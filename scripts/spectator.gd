class_name Spectator
extends Node
## Câmera de quem morreu (2026-10-05, pedido do usuário; primeira pessoa e morte em câmera
## lenta em 2026-10-21, ideia dele).
## Morte: por INTRO_TIME a câmera sai da cabeça, sobe e vira devagar para quem matou, com a
## tela fria nas bordas e o som desacelerado (só nesta máquina; o jogo segue na velocidade
## normal, por isso é uma imitação de câmera lenta: escolha dele). Depois corta para a
## primeira pessoa de quem matou; no 2x2, para a do parceiro. Clique ou escudo pula.
## Enquanto a rodada continua, três modos, como na maioria dos jogos de tiro:
## - 1a pessoa: pelos olhos de um jogador vivo, com a mira e a arma dele na tela (o corpo
##   dele some só desta câmera). A rede já manda para onde cada um olha; nada novo nela.
## - 3a pessoa: atrás e acima da cabeça, olhando para onde ele olha.
## - livre: voa sem colisão; mouse olha, WASD anda, pular sobe, agachar desce.
## Escudo (botão direito ou E) passa para o próximo modo; atirar (clique) passa para o próximo
## jogador (na câmera livre, volta a seguir). No 2x2 só segue o parceiro (era assim e ficou).
## Volta para a própria câmera ao fim da luta.

enum View { FIRST, THIRD, FREE }

const FOLLOW_BACK := 3.6
const FOLLOW_UP := 1.3
const FREE_SPEED := 12.0
## Camada de desenho do corpo de quem se assiste em 1a pessoa: a câmera do espectador não a
## desenha (cull_mask), as outras continuam vendo o corpo normalmente.
const HIDE_LAYER := 1 << 19
const ALL_LAYERS := 0xFFFFF
const REHIDE_EVERY := 0.5   # efeitos criados depois no corpo (estrelinhas, coroa) também somem
# Morte em câmera lenta (números propostos por mim em 2026-10-21; ajustar depois de jogar).
const INTRO_TIME := 1.2
const INTRO_RISE := 1.6       # metros que a câmera sobe
const INTRO_BACK := 1.2       # e recua, para longe de quem matou
const INTRO_SOUND := 0.55     # velocidade do som (AudioServer.playback_speed_scale)
const INTRO_FADE := 0.12      # escurece no fim e clareia depois do corte

var game: Node          # match.gd
var cam: Camera3D
var target: Player
var view := View.FIRST
var last_follow := View.FIRST   # 1a ou 3a pessoa: para onde o clique volta da câmera livre
var active := false
var _yaw := 0.0
var _pitch := 0.0
var _hidden := {}        # VisualInstance3D escondido -> camadas que ele tinha
var _rehide := 0.0
# Arma de primeira pessoa (cópia da do jogador assistido, presa nesta câmera).
var _vm: Node3D
var _vm_gun: Node3D
var _vm_skin := "?"
var _vm_bazooka: Node3D
var _vm_sniper: Node3D
var _vm_sword_pivot: Node3D
var _seen_tick := 0
var _kick := 0.0
var _bob := 0.0
# Morte em câmera lenta.
var intro := 0.0              # segundos que faltam (0: sem a cena)
var _intro_from: Transform3D
var _intro_to: Vector3
var _intro_killer: Player
var _intro_look: Vector3      # último ponto olhado (quem matou, ou onde morreu)
var _fade_in := 0.0           # clareando depois do corte


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = Player.BASE_FOV
	cam.near = 0.05
	add_child(cam)
	# A arma de primeira pessoa é montada aqui, no carregamento da partida (4,4 ms medidos
	# sem janela): na hora da morte seria uma engasgada a mais.
	_build_vm()
	_swap_gun(game.me.gun_skin)
	_vm.visible = false
	game.me.died.connect(_on_me_died)


func _exit_tree() -> void:
	AudioServer.playback_speed_scale = 1.0   # saiu da partida no meio da cena


func _process(delta: float) -> void:
	if intro > 0.0:
		_run_intro(delta)
		return
	if _fade_in > 0.0:
		_fade_in = maxf(0.0, _fade_in - delta)
		game.hud.set_death_fx(0.0, minf(1.0, _fade_in / INTRO_FADE))
	var me: Player = game.me
	var want: bool = me != null and not me.alive and not me.downed and game.phase == game.Phase.FIGHT and not GameState.autotest \
		and not _candidates().is_empty()
	if not want:
		if active:
			_stop()
		return
	if not active:
		_activate(null)
	if view != View.FREE and (target == null or not is_instance_valid(target) or not target.alive or not target in _candidates()):
		_follow(_next_target(0))
	match view:
		View.FIRST:
			_place_first(delta)
		View.THIRD:
			_place_follow(delta)
		View.FREE:
			_fly(delta)
	_update_hint()


