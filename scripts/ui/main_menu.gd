extends Control
## Menu principal, em páginas: Início (Jogar, Baralhos, Loja, Personalizar, Configurações, Sair),
## Jogar (treino contra bots ou online), Sala (quem entrou; o anfitrião começa quando
## quiser), Personalizar (personagem e arma, só aparência) e Configurações. Esc volta uma
## página.
##
## Online, quem cria a sala espera os amigos entrarem e clica em Começar. A partida é cada
## um por si com quem estiver na sala (2 a 4 jogadores); com 4, o anfitrião pode escolher
## 2x2 e arrumar os times. Na sala cada um troca o próprio nome (vale na hora para todos),
## troca ou edita o baralho e conversa no chat, embaixo da lista de jogadores.

enum Page { HOME, PLAY, LOBBY, SETTINGS, CUSTOM }

const SETTINGS_PATH := "user://settings.cfg"

var page := Page.HOME
var pages := {}
var ip_edit: LineEdit
var join_button: Button
var host_button: Button
var play_status: Label
var bot_count := 1
var lobby_title: Label
var lobby_slots: VBoxContainer
var lobby_info: Label
var start_button: Button
var deck_picks: Array = []   # OptionButton do baralho em Jogar e na Sala, sempre iguais
var solo_modes: ModePicker   # modo do treino
var solo_bots: HSlider       # quantos bots (1 a 3; slider, pedido do usuário)
var solo_bots_label: Label
var bots_hint: Label         # frase da linha dos bots: que tamanhos de mapa saem
const LEVEL_HINTS := ["Mira e reage devagar; quase não usa o escudo.",
	"Reage como gente; só defende o que vê chegar.", "Reflexos rápidos: o bot de sempre."]
var start_solo: Button
var lobby_modes: ModePicker  # modo da sala (só o anfitrião mexe)
var maps_button: Button      # abre a lista de mapas da sala (MapPicker)
var maps_hint: Label         # "8 de 12 ligados" na linha dos mapas
const LOBBY_CONTROL := 300.0 # coluna dos controles na Sala
var map_picker: MapPicker
var shuffle_button: Button
var nick_edits: Array = []   # o campo de nome aparece na Sala e em Configurações
var nick_timer: Timer        # espera a pessoa parar de digitar para mandar o nome à sala
var settings: SettingsPanel
var custom_back := Page.HOME   # Personalizar volta para onde foi aberto (Início ou Sala)
var custom_tab := 0            # 0 personagem, 1 arma
var preview: LookPreview
var look_name: Label
var look_grid: GridContainer
var lobby_look: Array = []     # [miniatura, nome] do visual na Sala


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.lobby_changed.connect(func(_c): _refresh_lobby())
	Net.joined.connect(_on_joined)
	Net.match_starting.connect(_on_match_starting)
	Net.failed.connect(_on_failed)
	Net.disconnected.connect(_on_lost)
	bot_count = GameState.bot_count

	theme = Ui.theme()
	Ui.background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var stack := Control.new()
	margin.add_child(stack)
	pages[Page.HOME] = _home_page()
	pages[Page.PLAY] = _play_page()
	pages[Page.LOBBY] = _lobby_page()
	pages[Page.SETTINGS] = _settings_page()
	pages[Page.CUSTOM] = _custom_page()
	for p in pages.values():
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
	map_picker = MapPicker.new()
	add_child(map_picker)
	_show(Page.HOME)
	var came_back := GameState.from_lobby
	if GameState.from_lobby:
		# Voltando dos Baralhos com a sala aberta.
		GameState.from_lobby = false
		var peer := multiplayer.multiplayer_peer
		if Net.online and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_show(Page.LOBBY)
			_refresh_lobby()
		else:
			Net.stop()
			_show(Page.PLAY)
			_play_error("A conexão com a sala caiu.")

	# Testes automáticos: "-- --autotest --solo" (contra bots, com --bots=2 para dois),
	# e em rede "--host" (começa com 1 convidado), "--host3" (espera 2), "--host4" (espera 3)
	# e "--join".
	# Adiado: trocar de cena dentro do _ready da cena inicial dá erro.
	var args := OS.get_cmdline_user_args()
	if came_back:
		pass   # de volta à sala: a conexão já existe
	elif _autotest_players() > 0:
		_host.call_deferred()
	elif "--solo" in args:
		_play_bots.call_deferred()
	elif "--join" in args:
		ip_edit.text = "127.0.0.1"
		_join.call_deferred()


