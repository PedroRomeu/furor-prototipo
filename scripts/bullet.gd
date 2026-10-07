class_name Bullet
extends Node3D
## Projétil. A cada quadro testa o trecho que vai percorrer: um raio contra o cenário
## e uma conta de distância contra a cápsula de cada jogador (assim o tamanho da bala
## conta). Se acerta alguém com escudo, muda de dono e volta para quem atirou.
## Os efeitos (veneno, explosão etc.) são copiados de quem atirou no momento do tiro.
##
## A bala cai com a gravidade (bullet_gravity): de perto vai reto, de longe é preciso
## mirar um pouco acima, como no ROUNDS. Deixa um rastro para dar para ver de onde veio.
##
## Em rede, cada máquina simula todas as balas, mas só decide acerto contra o jogador
## que ela mesma controla. Ao encostar no jogador remoto, a bala espera um instante
## (escondida) pela resposta da outra máquina: refletiu, acertou ou passou.

const LIFETIME := 4.0
## Cada quique dá mais BOUNCE_LIFE de vida (2026-10-07, para a "nuke" do Furor: atirar para o
## céu e esperar quicar). Sem teto de tempo: o teto de quiques (LIMITS) já limita.
const BOUNCE_LIFE := 2.0
const REFLECTED_COLOR := Color(0.6, 1.0, 1.0)
const CRIT_COLOR := Color(1.0, 0.85, 0.2)
const PIERCE_COLOR := Color(0.85, 0.5, 1.0)
const EXPLOSION_DAMAGE := 0.6
## A explosão começa na borda da bala: raio das cartas + EXPLOSION_SIZE_GAIN x o raio da bala
## (2026-10-07; a bala base soma 0,2 m, a Bala Gigante 0,7, uma nuke de 9 m uns 14).
const EXPLOSION_SIZE_GAIN := 1.5
const EXPLOSION_MIN := 0.5
const TRAIL_MAX_WIDTH := 1.5   # rastro de bala gigante: faixa translúcida enorme pesa na placa
const SPLIT_ANGLE := 10.0
## Teto invisível (2026-10-07, como no Furor): a CEILING_Y a bala quica como numa parede
## (gasta um quique, soma na Tabelinha, depois pode acertar quem atirou) e desce. Sem
## quiques sobrando, some lá em cima. No teto não há explosão, nuvem, buraco nem marca de
## meteoro (ninguém está lá, e o meteoro cairia em quem atirou). Perfurante, Sniper, caco de
## gelo e foguete solto passam. O muro mais alto tem 18 m e jogador nenhum chega a 30.
const CEILING_Y := 30.0
const MAX_BULLETS := 300   # teto de segurança para combinações extremas de cartas
const REMOTE_WAIT := 0.3
const TRAIL_POINTS := 6
const BOOMERANG_TIME := 0.5
const STICKY_FUSE := 0.6
const STICKY_RADIUS := 3.5
const LAZY_START := 0.35   # Bala Preguiçosa: sai com 35% da velocidade...
const LAZY_TOP := 2.5      # ...e acelera até 2,5x
const LAZY_ACCEL := 2.2
const SHARD_DAMAGE := 0.4
const MAX_GROW_RADIUS := 1.2
## Bola de Neve: o dano cresce em linha reta até GROW_TIME (por carta, +grow de dano no fim).
## Antes crescia em juros compostos e, com 3 cópias, chegava a centenas de vezes o dano.
const GROW_TIME := 2.0
## Teleguiada (refeita em 2026-10-04 como a Seeker do OVERKILL e a do Furor; faixa refeita
## em 2026-10-07): nem toda bala procura alvo, e a que procura só curva quando um inimigo
## passa perto dela, mas aí curva forte, para dar para ver (e fica verde, SEEK_COLOR).
## As cópias (n) aumentam sobretudo a chance, com retorno decrescente e teto de 70%: nunca
## é toda bala. Simulação (balas que passariam a 0,65-2 m do alvo): viram acerto
## 9/19/27/42/61% com n = 1/2/3/5/10. Antes do ajuste de 2026-10-07 (raio 4, curva 4,5 com
## 1 cópia) eram 15/25/37/53/61%: forte demais no começo da partida, achou o usuário.
## Fórmula de cada termo: MIN + GAIN x (n - 1) / (n + K).
const SEEK_CHANCE_MIN := 0.35
const SEEK_CHANCE_GAIN := 0.35
const SEEK_CHANCE_K := 2.0
const SEEK_RADIUS_MIN := 3.5   # era 4 (e curva 4,5) até 2026-10-07: forte com 1 cópia
const SEEK_RADIUS_GAIN := 2.5
const SEEK_RADIUS_K := 3.0
const SEEK_TURN_MIN := 4.0
const SEEK_TURN_GAIN := 2.0
const SEEK_TURN_K := 3.0
const SEEK_COLOR := Color(0.1, 1.0, 0.25)   # saturado: o brilho (x2,2) deixa cor clara branca
## Quique Certeiro (refeito em 2026-10-04: antes virava a bala direto para o inimigo em todo
## quique, uma mira automática). Junta com a Teleguiada: n = 1 (a carta) + cópias de
## Teleguiada. No quique a bala vira para o inimigo só até um ângulo, que cresce com
## n / (n + k): n=1 19 graus, n=2 29, n=4 38, n=10 48. Depois do quique ela vira uma bala
## teleguiada de força n (raio e curva de SEEK_*), mesmo que não tenha ganhado o sorteio.
const BOUNCE_AIM_MAX := 1.0   # radianos
const BOUNCE_AIM_K := 2.0
## O tamanho acompanha o dano, de leve (como no Furor): dano dobrado = bala 41% maior.
## Vale no disparo (crítico e Última Bala saem maiores) e durante o voo (Bola de Neve,
## Tabelinha, reflexo): uma bala que junta muito dano fica enorme. Cartas de tamanho somam.
const DAMAGE_SIZE_EXP := 0.5
const DAMAGE_SIZE_MIN := 0.7   # chumbo de escopeta não some de tão pequeno
const GUIDED_TURN := 5.0       # Piloto: quanto a bala vira por segundo atrás da mira (rad/s)
const GUIDED_LEAD := 4.0       # ...mirando este tanto à frente da bala, na linha da mira
const FIELDS := ["damage", "radius", "bounces", "homing", "ghost", "explosion", "poison",
	"slow", "push", "shield_break", "target_bounce", "execute", "reflected", "gravity",
	"boomerang", "returning", "bounce_damage", "sticky", "split", "grow", "swap", "blind",
	"lazy_top", "seek", "crit", "bounced", "guided", "pierce", "bounce_hits", "grow_mult", "ghost_walls",
	"toxic", "hole", "laser", "ice", "meteor", "rocket", "blast_radius", "blast_damage", "life"]
