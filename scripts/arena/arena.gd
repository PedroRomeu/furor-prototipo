class_name Arena
extends Node3D
## Gera uma arena aleatória a cada rodada. Cada peça é repetida girada em volta do centro,
## uma vez por jogador (2 cópias a 180 graus, 3 a 120, 4 a 90), então todos
## os lados são idênticos e ninguém começa com vantagem de mapa.
## O mesmo número (seed) gera sempre o mesmo mapa, o que vai servir para a rede:
## basta mandar o estilo e a seed para o outro jogador.
## Para criar um estilo novo: acrescente o nome em STYLES e um caso no match de build().
## A aparência (cores, texturas, céu) vem do tema (ArenaTheme), sorteado à parte pela seed.
##
## Altura conta: o pulo sobe ~2,2 m e a escalada de beirada alcança 2,2 m acima dos pés,
## então caixotes de ~2 m servem de degrau, um segundo andar 2,5 a 3 m acima de uma
## plataforma se alcança pulando e escalando, e as plataformas suspensas pelas
## plataformas de salto. Só rampas e elevadores entram no caminho dos bots.
##
## Vazio: abaixo do chão, em VOID_Y, fica o vazio (Player._void_bounce): quem cai quica e
## leva dano. Alguns mapas não têm muros nas bordas (OPEN_CHANCE) e alguns têm buracos no
## chão (PIT_CHANCE), também repetidos em volta do centro.

const STYLES := ["Pátio", "Ruínas", "Torres", "Fábrica"]
const WALL_HEIGHT := 18.0
const SPAWN_CLEAR := 6.0
const RAMP_ANGLE := 30.0
const VOID_Y := -1.0   # o vazio fica quase na altura do chão: voltar é quicar e andar
const OPEN_CHANCE := 0.4
const PIT_CHANCE := 0.5
const FLOOR_CELL := 2.0   # o chão com buracos é montado em faixas desta largura
## O chão desce até abaixo do vazio, como um penhasco: quem cai fica ao lado da parede e
## pode escalar de volta, sem um vão embaixo do mapa onde ficar preso.
const FLOOR_DEPTH := 8.0

var style_name := ""
var half := 35.0
var copies := 2
var spawns: Array[Transform3D] = []
var rng := RandomNumberGenerator.new()
var nav: NavigationRegion3D
var occupied: Array = []   # Vector3(x, z, raio) na planta, já com as cópias giradas
var palette: Dictionary      # o tema (ArenaTheme.THEMES): cores por papel, texturas, céu
var theme_name := ""
var open_edges := false
var pits: Array = []         # Vector3(x, z, raio) dos buracos no chão, já com as cópias giradas
var high_spots: Array = []   # topos de peças altas (só a fatia original), para o orbe de movimento
var pickups: Array = []      # Pickup, na mesma ordem em todas as máquinas
var _materials := {}
var _tex_by_color := {}   # cor do papel -> textura do papel (ver _material)


func build(style: int, seed_value: int, player_count := 2) -> void:
	rng.seed = seed_value
	copies = player_count
	style_name = STYLES[style]
	half = rng.randf_range(32.0, 42.0) + (copies - 2) * 4.0   # mais gente, arena maior
	palette = ArenaTheme.THEMES[ArenaTheme.pick(seed_value)]
	theme_name = palette["name"]
	for role in palette["tex"]:
		_tex_by_color[palette[role]] = palette["tex"][role]
	_setup_nav()
	# Cada um nasce na borda, olhando para o centro.
	var spawn_z := half - 4.0
	for k in copies:
		var turn := Basis(Vector3.UP, _angle(k))
		spawns.append(Transform3D(turn, turn * Vector3(0, 0.1, spawn_z)))
	_reserve(0.0, spawn_z, SPAWN_CLEAR)
	open_edges = rng.randf() < OPEN_CHANCE
	if rng.randf() < PIT_CHANCE:
		_pits(rng.randi_range(1, 2))
	_floor_and_walls()
	_void_plane()
	match style:
		0: _style_patio()
		1: _style_ruins()
		2: _style_towers()
		3: _style_factory()
	_pickups()
	# Malha de navegação para o bot achar caminho. Só o que é fixo entra nela.
	nav.bake_navigation_mesh(false)


