class_name AreaField
extends Node3D
## Áreas das cartas de 2026-10-06 (pedido do usuário, lembrando cartas do Furor; números
## meus): Serra, Chamas e Mina nascem do escudo (E); Nuvem Tóxica e Buraco Negro, de onde
## a bala bate. A Geada do escudo é instantânea e não deixa área (shield()).
##
## Em rede, cada máquina cria a mesma área (o escudo avisa por rpc, Player._net_shield_area;
## as balas já existem em todas) e cada uma só fere ou puxa os jogadores que ela controla,
## como as explosões em bullet.gd.
##
## Desempenho (PCs fracos): nada de partículas de fumaça nem névoa de verdade. Malhas e
## materiais são compartilhados; a nuvem é uma esfera de poucos polígonos com a borda
## esfumada por shader. Dano é conferido em intervalos (TICK), não a cada quadro. Nuvem e
## buraco negro têm intervalo mínimo e teto por jogador, e bala que bate perto de uma nuvem
## sua renova essa nuvem em vez de criar outra: uma Metralhadora não enche o mapa.

enum Kind { SAW, FLAMES, MINE, CLOUD, HOLE }

## Bits do aviso de escudo (Player._shield_area_mask), na ordem das cartas.
const SHIELD_SAW := 1
const SHIELD_FLAMES := 2
const SHIELD_FROST := 4
const SHIELD_MINE := 8

# Serra: gira em volta do dono; o raio cresce por cópia.
const SAW_TIME := 2.0
const SAW_RADIUS := 2.5
const SAW_RADIUS_STEP := 1.0
const SAW_TICK := 0.33
const SAW_DAMAGE := 6.0        # por toque: uns 18 por segundo
const SAW_SPIN := 14.0         # rad/s
# Chamas: acompanham o dono (escolha do usuário); quem fica dentro queima e continua
# queimando um pouco depois de sair (Player.apply_burn).
const FLAMES_TIME := 3.0
const FLAMES_RADIUS := 4.0
const FLAMES_RADIUS_STEP := 1.0
const FLAMES_TICK := 0.25
const FLAMES_DPS := 9.0
const BURN_AFTER := 1.0
# Geada: onda instantânea.
const FROST_RADIUS := 5.0
const FROST_RADIUS_STEP := 1.5
const FROST_DAMAGE := 6.0
const FROST_SLOW := 0.45
const FROST_TIME := 2.0
const FROST_TIME_STEP := 0.5
# Mina: pisca e explode; dano fixo (escolha do usuário), metade na borda.
const MINE_FUSE := 1.0
const MINE_RADIUS := 4.0
const MINE_RADIUS_STEP := 0.5
const MINE_DAMAGE := 30.0
const MINE_DAMAGE_STEP := 15.0
# Nuvem Tóxica: por segundo, CLOUD_DPS x o dano da bala que a criou.
const CLOUD_TIME := 3.0
const CLOUD_TIME_STEP := 1.0
const CLOUD_RADIUS := 2.5
const CLOUD_RADIUS_STEP := 0.75
const CLOUD_DPS := 0.3
const CLOUD_TICK := 0.5
const CLOUD_MERGE := 1.5       # bala a menos disto de uma nuvem sua renova a nuvem
const CLOUD_GAP := 0.25        # uma nuvem nova por jogador a cada tanto, no máximo
const CLOUD_MAX := 6           # nuvens vivas por jogador
# Buraco Negro: puxa para o centro, mais forte perto dele; sem dano.
const HOLE_TIME := 0.6
const HOLE_RADIUS := 5.0
const HOLE_RADIUS_STEP := 1.0
const HOLE_PULL := 30.0        # m/s² no centro (cai até um terço na borda)
const HOLE_PULL_STEP := 12.0
const HOLE_GROUND := 0.17      # no chão: arrasta a 5 m/s no centro com 1 cópia
const HOLE_GAP := 0.4
const HOLE_MAX := 4

