class_name KingRealm
extends Node3D
## Sala do Domínio do Rei (carta mestra, 2026-10-11, ideia do usuário inspirada na
## ultimate do Mordekaiser; números meus, aprovados). Quem lança leva o alvo para cá e os
## dois lutam sozinhos por Player.REALM_TIME. A sala fica longe do mapa, na mesma altura
## (o vazio e o teto das balas continuam valendo como lá), uma por jogador (vaga = lado),
## para dois Domínios ao mesmo tempo não se misturarem. Montada no 1o uso e guardada até o
## fim da partida (a arena muda a cada rodada; a sala não).
##
## Desempenho: ~10 caixas opacas com 3 materiais da sala, sem sombras; só quem está
## dentro a vê (de longe some na névoa).

const OFFSET := Vector3(1000, 0, 0)   # vaga 0; cada vaga a mais anda SLOT_STEP em x
const SLOT_STEP := 60.0
const HALF := 13.0      # 26 x 26 m (era 18 x 18; o usuário achou pequena demais)
const HEIGHT := 10.0    # cabe a Corrente (8 m) e um pulo em cima de uma cobertura
const DEPTH := 2.0      # laje do chão
const SPAWN_Z := 8.5    # os dois nascem frente a frente, a 17 m

const FLOOR_COLOR := Color(0.07, 0.04, 0.1)
const WALL_COLOR := Color(0.1, 0.05, 0.15)
const BLOCK_COLOR := Color(0.2, 0.09, 0.28)
const GLOW := Color(0.75, 0.35, 1.0)   # grade roxa acesa por emissão
const MARK_COLOR := Color(0.7, 0.3, 1.0)

var _materials := {}   # da sala (não estático: nada preso ao fechar o jogo)
var _grid: ImageTexture


## A sala da vaga (lado de quem lança) dentro de `parent` (a partida); cria no 1o uso.
static func room_for(parent: Node, slot: int) -> KingRealm:
	var key := "KingRealm%d" % slot
	var room := parent.get_node_or_null(key) as KingRealm
	if room == null:
		room = KingRealm.new()
		room.name = key
		room.position = center_of(slot)
		parent.add_child(room)
		room._build()
	return room


static func center_of(slot: int) -> Vector3:
	return OFFSET + Vector3(SLOT_STEP * slot, 0, 0)


## Onde cada um nasce: quem lança no sul olhando para o norte, o alvo à frente dele.
func spawn_for(king: bool) -> Transform3D:
	var z := SPAWN_Z if king else -SPAWN_Z
	var basis := Basis() if king else Basis(Vector3.UP, PI)
	return Transform3D(basis, global_position + Vector3(0, 0.1, z))


func _build() -> void:
	var h := HEIGHT
	var w := HALF * 2.0
	_block(Vector3(0, -DEPTH / 2.0, 0), Vector3(w + 2, DEPTH, w + 2), "floor")
	_block(Vector3(0, h / 2.0, -HALF - 0.5), Vector3(w + 2, h, 1), "wall")
	_block(Vector3(0, h / 2.0, HALF + 0.5), Vector3(w + 2, h, 1), "wall")
	_block(Vector3(-HALF - 0.5, h / 2.0, 0), Vector3(1, h, w), "wall")
	_block(Vector3(HALF + 0.5, h / 2.0, 0), Vector3(1, h, w), "wall")
	_block(Vector3(0, h + 0.5, 0), Vector3(w + 2, 1, w + 2), "wall")
	# Duas coberturas baixas (agachado esconde) e dois pilares, em diagonal: nenhum dos dois
	# lados começa com vantagem.
	_block(Vector3(-4.0, 0.6, -2.0), Vector3(3.5, 1.2, 1.0), "block")
	_block(Vector3(4.0, 0.6, 2.0), Vector3(3.5, 1.2, 1.0), "block")
	_block(Vector3(-7.5, h / 2.0, 4.5), Vector3(1.4, h, 1.4), "block")
	_block(Vector3(7.5, h / 2.0, -4.5), Vector3(1.4, h, 1.4), "block")


func _block(center: Vector3, size: Vector3, kind: String) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _material(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)


## Mesmo jeito das superfícies da sala de teste (grade por emissão que não estica), em roxo.
func _material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var colors := {"floor": FLOOR_COLOR, "wall": WALL_COLOR, "block": BLOCK_COLOR}
	var glow := {"floor": 0.6, "wall": 0.4, "block": 0.7}
	var m := StandardMaterial3D.new()
	m.albedo_color = colors[kind]
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = GLOW
	m.emission_energy_multiplier = glow[kind]
	if _grid == null:
		_grid = TestRoom.make_holo_texture()
	m.emission_texture = _grid
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_materials[kind] = m
	return m


## Marca no mapa onde alguém sumiu para o Domínio: círculo roxo no chão e os segundos até
## voltar, para quem ficou saber onde e quando ele reaparece (o contra-jogo da carta).
class Marker extends Node3D:
	var time_left := 0.0
	var label: Label3D

	func _init(t: float) -> void:
		time_left = t

	func _ready() -> void:
		# Malha própria (só 2 marcas por uso): estática ficaria presa ao fechar o jogo.
		var disc := CylinderMesh.new()
		disc.top_radius = 0.9
		disc.bottom_radius = 0.9
		disc.height = 0.04
		disc.radial_segments = 24
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(MARK_COLOR, 0.7)
		disc.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.position.y = 0.05
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Coluna de luz fraca: o ponto de volta se acha de longe (o disco no chão some).
		var column := CylinderMesh.new()
		column.top_radius = 0.5
		column.bottom_radius = 0.7
		column.height = 3.0
		column.radial_segments = 16
		column.cap_top = false
		column.cap_bottom = false
		var glow := mat.duplicate() as StandardMaterial3D
		glow.albedo_color = Color(MARK_COLOR, 0.2)
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		column.material = glow
		var ci := MeshInstance3D.new()
		ci.mesh = column
		ci.position.y = 1.5
		ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ci)
		label = Label3D.new()
		label.font = Ui.bold()
		label.font_size = 64
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = MARK_COLOR.lightened(0.3)
		label.outline_size = 8
		label.position.y = 3.5
		add_child(label)
		_show()

	func _process(delta: float) -> void:
		time_left = maxf(0.0, time_left - delta)
		_show()

	func _show() -> void:
		label.text = "%d" % ceili(time_left)
