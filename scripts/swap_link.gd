class_name SwapLink
extends Node3D
## Troca-Troca (2026-10-05): enquanto a troca carrega, uma linha roxa liga os dois e um anel
## em volta de cada um se fecha até a hora da troca. Só visual, em todas as máquinas; quem
## decide a troca é a máquina de quem levou o tiro (Player.begin_swap).

const COLOR := Color(0.7, 0.45, 1.0)
const RING_START := 1.6   # raio do anel no começo; fecha até RING_END
const RING_END := 0.5

var a: Player
var b: Player
var time := 0.6
var _left := 0.0
var _beam: MeshInstance3D
var _rings: Array = []
var _mat: StandardMaterial3D


func _ready() -> void:
	_left = time
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = COLOR
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.05
	beam_mesh.bottom_radius = 0.05
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 6
	beam_mesh.rings = 1
	beam_mesh.material = _mat
	_beam = MeshInstance3D.new()
	_beam.mesh = beam_mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 4
	ring_mesh.material = _mat
	for i in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.top_level = true
		add_child(ring)
		_rings.append(ring)
	_place()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 or not _valid():
		queue_free()
		return
	_place()


func _valid() -> bool:
	return is_instance_valid(a) and is_instance_valid(b) and a.alive and b.alive


func _place() -> void:
	if not _valid():
		return
	var t := 1.0 - _left / time   # 0 no começo, 1 na troca
	# Pisca mais rápido perto da troca.
	_mat.albedo_color.a = 0.45 + 0.4 * absf(sin(t * t * 18.0))
	var p := a.chest()
	var q := b.chest()
	var length := p.distance_to(q)
	if length > 0.05:
		var dir := (q - p) / length
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		var up := side.cross(dir).normalized()
		_beam.global_transform = Transform3D(Basis(side.normalized(), dir, up), (p + q) / 2.0) \
			* Transform3D(Basis.from_scale(Vector3(1, length, 1)), Vector3.ZERO)
	var r := lerpf(RING_START, RING_END, t)
	for i in 2:
		var who: Player = a if i == 0 else b
		_rings[i].global_transform = Transform3D(Basis.from_scale(Vector3(r, r * 2.0, r)), who.global_position + Vector3.UP * 0.15)
