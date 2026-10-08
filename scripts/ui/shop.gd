extends Control
## Loja (2026-10-08, desenho do usuário): Pacotes (o jeito principal de ganhar cartas),
## Ofertas (3 cartas que trocam a cada 8 h; travar segura a carta) e Fichas (cópias a mais
## viram fichas da raridade, trocadas por uma carta à escolha). Regras e números em
## Collection. Em modo de teste mostra "Repor moedas" e "Zerar coleção".
## Primeira visita com o Pacote de Mestra fechado: ele abre sozinho.

const TABS := ["Pacotes", "Ofertas", "Fichas"]

var tab := 0
var body: VBoxContainer
var coins_label: Label
var progress_label: Label
var opening: PackOpening
var _token_rarity := ""      # Fichas: raridade escolhida para trocar
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
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := Ui.vbox(18)
	margin.add_child(column)

	var header := Ui.hbox(16)
	column.add_child(header)
	var back := Ui.flat(Ui.button("‹  Menu", _back))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(back)
	var titles := Ui.vbox(2)
	titles.add_child(Ui.label("Loja", 32, Ui.TEXT, true))
	progress_label = Ui.label("", 15, Ui.MUTED)
	titles.add_child(progress_label)
	header.add_child(titles)
	header.add_child(Ui.spacer())
	if Collection.TEST_MODE:
		var test := Ui.vbox(4)
		test.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		test.add_child(Ui.label("MODO DE TESTE", 11, Ui.WARN, true))
		var row := Ui.hbox(6)
		row.add_child(Ui.flat(Ui.button("Repor moedas", func(): Collection.test_refill())))
		row.add_child(Ui.flat(Ui.button("Zerar coleção", _reset)))
		test.add_child(row)
		header.add_child(test)
	var wallet := PanelContainer.new()
	var ws := Ui.box(Ui.SURFACE, 10, Ui.LINE)
	ws.content_margin_left = 16
	ws.content_margin_right = 16
	ws.content_margin_top = 8
	ws.content_margin_bottom = 8
	wallet.add_theme_stylebox_override("panel", ws)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins_label = Ui.label("", 20, Ui.WARN, true)
	wallet.add_child(coins_label)
	header.add_child(wallet)

	var tabs := Ui.tabs(TABS, 0, func(i): tab = i; _token_rarity = ""; _fill())
	tabs.custom_minimum_size.x = 420
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.thin_scrollbar(scroll)
	column.add_child(scroll)
	body = Ui.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	opening = PackOpening.new()
	opening.visible = false
	add_child(opening)
	opening.finished.connect(func(): opening.visible = false; _fill())
	opening.again.connect(func(): _open(opening.pack_id))
	Collection.changed.connect(_update_header)
	Collection.refresh_offers()
	_update_header()
	_fill()
	if Collection.master_pack:
		_open.call_deferred("mestra")


func _process(delta: float) -> void:
	# Contagem até a troca das ofertas; na virada, sorteia de novo.
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.text = "Trocam em %s" % _time_text(Collection.seconds_to_rotation())
	var before := Collection.offer_window
	Collection.refresh_offers()
	if Collection.offer_window != before and tab == 1:
		_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not opening.visible:
		get_viewport().set_input_as_handled()
		if _token_rarity != "":
			_token_rarity = ""
			_fill()
		else:
			_back()


func _update_header() -> void:
	coins_label.text = "%s moedas" % _thousands(Collection.coins)
	var p := Collection.progress()
	progress_label.text = "Coleção: %d de %d cópias (%d%%)" % [p.x, p.y, roundi(100.0 * p.x / maxf(1.0, p.y))]


func _fill() -> void:
	for c in body.get_children():
		c.queue_free()
	_timer_label = null
	match tab:
		0: _packs_page()
		1: _offers_page()
		2: _tokens_page()


# ---------------------------------------------------------------- pacotes

