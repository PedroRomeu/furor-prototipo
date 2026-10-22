class_name SettingsPanel
extends HBoxContainer
## Configurações por categoria: lista à esquerda e, à direita, só a categoria aberta.
## Refeitas em 2026-10-06 (pedido do usuário, na linha do editor de baralhos novo: menos
## coisa de uma vez, minimalista e profissional): cada opção é uma linha com o nome e uma
## frase curta à esquerda e o controle à direita, agrupadas em seções, como nas telas de
## configuração de Valorant e Apex. Perfil (nome, só no menu principal), Vídeo, Áudio,
## Controles e Créditos. Usado no menu principal e no de pausa; a última categoria aberta
## volta aberta. Tudo é salvo na hora pelo GameState.

const QUALITY_NAMES := ["Low", "Medium", "High"]   # i18n
const QUALITY_HINTS := [
	"No shadows, glow or fog. For modest PCs.",   # i18n
	"Simple shadows, no glow or fog.",   # i18n
	"Detailed shadows, glow and fog. Heavy on integrated graphics.",   # i18n
]
const MODE_HINTS := [
	"Can be moved, resized and maximized.",   # i18n
	"Whole screen, no border. Instant Alt+Tab.",   # i18n
	"Exclusive fullscreen. Alt+Tab is slow.",   # i18n
]
const CONTROL_WIDTH := 330.0   # coluna dos controles, à direita de cada linha
const CONTENT_MAX := 940.0     # largura máxima do painel (em tela larga não espalha)

static var _last_tab := ""

var bind_buttons := {}   # [ação, vaga] -> Button
var bind_hint: Label
var rebind_action := ""   # esperando tecla para esta ação ("" = não)
var rebind_slot := 0
var _tabs := {}           # nome -> [botão da lista, página]
var in_main_menu := false  # no menu principal dá para reiniciar o jogo (API gráfica)


## nick_field: campo do nome (o menu principal manda o seu); null tira a categoria Perfil.
func _init(nick_field: Control = null) -> void:
	in_main_menu = nick_field != null
	add_theme_constant_override("separation", 28)
	var nav := Ui.vbox(2)
	nav.custom_minimum_size.x = 190
	add_child(nav)
	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Ui.box(Ui.SURFACE.darkened(0.15), 14, Ui.LINE)
	style.set_content_margin_all(0)
	holder.add_theme_stylebox_override("panel", style)
	add_child(holder)
	# Em tela larga o painel para em CONTENT_MAX (o resto fica livre), senão espalharia.
	resized.connect(func():
		var room := size.x - nav.custom_minimum_size.x - get_theme_constant("separation")
		holder.custom_minimum_size.x = minf(room, CONTENT_MAX)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL if room <= CONTENT_MAX else Control.SIZE_SHRINK_BEGIN)
	var group := ButtonGroup.new()
	var pages: Array = []   # [id, título, página]
	if nick_field:
		pages.append(["profile", tr("Profile"), _profile_page(nick_field)])
	pages.append_array([["video", tr("Video"), _video_page()], ["audio", tr("Audio"), _audio_page()],
		["controls", tr("Controls"), _controls_page()], ["credits", tr("Credits"), _credits_page()]])
	for entry in pages:
		var id: String = entry[0]
		var b := Ui.nav_button(entry[1], group)
		b.pressed.connect(_open.bind(id))
		nav.add_child(b)
		var page := _scrolled(entry[2])
		page.visible = false
		holder.add_child(page)
		_tabs[id] = [b, page]
	_open(_last_tab if _tabs.has(_last_tab) else String(pages[0][0]))


func _open(id: String) -> void:
	stop_rebind()
	_last_tab = id
	for t in _tabs:
		_tabs[t][0].set_pressed_no_signal(t == id)
		_tabs[t][1].visible = t == id


## Página rolável, com margem.
func _scrolled(page: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32 if side != "top" else 28)
	scroll.add_child(margin)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(page)
	return scroll


func _page(title: String) -> VBoxContainer:
	var col := Ui.vbox(0)
	col.add_child(Ui.label(title, 24, Ui.TEXT, true))
	return col


