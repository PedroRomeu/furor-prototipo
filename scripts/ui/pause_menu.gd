class_name PauseMenu
extends CanvasLayer
## Menu do Esc na partida: Continuar, Configurações, Sair para o menu e Sair do jogo.
## Contra bots o jogo para (SceneTree.paused); online a partida segue rodando e o
## personagem fica parado (GameState.menu_open). Sair pede confirmação.
##
## Roda mesmo com o jogo parado (PROCESS_MODE_ALWAYS). Esc volta um passo: confirmação ->
## configurações -> menu -> jogo.

signal resumed
signal leave_requested   # voltar ao menu principal
signal quit_requested    # fechar o jogo

const PANEL_WIDTH := 400.0

var online := false
var practice := false   # sala de teste: "Voltar ao editor" sem confirmar, sem placar
var _score_title: Label
var _root: Control
var _title: Label
var _subtitle: Label
var _status: Label
var _score: Label
var _main: Control
var _settings_page: Control
var _settings: SettingsPanel
var _confirm: Control
var _confirm_title: Label
var _confirm_text: Label
var _confirm_ok: Button
var _confirm_action: Callable


func _ready() -> void:
	layer = 20   # acima do HUD e da tela de escolha
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.theme = Ui.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_main = _main_panel()
	_root.add_child(_main)
	_settings_page = _settings_screen()
	_root.add_child(_settings_page)
	_confirm = _confirm_box()
	_root.add_child(_confirm)


## info: rodada e adversários; score: placar em texto.
func open(info: String, score: String) -> void:
	_title.text = "MENU" if online else "PAUSA"
	_subtitle.text = info
	_score.text = score
	_status.visible = online
	_show_main()
	visible = true
	GameState.menu_open = true
	if not online:
		get_tree().paused = true


func close() -> void:
	if not visible:
		return
	_settings.stop_rebind()
	visible = false
	GameState.menu_open = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _confirm.visible:
		_confirm.visible = false
	elif _settings_page.visible:
		_show_main()
	else:
		_resume()


func _resume() -> void:
	close()
	resumed.emit()


func _show_main() -> void:
	_settings.stop_rebind()
	_main.visible = true
	_settings_page.visible = false
	_confirm.visible = false


# ---------------------------------------------------------------- telas

## Coluna à esquerda, da altura da tela, com o título e as ações.
func _main_panel() -> Control:
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_right = PANEL_WIDTH
	var style := Ui.box(Color(Ui.BG, 0.97), 0)
	style.content_margin_left = 48
	style.content_margin_right = 40
	style.content_margin_top = 56
	style.content_margin_bottom = 40
	style.border_color = Ui.ACCENT
	style.border_width_right = 3
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(0)
	panel.add_child(col)
	col.add_child(Ui.label("FUROR", 14, Ui.MUTED, true))
	col.add_child(Ui.gap(4))
	_title = Ui.label("", 52, Ui.TEXT, true)
	col.add_child(_title)
	_subtitle = Ui.label("", 15, Ui.MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle)
	col.add_child(Ui.gap(12))
	_status = Ui.label("ONLINE  ·  A PARTIDA CONTINUA", 13, Ui.WARN, true)
	col.add_child(_status)
	col.add_child(Ui.gap(36))

	var menu := Ui.vbox(10)
	col.add_child(menu)
	var resume := Ui.accent(_menu_button("Continuar", _resume))
	resume.custom_minimum_size.y = 56
	resume.add_theme_font_size_override("font_size", 20)
	menu.add_child(resume)
	menu.add_child(_menu_button("Configurações", func():
		_main.visible = false
		_settings_page.visible = true))
	menu.add_child(Ui.gap(14))
	if practice:
		menu.add_child(_menu_button("Voltar ao editor", func(): leave_requested.emit()))
	else:
		menu.add_child(_menu_button("Sair para o menu", _ask_leave))
	menu.add_child(_menu_button("Sair do jogo", _ask_quit))

	col.add_child(Ui.grow())
	_score_title = Ui.label("PLACAR", 12, Ui.MUTED, true)
	_score_title.visible = not practice
	col.add_child(_score_title)
	col.add_child(Ui.gap(4))
	_score = Ui.label("", 16, Ui.TEXT)
	_score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_score)
	col.add_child(Ui.gap(20))
	col.add_child(Ui.label("Esc  voltar ao jogo", 13, Ui.MUTED))
	return panel


## Configurações em tela cheia (as mesmas do menu principal, sem o nome).
func _settings_screen() -> Control:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := Ui.box(Color(Ui.BG, 0.97), 0)
	style.content_margin_left = 64
	style.content_margin_right = 64
	style.content_margin_top = 48
	style.content_margin_bottom = 48
	bg.add_theme_stylebox_override("panel", style)
	var root := Ui.vbox(24)
	bg.add_child(root)
	var header := Ui.hbox(16)
	root.add_child(header)
	header.add_child(Ui.flat(Ui.button("< Voltar", _show_main)))
	var titles := Ui.vbox(2)
	titles.add_child(Ui.label("Configurações", 32, Ui.TEXT, true))
	titles.add_child(Ui.label("Salvas sozinhas e valem na hora.", 15, Ui.MUTED))
	header.add_child(titles)
	_settings = SettingsPanel.new()
	_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_settings)
	return bg


## Caixa de confirmação no centro, por cima de tudo.
func _confirm_box() -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 480
	var style := Ui.box(Ui.SURFACE, 12, Ui.LINE)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := Ui.vbox(10)
	panel.add_child(col)
	_confirm_title = Ui.label("", 24, Ui.TEXT, true)
	col.add_child(_confirm_title)
	_confirm_text = Ui.label("", 16, Ui.MUTED)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_confirm_text)
	col.add_child(Ui.gap(14))
	var row := Ui.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	row.add_child(Ui.flat(Ui.button("Cancelar", func(): _confirm.visible = false, 120)))
	_confirm_ok = _danger(Ui.button("", func(): _confirm_action.call(), 160))
	row.add_child(_confirm_ok)
	return shade


func _ask(title: String, text: String, ok_text: String, action: Callable) -> void:
	_confirm_title.text = title
	_confirm_text.text = text
	_confirm_ok.text = ok_text
	_confirm_action = action
	_confirm.visible = true


func _ask_leave() -> void:
	var text := "O progresso desta partida será perdido."
	if online:
		text = "A partida acaba para todos na sala."
	_ask("Sair para o menu?", text, "Sair da partida", func():
		close()
		leave_requested.emit())


func _ask_quit() -> void:
	var text := "O jogo vai fechar e o progresso desta partida será perdido."
	if online:
		text = "O jogo vai fechar e a partida acaba para todos na sala."
	_ask("Sair do jogo?", text, "Fechar o jogo", func():
		close()
		quit_requested.emit())


# ---------------------------------------------------------------- peças

func _menu_button(text: String, action: Callable) -> Button:
	var b := Ui.button(text, action)
	b.custom_minimum_size.y = 50
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	return b


## Botão vermelho da ação que não tem volta.
func _danger(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", Ui.box(Ui.DANGER.darkened(0.25), 8))
	b.add_theme_stylebox_override("hover", Ui.box(Ui.DANGER.darkened(0.1), 8))
	b.add_theme_stylebox_override("pressed", Ui.box(Ui.DANGER.darkened(0.4), 8))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_font_override("font", Ui.bold())
	return b
