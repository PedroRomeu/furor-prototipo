class_name Pickup
extends Area3D
## Item no mapa que some ao ser pego e volta depois de um tempo.
## SPEED (círculo rosa com ">>", no chão): +30% de velocidade por 4 s.
## LAUNCH (círculo verde com uma seta para cima, flutuando baixo): lança uns 6 m e devolve
## dash, pulos e jato no ar (os dois substituíram o orbe de reset em 2026-10-06, ideia do
## usuário: o antigo ficava no alto das peças e quase ninguém pegava).
## HEALTH (cruz verde, no chão): cura um pouco. ARMOR (escudinho azul, raro): soma colete,
## que absorve dano antes da vida e não passa da rodada.
##
## Em rede cada máquina só testa o próprio jogador; quem pega avisa os outros pela arena
## (sinal taken), e eles escondem o item. Se dois pegarem no mesmo instante, os dois levam.

signal taken(index: int)

enum Kind { LAUNCH, HEALTH, ARMOR, SPEED }

const RESPAWN := {Kind.LAUNCH: 8.0, Kind.HEALTH: 25.0, Kind.ARMOR: 30.0, Kind.SPEED: 15.0}
const HEAL := 30.0
const ARMOR := 25.0
const LAUNCH_HEIGHT := 1.5   # Impulso: altura do centro acima do chão
## Cores do usuário (2026-10-06): Velocidade rosa, Impulso verde (um verde-limão, para não
## confundir com a cruz da vida), colete azul (o mesmo da HUD).
const COLORS := {Kind.LAUNCH: Color(0.7, 1.0, 0.25), Kind.HEALTH: Color(0.35, 1.0, 0.45),
	Kind.ARMOR: Color(0.3, 0.55, 1.0), Kind.SPEED: Color(1.0, 0.45, 0.75)}

var kind := Kind.LAUNCH
var index := 0
var cooldown := 0.0
var visual: Node3D
var ground: MeshInstance3D   # anel no chão (vida e colete)
var t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	cs.shape = sphere
	add_child(cs)
	visual = Node3D.new()
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # anima no _process
	add_child(visual)
	for mesh in _meshes(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(mi)
	# Marca no chão (fica enquanto o item não volta, para saber onde ele aparece). Todos
	# ficam a 0,8 m do chão, menos o Impulso, que flutua mais alto (marca mais abaixo).
	ground = MeshInstance3D.new()
	ground.mesh = _spot_mesh()
	ground.material_override = _spot_material(kind)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = -0.77 if kind != Kind.LAUNCH else -LAUNCH_HEIGHT + 0.03
	add_child(ground)


# ---------------------------------------------------------------- modelos (2026-10-06)
## Pedido do usuário: os antigos eram uma cruz de caixas, um "quadrado amarelo" e uma
## bolinha que não dava para entender. Agora: cruz com volume (vida), escudinho (colete) e
## duas setas para cima num anel (orbe de movimento, na cor do dash da HUD). As malhas são
## geradas uma vez e as mesmas para todos os itens; poucos triângulos e sem sombra.

static var _mesh_cache := {}
static var _spot_cache: Mesh
static var _spot_mats := {}


static func _meshes(k: Kind) -> Array:
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var color: Color = COLORS[k]
	var out := []
	match k:
		Kind.HEALTH:
			var cross := PackedVector2Array([Vector2(-0.12, 0.36), Vector2(0.12, 0.36), Vector2(0.12, 0.12),
				Vector2(0.36, 0.12), Vector2(0.36, -0.12), Vector2(0.12, -0.12), Vector2(0.12, -0.36),
				Vector2(-0.12, -0.36), Vector2(-0.12, -0.12), Vector2(-0.36, -0.12), Vector2(-0.36, 0.12),
				Vector2(-0.12, 0.12)])
			out.append(_extrude(cross, 0.2, _material(color)))
		Kind.ARMOR:
			var shield := _shield(0.62, 0.74)
			out.append(_extrude(shield, 0.16, _material(color)))
			# Emblema claro na frente e atrás: um escudo menor, um pouco saliente.
			var inner := _shield(0.36, 0.44)
			out.append(_extrude(inner, 0.22, _material(color.lerp(Color.WHITE, 0.55)), Vector2(0, 0.03)))
		Kind.LAUNCH, Kind.SPEED:
			# Velocidade: ">>" (duas setas deitadas); Impulso: uma seta para cima, maior.
			var shape_xf := Transform2D(0.0, Vector2(1.25, 1.25), 0.0, Vector2(0, 0.06)) if k == Kind.LAUNCH \
				else Transform2D(-PI / 2.0, Vector2.ZERO)
			for dy in ([0.0] if k == Kind.LAUNCH else [-0.1, 0.12]):
				var arrow := PackedVector2Array([Vector2(-0.24, dy - 0.08), Vector2(0.0, dy + 0.14),
					Vector2(0.24, dy - 0.08), Vector2(0.24, dy - 0.2), Vector2(0.0, dy + 0.02), Vector2(-0.24, dy - 0.2)])
				out.append(_extrude(shape_xf * arrow, 0.12, _material(color.lerp(Color.WHITE, 0.25))))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.38
			ring.outer_radius = 0.44
			ring.rings = 20
			ring.ring_segments = 6
			ring.material = _material(color)
			var holder := ArrayMesh.new()
			holder.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ring.get_mesh_arrays())
			holder.surface_set_material(0, ring.material)
			# O toro nasce deitado; em pé, de frente para quem olha (gira junto com o item).
			var arrays := holder.surface_get_arrays(0)
			var turn := Basis(Vector3.RIGHT, PI / 2.0)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i] = turn * v[i]
				n[i] = turn * n[i]
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_TANGENT] = null
			var torus := ArrayMesh.new()
			torus.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			torus.surface_set_material(0, ring.material)
			out.append(torus)
	_mesh_cache[k] = out
	return out