## Título de seção e linha de opção: os mesmos do resto do jogo (Ui.section, Ui.option_row).
func _section(col: VBoxContainer, title: String, extra: Control = null) -> void:
	Ui.section(col, title, extra)


func _row(col: VBoxContainer, title: String, hint: String, control: Control) -> Label:
	return Ui.option_row(col, title, hint, control, CONTROL_WIDTH)


func _dropdown(items: Array, selected: int) -> OptionButton:
	var pick := OptionButton.new()
	pick.custom_minimum_size.y = 38
	pick.add_theme_font_size_override("font_size", 14)
	for item in items:
		pick.add_item(item)
	pick.select(selected)
	return pick


func _switch(on: bool, action: Callable) -> Control:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	var sw := CheckButton.new()
	sw.button_pressed = on
	sw.toggled.connect(action)
	box.add_child(sw)
	return box


# ---------------------------------------------------------------- páginas

func _profile_page(nick_field: Control) -> Control:
	var col := _page(tr("Profile"))
	_section(col, tr("PLAYER"))
	nick_field.custom_minimum_size.y = 38
	_row(col, tr("Name"), tr("How others see you online. You can also change it in the lobby."), nick_field)
	# Idioma (2026-10-22): só no menu principal, que se refaz inteiro ao trocar.
	var pick := _dropdown(Lang.names(), Lang.codes().find(Lang.current))
	pick.item_selected.connect(func(i): Lang.set_language(Lang.codes()[i]))
	_row(col, tr("Language"), tr("Menus, cards and match texts."), pick)
	return col


func _video_page() -> Control:
	var col := _page(tr("Video"))
	# As funções anônimas copiam as variáveis ao nascer: os rótulos criados depois vão num
	# dicionário, que é compartilhado.
	var refs := {}
	_section(col, tr("DISPLAY"))
	refs["mode_hint"] = _row(col, tr("Display mode"), tr(MODE_HINTS[GameState.window_mode]),
		Ui.tabs(GameState.WINDOW_MODES.map(tr), GameState.window_mode, func(i):
			GameState.set_window_mode(i)
			_refresh_video(i, refs)))
	refs["res_pick"] = _dropdown([], -1)
	refs["res_pick"].item_selected.connect(func(i):
		var options: Array = refs["res_options"]
		if GameState.window_mode == 0:
			GameState.set_resolution(options[i])
		else:
			GameState.set_fullscreen_res(options[i])
		_refresh_video(GameState.window_mode, refs))
	refs["res_hint"] = _row(col, tr("Resolution"), "", refs["res_pick"])
	_refresh_video(GameState.window_mode, refs)
	_row(col, tr("Interface size"), tr("Menus and HUD. Increase it on large screens."),
		Ui.tabs(GameState.UI_SCALES.map(func(f): return "%d%%" % roundi(f * 100.0)), GameState.ui_scale,
			GameState.set_ui_scale))

	_section(col, tr("GRAPHICS"))
	refs["quality_hint"] = _row(col, tr("Quality"), tr(QUALITY_HINTS[GameState.quality]),
		Ui.tabs(QUALITY_NAMES.map(tr), GameState.quality, func(i):
			GameState.set_quality(i)
			refs["quality_hint"].text = tr(QUALITY_HINTS[i])))
	_row(col, "VSync", tr("On prevents screen tearing. Off, the FPS doesn't lock at 30."),
		_switch(GameState.vsync, GameState.set_vsync))
	_api_row(col)
	_row(col, tr("Show FPS"), tr("Frame counter in the corner during a match."), _switch(GameState.show_fps, GameState.set_show_fps))
	return col