## Bala Fantasma: só paredes contam (superfície quase em pé); no chão e no topo das peças a
## bala para ou quica como as outras.
const GHOST_WALL_NORMAL_Y := 0.7

static var _counter := 0
## Desempenho (2026-10-05): malha e materiais são compartilhados (um material por cor), os
## rastros de todas as balas saem numa malha só (TrailBatch) e a lista de jogadores é
## buscada uma vez por quadro de física, não três vezes por bala.
static var _mesh: SphereMesh
static var _materials := {}
static var _trail_mat: StandardMaterial3D
static var _players: Array = []
static var _barriers: Array = []
static var _cache_frame := -1

var id := ""
var shooter: Player
var velocity := Vector3.ZERO
var damage := 25.0
var radius := 0.1
var bounces := 0
var homing := 0.0      # curva fixa atrás do inimigo mais próximo (Espelho Perseguidor)
var seek := 0.0        # Teleguiada: cópias da carta, se esta bala ganhou o sorteio
var seek_locked := false   # já curvou atrás de alguém (mudou de cor)
var ghost := false      # atravessa todo o cenário (Perfurante)
## Bala Fantasma (refeita em 2026-10-05, ideia do usuário, como no Furor): cada bala
## atravessa as primeiras paredes em que bater, uma por cópia da carta.
var ghost_walls := 0
var _passed: Array[RID] = []   # paredes já atravessadas: o raio passa a ignorá-las
var explosion := 0.0
var blast_radius := 0.0   # Pólvora / Carga Concentrada: soma ao raio da explosão (só com explosão)
var blast_damage := 0.0   # ...e ao dano dela (+0,3 = +30%)
var life := LIFETIME      # cresce BOUNCE_LIFE a cada quique
var poison := 0.0
var slow := 0.0
var push := 0.0
var shield_break := false
var target_bounce := 0.0   # Quique Certeiro: força n (0 = sem a carta)
var execute := 0.0
var reflected := false
var gravity := 0.0
var boomerang := false
var returning := false
var bounce_damage := 0.0
var bounce_hits := 0     # Tabelinha: quiques já dados (o bônus soma, não multiplica)
var grow_mult := 1.0     # Bola de Neve: quanto do dano já veio do crescimento
var sticky := false
var split := 0
var grow := 0.0
var swap := false
var blind := 0.0
var laser := false   # tiro da Sniper: deixa um feixe reto ao nascer (em todas as máquinas)
var ice := false     # caco da Prisão de Gelo: congela em vez de ferir; some a ICE_RANGE
var meteor := false  # Chuva de Meteoros: onde bater marca o chão (uma vez só)
var rocket := false  # Foguete solto: explode (Player.rocket_blast) no contato ou no tempo
var toxic := 0   # Nuvem Tóxica: cópias (AreaField)
var hole := 0    # Buraco Negro: cópias (AreaField)
var lazy_top := 0.0
var crit := false
var bounced := false   # já quicou numa parede: pode acertar quem atirou (como no Furor)
var guided := false    # Piloto (mestra guardada): segue a mira de quem atirou
var pierce := false    # Perfurante: só muda a cor e o formato (o resto vem por ghost/gravity)
var sound := false
var age := 0.0
var waiting := 0.0
var fuse := 0.0
var ignore_remote_until := 0.0
var color := Color.WHITE   # cor de base (o rastro usa esta; o núcleo, ela mais brilhante)
var core: MeshInstance3D
var trail_points: Array = []


