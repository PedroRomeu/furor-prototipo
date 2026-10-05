class_name ChatBox
extends VBoxContainer
## Chat online (Net.chat_log), o mesmo na sala e na partida. Cada nome sai na cor do
## jogador (a da vaga ou do time); avisos de entrada e saída saem apagados.
##
## Na sala: histórico e campo sempre à vista; Enter leva o cursor ao campo, Esc o tira.
## Na partida: as mensagens aparecem no canto e somem depois de FADE_AFTER segundos;
## a tecla do chat (Enter) abre o campo, Enter manda e fecha, Esc fecha sem mandar.
## Com o campo aberto o personagem fica parado (GameState.chat_open).

const FADE_AFTER := 7.0
const FADE_TIME := 1.0

var in_match := false
var log_view: RichTextLabel
var input: LineEdit
var _back: StyleBoxFlat
var _idle := 0.0


func _init(p_in_match := false) -> void:
	in_match = p_in_match


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = false
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 15)
	log_view.add_theme_font_size_override("bold_font_size", 15)
	log_view.add_theme_color_override("default_color", Ui.TEXT)
	log_view.add_theme_constant_override("line_separation", 3)
	log_view.add_theme_font_override("bold_font", Ui.bold())
	add_child(log_view)
	input = LineEdit.new()
	input.max_length = Net.CHAT_MAX
	input.custom_minimum_size.y = 40
	input.context_menu_enabled = false
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	add_child(input)
	if in_match:
		# Fundo só com o campo aberto; fechado, só o texto com contorno por cima do jogo.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_view.scroll_active = false
		log_view.add_theme_constant_override("outline_size", 5)
		log_view.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		input.placeholder_text = "Mensagem para todos  ·  Enter manda, Esc cancela"
		input.visible = false
		_back = Ui.box(Color(Ui.BG, 0.0), 8)
		_back.set_content_margin_all(8)
		var holder := get_parent()
		if holder is PanelContainer:
			holder.add_theme_stylebox_override("panel", _back)
		modulate.a = 0.0
	else:
		input.placeholder_text = "Mensagem para a sala"
		var area := Ui.box(Ui.BG, 8)
		area.set_content_margin_all(12)
		log_view.add_theme_stylebox_override("normal", area)
	for entry in Net.chat_log:
		_append(entry)
	Net.chat_received.connect(_on_message)


func _exit_tree() -> void:
	if in_match and is_open():
		GameState.chat_open = false


func is_open() -> bool:
	return input.visible and input.has_focus()


func open() -> void:
	input.visible = true
	input.grab_focus()
	if in_match:
		GameState.chat_open = true
	_set_back(true)
	modulate.a = 1.0
	_idle = 0.0


func close() -> void:
	input.text = ""
	input.release_focus()
	if in_match:
		input.visible = false
		GameState.chat_open = false
		_set_back(false)
	_idle = 0.0


func _set_back(on: bool) -> void:
	if _back:
		_back.bg_color = Color(Ui.BG, 0.72 if on else 0.0)
		log_view.scroll_active = on


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("chat") or event.is_echo() or not Net.online:
		return
	if in_match and (GameState.menu_open or input.visible):
		return
	if not is_visible_in_tree():
		return
	get_viewport().set_input_as_handled()
	open()


func _on_input_key(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close()


func _on_submit(text: String) -> void:
	Net.send_chat(text)
	input.text = ""
	if in_match:
		close()


func _on_message(entry: Dictionary) -> void:
	_append(entry)
	if in_match:
		modulate.a = 1.0
		_idle = 0.0


func _append(entry: Dictionary) -> void:
	if log_view.get_parsed_text() != "":
		log_view.append_text("\n")
	var text := _escape(entry["text"])
	if entry["system"]:
		log_view.append_text("[color=#%s]%s[/color]" % [Ui.MUTED.to_html(false), text])
	else:
		var color: Color = entry["color"]
		log_view.append_text("[b][color=#%s]%s[/color][/b]  %s" % [
			color.lightened(0.25).to_html(false), _escape(entry["name"]), text])


## O texto vem de outra pessoa: "[" vira literal para ninguém mudar cor ou formato no chat.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _process(delta: float) -> void:
	if not in_match:
		return
	if input.visible:
		if GameState.menu_open or not input.has_focus():
			close()
		return
	_idle += delta
	if _idle > FADE_AFTER:
		modulate.a = maxf(0.0, 1.0 - (_idle - FADE_AFTER) / FADE_TIME)