## Resolução: na janela, o tamanho dela; na tela cheia, a do monitor (padrão) ou uma menor,
## mais leve, esticada até o monitor. A lista muda com o modo.
func _refresh_video(mode: int, refs: Dictionary) -> void:
	refs["mode_hint"].text = tr(MODE_HINTS[mode])
	var pick: OptionButton = refs["res_pick"]
	pick.clear()
	var options: Array
	var chosen: Vector2i
	if mode == 0:
		options = GameState.available_resolutions()
		chosen = GameState.resolution
	else:
		options = GameState.fullscreen_resolutions()
		chosen = GameState.fullscreen_res
	var screen := DisplayServer.screen_get_size()
	for r: Vector2i in options:
		pick.add_item(tr("Monitor's  (%d x %d)") % [screen.x, screen.y] if r == Vector2i.ZERO else "%d x %d" % [r.x, r.y])
	pick.select(maxi(0, options.find(chosen)))
	refs["res_options"] = options
	var hint: Label = refs["res_hint"]
	hint.visible = true
	if mode == 0:
		hint.text = tr("Window size on launch. When maximized, the game follows.")
	elif chosen == Vector2i.ZERO:
		hint.text = tr("Sharp and heavier. A lower one makes the game lighter.")
	else:
		hint.text = tr("Lighter: the game is drawn smaller and stretched to the monitor.")


## API gráfica: lista suspensa; a frase diz a que está em uso e se falta reiniciar (no menu
## principal aparece o botão para reiniciar).
func _api_row(col: VBoxContainer) -> void:
	var box := Ui.vbox(8)
	var ids: Array = GameState.GRAPHICS_APIS.map(func(a): return a[0])
	var pick := _dropdown(GameState.GRAPHICS_APIS.map(func(a): return tr(a[1]) + (tr("  (recommended)") if a[0] == "compat" else "")),
		ids.find(GameState.chosen_graphics_api()))
	box.add_child(pick)
	var restart := Ui.accent(Ui.button(tr("Restart now"), GameState.restart_game))
	restart.custom_minimum_size.y = 36
	box.add_child(restart)
	var refs := {"hint": _row(col, tr("Graphics API"), "", box)}
	var refresh := func():
		var hint: Label = refs["hint"]
		hint.visible = true
		var chosen := GameState.chosen_graphics_api()
		var now := tr("In use: %s.") % GameState.current_graphics_api()
		var pending := chosen != GameState.api_at_start
		var fell_back := not pending and chosen != "compat" \
			and RenderingServer.get_current_rendering_driver_name().begins_with("opengl3")
		if pending:
			hint.text = now + " " + tr("The choice applies after restarting.")
			hint.add_theme_color_override("font_color", Ui.WARN)
		elif fell_back:
			hint.text = now + " " + tr("This PC doesn't have %s; fell back to OpenGL.") % tr(GameState.GRAPHICS_APIS[ids.find(chosen)][1])
			hint.add_theme_color_override("font_color", Ui.WARN)
		else:
			hint.text = now + " " + tr("Vulkan and DirectX 12 are heavier on integrated graphics.")
			hint.add_theme_color_override("font_color", Ui.MUTED)
		restart.visible = in_main_menu and pending
	pick.item_selected.connect(func(i):
		GameState.set_graphics_api(ids[i])
		refresh.call())
	refresh.call()


func _audio_page() -> Control:
	var col := _page(tr("Audio"))
	_section(col, tr("VOLUME"))
	for b in GameState.AUDIO_BUSES:
		var hint := ""
		match b[0]:
			"Master":
				hint = tr("Everything the game plays.")
			"Efeitos":
				hint = tr("Shots, explosions and footsteps in the world.")
			"Interface":
				hint = tr("Hits, kills and damage taken.")
			"Musica":
				hint = tr("There's no music in the game yet.")
		_row(col, tr(b[1]), hint, _volume_slider(b[0]))
	col.add_child(Ui.gap(10))
	col.add_child(Ui.label(tr("Release the slider to hear a sample."), 13, Ui.MUTED))
	return col