## Começa a assistir p (null: o primeiro da lista) em primeira pessoa.
func _activate(p: Player) -> void:
	active = true
	cam.current = true
	game.hud.set_dead_view(true)
	last_follow = View.FIRST
	target = p if p and p in _candidates() else null
	if target:
		_show_tag(target, false)
	_set_view(View.FIRST)


func _stop() -> void:
	active = false
	_show_body()
	_show_tag(target, true)
	target = null
	if _vm:
		_vm.visible = false
	cam.cull_mask = ALL_LAYERS
	game.hud.spectate_aim = false
	game.hud.set_dead_view(false)
	game.hud.set_death_fx(0.0, 0.0)
	_fade_in = 0.0
	if game.me and is_instance_valid(game.me):
		game.me.camera.current = true
	game.hud.set_spectating("", "")


# ---------------------------------------------------------------- morte em câmera lenta

func _on_me_died(_p: Player) -> void:
	if GameState.autotest or not (game.phase in [game.Phase.FIGHT, game.Phase.ROUND_OVER]):
		return
	var me: Player = game.me
	if active:
		_stop()
	_intro_killer = null
	for p in game.players:
		if is_instance_valid(p) and p != me and String(p.name) == me.death_killer:
			_intro_killer = p
	_intro_from = me.camera.global_transform
	_intro_look = _intro_killer.chest() if _intro_killer else me.global_position
	# Sobe e recua para longe de quem matou (ou para trás de onde olhava); teto ou parede no
	# caminho: para um pouco antes.
	var away := _intro_from.origin - _intro_look
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else _intro_from.basis.z
	var want := _intro_from.origin + Vector3.UP * INTRO_RISE + away * INTRO_BACK
	var query := PhysicsRayQueryParameters3D.create(_intro_from.origin, want, 1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		want = hit["position"] + (_intro_from.origin - want).normalized() * 0.3
	_intro_to = want
	intro = INTRO_TIME
	cam.global_transform = _intro_from
	cam.cull_mask = ALL_LAYERS
	cam.current = true
	game.hud.set_dead_view(true)
	game.hud.spectate_aim = false
	var who := _intro_killer.player_name if _intro_killer else ""
	game.hud.set_spectating(tr("Killed by %s") % who if who != "" else tr("You died"),
		tr("[%s] skip") % GameState.key_text("shoot"))


func _run_intro(delta: float) -> void:
	var me: Player = game.me
	if me == null or me.alive or not (game.phase in [game.Phase.FIGHT, game.Phase.ROUND_OVER]):
		_end_intro(false)   # Fênix, rodada nova ou fim da partida
		return
	intro = maxf(0.0, intro - delta)
	var t := 1.0 - intro / INTRO_TIME
	var fx := minf(1.0, t / 0.15)
	AudioServer.playback_speed_scale = lerpf(1.0, INTRO_SOUND, fx)
	game.hud.set_death_fx(fx, clampf((INTRO_FADE - intro) / INTRO_FADE, 0.0, 1.0))
	if _intro_killer and is_instance_valid(_intro_killer) and _intro_killer.alive:
		_intro_look = _intro_killer.chest()
	var pos := _intro_from.origin.lerp(_intro_to, 1.0 - pow(1.0 - t, 3.0))
	var dir := (_intro_look - pos).normalized()
	var look := _intro_from.basis.orthonormalized()
	if dir.length() > 0.01:
		look = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK)
	var q := _intro_from.basis.get_rotation_quaternion().slerp(look.get_rotation_quaternion(), smoothstep(0.0, 0.7, t))
	cam.global_transform = Transform3D(Basis(q), pos)
	if intro <= 0.0:
		_end_intro(true)


## Fim da cena: o som volta e, se a rodada continua, corta para quem matou (no 2x2, para o
## parceiro; sem quem matou, para o vivo mais perto de onde morreu).
func _end_intro(cut: bool) -> void:
	intro = 0.0
	AudioServer.playback_speed_scale = 1.0
	game.hud.set_death_fx(0.0, 0.0)
	game.hud.set_spectating("", "")
	var me: Player = game.me
	var list := _candidates()
	if not cut or game.phase != game.Phase.FIGHT or list.is_empty() or me.alive or me.downed:
		_stop()
		return
	var next: Player = _intro_killer if _intro_killer in list else null
	if next == null:
		var best := INF
		for p: Player in list:
			var d := p.global_position.distance_squared_to(me.global_position)
			if d < best:
				best = d
				next = p
	_fade_in = INTRO_FADE * 1.6
	game.hud.set_death_fx(0.0, 1.0)
	_activate(next)


