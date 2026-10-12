class_name ShadowClone
extends CharacterBody3D
## Clone da mestra Clone (2026-10-12, caminho A escolhido pelo usuário: o Clone Sombra, com 8 s
## e andando devagar para a frente, pedidos dele). Igual ao dono para os outros (modelo, arma,
## nome e a vida dele no rótulo). Anda a SPEED na direção em que o dono olhava, com gravidade,
## para nas paredes e some no vazio. Enquanto existe, cada tiro do dono também sai daqui
## (Player._volley, metade do dano). Balas inimigas o acertam (Bullet._clone_on_segment):
## todas as máquinas param a bala, só a máquina do dono tira vida e, zerada, avisa as outras.
## Cada máquina simula o próprio clone a partir do mesmo ponto e direção (a diferença é a do
## atraso da rede); a troca de lugar usa a posição na máquina do dono.

const SPEED := 2.5
const LIFE := 8.0
const HEALTH := 40.0
const GRAVITY := 42.0
const RADIUS := 0.45

var owner_p: Player
var dir := Vector3.FORWARD
var life := LIFE
var health := HEALTH
var model: Node3D
var anim: AnimationPlayer
var tag: Label3D
var gun: Node3D


static func spawn(p: Player, pos: Vector3, look: Vector3) -> ShadowClone:
	var c := ShadowClone.new()
	c.owner_p = p
	c.dir = Vector3(look.x, 0.0, look.z).normalized() if Vector2(look.x, look.z).length() > 0.01 else Vector3.FORWARD
	c.position = pos
	p.get_parent().add_child(c)
	return c


func _ready() -> void:
	add_to_group("shadow_clones")
	collision_layer = 0   # jogadores e balas passam (as balas testam o clone à parte)
	collision_mask = 1
	var body_scale: float = owner_p.stats["body_scale"]
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = Player.STAND_HEIGHT * body_scale
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	add_child(shape)
	rotation.y = atan2(-dir.x, -dir.z)
	var id: String = owner_p.skin if owner_p.skin in Player.skin_ids() else String(Player.SKINS[owner_p.side % Player.SKINS.size()][0])
	model = load(Player.skin_model(id)).instantiate()
	model.scale = Vector3.ONE * Player.MODEL_SCALE * body_scale
	model.rotation.y = PI
	add_child(model)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	if anim.has_animation("walk"):
		anim.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
		anim.play("walk")
		anim.speed_scale = 0.5   # passo lento, como o andar
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	owner_p._rigidify(skeleton, Player.skin_model(id))
	skeleton.add_child(AimArm.new())
	var hand := BoneAttachment3D.new()
	hand.bone_name = "arm-right"
	skeleton.add_child(hand)
	gun = load(Player.gun_model(owner_p.gun_skin)).instantiate()
	gun.scale = Vector3.ONE * (1.3 / Player.MODEL_SCALE)
	gun.rotation = Player.HAND_ROT
	gun.position = Player.HAND_POS
	hand.add_child(gun)
	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.outline_size = 8
	tag.modulate = owner_p.color.lightened(0.5)   # como o rótulo do jogador
	tag.position.y = Player.STAND_HEIGHT * body_scale + 0.5
	add_child(tag)
	Effects.burst(get_parent(), global_position + Vector3.UP, 1.4, Player.CLONE_COLOR, 0.2)


## Ponto de onde saem os tiros do eco (a arma na mão, ou o peito se ela sumiu).
func muzzle() -> Vector3:
	if is_instance_valid(gun):
		return gun.global_position - global_transform.basis.z * 0.3
	return chest()


func chest() -> Vector3:
	return global_position + Vector3.UP * Player.STAND_HEIGHT * 0.66 * float(owner_p.stats["body_scale"])


## Eixo do corpo para o teste das balas: pés e cabeça.
func axis() -> Array:
	var h := Player.STAND_HEIGHT * float(owner_p.stats["body_scale"])
	return [global_position + Vector3.UP * 0.2, global_position + Vector3.UP * (h - 0.2)]


func hit_radius() -> float:
	return RADIUS * float(owner_p.stats["body_scale"])


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_p):
		queue_free()
		return
	life -= delta
	if life <= 0.0:
		vanish()
		return
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if global_position.y < Arena.VOID_Y:
		vanish()
		return
	# Para os outros parece você: o seu nome e a sua vida (para você, "Clone" e a dele).
	if owner_p == Player.viewer:
		tag.text = "Clone\n%d" % ceili(health)
	else:
		tag.text = "%s\n%d" % [owner_p.player_name, ceili(owner_p.health)]


## Uma bala inimiga bateu: só a máquina do dono tira vida (as outras só mostram o impacto).
func take_bullet(dmg: float, point: Vector3) -> void:
	Effects.burst(get_parent(), point, 0.5, Player.CLONE_COLOR, 0.12)
	if not owner_p.is_local:
		return
	health -= dmg
	if health <= 0.0:
		owner_p.clone_destroyed()


## Some com um estouro (tempo, vazio, destruído ou troca de lugar).
func vanish() -> void:
	if is_queued_for_deletion():
		return
	Effects.burst(get_parent(), chest(), 1.2, Player.CLONE_COLOR, 0.2)
	remove_from_group("shadow_clones")
	queue_free()
	if is_instance_valid(owner_p) and owner_p.clone == self:
		owner_p.clone = null
