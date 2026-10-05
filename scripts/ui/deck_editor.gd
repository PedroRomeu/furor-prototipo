extends Control
## Editor de um baralho (GameState.editing). Grade de cartas filtrada por categoria,
## arquétipo (CardDB.ARCHETYPES) e busca; clique põe uma cópia, botão direito tira. De CardDB.DECK_MIN a DECK_MAX cartas,
## até MAX_COPIES cópias de cada: mais cópias, mais chance de a carta aparecer.
## Em cima, a carta mestra: uma por baralho, escolhida entre CardDB.MASTERS.
## Cada mudança é salva na hora.

const TILE_WIDTH := 250.0
const FILTER_ALL := "Todas"

var index := 0
var deck: Array = []
var master := ""
var master_tiles := {}   # id -> PanelContainer
var master_desc: Label
var name_edit: LineEdit
var count_label: Label
var status_label: Label
var count_bar: HBoxContainer
var grid: GridContainer
var scroll: ScrollContainer
var search: LineEdit
var only_deck: CheckButton
var filter_buttons := {}
var filter := FILTER_ALL
var archetype_buttons := {}
var archetype := ""   # "" = qualquer arquétipo
var archetype_desc: Label
var tiles := {}   # id -> {panel, pips, minus, plus}


func _ready() -> void:
	index = clampi(GameState.editing, 0, GameState.decks.size() - 1)
	deck = GameState.decks[index]["cards"].duplicate()
	master = GameState.decks[index]["master"]
	theme = Ui.theme()
	Ui.background(self)
	if GameState.from_lobby:
		Net.match_starting.connect(_on_match_starting)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	add_child(margin)
	var column := Ui.vbox(14)
	margin.add_child(column)

	# Cabeçalho: voltar, nome, contagem.
	var header := Ui.hbox(16)
	column.add_child(header)
	header.add_child(Ui.flat(Ui.button("< Baralhos", _back)))
	name_edit = LineEdit.new()
	name_edit.text = GameState.decks[index]["name"]
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(300, 44)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.add_theme_font_override("font", Ui.bold())
	name_edit.tooltip_text = "Clique para mudar o nome"
	name_edit.text_changed.connect(func(_t): _save())
	header.add_child(name_edit)
	header.add_child(Ui.spacer())
	var counter := Ui.vbox(2)
	counter.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(counter)
	count_label = Ui.label("", 24, Ui.TEXT, true)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.add_child(count_label)
	status_label = Ui.label("", 14, Ui.MUTED)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.add_child(status_label)
	var more := MenuButton.new()
	more.text = "..."
	more.flat = false
	more.custom_minimum_size = Vector2(44, 44)
	more.get_popup().add_item("Completar com cartas aleatórias", 0)
	more.get_popup().add_item("Tirar todas as cartas", 1)
	more.get_popup().id_pressed.connect(_menu)
	header.add_child(more)

	count_bar = HBoxContainer.new()
	column.add_child(count_bar)
	column.add_child(_master_row())

	# Filtros: categoria, só as do baralho, busca.
	var filters := Ui.hbox(8)
	column.add_child(filters)
	var group := ButtonGroup.new()
	for cat in [FILTER_ALL] + CardDB.CATEGORY_COLORS.keys():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(96, 38)
		b.button_pressed = cat == FILTER_ALL
		if cat != FILTER_ALL:
			b.add_theme_color_override("font_color", CardDB.CATEGORY_COLORS[cat].lerp(Ui.TEXT, 0.35))
		b.pressed.connect(func(): filter = cat; _apply_filter())
		filters.add_child(b)
		filter_buttons[cat] = b
	filters.add_child(Ui.spacer())
	only_deck = CheckButton.new()
	only_deck.text = "Só as do baralho"
	only_deck.toggled.connect(func(_on): _apply_filter())
	filters.add_child(only_deck)
	search = LineEdit.new()
	search.placeholder_text = "Buscar carta..."
	search.custom_minimum_size = Vector2(230, 38)
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _apply_filter())
	filters.add_child(search)

	# Arquétipos: clicar de novo no marcado desmarca.
	var arch_row := Ui.hbox(10)
	column.add_child(arch_row)
	var arch_title := Ui.label("ARQUÉTIPO", 13, Ui.MUTED, true)
	arch_title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	arch_title.custom_minimum_size.y = 30
	arch_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arch_row.add_child(arch_title)
	var arch_col := Ui.vbox(4)
	arch_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arch_row.add_child(arch_col)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	arch_col.add_child(flow)
	var arch_group := ButtonGroup.new()
	arch_group.allow_unpress = true
	for a in CardDB.ARCHETYPES:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = arch_group
		b.custom_minimum_size.y = 30
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = CardDB.ARCHETYPES[a]["desc"] + "\nO número é quantas você já tem no baralho."
		b.toggled.connect(func(_on): _pick_archetype())
		flow.add_child(b)
		archetype_buttons[a] = b
	archetype_desc = Ui.label("", 13, Ui.MUTED)
	arch_col.add_child(archetype_desc)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for id in CardDB.all_ids():
		grid.add_child(_tile(id))
	scroll.resized.connect(_fit_columns)

	column.add_child(Ui.label("Clique numa carta para pôr no baralho, botão direito para tirar. "
		+ "Até %d cópias de cada: mais cópias, mais chance de ela aparecer na partida." % CardDB.MAX_COPIES,
		14, Ui.MUTED))
	_pick_archetype()
	_refresh()
	_fit_columns()