func _setup_nav() -> void:
	nav = NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.5
	mesh.agent_max_slope = 40.0
	nav.navigation_mesh = mesh
	add_child(nav)


# ---------------------------------------------------------------- estilos

## Aberto: obstáculos espalhados, plataformas com rampa.
func _style_patio() -> void:
	_center_piece()
	for i in rng.randi_range(2, 3):
		_random_platform(rng.randf_range(3.0, 4.5), rng.randf_range(6.0, 8.0), false, rng.randf() < 0.5)
	_scatter(rng.randi_range(10, 14))
	_floating(rng.randi_range(1, 2))
	_jump_pads(rng.randi_range(2, 3))
	_sliders(rng.randi_range(0, 1))


## Labirinto aberto: muros numa grade, com vãos de 2 m em todo cruzamento (sempre há passagem).
func _style_ruins() -> void:
	var cell := 6.0
	var n := int((half - 2.0) / cell)
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			for along_x in [true, false]:
				var c := Vector3((gx + 0.5) * cell, 0, gz * cell) if along_x else Vector3(gx * cell, 0, (gz + 0.5) * cell)
				# Só uma fatia do mapa; as outras vêm das cópias giradas.
				var a := fposmod(atan2(c.z, c.x) + 0.0001, TAU)
				if a >= TAU / copies or Vector2(c.x, c.z).length() < 0.01:
					continue
				if absf(c.x) > half - 3.0 or absf(c.z) > half - 3.0:
					continue
				if rng.randf() > 0.38:
					continue
				if _in_pit_margin(c.x, c.z, 3.5):
					continue
				if copies > 2 and not _is_free(c.x, c.z, 2.0):
					continue
				if copies == 2 and Vector2(c.x, c.z).distance_to(Vector2(0, half - 4.0)) < SPAWN_CLEAR + 1.0:
					continue
				var tall := rng.randf() < 0.6
				var h := 4.5 if tall else 1.2
				c.y = h / 2.0
				var basis := Basis() if along_x else Basis(Vector3.UP, PI / 2.0)
				_pair(c, Vector3(cell - 2.0, h, 0.7), basis, palette["wall"] if tall else palette["cover"])
				_reserve(c.x, c.z, 2.5)
	_scatter(rng.randi_range(3, 5))
	_random_platform(rng.randf_range(3.0, 4.0), 6.0, false)
	_floating(1)
	_jump_pads(2)
	_sliders(rng.randi_range(0, 1))


## Vertical: torres com rampas e elevadores, às vezes uma ponte elevada no centro.
func _style_towers() -> void:
	if rng.randf() < 0.6:
		var h := 6.0
		_box(nav, Vector3(0, h - 0.25, 0), Vector3(8, 0.5, 8), Basis(), palette["cover"])
		_box(nav, Vector3(0, (h - 0.5) / 2.0, 0), Vector3(2, h - 0.5, 2), Basis(), palette["wall"])
		_ramp(Vector3(0, 0, 4), Vector3(0, 0, -1), h, 3.0, palette["wall"])
		high_spots.append(Vector3(0, h, -2.5))
		_reserve(0, 0, 4.0 + h / tan(deg_to_rad(RAMP_ANGLE)) + 1.0)
	else:
		_center_piece()
	for i in rng.randi_range(2, 3):
		_random_platform(rng.randf_range(5.0, 7.5), rng.randf_range(6.0, 8.0), rng.randf() < 0.6, true)
	_scatter(rng.randi_range(5, 7))
	_floating(rng.randi_range(2, 3))
	_jump_pads(3)