func _show(p: Page) -> void:
	page = p
	if map_picker and p != Page.LOBBY:
		map_picker.close()
	for k in pages:
		pages[k].visible = k == p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match page:
			Page.PLAY, Page.SETTINGS:
				settings.stop_rebind()
				_show(Page.HOME)
			Page.CUSTOM:
				_close_custom()
			Page.LOBBY:
				if map_picker.visible:
					map_picker.close()
				else:
					_leave_lobby()


# ---------------------------------------------------------------- páginas

## Início: título e as ações principais numa coluna à esquerda; o baralho equipado embaixo.
func _home_page() -> Control:
	var root := Ui.vbox(0)
	var title := Ui.label("FUROR", 88, Ui.TEXT, true)
	root.add_child(title)
	root.add_child(Ui.label("Tiro com baralho de melhorias. Cada um por si.", 18, Ui.MUTED))
	root.add_child(Ui.gap(48))
	var menu := Ui.vbox(10)
	menu.custom_minimum_size.x = 320
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.add_child(menu)
	var play := Ui.accent(_menu_button("JOGAR", func(): _show(Page.PLAY)))
	play.custom_minimum_size.y = 58
	play.add_theme_font_size_override("font_size", 22)
	menu.add_child(play)
	menu.add_child(_menu_button("Baralhos", _open_decks))
	menu.add_child(_menu_button("Loja", func(): get_tree().change_scene_to_file("res://scenes/shop.tscn")))
	menu.add_child(_menu_button("Personalizar", _open_custom))
	menu.add_child(_menu_button("Configurações", func(): _show(Page.SETTINGS)))
	menu.add_child(_menu_button("Sair", func(): get_tree().quit()))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(fill)
	root.add_child(_deck_card())
	return root


## Jogar (refeita em 2026-10-10, no padrão das Configurações): à esquerda os jeitos de
## jogar, à direita só o que está aberto. Um jeito novo (o singleplayer com moedas, depois)
## entra como mais uma linha em PLAY_TABS e mais uma página.
const PLAY_TABS := ["Treino", "Online"]
const PLAY_CONTENT_MAX := 940.0
static var _play_tab := "Treino"   # lembra o último aberto enquanto o jogo roda
var play_tabs := {}                # nome -> [botão da lista, página]
var play_footers := {}             # nome -> pé fixo da página (baralho e botão), fora da rolagem


