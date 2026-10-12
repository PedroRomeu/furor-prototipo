class_name RealmCrown
extends Node3D
## Coroa do Domínio do Rei (2026-10-11, ideia do usuário): na cabeça de quem lançou,
## enquanto tem o bônus de dano (lá dentro e nos 6 s depois de vencer). As pontas crescem
## com o bônus: baixinhas no começo, compridas e finas no máximo (+30%). Só para os outros
## (quem joga não tem modelo na própria tela).
##
## Desempenho: 2 chamadas de desenho (o aro e as pontas numa MultiMesh); criada no 1o uso
## e só ligada/desligada depois.

const POINTS := 5
const RING_RADIUS := 0.2
const RING_HEIGHT := 0.08
const SPIKE_MIN := 0.05     # altura das pontas sem bônus (m)
const SPIKE_MAX := 0.34     # no bônus máximo
const GOLD := Color(1.0, 0.78, 0.22)

var _spikes: MultiMeshInstance3D
var _bonus := -1.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GOLD
	mat.metallic = 0.6
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = GOLD
	mat.emission_energy_multiplier = 0.45   # aparece mesmo na sombra (0,25 ficava oliva)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var band := CylinderMesh.new()
	band.top_radius = RING_RADIUS
	band.bottom_radius = RING_RADIUS * 0.92
	band.height = RING_HEIGHT
	band.radial_segments = 20
	band.cap_top = false
	band.cap_bottom = false
	band.material = mat
	var ring := MeshInstance3D.new()
	ring.mesh = band
	ring.position.y = RING_HEIGHT / 2.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Ponta: pirâmide de 4 lados com a base no zero (escala em y = altura).
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.055
	cone.height = 1.0
	cone.radial_segments = 4
	cone.rings = 1
	cone.material = mat
	_spikes = MultiMeshInstance3D.new()
	_spikes.multimesh = MultiMesh.new()
	_spikes.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_spikes.multimesh.mesh = cone
	_spikes.multimesh.instance_count = POINTS
	_spikes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spikes.position.y = RING_HEIGHT
	add_child(_spikes)


## bonus: 0 a 1 (fração do bônus máximo); size: tamanho do corpo; top: altura da cabeça.
func tick(bonus: float, size: float, top: float) -> void:
	position = Vector3(0.0, top - 0.04 * size, 0.0)
	scale = Vector3.ONE * size
	if absf(bonus - _bonus) < 0.01:
		return
	_bonus = bonus
	var h := lerpf(SPIKE_MIN, SPIKE_MAX, bonus)
	var width := lerpf(1.0, 0.75, bonus)   # mais altas, mais finas: "pontuda"
	for i in POINTS:
		var a := TAU * i / POINTS
		# A base fica no meio da altura do cone (CylinderMesh é centrado): sobe metade.
		var b := Basis(Vector3.UP, a) * Basis().scaled(Vector3(width, h, width))
		var pos := Vector3(cos(a) * RING_RADIUS, h / 2.0, sin(a) * RING_RADIUS)
		_spikes.multimesh.set_instance_transform(i, Transform3D(b, pos))
