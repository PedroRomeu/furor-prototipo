class_name CardTimers
extends HBoxContainer
## Esperas das cartas comuns acima dos selos de estado (2026-10-11, pedido do usuário): o
## ícone da carta escurece de cima para baixo pelo que falta e some quando acaba. Meteoro,
## Regeneração e Segunda Pele contam em você; Flash, Atordoante e Troca-Troca, a proteção que
## você ganhou depois de levar um (Player.blind_guard / silence_guard / swap_lock).
##
## Desempenho: um ícone fixo por carta, só ligado ou desligado; cada um sai numa chamada de
## desenho (o shader faz fundo, ícone e escurecido; o que falta vai no self_modulate.r).

const SIZE := 34.0
const SHADER := "shader_type canvas_item;
varying float left;   // fração que falta (1 = cheio, 0 = acabou), do self_modulate.r
void vertex() {
	left = COLOR.r;   // no fragment o COLOR já vem multiplicado pela textura
}
void fragment() {
	vec2 uv = (UV - 0.14) / 0.72;
	float a = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0)
		a = texture(TEXTURE, uv).a;
	float dim = UV.y < left ? 0.42 : 1.0;
	vec3 bg = UV.y < left ? vec3(0.04, 0.045, 0.06) : vec3(0.16, 0.19, 0.25);
	COLOR = vec4(mix(bg, vec3(dim), a), 0.9);
}"

## [id da carta, função (Player) -> [falta, total]]; a ordem é a da fileira.
var _entries := []
var _icons := {}
static var _material: ShaderMaterial


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
	_entries = [
		["meteoro", func(p: Player): return [p.slam_cd, Player.SLAM_COOLDOWN] if p.stats["ground_slam"] > 0 else [0.0, 1.0]],
		["regeneracao", func(p: Player): return [p.regen_wait(), Player.REGEN_DELAY]],
		["segunda_pele", func(p: Player): return [p.skin_wait(), Player.SKIN_DELAY]],
		["flash", func(p: Player): return [p.blind_guard, p.blind_guard_total]],
		["atordoante", func(p: Player): return [p.silence_guard, Player.SILENCE_TIME + Player.SILENCE_GUARD]],
		["troca_troca", func(p: Player): return [p.swap_lock, Player.SWAP_DELAY + Player.SWAP_COOLDOWN]],
	]
	for e in _entries:
		var icon := TextureRect.new()
		icon.texture = CardDB.icon(e[0])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(SIZE, SIZE)
		icon.material = _material
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		add_child(icon)
		_icons[e[0]] = icon


func update_from(p: Player) -> void:
	for e in _entries:
		var icon: TextureRect = _icons[e[0]]
		var t: Array = e[1].call(p)
		var on: bool = t[0] > 0.0
		if icon.visible != on:
			icon.visible = on
		if on:
			icon.self_modulate = Color(clampf(t[0] / t[1], 0.0, 1.0), 1, 1, 1)