## overrides: campos para trocar depois de copiar os atributos de quem atirou
## (as bombas do escudo, por exemplo). "speed" troca a velocidade.
static func fire(from: Player, pos: Vector3, dir: Vector3, damage_mult := 1.0, with_sound := false,
		overrides := {}) -> Bullet:
	if from.get_tree().get_node_count_in_group("bullets") >= MAX_BULLETS:
		return null
	var b := Bullet.new()
	var s := from.stats
	b.shooter = from
	b.damage = from.shot_damage() * damage_mult
	var size := pow(b.damage / float(Player.BASE_STATS["damage"]), DAMAGE_SIZE_EXP)
	b.radius = s["bullet_radius"] * maxf(size, DAMAGE_SIZE_MIN)
	b.bounces = s["bounces"]
	b.ghost_walls = s["ghost"]
	# Teleguiada: cada bala sorteia se procura alvo; o raio e a curva vêm do número de cópias.
	var seekers := float(s["homing"])
	if seekers > 0.0 and randf() < _seek_term(seekers, SEEK_CHANCE_MIN, SEEK_CHANCE_GAIN, SEEK_CHANCE_K):
		b.seek = seekers
	b.explosion = s["explosion"]
	b.blast_radius = s["blast_radius"]
	b.blast_damage = s["blast_damage"]
	b.poison = s["poison"]
	b.slow = s["slow"]
	b.push = s["knockback"]
	b.shield_break = s["shield_break"] > 0
	b.target_bounce = float(s["target_bounce"] + s["homing"]) if s["target_bounce"] > 0 else 0.0
	b.execute = s["execute"]
	b.gravity = s["bullet_gravity"]
	b.boomerang = s["boomerang"] > 0
	b.bounce_damage = s["bounce_damage"]
	b.sticky = s["sticky"] > 0
	b.split = s["split"]
	b.grow = s["grow"]
	b.swap = s["swap"] > 0
	b.blind = s["blind"]
	b.toxic = s["toxic"]
	b.hole = s["black_hole"]
	b.guided = s["guided"] > 0
	if b.guided:
		b.gravity = 0.0
	var speed := float(s["bullet_speed"])
	if s["lazy"] > 0:
		b.lazy_top = speed * LAZY_TOP
		speed *= LAZY_START
	for key in overrides:
		if key == "speed":
			speed = overrides[key]
			b.lazy_top = 0.0
		else:
			b.set(key, overrides[key])
	b.velocity = dir * speed
	b.sound = with_sound
	b._launch(from.get_parent(), pos)
	if b.laser:
		b._laser_beam()
	return b


## Recria na outra máquina uma bala que nasceu lá (ver match.gd: net_spawn_bullet).
static func from_data(parent: Node, data: Dictionary) -> void:
	var owner_player := parent.get_node_or_null(String(data["owner"])) as Player
	if owner_player == null:
		return
	var b := Bullet.new()
	b.id = data["id"]
	b.shooter = owner_player
	b.velocity = data["vel"]
	b.sound = data["sound"]
	for f in FIELDS:
		b.set(f, data[f])
	parent.add_child(b)
	b.global_position = data["pos"]
	b.reset_physics_interpolation()
	b._orient()
	if b.laser:
		b._laser_beam()
	owner_player.reveal()


func to_data() -> Dictionary:
	var data := {"id": id, "owner": String(shooter.name), "pos": global_position, "vel": velocity, "sound": sound}
	for f in FIELDS:
		data[f] = get(f)
	return data


## Coloca a bala no mundo e, em rede, avisa a outra máquina.
func _launch(parent: Node, pos: Vector3) -> void:
	_counter += 1
	id = "%s_%d" % [shooter.name, _counter]
	parent.add_child(self)
	global_position = pos
	reset_physics_interpolation()
	_orient()
	if Net.online:
		parent.net_spawn_bullet.rpc(to_data())


## Cópia desta bala noutra direção (Espelho Duplo, estilhaços). overrides como em fire().
func _clone(dir: Vector3, overrides := {}) -> void:
	if get_tree().get_node_count_in_group("bullets") >= MAX_BULLETS:
		return
	var b := Bullet.new()
	b.shooter = shooter
	for f in FIELDS:
		b.set(f, get(f))
	b._passed = _passed.duplicate()
	b.grow = 0.0   # a cópia nasce com idade 0: fica do tamanho atual em vez de recomeçar a conta
	for key in overrides:
		b.set(key, overrides[key])
	b.velocity = dir * velocity.length()
	b._launch(get_parent(), global_position)