const SAW_COLOR := Color(0.85, 0.88, 0.95)
const FLAME_COLOR := Color(1.0, 0.45, 0.1)
const FROST_COLOR := Color(0.55, 0.85, 1.0)
const MINE_COLOR := Color(1.0, 0.2, 0.15)
const CLOUD_COLOR := Color(0.45, 0.85, 0.2)
const HOLE_COLOR := Color(0.6, 0.3, 1.0)

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color;
uniform float fade = 1.0;
void vertex() {
	VERTEX += NORMAL * 0.07 * sin(TIME * 2.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0);
}
void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * fade * pow(facing, 1.6);
}
"""

static var _mats := {}
static var _meshes := {}
static var _cloud_shader: Shader
static var _last_spawn := {}   # "kind:dono" -> Time.get_ticks_msec()
static var _pulled := {}       # jogador -> quadro de física em que um buraco já o puxou
static var _cloud_hit := {}    # "alvo:dono" -> ms: nuvens do mesmo dono não somam

var kind := Kind.SAW
var owner_player: Player
var radius := 1.0
var life := 1.0
var time_total := 1.0
var power := 0.0               # dano (Serra, Mina, Nuvem) ou puxada (Buraco Negro)
var tick := 0.0
var _visual: Node3D
var _extra: Node3D             # Serra: nada; Mina: luz que pisca; Buraco: anel
var _cloud_mat: ShaderMaterial


# ---------------------------------------------------------------- criação

## Escudo levantado: cria as áreas dos bits de mask (e a onda da Geada). Roda em todas as
## máquinas; pos é onde o dono estava (a Mina fica ali).
static func shield(owner: Player, mask: int, pos: Vector3) -> void:
	var s := owner.stats
	var parent := owner.get_parent()
	if mask & SHIELD_SAW:
		_spawn(owner, Kind.SAW, pos, SAW_RADIUS + SAW_RADIUS_STEP * (s["shield_saw"] - 1), SAW_TIME, SAW_DAMAGE)
	if mask & SHIELD_FLAMES:
		_spawn(owner, Kind.FLAMES, pos, FLAMES_RADIUS + FLAMES_RADIUS_STEP * (s["shield_flames"] - 1),
			FLAMES_TIME, FLAMES_DPS)
	if mask & SHIELD_MINE:
		var mine := _spawn(owner, Kind.MINE, pos + Vector3.UP * 0.2,
			MINE_RADIUS + MINE_RADIUS_STEP * (s["shield_mine"] - 1), MINE_FUSE,
			MINE_DAMAGE + MINE_DAMAGE_STEP * (s["shield_mine"] - 1))
		Sfx.at(mine, "shield", mine.global_position)
	if mask & SHIELD_FROST:
		var n: int = s["shield_frost"]
		var r := FROST_RADIUS + FROST_RADIUS_STEP * (n - 1)
		var center := pos + Vector3.UP * owner.height * 0.6
		Effects.burst(parent, center, r, FROST_COLOR, 0.35)
		Effects.sparks(parent, center, FROST_COLOR, 12, 9.0)
		for p: Player in _local_enemies(owner):
			if p.chest().distance_to(center) < r:
				p.apply_slow(FROST_SLOW, FROST_TIME + FROST_TIME_STEP * (n - 1))
				p.take_damage(FROST_DAMAGE, owner)


## Bala bateu (parede, chão ou alguém): Nuvem Tóxica e Buraco Negro, se ela os carrega.
static func on_impact(owner: Player, point: Vector3, normal: Vector3, toxic: int, hole: int, damage: float) -> void:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	if toxic > 0:
		var center := point + normal * 0.6
		var near := _near_cloud(owner, center)
		var r := CLOUD_RADIUS + CLOUD_RADIUS_STEP * (toxic - 1)
		var t := CLOUD_TIME + CLOUD_TIME_STEP * (toxic - 1)
		if near:
			near.life = maxf(near.life, t)
			near.time_total = maxf(near.time_total, near.life)
			near.power = maxf(near.power, damage * CLOUD_DPS)
		elif _may_spawn(owner, Kind.CLOUD, CLOUD_GAP, CLOUD_MAX):
			_spawn(owner, Kind.CLOUD, center, r, t, damage * CLOUD_DPS)
	if hole > 0 and _may_spawn(owner, Kind.HOLE, HOLE_GAP, HOLE_MAX):
		_spawn(owner, Kind.HOLE, point + normal * 0.5, HOLE_RADIUS + HOLE_RADIUS_STEP * (hole - 1),
			HOLE_TIME, HOLE_PULL + HOLE_PULL_STEP * (hole - 1))


static func _spawn(owner: Player, k: Kind, pos: Vector3, r: float, t: float, p: float) -> AreaField:
	var f := AreaField.new()
	f.kind = k
	f.owner_player = owner
	f.radius = r
	f.life = t
	f.time_total = t
	f.power = p
	owner.get_parent().add_child(f)
	f.global_position = pos
	if k == Kind.CLOUD or k == Kind.HOLE:
		_last_spawn["%d:%s" % [k, owner.name]] = Time.get_ticks_msec()
	return f


static func _may_spawn(owner: Player, k: Kind, gap: float, most: int) -> bool:
	var last: int = _last_spawn.get("%d:%s" % [k, owner.name], -100000)
	if Time.get_ticks_msec() - last < gap * 1000.0:
		return false
	var count := 0
	for f in owner.get_tree().get_nodes_in_group("fields"):
		if f.kind == k and f.owner_player == owner:
			count += 1
	return count < most


static func _near_cloud(owner: Player, pos: Vector3) -> AreaField:
	for f in owner.get_tree().get_nodes_in_group("fields"):
		if f.kind == Kind.CLOUD and f.owner_player == owner and f.global_position.distance_to(pos) < CLOUD_MERGE:
			return f
	return null


## Inimigos vivos do dono que esta máquina controla (os únicos que ela pode ferir).
static func _local_enemies(owner: Player) -> Array:
	return owner.enemies().filter(func(p): return p.is_local)


## Fim da partida: solta malhas e materiais compartilhados.
static func clear_cache() -> void:
	_mats.clear()
	_meshes.clear()
	_cloud_shader = null
	_last_spawn.clear()
	_pulled.clear()
	_cloud_hit.clear()


# ---------------------------------------------------------------- vida da área

func _ready() -> void:
	add_to_group("fields")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	match kind:
		Kind.SAW: _build_saw()
		Kind.FLAMES: _build_flames()
		Kind.MINE: _build_mine()
		Kind.CLOUD: _build_cloud()
		Kind.HOLE: _build_hole()
	_follow()


func _physics_process(delta: float) -> void:
	life -= delta
	var follows := kind == Kind.SAW or kind == Kind.FLAMES
	if not is_instance_valid(owner_player) or (follows and not owner_player.alive):
		queue_free()
		return
	if life <= 0.0:
		if kind == Kind.MINE:
			_explode()
		queue_free()
		return
	_follow()
	if kind == Kind.HOLE:
		_pull(delta)
		return
	tick -= delta
	if tick > 0.0:
		return
	match kind:
		Kind.SAW:
			tick = SAW_TICK
			for p: Player in _local_enemies(owner_player):
				if _inside(p):
					p.take_damage(power, owner_player)
		Kind.FLAMES:
			tick = FLAMES_TICK
			for p: Player in _local_enemies(owner_player):
				if _inside(p):
					p.apply_burn(power, BURN_AFTER + FLAMES_TICK, owner_player)
		Kind.CLOUD:
			tick = CLOUD_TICK
			var now := Time.get_ticks_msec()
			for p: Player in _local_enemies(owner_player):
				var key := "%s:%s" % [p.name, owner_player.name]
				if _inside(p) and now - int(_cloud_hit.get(key, -100000)) >= CLOUD_TICK * 900.0:
					_cloud_hit[key] = now
					p.take_damage(power * CLOUD_TICK, owner_player)


func _process(delta: float) -> void:
	match kind:
		Kind.SAW:
			_visual.rotate_y(SAW_SPIN * delta)
			_visual.scale = Vector3.ONE * radius * minf(1.0, life / 0.2) * minf(1.0, (time_total - life) / 0.1 + 0.2)
		Kind.FLAMES:
			var k := minf(1.0, life / 0.3)
			_visual.scale = Vector3(radius * k, 1.0, radius * k)
			if life < 0.3:
				(_extra as CPUParticles3D).emitting = false
		Kind.MINE:
			# Pisca cada vez mais rápido perto de explodir.
			var t := 1.0 - life / time_total
			_extra.visible = fmod(t * t * 14.0, 1.0) < 0.5
		Kind.CLOUD:
			var grow := minf(1.0, (time_total - life) / 0.25)
			_visual.scale = Vector3.ONE * radius * (0.6 + 0.4 * grow)
			_cloud_mat.set_shader_parameter("fade", minf(1.0, life / 0.6))
		Kind.HOLE:
			var age := time_total - life
			var k := minf(1.0, age / 0.1) * minf(1.0, life / 0.15)
			_visual.scale = Vector3.ONE * 0.55 * k
			# Anel que se fecha para o centro, repetindo: mostra a puxada.
			var ring := 1.0 - fmod(age / 0.3, 1.0)
			_extra.scale = Vector3.ONE * maxf(0.05, radius * ring * k)


func _follow() -> void:
	if kind == Kind.SAW and is_instance_valid(owner_player):
		global_position = owner_player.global_position \
			+ Vector3.UP * owner_player.height * 0.5 * float(owner_player.stats["body_scale"])
	elif kind == Kind.FLAMES and is_instance_valid(owner_player):
		global_position = owner_player.global_position + Vector3.UP * 0.05


## Dentro da área: Serra e Chamas medem no chão (cilindro), as outras em esfera.
func _inside(p: Player) -> bool:
	if kind == Kind.SAW or kind == Kind.FLAMES:
		var d := p.global_position - owner_player.global_position
		var high := 2.0 if kind == Kind.SAW else 2.5
		return Vector2(d.x, d.z).length() < radius + Player.RADIUS and d.y > -2.0 and d.y < high
	return p.chest().distance_to(global_position) < radius + p.hit_radius() * 0.5


## Buraco Negro: puxa cada inimigo desta máquina para o centro. Um buraco por jogador a
## cada quadro (vários buracos juntos não somam a puxada).
func _pull(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	for p: Player in _local_enemies(owner_player):
		if _pulled.get(p, -1) == frame:
			continue
		var to := global_position - p.chest()
		var d := to.length()
		if d > radius or d < 0.3:
			continue
		_pulled[p] = frame
		var strength := power * (1.0 - 0.67 * d / radius)
		var dir := to / d
		if p.is_on_floor():
			# No chão o atrito anularia a puxada a cada quadro: arrasta direto, sem tirar do
			# chão, respeitando paredes (HOLE_GROUND m/s para cada m/s² da puxada).
			p.move_and_collide(Vector3(dir.x, 0.0, dir.z) * strength * HOLE_GROUND * delta)
		else:
			p.velocity += dir * strength * delta
			p.jump_rising = false


func _explode() -> void:
	var parent := get_parent()
	Effects.burst(parent, global_position, radius, Color(1.0, 0.6, 0.2))
	Sfx.at(parent, "explosion", global_position)
	if owner_player.is_local and owner_player.alive and owner_player.stats["rocket_jump"] > 0:
		var d := owner_player.chest().distance_to(global_position)
		if d < radius + 1.0:
			var away := (owner_player.chest() - global_position).normalized()
			var k := 1.0 - 0.5 * d / (radius + 1.0)
			owner_player.launch(Vector3(away.x * 13.0, maxf(away.y * 15.0, 8.0), away.z * 13.0) * k)
	for p: Player in _local_enemies(owner_player):
		var d := p.chest().distance_to(global_position)
		if d < radius:
			var away := (p.chest() - global_position).normalized()
			p.knockback(away * 9.0 + Vector3.UP * 4.0)
			p.take_damage(power * (1.0 - 0.5 * d / radius), owner_player)


# ---------------------------------------------------------------- visual

static func _mat(key: String, color: Color, additive := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = color
		if color.a < 1.0 or additive:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mats[key] = m
	return _mats[key]


func _add_mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Serra: anel fino com dentes, de raio 1 (a escala dá o raio), deitado.
static func _saw_mesh() -> ArrayMesh:
	if not _meshes.has("saw"):
		var teeth := 24
		var verts := PackedVector3Array()
		for i in teeth:
			var a0 := TAU * i / teeth
			var a1 := TAU * (i + 1) / teeth
			var am := (a0 + a1) * 0.5
			var in0 := Vector3(cos(a0), 0, sin(a0)) * 0.9
			var in1 := Vector3(cos(a1), 0, sin(a1)) * 0.9
			var out0 := Vector3(cos(a0), 0, sin(a0))
			var out1 := Vector3(cos(a1), 0, sin(a1))
			verts.append_array([in0, out0, in1, in1, out0, out1])
			# dente inclinado, como numa serra circular
			verts.append_array([out0, Vector3(cos(am), 0, sin(am)) * 1.12, out1])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes["saw"] = mesh
	return _meshes["saw"]


func _build_saw() -> void:
	_visual = _add_mesh(_saw_mesh(), _mat("saw", Color(SAW_COLOR, 0.85)))
	_visual.scale = Vector3.ONE * radius * 0.2
	Sfx.at(self, "shield", global_position)


static func _ring_mesh() -> TorusMesh:
	if not _meshes.has("ring"):
		var t := TorusMesh.new()
		t.inner_radius = 0.94
		t.outer_radius = 1.0
		t.rings = 32
		t.ring_segments = 4
		_meshes["ring"] = t
	return _meshes["ring"]


func _build_flames() -> void:
	_visual = _add_mesh(_ring_mesh(), _mat("flame_ring", Color(FLAME_COLOR, 0.7)))
	_visual.scale = Vector3(radius, 1.0, radius)
	var p := flame_particles()
	p.amount = 24 if GameState.quality == 0 else 48
	p.lifetime = 0.55
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.15
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	add_child(p)
	p.emitting = true
	_extra = p
	Sfx.at(self, "pad", global_position)


## Partículas de fogo (quadrados esfumados somando luz, laranja para vermelho), com malha,
## material e cores compartilhados. Quem usa ajusta a forma e a quantidade. Chamas e a
## Bota Foguete.
static func flame_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	if not _meshes.has("flame"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.6
		_meshes["flame"] = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft_dot()
		_mats["flame"] = m
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
		ramp.set_color(1, Color(0.9, 0.15, 0.05, 0.0))
		_meshes["flame_ramp"] = ramp
	p.mesh = _meshes["flame"]
	p.material_override = _mats["flame"]
	p.color_ramp = _meshes["flame_ramp"]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Círculo branco esfumado (64 px), usado nas chamas. Feito uma vez em código.
static func _soft_dot() -> ImageTexture:
	if not _meshes.has("dot"):
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5 - size / 2.0, y + 0.5 - size / 2.0).length() / (size / 2.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
		_meshes["dot"] = ImageTexture.create_from_image(img)
	return _meshes["dot"]


func _build_mine() -> void:
	var body := _add_mesh(Effects.sphere_mesh(), _mat("mine", Color(0.15, 0.15, 0.17)))
	body.scale = Vector3(0.3, 0.18, 0.3)
	_visual = body
	var light := _add_mesh(Effects.sphere_mesh(), _mat("mine_light", Color(MINE_COLOR.r * 2.5, MINE_COLOR.g * 2.5, MINE_COLOR.b * 2.5)))
	light.scale = Vector3.ONE * 0.1
	light.position.y = 0.17
	_extra = light
	# Anel no chão mostrando até onde a explosão chega.
	var ring := _add_mesh(_ring_mesh(), _mat("mine_ring", Color(MINE_COLOR, 0.35)))
	ring.scale = Vector3(radius, 1.0, radius)
	ring.position.y = -0.15


func _build_cloud() -> void:
	if _cloud_shader == null:
		_cloud_shader = Shader.new()
		_cloud_shader.code = CLOUD_SHADER
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = _cloud_shader
	_cloud_mat.set_shader_parameter("tint", Color(CLOUD_COLOR, 0.5))
	_visual = _add_mesh(Effects.sphere_mesh(), _cloud_mat)
	_visual.scale = Vector3.ONE * radius * 0.6


func _build_hole() -> void:
	_visual = _add_mesh(Effects.sphere_mesh(), _mat("hole", Color(0.02, 0.0, 0.05)))
	_visual.scale = Vector3.ONE * 0.05
	_extra = _add_mesh(_ring_mesh(), _mat("hole_ring", Color(HOLE_COLOR.r * 1.6, HOLE_COLOR.g * 1.6, HOLE_COLOR.b * 1.6, 0.8)))
	# Anel virado para cima e um pouco inclinado, para se ver de qualquer lado.
	_extra.rotation = Vector3(0.5, 0.0, 0.3)
	_extra.scale = Vector3.ONE * radius
	Effects.burst(get_parent(), global_position, 1.0, HOLE_COLOR, 0.2)