func _credits_page() -> Control:
	var col := _page(tr("Credits"))
	_section(col, tr("ASSETS"))
	var text := Ui.label(tr("Models and sounds by Kenney (kenney.nl), CC0.\n\nCard icons from game-icons.net, by Lorc, Delapouite, Caro Asercion, Faithtoken, Felbrigg, HeavenlyDog, John Colburn, Lucas, Sbed and Skoll (CC BY 3.0)."), 15, Ui.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(Ui.gap(14))
	col.add_child(text)
	return col


## Barra com o valor à direita.
func _slider_box(slider: HSlider, value: Label) -> Control:
	var row := Ui.hbox(12)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	value.custom_minimum_size.x = 52
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _sens_slider() -> Control:
	var slider := HSlider.new()
	slider.min_value = 0.25
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = GameState.mouse_sens / GameState.DEFAULT_SENS
	var value := Ui.label("%.2fx" % slider.value, 15, Ui.TEXT)
	slider.value_changed.connect(func(v):
		value.text = "%.2fx" % v
		GameState.set_mouse_sens(v * GameState.DEFAULT_SENS))
	return _slider_box(slider, value)


## Volume de um canal: barra e porcentagem ("Mudo" no zero). Ao soltar a barra toca um som
## de exemplo naquele canal (Geral usa um tiro).
const VOLUME_SAMPLE := {"Master": "shot", "Efeitos": "explosion", "Interface": "hitmarker"}


func _volume_slider(bus: String) -> Control:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = GameState.volumes[bus]
	var value := Ui.label("", 15, Ui.TEXT)
	var show := func(v: float):
		value.text = tr("Muted") if v <= 0.0 else "%d%%" % int(v)
		value.add_theme_color_override("font_color", Ui.MUTED if v <= 0.0 else Ui.TEXT)
	show.call(slider.value)
	slider.value_changed.connect(func(v):
		show.call(v)
		GameState.set_volume(bus, int(v)))
	slider.drag_ended.connect(func(_changed):
		if VOLUME_SAMPLE.has(bus):
			Sfx.preview(self, VOLUME_SAMPLE[bus], "Master" if bus == "Master" else bus))
	return _slider_box(slider, value)


## Controles: sensibilidade e uma linha por ação, com duas vagas de tecla. Clicar numa vaga
## e apertar a tecla (ou botão do mouse) nova; Esc cancela; botão direito esvazia a vaga.
func _controls_page() -> Control:
	var col := _page(tr("Controls"))
	_section(col, tr("MOUSE"))
	_row(col, tr("Sensitivity"), "", _sens_slider())
	var reset := Ui.flat(Ui.button(tr("Restore defaults"), func():
		stop_rebind()
		GameState.reset_binds()
		_refresh_binds()))
	reset.custom_minimum_size.y = 30
	reset.add_theme_font_size_override("font_size", 13)
	_section(col, tr("KEYS"), reset)
	bind_hint = Ui.label("", 13, Ui.MUTED)
	bind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(Ui.gap(8))
	col.add_child(bind_hint)
	col.add_child(Ui.gap(4))
	for a in GameState.ACTIONS:
		var keys := Ui.hbox(8)
		for slot in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(0, 34)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_start_rebind.bind(a[0], slot))
			b.gui_input.connect(func(event: InputEvent):
				var mb := event as InputEventMouseButton
				if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and rebind_action == "":
					GameState.set_bind(a[0], slot, "")
					_refresh_binds())
			keys.add_child(b)
			bind_buttons[[a[0], slot]] = b
		_row(col, GameState.action_label(a[0]), "", keys)
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
	if bind_hint == null:
		return
	var warnings := []
	for key in bind_buttons:
		var action: String = key[0]
		var code: String = GameState.binds[action][key[1]]
		var b: Button = bind_buttons[key]
		var clash := GameState.conflicts(action, code)
		if action == rebind_action and key[1] == rebind_slot:
			b.text = tr("Press a key...")
			b.add_theme_color_override("font_color", Ui.ACCENT)
		else:
			b.text = GameState.code_text(code) if code != "" else "-"
			b.add_theme_color_override("font_color", Ui.WARN if not clash.is_empty() else (Ui.TEXT if code != "" else Ui.MUTED))
		if not clash.is_empty() and action < clash[0]:
			warnings.append(tr("%s is on %s and on %s.") % [GameState.code_text(code), GameState.action_label(action),
				", ".join(clash.map(GameState.action_label))])
	if rebind_action != "":
		bind_hint.text = tr("Press the key or mouse button for %s. Esc cancels.") % GameState.action_label(rebind_action)
		bind_hint.add_theme_color_override("font_color", Ui.ACCENT)
	elif not warnings.is_empty():
		bind_hint.text = tr("Repeated key:") + " " + " ".join(warnings)
		bind_hint.add_theme_color_override("font_color", Ui.WARN)
	else:
		bind_hint.text = tr("Click a key to change it; right click clears it. Aim and Esc are fixed.")
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