func _ready() -> void:
	add_to_group("bullets")
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 10
		_mesh.rings = 5
	core = MeshInstance3D.new()
	core.mesh = _mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	_resize_core()
	# Rastro: desenhado junto com o das outras balas pelo TrailBatch do mesmo nó pai.
	if not get_parent().has_node(TrailBatch.NODE_NAME):
		get_parent().add_child(TrailBatch.new())

	var c := shooter.color.lightened(0.45)
	if pierce:
		c = PIERCE_COLOR
	if crit:
		c = CRIT_COLOR
	if reflected:
		c = REFLECTED_COLOR
	if ice:
		c = Player.ICE_COLOR
	if meteor:
		c = MeteorStrike.COLOR
	if rocket:
		c = Player.ROCKET_COLOR
	_set_color(c)
	if sound:
		Sfx.at(get_parent(), "shot", global_position)


## Muda o dano e o tamanho junto (DAMAGE_SIZE_EXP).
func _scale_damage(k: float) -> void:
	damage *= k
	radius *= pow(k, DAMAGE_SIZE_EXP)
	if core:
		_resize_core()


func _resize_core() -> void:
	var w := maxf(0.09, radius)
	core.scale = Vector3(w, w, w * (6.0 if pierce else 2.4))


## Cor acima de 1 faz a bala brilhar com o glow do ambiente.
func _set_color(c: Color) -> void:
	color = c
	_set_core(Color(c.r * 2.2, c.g * 2.2, c.b * 2.2))


func _set_core(albedo: Color) -> void:
	if not _materials.has(albedo):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = albedo
		_materials[albedo] = mat
	core.material_override = _materials[albedo]


## Solta as malhas e materiais compartilhados (fim da partida).
static func clear_cache() -> void:
	_mesh = null
	_materials.clear()
	_trail_mat = null
	_players.clear()
	_barriers.clear()
	_cache_frame = -1


static func trail_material() -> StandardMaterial3D:
	if _trail_mat == null:
		_trail_mat = StandardMaterial3D.new()
		_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_mat.vertex_color_use_as_albedo = true
		_trail_mat.albedo_color = Color(1.6, 1.6, 1.6)
	return _trail_mat


## Jogadores e paredes do Bastião, buscados uma vez por quadro de física para todas as balas.
func _refresh_cache() -> void:
	var frame := Engine.get_physics_frames()
	if frame != _cache_frame:
		_cache_frame = frame
		_players = get_tree().get_nodes_in_group("players")
		_barriers = get_tree().get_nodes_in_group("barriers")


func _orient() -> void:
	if velocity.is_zero_approx():
		return
	var dir := velocity.normalized()
	var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(global_position + dir, up)


func _physics_process(delta: float) -> void:
	age += delta
	if rocket and age > Player.ROCKET_FREE_TIME:
		Player.rocket_blast(get_parent(), global_position, shooter)
		queue_free()
		return
	if age > life or (ice and age * velocity.length() > Player.ICE_RANGE):
		queue_free()
		return
	if fuse > 0.0:
		fuse -= delta
		if fuse <= 0.0:
			_explode(global_position, null)
			queue_free()
		return
	if waiting > 0.0:
		waiting -= delta
		if waiting <= 0.0:
			visible = true   # a outra máquina não respondeu: a bala passou direto
		return
	_refresh_cache()
	_update_flight(delta)
	var from := global_position
	var to := from + velocity * delta
	var world_hit := {}
	if not ghost:
		world_hit = _world_ray(from, to)
		while not world_hit.is_empty() and ghost_walls > 0 and absf(world_hit["normal"].y) < GHOST_WALL_NORMAL_Y:
			ghost_walls -= 1
			_passed.append(world_hit["rid"])
			Effects.burst(get_parent(), world_hit["position"], maxf(0.35, radius * 2.5), Color(0.75, 0.6, 1.0), 0.15)
			world_hit = _world_ray(from, to)
		if not ice and not rocket:
			var ceiling := _ceiling_hit(from, to)
			if not ceiling.is_empty() and (world_hit.is_empty()
					or from.distance_to(world_hit["position"]) > from.distance_to(ceiling["position"])):
				world_hit = ceiling
	var end: Vector3 = to if world_hit.is_empty() else world_hit["position"]
	if _check_barriers(from, end):
		_remember_point(from)
		return
	var target := _player_on_segment(from, end)
	if not target.is_empty():
		_hit_player(target["player"], target["point"])
	elif not world_hit.is_empty():
		_hit_world(world_hit)
	else:
		global_position = to
		_orient()
	_remember_point(from)


## Cruzou o teto invisível neste passo (a borda da bala, para a bala gigante da nuke)?
func _ceiling_hit(from: Vector3, to: Vector3) -> Dictionary:
	var top := CEILING_Y - radius
	if velocity.y <= 0.0 or to.y < top:
		return {}
	var t := clampf((top - from.y) / maxf(to.y - from.y, 0.0001), 0.0, 1.0)
	return {"position": from.lerp(to, t), "normal": Vector3.DOWN, "ceiling": true}


func _world_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, _passed)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _remember_point(p: Vector3) -> void:
	trail_points.append(p)
	if trail_points.size() > TRAIL_POINTS:
		trail_points.pop_front()