## Industrial: muros que deslizam, barras giratórias para pular e elevador.
func _style_factory() -> void:
	_spinners(rng.randi_range(1, 2))
	_sliders(rng.randi_range(2, 3))
	_random_platform(rng.randf_range(5.0, 6.5), 7.0, true, rng.randf() < 0.5)
	_scatter(rng.randi_range(6, 9))
	_floating(1)
	_jump_pads(2)


# ---------------------------------------------------------------- peças

func _center_piece() -> void:
	match rng.randi() % 3:
		0:
			_box(nav, Vector3(0, 1.5, 0), Vector3(4, 3, 4), Basis(Vector3.UP, rng.randf_range(0, PI)), palette["wall"])
			_reserve(0, 0, 4.0)
		1:
			# Muretas saindo do centro, uma por jogador.
			_pair(Vector3(0, 0.7, 2.8), Vector3(0.8, 1.4, 5.0), Basis(), palette["cover"])
			_reserve(0, 0, 5.5)


## Obstáculos soltos: muretas (dá para se esconder agachado), caixotes, pilares e paredes.
func _scatter(n: int) -> void:
	for i in n:
		var size: Vector3
		match rng.randi() % 4:
			0:
				size = Vector3(rng.randf_range(3, 7), rng.randf_range(1.1, 1.5), 1.0)
			1:
				var s := rng.randf_range(1.8, 2.8)
				size = Vector3(s, s, s)
			2:
				size = Vector3(1.6, rng.randf_range(5, 10), 1.6)
			_:
				size = Vector3(rng.randf_range(4, 8), rng.randf_range(3.0, 5.0), 0.8)
		var r := Vector2(size.x, size.z).length() / 2.0 + 1.2
		var spot := _find_spot(r)
		if spot == Vector2.INF:
			continue
		_reserve(spot.x, spot.y, r)
		var c: Color = palette["cover"] if size.y < 2.0 else palette["wall"]
		_pair(Vector3(spot.x, size.y / 2.0, spot.y), size, Basis(Vector3.UP, rng.randf_range(0, PI)), c)


## Plataforma elevada com rampa e, se pedir, um elevador do lado e um segundo andar
## (bloco menor em cima, alcançado pulando e escalando a beirada).
func _random_platform(h: float, size: float, with_elevator: bool, upper := false) -> void:
	var run := h / tan(deg_to_rad(RAMP_ANGLE))
	var r := size / 2.0 + run + 1.0
	var spot := _find_spot(r)
	if spot == Vector2.INF:
		return
	_reserve(spot.x, spot.y, r)
	var yaw := rng.randi_range(0, 3) * PI / 2.0
	var center := Vector3(spot.x, h / 2.0, spot.y)
	_pair(center, Vector3(size, h, size), Basis(Vector3.UP, yaw), palette["cover"])
	var dir := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	_ramp(Vector3(spot.x, 0, spot.y) - dir * (size / 2.0), dir, h, minf(size, 4.0), palette["wall"])
	if upper:
		# Fica na metade de trás, longe da rampa; 2,5 a 3 m acima da plataforma.
		var tier := rng.randf_range(2.5, 3.0)
		var back := Vector3(spot.x, h + tier / 2.0, spot.y) + dir * (size / 4.0)
		_pair(back, Vector3(size * 0.5, tier, size * 0.5), Basis(Vector3.UP, yaw), palette["wall"])
		high_spots.append(Vector3(back.x, h + tier, back.z))
	else:
		high_spots.append(Vector3(spot.x, h, spot.y) + dir * (size / 4.0))
	if with_elevator:
		var side := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var pos := Vector3(spot.x, 0, spot.y) + side * (size / 2.0 + 1.6)
		# A plataforma vai do nível do chão até o topo da torre.
		pos.y = (h - 0.45) / 2.0
		_mover_pair(pos, Vector3(3, 0.5, 3), Basis(), Vector3(0, (h - 0.05) / 2.0, 0), 6.0, 0.0, palette["moving"])


