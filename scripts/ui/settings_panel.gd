class_name SettingsPanel
extends HBoxContainer
## Configurações em dois painéis: geral (nome, mouse, qualidade, FPS, créditos) e
## controles (troca de teclas). Usado no menu principal e no menu de pausa da partida.
## Tudo é salvo na hora pelo GameState.

const QUALITY_NAMES := ["Baixa", "Média", "Alta"]
const QUALITY_HINTS := [
	"Sem sombras, brilho nem névoa. Para PCs modestos.",
	"Sombras simples, sem brilho nem névoa.",
	"Sombras detalhadas, brilho, névoa e antisserrilhado. Pesada em placa de vídeo integrada.",
]

var bind_buttons := {}   # [ação, vaga] -> Button
var bind_hint: Label
var rebind_action := ""   # esperando tecla para esta ação ("" = não)
var rebind_slot := 0


## nick_field: campo do nome (o menu principal manda o seu); null esconde o nome.
func _init(nick_field: Control = null) -> void:
	add_theme_constant_override("separation", 20)
	var panel := Ui.panel(self)
	if nick_field:
		panel.add_child(Ui.label("Seu nome (o que os amigos veem online)", 14, Ui.MUTED))
		panel.add_child(nick_field)
		panel.add_child(Ui.gap(8))
	panel.add_child(Ui.label("Sensibilidade do mouse", 14, Ui.MUTED))
	panel.add_child(_sens_row())
	panel.add_child(Ui.gap(8))
	panel.add_child(Ui.label("Qualidade gráfica", 14, Ui.MUTED))
	var hint := Ui.label(QUALITY_HINTS[GameState.quality], 14, Ui.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(Ui.segmented(QUALITY_NAMES, GameState.quality, func(i):
		GameState.set_quality(i)
		hint.text = QUALITY_HINTS[i]))
	panel.add_child(hint)
	panel.add_child(Ui.gap(8))
	var fps := CheckButton.new()
	fps.text = "Mostrar FPS na partida"
	fps.button_pressed = GameState.show_fps
	fps.toggled.connect(GameState.set_show_fps)
	panel.add_child(fps)
	panel.add_child(Ui.grow())
	var credits := Ui.label("Créditos: modelos e sons de Kenney (CC0). Ícones das cartas de game-icons.net, "
		+ "por Lorc, Delapouite, Caro Asercion, Felbrigg, HeavenlyDog, John Colburn, Sbed e Skoll (CC BY 3.0).", 12, Ui.MUTED)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(credits)
	_controls_panel()


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


## Controles: uma linha por ação, com duas vagas de tecla. Clicar numa vaga e apertar a
## tecla (ou botão do mouse) nova; Esc cancela; botão direito na vaga a esvazia.
func _controls_panel() -> void:
	var col := Ui.panel(self)
	var top := Ui.hbox(8)
	col.add_child(top)
	top.add_child(Ui.label("Controles", 14, Ui.MUTED))
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