## Muda a velocidade em voo: gravidade, aceleração, crescimento, bumerangue, teleguiada.
func _update_flight(delta: float) -> void:
	if lazy_top > 0.0:
		var speed := velocity.length()
		if speed < lazy_top and speed > 0.01:
			velocity *= minf(1.0 + LAZY_ACCEL * delta, lazy_top / speed)
	if grow > 0.0 and age <= GROW_TIME + delta:
		# O crescimento próprio da carta tem teto; o que vem do dano, não.
		radius = minf(radius * (1.0 + grow * 0.25 * delta), maxf(radius, MAX_GROW_RADIUS))
		var target := 1.0 + grow * minf(age, GROW_TIME) / GROW_TIME
		_scale_damage(target / grow_mult)
		grow_mult = target
	if boomerang and not returning and not reflected and age > BOOMERANG_TIME:
		returning = true
		velocity = -velocity
	if returning:
		if not is_instance_valid(shooter) or not shooter.alive:
			returning = false
		elif shooter.chest().distance_to(global_position) < 1.3:
			queue_free()
			return
		else:
			_steer_to(shooter.chest(), 6.0, delta)
			return
	if guided and not reflected and is_instance_valid(shooter) and shooter.alive:
		# Piloto: vira para um ponto na linha da mira, um pouco à frente de onde a bala está.
		var eye: Transform3D = shooter.head.global_transform
		var along := eye.origin.distance_to(global_position) + GUIDED_LEAD
		_steer_to(eye.origin - eye.basis.z * along, GUIDED_TURN, delta)
	if gravity > 0.0:
		velocity.y -= gravity * delta
	if homing > 0.0:
		var enemy := _enemy()
		if enemy:
			_steer_to(enemy.chest(), homing, delta)
	elif seek > 0.0:
		var enemy := _enemy()
		var reach := _seek_term(seek, SEEK_RADIUS_MIN, SEEK_RADIUS_GAIN, SEEK_RADIUS_K)
		if enemy and enemy.chest().distance_to(global_position) < reach:
			if not seek_locked:
				seek_locked = true   # travou: fica verde (rastro junto) para o efeito ser visto
				if not crit and not reflected:
					_set_color(SEEK_COLOR)
			_steer_to(enemy.chest(), _seek_term(seek, SEEK_TURN_MIN, SEEK_TURN_GAIN, SEEK_TURN_K), delta)


## Termo da Teleguiada com n cópias: MIN com 1 cópia, tendendo a MIN + GAIN.
static func _seek_term(n: float, base: float, gain: float, k: float) -> float:
	return base + gain * maxf(0.0, n - 1.0) / (n + k)


## Parede do Bastião no caminho: devolve a bala de quem não é o dono dela. Quem decide é a
## máquina do dono da parede; as outras escondem a bala e esperam a resposta.
func _check_barriers(from: Vector3, end: Vector3) -> bool:
	for node in _barriers:
		if not is_instance_valid(node):
			continue
		var wall := node as Barrier
		var owner_player := wall.owner_player
		if not is_instance_valid(owner_player) or owner_player == shooter or not owner_player.alive \
				or (is_instance_valid(shooter) and shooter.is_ally(owner_player)):
			continue
		if age < ignore_remote_until and not owner_player.is_local:
			continue
		var hit = wall.crossing(from, end)
		if hit == null:
			continue
		if owner_player.is_local:
			_reflect(owner_player, hit)
			wall.flash()
		else:
			waiting = REMOTE_WAIT
			ignore_remote_until = age + REMOTE_WAIT + 0.25
			visible = false
			global_position = hit
		return true
	return false


## Jogador mais próximo cuja cápsula (mais o raio da bala) cruza o trecho from-end.
func _player_on_segment(from: Vector3, end: Vector3) -> Dictionary:
	var best := {}
	var best_dist := INF
	var mid := (from + end) * 0.5
	var half := from.distance_to(end) * 0.5
	for node in _players:
		if not is_instance_valid(node):
			continue
		var p := node as Player
		if not p.alive or (p == shooter and (not bounced or returning)):
			continue
		# Descarte rápido: longe demais do trecho para a cápsula (ou o escudo) alcançar.
		var body: float = p.height * 0.5 * float(p.stats["body_scale"])
		var center := p.global_position + Vector3(0.0, body, 0.0)
		if center.distance_to(mid) > half + body + p.hit_radius() + radius:
			continue
		if is_instance_valid(shooter) and shooter.is_ally(p) and p.hooked_by == null:
			continue   # 2x2: a bala atravessa o parceiro (menos preso no Gancho: escudo humano)
		if not p.is_local and age < ignore_remote_until:
			continue
		if p.is_local and p.is_dodging():
			continue   # Esquiva: no dash a bala atravessa (quem decide é a máquina do alvo)
		var seg := p.hit_segment()
		var pts := Geometry3D.get_closest_points_between_segments(from, end, seg[0], seg[1])
		if pts[0].distance_to(pts[1]) > p.hit_radius() + radius:
			continue
		var d := from.distance_to(pts[0])
		if d < best_dist:
			best_dist = d
			best = {"player": p, "point": pts[0]}
	return best