## Rampa que sobe na direção dir e termina em top_edge (ponto no chão sob a borda de cima).
func _ramp(top_edge: Vector3, dir: Vector3, h: float, width: float, c: Color) -> void:
	var a := deg_to_rad(RAMP_ANGLE)
	var center := top_edge - dir * (h / tan(a) / 2.0)
	center.y = h / 2.0 - 0.2 / cos(a)
	var yaw := atan2(-dir.x, -dir.z)
	_pair(center, Vector3(width, 0.4, h / sin(a)), Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, a), c)


func _sliders(n: int) -> void:
	for i in n:
		var width := rng.randf_range(4.0, 6.0)
		var amp := rng.randf_range(3.0, 6.0)
		var r := width / 2.0 + amp + 1.0
		var spot := _find_spot(r)
		if spot == Vector2.INF:
			continue
		_reserve(spot.x, spot.y, r)
		var yaw := rng.randi_range(0, 3) * PI / 2.0
		var axis := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		_mover_pair(Vector3(spot.x, 1.5, spot.y), Vector3(width, 3, 0.8), Basis(Vector3.UP, yaw),
			axis * amp, rng.randf_range(3.0, 6.0), 0.0, palette["moving"])


## Barras baixas que giram: dá para pular por cima, mas elas empurram quem fica no caminho.
func _spinners(n: int) -> void:
	for i in n:
		var length := rng.randf_range(8.0, 12.0)
		var r := length / 2.0 + 1.0
		var speed := rng.randf_range(0.8, 1.4)
		var size := Vector3(length, 1.0, 0.6)
		if i == 0 and _is_center_free(r):
			_reserve(0, 0, r)
			_mover_pair(Vector3(0, 0.5, 0), size, Basis(), Vector3.ZERO, 1.0, speed, palette["moving"])
			continue
		var spot := _find_spot(r)
		if spot == Vector2.INF:
			continue
		_reserve(spot.x, spot.y, r)
		_mover_pair(Vector3(spot.x, 0.5, spot.y), size, Basis(), Vector3.ZERO, 1.0, speed, palette["moving"])


## Plataformas suspensas: lajes no alto, alcançadas pelas plataformas de salto ou
## pulando de uma peça mais alta.
func _floating(n: int) -> void:
	for i in n:
		var size := Vector3(rng.randf_range(4.0, 6.0), 0.5, rng.randf_range(4.0, 6.0))
		var r := Vector2(size.x, size.z).length() / 2.0 + 1.0
		var spot := _find_spot(r)
		if spot == Vector2.INF:
			continue
		_reserve(spot.x, spot.y, r)
		var y := rng.randf_range(5.0, 7.0)
		_pair(Vector3(spot.x, y, spot.y), size, Basis(Vector3.UP, rng.randf_range(0, PI)), palette["cover"])
		high_spots.append(Vector3(spot.x, y + 0.25, spot.y))


## Itens: nem todo mapa tem. O orbe de movimento flutua acima de um ponto alto (pega-se
## no meio de um pulo; parado em cima o chão já devolveria tudo); a vida fica no chão.
## Um de cada por jogador, nas cópias giradas. O colete é o mais raro.
func _pickups() -> void:
	if not high_spots.is_empty() and rng.randf() < 0.75:
		var top: Vector3 = high_spots[rng.randi() % high_spots.size()]
		_pickup_pair(top + Vector3.UP * 1.6, Pickup.Kind.MOVE)
	if rng.randf() < 0.5:
		var spot := _find_spot(1.2)
		if spot != Vector2.INF:
			_reserve(spot.x, spot.y, 1.2)
			_pickup_pair(Vector3(spot.x, 0.8, spot.y), Pickup.Kind.HEALTH)
	# Colete: raro, num lugar exposto (ao ar livre, longe de quem nasce).
	if rng.randf() < 0.35:
		var spot := _find_spot(1.2)
		if spot != Vector2.INF:
			_reserve(spot.x, spot.y, 1.2)
			_pickup_pair(Vector3(spot.x, 0.8, spot.y), Pickup.Kind.ARMOR)


