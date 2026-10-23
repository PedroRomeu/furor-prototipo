class_name Barrier
extends Node3D
## Parede do Bastião (carta mestra de Escudo): painel de energia em pé, de frente para onde
## o dono olhava. Devolve as balas dos outros (o teste é em bullet.gd, _check_barriers);
## as do dono e os jogadores passam. Some sozinha depois de TIME.
## Reforço de 2026-10-23 (pedido do usuário: não era ruim, mas faltava algo): a bala devolvida
## volta com REFLECT_MULT do dano, e Q de novo empurra a parede PUSH_DIST para a frente em
## PUSH_TIME; quem ela atropelar leva o dano de RAM_DAMAGE (x master_scale() do dono) e é
## empurrado, uma vez por empurrão. A parede atravessa o cenário (é energia). Quem decide o
## atropelo é a máquina do dono; a da vítima aplica (Player.receive_wall_ram).

const TIME := 4.0
const WIDTH := 4.0
const HEIGHT := 3.2
const COLOR := Color(0.4, 0.9, 1.0)
const REFLECT_MULT := 1.5
const PUSH_DIST := 10.0
const PUSH_TIME := 0.5
const PUSH_LOCK := 0.3   # Q logo depois de levantar não empurra (o mesmo toque não vale duas vezes)
const RAM_DAMAGE := 25.0
const RAM_DEPTH := 0.9   # alcance à frente e atrás do painel que conta como atropelo

var owner_player: Player
var life := TIME
var glow := 0.0
var material: StandardMaterial3D
var pushed := false
var push_left := 0.0
var ram_damage := RAM_DAMAGE
var _rammed: Array = []


func _ready() -> void:
	add_to_group("barriers")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(WIDTH, HEIGHT, 0.08)
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = HEIGHT / 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Só o desenho cresce ao surgir; a área que devolve as balas vale desde o começo.
	mi.scale = Vector3(1, 0.05, 1)
	create_tween().tween_property(mi, "scale", Vector3.ONE, 0.15)
	_paint()


func _process(delta: float) -> void:
	life -= delta
	glow = maxf(0.0, glow - delta * 4.0)
	if life <= 0.0:
		queue_free()
		return
	if push_left > 0.0:
		_push_step(delta)
	_paint()


func _paint() -> void:
	var fade := clampf(life / 0.5, 0.0, 1.0)   # some no último meio segundo
	material.albedo_color = Color(COLOR, (0.22 + glow * 0.5) * fade)


func flash() -> void:
	glow = 1.0
	Effects.burst(get_parent(), global_position + Vector3.UP * HEIGHT * 0.5, 1.0, COLOR, 0.15)


func can_push() -> bool:
	return not pushed and life < TIME - PUSH_LOCK


## Q de novo (em todas as máquinas; dmg vem do dono).
func push(dmg: float) -> void:
	pushed = true
	push_left = PUSH_TIME
	ram_damage = dmg
	glow = 1.0
	Sfx.at(get_parent(), "dash", global_position + Vector3.UP * HEIGHT * 0.5)


func _forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _push_step(delta: float) -> void:
	var step := minf(delta, push_left)
	push_left -= step
	var dir := _forward()
	global_position += dir * (PUSH_DIST / PUSH_TIME) * step
	glow = maxf(glow, 0.6)
	if not is_instance_valid(owner_player) or not owner_player.is_local:
		return
	var inv := global_transform.affine_inverse()
	for enemy: Player in owner_player.enemies():
		if enemy in _rammed:
			continue
		var p := inv * enemy.chest()
		if absf(p.x) > WIDTH / 2.0 + enemy.hit_radius() or p.y < -0.5 or p.y > HEIGHT + 0.5 \
				or absf(p.z) > RAM_DEPTH:
			continue
		_rammed.append(enemy)
		enemy.remote_call("receive_wall_ram", [String(owner_player.name), dir, ram_damage])
		Effects.burst(get_parent(), enemy.chest(), 1.3, COLOR, 0.15)


## Ponto onde o trecho from-to atravessa o painel, ou null.
func crossing(from: Vector3, to: Vector3) -> Variant:
	var inv := global_transform.affine_inverse()
	var a := inv * from
	var b := inv * to
	if (a.z > 0.0) == (b.z > 0.0) or is_equal_approx(a.z, b.z):
		return null
	var p := a.lerp(b, a.z / (a.z - b.z))
	if absf(p.x) > WIDTH / 2.0 or p.y < 0.0 or p.y > HEIGHT:
		return null
	return global_transform * p
