class_name Effects
extends RefCounted
## Efeitos visuais simples, sem arquivos de arte. Animados por tween (fora da física),
## então ficam de fora da interpolação de física.
##
## Desempenho (2026-10-05, builds de muitas balas travavam PCs fracos): malhas e materiais
## são compartilhados em vez de criados a cada efeito, e cada tipo tem um teto de efeitos
## ao mesmo tempo (BUDGET). Passou do teto, o efeito novo não aparece: numa chuva de balas
## ninguém nota um clarão a menos, mas nota o jogo travar. Na qualidade Baixa o teto cai
## pela metade. Explosões têm teto próprio, separado dos clarões pequenos.

const BUDGET := {"burst": 36, "explosion": 14, "sparks": 16, "number": 20}

static var _live := {}
static var _sphere: SphereMesh
static var _cube: BoxMesh
static var _spark_mats := {}


## Check-up de desempenho (scripts/dev/checkup.gd): tipos de efeito desligados.
static var disabled_kinds: Array = []


static func _allowed(kind: String) -> bool:
	if kind in disabled_kinds:
		return false
	var limit: int = BUDGET[kind]
	if GameState.quality == 0:
		limit = maxi(1, limit / 2)
	return _live.get(kind, 0) < limit


## Conta o efeito enquanto ele existe (some sozinho ou junto com a arena).
static func _track(node: Node, kind: String) -> void:
	_live[kind] = _live.get(kind, 0) + 1
	node.tree_exiting.connect(func(): _live[kind] = maxi(0, _live.get(kind, 1) - 1))


## Solta as malhas e materiais compartilhados e zera as contas (fim da partida).
static func clear_cache() -> void:
	_sphere = null
	_cube = null
	_spark_mats.clear()
	_live.clear()


## Esfera de poucos polígonos: a padrão do Godot tem 64 x 32 faixas, demais para um clarão.
static func sphere_mesh() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 16
		_sphere.rings = 8
	return _sphere


## Esfera que cresce até o raio e some. Usada em explosões, onda de choque e Fênix.
## A partir de 1,5 m conta como explosão (teto próprio).
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, time := 0.3) -> void:
	var kind := "explosion" if radius >= 1.5 else "burst"
	if not _allowed(kind):
		return
	var mi := MeshInstance3D.new()
	# O material é de cada clarão porque a transparência anima; a malha é uma só.
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, 0.45)
	mi.mesh = sphere_mesh()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_track(mi, kind)
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.1
	var tween := mi.create_tween().set_parallel()
	tween.tween_property(mi, "scale", Vector3.ONE * radius, time)
	tween.tween_property(mat, "albedo_color:a", 0.0, time)
	tween.chain().tween_callback(mi.queue_free)


## Explosão: o dano é instantâneo e cobre o raio todo, então o clarão já nasce grande (70%)
## e chega ao raio real em 0,1 s antes de desbotar. O burst cresce de 0,1 enquanto some e
## parecia bem menor que a área de dano (2026-10-07).
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color, time := 0.35) -> void:
	if not _allowed("explosion"):
		return
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Só a face de trás, com a opacidade de duas camadas (check-up de 2026-10-08: as duas
	# faces pintavam cada pixel duas vezes; 7 explosões de 6 m custavam +4,4 ms, assim +1,2).
	# A face de trás aparece por fora e de dentro da explosão.
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.albedo_color = Color(color, 0.75)
	mi.mesh = sphere_mesh()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_track(mi, "explosion")
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * radius * 0.7
	var tween := mi.create_tween().set_parallel()
	tween.tween_property(mi, "scale", Vector3.ONE * radius, 0.1)
	tween.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)


## Feixe reto que some rápido (o tiro da Sniper): uma fita virada para a câmera, como os
## rastros das balas, para aparecer de qualquer ângulo (um cilindro fino visto de ponta,
## na direção da mira, quase sumia).
static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, width := 0.07, time := 0.45) -> void:
	if from.distance_to(to) < 0.01:
		return
	var b := Beam.new()
	b.a = from
	b.b = to
	b.width = width
	b.total = time
	b.life = time
	b.color = color
	parent.add_child(b)