## Material com luz (mostra o volume) e um pouco de brilho próprio, para ler de longe.
static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.45
	m.roughness = 0.6
	return m


## Polígono 2D (no plano XY) com espessura em Z: frente, verso e laterais.
static func _extrude(poly: PackedVector2Array, depth: float, mat: Material, offset := Vector2.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	var h := depth / 2.0
	for side in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, side))
		for i in range(0, tris.size(), 3):
			var order := [0, 1, 2] if side < 0.0 else [0, 2, 1]
			for o in order:
				var p := poly[tris[i + o]] + offset
				st.add_vertex(Vector3(p.x, p.y, h * side))
	var clockwise := Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var a := poly[i] + offset
		var b := poly[(i + 1) % poly.size()] + offset
		var edge := (b - a).normalized()
		var out_dir := Vector3(edge.y, -edge.x, 0) * (-1.0 if clockwise else 1.0)
		st.set_normal(out_dir)
		var q := [Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(b.x, b.y, -h), Vector3(a.x, a.y, -h)]
		if clockwise:
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[idx])
		else:
			for idx in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(q[idx])
	st.set_material(mat)
	return st.commit()


## Contorno de escudo (largura w, altura h), centrado na origem.
static func _shield(w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hw := w / 2.0
	var top := h / 2.0
	pts.append(Vector2(-hw, top))
	pts.append(Vector2(hw, top))
	pts.append(Vector2(hw, top - h * 0.4))
	for k in range(1, 8):
		var t := k / 8.0
		var a := Vector2(hw, top - h * 0.4)
		var c := Vector2(hw, top - h * 0.8)
		var b := Vector2(0, -top)
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	pts.append(Vector2(0, -top))
	for k in range(1, 8):
		var t := k / 8.0
		var a := Vector2(0, -top)
		var c := Vector2(-hw, top - h * 0.8)
		var b := Vector2(-hw, top - h * 0.4)
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	pts.append(Vector2(-hw, top - h * 0.4))
	return pts


static func _spot_mesh() -> Mesh:
	if _spot_cache == null:
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.6)
		q.orientation = PlaneMesh.FACE_Y
		_spot_cache = q
	return _spot_cache


## Anel no chão desenhado por shader (um quadrado só, sem textura).
static func _spot_material(k: Kind) -> ShaderMaterial:
	if not _spot_mats.has(k):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.78, 0.84, d) * (1.0 - smoothstep(0.92, 0.98, d));
	ALBEDO = color.rgb;
	ALPHA = ring * color.a;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		var c: Color = COLORS[k]
		c.a = 0.55
		m.set_shader_parameter("color", c)
		_spot_mats[k] = m
	return _spot_mats[k]


func _physics_process(delta: float) -> void:
	if cooldown > 0.0:
		cooldown -= delta
		visual.visible = cooldown <= 0.0
		return
	for body in get_overlapping_bodies():
		var p := body as Player
		if p and p.is_local and p.alive and not p.frozen and _apply(p):
			take()
			taken.emit(index)
			return


func _process(delta: float) -> void:
	t += delta
	visual.rotation.y = t * 1.6
	visual.position.y = sin(t * 2.2) * 0.12


## Devolve se o jogador aproveitou (vida cheia não gasta a cura).
func _apply(p: Player) -> bool:
	if kind == Kind.HEALTH:
		if p.health >= p.stats["max_health"]:
			return false
		p.heal(HEAL)
	elif kind == Kind.ARMOR:
		if p.armor >= Player.ARMOR_MAX:
			return false
		p.armor = minf(Player.ARMOR_MAX, p.armor + ARMOR)
	elif kind == Kind.SPEED:
		p.speed_boost()
	else:
		p.launch_up()
	if p.is_human:
		Sfx.ui(p, "pickup")
	return true


func take() -> void:
	cooldown = RESPAWN[kind]
	visual.visible = false
