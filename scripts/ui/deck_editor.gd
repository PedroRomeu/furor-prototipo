extends Control
## Editor de um baralho (GameState.editing), refeito em 2026-10-06 (pedido do usuário: menos
## botões e informação de uma vez, minimalista e profissional; layout de duas colunas como
## nos editores de Hearthstone e Marvel Snap).
##
## Esquerda: a coleção. Uma barra só (voltar, busca, grupos e "Filtros", que guarda
## arquétipo, raridade e "só as do baralho") e a grade de cartas: clique põe uma cópia,
## botão direito tira. Direita: o baralho. Nome, contagem, a carta mestra numa vaga (clicar
## abre a escolha, que cabe quantas mestras houver) e a lista do que está nele, por grupo;
## clicar numa linha tira uma cópia. Cada mudança é salva na hora.

const TILE_WIDTH := 216.0
const TILE_HEIGHT := 138.0
## Descrição numa área fixa (pedido do usuário, como nos Yu-Gi-Oh online): texto que não
## cabe ganha uma barra de rolagem fina à direita, em vez de esticar ou vazar da carta.
const DESC_HEIGHT := 62.0   # 3 linhas inteiras
const GAP := 10
const FILTER_ALL := "Todas"
const RARITY_FILTERS := ["comum", "raro", "epico", "lendario"]

var index := 0
var deck: Array = []
var master := ""
var tiles := {}   # id -> {panel, badge, cat}
var hovered := ""

var name_edit: LineEdit
var count_label: Label
var status_label: Label
var count_bar: HBoxContainer
var master_slot: PanelContainer
var deck_list: VBoxContainer
var deck_empty: Label
var grid: GridContainer
var scroll: ScrollContainer
var search: LineEdit
var cat_buttons := {}
var category := FILTER_ALL
var filter_button: Button
var filter_popup: PopupPanel
var arch_buttons := {}
var rarity_buttons := {}
var only_deck: CheckButton
var empty_grid: Label
var picker: Control   # escolha da carta mestra (por cima de tudo)
var picker_group := FILTER_ALL   # grupo mostrado na escolha da mestra
var side_panel: PanelContainer


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
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var row := Ui.hbox(20)
	margin.add_child(row)
	row.add_child(_build_collection())
	side_panel = _build_deck_panel()
	row.add_child(side_panel)
	_build_picker()
	resized.connect(_fit)
	_refresh()
	_fit()


# ---------------------------------------------------------------- coleção (esquerda)

func _build_collection() -> Control:
	var col := Ui.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar := Ui.hbox(8)
	col.add_child(bar)
	var back := Ui.flat(Ui.button("‹  Baralhos", _back))
	bar.add_child(back)
	search = LineEdit.new()
	search.placeholder_text = "Buscar carta"
	search.custom_minimum_size = Vector2(170, 40)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _apply_filter())
	bar.add_child(search)
	# Grupos: botões colados, só um marcado.
	var segs := Ui.hbox(0)
	bar.add_child(segs)
	var group := ButtonGroup.new()
	var cats: Array = [FILTER_ALL] + CardDB.CATEGORY_COLORS.keys()
	for i in cats.size():
		var cat: String = cats[i]
		var b := Button.new()
		b.text = cat
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = cat == FILTER_ALL
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 14)
		Ui.segment_style(b, i == 0, i == cats.size() - 1,
			Ui.ACCENT if cat == FILTER_ALL else CardDB.CATEGORY_COLORS[cat])
		b.pressed.connect(func(): category = cat; _apply_filter())
		segs.add_child(b)
		cat_buttons[cat] = b
	filter_button = Ui.button("Filtros", _open_filters)
	filter_button.custom_minimum_size = Vector2(96, 40)
	filter_button.add_theme_font_size_override("font_size", 14)
	bar.add_child(filter_button)
	_build_filter_popup()

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var inner := Ui.vbox(0)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	inner.add_child(grid)
	for id in CardDB.all_ids():
		grid.add_child(_tile(id))
	empty_grid = Ui.label("Nenhuma carta com esses filtros.", 15, Ui.MUTED)
	empty_grid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_grid.custom_minimum_size.y = 120
	empty_grid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_child(empty_grid)
	return col


