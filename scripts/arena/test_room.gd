class_name TestRoom
extends Arena
## Sala de teste do baralho (pedido do usuário em 2026-10-07; tema "sala de testes" com
## base azul e hologramas, 2026-10-08). Mapa fixo, feito à mão, fechado e sem sombras:
## a oeste o estande de tiro (bonecos a 8, 20 e 40 m e o trilho do alvo móvel, a parede
## lisa ao lado para ricochete), a sudeste o parkour (degraus de 2, 4 e 6 m, muro de 7 m,
## vão de 10 m sobre o vazio, plataforma de salto), a nordeste a área de defesa (atiradores
## no chão e no mezanino).
##
## Desempenho (Intel HD): tudo opaco; o "aceso" é cor que não recebe luz (unshaded) ou
## emissão sem glow; os filetes de luz de todas as quinas são UMA malha só.

const HALF_X := 32.0
const HALF_Z := 30.0
const HEIGHT := 16.0          # pé-direito; teto fechado
const DEPTH := 8.0            # laje do chão (mais funda que o buraco, para não entrar embaixo)
const STRIP := 0.04           # espessura dos filetes de luz
const PIT := Rect2(11, 4, 8, 8)   # buraco para o vazio (x, z, largura, fundo), embaixo do vão

const HOLO := Color(0.35, 0.85, 1.0)       # ciano dos filetes, placas e marcas
const FLOOR_COLOR := Color(0.05, 0.08, 0.15)
const WALL_COLOR := Color(0.06, 0.1, 0.19)
const BLOCK_COLOR := Color(0.1, 0.19, 0.36)
const CEIL_COLOR := Color(0.03, 0.05, 0.1)

## Pontos usados pela partida: alvos parados, trilho do alvo móvel (ponta a ponta),
## atiradores e o ponto de defesa.
const DUMMY_SPOTS := [Vector3(-16, 0, 12), Vector3(-16, 0, 0), Vector3(-16, 0, -20)]
const RAIL := [Vector3(-26, 0, -8), Vector3(-6, 0, -8)]
const SHOOTER_SPOTS := [Vector3(18, 0, -19), Vector3(18, 6, -27.5)]
const DEFENSE_SPOT := Vector3(18, 0, -4)

const PALETTE := {
	"name": "Sala de teste", "void": Color(0.02, 0.04, 0.09),
	"sky_top": Color(0.02, 0.035, 0.07), "sky_horizon": Color(0.03, 0.05, 0.1),
	"fog": Color(0.1, 0.2, 0.35), "fog_density": 0.006,
	"sun": Color(0.85, 0.92, 1.0), "sun_energy": 0.35,
	"ambient": Color(0.55, 0.7, 0.95), "ambient_energy": 0.62,
}

var _strips := SurfaceTool.new()
static var _holo_tex: ImageTexture
static var _holo_mats := {}   # cor -> ShaderMaterial do corpo de holograma
const SHOOTER_TINT := Color(1.0, 0.55, 0.25)   # atiradores em laranja: são os que atiram