## Quem dá para assistir: os vivos (no 2x2, só os do seu time).
func _candidates() -> Array:
	var me: Player = game.me
	return game.players.filter(func(p): return is_instance_valid(p) and p != me and p.alive \
		and (not game.teams_on or me.is_ally(p)))


func _next_target(step: int) -> Player:
	var list := _candidates()
	if list.is_empty():
		return null
	var i := list.find(target)
	return list[(i + step) % list.size()] if i >= 0 else list[0]


## O nome e o anel do chão de quem está sendo seguido ficam escondidos: estariam bem no
## meio e embaixo da tela. (Por transparência e escala: o Player liga e desliga os dois.)
func _show_tag(p: Player, on: bool) -> void:
	if p and is_instance_valid(p) and p.tag:
		p.tag.modulate.a = 1.0 if on else 0.0
		p.tag.outline_modulate.a = 1.0 if on else 0.0
		if p.ring:
			p.ring.scale = Vector3.ONE if on else Vector3.ZERO


func _follow(p: Player) -> void:
	_show_tag(target, true)
	_show_body()
	target = p
	_show_tag(p, false)
	_seen_tick = p.attack_tick if p else 0
	_kick = 0.0
	if p == null:
		return
	if view == View.FIRST:
		_hide_body(p)
		cam.global_transform = _eye(p)
	else:
		cam.global_position = _follow_spot(p)


func _set_view(v: View) -> void:
	view = v
	if v != View.FREE:
		last_follow = v
	cam.cull_mask = ALL_LAYERS & ~HIDE_LAYER if v == View.FIRST else ALL_LAYERS
	if _vm:
		_vm.visible = v == View.FIRST
	game.hud.spectate_aim = v == View.FIRST
	if v == View.FREE:
		_show_body()
		_show_tag(target, true)
		var e := cam.global_transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y
	else:
		_follow(target if target and is_instance_valid(target) and target.alive else _next_target(0))


# ---------------------------------------------------------------- primeira pessoa

## Corpo, nome, anel e efeitos presos no jogador vão para HIDE_LAYER. Ficam de fora a luz do
## disparo (ilumina o cenário) e a bolha do escudo (vista de dentro, é o aviso do escudo).
func _hide_body(p: Player) -> void:
	_rehide = REHIDE_EVERY
	for v: VisualInstance3D in p.find_children("*", "VisualInstance3D", true, false):
		if v is Light3D or v == p.shield_mesh or _hidden.has(v):
			continue
		_hidden[v] = v.layers
		v.layers = HIDE_LAYER


func _show_body() -> void:
	for v in _hidden:
		if is_instance_valid(v):
			v.layers = _hidden[v]
	_hidden.clear()


## Olho do jogador: a cabeça na posição interpolada (sem tremer entre passos de física).
func _eye(p: Player) -> Transform3D:
	return p.head.get_global_transform_interpolated()


func _place_first(delta: float) -> void:
	if target == null:
		return
	_rehide -= delta
	if _rehide <= 0.0:
		_hide_body(target)
	_vm.visible = true
	var kind := _weapon_kind(target)
	if _vm_skin != target.gun_skin:
		_swap_gun(target.gun_skin)
	_vm_gun.visible = kind == 0
	_vm_bazooka.visible = kind == 1
	_vm_sniper.visible = kind == 2
	_vm_sword_pivot.visible = kind == 3
	if target.attack_tick != _seen_tick:
		_seen_tick = target.attack_tick
		if target.last_swing >= 0:
			Player.swing_sword(_vm_sword_pivot, target.last_swing)
		else:
			_kick = [1.0, 1.6, 2.5, 1.0][kind]
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	var eye := _eye(target)
	# A mira chega da rede a cada quadro de física; um pouco de suavização tira o tranco.
	var q := cam.global_transform.basis.get_rotation_quaternion().slerp(eye.basis.get_rotation_quaternion(),
		minf(1.0, delta * 30.0))
	var basis := Basis(q).rotated(Basis(q).x, _kick * Player.RECOIL_KICK)
	cam.global_transform = Transform3D(basis, eye.origin)
	var hspeed := Vector2(target.velocity.x, target.velocity.z).length()
	if absf(target.velocity.y) < 1.0 and hspeed > 1.0:
		_bob += delta * hspeed * 1.3
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.014, 0.0) * minf(hspeed / 9.0, 1.0)
	_vm.position = Player.VIEWMODEL_POS + bob + Vector3(0.0, 0.0, _kick * 0.07)
	_vm.rotation = Vector3(_kick * 0.25, 0.0, 0.0)


## Arma que o jogador tem na mão agora (a do corpo dele diz): 0 a de sempre, 1 Bazuca,
## 2 Sniper, 3 Espada.
func _weapon_kind(p: Player) -> int:
	if p.bazooka and p.bazooka.visible:
		return 1
	if p.sniper and p.sniper.visible:
		return 2
	if p.sword and p.sword.visible:
		return 3
	return 0