func _build_filter_popup() -> void:
	filter_popup = PopupPanel.new()
	var style := Ui.box(Ui.SURFACE_HI, 10, Ui.LINE)
	style.set_content_margin_all(18)
	filter_popup.add_theme_stylebox_override("panel", style)
	add_child(filter_popup)
	var col := Ui.vbox(10)
	col.custom_minimum_size.x = 420
	filter_popup.add_child(col)

	col.add_child(_section_title("ARQUÉTIPO"))
	# Grade de colunas fixas (um HFlowContainer mede a altura antes de saber a largura e
	# deixava a janela comprida demais).
	var flow := GridContainer.new()
	flow.columns = 3
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	col.add_child(flow)
	var arch_group := ButtonGroup.new()
	arch_group.allow_unpress = true
	for a in CardDB.ARCHETYPES:
		var b := _chip(a, arch_group)
		b.tooltip_text = CardDB.ARCHETYPES[a]["desc"]
		flow.add_child(b)
		arch_buttons[a] = b

	col.add_child(Ui.gap(4))
	col.add_child(_section_title("RARIDADE"))
	var rar_row := Ui.hbox(6)
	col.add_child(rar_row)
	var rar_group := ButtonGroup.new()
	rar_group.allow_unpress = true
	for r in RARITY_FILTERS:
		var b := _chip(CardDB.RARITIES[r]["name"], rar_group)
		b.add_theme_color_override("font_color", CardDB.RARITIES[r]["color"])
		rar_row.add_child(b)
		rarity_buttons[r] = b

	col.add_child(Ui.gap(2))
	var sep := HSeparator.new()
	col.add_child(sep)
	var bottom := Ui.hbox(8)
	col.add_child(bottom)
	only_deck = CheckButton.new()
	only_deck.text = "Só cartas do baralho"
	only_deck.toggled.connect(func(_on): _apply_filter())
	bottom.add_child(only_deck)
	bottom.add_child(Ui.spacer())
	bottom.add_child(Ui.flat(Ui.button("Limpar filtros", _clear_filters)))


func _section_title(text: String) -> Label:
	return Ui.label(text, 12, Ui.MUTED, true)


