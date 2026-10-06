class_name ModePicker
extends VBoxContainer
## Escolha do modo de jogo (2026-10-05): um cartão por modo de GameModes (nome, frase curta
## e quantos jogadores), o escolhido com borda de destaque, e embaixo as opções do modo
## (Vidas no Duelos). Modo novo em GameModes aparece aqui sozinho. Usado no Treino e na
## Sala; na sala só o anfitrião mexe (editable).

signal changed(mode: String, lives: int)

const COLUMNS := 3

var mode := "ffa"
var lives := GameModes.DEFAULT_LIVES
var editable := true
var _cards := {}          # id -> Button
var _lives_row: Control
var _lives_buttons: Array = []
var note: Label           # aviso embaixo (quem chama escreve: "2x2 precisa de 4 jogadores")


func _init(p_mode: String, p_lives: int) -> void:
	mode = p_mode
	lives = p_lives
	add_theme_constant_override("separation", 8)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for m in GameModes.MODES:
		var b := _card(m)
		grid.add_child(b)
		_cards[m["id"]] = b
	# Vidas (só no Duelos): linha de opção com abas compactas, como nas configurações.
	_lives_row = Ui.vbox(0)
	var tabs := Ui.tabs(GameModes.LIVES_OPTIONS.map(func(n): return str(n)),
		GameModes.LIVES_OPTIONS.find(lives), func(i):
			lives = GameModes.LIVES_OPTIONS[i]
			changed.emit(mode, lives))
	_lives_buttons = tabs.get_children()
	Ui.option_row(_lives_row, "Vidas", "Quem perde todas sai do rodízio.", tabs, 200, 8)
	add_child(_lives_row)
	note = Ui.label("", 13, Ui.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	_refresh()


## Atualiza o que aparece (a sala chama quando o anfitrião muda o modo).
func set_state(p_mode: String, p_lives: int, p_editable: bool) -> void:
	mode = p_mode
	lives = p_lives
	editable = p_editable
	_refresh()


func set_note(text: String, warn := false) -> void:
	note.text = text
	note.visible = text != ""
	note.add_theme_color_override("font_color", Ui.WARN if warn else Ui.MUTED)


func _card(m: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 112)
	b.pressed.connect(func():
		if editable and mode != m["id"]:
			mode = m["id"]
			_refresh()
			changed.emit(mode, lives))
	var col := Ui.vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14
	col.offset_right = -12
	col.offset_top = 11
	col.offset_bottom = -10
	b.add_child(col)
	var title := Ui.label(m["name"], 16, Ui.TEXT, true)
	title.name = "Title"
	col.add_child(title)
	var desc := Ui.label(m["desc"], 12, Ui.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(desc)
	col.add_child(Ui.label(m["players"], 11, Ui.MUTED.darkened(0.2), true))
	for c in col.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _refresh() -> void:
	for id in _cards:
		var b: Button = _cards[id]
		var chosen: bool = id == mode
		var normal := Ui.box(Ui.SURFACE_HI if chosen else Ui.BG, 10, Ui.ACCENT if chosen else Ui.LINE, 1)
		if chosen:
			normal.border_width_bottom = 3
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("disabled", normal)
		var hover := Ui.box(Ui.SURFACE_HI, 10, Ui.ACCENT if chosen else Ui.LINE.lightened(0.3), 1)
		hover.border_width_bottom = normal.border_width_bottom
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", normal)
		b.disabled = not editable
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if editable else Control.CURSOR_ARROW
		var title: Label = b.find_child("Title", true, false)
		title.add_theme_color_override("font_color", Ui.ACCENT.lightened(0.25) if chosen else Ui.TEXT)
		# Cartão de quem não escolhe: os não escolhidos ficam apagados.
		b.modulate.a = 1.0 if chosen or editable else 0.45
	_lives_row.visible = mode == "duels"
	var k := GameModes.LIVES_OPTIONS.find(lives)
	for i in _lives_buttons.size():
		_lives_buttons[i].set_pressed_no_signal(i == k)
		_lives_buttons[i].disabled = not editable
