class_name PracticeCards
extends CanvasLayer
## Cartas da sala de teste (tecla B): pausa o jogo e mostra, à esquerda, todas as cartas
## (busca e grupos; clique põe uma, botão direito tira) ou, trocando a mestra, todas as
## mestras; à direita, a mestra e as cartas valendo agora, "Pegar o baralho todo", "Tirar
## todas" e "Mestra sem recarga". Mexe só nas cartas da sala (Player.cards), nunca no
## baralho salvo. Cada carta respeita o limite por partida (CardDB.can_take); as sem
## limite param em NO_LIMIT_CAP.

signal applied(cards: Array)   # as cartas mudaram: a partida recalcula o jogador
signal closed

const NO_LIMIT_CAP := 10
const GROUPS := ["Todas", "Arma", "Balas", "Escudo", "Corpo", "Movimento"]

var cards: Array = []          # mestra primeiro, depois as cartas pegas
var deck: Array = []           # o baralho aberto no editor (para "Pegar o baralho todo")
var no_cooldown := false
var shooter_mode := 0          # atiradores: 0 desligado, 1 lento, 2 normal, 3 rajada (match._shooter_step)

var _group := 0
var _search := ""
var _picking_master := false
var _grid: GridContainer
var _list: VBoxContainer
var _master_slot: PanelContainer
var _count_label: Label
var _tiles := {}               # id -> PanelContainer
var _search_edit: LineEdit
var _tabs: HBoxContainer
var _nocd: CheckButton
var _hint: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.theme = Ui.theme()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var row := Ui.hbox(20)
	margin.add_child(row)
	row.add_child(_build_collection())
	row.add_child(_build_side())


func open(p_cards: Array, p_deck: Array, p_no_cd: bool) -> void:
	cards = p_cards.duplicate()
	deck = p_deck
	no_cooldown = p_no_cd
	_picking_master = false
	visible = true
	get_tree().paused = true
	GameState.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	GameState.menu_open = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.physical_keycode == KEY_B or key.physical_keycode == KEY_ESCAPE) \
			and not (_search_edit.has_focus() and key.physical_keycode == KEY_B):
		get_viewport().set_input_as_handled()
		if _picking_master:
			_picking_master = false
			_refresh()
		else:
			close()


# ---------------------------------------------------------------- esquerda

func _build_collection() -> Control:
	var col := Ui.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Ui.hbox(12)
	col.add_child(head)
	head.add_child(Ui.label("Cartas da sala", 24, Ui.TEXT, true))
	head.add_child(Ui.spacer())
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Buscar carta"
	_search_edit.custom_minimum_size = Vector2(220, 38)
	_search_edit.text_changed.connect(func(t): _search = t.strip_edges().to_lower(); _fill())
	head.add_child(_search_edit)
	var colors := [Ui.ACCENT] + CardDB.CATEGORY_COLORS.values()
	_tabs = Ui.tabs(GROUPS, 0, func(i): _group = i; _fill(), colors)
	col.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.thin_scrollbar(scroll)
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	_hint = Ui.label("", 13, Ui.MUTED)
	col.add_child(_hint)
	return col


## Monta a grade: cartas comuns do grupo e da busca, ou as mestras.
func _fill() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_tiles.clear()
	var ids: Array = CardDB.master_ids() if _picking_master else CardDB.all_ids()
	for id in ids:
		var card: Dictionary = CardDB.CARDS[id]
		if _group > 0 and card["cat"] != GROUPS[_group]:
			continue
		if _search != "" and not card["name"].to_lower().contains(_search):
			continue
		var tile := _tile(id)
		_grid.add_child(tile)
		_tiles[id] = tile
	_style_tiles()


