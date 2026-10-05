class_name DraftScreen
extends CanvasLayer
## Tela de escolha. choose() mostra cartas e devolve (com await) a escolhida;
## ask() mostra botões de texto e devolve o índice do escolhido.

signal picked(index: int)

var _count := 0


func _ready() -> void:
	layer = 10
	visible = false


func choose(options: Array, title: String, owned: Array) -> String:
	var row := _open(title, "Clique numa carta ou aperte 1, 2 ou 3")
	for i in options.size():
		row.add_child(_card(options[i], i, owned.count(options[i])))
	var index: int = await _wait(options.size())
	return options[index]


func ask(title: String, subtitle: String, labels: Array) -> int:
	var row := _open(title, subtitle)
	for i in labels.size():
		var b := Button.new()
		b.text = "[%d]  %s" % [i + 1, labels[i]]
		b.custom_minimum_size = Vector2(260, 60)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func(): picked.emit(i))
		row.add_child(b)
	return await _wait(labels.size())


func _open(title: String, subtitle: String) -> HBoxContainer:
	for child in get_children():
		child.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = Ui.theme()
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 760   # sem largura mínima o texto quebraria a cada palavra
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	column.add_child(_text(title, 36))
	column.add_child(_text(subtitle, 18))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	return row


## Fecha a tela sem resposta (a partida acabou ou a conexão caiu).
func close() -> void:
	visible = false
	_count = 0


func _wait(count: int) -> int:
	_count = count
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var index: int = await picked
	visible = false
	return index


func _card(id: String, index: int, owned: int) -> Button:
	var card: Dictionary = CardDB.CARDS[id]
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 400)
	button.pressed.connect(func(): picked.emit(index))
	var color: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	button.add_theme_stylebox_override("normal", Ui.box(Ui.SURFACE, 14, color.darkened(0.3), 2))
	button.add_theme_stylebox_override("hover", Ui.box(Ui.SURFACE_HI, 14, color, 3))
	button.add_theme_stylebox_override("pressed", Ui.box(Ui.SURFACE_HI, 14, Color.WHITE, 3))

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	button.add_child(column)
	column.add_child(_text("[%d]" % (index + 1), 18))
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 10)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tags)
	var cat := _text(card["cat"], 15)
	cat.add_theme_color_override("font_color", CardDB.CATEGORY_COLORS[card["cat"]])
	cat.autowrap_mode = TextServer.AUTOWRAP_OFF
	tags.add_child(cat)
	var rarity := _text(CardDB.rarity_name(id), 15)
	rarity.add_theme_color_override("font_color", CardDB.rarity_color(id))
	rarity.autowrap_mode = TextServer.AUTOWRAP_OFF
	tags.add_child(rarity)
	var icon := CardIcon.make(id, 72, 1, false)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	column.add_child(_text(card["name"], 26))
	column.add_child(_text(card["desc"], 16))
	if owned > 0:
		var stack := _text("Você já tem %d" % owned, 16)
		stack.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		column.add_child(stack)
	return button


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or GameState.menu_open or GameState.chat_open or key == null or not key.pressed or key.echo:
		return
	var index := key.physical_keycode - KEY_1
	if index >= 0 and index < _count:
		get_viewport().set_input_as_handled()
		picked.emit(index)
