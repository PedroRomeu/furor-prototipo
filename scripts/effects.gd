class_name Effects
extends RefCounted
## Efeitos visuais simples, sem arquivos de arte. Animados por tween (fora da física),
## então ficam de fora da interpolação de física.


## Esfera que cresce até o raio e some. Usada em explosões, onda de choque e Fênix.
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, time := 0.3) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, 0.45)
	sphere.material = mat
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.1
	var tween := mi.create_tween().set_parallel()
	tween.tween_property(mi, "scale", Vector3.ONE * radius, time)
	tween.tween_property(mat, "albedo_color:a", 0.0, time)
	tween.chain().tween_callback(mi.queue_free)


## Número de dano que sobe e some. Crítico: amarelo e maior.
static func number(parent: Node, pos: Vector3, amount: float, crit := false) -> void:
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
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	var tween := l.create_tween().set_parallel()
	tween.tween_property(l, "global_position:y", l.global_position.y + 1.2, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.chain().tween_callback(l.queue_free)


## Faíscas que espirram do ponto e caem (impacto de bala em alguém).
static func sparks(parent: Node, pos: Vector3, color: Color, count := 8, speed := 6.0) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)   # brilha com o glow
	mesh.material = mat
	p.mesh = mesh
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
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(0.5).timeout.connect(p.queue_free)
