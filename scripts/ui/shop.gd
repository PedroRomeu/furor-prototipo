extends Control
## Loja (2026-10-08, desenho do usuário; numa página só desde 2026-10-11): Pacote de Mestra
## (quando houver), Pacotes (o jeito principal de ganhar cartas) e Ofertas (3 cartas que
## trocam a cada 8 h; travar segura a carta). As fichas (cópias a mais) são gastas no editor
## de baralho, no modo "Criar cartas". Regras e números em Collection. Em modo de teste o
## menu "⋯" repõe moedas e fichas e zera a coleção.
## Primeira visita com o Pacote de Mestra fechado: ele abre sozinho.

const PAGE_MAX := 1440.0   # largura máxima do conteúdo em tela larga
const OFFER_WIDTH := 240.0

var body: VBoxContainer
var coins_label: Label
var tokens_row: HBoxContainer
var progress_label: Label
var opening: PackOpening
var _timer_label: Label
var _tick := 0.0


func _ready() -> void:
	theme = Ui.theme()
	Ui.background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := Ui.vbox(14)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	resized.connect(_fit_width.bind(column))

	var header := Ui.hbox(16)
	column.add_child(header)
	var back := Ui.flat(Ui.button("‹  Menu", _back))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(back)
	var titles := Ui.vbox(2)
	titles.add_child(Ui.label(tr("Shop"), 32, Ui.TEXT, true))
	progress_label = Ui.label("", 14, Ui.MUTED)
	titles.add_child(progress_label)
	header.add_child(titles)
	header.add_child(Ui.spacer())
	header.add_child(_wallet())
	if Collection.TEST_MODE:
		header.add_child(_test_menu())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.thin_scrollbar(scroll)
	column.add_child(scroll)
	var pad := MarginContainer.new()   # espaço para a barra de rolagem não cobrir a direita
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 14)
	scroll.add_child(pad)
	body = Ui.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(body)

	opening = PackOpening.new()
	opening.visible = false
	add_child(opening)
	opening.finished.connect(func(): opening.visible = false; _fill())
	opening.again.connect(func(): _open(opening.pack_id))
	Collection.changed.connect(_update_header)
	Collection.refresh_offers()
	_update_header()
	_fill()
	_fit_width.call_deferred(column)
	if Collection.master_packs > 0:
		_open.call_deferred("mestra")


## Em tela larga o conteúdo fica centralizado em até PAGE_MAX.
func _fit_width(column: VBoxContainer) -> void:
	var margin: MarginContainer = column.get_parent()
	var side := maxf(48.0, (size.x - PAGE_MAX) * 0.5)
	margin.add_theme_constant_override("margin_left", int(side))
	margin.add_theme_constant_override("margin_right", int(side))


func _process(delta: float) -> void:
	# Contagem até a troca das ofertas; na virada, sorteia de novo.
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.text = tr("Changes in %s") % _time_text(Collection.seconds_to_rotation())
	var before := Collection.offer_window
	Collection.refresh_offers()
	if Collection.offer_window != before:
		_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not opening.visible:
		get_viewport().set_input_as_handled()
		_back()


## Moedas em destaque e as fichas de cada raridade embaixo, pequenas, na cor da raridade.
func _wallet() -> Control:
	var wallet := PanelContainer.new()
	var ws := Ui.box(Ui.SURFACE, 10, Ui.LINE)
	ws.content_margin_left = 16
	ws.content_margin_right = 16
	ws.content_margin_top = 6
	ws.content_margin_bottom = 8
	wallet.add_theme_stylebox_override("panel", ws)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet.tooltip_text = tr("Copies beyond the max turn into tokens of their rarity.\nSpend tokens in the deck editor, under \"Craft cards\".")
	var col := Ui.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(col)
	coins_label = Ui.label("", 20, Ui.WARN, true)
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(coins_label)
	tokens_row = Ui.hbox(10)
	tokens_row.alignment = BoxContainer.ALIGNMENT_END
	tokens_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tokens_row)
	return wallet


func _test_menu() -> Control:
	var more := MenuButton.new()
	more.text = "⋯"
	more.flat = false
	more.custom_minimum_size = Vector2(40, 40)
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more.tooltip_text = tr("Test mode")
	var popup := more.get_popup()
	popup.add_separator(tr("Test mode"))
	popup.add_item(tr("Refill coins"), 0)
	popup.add_item(tr("Refill tokens"), 1)
	popup.add_item(tr("Reset collection"), 2)
	popup.id_pressed.connect(_test_action)
	return more


