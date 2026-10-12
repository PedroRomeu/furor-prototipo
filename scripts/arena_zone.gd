class_name ArenaZone
extends MeshInstance3D
## Parede de vidro da Prorrogação (Overtime): cilindro aberto em volta do centro, do fundo do
## penhasco até acima do teto das balas, encolhido pela escala. Uma chamada de desenho, sem
## colisão (balas e jogadores passam; o dano fora é do Player._zone_check). Shader barato:
## translúcido, grade fina, borda mais forte de lado (fresnel) e uma faixa clara que desce.

const BOTTOM := -10.0
const TOP := 40.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 1.0);
varying float wy;
void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	vec2 g = abs(fract(vec2(UV.x * 64.0, wy / 3.0)) - 0.5);
	float line = smoothstep(0.44, 0.5, max(g.x, g.y));
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	float sweep = smoothstep(0.9, 1.0, fract(-wy / 24.0 + TIME * 0.25));
	ALBEDO = tint.rgb;
	ALPHA = 0.07 + 0.22 * line + 0.3 * edge * edge * edge + 0.08 * sweep;
}
"""

static var _mesh: CylinderMesh
static var _mat: ShaderMaterial


func _ready() -> void:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = 1.0
		_mesh.bottom_radius = 1.0
		_mesh.height = TOP - BOTTOM
		_mesh.radial_segments = 96
		_mesh.rings = 1
		_mesh.cap_top = false
		_mesh.cap_bottom = false
		_mat = ShaderMaterial.new()
		_mat.shader = Shader.new()
		_mat.shader.code = SHADER
		_mat.set_shader_parameter("tint", Player.ZONE_COLOR)
	mesh = _mesh
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = (TOP + BOTTOM) / 2.0
	visible = false


## INF esconde.
func set_radius(r: float) -> void:
	visible = r < INF
	if visible:
		scale = Vector3(r, 1.0, r)
