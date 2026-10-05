class_name LookPreview
extends SubViewportContainer
## Personagem em 3D da tela Personalizar, com a arma na mão como na partida. Arrastar com
## o mouse gira o modelo. Só desenha enquanto está na tela (o SubViewport para sozinho
## quando o painel some), para não pesar no menu.

const DRAG_SPEED := 0.01
const START_YAW := deg_to_rad(55.0)

var viewport: SubViewport
var pivot: Node3D
var model: Node3D
var _yaw := START_YAW
var _skin := ""
var _gun := ""


func _ready() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.9
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.2, 6.6)
	viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	# Disco escuro embaixo dos pés, como um pedestal.
	var floor_disc := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.02
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = mat
	floor_disc.mesh = disc
	viewport.add_child(floor_disc)
	pivot = Node3D.new()
	viewport.add_child(pivot)


func show_look(skin: String, gun: String) -> void:
	if skin == _skin and gun == _gun and model:
		return
	_skin = skin
	_gun = gun
	if model:
		model.queue_free()
	model = load(Player.skin_model(skin)).instantiate()
	model.scale = Vector3.ONE * Player.MODEL_SCALE
	# Os modelos olham para +Z, que é para a câmera.
	pivot.add_child(model)
	var anim: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	# Arma na mão, com o braço levantado, igual ao _build_body do Player.
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var arm := AimArm.new()
	arm.pitch = -0.15
	skeleton.add_child(arm)
	var hand := BoneAttachment3D.new()
	hand.bone_name = "arm-right"
	skeleton.add_child(hand)
	var g: Node3D = load(Player.gun_model(gun)).instantiate()
	g.scale = Vector3.ONE * (1.3 / Player.MODEL_SCALE)
	g.rotation.x = -PI / 2.0
	g.position = Vector3(0, -0.13, 0.04)
	hand.add_child(g)
	pivot.rotation.y = _yaw


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw += motion.relative.x * DRAG_SPEED
		pivot.rotation.y = _yaw
		accept_event()
