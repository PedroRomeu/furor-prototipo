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
const REFLECTED_COLOR := Color(0.6, 1.0, 1.0)
const CRIT_COLOR := Color(1.0, 0.85, 0.2)
const PIERCE_COLOR := Color(0.85, 0.5, 1.0)
const EXPLOSION_DAMAGE := 0.6
const SPLIT_ANGLE := 10.0
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
## Teleguiada (refeita em 2026-10-04, como a Seeker do OVERKILL e a do Furor): a bala só
## curva quando um inimigo entra num raio em volta dela, e nem toda bala procura alvo.
## Raio, curva e chance crescem com as cópias (n) com retorno decrescente, n / (n + k):
## n=1: 33% das balas, raio 4,5 m, 1,3 rad/s (uns 8 graus de correção num tiro de perto);
## n=3: 60%, 7 m, 2,4 rad/s; n=10: 83%, 9,7 m, 3,3 rad/s. Nunca chega à mira perfeita.
const SEEK_CHANCE_K := 0.5
const SEEK_RADIUS_MIN := 2.0
const SEEK_RADIUS_GAIN := 10.0
const SEEK_RADIUS_K := 3.0
const SEEK_TURN_MAX := 4.0
const SEEK_TURN_K := 2.0
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
	"lazy_top", "seek", "crit", "bounced", "guided", "pierce", "bounce_hits", "grow_mult"]

static var _counter := 0

var id := ""
var shooter: Player
var velocity := Vector3.ZERO
var damage := 25.0
var radius := 0.1
var bounces := 0
var homing := 0.0      # curva fixa atrás do inimigo mais próximo (Espelho Perseguidor)
var seek := 0.0        # Teleguiada: cópias da carta, se esta bala ganhou o sorteio
var ghost := false
var explosion := 0.0
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
var material: StandardMaterial3D
var core: MeshInstance3D
var trail: ImmediateMesh
var trail_mat: StandardMaterial3D
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
	# Teleguiada: cada bala sorteia se procura alvo; o raio e a curva vêm do número de cópias.
	var seekers := float(s["homing"])
	if seekers > 0.0 and randf() < 1.0 - 1.0 / (1.0 + SEEK_CHANCE_K * seekers):
		b.seek = seekers
	b.explosion = s["explosion"]
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
	b.grow = 0.0   # a cópia nasce com idade 0: fica do tamanho atual em vez de recomeçar a conta
	for key in overrides:
		b.set(key, overrides[key])
	b.velocity = dir * velocity.length()
	b._launch(get_parent(), global_position)


func _ready() -> void:
	add_to_group("bullets")
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = material
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	_resize_core()

	# Rastro: uma fita virada para a câmera, desenhada a cada quadro pelos últimos pontos.
	trail = ImmediateMesh.new()
	trail_mat = StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_mat.vertex_color_use_as_albedo = true
	var trail_node := MeshInstance3D.new()
	trail_node.mesh = trail
	trail_node.top_level = true
	trail_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail_node)
	trail_node.global_transform = Transform3D.IDENTITY

	var c := shooter.color.lightened(0.45)
	if pierce:
		c = PIERCE_COLOR
	if crit:
		c = CRIT_COLOR
	if reflected:
		c = REFLECTED_COLOR
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
	material.albedo_color = Color(c.r * 2.2, c.g * 2.2, c.b * 2.2)
	if trail_mat:
		trail_mat.albedo_color = Color(1.6, 1.6, 1.6)
	set_meta("trail_color", c)


func _orient() -> void:
	if velocity.is_zero_approx():
		return
	var dir := velocity.normalized()
	var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(global_position + dir, up)


func _process(_delta: float) -> void:
	_draw_trail()


func _draw_trail() -> void:
	trail.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or trail_points.is_empty() or not visible:
		return
	var pts: Array = trail_points.duplicate()
	pts.append(get_global_transform_interpolated().origin)
	if pts.size() < 2:
		return
	var color: Color = get_meta("trail_color", Color.WHITE)
	var width := maxf(0.07, radius * 0.8)
	trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, trail_mat)
	for i in pts.size():
		var p: Vector3 = pts[i]
		var tangent: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		var side := tangent.cross(cam.global_position - p)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		var t := float(i) / (pts.size() - 1)
		side = side.normalized() * width * t
		trail.surface_set_color(Color(color, 0.55 * t))
		trail.surface_add_vertex(p + side)
		trail.surface_add_vertex(p - side)
	trail.surface_end()