func _chip(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size.y = 32
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.toggled.connect(func(_on): _apply_filter())
	return b


func _open_filters() -> void:
	var r := filter_button.get_global_rect()
	var content := filter_popup.get_child(0) as Control
	var height := int(content.get_combined_minimum_size().y) + 36   # + margens do painel
	filter_popup.popup(Rect2i(Vector2i(int(r.end.x - 456), int(r.end.y + 6)), Vector2i(456, height)))


func _clear_filters() -> void:
	for b in arch_buttons.values() + rarity_buttons.values():
		b.set_pressed_no_signal(false)
	only_deck.set_pressed_no_signal(false)
	_apply_filter()


func _tile(id: String) -> Control:
	var card: Dictionary = CardDB.CARDS[id]
	var color: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TILE_WIDTH, TILE_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tip: String = CardIcon._wrap(card["desc"], 52)
	var archs := CardDB.archetypes_of(id)
	if not archs.is_empty():
		tip += "\n\nArquétipos: " + ", ".join(archs)
	panel.tooltip_text = tip + "\n\nClique: põe uma cópia   ·   Botão direito: tira"
	panel.gui_input.connect(_on_tile_input.bind(id))
	panel.mouse_entered.connect(func(): hovered = id; _style_tile(id))
	panel.mouse_exited.connect(func(): if hovered == id: hovered = ""; _style_tile(id))
	var col := Ui.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var head := Ui.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	head.add_child(CardIcon.make(id, 38, 1, false))
	var names := Ui.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(names)
	var title := Ui.label(card["name"], 16, Ui.TEXT, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Nome e, no canto de cima, o símbolo do grupo.
	var title_row := Ui.hbox(6)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(title_row)
	title_row.add_child(title)
	title_row.add_child(CardFrame.symbol_rect(card["cat"], 18))
	var sub := CardDB.rarity_name(id)
	if card.has("max"):
		sub += "  ·  " + CardDB.limit_short(id)
	# Raridade e, à direita, as cópias no baralho (fora da linha do nome, que fica inteira).
	var sub_row := Ui.hbox(6)
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(sub_row)
	var rarity := Ui.label(sub, 12, CardDB.rarity_color(id))
	rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_row.add_child(rarity)
	sub_row.add_child(Ui.spacer())
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_font_override("font", Ui.bold())
	badge.add_theme_color_override("font_color", Ui.BG)
	var badge_style := Ui.box(color, 10)
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 0
	badge_style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("normal", badge_style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_row.add_child(badge)

	col.add_child(_desc_box(card["desc"]))
	tiles[id] = {"panel": panel, "badge": badge, "cat": card["cat"]}
	return panel


## Área de descrição de altura fixa; rola quando o texto é maior (Ui.scroll_text).
func _desc_box(text: String) -> ScrollContainer:
	return Ui.scroll_text(text, DESC_HEIGHT)


func _style_tile(id: String) -> void:
	var t: Dictionary = tiles[id]
	var copies := deck.count(id)
	var hot := id == hovered
	# Moldura do grupo acesa (com brilho) para as cartas do baralho, apagada para as outras.
	var look := ("hot" if hot else "lit") if copies > 0 else ("dim_hot" if hot else "dim")
	t["panel"].add_theme_stylebox_override("panel", CardFrame.style(t["cat"], look, false, 12))
	t["badge"].visible = copies > 0
	t["badge"].text = "x%d" % copies


func _on_tile_input(event: InputEvent, id: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_change(id, 1)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_change(id, -1)


func _apply_filter() -> void:
	var text := search.text.strip_edges().to_lower()
	var arch := ""
	for a in arch_buttons:
		if arch_buttons[a].button_pressed:
			arch = a
	var rarity := ""
	for r in rarity_buttons:
		if rarity_buttons[r].button_pressed:
			rarity = r
	var shown := 0
	for id in tiles:
		var card: Dictionary = CardDB.CARDS[id]
		var show: bool = category == FILTER_ALL or card["cat"] == category
		if arch != "" and not id in CardDB.ARCHETYPES[arch]["cards"]:
			show = false
		if rarity != "" and card["rarity"] != rarity:
			show = false
		if only_deck.button_pressed and not deck.has(id):
			show = false
		if text != "" and not (card["name"].to_lower().contains(text) or card["desc"].to_lower().contains(text)
				or " ".join(CardDB.archetypes_of(id)).to_lower().contains(text)):
			show = false
		tiles[id]["panel"].visible = show
		shown += 1 if show else 0
	empty_grid.visible = shown == 0
	# O botão mostra quantos filtros estão ligados (e fica laranja).
	var active := (1 if arch != "" else 0) + (1 if rarity != "" else 0) + (1 if only_deck.button_pressed else 0)
	filter_button.text = "Filtros" if active == 0 else "Filtros  %d" % active
	if active > 0:
		filter_button.add_theme_stylebox_override("normal", Ui.box(Ui.SURFACE, 8, Ui.ACCENT))
		filter_button.add_theme_color_override("font_color", Ui.ACCENT.lightened(0.2))
	else:
		filter_button.remove_theme_stylebox_override("normal")
		filter_button.remove_theme_color_override("font_color")


# ---------------------------------------------------------------- baralho (direita)

func _build_deck_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := Ui.box(Ui.SURFACE.darkened(0.15), 14, Ui.LINE)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(14)
	panel.add_child(col)

	var head := Ui.hbox(6)
	col.add_child(head)
	name_edit = LineEdit.new()
	name_edit.text = GameState.decks[index]["name"]
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = 40
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.add_theme_font_override("font", Ui.bold())
	var plain := Ui.box(Color.TRANSPARENT, 8)
	plain.content_margin_left = 6
	name_edit.add_theme_stylebox_override("normal", plain)
	var editing := Ui.box(Ui.SURFACE, 8, Ui.ACCENT)
	editing.content_margin_left = 6
	name_edit.add_theme_stylebox_override("focus", editing)
	name_edit.tooltip_text = "Clique para mudar o nome"
	name_edit.text_changed.connect(func(_t): _save())
	head.add_child(name_edit)
	var more := MenuButton.new()
	more.text = "⋯"
	more.flat = false
	more.custom_minimum_size = Vector2(40, 40)
	more.tooltip_text = "Mais opções"
	more.get_popup().add_item("Completar com cartas aleatórias", 0)
	more.get_popup().add_item("Tirar todas as cartas", 1)
	more.get_popup().id_pressed.connect(_menu)
	head.add_child(more)

	var counter := Ui.vbox(6)
	col.add_child(counter)
	var count_row := Ui.hbox(8)
	counter.add_child(count_row)
	count_label = Ui.label("", 26, Ui.TEXT, true)
	count_row.add_child(count_label)
	status_label = Ui.label("", 14, Ui.MUTED)
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_row.add_child(Ui.spacer())
	count_row.add_child(status_label)
	count_bar = HBoxContainer.new()
	count_bar.add_theme_constant_override("separation", 0)
	counter.add_child(count_bar)

	col.add_child(_section_title("CARTA MESTRA"))
	master_slot = PanelContainer.new()
	master_slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	master_slot.tooltip_text = "Clique para trocar"
	master_slot.gui_input.connect(func(event: InputEvent):
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_picker())
	col.add_child(master_slot)

	var list_head := Ui.hbox(8)
	col.add_child(list_head)
	list_head.add_child(_section_title("CARTAS"))
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(list_scroll)
	deck_list = Ui.vbox(2)
	deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(deck_list)
	deck_empty = Ui.label("Clique nas cartas à esquerda para montar o baralho.", 14, Ui.MUTED)
	deck_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(deck_empty)

	# Sala de teste (TestRoom): só fora da sala online (lá a conexão segue aberta).
	var test := Ui.accent(Ui.button("Testar na sala de teste", _open_practice))
	test.custom_minimum_size.y = 44
	if Net.online:
		test.disabled = true
		test.tooltip_text = "Saia da sala online para usar a sala de teste"
	else:
		test.tooltip_text = "Bonecos de alvo, parkour e defesa, com a mestra deste baralho"
	col.add_child(test)
	return panel


func _refresh_master() -> void:
	for c in master_slot.get_children():
		c.queue_free()
	var card: Dictionary = CardDB.CARDS[master]
	var color: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var style := Ui.box(Ui.SURFACE, 10, color.darkened(0.2))
	style.set_content_margin_all(10)
	master_slot.add_theme_stylebox_override("panel", style)
	var row := Ui.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	master_slot.add_child(row)
	row.add_child(CardIcon.make(master, 40, 1, false))
	var names := Ui.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(names)
	var title := Ui.label(card["name"], 16, Ui.TEXT, true)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(title)
	var sub := Ui.label(_master_sub(master), 12, Ui.MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(sub)
	var change := Ui.label("Trocar  ›", 13, Ui.MUTED)
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(change)


## "Arma  ·  Q, 18 s" ou "Corpo  ·  passiva".
func _master_sub(id: String) -> String:
	var card: Dictionary = CardDB.CARDS[id]
	if card.has("cooldown"):
		return "%s  ·  %s, recarga %d s" % [card["cat"], GameState.key_text("master"), card["cooldown"]]
	return "%s  ·  passiva" % card["cat"]


func _refresh_list() -> void:
	for c in deck_list.get_children():
		c.queue_free()
	deck_empty.visible = deck.is_empty()
	for cat in CardDB.CATEGORY_COLORS:
		var ids: Array = []
		for id in CardDB.all_ids():
			if CardDB.CARDS[id]["cat"] == cat and deck.has(id):
				ids.append(id)
		if ids.is_empty():
			continue
		var n := deck.filter(func(id): return CardDB.CARDS[id]["cat"] == cat).size()
		var head := Ui.hbox(6)
		if deck_list.get_child_count() > 0:
			deck_list.add_child(Ui.gap(8))
		deck_list.add_child(head)
		head.add_child(Ui.label(cat.to_upper(), 12, CardDB.CATEGORY_COLORS[cat].lerp(Ui.MUTED, 0.3), true))
		head.add_child(Ui.spacer())
		head.add_child(Ui.label(str(n), 12, Ui.MUTED, true))
		for id in ids:
			deck_list.add_child(_deck_row(id))


## Linha do baralho: ícone, nome e cópias. Clique (ou botão direito) tira uma cópia.
func _deck_row(id: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Clique para tirar uma cópia"
	var normal := Ui.box(Color.TRANSPARENT, 6)
	normal.set_content_margin_all(4)
	normal.content_margin_left = 6
	normal.content_margin_right = 8
	var hot := Ui.box(Ui.SURFACE_HI, 6)
	hot.set_content_margin_all(4)
	hot.content_margin_left = 6
	hot.content_margin_right = 8
	row.add_theme_stylebox_override("panel", normal)
	var line := Ui.hbox(10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	line.add_child(CardIcon.make(id, 24, 1, false))
	var name_label := Ui.label(CardDB.card_name(id), 14, Ui.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	var copies := Ui.label("x%d" % deck.count(id), 14, Ui.MUTED, true)
	copies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(copies)
	row.mouse_entered.connect(func():
		row.add_theme_stylebox_override("panel", hot)
		copies.text = "−"
		copies.add_theme_color_override("font_color", Ui.DANGER))
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", normal)
		copies.text = "x%d" % deck.count(id)
		copies.add_theme_color_override("font_color", Ui.MUTED))
	row.gui_input.connect(func(event: InputEvent):
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			_change(id, -1))
	return row


# ---------------------------------------------------------------- escolha da mestra

func _build_picker() -> void:
	picker = Control.new()
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.visible = false
	add_child(picker)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			picker.visible = false)
	picker.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picker.add_child(center)
	var box := PanelContainer.new()
	var style := Ui.box(Ui.SURFACE, 14, Ui.LINE)
	style.set_content_margin_all(24)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var col := Ui.vbox(16)
	box.add_child(col)
	var head := Ui.hbox(10)
	col.add_child(head)
	var titles := Ui.vbox(2)
	head.add_child(titles)
	titles.add_child(Ui.label("Carta mestra", 22, Ui.TEXT, true))
	titles.add_child(Ui.label("Uma por baralho. Você começa toda partida com ela.", 14, Ui.MUTED))
	head.add_child(Ui.spacer())
	var close := Ui.flat(Ui.button("Fechar", func(): picker.visible = false))
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(close)
	# Grupos em abas (como na coleção) e a grade rolando: as mestras não cabem numa tela.
	var cats: Array = [FILTER_ALL] + CardDB.CATEGORY_COLORS.keys()
	var colors: Array = [Ui.ACCENT] + CardDB.CATEGORY_COLORS.values()
	col.add_child(Ui.tabs(cats, 0, func(i):
		picker_group = cats[i]
		_fill_picker(), colors))
	var options_scroll := ScrollContainer.new()
	options_scroll.name = "OptionsScroll"
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.thin_scrollbar(options_scroll)
	col.add_child(options_scroll)
	var options := GridContainer.new()
	options.name = "Options"
	options.columns = 3
	options.add_theme_constant_override("h_separation", 12)
	options.add_theme_constant_override("v_separation", 12)
	options_scroll.add_child(options)


func _open_picker() -> void:
	picker.visible = true
	_fill_picker()


## Mestras do grupo escolhido, na ordem dos grupos; a área rola acima de ~70% da tela.
func _fill_picker() -> void:
	var options: GridContainer = picker.find_child("Options", true, false)
	for c in options.get_children():
		options.remove_child(c)
		c.queue_free()
	var cats: Array = CardDB.CATEGORY_COLORS.keys()
	var ids: Array = CardDB.master_ids().filter(func(id):
		return picker_group == FILTER_ALL or CardDB.CARDS[id]["cat"] == picker_group)
	ids.sort_custom(func(a, b):
		return cats.find(CardDB.CARDS[a]["cat"]) < cats.find(CardDB.CARDS[b]["cat"]))
	for id in ids:
		options.add_child(_master_option(id))
	var options_scroll: ScrollContainer = picker.find_child("OptionsScroll", true, false)
	# Largura fixa de 3 cartas mais a barra (não pula ao trocar de grupo); altura medida
	# depois de as descrições quebrarem a linha.
	options_scroll.custom_minimum_size.x = 3 * 250 + 2 * 12 + 14
	options_scroll.scroll_vertical = 0
	await get_tree().process_frame
	options_scroll.custom_minimum_size.y = minf(options.get_combined_minimum_size().y, size.y * 0.7 - 120.0)


func _master_option(id: String) -> Control:
	var card: Dictionary = CardDB.CARDS[id]
	var color: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var chosen := id == master
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", CardFrame.style(card["cat"], "hot" if chosen else "lit", true, 14))
	panel.gui_input.connect(func(event: InputEvent):
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			master = id
			_save()
			_refresh_master()
			picker.visible = false)
	var col := Ui.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var head := Ui.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	head.add_child(CardIcon.make(id, 40, 1, false))
	var names := Ui.vbox(0)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var title := Ui.label(card["name"], 16, Ui.TEXT, true)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(title)
	var sub := Ui.label(_master_sub(id), 12, color.lerp(Ui.MUTED, 0.4))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(sub)
	if chosen:
		var tag := Ui.label("Equipada", 12, Ui.OK, true)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		head.add_child(tag)
	var desc := Ui.label(card["desc"], 13, Ui.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 222
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc)
	return panel


# ---------------------------------------------------------------- comum

func _fit() -> void:
	# Painel do baralho: um quarto da largura (entre 300 e 400 px); a grade usa o resto.
	side_panel.custom_minimum_size.x = clampf(size.x * 0.25, 300.0, 400.0)
	await get_tree().process_frame
	grid.columns = maxi(2, int((scroll.size.x - 14.0 + GAP) / (TILE_WIDTH + GAP)))


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
		status_label.text = "Faltam %d" % (CardDB.DECK_MIN - n)
		status_label.add_theme_color_override("font_color", Ui.WARN)
	else:
		status_label.text = "Baralho cheio" if n == CardDB.DECK_MAX else "Pronto para jogar"
		status_label.add_theme_color_override("font_color", Ui.OK)
	for c in count_bar.get_children():
		c.queue_free()
	var bar := Ui.category_bar(deck, 6.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_stretch_ratio = maxf(n, 0.001)
	count_bar.add_child(bar)
	if n < CardDB.DECK_MAX:
		var rest := ColorRect.new()
		rest.color = Ui.LINE
		rest.custom_minimum_size.y = 6
		rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rest.size_flags_stretch_ratio = CardDB.DECK_MAX - n
		count_bar.add_child(rest)
	for id in tiles:
		_style_tile(id)
	_refresh_master()
	_refresh_list()
	_apply_filter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if picker.visible:
			picker.visible = false
		else:
			_back()
		get_viewport().set_input_as_handled()


## Na sala online: o anfitrião começou enquanto você editava.
func _on_match_starting() -> void:
	_save()
	GameState.go_to_match()


func _open_practice() -> void:
	_save()
	GameState.editing = index
	GameState.practice = true
	get_tree().change_scene_to_file("res://scenes/match.tscn")


func _back() -> void:
	_save()
	get_tree().change_scene_to_file("res://scenes/decks.tscn")
