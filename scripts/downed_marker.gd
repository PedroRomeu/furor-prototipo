class_name DownedMarker
extends Node3D
## Caído no 2x2 (2026-10-06): círculo no chão mostrando a área de reviver e, para o próprio
## time, um anel sobre o caído com o prazo (vermelho, esvaziando) e o reviver (verde,
## enchendo), e os segundos que faltam. O inimigo vê só o círculo, bem apagado (pedido do
## usuário: não atrapalhar quem joga contra). Quem está caído vê o anel no HUD, não aqui.
## Só visual; quem decide é Player._update_down.

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform float bleed = 1.0;
uniform float revive = 0.0;
uniform vec4 bleed_color : source_color = vec4(1.0, 0.3, 0.25, 1.0);
uniform vec4 revive_color : source_color = vec4(0.4, 1.0, 0.5, 1.0);
uniform float screen_size = 0.07;
void vertex() {
	// Sempre de frente para a câmera e do mesmo tamanho na tela, perto ou longe (de perto,
	// revivendo, ele cobria a tela).
	vec4 center = VIEW_MATRIX * MODEL_MATRIX[3];
	VERTEX *= max(0.5, length(center.xyz)) * screen_size;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Ângulo de 0 a 1 a partir do topo, no sentido horário.
	float a = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	vec4 c = vec4(0.0);
	if (r > 0.78 && r < 0.98) {
		c = a < bleed ? bleed_color : vec4(0.0, 0.0, 0.0, 0.45);
	} else if (r > 0.52 && r < 0.72 && revive > 0.0) {
		c = a < revive ? revive_color : vec4(0.0, 0.0, 0.0, 0.35);
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""
const ALLY_ALPHA := 0.45
const ENEMY_ALPHA := 0.12

static var _shader: Shader
static var _ring_mesh: TorusMesh
static var _quad: QuadMesh

var player: Player
var _floor_ring: MeshInstance3D
var _floor_mat: StandardMaterial3D
var _gauge: MeshInstance3D
var _gauge_mat: ShaderMaterial
var _label: Label3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.95
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 40
		_ring_mesh.ring_segments = 4
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_shader = Shader.new()
		_shader.code = RING_SHADER
	var color := player.color   # no 2x2, a cor do time
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_floor_mat.albedo_color = Color(color, ALLY_ALPHA)
	_floor_ring = MeshInstance3D.new()
	_floor_ring.mesh = _ring_mesh
	_floor_ring.material_override = _floor_mat
	_floor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_ring.scale = Vector3(Player.REVIVE_RADIUS, 1.0, Player.REVIVE_RADIUS)
	_floor_ring.position.y = 0.06
	add_child(_floor_ring)
	_gauge_mat = ShaderMaterial.new()
	_gauge_mat.shader = _shader
	_gauge = MeshInstance3D.new()
	_gauge.mesh = _quad
	_gauge.material_override = _gauge_mat
	_gauge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gauge.extra_cull_margin = 40.0   # o shader aumenta o quadrado de longe
	_gauge.position.y = 2.5   # acima do nome e da seta do aliado
	add_child(_gauge)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.font_size = 40
	_label.outline_size = 10
	_label.position.y = 2.5
	add_child(_label)
	_process(0.0)


func _process(_delta: float) -> void:
	var viewer := Player.viewer
	var own_team := viewer != null and (viewer == player or viewer.is_ally(player))
	_floor_mat.albedo_color.a = ALLY_ALPHA if own_team else ENEMY_ALPHA
	# Anel e número só para o parceiro (o caído vê no HUD).
	var show := own_team and viewer != player
	_gauge.visible = show
	_label.visible = show
	if show:
		_gauge_mat.set_shader_parameter("bleed", player.bleed_timer / maxf(0.01, player.bleed_total))
		_gauge_mat.set_shader_parameter("revive", player.revive_progress / Player.REVIVE_TIME)
		_label.text = str(ceili(player.bleed_timer))
