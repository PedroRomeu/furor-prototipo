extends Control
## Tela "Baralhos": lista os baralhos salvos, equipa um (o usado nas partidas), cria
## um novo a partir de um modelo, edita, duplica e apaga.

var grid: GridContainer
var overlay: Control
var name_edit: LineEdit
var template_buttons: Array = []
var chosen_template := 0


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
	header.add_child(Ui.flat(Ui.button("< Sala" if GameState.from_lobby else "< Menu", _back)))
	var titles := Ui.vbox(2)
	titles.add_child(Ui.label("Baralhos", 32, Ui.TEXT, true))
	titles.add_child(Ui.label("O baralho equipado é o que você leva para as partidas.", 15, Ui.MUTED))
	if GameState.from_lobby:
		# Continua na sala: se o anfitrião começar, a partida abre daqui mesmo.
		titles.add_child(Ui.label("Você continua na sala. Se o anfitrião começar, a partida abre sozinha.", 14, Ui.WARN))
		Net.match_starting.connect(_on_match_starting)
	header.add_child(titles)
	header.add_child(Ui.spacer())
	var new_button := Ui.accent(Ui.button("+  Novo baralho", _open_new, 190))
	new_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(new_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	_build_new_dialog()
	_refresh()


func _refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	for i in GameState.decks.size():
		grid.add_child(_deck_tile(i))


func _deck_tile(i: int) -> Control:
	var deck: Dictionary = GameState.decks[i]
	var cards: Array = deck["cards"]
	var equipped := i == GameState.equipped
	var valid := CardDB.is_valid_deck(cards)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 150)
	var style := Ui.box(Ui.SURFACE, 12, Ui.ACCENT if equipped else Ui.LINE, 2 if equipped else 1)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(10)
	panel.add_child(col)

	var top := Ui.hbox(8)
	col.add_child(top)
	var title := Ui.label(deck["name"], 21, Ui.TEXT, true)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if equipped:
		top.add_child(Ui.label("EQUIPADO", 13, Ui.ACCENT, true))
	var status := Ui.deck_status(cards)
	var info := Ui.hbox(8)
	col.add_child(info)
	info.add_child(Ui.label(status[0], 15, status[1]))
	info.add_child(Ui.spacer())
	info.add_child(Ui.master_label(deck["master"]))
	col.add_child(Ui.category_bar(cards))

	var buttons := Ui.hbox(8)
	col.add_child(buttons)
	if not equipped:
		var equip := Ui.button("Equipar", func(): GameState.equip(i); _refresh())
		equip.disabled = not valid
		equip.tooltip_text = "" if valid else "Precisa de pelo menos %d cartas" % CardDB.DECK_MIN
		buttons.add_child(Ui.accent(equip) if valid else equip)
	buttons.add_child(Ui.button("Editar", _edit.bind(i)))
	buttons.add_child(Ui.spacer())
	var more := MenuButton.new()
	more.text = "..."
	more.custom_minimum_size = Vector2(44, 40)
	more.flat = false
	var popup := more.get_popup()
	popup.add_item("Duplicar", 0)
	popup.add_item("Apagar", 1)
	popup.set_item_disabled(1, GameState.decks.size() <= 1)
	popup.id_pressed.connect(func(id): _duplicate(i) if id == 0 else _confirm_delete(i))
	buttons.add_child(more)
	return panel


func _edit(i: int) -> void:
	GameState.editing = i
	get_tree().change_scene_to_file("res://scenes/deck_editor.tscn")


func _duplicate(i: int) -> void:
	var d: Dictionary = GameState.decks[i]
	GameState.add_deck("%s (cópia)" % d["name"], d["cards"], d["master"])
	_refresh()


func _confirm_delete(i: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Apagar baralho"
	dialog.dialog_text = "Apagar \"%s\"? Não dá para desfazer." % GameState.decks[i]["name"]
	dialog.ok_button_text = "Apagar"
	dialog.cancel_button_text = "Cancelar"
	dialog.confirmed.connect(func(): GameState.delete_deck(i); _refresh())
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


# ---------------------------------------------------------------- novo baralho

func _build_new_dialog() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := Ui.box(Ui.SURFACE, 14, Ui.LINE)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 560
	center.add_child(panel)
	var col := Ui.vbox(14)
	panel.add_child(col)

	col.add_child(Ui.label("Novo baralho", 26, Ui.TEXT, true))
	col.add_child(Ui.label("Nome", 14, Ui.MUTED))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.y = 42
	name_edit.max_length = 24
	name_edit.text_submitted.connect(func(_t): _create())
	col.add_child(name_edit)
	col.add_child(Ui.label("Começar com", 14, Ui.MUTED))
	var list := Ui.vbox(6)
	col.add_child(list)
	var group := ButtonGroup.new()
	for t in CardDB.TEMPLATES.size():
		var tpl: Dictionary = CardDB.TEMPLATES[t]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   ·   %s" % [tpl["name"], tpl["desc"]]
		b.custom_minimum_size.y = 40
		b.pressed.connect(func(): chosen_template = t)
		list.add_child(b)
		template_buttons.append(b)

	var buttons := Ui.hbox(10)
	col.add_child(buttons)
	buttons.add_child(Ui.spacer())
	buttons.add_child(Ui.flat(Ui.button("Cancelar", func(): overlay.visible = false, 110)))
	buttons.add_child(Ui.accent(Ui.button("Criar e editar", _create, 160)))


func _open_new() -> void:
	name_edit.text = GameState.new_deck_name()
	chosen_template = 0
	template_buttons[0].button_pressed = true
	overlay.visible = true
	name_edit.grab_focus()
	name_edit.select_all()


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