func _pickup_pair(pos: Vector3, kind: Pickup.Kind) -> void:
	for k in copies:
		var item := Pickup.new()
		item.kind = kind
		item.index = pickups.size()
		item.position = _rot(pos, k)
		pickups.append(item)
		add_child(item)


func _jump_pads(n: int) -> void:
	for i in n:
		var spot := _find_spot(1.8)
		if spot == Vector2.INF:
			continue
		_reserve(spot.x, spot.y, 1.8)
		for k in copies:
			var pos := _rot(Vector3(spot.x, 0, spot.y), k)
			var pad := JumpPad.new()
			pad.position = pos
			pad.rotation.y = atan2(pos.x, pos.z)   # a frente (-Z) aponta para o centro
			var mi := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 1.0
			disc.bottom_radius = 1.0
			disc.height = 0.1
			var mat := StandardMaterial3D.new()
			mat.albedo_color = palette["accent"]
			mat.emission_enabled = true
			mat.emission = palette["accent"]
			mat.emission_energy_multiplier = 0.12   # só o bastante para achar na sombra, sem brilhar
			disc.material = mat
			mi.mesh = disc
			mi.position.y = 0.05
			pad.add_child(mi)
			add_child(pad)


## Buracos redondos no chão, fora do caminho de quem nasce. Peças não ficam por cima.
func _pits(n: int) -> void:
	for i in n:
		var r := rng.randf_range(2.5, 4.5)
		var spot := _find_spot(r + 1.0)
		if spot == Vector2.INF:
			continue
		_reserve(spot.x, spot.y, r + 1.0)
		for k in copies:
			var p := _rot(Vector3(spot.x, 0, spot.y), k)
			pits.append(Vector3(p.x, p.z, r))


func _in_pit(x: float, z: float) -> bool:
	return _in_pit_margin(x, z, 0.0)


func _in_pit_margin(x: float, z: float, margin: float) -> bool:
	for p in pits:
		if Vector2(x, z).distance_to(Vector2(p.x, p.y)) < p.z + margin:
			return true
	return false


## Chão (inteiro, ou em faixas quando há buracos) e, se o mapa não for aberto, os muros.
func _floor_and_walls() -> void:
	var size := half * 2.0
	if pits.is_empty():
		_box(nav, Vector3(0, -FLOOR_DEPTH / 2.0, 0), Vector3(size, FLOOR_DEPTH, size), Basis(), palette["floor"])
	else:
		_floor_with_pits()
	if open_edges:
		return
	var y := WALL_HEIGHT / 2.0
	_box(nav, Vector3(0, y, half + 0.5), Vector3(size + 2, WALL_HEIGHT, 1), Basis(), palette["wall"])
	_box(nav, Vector3(0, y, -half - 0.5), Vector3(size + 2, WALL_HEIGHT, 1), Basis(), palette["wall"])
	_box(nav, Vector3(half + 0.5, y, 0), Vector3(1, WALL_HEIGHT, size), Basis(), palette["wall"])
	_box(nav, Vector3(-half - 0.5, y, 0), Vector3(1, WALL_HEIGHT, size), Basis(), palette["wall"])


## Divide o chão numa grade; em cada fileira junta as células cheias em trechos, e
## fileiras seguidas com os mesmos trechos viram uma caixa só (poucas peças para desenhar).
func _floor_with_pits() -> void:
	var n := int(ceil(half * 2.0 / FLOOR_CELL))
	var cell := half * 2.0 / n
	var rows: Array = []
	for iz in n:
		var z := -half + (iz + 0.5) * cell
		var runs: Array = []
		var start := -1
		for ix in n + 1:
			var hole := ix == n or _in_pit(-half + (ix + 0.5) * cell, z)
			if not hole and start < 0:
				start = ix
			elif hole and start >= 0:
				runs.append(Vector2i(start, ix))
				start = -1
		rows.append(runs)
	var iz := 0
	while iz < n:
		var last := iz
		while last + 1 < n and rows[last + 1] == rows[iz]:
			last += 1
		for run in rows[iz]:
			var x0: float = -half + run.x * cell
			var x1: float = -half + run.y * cell
			var z0 := -half + iz * cell
			var z1 := -half + (last + 1) * cell
			_box(nav, Vector3((x0 + x1) / 2.0, -FLOOR_DEPTH / 2.0, (z0 + z1) / 2.0), Vector3(x1 - x0, FLOOR_DEPTH, z1 - z0),
				Basis(), palette["floor"])
		iz = last + 1