func _test_action(id: int) -> void:
	match id:
		0: Collection.test_refill()
		1: Collection.test_refill_tokens()
		2: _reset()


func _update_header() -> void:
	coins_label.text = tr("%s coins") % _thousands(Collection.coins)
	for c in tokens_row.get_children():
		c.queue_free()
	tokens_row.add_child(Ui.label(tr("Tokens"), 12, Ui.MUTED))
	for r in Collection.RARITY_ORDER:
		var l := Ui.label(str(Collection.tokens.get(r, 0)), 12, CardDB.RARITIES[r]["color"], true)
		l.tooltip_text = Collection.tokens_label(r)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		tokens_row.add_child(l)
	var p := Collection.progress()
	progress_label.text = tr("Collection: %d of %d copies (%d%%)") % [p.x, p.y, roundi(100.0 * p.x / maxf(1.0, p.y))]


func _fill() -> void:
	for c in body.get_children():
		c.queue_free()
	_timer_label = null
	if Collection.master_packs > 0:
		body.add_child(_master_banner())
	var hint := Ui.label(tr("the last card is the guaranteed one"), 12, Ui.MUTED)
	Ui.section(body, tr("PACKS"), hint, 8)
	var row := Ui.hbox(20)
	body.add_child(row)
	for id in Collection.SHOP_PACKS:
		row.add_child(_pack_tile(id))
	_timer_label = Ui.label(tr("Changes in %s") % _time_text(Collection.seconds_to_rotation()), 13, Ui.TEXT, true)
	Ui.section(body, tr("CURRENT OFFERS"), _timer_label)
	if Collection.offers.all(func(o): return o["id"] == ""):
		body.add_child(Ui.label(tr("You already have every epic, legendary and master card."), 13, Ui.MUTED))
		body.add_child(Ui.gap(12))
		return
	var note := Ui.label(tr("One epic, one legendary and one master. Lock one so it doesn't change while you save up coins."), 13, Ui.MUTED)
	body.add_child(note)
	var offers := Ui.hbox(28)
	offers.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(offers)
	for i in Collection.offers.size():
		offers.add_child(_offer_tile(i))
	body.add_child(Ui.gap(12))


# ---------------------------------------------------------------- pacotes

## Faixa do Pacote de Mestra fechado (o do começo e os das missões semanais).
func _master_banner() -> Control:
	var pack: Dictionary = Collection.PACKS["mestra"]
	var color: Color = pack["color"]
	var panel := PanelContainer.new()
	var style := Ui.box(color.darkened(0.78), 12, color.darkened(0.15), 2)
	style.content_margin_left = 20
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var row := Ui.hbox(16)
	panel.add_child(row)
	var texts := Ui.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var n := Collection.master_packs
	texts.add_child(Ui.label(Collection.pack_name("mestra") + (" ×%d" % n if n > 1 else ""), 18, Ui.TEXT, true))
	texts.add_child(Ui.label(tr("One master card. Earn more in weekly missions."), 13, Ui.MUTED))
	var b := Ui.accent(Ui.button(tr("Open"), _open.bind("mestra"), 160))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	return panel


