class_name Pickup
extends Area3D
## Item no mapa que some ao ser pego e volta depois de um tempo.
## MOVE (orbe roxo, nos pontos altos): devolve os dashes no ar, zera a recarga do dash e
## dá um pulo extra no ar. HEALTH (cruz verde, no chão): cura um pouco. ARMOR (colete
## amarelo, raro): soma colete, que absorve dano antes da vida e não passa da rodada.
##
## Em rede cada máquina só testa o próprio jogador; quem pega avisa os outros pela arena
## (sinal taken), e eles escondem o item. Se dois pegarem no mesmo instante, os dois levam.

signal taken(index: int)

enum Kind { MOVE, HEALTH, ARMOR }

const RESPAWN := {Kind.MOVE: 6.0, Kind.HEALTH: 25.0, Kind.ARMOR: 30.0}
const HEAL := 30.0
const ARMOR := 25.0
const COLORS := {Kind.MOVE: Color(0.75, 0.6, 1.0), Kind.HEALTH: Color(0.35, 1.0, 0.45),
	Kind.ARMOR: Color(1.0, 0.8, 0.3)}

var kind := Kind.MOVE
var index := 0
var cooldown := 0.0
var visual: Node3D
var t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	cs.shape = sphere
	add_child(cs)
	visual = Node3D.new()
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # anima no _process
	add_child(visual)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLORS[kind]
	if kind == Kind.MOVE:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.32
		mesh.height = 0.64
		mesh.radial_segments = 8
		mesh.rings = 4
		mesh.material = mat
		mi.mesh = mesh
		visual.add_child(mi)
	elif kind == Kind.ARMOR:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.55, 0.65, 0.2)
		mesh.material = mat
		mi.mesh = mesh
		visual.add_child(mi)
	else:
		for size in [Vector3(0.7, 0.22, 0.22), Vector3(0.22, 0.7, 0.22)]:
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = size
			mesh.material = mat
			mi.mesh = mesh
			visual.add_child(mi)
	for mi in visual.get_children():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	if cooldown > 0.0:
		cooldown -= delta
		visual.visible = cooldown <= 0.0
		return
	for body in get_overlapping_bodies():
		var p := body as Player
		if p and p.is_local and p.alive and not p.frozen and _apply(p):
			take()
			taken.emit(index)
			return


func _process(delta: float) -> void:
	t += delta
	visual.rotation.y = t * 1.6
	visual.position.y = sin(t * 2.2) * 0.12


## Devolve se o jogador aproveitou (vida cheia não gasta a cura).
func _apply(p: Player) -> bool:
	if kind == Kind.HEALTH:
		if p.health >= p.stats["max_health"]:
			return false
		p.heal(HEAL)
	elif kind == Kind.ARMOR:
		if p.armor >= Player.ARMOR_MAX:
			return false
		p.armor = minf(Player.ARMOR_MAX, p.armor + ARMOR)
	else:
		p.refresh_movement()
	if p.is_human:
		Sfx.ui(p, "pickup")
	return true


func take() -> void:
	cooldown = RESPAWN[kind]
	visual.visible = false
