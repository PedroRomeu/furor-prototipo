class_name Spectator
extends Node
## Câmera de quem morreu enquanto a rodada continua (2026-10-05, pedido do usuário).
## Dois modos, como na maioria dos jogos de tiro:
## - seguir: atrás e acima da cabeça de um jogador vivo, olhando para onde ele olha. Atirar
##   (clique) passa para o próximo. No 2x2 só segue o parceiro (era assim e ficou).
## - câmera livre: voa sem colisão; mouse olha, WASD anda, pular sobe, agachar desce.
##   Clique volta a seguir.
## Escudo (botão direito ou E) troca entre os dois. Volta para a própria câmera ao fim da luta.

const FOLLOW_BACK := 3.6
const FOLLOW_UP := 1.3
const FREE_SPEED := 12.0

var game: Node          # match.gd
var cam: Camera3D
var target: Player
var free := false
var active := false
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = Player.BASE_FOV
	cam.near = 0.05
	add_child(cam)


func _process(delta: float) -> void:
	var me: Player = game.me
	var want: bool = me != null and not me.alive and not me.downed and game.phase == game.Phase.FIGHT and not GameState.autotest \
		and not _candidates().is_empty()
	if not want:
		if active:
			_stop()
		return
	if not active:
		active = true
		free = false
		target = null
		cam.global_transform = me.camera.global_transform
		cam.current = true
		game.hud.set_dead_view(true)
	if not free and (target == null or not target.alive or not target in _candidates()):
		_follow(_next_target(0))
	if free:
		_fly(delta)
	else:
		_place_follow(delta)
	_update_hint()


func _stop() -> void:
	active = false
	_show_tag(target, true)
	target = null
	free = false
	game.hud.set_dead_view(false)
	if game.me and is_instance_valid(game.me):
		game.me.camera.current = true
	game.hud.set_spectating("", "")


## Quem dá para assistir: os vivos (no 2x2, só os do seu time).
func _candidates() -> Array:
	var me: Player = game.me
	return game.players.filter(func(p): return p != me and p.alive and (not game.teams_on or me.is_ally(p)))


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
	target = p
	free = false
	_show_tag(p, false)
	if p:
		cam.global_position = _follow_spot(p)


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


func _go_free() -> void:
	free = true
	_show_tag(target, true)
	var e := cam.global_transform.basis.get_euler()
	_pitch = e.x
	_yaw = e.y


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
	if not active or GameState.menu_open or GameState.chat_open:
		return
	var motion := event as InputEventMouseMotion
	if motion and free and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameState.mouse_sens
		_yaw = wrapf(_yaw - motion.relative.x * sens, -PI, PI)
		_pitch = clampf(_pitch - motion.relative.y * sens, -1.5, 1.5)
		return
	if event.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		get_viewport().set_input_as_handled()
		if free:
			_follow(_next_target(0))
		else:
			_follow(_next_target(1))
	elif event.is_action_pressed("shield"):
		get_viewport().set_input_as_handled()
		if free:
			_follow(_next_target(0))
		else:
			_go_free()


func _update_hint() -> void:
	var swap := GameState.key_text("shield")
	if free:
		game.hud.set_spectating("Câmera livre",
			"[%s] seguir um jogador   ·   [%s] subir   [%s] descer" % [
			GameState.key_text("shoot"), GameState.key_text("jump"), GameState.key_text("crouch")])
	elif target:
		var more := _candidates().size() > 1
		game.hud.set_spectating("Assistindo %s" % target.player_name,
			("[%s] próximo   ·   " % GameState.key_text("shoot") if more else "") + "[%s] câmera livre" % swap)
