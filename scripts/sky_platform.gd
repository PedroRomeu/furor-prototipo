class_name SkyPlatform
extends StaticBody3D
## Uma plataforma da carta mestra Plataformas Suspensas: chão fino de 2 x 2 m que dura LIFETIME e
## pisca no último segundo. Todos pisam (escolha do usuário); as balas atravessam: fica
## numa camada própria (LAYER), que só os jogadores enxergam. Criada em todas as máquinas
## na mesma posição (Player._net_platform).

const LIFETIME := 5.0
const BLINK := 1.0
const SIZE := Vector3(2.0, 0.2, 2.0)
const LAYER := 4   # camada 3, "plataformas" (valor 4)

static var _mesh: BoxMesh
static var _shape: BoxShape3D

var time_left := LIFETIME
var _mat: StandardMaterial3D
var _mi: MeshInstance3D


static func spawn(parent: Node, pos: Vector3, color: Color) -> SkyPlatform:
	var p := SkyPlatform.new()
	p.collision_layer = LAYER
	p.collision_mask = 0
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = SIZE
		_shape = BoxShape3D.new()
		_shape.size = SIZE
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	p.add_child(cs)
	p._mat = StandardMaterial3D.new()
	p._mat.albedo_color = Color(color.lightened(0.35), 0.55)
	p._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p._mat.emission_enabled = true
	p._mat.emission = color
	p._mat.emission_energy_multiplier = 0.4
	p._mi = MeshInstance3D.new()
	p._mi.mesh = _mesh
	p._mi.material_override = p._mat
	p._mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(p._mi)
	p.add_to_group("sky_platforms")
	parent.add_child(p)
	p.global_position = pos
	Effects.burst(parent, pos, 1.4, color, 0.18)
	return p


func _physics_process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return
	if time_left < BLINK:
		_mi.visible = fmod(time_left, 0.2) > 0.08
