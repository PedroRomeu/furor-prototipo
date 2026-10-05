class_name SettingsPanel
extends HBoxContainer
## Configurações por categoria (2026-10-05, pedido do usuário; antes era tudo numa tela):
## lista à esquerda e, à direita, só a categoria aberta, como na maioria dos jogos.
## Perfil (nome, só no menu principal), Vídeo, Áudio, Controles (mouse e teclas) e
## Créditos. Usado no menu principal e no menu de pausa da partida; a última categoria
## aberta volta aberta. Tudo é salvo na hora pelo GameState.

const QUALITY_NAMES := ["Baixa", "Média", "Alta"]
const QUALITY_HINTS := [
	"Sem sombras, brilho nem névoa. Para PCs modestos.",
	"Sombras simples, sem brilho nem névoa.",
	"Sombras detalhadas, brilho, névoa e antisserrilhado. Pesada em placa de vídeo integrada.",
]

const MODE_HINTS := [
	"Janela comum, que dá para mover e redimensionar.",
	"Ocupa a tela toda sem borda; trocar de programa (Alt+Tab) é instantâneo.",
	"Tela cheia exclusiva: pode render um pouco mais, mas o Alt+Tab demora.",
]

static var _last_tab := ""

var bind_buttons := {}   # [ação, vaga] -> Button
var bind_hint: Label
var rebind_action := ""   # esperando tecla para esta ação ("" = não)
var rebind_slot := 0
var _tabs := {}           # nome -> [botão da lista, página]


## nick_field: campo do nome (o menu principal manda o seu); null tira a categoria Perfil.
func _init(nick_field: Control = null) -> void:
	add_theme_constant_override("separation", 20)
	var nav := Ui.vbox(6)
	nav.custom_minimum_size.x = 220
	add_child(nav)
	var holder := Ui.panel(self)
	var group := ButtonGroup.new()
	var pages: Array = []
	if nick_field:
		pages.append(["Perfil", _profile_page(nick_field)])
	pages.append_array([["Vídeo", _video_page()], ["Áudio", _audio_page()],
		["Controles", _controls_page()], ["Créditos", _credits_page()]])
	for entry in pages:
		var title: String = entry[0]
		var b := Button.new()
		b.text = title
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 46
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_open.bind(title))
		nav.add_child(b)
		var page: Control = entry[1]
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = false
		holder.add_child(page)
		_tabs[title] = [b, page]
	_open(_last_tab if _tabs.has(_last_tab) else String(pages[0][0]))


func _open(title: String) -> void:
	stop_rebind()
	_last_tab = title
	for t in _tabs:
		_tabs[t][0].set_pressed_no_signal(t == title)
		_tabs[t][1].visible = t == title