## Arco de um corte de espada: faixa curva na horizontal, na frente do corpo, que some
## rápido. to_right: varre da esquerda para a direita (o desenho é o mesmo; muda o brilho).
static func slash(parent: Node, center: Vector3, forward: Vector3, right: Vector3, radius: float,
		to_right: bool, color: Color, time := 0.22, strength := 1.0, inner := 0.6) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var n := 14
	var span := deg_to_rad(65.0)
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a0 := lerpf(-span, span, t0)
		var a1 := lerpf(-span, span, t1)
		# Mais forte no fim do movimento (para onde a lâmina foi).
		var w0 := t0 if to_right else 1.0 - t0
		var w1 := t1 if to_right else 1.0 - t1
		var d0 := forward.rotated(Vector3.UP, -a0)
		var d1 := forward.rotated(Vector3.UP, -a1)
		var c0 := Color(color, (0.06 + 0.34 * w0) * strength)
		var c1 := Color(color, (0.06 + 0.34 * w1) * strength)
		var in0 := center + d0 * radius * inner
		var out0 := center + d0 * radius
		var in1 := center + d1 * radius * inner
		var out1 := center + d1 * radius
		for v in [[in0, c0], [out0, c0], [out1, c1], [in0, c0], [out1, c1], [in1, c1]]:
			im.surface_set_color(v[1])
			im.surface_add_vertex(v[0])
	im.surface_end()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.top_level = true
	parent.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	var tween := mi.create_tween()
	tween.tween_property(mi, "transparency", 1.0, time)
	tween.tween_callback(mi.queue_free)


class Beam extends MeshInstance3D:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var width := 0.07
	var total := 0.45
	var life := 0.45
	var color := Color.WHITE
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()

	func _ready() -> void:
		mesh = im
		top_level = true
		global_transform = Transform3D.IDENTITY
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_draw_ribbon()

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		_draw_ribbon()

	func _draw_ribbon() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var k := clampf(life / total, 0.0, 1.0)
		var eye := cam.global_position
		var dir := b - a
		var side_a := dir.cross(eye - a)
		var side_b := dir.cross(eye - b)
		if side_a.length_squared() < 0.000001 or side_b.length_squared() < 0.000001:
			return
		# Mais fina na saída: perto da câmera a perspectiva a deixaria larga demais.
		side_a = side_a.normalized() * width * 0.25 * (0.4 + 0.6 * k)
		side_b = side_b.normalized() * width * (0.4 + 0.6 * k)
		mat.albedo_color = Color(color, 0.95 * k)
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for v in [a + side_a, a - side_a, b + side_b, a - side_a, b - side_b, b + side_b]:
			im.surface_add_vertex(v)
		im.surface_end()


## Número de dano que sobe e some. Crítico: amarelo e maior.
static func number(parent: Node, pos: Vector3, amount: float, crit := false) -> void:
	if not _allowed("number"):
		return
	var l := Label3D.new()
	l.text = str(roundi(amount)) + ("!" if crit else "")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011 if crit else 0.0008
	l.font_size = 48
	l.outline_size = 12
	l.modulate = Color(1.0, 0.85, 0.2) if crit else Color(1, 1, 1)
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_track(l, "number")
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	var tween := l.create_tween().set_parallel()
	tween.tween_property(l, "global_position:y", l.global_position.y + 1.2, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.chain().tween_callback(l.queue_free)


## Faíscas que espirram do ponto e caem (impacto de bala em alguém).
static func sparks(parent: Node, pos: Vector3, color: Color, count := 8, speed := 6.0) -> void:
	if not _allowed("sparks"):
		return
	if _cube == null:
		_cube = BoxMesh.new()
		_cube.size = Vector3.ONE * 0.05
	var p := CPUParticles3D.new()
	p.mesh = _cube
	p.material_override = _spark_material(color)
	p.amount = count
	p.lifetime = 0.25
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_track(p, "sparks")
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(0.5).timeout.connect(p.queue_free)


static func _spark_material(color: Color) -> StandardMaterial3D:
	if not _spark_mats.has(color):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)   # brilha com o glow
		_spark_mats[color] = mat
	return _spark_mats[color]