## O vazio: um plano escuro lá embaixo, só visual (quem cai quica em Player._void_bounce).
## Aparece só onde há por onde cair.
func _void_plane() -> void:
	if pits.is_empty() and not open_edges:
		return
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = palette["void"]
	mat.albedo_texture = ArenaTheme.texture("grid")
	mat.uv1_scale = Vector3(150, 150, 1)
	plane.material = mat
	mi.mesh = plane
	mi.position.y = VOID_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- construção

func _angle(k: int) -> float:
	return TAU * k / copies


func _rot(p: Vector3, k: int) -> Vector3:
	return Basis(Vector3.UP, _angle(k)) * p


## Cria a peça e as cópias giradas em volta do centro do mapa (uma por jogador).
func _pair(center: Vector3, size: Vector3, basis: Basis, c: Color) -> void:
	var n := copies if Vector2(center.x, center.z).length() > 0.01 else 1
	for k in n:
		_box(nav, _rot(center, k), size, Basis(Vector3.UP, _angle(k)) * basis, c)


## Peças móveis ficam fora da região de navegação (não entram na malha do bot).
func _mover_pair(center: Vector3, size: Vector3, basis: Basis, offset: Vector3,
		period: float, spin: float, c: Color) -> void:
	var n := copies if Vector2(center.x, center.z).length() > 0.01 else 1
	for k in n:
		var body := MovingBody.new()
		var pos := _rot(center, k)
		_box(self, pos, size, Basis(Vector3.UP, _angle(k)) * basis, c, body)
		body.base = pos
		body.offset = _rot(offset, k)
		body.period = period
		body.spin = spin


func _box(parent: Node, center: Vector3, size: Vector3, basis: Basis, c: Color,
		body: PhysicsBody3D = null) -> PhysicsBody3D:
	if body == null:
		body = StaticBody3D.new()
	body.transform = Transform3D(basis, center)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _material(c)
	body.add_child(mi)
	parent.add_child(body)
	return body


func _reserve(x: float, z: float, r: float) -> void:
	var n := copies if Vector2(x, z).length() > 0.01 else 1
	for k in n:
		var p := _rot(Vector3(x, 0, z), k)
		occupied.append(Vector3(p.x, p.z, r))


func _is_center_free(r: float) -> bool:
	for o in occupied:
		if Vector2(o.x, o.y).length() < r + o.z:
			return false
	return true


func _is_free(x: float, z: float, r: float) -> bool:
	var limit := half - 1.0 - r
	for k in copies:
		var q := _rot(Vector3(x, 0, z), k)
		if absf(q.x) > limit or absf(q.z) > limit:
			return false
	var p := Vector2(x, z)
	if p.length() < r / sin(PI / copies) + 0.5:
		return false   # encostaria nas próprias cópias giradas
	for o in occupied:
		if p.distance_to(Vector2(o.x, o.y)) < r + o.z:
			return false
	return true


func _find_spot(r: float) -> Vector2:
	for i in 40:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if _is_free(x, z, r):
			return Vector2(x, z)
	return Vector2.INF


## Material com a textura do papel da cor (chão, muro...) em coordenadas do mundo:
## a textura cobre 2 m e não estica com o tamanho da peça.
func _material(c: Color) -> StandardMaterial3D:
	if _materials.has(c):
		return _materials[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = ArenaTheme.texture(_tex_by_color.get(c, "grid"))
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_materials[c] = m
	return m