## Página com título e uma frase curta embaixo.
func _page(title: String, subtitle: String) -> VBoxContainer:
	var col := Ui.vbox(10)
	col.add_child(Ui.label(title, 22, Ui.TEXT, true))
	if subtitle != "":
		var sub := Ui.label(subtitle, 14, Ui.MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(sub)
	col.add_child(Ui.gap(8))
	return col


func _profile_page(nick_field: Control) -> Control:
	var col := _page("Perfil", "Como os outros jogadores te veem online. Também dá para mudar dentro da sala.")
	col.add_child(Ui.label("Seu nome", 14, Ui.MUTED))
	col.add_child(nick_field)
	return col


func _video_page() -> Control:
	var col := _page("Vídeo", "")
	col.add_child(Ui.label("Modo de exibição", 14, Ui.MUTED))
	var mode_hint := Ui.label(MODE_HINTS[GameState.window_mode], 14, Ui.MUTED)
	mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(Ui.segmented(GameState.WINDOW_MODES, GameState.window_mode, func(i):
		GameState.set_window_mode(i)
		mode_hint.text = MODE_HINTS[i]))
	col.add_child(mode_hint)
	col.add_child(Ui.gap(12))
	col.add_child(Ui.label("Resolução", 14, Ui.MUTED))
	# Lista suspensa: mostra a atual e abre as que cabem no monitor.
	var res_pick := OptionButton.new()
	res_pick.custom_minimum_size = Vector2(260, 42)
	res_pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var options := GameState.available_resolutions()
	for r in options:
		res_pick.add_item("%d x %d" % [r.x, r.y])
	res_pick.select(options.find(GameState.resolution))
	res_pick.item_selected.connect(func(i): GameState.set_resolution(options[i]))
	col.add_child(res_pick)
	var res_hint := Ui.label("Mais alta fica mais nítida e mais pesada. Em PC modesto, 1280 x 720.", 14, Ui.MUTED)
	res_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(res_hint)
	col.add_child(Ui.gap(12))
	col.add_child(Ui.label("Qualidade gráfica", 14, Ui.MUTED))
	var hint := Ui.label(QUALITY_HINTS[GameState.quality], 14, Ui.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(Ui.segmented(QUALITY_NAMES, GameState.quality, func(i):
		GameState.set_quality(i)
		hint.text = QUALITY_HINTS[i]))
	col.add_child(hint)
	col.add_child(Ui.gap(12))
	var fps := CheckButton.new()
	fps.text = "Mostrar FPS na partida"
	fps.button_pressed = GameState.show_fps
	fps.toggled.connect(GameState.set_show_fps)
	col.add_child(fps)
	return col


func _audio_page() -> Control:
	var col := _page("Áudio", "Solte a barra para ouvir um exemplo.")
	col.add_theme_constant_override("separation", 16)
	for b in GameState.AUDIO_BUSES:
		col.add_child(_volume_row(b[0], b[1]))
	return col


func _credits_page() -> Control:
	var col := _page("Créditos", "")
	var text := Ui.label("Modelos e sons de Kenney (kenney.nl), CC0.\n\nÍcones das cartas de game-icons.net, "
		+ "por Lorc, Delapouite, Caro Asercion, Felbrigg, HeavenlyDog, John Colburn, Sbed e Skoll (CC BY 3.0).", 15, Ui.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	return col


func _sens_row() -> Control:
	var row := Ui.hbox(8)
	var slider := HSlider.new()
	slider.min_value = 0.25
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = GameState.mouse_sens / GameState.DEFAULT_SENS
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := Ui.label("%.2fx" % slider.value, 16, Ui.TEXT)
	value.custom_minimum_size.x = 56
	row.add_child(value)
	slider.value_changed.connect(func(v):
		value.text = "%.2fx" % v
		GameState.set_mouse_sens(v * GameState.DEFAULT_SENS))
	return row


## Barra de volume de um canal: nome, barra e a porcentagem ("Mudo" no zero). Ao soltar a
## barra toca um som de exemplo naquele canal (Geral usa um tiro).
const VOLUME_SAMPLE := {"Master": "shot", "Efeitos": "explosion", "Interface": "hitmarker"}


func _volume_row(bus: String, title: String) -> Control:
	var row := Ui.hbox(10)
	var name_label := Ui.label(title, 16, Ui.TEXT)
	name_label.custom_minimum_size.x = 92
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = GameState.volumes[bus]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := Ui.label("", 16, Ui.TEXT)
	value.custom_minimum_size.x = 56
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var show := func(v: float):
		value.text = "Mudo" if v <= 0.0 else "%d%%" % int(v)
		value.add_theme_color_override("font_color", Ui.MUTED if v <= 0.0 else Ui.TEXT)
	show.call(slider.value)
	slider.value_changed.connect(func(v):
		show.call(v)
		GameState.set_volume(bus, int(v)))
	slider.drag_ended.connect(func(_changed):
		if VOLUME_SAMPLE.has(bus):
			Sfx.preview(self, VOLUME_SAMPLE[bus], "Master" if bus == "Master" else bus))
	if bus == "Musica":
		slider.tooltip_text = "Ainda não há música no jogo; o ajuste fica salvo para quando houver."
	return row


## Controles: uma linha por ação, com duas vagas de tecla. Clicar numa vaga e apertar a
## tecla (ou botão do mouse) nova; Esc cancela; botão direito na vaga a esvazia.
func _controls_page() -> Control:
	var col := _page("Controles", "")
	col.add_child(Ui.label("Sensibilidade do mouse", 14, Ui.MUTED))
	col.add_child(_sens_row())
	col.add_child(Ui.gap(8))
	var top := Ui.hbox(8)
	col.add_child(top)
	top.add_child(Ui.label("Teclas", 14, Ui.MUTED))
	top.add_child(Ui.spacer())
	top.add_child(Ui.flat(Ui.button("Restaurar padrão", func():
		stop_rebind()
		GameState.reset_binds()
		_refresh_binds())))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := Ui.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for a in GameState.ACTIONS:
		var line := Ui.hbox(8)
		list.add_child(line)
		var name_label := Ui.label(a[1], 16, Ui.TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		for slot in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(150, 36)
			b.pressed.connect(_start_rebind.bind(a[0], slot))
			b.gui_input.connect(func(event: InputEvent):
				var mb := event as InputEventMouseButton
				if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and rebind_action == "":
					GameState.set_bind(a[0], slot, "")
					_refresh_binds())
			line.add_child(b)
			bind_buttons[[a[0], slot]] = b
	bind_hint = Ui.label("", 14, Ui.MUTED)
	bind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(bind_hint)
	_refresh_binds()
	return col


func _start_rebind(action: String, slot: int) -> void:
	rebind_action = action
	rebind_slot = slot
	_refresh_binds()


func stop_rebind() -> void:
	rebind_action = ""
	_refresh_binds()


func _refresh_binds() -> void:
	var warnings := []
	for key in bind_buttons:
		var action: String = key[0]
		var code: String = GameState.binds[action][key[1]]
		var b: Button = bind_buttons[key]
		var clash := GameState.conflicts(action, code)
		if action == rebind_action and key[1] == rebind_slot:
			b.text = "Aperte uma tecla..."
			b.add_theme_color_override("font_color", Ui.ACCENT)
		else:
			b.text = GameState.code_text(code) if code != "" else "-"
			b.add_theme_color_override("font_color", Ui.WARN if not clash.is_empty() else (Ui.TEXT if code != "" else Ui.MUTED))
		if not clash.is_empty() and action < clash[0]:
			warnings.append("%s está em %s e em %s." % [GameState.code_text(code), GameState.action_label(action),
				", ".join(clash.map(GameState.action_label))])
	if rebind_action != "":
		bind_hint.text = "Aperte a tecla ou botão do mouse para %s. Esc cancela." % GameState.action_label(rebind_action)
		bind_hint.add_theme_color_override("font_color", Ui.ACCENT)
	elif not warnings.is_empty():
		bind_hint.text = "Tecla repetida: " + " ".join(warnings)
		bind_hint.add_theme_color_override("font_color", Ui.WARN)
	else:
		bind_hint.text = "Clique numa tecla para trocar. Botão direito apaga. Mouse mira; Esc pausa (fixos)."
		bind_hint.add_theme_color_override("font_color", Ui.MUTED)


## Esperando a tecla nova: pega o próximo aperto antes de qualquer botão da tela.
func _input(event: InputEvent) -> void:
	if rebind_action == "" or not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		stop_rebind()
		return
	var code := GameState.code_of(event)
	if code != "":
		GameState.set_bind(rebind_action, rebind_slot, code)
	stop_rebind()