## Carta mestra: cinco botões lado a lado (grupo, nome, tecla) e, embaixo, o texto da escolhida.
func _master_row() -> Control:
	var box := Ui.vbox(8)
	var title := Ui.hbox(10)
	box.add_child(title)
	title.add_child(Ui.label("CARTA MESTRA", 13, Ui.MUTED, true))
	title.add_child(Ui.label("Uma por baralho. Você começa toda partida com ela.", 13, Ui.MUTED))
	var row := Ui.hbox(10)
	box.add_child(row)
	for id in CardDB.master_ids():
		var card: Dictionary = CardDB.CARDS[id]
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = card["desc"]
		panel.gui_input.connect(func(event: InputEvent):
			var mb := event as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				master = id
				_save()
				_refresh_master())
		var col := Ui.vbox(2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(col)
		var top := Ui.hbox(6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(top)
		var cat := Ui.label(card["cat"].to_upper(), 11, CardDB.CATEGORY_COLORS[card["cat"]], true)
		cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(cat)
		var rar := Ui.label(CardDB.rarity_name(id).to_upper(), 11, CardDB.rarity_color(id), true)
		rar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(rar)
		top.add_child(Ui.spacer())
		var key := Ui.label("%s  %d s" % [GameState.key_text("master"), card["cooldown"]] if card.has("cooldown") else "passiva", 11, Ui.MUTED)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(key)
		var name_label := Ui.label(card["name"], 17, Ui.TEXT, true)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name_label)
		row.add_child(panel)
		master_tiles[id] = panel
	master_desc = Ui.label("", 14, Ui.TEXT)
	master_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(master_desc)
	_refresh_master()
	return box


func _refresh_master() -> void:
	for id in master_tiles:
		var chosen: bool = id == master
		var color: Color = CardDB.CATEGORY_COLORS[CardDB.CARDS[id]["cat"]]
		var style := Ui.box(Ui.SURFACE_HI if chosen else Ui.BG.lightened(0.02), 10,
			color if chosen else Ui.LINE, 2 if chosen else 1)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		master_tiles[id].add_theme_stylebox_override("panel", style)
		master_tiles[id].modulate = Color.WHITE if chosen else Color(1, 1, 1, 0.6)
	master_desc.text = CardDB.CARDS[master]["desc"]


func _fit_columns() -> void:
	grid.columns = maxi(2, int((scroll.size.x - 16.0) / (TILE_WIDTH + 12.0)))


func _tile(id: String) -> Control:
	var card: Dictionary = CardDB.CARDS[id]
	var color: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TILE_WIDTH, 184)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = card["desc"]
	panel.gui_input.connect(_on_tile_input.bind(id))
	var col := Ui.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var top := Ui.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var cat := Ui.label(card["cat"].to_upper(), 12, color, true)
	top.add_child(cat)
	top.add_child(Ui.label(CardDB.rarity_name(id).to_upper(), 12, CardDB.rarity_color(id), true))
	top.add_child(Ui.spacer())
	if card.has("max"):
		top.add_child(Ui.label("pega 1 vez" if card["max"] == 1 else "até %d vezes" % card["max"], 12, Ui.MUTED))
	var head := Ui.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	head.add_child(CardIcon.make(id, 44, 1, false))
	var names := Ui.vbox(2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(names)
	var title := Ui.label(card["name"], 18, Ui.TEXT, true)
	names.add_child(title)
	var tags := Ui.label("  ·  ".join(CardDB.archetypes_of(id)), 12, Ui.ACCENT.lerp(Ui.MUTED, 0.45))
	tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(tags)
	var desc := Ui.label(card["desc"], 14, Ui.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(desc)

	var bottom := Ui.hbox(6)
	bottom.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(bottom)
	var pips := Ui.hbox(4)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in CardDB.MAX_COPIES:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 6)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	bottom.add_child(pips)
	bottom.add_child(Ui.spacer())
	var minus := _small_button("-", func(): _change(id, -1))
	var plus := _small_button("+", func(): _change(id, 1))
	bottom.add_child(minus)
	bottom.add_child(plus)
	for l in [cat, title, tags, desc]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tiles[id] = {"panel": panel, "pips": pips, "minus": minus, "plus": plus, "color": color}
	return panel


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(36, 32)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	return b


func _on_tile_input(event: InputEvent, id: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_change(id, 1)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_change(id, -1)


func _change(id: String, delta: int) -> void:
	if delta > 0:
		if deck.count(id) >= CardDB.MAX_COPIES or deck.size() >= CardDB.DECK_MAX:
			_flash_limit()
			return
		deck.append(id)
	elif not deck.has(id):
		return
	else:
		deck.erase(id)
	_save()
	_refresh()


func _flash_limit() -> void:
	var tween := create_tween()
	count_label.modulate = Ui.DANGER
	tween.tween_property(count_label, "modulate", Color.WHITE, 0.5)


func _menu(id: int) -> void:
	if id == 0:
		var ids := CardDB.all_ids()
		ids.shuffle()
		var k := 0
		while deck.size() < CardDB.DECK_MIN and k < ids.size() * CardDB.MAX_COPIES:
			var pick: String = ids[k % ids.size()]
			if deck.count(pick) < CardDB.MAX_COPIES:
				deck.append(pick)
			k += 1
	else:
		deck.clear()
	_save()
	_refresh()


func _save() -> void:
	var d: Dictionary = GameState.decks[index]
	var new_name := name_edit.text.strip_edges()
	d["name"] = new_name if not new_name.is_empty() else "Sem nome"
	d["cards"] = deck.duplicate()
	d["master"] = master
	GameState.save_decks()


func _refresh() -> void:
	var n := deck.size()
	count_label.text = "%d / %d" % [n, CardDB.DECK_MAX]
	if n < CardDB.DECK_MIN:
		status_label.text = "Faltam %d para o mínimo de %d" % [CardDB.DECK_MIN - n, CardDB.DECK_MIN]
		status_label.add_theme_color_override("font_color", Ui.WARN)
	elif n == CardDB.DECK_MAX:
		status_label.text = "Baralho cheio"
		status_label.add_theme_color_override("font_color", Ui.OK)
	else:
		status_label.text = "Pronto para jogar"
		status_label.add_theme_color_override("font_color", Ui.OK)
	for c in count_bar.get_children():
		c.queue_free()
	var bar := Ui.category_bar(deck, 6.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_stretch_ratio = maxf(n, 0.001)
	count_bar.add_child(bar)
	if n < CardDB.DECK_MAX:
		var rest := ColorRect.new()
		rest.color = Ui.SURFACE
		rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rest.size_flags_stretch_ratio = CardDB.DECK_MAX - n
		count_bar.add_child(rest)

	for cat in filter_buttons:
		var in_cat: int = deck.size() if cat == FILTER_ALL else deck.filter(func(id): return CardDB.CARDS[id]["cat"] == cat).size()
		filter_buttons[cat].text = "%s  %d" % [cat, in_cat]
	for a in archetype_buttons:
		var cards: Array = CardDB.ARCHETYPES[a]["cards"]
		archetype_buttons[a].text = "%s  %d" % [a, deck.filter(func(id): return id in cards).size()]
	for id in tiles:
		var t: Dictionary = tiles[id]
		var copies := deck.count(id)
		var color: Color = t["color"]
		var style := Ui.box(Ui.SURFACE if copies > 0 else Ui.BG.lightened(0.02), 10,
			color if copies > 0 else Ui.LINE, 2 if copies > 0 else 1)
		style.set_content_margin_all(14)
		t["panel"].add_theme_stylebox_override("panel", style)
		t["panel"].modulate = Color.WHITE if copies > 0 else Color(1, 1, 1, 0.6)
		for k in CardDB.MAX_COPIES:
			t["pips"].get_child(k).color = color if k < copies else Ui.LINE
		t["minus"].disabled = copies == 0
		t["plus"].disabled = copies >= CardDB.MAX_COPIES or n >= CardDB.DECK_MAX
	_apply_filter()


func _apply_filter() -> void:
	var text := search.text.strip_edges().to_lower()
	for id in tiles:
		var card: Dictionary = CardDB.CARDS[id]
		var show: bool = filter == FILTER_ALL or card["cat"] == filter
		if archetype != "" and not id in CardDB.ARCHETYPES[archetype]["cards"]:
			show = false
		if only_deck.button_pressed and not deck.has(id):
			show = false
		if text != "" and not (card["name"].to_lower().contains(text) or card["desc"].to_lower().contains(text)
				or " ".join(CardDB.archetypes_of(id)).to_lower().contains(text)):
			show = false
		tiles[id]["panel"].visible = show


func _pick_archetype() -> void:
	archetype = ""
	for a in archetype_buttons:
		if archetype_buttons[a].button_pressed:
			archetype = a
	archetype_desc.visible = archetype != ""
	if archetype != "":
		archetype_desc.text = "%s: %s  Clique de novo para tirar o filtro." % [archetype, CardDB.ARCHETYPES[archetype]["desc"]]
	_apply_filter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


## Na sala online: o anfitrião começou enquanto você editava.
func _on_match_starting() -> void:
	_save()
	GameState.go_to_match()


func _back() -> void:
	_save()
	get_tree().change_scene_to_file("res://scenes/decks.tscn")