## Inimigo vivo mais próximo da bala (alvo da teleguiada e do Quique Certeiro).
func _enemy() -> Player:
	var best: Player = null
	var best_dist := INF
	for node in _players:
		if not is_instance_valid(node) or node == shooter or not node.alive or (is_instance_valid(shooter) and shooter.is_ally(node)):
			continue
		var d: float = node.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


func _steer_to(point: Vector3, rate: float, delta: float) -> void:
	var dir := velocity.normalized()
	var want := (point - global_position).normalized()
	var angle := dir.angle_to(want)
	if angle > 0.001:
		dir = dir.slerp(want, minf(1.0, rate * delta / angle))
		velocity = dir * velocity.length()


func _hit_world(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if rocket:
		Player.rocket_blast(get_parent(), point + normal * 0.3, shooter)
		queue_free()
		return
	if hit.get("ceiling", false):
		if bounces <= 0:
			queue_free()
			return
		Effects.burst(get_parent(), point, 0.35, Color(color.r * 2.2, color.g * 2.2, color.b * 2.2), 0.12)
		_bounce(point, normal)
		return
	if normal.is_zero_approx():
		normal = -velocity.normalized()   # o raio começou dentro de uma parede
	_impact_fields(point, normal)
	if bounces <= 0 and sticky:
		# Detonação: gruda e explode depois (todas as máquinas fazem o mesmo).
		global_position = point + normal * 0.05
		velocity = Vector3.ZERO
		explosion = maxf(explosion, STICKY_RADIUS)
		fuse = STICKY_FUSE
		_set_core(Color(3.0, 0.6, 0.3))
		return
	if explosion > 0.0:
		_explode(point, null)
	else:
		Effects.burst(get_parent(), point, 0.35, Color(color.r * 2.2, color.g * 2.2, color.b * 2.2), 0.12)
	if bounces <= 0:
		if split > 0 and is_instance_valid(shooter) and shooter.is_local:
			_shatter(point, normal)
		queue_free()
		return
	_bounce(point, normal)


## Quique (parede, chão ou teto invisível): gasta um, ganha vida e Tabelinha, Quique Certeiro.
func _bounce(point: Vector3, normal: Vector3) -> void:
	bounces -= 1
	bounced = true
	life += BOUNCE_LIFE
	if bounce_damage > 0.0:
		# +bounce_damage do dano de saída a cada quique, somando (3 quiques com +40% = +120%).
		bounce_hits += 1
		_scale_damage((1.0 + bounce_damage * bounce_hits) / (1.0 + bounce_damage * (bounce_hits - 1)))
	var dir := velocity.normalized().bounce(normal)
	var enemy := _enemy()
	if target_bounce > 0.0:
		seek = maxf(seek, target_bounce)
		if enemy:
			var to_enemy := (enemy.chest() - point).normalized()
			var limit := BOUNCE_AIM_MAX * target_bounce / (target_bounce + BOUNCE_AIM_K)
			var angle := dir.angle_to(to_enemy)
			if to_enemy.dot(normal) > 0.0 and angle > 0.001:
				dir = dir.slerp(to_enemy, minf(1.0, limit / angle)).normalized()
	velocity = dir * velocity.length()
	global_position = point + normal * 0.05
	_orient()


## Fragmentação: estilhaços menores saem da parede em leque. Só a máquina de quem atirou
## cria os estilhaços (e os manda para as outras), senão cada máquina criaria os seus.
func _shatter(point: Vector3, normal: Vector3) -> void:
	global_position = point + normal * 0.1
	var out := velocity.normalized().bounce(normal)
	for k in split:
		var dir := out.rotated(normal, TAU * k / split).slerp(normal, 0.35).normalized()
		dir = dir.rotated(Vector3.UP, randf_range(-0.3, 0.3))
		_clone(dir, {"damage": damage * SHARD_DAMAGE, "split": 0, "radius": radius * 0.6,
			"sticky": false, "boomerang": false, "returning": false, "explosion": 0.0, "bounces": 0})


func _hit_player(target: Player, point: Vector3) -> void:
	if not target.is_local:
		# Quem decide é a máquina do alvo. Espera a resposta escondida no ponto do contato.
		waiting = REMOTE_WAIT
		ignore_remote_until = age + REMOTE_WAIT + 0.25
		visible = false
		global_position = point
		return
	if rocket:
		Player.rocket_blast(get_parent(), point, shooter)
		if Net.online:
			get_parent().net_bullet_hit.rpc(id, point, -1.0)
		queue_free()
		return
	if target.ice_timer > 0.0:
		# Bloco de gelo: não leva dano nem efeito; o tiro só empurra.
		target.ice_push(velocity, damage if not ice else 20.0)
		if Net.online:
			get_parent().net_bullet_hit.rpc(id, point, 0.0)
		Effects.burst(get_parent(), point, 0.5, Player.ICE_COLOR, 0.12)
		queue_free()
		return
	if target.is_shielding():
		_reflect(target, point)
		return
	if ice:
		target.freeze()
		if Net.online:
			get_parent().net_bullet_hit.rpc(id, point, 0.0)
		Effects.burst(get_parent(), point, 1.0, Player.ICE_COLOR, 0.2)
		queue_free()
		return
	var dmg := damage
	if execute > 0.0 and target.health < target.stats["max_health"] * 0.4:
		dmg *= 1.0 + execute
	if push > 0.0:
		target.knockback(velocity.normalized() * push + Vector3.UP * 3.0)
	if slow > 0.0:
		target.apply_slow(slow)
	if poison > 0.0:
		target.apply_poison(dmg * poison, shooter)
	if shield_break:
		target.silence()
	if blind > 0.0:
		target.apply_blind(blind)
	if swap and is_instance_valid(shooter) and shooter.alive:
		target.begin_swap(shooter)
	target.take_damage(dmg, shooter)
	if Net.online:
		get_parent().net_bullet_hit.rpc(id, point, dmg)
	_show_damage(point, dmg)
	_finish_hit(point, target)


## Número de dano subindo do ponto do acerto, só na tela de quem atirou.
func _show_damage(point: Vector3, dmg: float) -> void:
	if is_instance_valid(shooter) and shooter == Player.viewer:
		Effects.number(get_parent(), point, dmg, crit)


## Fim de uma bala que acertou alguém: explosão (se tiver) e some.
func _finish_hit(point: Vector3, skip: Player) -> void:
	_impact_fields(point, -velocity.normalized() if not velocity.is_zero_approx() else Vector3.UP)
	if explosion > 0.0:
		_explode(point, skip)
	else:
		# Clarão branco do tamanho da bala e faíscas vermelhas: o acerto se vê de longe.
		Effects.burst(get_parent(), point, maxf(0.45, radius * 3.0), Color(1, 1, 1), 0.1)
		Effects.sparks(get_parent(), point, Color(1.0, 0.35, 0.3))
	queue_free()


## Sniper: o feixe vai do cano até onde a bala chega em 0,4 s (atravessa as paredes).
## Desenhado no disparo (e ao chegar pela rede): a 400 m/s a bala pode acertar e sumir no
## primeiro quadro.
func _laser_beam() -> void:
	var dir := velocity.normalized()
	Effects.beam(get_parent(), global_position, global_position + dir * minf(160.0, velocity.length() * 0.4),
		Player.SNIPER_COLOR)


## Nuvem Tóxica e Buraco Negro onde a bala bateu (em todas as máquinas, sem rede).
func _impact_fields(point: Vector3, normal: Vector3) -> void:
	# Chuva de Meteoros: só a máquina de quem atirou marca (e avisa as outras).
	if meteor and is_instance_valid(shooter) and shooter.is_local:
		meteor = false
		shooter.meteor_mark(point)
	if (toxic > 0 or hole > 0) and is_instance_valid(shooter):
		AreaField.on_impact(shooter, point, normal, toxic, hole, damage)


## Dano em área. Só fere jogadores desta máquina; nunca o dono da bala; quem levou
## o tiro direto não leva de novo. Com Pulo-Foguete, a explosão lança o próprio dono.
func _explode(point: Vector3, skip: Player) -> void:
	var r := blast_size()
	var power := damage * EXPLOSION_DAMAGE * (1.0 + blast_damage)
	Effects.explosion(get_parent(), point, r, Color(1.0, 0.6, 0.2))
	Sfx.at(get_parent(), "explosion", point)
	_refresh_cache()
	if is_instance_valid(shooter) and shooter.is_local and shooter.alive and shooter.stats["rocket_jump"] > 0:
		var d := shooter.chest().distance_to(point)
		if d < r + 1.0:
			var away := (shooter.chest() - point).normalized()
			var k := 1.0 - 0.5 * d / (r + 1.0)
			shooter.launch(Vector3(away.x * 13.0, maxf(away.y * 15.0, 8.0), away.z * 13.0) * k)
	for node in _players:
		if not is_instance_valid(node):
			continue
		var p := node as Player
		if p == shooter or p == skip or not p.alive or not p.is_local \
				or (is_instance_valid(shooter) and shooter.is_ally(p)):
			continue
		var d := p.chest().distance_to(point)
		if d < r:
			var away := (p.chest() - point).normalized()
			p.knockback(away * 6.0 + Vector3.UP * 2.0)
			p.take_area_damage(power * (1.0 - 0.5 * d / r), shooter)


## Raio da explosão: cartas (explosion + blast_radius) mais a borda da bala.
func blast_size() -> float:
	return maxf(EXPLOSION_MIN, explosion + blast_radius + EXPLOSION_SIZE_GAIN * radius)


## Reflexo: a bala muda de dono e segue na direção de quem atirou.
func _reflect(target: Player, point: Vector3) -> void:
	var dir := -velocity.normalized()
	if is_instance_valid(shooter) and shooter.alive:
		dir = (shooter.chest() - point).normalized()
	# Só a primeira reflexão de cada bala se divide; senão um pingue-pongue entre
	# dois Espelhos Duplos dobraria o número de balas a cada troca.
	var split_count: int = 0 if reflected else target.stats["reflect_split"]
	_apply_reflect(target, point, dir, damage * target.stats["reflect_mult"],
		maxf(homing, target.stats["reflect_homing"]))
	if Net.online:
		get_parent().net_bullet_reflect.rpc(id, point, dir, String(target.name), damage, homing)
	for k in split_count:
		var side := 1.0 if k % 2 == 0 else -1.0
		_clone(dir.rotated(Vector3.UP, deg_to_rad(SPLIT_ANGLE * floorf(k / 2.0 + 1.0)) * side))
	target.on_reflect()


## A idade não zera: um pingue-pongue de reflexos termina quando a bala chega a LIFETIME.
## A bala refletida volta reta (sem queda nem bumerangue), para o reflexo ser justo.
func _apply_reflect(new_owner: Player, point: Vector3, dir: Vector3, new_damage: float, new_homing: float) -> void:
	shooter = new_owner
	if damage > 0.0:
		_scale_damage(new_damage / damage)
	homing = new_homing
	reflected = true
	bounced = false
	returning = false
	gravity = 0.0
	lazy_top = 0.0
	waiting = 0.0
	visible = true
	velocity = dir * maxf(velocity.length(), new_owner.stats["bullet_speed"])
	global_position = point
	_set_color(REFLECTED_COLOR)
	_orient()


## Resposta da outra máquina: o alvo refletiu esta bala.
func remote_reflect(point: Vector3, dir: Vector3, owner_name: String, new_damage: float, new_homing: float) -> void:
	var new_owner := get_parent().get_node_or_null(owner_name) as Player
	if new_owner == null:
		return
	_apply_reflect(new_owner, point, dir, new_damage, new_homing)
	new_owner.reflect_flash = 1.0
	Sfx.at(get_parent(), "reflect", point)


## Resposta da outra máquina: o alvo levou esta bala.
func remote_hit(point: Vector3, dmg: float) -> void:
	if rocket:
		Player.rocket_blast(get_parent(), point, shooter)
		queue_free()
		return
	if dmg <= 0.0:
		# Gelo (congelou ou bateu num bloco): sem número nem explosão.
		Effects.burst(get_parent(), point, 0.8, Player.ICE_COLOR, 0.15)
		queue_free()
		return
	_show_damage(point, dmg)
	_finish_hit(point, null)


## Rastros de todas as balas de um mesmo nó pai numa malha só: uma fita virada para a
## câmera por bala, pelos últimos pontos dela. Antes cada bala tinha a própria malha,
## refeita e enviada à placa de vídeo a cada quadro (centenas de envios numa chuva de balas).
class TrailBatch extends MeshInstance3D:
	const NODE_NAME := "BulletTrails"
	var imesh := ImmediateMesh.new()

	func _init() -> void:
		name = NODE_NAME
		mesh = imesh
		top_level = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _ready() -> void:
		global_transform = Transform3D.IDENTITY

	func _process(_delta: float) -> void:
		imesh.clear_surfaces()
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var eye := cam.global_position
		var parent := get_parent()
		var open := false
		for node in get_tree().get_nodes_in_group("bullets"):
			var b := node as Bullet
			if b.get_parent() != parent or not b.visible or b.trail_points.is_empty():
				continue
			var pts: Array = b.trail_points.duplicate()
			pts.append(b.get_global_transform_interpolated().origin)
			var width := clampf(b.radius * 0.8, 0.07, Bullet.TRAIL_MAX_WIDTH)
			var last := pts.size() - 1
			var prev_a := Vector3.ZERO
			var prev_b := Vector3.ZERO
			for i in pts.size():
				var p: Vector3 = pts[i]
				var tangent: Vector3 = pts[mini(i + 1, last)] - pts[maxi(i - 1, 0)]
				var side := tangent.cross(eye - p)
				if side.length_squared() < 0.000001:
					side = Vector3.UP
				var t := float(i) / last
				side = side.normalized() * width * t
				var a := p + side
				var c := p - side
				if i > 0:
					if not open:
						imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, Bullet.trail_material())
						open = true
					var col_prev := Color(b.color, 0.55 * float(i - 1) / last)
					var col := Color(b.color, 0.55 * t)
					imesh.surface_set_color(col_prev)
					imesh.surface_add_vertex(prev_a)
					imesh.surface_add_vertex(prev_b)
					imesh.surface_set_color(col)
					imesh.surface_add_vertex(a)
					imesh.surface_set_color(col_prev)
					imesh.surface_add_vertex(prev_b)
					imesh.surface_set_color(col)
					imesh.surface_add_vertex(c)
					imesh.surface_add_vertex(a)
				prev_a = a
				prev_b = c
		if open:
			imesh.surface_end()