func _physics_process(delta: float) -> void:
	age += delta
	if age > LIFETIME:
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
	_update_flight(delta)
	var from := global_position
	var to := from + velocity * delta
	var world_hit := {}
	if not ghost:
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		world_hit = get_world_3d().direct_space_state.intersect_ray(query)
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
		var reach := SEEK_RADIUS_MIN + SEEK_RADIUS_GAIN * seek / (seek + SEEK_RADIUS_K)
		if enemy and enemy.chest().distance_to(global_position) < reach:
			_steer_to(enemy.chest(), SEEK_TURN_MAX * seek / (seek + SEEK_TURN_K), delta)


## Parede do Bastião no caminho: devolve a bala de quem não é o dono dela. Quem decide é a
## máquina do dono da parede; as outras escondem a bala e esperam a resposta.
func _check_barriers(from: Vector3, end: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("barriers"):
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
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if not p.alive or (p == shooter and (not bounced or returning)):
			continue
		if is_instance_valid(shooter) and shooter.is_ally(p):
			continue   # 2x2: a bala atravessa o parceiro
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
	for node in get_tree().get_nodes_in_group("players"):
		if node == shooter or not node.alive or (is_instance_valid(shooter) and shooter.is_ally(node)):
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
	if normal.is_zero_approx():
		normal = -velocity.normalized()   # o raio começou dentro de uma parede
	if bounces <= 0 and sticky:
		# Detonação: gruda e explode depois (todas as máquinas fazem o mesmo).
		global_position = point + normal * 0.05
		velocity = Vector3.ZERO
		explosion = maxf(explosion, STICKY_RADIUS)
		fuse = STICKY_FUSE
		material.albedo_color = Color(3.0, 0.6, 0.3)
		return
	if explosion > 0.0:
		_explode(point, null)
	else:
		Effects.burst(get_parent(), point, 0.35, material.albedo_color, 0.12)
	if bounces <= 0:
		if split > 0 and is_instance_valid(shooter) and shooter.is_local:
			_shatter(point, normal)
		queue_free()
		return
	bounces -= 1
	bounced = true
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
	if target.is_shielding():
		_reflect(target, point)
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
		var here := target.global_position
		target.teleport_to(shooter.global_position)
		shooter.remote_call("teleport_to", [here])
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
	if explosion > 0.0:
		_explode(point, skip)
	else:
		# Clarão branco do tamanho da bala e faíscas vermelhas: o acerto se vê de longe.
		Effects.burst(get_parent(), point, maxf(0.45, radius * 3.0), Color(1, 1, 1), 0.1)
		Effects.sparks(get_parent(), point, Color(1.0, 0.35, 0.3))
	queue_free()


## Dano em área. Só fere jogadores desta máquina; nunca o dono da bala; quem levou
## o tiro direto não leva de novo. Com Pulo-Foguete, a explosão lança o próprio dono.
func _explode(point: Vector3, skip: Player) -> void:
	Effects.burst(get_parent(), point, explosion, Color(1.0, 0.6, 0.2))
	Sfx.at(get_parent(), "explosion", point)
	if is_instance_valid(shooter) and shooter.is_local and shooter.alive and shooter.stats["rocket_jump"] > 0:
		var d := shooter.chest().distance_to(point)
		if d < explosion + 1.0:
			var away := (shooter.chest() - point).normalized()
			var power := 1.0 - 0.5 * d / (explosion + 1.0)
			shooter.launch(Vector3(away.x * 13.0, maxf(away.y * 15.0, 8.0), away.z * 13.0) * power)
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == shooter or p == skip or not p.alive or not p.is_local \
				or (is_instance_valid(shooter) and shooter.is_ally(p)):
			continue
		var d := p.chest().distance_to(point)
		if d < explosion:
			var away := (p.chest() - point).normalized()
			p.knockback(away * 6.0 + Vector3.UP * 2.0)
			p.take_damage(damage * EXPLOSION_DAMAGE * (1.0 - 0.5 * d / explosion), shooter)


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
	_show_damage(point, dmg)
	_finish_hit(point, null)
