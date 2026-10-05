class_name KillFeed
extends VBoxContainer
## Feed de abates no canto superior direito, como no CS: "Matador [mira] Vítima", cada nome
## na cor do jogador, com quem ajudou ("+ Nome") em letra menor. Linha em que você matou ou
## morreu ganha borda clara. Cada linha fica SHOW_TIME segundos e some; no máximo MAX_LINES.
## Morte sem matador (a própria bala, por exemplo) mostra só o ícone e a vítima.

const SHOW_TIME := 5.0
const FADE_TIME := 0.4
const MAX_LINES := 5

var me: Player


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_kill(killer: Player, victim: Player, assist: Player = null) -> void:
	var line := PanelContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	var mine := me != null and (killer == me or victim == me)
	var style := Ui.box(Color(0.04, 0.045, 0.06, 0.72), 6,
		Color(1, 1, 1, 0.85) if mine else Color.TRANSPARENT, 2 if mine else 0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	line.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(row)
	if killer and killer != victim:
		row.add_child(_name(killer, 16))
		if assist:
			var plus := _text("+", 13, Color(1, 1, 1, 0.55))
			row.add_child(plus)
			row.add_child(_name(assist, 13))
	row.add_child(KillIcon.new())
	row.add_child(_name(victim, 16))
	add_child(line)
	while get_child_count() > MAX_LINES:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	var tween := line.create_tween()
	tween.tween_interval(SHOW_TIME)
	tween.tween_property(line, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(line.queue_free)


func _name(p: Player, size: int) -> Label:
	return _text(p.player_name, size, p.color.lightened(0.3))


func _text(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Ui.bold())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Mira pequena desenhada em código entre os nomes (sem depender de fonte com símbolos).
class KillIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var col := Color(1, 1, 1, 0.9)
		draw_arc(c, 5.0, 0.0, TAU, 20, col, 1.6, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 3.0, c + d * 8.0, col, 1.6, true)
