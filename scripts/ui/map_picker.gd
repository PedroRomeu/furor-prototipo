class_name MapPicker
extends Control
## Lista de mapas da sala (2026-10-05, organização do usuário): janela por cima da sala,
## aberta pelo botão "Mapas". Filtro por estilo no topo e, em cada estilo, os três tamanhos,
## cada um com o botão de ligar e desligar. Só o anfitrião mexe; os convidados veem o que
## pode sair. Mapa que o anfitrião nunca clicou aparece como "automático" (MapList.auto_on).
## Lê e grava pelo Net (Net.maps, set_map, set_all_maps) e se redesenha quando a sala muda.

var _filter := -1   # estilo mostrado (-1 todos)
var _list: VBoxContainer
var _count: Label
var _note: Label
var _bottom: Control
var _filter_buttons: Array = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := PanelContainer.new()
	var style := Ui.box(Ui.BG, 14, Ui.LINE)
	style.set_content_margin_all(26)
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(620, 0)
	center.add_child(frame)
	var col := Ui.vbox(12)
	frame.add_child(col)

	var head := Ui.hbox(12)
	head.add_child(Ui.label("Mapas", 26, Ui.TEXT, true))
	head.add_child(Ui.spacer())
	_count = Ui.label("", 15, Ui.MUTED)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	col.add_child(head)
	var filters := Ui.tabs(["Todos"] + Arena.STYLES, 0, func(i):
		_filter = i - 1
		_refresh())
	_filter_buttons = filters.get_children()
	col.add_child(filters)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 400
	col.add_child(scroll)
	_list = Ui.vbox(0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_note = Ui.label("", 13, Ui.MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)
	var row := Ui.hbox(10)
	_bottom = Ui.hbox(10)
	_bottom.add_child(Ui.button("Ligar todos", func(): Net.set_all_maps(true), 130))
	_bottom.add_child(Ui.flat(Ui.button("Voltar ao automático", func(): Net.set_all_maps(false))))
	row.add_child(_bottom)
	row.add_child(Ui.spacer())
	row.add_child(Ui.accent(Ui.button("Fechar", close, 120)))
	col.add_child(row)


func _ready() -> void:
	Net.lobby_changed.connect(func(_c): _refresh())


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


## Texto do botão da sala: "Mapas  ·  9 de 12".
static func summary() -> String:
	var players := Net.arena_players()
	var on := range(MapList.count()).filter(func(i): return MapList.is_on(Net.maps, i, players)).size()
	return "Mapas  ·  %d de %d" % [on, MapList.count()]


func _refresh() -> void:
	if not visible:
		return
	var host := Net.is_host()
	var players := Net.arena_players()
	for i in _filter_buttons.size():
		_filter_buttons[i].set_pressed_no_signal(i == _filter + 1)
	for c in _list.get_children():
		c.queue_free()
	for s in Arena.STYLES.size():
		if _filter >= 0 and s != _filter:
			continue
		Ui.section(_list, Arena.STYLES[s].to_upper(), null, 4 if _list.get_child_count() == 0 else 18)
		for z in MapList.SIZES.size():
			_list.add_child(_row(s * MapList.SIZES.size() + z, players, host))
	_count.text = summary().trim_prefix("Mapas  ·  ") + " ligados"
	_bottom.visible = host
	if not host:
		_note.text = "Só o anfitrião liga e desliga mapas. A cada rodada sai um dos ligados, com um desenho novo."
	else:
		_note.text = "A cada rodada sai um dos ligados, com um desenho novo. Automático: os grandes ficam desligados com 2 na arena (1x1 e Duelos) e ligados com 3 ou 4."


const SIZE_HINTS := ["Encontros rápidos.", "Mais espaço e mais peças.", "Muros dividem a arena. Melhor com 3 ou 4."]


## Um tamanho do estilo: nome, frase curta, "automático" e o interruptor.
func _row(index: int, players: int, host: bool) -> Control:
	var on := MapList.is_on(Net.maps, index, players)
	var auto := not Net.maps.has(MapList.id(index))
	var z := MapList.size_of(index)
	var line := Ui.hbox(12)
	var texts := Ui.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(texts)
	texts.add_child(Ui.label(String(MapList.SIZES[z]["name"]).capitalize(), 15, Ui.TEXT if on else Ui.MUTED, on))
	texts.add_child(Ui.label(SIZE_HINTS[z], 12, Ui.MUTED if on else Ui.MUTED.darkened(0.25)))
	if auto:
		var a := Ui.label("automático", 12, Ui.MUTED.darkened(0.1))
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		a.tooltip_text = "O jogo decide pelo número de jogadores até você mudar."
		a.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(a)
	var sw := CheckButton.new()
	sw.button_pressed = on
	sw.disabled = not host
	sw.focus_mode = Control.FOCUS_NONE
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if host else Control.CURSOR_ARROW
	sw.toggled.connect(func(v):
		Net.set_map(index, v)
		_refresh.call_deferred())   # o último ligado não desliga: o interruptor volta
	line.add_child(sw)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_child(line)
	var box := Ui.vbox(0)
	box.add_child(pad)
	var sep := HSeparator.new()
	sep.modulate.a = 0.5
	box.add_child(sep)
	return box