## As mesmas peças e posições da arma de primeira pessoa do Player (_build_viewmodel).
func _build_vm() -> void:
	var me: Player = game.me
	_vm = Node3D.new()
	cam.add_child(_vm)
	_vm_bazooka = me._make_bazooka()
	me._no_shadows(_vm_bazooka)
	_vm_bazooka.scale = Vector3.ONE * 0.6
	_vm_bazooka.position = Vector3(0.06, -0.02, 0.0)
	_vm.add_child(_vm_bazooka)
	_vm_sniper = load(Player.SNIPER_MODEL).instantiate()
	me._no_shadows(_vm_sniper)
	_vm_sniper.scale = Vector3.ONE * Player.SNIPER_VIEW_SCALE
	_vm_sniper.rotation.y = 0.06
	_vm_sniper.position = Player.SNIPER_VIEW_POS
	_vm.add_child(_vm_sniper)
	_vm_sword_pivot = Node3D.new()
	_vm.add_child(_vm_sword_pivot)
	var sword := me._make_sword()
	me._no_shadows(sword)
	sword.scale = Vector3.ONE * 0.55
	_vm_sword_pivot.add_child(sword)
	Player.rest_sword_pose(_vm_sword_pivot)


func _swap_gun(skin: String) -> void:
	var me: Player = game.me
	if _vm_gun:
		_vm_gun.queue_free()
	_vm_skin = skin
	_vm_gun = load(Player.gun_model(skin)).instantiate()
	me._no_shadows(_vm_gun)
	_vm_gun.scale = Vector3.ONE * Player.VIEWMODEL_SCALE
	_vm_gun.rotation.y = 0.06
	_vm.add_child(_vm_gun)


# ---------------------------------------------------------------- terceira pessoa e livre

func _follow_spot(p: Player) -> Vector3:
	var head: Transform3D = p.head.global_transform
	var eye := head.origin
	var want := eye + head.basis.z * FOLLOW_BACK + Vector3.UP * FOLLOW_UP
	# Parede atrás: a câmera chega mais perto em vez de atravessar.
	var query := PhysicsRayQueryParameters3D.create(eye, want, 1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		want = hit["position"] + (eye - want).normalized() * 0.3
	return want


func _place_follow(delta: float) -> void:
	if target == null:
		return
	var head: Transform3D = target.head.global_transform
	cam.global_position = cam.global_position.lerp(_follow_spot(target), minf(1.0, delta * 12.0))
	cam.look_at(head.origin - head.basis.z * 12.0)


func _fly(delta: float) -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	if GameState.menu_open or GameState.chat_open:
		return
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var basis := cam.global_transform.basis
	var dir := basis.x * move.x - basis.z * move.y
	if Input.is_action_pressed("jump"):
		dir += Vector3.UP
	if Input.is_action_pressed("crouch"):
		dir += Vector3.DOWN
	cam.global_position += dir.limit_length(1.0) * FREE_SPEED * delta


func _unhandled_input(event: InputEvent) -> void:
	if GameState.menu_open or GameState.chat_open:
		return
	if intro > 0.0:
		# Os primeiros 0,3 s não pulam: o clique de quem estava atirando ao morrer não conta.
		if intro < INTRO_TIME - 0.3 and (event.is_action_pressed("shoot") or event.is_action_pressed("shield")) \
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			get_viewport().set_input_as_handled()
			_end_intro(true)   # pular a cena
		return
	if not active:
		return
	var motion := event as InputEventMouseMotion
	if motion and view == View.FREE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameState.mouse_sens
		_yaw = wrapf(_yaw - motion.relative.x * sens, -PI, PI)
		_pitch = clampf(_pitch - motion.relative.y * sens, -1.5, 1.5)
		return
	if event.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		get_viewport().set_input_as_handled()
		if view == View.FREE:
			_set_view(last_follow)
		else:
			_follow(_next_target(1))
	elif event.is_action_pressed("shield"):
		get_viewport().set_input_as_handled()
		_set_view(((view + 1) % 3) as View)


func _update_hint() -> void:
	var swap := tr("[%s] switch camera") % GameState.key_text("shield")
	if view == View.FREE:
		game.hud.set_spectating(tr("Free camera"),
			tr("[%s] follow a player   ·   %s   ·   [%s] up   [%s] down") % [
			GameState.key_text("shoot"), swap, GameState.key_text("jump"), GameState.key_text("crouch")], view)
	elif target:
		var more := _candidates().size() > 1
		game.hud.set_spectating(tr("Watching %s   ·   %d health") % [target.player_name, ceili(target.health)],
			(tr("[%s] next player   ·   ") % GameState.key_text("shoot") if more else "") + swap, view)
