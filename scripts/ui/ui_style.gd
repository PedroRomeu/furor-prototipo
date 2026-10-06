class_name Ui
extends RefCounted
## Visual comum das telas de menu: cores, tema (botões, campos de texto, painéis) e
## pequenos construtores de interface. Aplicar com `control.theme = Ui.theme()`.

const BG := Color(0.065, 0.07, 0.085)
const SURFACE := Color(0.115, 0.125, 0.15)
const SURFACE_HI := Color(0.16, 0.17, 0.205)
const LINE := Color(0.22, 0.235, 0.28)
const TEXT := Color(0.93, 0.94, 0.96)
const MUTED := Color(0.58, 0.61, 0.68)
const ACCENT := Color(1.0, 0.56, 0.22)
const OK := Color(0.45, 0.9, 0.55)
const WARN := Color(1.0, 0.7, 0.3)
const DANGER := Color(1.0, 0.42, 0.4)

static var _theme: Theme
static var _bold: FontVariation


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(SURFACE, 8, LINE))
		t.set_stylebox("hover", type, box(SURFACE_HI, 8, LINE.lightened(0.15)))
		t.set_stylebox("pressed", type, box(SURFACE_HI, 8, ACCENT))
		t.set_stylebox("hover_pressed", type, box(SURFACE_HI, 8, ACCENT))
		t.set_stylebox("disabled", type, box(SURFACE.darkened(0.25), 8))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, ACCENT.lightened(0.3))
		t.set_color("font_hover_pressed_color", type, ACCENT.lightened(0.3))
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, MUTED.darkened(0.3))
	t.set_stylebox("normal", "LineEdit", box(SURFACE, 8, LINE))
	t.set_stylebox("focus", "LineEdit", box(SURFACE, 8, ACCENT, 2))
	t.set_stylebox("read_only", "LineEdit", box(SURFACE, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.2))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("panel", "PanelContainer", box(SURFACE, 12))
	t.set_stylebox("panel", "PopupMenu", box(SURFACE_HI, 8, LINE))
	t.set_stylebox("panel", "AcceptDialog", box(SURFACE_HI, 10, LINE))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", box(ACCENT.darkened(0.45), 6))
	t.set_stylebox("separator", "HSeparator", line_box())
	var tip := box(Color(SURFACE_HI, 0.98), 8, LINE)
	tip.set_content_margin_all(12)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t


## Caixa arredondada; borda opcional.
static func box(color: Color, radius := 10, border := Color.TRANSPARENT, border_width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(border_width)
	return s


static func line_box() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = LINE
	s.thickness = 1
	return s


static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


static func background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)


static func label(text: String, size := 16, color := TEXT, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	return l


static func button(text: String, action: Callable, min_width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 40)
	b.pressed.connect(action)
	return b


## Botão principal da tela (laranja).
static func accent(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", box(ACCENT, 8))
	b.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.12), 8))
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.15), 8))
	b.add_theme_stylebox_override("disabled", box(ACCENT.darkened(0.6), 8))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color(0.1, 0.07, 0.04))
	b.add_theme_font_override("font", bold())
	return b


## Botão sem fundo (ações secundárias, como "Voltar").
static func flat(b: Button) -> Button:
	for s in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, box(Color.TRANSPARENT, 8))
	b.add_theme_stylebox_override("hover", box(SURFACE, 8))
	b.add_theme_color_override("font_color", MUTED)
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hbox(separation := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func vbox(separation := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


## Barra fina com a mistura das categorias de um baralho (cores de CardDB.CATEGORY_COLORS).
static func category_bar(cards: Array, height := 6.0) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	bar.custom_minimum_size.y = height
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for cat in CardDB.CATEGORY_COLORS:
		var n := cards.filter(func(id): return CardDB.CARDS[id]["cat"] == cat).size()
		if n == 0:
			continue
		var r := ColorRect.new()
		r.color = CardDB.CATEGORY_COLORS[cat]
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_stretch_ratio = n
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(r)
	if cards.is_empty():
		var r := ColorRect.new()
		r.color = LINE
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(r)
	return bar


## "MESTRA  Corrente", na cor do grupo da carta mestra.
static func master_label(id: String, size := 14) -> Label:
	var l := label("Mestra: " + CardDB.card_name(id), size, CardDB.CATEGORY_COLORS[CardDB.CARDS[id]["cat"]], true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Texto curto do estado do baralho: "42 cartas" ou "Faltam 5 cartas".
static func deck_status(cards: Array) -> Array:
	var n := cards.size()
	if n < CardDB.DECK_MIN:
		return ["Incompleto: faltam %d" % (CardDB.DECK_MIN - n), WARN]
	return ["%d cartas" % n, MUTED]


## Caixa com fundo que cresce para ocupar o espaço da linha; devolve a coluna de dentro.
static func panel(parent: Control) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := box(SURFACE, 12, LINE)
	style.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	var col := vbox(10)
	p.add_child(col)
	return col


## Botões lado a lado em que só um fica marcado.
static func segmented(options: Array, selected: int, on_pick: Callable) -> HBoxContainer:
	var row := hbox(6)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(on_pick.bind(i))
		row.add_child(b)
	return row


## Botões colados, só um marcado (abas compactas do editor de baralhos e das
## configurações). colors: cor de cada opção quando marcada (vazio: laranja).
static func tabs(options: Array, selected: int, on_pick: Callable, colors: Array = []) -> HBoxContainer:
	var row := hbox(0)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		segment_style(b, i == 0, i == options.size() - 1, colors[i] if i < colors.size() else ACCENT)
		b.pressed.connect(on_pick.bind(i))
		row.add_child(b)
	return row


## Visual de um botão de abas compactas: só as pontas arredondadas; o marcado ganha a cor.
static func segment_style(b: Button, first: bool, last: bool, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var on: bool = state == "pressed" or state == "hover_pressed"
		var s := box(SURFACE_HI if on or state == "hover" else SURFACE, 8, color.darkened(0.1) if on else LINE, 1)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.corner_radius_top_left = 8 if first else 0
		s.corner_radius_bottom_left = 8 if first else 0
		s.corner_radius_top_right = 8 if last else 0
		s.corner_radius_bottom_right = 8 if last else 0
		if on:
			s.border_width_bottom = 2
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_pressed_color", color.lerp(Color.WHITE, 0.25))
	b.add_theme_color_override("font_hover_pressed_color", color.lerp(Color.WHITE, 0.25))
	b.add_theme_color_override("font_color", MUTED)


static func gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## Espaço que estica na vertical (empurra o que vem depois para baixo).
static func grow() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
