extends Control
## Tela "Baralhos": lista os baralhos salvos, equipa um (o usado nas partidas), cria
## um novo a partir de um modelo, edita, duplica e apaga. Visual do editor (2026-10-06):
## uma barra no topo e um cartão por baralho com a mestra como "capa".

const TILE_HEIGHT := 164.0
const COLUMNS := 3

var grid: GridContainer
var overlay: Control          # janela por cima (novo baralho ou apagar)
var overlay_body: VBoxContainer
var name_edit: LineEdit
var template_rows: Array = []
var chosen_template := 0
var count_label: Label


func _ready() -> void:
	theme = Ui.theme()
	Ui.background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := Ui.vbox(18)
	margin.add_child(column)

	var header := Ui.hbox(16)
	column.add_child(header)
	var back := Ui.flat(Ui.button("‹  Sala" if GameState.from_lobby else "‹  Menu", _back))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(back)
	var titles := Ui.vbox(2)
	var title_row := Ui.hbox(12)
	titles.add_child(title_row)
	title_row.add_child(Ui.label("Baralhos", 32, Ui.TEXT, true))
	count_label = Ui.label("", 15, Ui.MUTED)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(count_label)
	titles.add_child(Ui.label("O baralho equipado é o que você leva para as partidas.", 15, Ui.MUTED))
	if GameState.from_lobby:
		# Continua na sala: se o anfitrião começar, a partida abre daqui mesmo.
		titles.add_child(Ui.label("Você continua na sala. Se o anfitrião começar, a partida abre sozinha.", 14, Ui.WARN))
		Net.match_starting.connect(_on_match_starting)
	header.add_child(titles)
	header.add_child(Ui.spacer())
	var new_button := Ui.accent(Ui.button("+  Novo baralho", _open_new, 190))
	new_button.custom_minimum_size.y = 44
	new_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(new_button)
	var line := HSeparator.new()
	column.add_child(line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	_build_overlay()
	_refresh()


func _refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	for i in GameState.decks.size():
		grid.add_child(_deck_tile(i))
	var n := GameState.decks.size()
	count_label.text = "%d baralho%s" % [n, "" if n == 1 else "s"]


## Cartão de um baralho: ícone da mestra à esquerda; nome, estado e mistura dos grupos à
## direita; embaixo Equipar (ou a marca de equipado), Editar e o menu "⋯".
func _deck_tile(i: int) -> Control:
	var deck: Dictionary = GameState.decks[i]
	var cards: Array = deck["cards"]
	var equipped := i == GameState.equipped
	var valid := CardDB.is_valid_deck(cards)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, TILE_HEIGHT)
	var style := Ui.box(Ui.SURFACE_HI if equipped else Ui.SURFACE, 12, Ui.ACCENT if equipped else Ui.LINE, 1)
	if equipped:
		style.border_width_left = 4
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(12)
	panel.add_child(col)

	var top := Ui.hbox(14)
	col.add_child(top)
	var cover := CardIcon.make(deck["master"], 56)
	cover.tooltip_text = "Mestra: " + CardDB.card_name(deck["master"])
	top.add_child(cover)
	var texts := Ui.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(texts)
	var title := Ui.label(deck["name"], 19, Ui.TEXT, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var status := Ui.deck_status(cards)
	var sub := Ui.hbox(6)
	texts.add_child(sub)
	sub.add_child(Ui.label(status[0], 13, status[1]))
	sub.add_child(Ui.label("·", 13, Ui.LINE.lightened(0.3)))
	sub.add_child(Ui.label(CardDB.card_name(deck["master"]), 13,
		CardDB.CATEGORY_COLORS[CardDB.CARDS[deck["master"]]["cat"]].lerp(Ui.TEXT, 0.25)))
	var bar := Ui.category_bar(cards, 4)
	bar.tooltip_text = _mix_text(cards)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	texts.add_child(Ui.gap(4))
	texts.add_child(bar)

	col.add_child(Ui.grow())
	var buttons := Ui.hbox(8)
	col.add_child(buttons)
	if equipped:
		var mark := Ui.label("✓  Equipado", 14, Ui.ACCENT, true)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buttons.add_child(mark)
	else:
		var equip := Ui.button("Equipar", func(): GameState.equip(i); _refresh(), 100)
		equip.custom_minimum_size.y = 36
		equip.disabled = not valid
		equip.tooltip_text = "" if valid else "Precisa de pelo menos %d cartas" % CardDB.DECK_MIN
		buttons.add_child(equip)
	buttons.add_child(Ui.spacer())
	var edit := Ui.button("Editar", _edit.bind(i), 90)
	edit.custom_minimum_size.y = 36
	buttons.add_child(edit)
	var more := MenuButton.new()
	more.text = "⋯"
	more.flat = false
	more.tooltip_text = "Mais opções"
	more.custom_minimum_size = Vector2(40, 36)
	var popup := more.get_popup()
	popup.add_item("Duplicar", 0)
	popup.add_item("Apagar", 1)
	popup.set_item_disabled(1, GameState.decks.size() <= 1)
	popup.id_pressed.connect(func(id): _duplicate(i) if id == 0 else _confirm_delete(i))
	buttons.add_child(more)
	return panel


## Dica da barra de grupos: "Arma 8  ·  Balas 12  ·  ...".
func _mix_text(cards: Array) -> String:
	var parts := PackedStringArray()
	for cat in CardDB.CATEGORY_COLORS:
		var n := cards.filter(func(id): return CardDB.CARDS[id]["cat"] == cat).size()
		if n > 0:
			parts.append("%s %d" % [cat, n])
	return "  ·  ".join(parts) if not parts.is_empty() else "Sem cartas"


func _edit(i: int) -> void:
	GameState.editing = i
	get_tree().change_scene_to_file("res://scenes/deck_editor.tscn")


func _duplicate(i: int) -> void:
	var d: Dictionary = GameState.decks[i]
	GameState.add_deck("%s (cópia)" % d["name"], d["cards"], d["master"])
	_refresh()


# ---------------------------------------------------------------- janelas

## Fundo escuro e um painel no centro; o conteúdo muda conforme a janela aberta.
func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			overlay.visible = false)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := Ui.box(Ui.BG, 14, Ui.LINE)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 520
	center.add_child(panel)
	overlay_body = Ui.vbox(14)
	panel.add_child(overlay_body)