func _play_page() -> Control:
	var root := Ui.vbox(24)
	root.add_child(_header("Jogar", "Escolha como quer jogar."))
	var body := Ui.hbox(28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var nav := Ui.vbox(2)
	nav.custom_minimum_size.x = 190
	body.add_child(nav)
	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Ui.box(Ui.SURFACE.darkened(0.15), 14, Ui.LINE)
	style.set_content_margin_all(0)
	holder.add_theme_stylebox_override("panel", style)
	body.add_child(holder)
	# Em tela larga o painel para em PLAY_CONTENT_MAX (como nas Configurações).
	body.resized.connect(func():
		var room := body.size.x - nav.custom_minimum_size.x - body.get_theme_constant("separation")
		holder.custom_minimum_size.x = minf(room, PLAY_CONTENT_MAX)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL if room <= PLAY_CONTENT_MAX else Control.SIZE_SHRINK_BEGIN)
	var group := ButtonGroup.new()
	var builders := {"Treino": _solo_page, "Online": _online_page}
	for title in PLAY_TABS:
		var b := Ui.nav_button(title, group)
		b.pressed.connect(_open_play_tab.bind(title))
		nav.add_child(b)
		# As opções rolam quando não cabem (1280x720); o pé (baralho e botão) fica sempre à vista.
		var page := Ui.vbox(0)
		page.visible = false
		holder.add_child(page)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		Ui.thin_scrollbar(scroll)
		page.add_child(scroll)
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for side in ["left", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 32)
		margin.add_theme_constant_override("margin_top", 28)
		margin.add_child(builders[title].call())
		scroll.add_child(margin)
		if play_footers.has(title):
			var foot := MarginContainer.new()
			for side in ["left", "right", "bottom"]:
				foot.add_theme_constant_override("margin_" + side, 32)
			foot.add_theme_constant_override("margin_top", 12)
			foot.add_child(play_footers[title])
			page.add_child(foot)
		play_tabs[title] = [b, page]
	_open_play_tab(_play_tab)
	return root


func _open_play_tab(title: String) -> void:
	_play_tab = title
	for t in play_tabs:
		play_tabs[t][0].set_pressed_no_signal(t == title)
		play_tabs[t][1].visible = t == title


## Treino: modo, bots e dificuldade; embaixo o baralho e o botão de começar.
func _solo_page() -> Control:
	var solo := Ui.vbox(0)
	solo.add_child(Ui.label("Treino", 24, Ui.TEXT, true))
	solo.add_child(Ui.label("Contra bots, no seu computador.", 14, Ui.MUTED))
	Ui.section(solo, "MODO")
	solo.add_child(Ui.gap(10))
	solo_modes = ModePicker.new(GameState.mode, GameState.lives)
	solo_modes.changed.connect(func(m, n):
		GameState.set_mode(m, n)
		if m == "teams":
			_set_bots(3)   # 2x2 no treino é você e um bot contra dois
		_refresh_solo())
	solo.add_child(solo_modes)
	Ui.section(solo, "ADVERSÁRIOS")
	# Slider de 1 a 3 com o número ao lado (como os de volume e sensibilidade).
	var bots := Ui.hbox(12)
	solo_bots = HSlider.new()
	solo_bots.min_value = 1
	solo_bots.max_value = 3
	solo_bots.step = 1
	solo_bots.tick_count = 3
	solo_bots.ticks_on_borders = true
	solo_bots.value = bot_count
	solo_bots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo_bots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bots.add_child(solo_bots)
	solo_bots_label = Ui.label("", 15, Ui.TEXT)
	solo_bots_label.custom_minimum_size.x = 56
	solo_bots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bots.add_child(solo_bots_label)
	solo_bots.value_changed.connect(func(v):
		bot_count = int(v)
		_refresh_solo())
	bots_hint = Ui.option_row(solo, "Bots", "", bots, 260)
	var level_ref := {}   # o rótulo nasce depois da função anônima (ela copia variáveis)
	var levels := Ui.tabs(BotBrain.LEVEL_NAMES, GameState.bot_level, func(i):
		GameState.set_bot_level(i)
		level_ref["hint"].text = LEVEL_HINTS[i])
	level_ref["hint"] = Ui.option_row(solo, "Dificuldade", LEVEL_HINTS[GameState.bot_level], levels, 260)
	var foot := Ui.vbox(12)
	foot.add_child(_deck_strip())
	start_solo = Ui.accent(Ui.button("Começar treino", _play_bots))
	start_solo.custom_minimum_size.y = 50
	start_solo.add_theme_font_size_override("font_size", 18)
	foot.add_child(start_solo)
	play_footers["Treino"] = foot
	_refresh_solo()
	return solo


## Online: dois blocos lado a lado, criar ou entrar. O baralho se troca na própria sala.
func _online_page() -> Control:
	var col := Ui.vbox(0)
	col.add_child(Ui.label("Online", 24, Ui.TEXT, true))
	col.add_child(Ui.label("Com amigos, até 4 jogadores na sala.", 14, Ui.MUTED))
	col.add_child(Ui.gap(24))
	var row := Ui.hbox(16)
	col.add_child(row)

	var create := _online_block(row, "Criar sala",
		"Você é o anfitrião: escolhe o modo e os mapas e começa quando todos estiverem prontos. Seu IP aparece na sala para passar aos amigos.")
	host_button = Ui.accent(Ui.button("Criar sala", _host))
	host_button.custom_minimum_size.y = 46
	host_button.add_theme_font_size_override("font_size", 17)
	create.add_child(host_button)

	var join := _online_block(row, "Entrar numa sala", "Peça o IP a quem criou a sala: ele aparece na tela da sala.")
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP do anfitrião (ex.: 192.168.0.10)"
	ip_edit.text = _load_ip()
	ip_edit.custom_minimum_size.y = 44
	ip_edit.text_submitted.connect(func(_t): _join())
	join.add_child(ip_edit)
	join.add_child(Ui.gap(10))
	join_button = Ui.button("Entrar", _join)
	join_button.custom_minimum_size.y = 46
	join_button.add_theme_font_size_override("font_size", 17)
	join.add_child(join_button)

	col.add_child(Ui.gap(14))
	play_status = Ui.label("", 15, Ui.WARN)
	play_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(play_status)
	return col


## Bloco da página Online: título, frase e, embaixo (pelo grow), o que quem chama puser.
func _online_block(row: HBoxContainer, title: String, text: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Ui.box(Ui.SURFACE, 12, Ui.LINE)
	style.set_content_margin_all(22)
	box.add_theme_stylebox_override("panel", style)
	row.add_child(box)
	var col := Ui.vbox(0)
	box.add_child(col)
	col.add_child(Ui.label(title, 19, Ui.TEXT, true))
	col.add_child(Ui.gap(6))
	var l := Ui.label(text, 13, Ui.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.y = 56
	col.add_child(l)
	col.add_child(Ui.gap(16))
	col.add_child(Ui.grow())
	return col


## Faixa do baralho acima do botão de começar: ícone da mestra, nome e a troca rápida.
func _deck_strip() -> Control:
	var box := PanelContainer.new()
	var style := Ui.box(Ui.SURFACE, 12, Ui.LINE)
	style.set_content_margin_all(12)
	style.content_margin_left = 14
	box.add_theme_stylebox_override("panel", style)
	var row := Ui.hbox(14)
	box.add_child(row)
	var icon_slot := CenterContainer.new()
	icon_slot.custom_minimum_size = Vector2(44, 44)
	row.add_child(icon_slot)
	var texts := Ui.vbox(4)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	texts.add_child(Ui.label("BARALHO", 12, Ui.MUTED, true))
	var pick := _deck_picker()
	pick.custom_minimum_size = Vector2(0, 38)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(pick)
	var edit := Ui.flat(Ui.button("Editar baralhos", _open_decks))
	edit.size_flags_vertical = Control.SIZE_SHRINK_END
	edit.custom_minimum_size.y = 38
	row.add_child(edit)
	var show_master := func():
		for c in icon_slot.get_children():
			c.queue_free()
		icon_slot.add_child(CardIcon.make(GameState.player_master, 44))
	show_master.call()
	pick.item_selected.connect(func(_k): show_master.call())
	return box


## Sala: até 4 vagas (ou dois times de 2) e o chat embaixo; à direita o seu nome, o seu
## baralho, o formato, o IP (para o anfitrião) e o botão Começar.
func _lobby_page() -> Control:
	var root := Ui.vbox(24)
	var header := Ui.hbox(16)
	root.add_child(header)
	header.add_child(Ui.flat(Ui.button("‹  Sair da sala", _leave_lobby)))
	lobby_title = Ui.label("Sala", 32, Ui.TEXT, true)
	header.add_child(lobby_title)
	var body := Ui.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := Ui.panel(body)
	lobby_slots = Ui.vbox(8)
	left.add_child(lobby_slots)
	shuffle_button = Ui.button("Sortear times", func(): Net.shuffle_teams())
	shuffle_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(shuffle_button)
	Ui.section(left, "CHAT", null, 14)
	left.add_child(Ui.gap(4))
	var chat := ChatBox.new(false)
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(chat)
	var right := Ui.panel(body)
	Ui.section(right, "VOCÊ", null, 0)
	var nick := _nick_edit()
	nick.placeholder_text = "Como os outros vão te ver"
	nick.custom_minimum_size.y = 38
	nick_timer = Timer.new()
	nick_timer.one_shot = true
	nick_timer.wait_time = 0.5
	nick_timer.timeout.connect(func(): Net.change_nick(nick.text))
	right.add_child(nick_timer)
	nick.text_changed.connect(func(_t): nick_timer.start())
	nick.text_submitted.connect(func(t):
		nick_timer.stop()
		Net.change_nick(t)
		nick.release_focus())
	Ui.option_row(right, "Nome", "Como os outros te veem.", nick, LOBBY_CONTROL, 8)
	var look_line := Ui.hbox(10)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(30, 38)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	look_line.add_child(Ui.spacer())
	look_line.add_child(thumb)
	var custom := Ui.button("Personalizar", _open_custom, 140)
	custom.custom_minimum_size.y = 38
	look_line.add_child(custom)
	var look_text := Ui.option_row(right, "Visual", "", look_line, LOBBY_CONTROL, 8)
	look_text.visible = true
	lobby_look = [thumb, look_text]
	_refresh_lobby_look()
	var deck_line := Ui.hbox(8)
	var pick := _deck_picker()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size = Vector2(0, 38)
	deck_line.add_child(pick)
	var edit := Ui.button("Editar", _open_decks_from_lobby, 80)
	edit.custom_minimum_size.y = 38
	deck_line.add_child(edit)
	Ui.option_row(right, "Baralho", "O equipado vai para a partida.", deck_line, LOBBY_CONTROL, 8)

	Ui.section(right, "PARTIDA", null, 20)
	right.add_child(Ui.gap(6))
	lobby_modes = ModePicker.new("ffa", GameModes.DEFAULT_LIVES)
	lobby_modes.changed.connect(func(m, n): Net.set_mode(m, n))
	right.add_child(lobby_modes)
	maps_button = Ui.button("Escolher", func(): map_picker.open(), 140)
	maps_button.custom_minimum_size.y = 38
	maps_hint = Ui.option_row(right, "Mapas", "", maps_button, 140, 8)
	maps_hint.visible = true
	right.add_child(Ui.grow())
	# IP do anfitrião (ou a espera do convidado) numa faixa discreta acima do botão.
	var info_box := PanelContainer.new()
	var info_style := Ui.box(Ui.BG, 8, Ui.LINE)
	info_style.set_content_margin_all(12)
	info_box.add_theme_stylebox_override("panel", info_style)
	right.add_child(info_box)
	lobby_info = Ui.label("", 14, Ui.TEXT)
	lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(lobby_info)
	right.add_child(Ui.gap(4))
	start_button = Ui.accent(Ui.button("Começar", _on_start_pressed))
	start_button.custom_minimum_size.y = 52
	start_button.add_theme_font_size_override("font_size", 20)
	right.add_child(start_button)
	return root


## Personalizar: o personagem em 3D no centro (arrastar gira) e, à direita, as abas de
## cada parte com as opções. Escolher vale na hora, fica salvo e, na sala, os outros veem.
func _custom_page() -> Control:
	var root := Ui.vbox(24)
	var header := Ui.hbox(16)
	header.add_child(Ui.flat(Ui.button("< Voltar", _close_custom)))
	var titles := Ui.vbox(2)
	titles.add_child(Ui.label("Personalizar", 32, Ui.TEXT, true))
	titles.add_child(Ui.label("Só aparência: não muda nada no jogo.", 15, Ui.MUTED))
	header.add_child(titles)
	root.add_child(header)
	var body := Ui.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var stage := Ui.vbox(4)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 1.2
	body.add_child(stage)
	preview = LookPreview.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(preview)
	look_name = Ui.label("", 22, Ui.TEXT, true)
	look_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(look_name)
	var hint := Ui.label("Arraste para girar", 13, Ui.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(hint)

	var side := Ui.panel(body)
	side.get_parent().custom_minimum_size.x = 470
	side.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(Ui.segmented(["Personagem", "Arma"], custom_tab, func(i):
		custom_tab = i
		_refresh_custom()))
	side.add_child(Ui.gap(4))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	look_grid = GridContainer.new()
	look_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look_grid.add_theme_constant_override("h_separation", 10)
	look_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(look_grid)
	return root


func _open_custom() -> void:
	custom_back = page
	_show(Page.CUSTOM)
	_refresh_custom()


func _close_custom() -> void:
	_show(custom_back)
	if custom_back == Page.LOBBY:
		_refresh_lobby()
	_refresh_lobby_look()


## Cartões da aba aberta (personagens em 4 colunas, armas em 2) e o modelo no centro.
func _refresh_custom() -> void:
	preview.show_look(GameState.skin, GameState.gun_skin)
	look_name.text = "%s  ·  %s" % [Player.skin_name(GameState.skin), Player.gun_name(GameState.gun_skin)]
	for c in look_grid.get_children():
		c.queue_free()
	var guns := custom_tab == 1
	look_grid.columns = 2 if guns else 4
	for s in (Player.GUN_SKINS if guns else Player.SKINS):
		var id: String = s[0]
		var chosen := id == (GameState.gun_skin if guns else GameState.skin)
		var tex := Player.gun_thumb(id) if guns else Player.skin_thumb(id)
		look_grid.add_child(_look_card(tex, s[1], chosen, Vector2(188, 116) if guns else Vector2(84, 116),
			func(): _pick_look(id, guns)))


func _pick_look(id: String, gun: bool) -> void:
	if gun:
		Net.change_look(GameState.skin, id)
	else:
		Net.change_look(id, GameState.gun_skin)
	_refresh_custom()


## Cartão de uma opção: miniatura e nome; a escolhida tem borda na cor de destaque.
func _look_card(tex: Texture2D, title: String, chosen: bool, art: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", Ui.box(Ui.SURFACE_HI if chosen else Ui.BG, 10,
		Ui.ACCENT if chosen else Ui.LINE, 2 if chosen else 1))
	b.add_theme_stylebox_override("hover", Ui.box(Ui.SURFACE_HI, 10, Ui.ACCENT if chosen else Ui.LINE.lightened(0.3), 2 if chosen else 1))
	b.add_theme_stylebox_override("pressed", Ui.box(Ui.SURFACE_HI, 10, Ui.ACCENT, 2))
	b.pressed.connect(action)
	var col := Ui.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_right = -6
	col.offset_top = 6
	col.offset_bottom = -6
	b.add_child(col)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var name_label := Ui.label(title, 13, Ui.TEXT if chosen else Ui.MUTED, chosen)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	b.custom_minimum_size = art + Vector2(12, 34)
	return b


func _refresh_lobby_look() -> void:
	if lobby_look.is_empty():
		return
	lobby_look[0].texture = Player.skin_thumb(GameState.skin)
	lobby_look[1].text = "%s  ·  %s" % [Player.skin_name(GameState.skin), Player.gun_name(GameState.gun_skin)]


func _settings_page() -> Control:
	var root := Ui.vbox(24)
	root.add_child(_header("Configurações", "Salvas sozinhas."))
	settings = SettingsPanel.new(_nick_edit())
	settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(settings)
	return root


# ---------------------------------------------------------------- peças

func _header(title: String, subtitle: String) -> Control:
	var header := Ui.hbox(16)
	header.add_child(Ui.flat(Ui.button("< Voltar", func(): _show(Page.HOME))))
	var titles := Ui.vbox(2)
	titles.add_child(Ui.label(title, 32, Ui.TEXT, true))
	titles.add_child(Ui.label(subtitle, 15, Ui.MUTED))
	header.add_child(titles)
	return header


func _menu_button(text: String, action: Callable) -> Button:
	var b := Ui.button(text, action)
	b.custom_minimum_size.y = 48
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	return b


## Cartão do baralho equipado no canto da tela inicial; clicar abre os baralhos.
func _deck_card() -> Control:
	var cards: Array = GameState.decks[GameState.equipped]["cards"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(320, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(_open_decks)
	var col := Ui.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16
	col.offset_top = 14
	col.offset_right = -16
	col.offset_bottom = -14
	b.add_child(col)
	var top := Ui.label("BARALHO EQUIPADO", 12, Ui.MUTED, true)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name_label := Ui.label(GameState.equipped_name(), 20, Ui.TEXT, true)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	col.add_child(Ui.master_label(GameState.player_master))
	col.add_child(Ui.category_bar(cards))
	b.custom_minimum_size.y = 118
	return b


## Lista dos baralhos (incompletos aparecem, mas não dá para escolher). Trocar em um
## lugar troca nos outros.
func _deck_picker() -> OptionButton:
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(320, 42)
	pick.clip_text = true
	for i in GameState.decks.size():
		var d: Dictionary = GameState.decks[i]
		pick.add_item("%s  (%d, %s)" % [d["name"], d["cards"].size(), CardDB.card_name(d["master"])], i)
		pick.set_item_disabled(pick.item_count - 1, not CardDB.is_valid_deck(d["cards"]))
	pick.select(GameState.equipped)
	pick.item_selected.connect(func(k):
		GameState.equip(pick.get_item_id(k))
		for other in deck_picks:
			if other != pick:
				other.select(GameState.equipped))
	deck_picks.append(pick)
	return pick


func _nick_edit() -> LineEdit:
	var edit := LineEdit.new()
	edit.text = GameState.nick
	edit.max_length = GameState.NICK_MAX
	edit.placeholder_text = "Digite seu nome"
	edit.custom_minimum_size.y = 44
	edit.text_changed.connect(func(t: String):
		GameState.set_nick(t)
		for other in nick_edits:
			if other != edit:
				other.text = t)
	nick_edits.append(edit)
	return edit


# ---------------------------------------------------------------- ações

func _open_decks() -> void:
	get_tree().change_scene_to_file("res://scenes/decks.tscn")


## Da sala: a conexão continua aberta e a tela de Baralhos volta para cá.
func _open_decks_from_lobby() -> void:
	# Quem vai mexer no baralho deixa de estar pronto (marca de novo ao voltar).
	Net.set_ready(false)
	GameState.from_lobby = true
	_open_decks()


func _set_bots(n: int) -> void:
	bot_count = n
	solo_bots.set_value_no_signal(n)


## Treino: o modo precisa caber no número de bots (2x2 = 3 bots); senão, avisa e trava.
func _refresh_solo() -> void:
	var reason := GameModes.blocked_reason(GameState.mode, bot_count + 1)
	if GameState.mode == "teams":
		reason = "" if bot_count == 3 else "2x2 no treino é com 3 bots: você e um aliado contra dois."
		solo_modes.set_note("Você e um bot aliado contra dois bots." if reason == "" else reason, reason != "")
	elif GameState.mode == "duels":
		solo_modes.set_note("Você e os bots duelam um de cada vez; quem espera assiste.")
	else:
		solo_modes.set_note("")
	start_solo.disabled = reason != ""
	bots_hint.visible = true
	solo_bots_label.text = "%d bot%s" % [bot_count, "" if bot_count == 1 else "s"]
	bots_hint.text = ["Só mapas pequenos.", "Mapas pequenos e médios.", "Mapas de todos os tamanhos."][bot_count - 1]


func _play_bots() -> void:
	GameState.bot_count = bot_count
	get_tree().change_scene_to_file("res://scenes/match.tscn")


func _host() -> void:
	var err := Net.host()
	if err != OK:
		_play_error("Não deu para abrir a porta %d (erro %d). Outro programa já está usando?" % [Net.PORT, err])
		return
	# A sala abre no último modo usado no treino (o anfitrião troca na sala).
	Net.set_mode(GameState.mode, GameState.lives)
	_show(Page.LOBBY)
	_refresh_lobby()


func _join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		_play_error("Digite o IP de quem criou a sala.")
		return
	_save_ip(ip)
	var err := Net.join(ip)
	if err != OK:
		_play_error("Não deu para conectar (erro %d)." % err)
		return
	_play_error("")
	join_button.disabled = true
	host_button.disabled = true
	join_button.text = "Conectando..."


func _on_joined() -> void:
	_reset_join()
	_show(Page.LOBBY)
	_refresh_lobby()


## Vagas da sala e o que cada um vê: o anfitrião, o IP, o formato e o botão; o
## convidado, a espera. No 2x2 as vagas viram dois times, e o anfitrião troca as pessoas
## de time.
func _refresh_lobby() -> void:
	if page != Page.LOBBY or not Net.online:
		return
	var host := Net.is_host()
	var count := Net.lobby_count
	for c in lobby_slots.get_children():
		c.queue_free()
	if Net.team_mode:
		for t in 2:
			_team_column(t, host)
	else:
		lobby_slots.add_child(Ui.label("JOGADORES", 12, Ui.MUTED, true))
		var ids := Net.lobby_ids()
		for i in Net.MAX_GUESTS + 1:
			if i < count and i < ids.size():
				lobby_slots.add_child(_slot(ids[i], false))
			else:
				lobby_slots.add_child(_empty_slot())
	shuffle_button.visible = host and Net.team_mode
	lobby_modes.set_state(Net.mode, Net.lives, host)
	maps_button.text = "Escolher" if host else "Ver"
	maps_hint.text = MapPicker.summary().trim_prefix("Mapas  ·  ") + " ligados. A cada rodada sai um deles."
	var reason := GameModes.blocked_reason(Net.mode, count)
	if not host:
		lobby_modes.set_note("Só o anfitrião escolhe o modo.")
	elif reason != "":
		lobby_modes.set_note("%s: %s." % [GameModes.mode_name(Net.mode), reason.to_lower()], true)
	elif Net.team_mode and not Net.teams_ready():
		lobby_modes.set_note("Os times precisam de 2 cada (troque ou sorteie ao lado).", true)
	else:
		lobby_modes.set_note("")

	var mode := GameModes.label(Net.mode, Net.lives)
	lobby_title.text = "Sala  ·  %d de %d" % [count, Net.MAX_GUESTS + 1]
	if host:
		var ips := Net.local_ips()
		lobby_info.text = "Seu IP: %s  ·  porta %d\nOs amigos abrem Jogar > Online e digitam esse IP." % [
			", ".join(ips) if not ips.is_empty() else "não encontrado", Net.PORT]
		start_button.visible = true
		var blocked := reason != "" or (Net.team_mode and not Net.teams_ready())
		var ready_n := Net.ready_count()
		start_button.disabled = blocked or ready_n < count - 1
		if count < 2:
			start_button.text = "Esperando jogadores..."
		elif Net.team_mode and count < 4:
			start_button.text = "Esperando 4 jogadores (%d/4)" % count
		elif blocked:
			start_button.text = "Ajuste o modo para começar"
		elif ready_n < count - 1:
			start_button.text = "Esperando todos ficarem prontos (%d/%d)" % [ready_n, count - 1]
		else:
			start_button.text = "Começar  ·  %s" % mode
		if _autotest_players() > 0 and count >= _autotest_players() and ready_n >= count - 1:
			Net.start_match()
	else:
		# Convidado: o botão grande marca e desmarca "Pronto".
		var me_ready := Net.is_ready(Net.my_id())
		if me_ready:
			lobby_info.text = "Você está pronto. O anfitrião começa quando todos estiverem (%s)." % mode
		else:
			lobby_info.text = "Conectado. Clique em Pronto quando puder começar (%s)." % mode
		start_button.visible = true
		start_button.disabled = false
		start_button.text = "Cancelar pronto" if me_ready else "Pronto"
		if "--autotest" in OS.get_cmdline_user_args() and not me_ready:
			Net.set_ready(true)


## Um time no 2x2: faixa da cor, nome, e as vagas (2; mais se o time estiver desequilibrado).
func _team_column(team: int, host: bool) -> void:
	var color: Color = GameState.TEAM_COLORS[team][0]
	if team == 1:
		lobby_slots.add_child(Ui.gap(8))
	var head := Ui.hbox(10)
	var strip := ColorRect.new()
	strip.color = color
	strip.custom_minimum_size = Vector2(18, 4)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(strip)
	head.add_child(Ui.label("TIME %s" % String(GameState.TEAM_NAMES[team]).to_upper(), 14, color.lightened(0.35), true))
	lobby_slots.add_child(head)
	var members := Net.lobby_ids().filter(func(id): return Net.teams.get(id, 0) == team)
	for id in members:
		lobby_slots.add_child(_slot(id, host))
	for i in maxi(0, 2 - members.size()):
		lobby_slots.add_child(_empty_slot())


## Vaga ocupada: faixa e nome na cor do jogador (a mesma do chat e da partida), marcas
## (anfitrião, você) e, para o anfitrião no 2x2, o botão de trocar de time.
func _slot(id: int, can_switch: bool) -> Control:
	var color := Net.color_of(id)
	var box := PanelContainer.new()
	var style := Ui.box(Ui.SURFACE_HI, 8, Ui.LINE)
	style.border_color = color
	style.border_width_left = 4
	style.set_content_margin_all(10)
	style.content_margin_left = 14
	box.add_theme_stylebox_override("panel", style)
	var line := Ui.hbox(10)
	box.add_child(line)
	var name_label := Ui.label(Net.display_name(id), 18, color.lightened(0.3), true)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name_label)
	if id == 1:
		line.add_child(_tag("anfitrião"))
	if id == Net.my_id():
		line.add_child(_tag("você"))
	line.add_child(Ui.spacer())
	if id != 1:
		var state := _tag("pronto" if Net.is_ready(id) else "não está pronto")
		state.add_theme_color_override("font_color", Ui.OK if Net.is_ready(id) else Ui.MUTED)
		line.add_child(state)
	if can_switch:
		var other: int = 1 - int(Net.teams.get(id, 0))
		var b := Ui.flat(Ui.button("Mudar para %s" % GameState.TEAM_NAMES[other], func(): Net.switch_team(id)))
		b.custom_minimum_size.y = 32
		line.add_child(b)
	else:
		line.add_child(Control.new())
	box.custom_minimum_size.y = 52
	return box


func _empty_slot() -> Control:
	var box := PanelContainer.new()
	var style := Ui.box(Ui.BG, 8, Ui.LINE)
	style.set_content_margin_all(14)
	box.add_theme_stylebox_override("panel", style)
	box.add_child(Ui.label("Vaga livre", 18, Ui.MUTED))
	box.custom_minimum_size.y = 52
	return box


func _tag(text: String) -> Label:
	var l := Ui.label(text, 13, Ui.MUTED)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Teste automático hospedando: quantos jogadores esperar (0 se não for o caso).
func _autotest_players() -> int:
	var args := OS.get_cmdline_user_args()
	for n in [3, 4]:
		if "--host%d" % n in args:
			return n
	return 2 if "--host" in args else 0


## Botão grande da sala: o anfitrião começa; o convidado marca ou desmarca "Pronto".
func _on_start_pressed() -> void:
	if Net.is_host():
		Net.start_match()
	else:
		Net.set_ready(not Net.is_ready(Net.my_id()))


func _leave_lobby() -> void:
	Net.stop()
	_show(Page.PLAY)


func _on_match_starting() -> void:
	GameState.go_to_match()


func _on_failed(reason: String) -> void:
	_reset_join()
	_show(Page.PLAY)
	_play_error(reason)


func _on_lost() -> void:
	Net.stop()
	_reset_join()
	_show(Page.PLAY)
	_play_error("A conexão com a sala caiu.")


func _reset_join() -> void:
	join_button.disabled = false
	host_button.disabled = false
	join_button.text = "Entrar"


func _play_error(text: String) -> void:
	play_status.text = text
	if text != "":
		_open_play_tab("Online")


func _load_ip() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return cfg.get_value("rede", "ultimo_ip", "")
	return ""


func _save_ip(ip: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("rede", "ultimo_ip", ip)
	cfg.save(SETTINGS_PATH)
