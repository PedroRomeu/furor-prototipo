class_name MissileRain
extends Node3D
## Chuva de Mísseis (carta mestra de Arma, 2026-10-23, ideia do usuário: rádio, ponto e direção
## como o E do Viktor, área que estica devagar e salvas com aviso; números meus, aprovados).
## A área começa num círculo de RADIUS e a ponta da frente anda GROW m/s na direção escolhida,
## até LENGTH_MAX a mais (um oval de 5 x 15 m). Dura SALVOS salvas, uma a cada GAP s: o contorno
## avisa por WARN s (pisca vermelho e assobia) e caem MISSILES mísseis; quem está dentro leva
## o dano (o dono também; o parceiro dele não). O escudo não segura: vem de cima, como as
## explosões. BIG: com a chuva ativa, Q de novo chama um míssil grande na mira, dentro da área,
## uma vez por chuva. Cada máquina desenha tudo e só fere os jogadores dela.
## preview: o desenho que o dono vê enquanto mira (sem tempo nem dano).

const RADIUS := 5.0
const GROW := 1.2
const LENGTH_MAX := 10.0
const GAP := 2.0
const SALVOS := 6
const WARN := 0.8
const FALL := 0.5
const FALL_HEIGHT := 30.0
const HEIGHT := 8.0        # até esta altura acima do chão da área os mísseis pegam (ignoram telhado)
const DAMAGE := 18.0       # x Player.master_scale() de quem chamou
const MISSILES := 6
const BIG_DAMAGE := 40.0   # x master_scale(), 50% na borda
const BIG_RADIUS := 3.5
const COLOR := Color(1.0, 0.45, 0.2)
const WARN_COLOR := Color(1.0, 0.15, 0.1)
const AIM_COLOR := Color(1.0, 0.9, 0.6)
const AREA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec2 size = vec2(10.0, 10.0);
uniform float half_len = 0.0;
uniform float radius = 5.0;
uniform float warn = 0.0;
uniform vec3 color = vec3(1.0, 0.45, 0.2);
uniform vec3 warn_color = vec3(1.0, 0.15, 0.1);
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float d = length(vec2(max(abs(p.x) - half_len, 0.0), p.y));
	float edge = smoothstep(radius - 0.45, radius - 0.25, d) * (1.0 - smoothstep(radius - 0.08, radius, d));
	float inside = 1.0 - smoothstep(radius - 0.1, radius, d);
	float pulse = warn * (0.55 + 0.45 * sin(TIME * 28.0));
	ALBEDO = mix(color, warn_color, warn);
	ALPHA = max(edge * (0.75 + 0.25 * pulse), inside * (0.07 + 0.22 * pulse));
}
"""

static var _shader: Shader
static var _quad: QuadMesh
static var _missile_mesh: CylinderMesh

var owner_player: Player
var start := Vector3.ZERO
var dir := Vector3.FORWARD
var length := 0.0
var damage := DAMAGE
var preview := false
var big_used := false
var t := 0.0
var salvos_done := 0
var _area: MeshInstance3D
var _mat: ShaderMaterial
var _falling: Array = []   # [{node, pos}] mísseis da salva que vem
var _big: Dictionary = {}  # ataque concentrado: {pos, dmg, t, ring, mat, node}


static func spawn(parent: Node, from: Player, pos: Vector3, direction: Vector3, dmg: float, is_preview := false) -> MissileRain:
	var r := MissileRain.new()
	r.owner_player = from
	r.damage = dmg
	r.preview = is_preview
	if not is_preview:
		r.add_to_group("missile_rains")
	parent.add_child(r)
	r.set_shape(pos, direction, 0.0)
	return r


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = AREA_SHADER
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_quad.orientation = PlaneMesh.FACE_Y
		_missile_mesh = CylinderMesh.new()
		_missile_mesh.top_radius = 0.05
		_missile_mesh.bottom_radius = 0.2
		_missile_mesh.height = 1.3
		_missile_mesh.radial_segments = 8
		_missile_mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.32)
		mat.emission_enabled = true
		mat.emission = COLOR
		mat.emission_energy_multiplier = 0.8
		_missile_mesh.material = mat
	_area = _make_area()
	_mat = _area.material_override
	if preview:
		_mat.set_shader_parameter("color", Vector3(AIM_COLOR.r, AIM_COLOR.g, AIM_COLOR.b))


func _make_area() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("color", Vector3(COLOR.r, COLOR.g, COLOR.b))
	mat.set_shader_parameter("warn_color", Vector3(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Começo, direção (no chão) e quanto a ponta já andou. O quad cobre o oval: comprimento ao
## longo da direção, largura 2 x RADIUS.
func set_shape(pos: Vector3, direction: Vector3, along: float) -> void:
	start = pos
	var flat := Vector3(direction.x, 0.0, direction.z)
	dir = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	length = along
	_place(_area, _mat, start + dir * (length / 2.0), length, RADIUS)


func _place(mi: MeshInstance3D, mat: ShaderMaterial, center: Vector3, along: float, r: float) -> void:
	var w := along + r * 2.0
	mi.global_transform = Transform3D(Basis(dir * w, Vector3.UP, dir.cross(Vector3.UP) * (r * 2.0)), center + Vector3.UP * 0.06)
	mat.set_shader_parameter("size", Vector2(w, r * 2.0))
	mat.set_shader_parameter("half_len", along / 2.0)
	mat.set_shader_parameter("radius", r)


## Dentro do oval (no chão) e na faixa de altura que os mísseis pegam.
func contains(pos: Vector3, pad := 0.0) -> bool:
	if pos.y < start.y - 2.0 or pos.y > start.y + HEIGHT:
		return false
	return _flat_dist(pos) <= RADIUS + pad


func _flat_dist(pos: Vector3) -> float:
	var p := Vector3(pos.x - start.x, 0.0, pos.z - start.z)
	var s := clampf(p.dot(dir), 0.0, length)
	return p.distance_to(dir * s)


## Para onde sair da área mais rápido (no chão), ou zero fora dela. Usado pelos bots.
func escape_dir(pos: Vector3) -> Vector3:
	if not contains(pos, 0.8):
		return Vector3.ZERO
	var p := Vector3(pos.x - start.x, 0.0, pos.z - start.z)
	var away := p - dir * clampf(p.dot(dir), 0.0, length)
	return away.normalized() if away.length() > 0.2 else dir.cross(Vector3.UP)


## O ponto mais perto dentro da área (o ataque concentrado mirado fora cai na borda).
func clamp_inside(pos: Vector3) -> Vector3:
	var p := Vector3(pos.x - start.x, 0.0, pos.z - start.z)
	var on := dir * clampf(p.dot(dir), 0.0, length)
	var off := p - on
	if off.length() > RADIUS - 0.5:
		off = off.normalized() * (RADIUS - 0.5)
	return Vector3(start.x, start.y, start.z) + on + off


func _process(delta: float) -> void:
	if preview:
		return
	t += delta
	length = minf(LENGTH_MAX, GROW * t)
	_place(_area, _mat, start + dir * (length / 2.0), length, RADIUS)
	var impact := GAP * float(salvos_done + 1)
	var warn := clampf((t - (impact - WARN)) / WARN, 0.0, 1.0)
	_mat.set_shader_parameter("warn", warn)
	if warn > 0.0 and _falling.is_empty() and salvos_done < SALVOS:
		_announce(impact)
	_fall(impact)
	if t >= impact and salvos_done < SALVOS:
		_salvo()
	if not _big.is_empty():
		_big_step(delta)
	if salvos_done >= SALVOS and _big.is_empty():
		queue_free()


## Começo do aviso: assobio e os mísseis sorteados onde a área vai estar no impacto.
func _announce(impact: float) -> void:
	Sfx.at(get_parent(), "missile_warn", start + dir * (length / 2.0) + Vector3.UP)
	var len_then := minf(LENGTH_MAX, GROW * impact)
	for i in MISSILES:
		var a := randf() * TAU
		var r := sqrt(randf()) * (RADIUS - 0.6)
		var pos := start + dir * (randf() * len_then) + Vector3(cos(a), 0.0, sin(a)) * r
		var node := MeshInstance3D.new()
		node.mesh = _missile_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		_falling.append({"node": node, "pos": pos})


func _fall(impact: float) -> void:
	var k := clampf((t - (impact - FALL)) / FALL, 0.0, 1.0)
	if k <= 0.0:
		return
	for m in _falling:
		var node: MeshInstance3D = m["node"]
		node.visible = true
		node.global_position = m["pos"] + Vector3.UP * lerpf(FALL_HEIGHT, 0.6, k * k)


func _salvo() -> void:
	salvos_done += 1
	for m in _falling:
		var pos: Vector3 = m["pos"] + Vector3.UP * 0.4
		Effects.explosion(get_parent(), pos, 1.8, COLOR)
		m["node"].queue_free()
	_falling.clear()
	Sfx.at(get_parent(), "explosion", start + dir * (length / 2.0) + Vector3.UP)
	for p: Player in _victims():
		if contains(p.chest(), p.hit_radius()):
			p.take_area_damage(damage, owner_player if is_instance_valid(owner_player) else null)


## Jogadores desta máquina que a chuva fere: todos menos o parceiro de quem chamou.
func _victims() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.is_local or not p.alive:
			continue
		if is_instance_valid(owner_player) and owner_player.is_ally(p):
			continue
		out.append(p)
	return out


## Ataque concentrado (todas as máquinas): círculo de aviso no ponto e um míssil grande.
func big_strike(pos: Vector3, dmg: float) -> void:
	if big_used:
		return
	big_used = true
	var ring := _make_area()
	var mat: ShaderMaterial = ring.material_override
	_place(ring, mat, pos, 0.0, BIG_RADIUS)
	mat.set_shader_parameter("warn", 1.0)
	var node := MeshInstance3D.new()
	node.mesh = _missile_mesh
	node.scale = Vector3.ONE * 2.2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	_big = {"pos": pos, "dmg": dmg, "t": 0.0, "ring": ring, "node": node}
	Sfx.at(get_parent(), "missile_warn", pos + Vector3.UP)


func _big_step(delta: float) -> void:
	_big["t"] += delta
	var bt: float = _big["t"]
	var node: MeshInstance3D = _big["node"]
	var k := clampf((bt - (WARN - FALL)) / FALL, 0.0, 1.0)
	if k > 0.0:
		node.visible = true
		node.global_position = _big["pos"] + Vector3.UP * lerpf(FALL_HEIGHT, 1.0, k * k)
	if bt < WARN:
		return
	var pos: Vector3 = _big["pos"] + Vector3.UP * 0.5
	Effects.explosion(get_parent(), pos, BIG_RADIUS, COLOR)
	Effects.sparks(get_parent(), pos, COLOR, 16, 9.0)
	Sfx.at(get_parent(), "explosion", pos)
	for p: Player in _victims():
		var d := p.chest().distance_to(pos)
		if d > BIG_RADIUS + p.hit_radius():
			continue
		p.take_area_damage(_big["dmg"] * (1.0 - 0.5 * clampf(d / BIG_RADIUS, 0.0, 1.0)),
			owner_player if is_instance_valid(owner_player) else null)
	_big["ring"].queue_free()
	node.queue_free()
	_big = {}