## Corpo dos bonecos: holograma translúcido, mais claro na silhueta, com faixas de
## varredura descendo. Sem luz (unshaded).
const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;
uniform vec4 tint : source_color = vec4(0.45, 0.9, 1.0, 1.0);
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float scan = 0.75 + 0.25 * step(0.5, fract(world_pos.y * 7.0 - TIME * 0.8));
	ALBEDO = tint.rgb * (0.55 + rim * 0.9) * scan;
	ALPHA = clamp(0.45 + rim * 0.5, 0.0, 1.0);
}
"""


func build(_map_index: int, _seed_value: int, _player_count := 2) -> void:
	half = minf(HALF_X, HALF_Z)
	palette = PALETTE
	theme_name = PALETTE["name"]
	map_name = "Sala de teste"
	style_name = map_name
	_setup_nav()
	_strips.begin(Mesh.PRIMITIVE_TRIANGLES)
	spawns.append(Transform3D(Basis(), Vector3(0, 0.1, 24)))   # olhando para o norte (-Z)
	# Bonecos (lados 1 a 4 da partida), virados para a linha de tiro (+Z).
	var facing := Basis(Vector3.UP, PI)
	for spot: Vector3 in DUMMY_SPOTS + [(RAIL[0] + RAIL[1]) / 2.0]:
		spawns.append(Transform3D(facing, spot + Vector3(0, 0.1, 0)))
	# Atiradores (lados 5 e 6), virados para o ponto de defesa.
	for spot: Vector3 in SHOOTER_SPOTS:
		var to := DEFENSE_SPOT - spot
		spawns.append(Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), spot + Vector3(0, 0.1, 0)))

	_room()
	_range()
	_parkour()
	_defense()

	var lines := MeshInstance3D.new()
	lines.mesh = _strips.commit()
	lines.material_override = _flat(HOLO)
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)


# ---------------------------------------------------------------- partes

## Chão com o buraco do vazio, paredes e teto.
func _room() -> void:
	var p := PIT
	var x0 := -HALF_X
	var x1 := HALF_X
	var z0 := -HALF_Z
	var z1 := HALF_Z
	# Chão em 4 lajes em volta do buraco.
	for r in [Rect2(x0, z0, x1 - x0, p.position.y - z0), Rect2(x0, p.end.y, x1 - x0, z1 - p.end.y),
			Rect2(x0, p.position.y, p.position.x - x0, p.size.y), Rect2(p.end.x, p.position.y, x1 - p.end.x, p.size.y)]:
		_block(Vector3(r.get_center().x, -DEPTH / 2.0, r.get_center().y), Vector3(r.size.x, DEPTH, r.size.y), "floor", false)
	_rect_strip(Rect2(p.position, p.size), 0.0)
	_void_floor()
	# Paredes e teto.
	var h := HEIGHT
	_block(Vector3(0, h / 2.0, z0 - 0.5), Vector3(x1 - x0 + 2, h, 1), "wall", false)
	_block(Vector3(0, h / 2.0, z1 + 0.5), Vector3(x1 - x0 + 2, h, 1), "wall", false)
	_block(Vector3(x0 - 0.5, h / 2.0, 0), Vector3(1, h, z1 - z0), "wall", false)
	_block(Vector3(x1 + 0.5, h / 2.0, 0), Vector3(1, h, z1 - z0), "wall", false)
	_block(Vector3(0, h + 0.5, 0), Vector3(x1 - x0 + 2, 1, z1 - z0 + 2), "ceiling", false)
	# Filetes: rodapé, quinas de cima e cantos em pé.
	_rect_strip(Rect2(x0, z0, x1 - x0, z1 - z0), 0.0)
	_rect_strip(Rect2(x0, z0, x1 - x0, z1 - z0), h)
	for c in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1)]:
		_strip(Vector3(c.x, 0, c.y), Vector3(c.x, h, c.y))


## Estande de tiro: linha de tiro, marcas dos bonecos com a distância e o trilho do alvo móvel.
func _range() -> void:
	var line_z := 20.0
	_strip(Vector3(-28, 0, line_z), Vector3(-4, 0, line_z))
	_sign("LINHA DE TIRO", Vector3(-16, 0.25, line_z + 0.6), 40, true)
	for spot: Vector3 in DUMMY_SPOTS:
		_ring(spot, 0.9)   # a distância está no nome do boneco (match.DUMMY_NAMES)
	_strip(RAIL[0], RAIL[1])
	_strip(RAIL[0] + Vector3(0, 0, 0.6), RAIL[1] + Vector3(0, 0, 0.6))
	_sign("RICOCHETE", Vector3(-HALF_X + 0.05, 5.0, 4.0), 64, false, PI / 2.0)


## Parkour: degraus de 2, 4 e 6 m, muro de 7 m para escalar, vão de 10 m sobre o vazio e
## uma plataforma de salto.
func _parkour() -> void:
	for i in 3:
		var h := 2.0 * (i + 1)
		_block(Vector3(7 + 5 * i, h / 2.0, 27 - 5 * i), Vector3(3, h, 3), "block")
		_sign("%d m" % roundi(h), Vector3(7 + 5 * i, h + 1.2, 27 - 5 * i + 1.6), 40)
	_block(Vector3(27, 3.5, 23), Vector3(6, 7, 8), "block")
	_sign("ESCALADA 7 m", Vector3(23.9, 4.0, 23), 48, false, -PI / 2.0)
	for x in [8.0, 22.0]:
		_block(Vector3(x, 1.5, PIT.get_center().y), Vector3(4, 3, 4), "block")
	_sign("VÃO 10 m", Vector3(15, 5.0, PIT.get_center().y), 56)
	var pad := JumpPad.new()
	pad.position = Vector3(27, 0, 13)
	pad.rotation.y = PI / 2.0      # lança para oeste, na direção do vão
	add_child(pad)
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.08
	mesh.radial_segments = 24
	disc.mesh = mesh
	disc.material_override = _flat(HOLO.darkened(0.35))
	disc.position.y = 0.04
	pad.add_child(disc)
	_sign("PARKOUR", Vector3(16, 9.0, 29.9), 96, false, PI)


## Defesa: o ponto onde ficar e o mezanino do atirador de cima.
func _defense() -> void:
	_block(Vector3(18, 3, -27.5), Vector3(20, 6, 5), "block")
	_ring(DEFENSE_SPOT, 1.2)
	_sign("DEFESA", DEFENSE_SPOT + Vector3(0, 0.25, 1.8), 56, true)


# ---------------------------------------------------------------- bonecos

## Deixa o jogador com cara de boneco de teste: corpo de holograma na cor tint; sem
## arma na mão, menos nos atiradores (keep_gun).
static func make_hologram(p: Player, tint := Color(0.45, 0.9, 1.0), keep_gun := false) -> void:
	if not _holo_mats.has(tint):
		var sh := Shader.new()
		sh.code = HOLO_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tint", tint)
		_holo_mats[tint] = mat
	for m in p.body_meshes:
		m.material_override = _holo_mats[tint]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if p.gun and not keep_gun:
		p.gun.get_parent().visible = false   # o encaixe da mão (a partida volta a mostrar a arma)


# ---------------------------------------------------------------- construção

## Caixa com colisão. kind: floor, wall, block (plataformas, com filetes nas quinas de cima)
## ou ceiling.
func _block(center: Vector3, size: Vector3, kind: String, edges := true) -> void:
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
	mi.material_override = _holo_material(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	nav.add_child(body)
	if edges:
		var top := center.y + size.y / 2.0
		_rect_strip(Rect2(center.x - size.x / 2.0, center.z - size.z / 2.0, size.x, size.z), top)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var c := Vector3(center.x + sx * size.x / 2.0, 0, center.z + sz * size.z / 2.0)
				_strip(Vector3(c.x, center.y - size.y / 2.0, c.z), Vector3(c.x, top, c.z))


## O vazio lá embaixo do buraco: plano escuro com a grade.
func _void_floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = PIT.size
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = HOLO.darkened(0.6)
	mat.albedo_texture = _holo_texture()
	mat.uv1_scale = Vector3(PIT.size.x / 2.0, PIT.size.y / 2.0, 1)
	plane.material = mat
	mi.position = Vector3(PIT.get_center().x, VOID_Y - 0.5, PIT.get_center().y)
	add_child(mi)


## Placa holográfica (texto ciano). on_floor: deitada no chão, lida de quem vem do sul.
func _sign(text: String, pos: Vector3, size: int, on_floor := false, turn := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Ui.bold()
	l.font_size = size
	l.outline_size = 0
	l.modulate = Color(HOLO, 0.9)
	l.pixel_size = 0.01
	l.position = pos
	l.rotation.y = turn
	if on_floor:
		l.rotation.x = -PI / 2.0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)


## Anel no chão marcando um lugar (bonecos, defesa).
func _ring(pos: Vector3, radius: float) -> void:
	var n := 24
	for i in n:
		var a := TAU * i / n
		var b := TAU * (i + 1) / n
		_strip(pos + Vector3(cos(a), 0, sin(a)) * radius, pos + Vector3(cos(b), 0, sin(b)) * radius)


## Contorno de um retângulo da planta (x, z) na altura y.
func _rect_strip(r: Rect2, y: float) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	for pair in [[a, b], [b, c], [c, d], [d, a]]:
		_strip(pair[0], pair[1])


## Filete de luz de a até b: uma caixa fina somada à malha única dos filetes.
func _strip(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		return
	var fwd := dir / length
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.01:
		side = fwd.cross(Vector3.RIGHT)
	side = side.normalized() * STRIP
	var up := side.cross(fwd).normalized() * STRIP
	var start := a - fwd * STRIP + up * 0.2   # levemente acima da superfície, sem brigar com ela
	var end := b + fwd * STRIP + up * 0.2
	var corners := []
	for s in [-1, 1]:
		for u in [-1, 1]:
			corners.append(side * s + up * u)
	# 4 faces compridas (as pontas não aparecem; o material desenha os dois lados).
	var quads := [[0, 1], [1, 3], [3, 2], [2, 0]]
	for q in quads:
		var c0: Vector3 = corners[q[0]]
		var c1: Vector3 = corners[q[1]]
		_strips.add_vertex(start + c0)
		_strips.add_vertex(end + c0)
		_strips.add_vertex(end + c1)
		_strips.add_vertex(start + c0)
		_strips.add_vertex(end + c1)
		_strips.add_vertex(start + c1)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


## Material das superfícies: azul-escuro que recebe luz, com a grade ciano acesa por cima
## (emissão, sem glow). A grade cobre 2 m e não estica com a peça.
func _holo_material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var colors := {"floor": FLOOR_COLOR, "wall": WALL_COLOR, "block": BLOCK_COLOR, "ceiling": CEIL_COLOR}
	var glow := {"floor": 0.55, "wall": 0.35, "block": 0.6, "ceiling": 0.15}
	var m := StandardMaterial3D.new()
	m.albedo_color = colors[kind]
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = HOLO
	m.emission_energy_multiplier = glow[kind]
	m.emission_texture = _holo_texture()
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # o padrão (somar) acendia a superfície toda
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_materials[kind] = m
	return m


## Grade da sala: linha a cada 1 m e uma mais fraca a cada 25 cm, em fundo preto (vira a
## máscara da emissão). 128 px para 2 m, com mipmaps.
static func _holo_texture() -> ImageTexture:
	if _holo_tex:
		return _holo_tex
	var n := 128
	var px := n / 2
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v := 0.0
			if x % (px / 4) == 0 or y % (px / 4) == 0:
				v = 0.18
			if x % px < 2 or y % px < 2:
				v = 1.0
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_holo_tex = ImageTexture.create_from_image(img)
	return _holo_tex