func _tile(id: String) -> PanelContainer:
	var card: Dictionary = CardDB.CARDS[id]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = CardIcon._wrap(card["desc"], 52)
	panel.gui_input.connect(_on_tile_input.bind(id))
	var row := Ui.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(CardIcon.make(id, 34, 1, false))
	var names := Ui.vbox(0)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var title := Ui.label(card["name"], 15, Ui.TEXT, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(title)
	var sub := CardDB.rarity_name(id)
	if card.has("max"):
		sub += "  ·  " + CardDB.limit_short(id)
	var rarity := Ui.label(sub, 12, CardDB.rarity_color(id))
	rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(rarity)
	var count := Ui.label("", 15, CardDB.CATEGORY_COLORS[card["cat"]], true)
	count.name = "Count"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	return panel


func _style_tiles() -> void:
	for id in _tiles:
		var panel: PanelContainer = _tiles[id]
		var n := cards.count(id)
		var lit := n > 0
		panel.add_theme_stylebox_override("panel", CardFrame.style(CardDB.CARDS[id]["cat"], "lit" if lit else "dim", _picking_master, 10))
		var count: Label = panel.find_child("Count", true, false)
		count.text = ("x%d" % n if n > 0 else "") if not _picking_master else ("Equipada" if lit else "")


func _on_tile_input(event: InputEvent, id: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if _picking_master:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			cards = cards.filter(func(c): return not CardDB.is_master(c))
			cards.push_front(id)
			_picking_master = false
			_apply()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_add(id)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_remove(id)


# ---------------------------------------------------------------- direita

func _build_side() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	var style := Ui.box(Ui.SURFACE.darkened(0.15), 14, Ui.LINE)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(12)
	panel.add_child(col)
	col.add_child(Ui.label("MESTRA", 12, Ui.MUTED, true))
	_master_slot = PanelContainer.new()
	_master_slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_master_slot.tooltip_text = "Clique para trocar"
	_master_slot.gui_input.connect(func(event: InputEvent):
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_picking_master = not _picking_master
			_refresh())
	col.add_child(_master_slot)
	_nocd = CheckButton.new()
	_nocd.text = "Mestra sem recarga"
	_nocd.toggled.connect(func(on): no_cooldown = on)
	col.add_child(_nocd)
	col.add_child(Ui.label("ATIRADORES", 12, Ui.MUTED, true))
	col.add_child(Ui.tabs(["Desligado", "Lento", "Normal", "Rajada"], shooter_mode, func(i): shooter_mode = i))
	col.add_child(Ui.gap(4))
	var head := Ui.hbox(8)
	col.add_child(head)
	head.add_child(Ui.label("CARTAS VALENDO", 12, Ui.MUTED, true))
	head.add_child(Ui.spacer())
	_count_label = Ui.label("", 12, Ui.MUTED, true)
	head.add_child(_count_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.thin_scrollbar(scroll)
	col.add_child(scroll)
	_list = Ui.vbox(2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	col.add_child(Ui.button("Pegar o baralho todo", _take_deck))
	col.add_child(Ui.button("Tirar todas", func():
		cards = cards.filter(CardDB.is_master)
		_apply()))
	col.add_child(Ui.accent(Ui.button("Voltar à sala", close)))
	return panel


func _refresh() -> void:
	_nocd.set_pressed_no_signal(no_cooldown)
	_tabs.visible = not _picking_master
	_hint.text = "Clique numa mestra para equipar   ·   B ou Esc: voltar às cartas" if _picking_master 		else "Clique: põe uma   ·   Botão direito: tira   ·   Passe o mouse para ler   ·   B ou Esc: voltar"
	_search_edit.visible = not _picking_master
	_fill()
	# Mestra
	for child in _master_slot.get_children():
		child.queue_free()
	var master: String = cards.filter(CardDB.is_master).front() if cards.any(CardDB.is_master) else ""
	_master_slot.add_theme_stylebox_override("panel", CardFrame.style(CardDB.CARDS[master]["cat"] if master != "" else "Arma",
		"hot" if _picking_master else "lit", true, 12))
	var row := Ui.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_master_slot.add_child(row)
	if master != "":
		row.add_child(CardIcon.make(master, 38, 1, false))
	var name_label := Ui.label(CardDB.card_name(master) if master != "" else "Sem mestra", 16, Ui.TEXT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	var hint := Ui.label("Voltar ›" if _picking_master else "Trocar ›", 13, Ui.MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hint)
	# Lista das cartas valendo (na ordem da coleção), clique tira uma.
	for child in _list.get_children():
		child.queue_free()
	var taken := cards.filter(func(c): return not CardDB.is_master(c))
	_count_label.text = "%d" % taken.size()
	for id in CardDB.all_ids():
		if taken.has(id):
			_list.add_child(_list_row(id, taken.count(id)))
	if taken.is_empty():
		var empty := Ui.label("Nenhuma: só a arma base.", 14, Ui.MUTED)
		_list.add_child(empty)


func _list_row(id: String, n: int) -> Control:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = "Clique para tirar uma"
	b.custom_minimum_size.y = 34
	b.pressed.connect(_remove.bind(id))
	var row := Ui.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(CardIcon.make(id, 26, 1, false))
	var l := Ui.label(CardDB.card_name(id), 14, Ui.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var c := Ui.label("x%d" % n, 14, Ui.MUTED, true)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(c)
	return b


# ---------------------------------------------------------------- mudanças

func _add(id: String) -> void:
	if not CardDB.can_take(id, cards) or cards.count(id) >= NO_LIMIT_CAP:
		return
	cards.append(id)
	_apply()


func _remove(id: String) -> void:
	if cards.has(id):
		cards.erase(id)
		_apply()


func _take_deck() -> void:
	var kept := cards.filter(CardDB.is_master)
	for id in deck:
		if CardDB.can_take(id, kept) and not CardDB.is_master(id):
			kept.append(id)
	cards = kept
	_apply()


func _apply() -> void:
	applied.emit(cards)
	_refresh()
