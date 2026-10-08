class_name MeteorStrike
extends Node3D
## Um meteoro da carta mestra Chuva de Meteoros: círculo no chão que se fecha por DELAY
## (o aviso, visível para todos) e o meteoro caindo de cima, ignorando telhados (escolha do
## usuário). No impacto, dano em área como as explosões: cada máquina só fere os
## jogadores dela; nunca quem atirou nem o parceiro dele.

const DELAY := 1.5
const FALL := 0.4          # o meteoro aparece nos últimos FALL segundos e cai
const FALL_HEIGHT := 30.0
const RADIUS := 4.0
# Dano no centro (50% na borda): DAMAGE_BASE + DAMAGE_SCALE x o dano da bala que marcou, até
# DAMAGE_MAX (2026-10-08, pedido do usuário: um pouco mais de dano, com escala e teto; era 35
# fixo). Arma base (25): 42,5; teto a partir de um tiro de 50.
const DAMAGE_BASE := 30.0
const DAMAGE_SCALE := 0.5
const DAMAGE_MAX := 55.0
const COLOR := Color(1.0, 0.5, 0.15)
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float progress = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float outer = smoothstep(0.9, 0.94, d) * (1.0 - smoothstep(0.97, 1.0, d));
	float r = 1.0 - progress;
	float inner = smoothstep(r - 0.06, r - 0.02, d) * (1.0 - smoothstep(r, r + 0.03, d));
	float fill = (1.0 - smoothstep(0.0, 1.0, d)) * 0.12 * progress;
	ALBEDO = vec3(1.0, 0.3, 0.1);
	ALPHA = max(max(outer * 0.8, inner * 0.9), fill);
}
"""

static var _ring_shader: Shader
static var _rock_mesh: SphereMesh
static var _rock_mat: StandardMaterial3D

var shooter: Player
var damage := DAMAGE_BASE
var t := 0.0
var _ring_mat: ShaderMaterial
var _rock: MeshInstance3D


static func damage_for(shot_damage: float) -> float:
	return minf(DAMAGE_BASE + DAMAGE_SCALE * maxf(shot_damage, 0.0), DAMAGE_MAX)


static func spawn(parent: Node, pos: Vector3, from: Player, dmg: float) -> void:
	var m := MeteorStrike.new()
	m.shooter = from
	m.damage = minf(dmg, DAMAGE_MAX)
	m.add_to_group("meteor_strikes")
	parent.add_child(m)
	m.global_position = pos


func _ready() -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
		_rock_mesh = SphereMesh.new()
		_rock_mesh.radius = 1.0
		_rock_mesh.height = 2.0
		_rock_mesh.radial_segments = 10
		_rock_mesh.rings = 6
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.albedo_color = Color(0.35, 0.2, 0.15)
		_rock_mat.emission_enabled = true
		_rock_mat.emission = COLOR
		_rock_mat.emission_energy_multiplier = 1.2
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	ring.mesh = quad
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = _ring_shader
	ring.material_override = _ring_mat
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_rock = MeshInstance3D.new()
	_rock.mesh = _rock_mesh
	_rock.material_override = _rock_mat
	_rock.scale = Vector3.ONE * 1.1
	_rock.visible = false
	_rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rock)


func _process(delta: float) -> void:
	t += delta
	_ring_mat.set_shader_parameter("progress", clampf(t / DELAY, 0.0, 1.0))
	var fall_start := DELAY - FALL
	if t >= fall_start:
		_rock.visible = true
		var k := clampf((t - fall_start) / FALL, 0.0, 1.0)
		_rock.position = Vector3(0.0, lerpf(FALL_HEIGHT, 0.5, k * k), 0.0)
	if t >= DELAY:
		_impact()
		queue_free()


func _impact() -> void:
	var pos := global_position + Vector3.UP * 0.5
	Effects.explosion(get_parent(), pos, RADIUS, COLOR)
	Effects.sparks(get_parent(), pos, COLOR, 16, 9.0)
	Sfx.at(get_parent(), "explosion", pos)
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.is_local or not p.alive or p == shooter:
			continue
		if is_instance_valid(shooter) and shooter.is_ally(p):
			continue
		var d := p.chest().distance_to(pos)
		if d > RADIUS + p.hit_radius():
			continue
		var away := p.chest() - pos
		away.y = 0.0
		p.knockback(away.normalized() * 6.0 + Vector3.UP * 4.0)
		p.take_area_damage(damage * (1.0 - 0.5 * clampf(d / RADIUS, 0.0, 1.0)), shooter if is_instance_valid(shooter) else null)