func _packs_page() -> void:
	body.add_child(Ui.label("O jeito principal de ganhar cartas. A última carta de cada pacote é a garantida; as mais raras aparecem por último.", 15, Ui.MUTED))
	if Collection.master_pack:
		var b := Ui.accent(Ui.button("Abrir o Pacote de Mestra inicial", _open.bind("mestra")))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		body.add_child(b)
	var row := Ui.hbox(20)
	body.add_child(row)
	for id in Collection.SHOP_PACKS:
		row.add_child(_pack_tile(id))


func _pack_tile(id: String) -> Control:
	var pack: Dictionary = Collection.PACKS[id]
	var color: Color = pack["color"]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Ui.box(Ui.SURFACE, 14, color.darkened(0.2), 2)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(10)
	panel.add_child(col)
	# A "arte" do pacote: um retângulo na cor do tier.
	var art := PanelContainer.new()
	art.custom_minimum_size = Vector2(0, 120)
	art.add_theme_stylebox_override("panel", Ui.box(color.darkened(0.55), 12, color, 2))
	var art_col := Ui.vbox(2)
	art_col.alignment = BoxContainer.ALIGNMENT_CENTER
	art.add_child(art_col)
	for t in [["FUROR", 30, Color.WHITE], ["%d cartas" % pack["cards"], 14, color.lightened(0.3)]]:
		var l := Ui.label(t[0], t[1], t[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_col.add_child(l)
	col.add_child(art)
	col.add_child(Ui.label(pack["name"], 22, Ui.TEXT, true))
	col.add_child(Ui.label("Garante %s" % pack["promise"], 15, color.lightened(0.2), true))
	col.add_child(Ui.label("Chance de cada carta:", 13, Ui.MUTED))
	for r in Collection.RARITY_ORDER:
		var chance: float = pack["odds"].get(r, 0.0)
		if chance <= 0.0:
			continue
		var line := Ui.hbox(8)
		line.add_child(Ui.label(CardDB.RARITIES[r]["name"], 14, CardDB.RARITIES[r]["color"]))
		line.add_child(Ui.spacer())
		line.add_child(Ui.label(_percent(chance), 14, Ui.TEXT))
		col.add_child(line)
	col.add_child(Ui.grow())
	var buy := Ui.accent(Ui.button("Abrir  ·  %s moedas" % _thousands(pack["price"]), _open.bind(id)))
	buy.custom_minimum_size.y = 46
	buy.disabled = Collection.coins < pack["price"]
	col.add_child(buy)
	return panel


func _open(pack_id: String) -> void:
	var results := Collection.open_pack(pack_id)
	if results.is_empty():
		opening.visible = false
		_fill()
		return
	opening.open(pack_id, results, pack_id != "mestra")


# ---------------------------------------------------------------- ofertas

func _offers_page() -> void:
	var head := Ui.hbox(12)
	body.add_child(head)
	head.add_child(Ui.label("Uma épica, uma lendária e uma mestra. Para pegar uma carta específica que falta; trave para ela não trocar enquanto junta moedas.", 15, Ui.MUTED))
	head.add_child(Ui.spacer())
	_timer_label = Ui.label("Trocam em %s" % _time_text(Collection.seconds_to_rotation()), 15, Ui.TEXT, true)
	head.add_child(_timer_label)
	var row := Ui.hbox(28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	for i in Collection.offers.size():
		row.add_child(_offer_tile(i))


func _offer_tile(slot: int) -> Control:
	var o: Dictionary = Collection.offers[slot]
	var col := Ui.vbox(10)
	col.custom_minimum_size.x = 260
	if o["id"] == "":
		var empty := Ui.label("Você já tem todas as cartas %s." % Collection.RARITY_FEM_PLURAL[o["rarity"]], 15, Ui.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(empty)
		return col
	col.add_child(CardFace.make(o["id"], 260, 96))
	var have := Collection.has_card(o["id"])
	var info := Ui.label("Você tem %d/%d" % [have, Collection.max_copies(o["id"])], 14, Ui.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)
	var buttons := Ui.hbox(8)
	col.add_child(buttons)
	var lock := Ui.button("Travada" if o["locked"] else "Travar", func():
		Collection.toggle_lock(slot)
		_fill())
	lock.tooltip_text = "Travada, esta vaga não troca a cada 8 h"
	lock.disabled = o["bought"]
	if o["locked"]:
		Ui.accent(lock)
	buttons.add_child(lock)
	var price: int = Collection.OFFER_PRICES[o["rarity"]]
	var buy := Ui.accent(Ui.button("Comprada" if o["bought"] else "Comprar  ·  %s" % _thousands(price), func():
		if Collection.buy_offer(slot):
			Sfx.ui(self, "kill")
		_fill()))
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = o["bought"] or Collection.coins < price or Collection.is_full(o["id"])
	buttons.add_child(buy)
	return col


# ---------------------------------------------------------------- fichas

func _tokens_page() -> void:
	body.add_child(Ui.label("Cada carta vai até 3 cópias (mestra até 1). A cópia a mais vira uma ficha da raridade, e as fichas trocam por uma carta que você escolhe.", 15, Ui.MUTED))
	for r in Collection.RARITY_ORDER:
		body.add_child(_token_row(r))
	if _token_rarity != "":
		_token_picker()


func _token_row(r: String) -> Control:
	var panel := PanelContainer.new()
	var on := r == _token_rarity
	var style := Ui.box(Ui.SURFACE_HI if on else Ui.SURFACE, 10, CardDB.RARITIES[r]["color"].darkened(0.3) if on else Ui.LINE)
	style.content_margin_left = 18
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var row := Ui.hbox(16)
	panel.add_child(row)
	var name_label := Ui.label("Fichas %s" % Collection.RARITY_FEM_PLURAL[r], 17, CardDB.RARITIES[r]["color"], true)
	name_label.custom_minimum_size.x = 220
	row.add_child(name_label)
	var have: int = Collection.tokens.get(r, 0)
	var rate: int = Collection.TOKEN_RATES[r]
	row.add_child(Ui.label("%d" % have, 22, Ui.TEXT, true))
	row.add_child(Ui.label("%d fichas = 1 carta %s à escolha" % [rate, Collection.RARITY_FEM[r]], 14, Ui.MUTED))
	row.add_child(Ui.spacer())
	var pick := Ui.button("Fechar" if on else "Escolher carta", func():
		_token_rarity = "" if on else r
		_fill(), 170)
	pick.disabled = have < rate and not on
	row.add_child(pick)
	return panel


## Cartas da raridade que ainda não estão completas; clique troca as fichas por uma cópia.
func _token_picker() -> void:
	var r := _token_rarity
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for id in Collection.ids_of(r):
		if Collection.is_full(id):
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = CardIcon._wrap(CardDB.CARDS[id]["desc"], 52)
		b.pressed.connect(func():
			if Collection.exchange(id):
				Sfx.ui(self, "kill")
			if Collection.tokens.get(r, 0) < Collection.TOKEN_RATES[r]:
				_token_rarity = ""
			_fill())
		var row := Ui.hbox(10)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		row.offset_right = -8
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		row.add_child(CardIcon.make(id, 34, 1, false))
		var l := Ui.label(CardDB.card_name(id), 14, Ui.TEXT, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
		var c := Ui.label("%d/%d" % [Collection.has_card(id), Collection.max_copies(id)], 14, Ui.MUTED, true)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(c)
		grid.add_child(b)


# ---------------------------------------------------------------- comum

func _reset() -> void:
	Collection.test_reset()
	_fill()
	if Collection.master_pack:
		_open("mestra")


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


static func _percent(x: float) -> String:
	var p := x * 100.0
	return ("%.1f%%" % p).replace(".", ",") if p < 10.0 and absf(p - roundf(p)) > 0.01 else "%d%%" % roundi(p)


static func _time_text(sec: int) -> String:
	var h := sec / 3600
	var m := (sec % 3600) / 60
	return "%d h %02d min" % [h, m] if h > 0 else "%d min %02d s" % [m, sec % 60]
