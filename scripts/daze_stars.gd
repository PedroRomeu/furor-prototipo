class_name DazeStars
extends MultiMeshInstance3D
## Tonto (Mega Tapa na parede, boliche do Gancho): estrelinhas girando em volta da cabeça,
## como nos desenhos. As 4 estrelas são instâncias de uma MultiMesh (uma chamada de
## desenho), com malha e material compartilhados por todos os jogadores.

const COUNT := 4
const RADIUS := 0.42        # raio do anel, multiplicado pelo tamanho do corpo
const ORBIT_SPEED := 4.5    # rad/s em volta da cabeça
const SPIN_SPEED := 5.0     # rad/s de cada estrela no próprio eixo
const TILT := 0.09          # o anel sobe de um lado e desce do outro (m)
const STAR_SIZE := 0.13     # raio da ponta da estrela (m)
const SHRINK_TIME := 0.3    # no fim as estrelas encolhem até sumir

static var _mesh: ArrayMesh
static var _mat: StandardMaterial3D

var _t := 0.0


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _star_mesh()
	multimesh.instance_count = COUNT
	material_override = _star_mat()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## left: quanto falta do efeito (s); size: tamanho do corpo; top: altura da cabeça (m).
func tick(delta: float, left: float, size: float, top: float) -> void:
	_t += delta
	position = Vector3(0.0, top + 0.12 * size, 0.0)
	var grow := clampf(left / SHRINK_TIME, 0.0, 1.0) * size
	for i in COUNT:
		var a := _t * ORBIT_SPEED + TAU * i / COUNT
		var pos := Vector3(cos(a) * RADIUS * size, sin(a) * TILT * size, sin(a) * RADIUS * size)
		var b := Basis(Vector3.UP, _t * SPIN_SPEED + i * 1.3).scaled(Vector3.ONE * grow)
		multimesh.set_instance_transform(i, Transform3D(b, pos))


## Estrela de 5 pontas chata: amarela por dentro e borda laranja um pouco maior atrás, nos
## dois lados (cores por vértice, para caber num material só).
static func _star_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_star(st, 1.0, 0.0, Color(0.95, 0.45, 0.05))
	_add_star(st, 0.72, 0.006, Color(1.0, 0.9, 0.25))
	_add_star(st, 0.72, -0.006, Color(1.0, 0.9, 0.25))
	_mesh = st.commit()
	return _mesh


static func _add_star(st: SurfaceTool, k_size: float, z: float, c: Color) -> void:
	var pts: Array[Vector3] = []
	for k in 10:
		var r := STAR_SIZE * k_size * (1.0 if k % 2 == 0 else 0.45)
		var a := PI / 2.0 + TAU * k / 10.0
		pts.append(Vector3(cos(a) * r, sin(a) * r, z))
	st.set_color(c)
	for k in 10:
		st.add_vertex(Vector3(0.0, 0.0, z))
		st.add_vertex(pts[k])
		st.add_vertex(pts[(k + 1) % 10])


static func _star_mat() -> StandardMaterial3D:
	if _mat:
		return _mat
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat
