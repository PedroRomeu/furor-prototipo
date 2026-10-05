class_name Barrier
extends Node3D
## Parede do Bastião (carta mestra de Escudo): painel de energia em pé, de frente para onde
## o dono olhava. Devolve as balas dos outros (o teste é em bullet.gd, _check_barriers);
## as do dono e os jogadores passam. Some sozinha depois de TIME.

const TIME := 4.0
const WIDTH := 4.0
const HEIGHT := 3.2
const COLOR := Color(0.4, 0.9, 1.0)

var owner_player: Player
var life := TIME
var glow := 0.0
var material: StandardMaterial3D


func _ready() -> void:
	add_to_group("barriers")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(WIDTH, HEIGHT, 0.08)
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = HEIGHT / 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Só o desenho cresce ao surgir; a área que devolve as balas vale desde o começo.
	mi.scale = Vector3(1, 0.05, 1)
	create_tween().tween_property(mi, "scale", Vector3.ONE, 0.15)
	_paint()


func _process(delta: float) -> void:
	life -= delta
	glow = maxf(0.0, glow - delta * 4.0)
	if life <= 0.0:
		queue_free()
		return
	_paint()


func _paint() -> void:
	var fade := clampf(life / 0.5, 0.0, 1.0)   # some no último meio segundo
	material.albedo_color = Color(COLOR, (0.22 + glow * 0.5) * fade)


func flash() -> void:
	glow = 1.0
	Effects.burst(get_parent(), global_position + Vector3.UP * HEIGHT * 0.5, 1.0, COLOR, 0.15)


## Ponto onde o trecho from-to atravessa o painel, ou null.
func crossing(from: Vector3, to: Vector3) -> Variant:
	var inv := global_transform.affine_inverse()
	var a := inv * from
	var b := inv * to
	if (a.z > 0.0) == (b.z > 0.0) or is_equal_approx(a.z, b.z):
		return null
	var p := a.lerp(b, a.z / (a.z - b.z))
	if absf(p.x) > WIDTH / 2.0 or p.y < 0.0 or p.y > HEIGHT:
		return null
	return global_transform * p