func _open_overlay(title: String) -> VBoxContainer:
	for c in overlay_body.get_children():
		c.queue_free()
	overlay_body.add_child(Ui.label(title, 24, Ui.TEXT, true))
	overlay.visible = true
	return overlay_body


func _overlay_buttons(confirm: Button) -> void:
	var buttons := Ui.hbox(10)
	overlay_body.add_child(Ui.gap(4))
	overlay_body.add_child(buttons)
	buttons.add_child(Ui.spacer())
	buttons.add_child(Ui.flat(Ui.button("Cancelar", func(): overlay.visible = false, 110)))
	confirm.custom_minimum_size = Vector2(160, 42)
	buttons.add_child(confirm)


func _confirm_delete(i: int) -> void:
	var col := _open_overlay("Apagar baralho")
	var text := Ui.label("Apagar \"%s\"? Não dá para desfazer." % GameState.decks[i]["name"], 15, Ui.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var confirm := Ui.button("Apagar", func():
		overlay.visible = false
		GameState.delete_deck(i)
		_refresh())
	confirm.add_theme_stylebox_override("normal", Ui.box(Ui.DANGER.darkened(0.55), 8, Ui.DANGER.darkened(0.2)))
	confirm.add_theme_stylebox_override("hover", Ui.box(Ui.DANGER.darkened(0.45), 8, Ui.DANGER))
	confirm.add_theme_color_override("font_color", Ui.DANGER.lightened(0.4))
	_overlay_buttons(confirm)


## Novo baralho: nome e o modelo de partida (uma linha por modelo, nome e frase).
func _open_new() -> void:
	var col := _open_overlay("Novo baralho")
	Ui.section(col, "NOME", null, 4)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.y = 42
	name_edit.max_length = 24
	name_edit.text = GameState.new_deck_name()
	name_edit.text_submitted.connect(func(_t): _create())
	col.add_child(name_edit)
	Ui.section(col, "COMEÇAR COM", null, 6)
	var list := Ui.vbox(6)
	col.add_child(list)
	template_rows.clear()
	chosen_template = 0
	for t in CardDB.TEMPLATES.size():
		list.add_child(_template_row(t))
	_style_templates()
	var hint := Ui.label("Dá para trocar tudo depois no editor.", 13, Ui.MUTED)
	col.add_child(hint)
	_overlay_buttons(Ui.accent(Ui.button("Criar e editar", _create)))
	name_edit.grab_focus.call_deferred()
	name_edit.select_all.call_deferred()


func _template_row(t: int) -> Control:
	var tpl: Dictionary = CardDB.TEMPLATES[t]
	var box := PanelContainer.new()
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			chosen_template = t
			_style_templates()
			if e.double_click:
				_create())
	var row := Ui.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	if tpl.has("master"):
		var icon := CardIcon.make(tpl["master"], 34, 1, false)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		var blank := Control.new()   # alinha o texto com o dos modelos que têm ícone
		blank.custom_minimum_size = Vector2(34, 34)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(blank)
	var texts := Ui.vbox(0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var name_label := Ui.label(tpl["name"], 15, Ui.TEXT, true)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name_label)
	var text: String = tpl["desc"]
	var desc := Ui.label(text.left(1).to_upper() + text.substr(1) + ".", 13, Ui.MUTED)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(desc)
	template_rows.append(box)
	return box


func _style_templates() -> void:
	for t in template_rows.size():
		var on := t == chosen_template
		var s := Ui.box(Ui.SURFACE_HI if on else Ui.SURFACE, 8, Ui.ACCENT if on else Ui.LINE, 1)
		s.set_content_margin_all(10)
		s.content_margin_left = 12
		template_rows[t].add_theme_stylebox_override("panel", s)


func _create() -> void:
	var deck_name := name_edit.text.strip_edges()
	if deck_name.is_empty():
		deck_name = GameState.new_deck_name()
	_edit(GameState.add_deck(deck_name, CardDB.template_deck(chosen_template), CardDB.template_master(chosen_template)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if overlay.visible:
			overlay.visible = false
		else:
			_back()


func _on_match_starting() -> void:
	GameState.go_to_match()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