func _pack_tile(id: String) -> Control:
	var pack: Dictionary = Collection.PACKS[id]
	var color: Color = pack["color"]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Ui.box(Ui.SURFACE, 14, color.darkened(0.2), 2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	panel.tooltip_text = _odds_text(id)
	var col := Ui.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	# A "arte" do pacote: um retângulo na cor do tier.
	var art := PanelContainer.new()
	art.custom_minimum_size = Vector2(0, 92)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_theme_stylebox_override("panel", Ui.box(color.darkened(0.55), 12, color, 2))
	var art_col := Ui.vbox(0)
	art_col.alignment = BoxContainer.ALIGNMENT_CENTER
	art_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(art_col)
	for t in [["FUROR", 28, Color.WHITE], [tr_n("%d card", "%d cards", pack["cards"]) % pack["cards"], 13, color.lightened(0.3)]]:
		var l := Ui.label(t[0], t[1], t[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_col.add_child(l)
	col.add_child(art)
	var name_row := Ui.hbox(8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	name_row.add_child(Ui.label(Collection.pack_name(id), 20, Ui.TEXT, true))
	name_row.add_child(Ui.spacer())
	var promise := Ui.label(tr("Guarantees %s") % Collection.pack_promise(id), 13, color.lightened(0.2), true)
	promise.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(promise)
	col.add_child(_odds_bar(pack["odds"]))
	var buy := Ui.accent(Ui.button(tr("Open  ·  %s coins") % _thousands(pack["price"]), _open.bind(id)))
	buy.custom_minimum_size.y = 42
	buy.disabled = Collection.coins < pack["price"]
	col.add_child(buy)
	return panel


## Barra fina com as chances de raridade de cada carta, nas cores das raridades (os números
## estão na dica do pacote). Raridade rara demais ganha um mínimo para não sumir.
func _odds_bar(odds: Dictionary) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	bar.custom_minimum_size.y = 6
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in Collection.RARITY_ORDER:
		var chance: float = odds.get(r, 0.0)
		if chance <= 0.0:
			continue
		var piece := ColorRect.new()
		piece.color = CardDB.RARITIES[r]["color"]
		piece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		piece.size_flags_stretch_ratio = maxf(chance, 0.012)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(piece)
	return bar


func _odds_text(id: String) -> String:
	var pack: Dictionary = Collection.PACKS[id]
	var lines := PackedStringArray([tr("Chance for each card:")])
	for r in Collection.RARITY_ORDER:
		var chance: float = pack["odds"].get(r, 0.0)
		if chance > 0.0:
			lines.append("%s  %s" % [CardDB.rarity_label(r), _percent(chance)])
	lines.append(tr("The last card guarantees %s.") % Collection.pack_promise(id))
	return "\n".join(lines)


func _open(pack_id: String) -> void:
	var results := Collection.open_pack(pack_id)
	if results.is_empty():
		opening.visible = false
		_fill()
		return
	opening.open(pack_id, results, pack_id != "mestra")


# ---------------------------------------------------------------- ofertas

func _offer_tile(slot: int) -> Control:
	var o: Dictionary = Collection.offers[slot]
	var col := Ui.vbox(8)
	col.custom_minimum_size.x = OFFER_WIDTH
	if o["id"] == "":
		var slot_box := PanelContainer.new()
		slot_box.custom_minimum_size.y = 300
		var style := Ui.box(Color.TRANSPARENT, 16, Ui.LINE)
		style.set_content_margin_all(20)
		slot_box.add_theme_stylebox_override("panel", style)
		var empty := Ui.label(tr("You already have every %s card.") % Collection.rarity_fem(o["rarity"], true), 14, Ui.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_box.add_child(empty)
		col.add_child(slot_box)
		return col
	col.add_child(CardFace.make(o["id"], OFFER_WIDTH, 80))
	var have := Collection.has_card(o["id"])
	var info := Ui.label(tr("You have %d/%d") % [have, Collection.max_copies(o["id"])], 13, Ui.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)
	var buttons := Ui.hbox(8)
	col.add_child(buttons)
	var lock := Ui.button(tr("Locked") if o["locked"] else tr("Lock"), func():
		Collection.toggle_lock(slot)
		_fill())
	lock.tooltip_text = tr("Locked, this slot doesn't change every 8 h")
	lock.disabled = o["bought"]
	if o["locked"]:
		Ui.accent(lock)
	buttons.add_child(lock)
	var price: int = Collection.OFFER_PRICES[o["rarity"]]
	var buy := Ui.accent(Ui.button(tr("Bought") if o["bought"] else tr("Buy  ·  %s") % _thousands(price), func():
		if Collection.buy_offer(slot):
			Sfx.ui(self, "kill")
		_fill()))
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = o["bought"] or Collection.coins < price or Collection.is_full(o["id"])
	buttons.add_child(buy)
	return col


# ---------------------------------------------------------------- comum

func _reset() -> void:
	Collection.test_reset()
	_fill()
	if Collection.master_packs > 0:
		_open("mestra")


func _back() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")   # adiado: ver deck_editor._back


## Milhares com o separador do idioma (1,000 / 1.000).
static func _thousands(n: int) -> String:
	return Missions.num(n)


static func _percent(x: float) -> String:
	var p := x * 100.0
	return Lang.num(p, 1) + "%" if p < 10.0 and absf(p - roundf(p)) > 0.01 else "%d%%" % roundi(p)


static func _time_text(sec: int) -> String:
	var h := sec / 3600
	var m := (sec % 3600) / 60
	return "%d h %02d min" % [h, m] if h > 0 else "%d min %02d s" % [m, sec % 60]
