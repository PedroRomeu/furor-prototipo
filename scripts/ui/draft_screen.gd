class_name DraftScreen
extends CanvasLayer
## Telas entre as rodadas. choose() mostra cartas e devolve (com await) a escolhida;
## vote() mostra a votação do fim do bloco e devolve o voto, ficando aberta com os votos
## dos outros (set_votes) até a partida seguir ou acabar (close).

signal picked(index: int)

const CARD_SIZE := Vector2(250, 372)
const DESC_HEIGHT := 112.0    # ~6 linhas; descrição maior rola dentro da carta
const VOTE_WIDTH := 560.0

var _count := 0
var _voting := false
var _vote_rows := {}          # nome do nó -> [Label do estado, Player]
var _vote_buttons: Array = []
var _cards: Array = []        # [PanelContainer, grupo] de cada carta, para o realce


func _ready() -> void:
	layer = 10
	visible = false


## title: o que aconteceu ("Você perdeu a rodada"); a linha de baixo pede a escolha.
func choose(options: Array, title: String, owned: Array) -> String:
	var col := _open()
	col.add_child(_heading(title, "Escolha uma carta para o seu baralho da partida"))
	var row := Ui.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_cards.clear()
	for i in options.size():
		row.add_child(_card(options[i], i, owned.count(options[i])))
	var keys := "1, 2 ou 3" if options.size() == 3 else "1 a %d" % options.size()
	var hint := Ui.label("Clique numa carta ou aperte %s" % keys, 14, Ui.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var index: int = await _wait(options.size())
	return options[index]


## Votação do fim do bloco. voters: os jogadores que votam (todos em rede; só você
## contra bots). Devolve true para continuar. A tela fica aberta depois do voto.
func vote(round_num: int, extra: int, score_text: String, voters: Array, online: bool) -> bool:
	var col := _open()
	var panel := PanelContainer.new()
	var style := Ui.box(Color(Ui.BG, 0.97), 14, Ui.LINE)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = VOTE_WIDTH
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(panel)
	var inner := Ui.vbox(18)
	panel.add_child(inner)

	var top := Ui.label("FIM DO BLOCO  ·  RODADA %d" % round_num, 13, Ui.ACCENT, true)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(top)
	var score := Ui.label(score_text, 26, Ui.TEXT, true)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(score)
	var ask := Ui.label("Jogar mais %d rodadas ou terminar a partida?" % extra, 15, Ui.MUTED)
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(ask)

	var buttons := Ui.hbox(12)
	inner.add_child(buttons)
	_vote_buttons.clear()
	var labels := ["Mais %d rodadas" % extra, "Terminar"]
	for i in 2:
		var b := Ui.button("%s   %d" % [labels[i], i + 1], func(): picked.emit(i))
		b.custom_minimum_size.y = 50
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		if i == 0:
			Ui.accent(b)
		buttons.add_child(b)
		_vote_buttons.append(b)

	_vote_rows.clear()
	if online:
		inner.add_child(HSeparator.new())
		var head := Ui.hbox(8)
		inner.add_child(head)
		head.add_child(Ui.label("VOTOS", 12, Ui.MUTED, true))
		head.add_child(Ui.spacer())
		head.add_child(Ui.label("Só continua se todos quiserem", 12, Ui.MUTED))
		var list := Ui.vbox(6)
		inner.add_child(list)
		for p in voters:
			var line := Ui.hbox(10)
			var swatch := ColorRect.new()
			swatch.color = p.color
			swatch.custom_minimum_size = Vector2(4, 20)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(swatch)
			line.add_child(Ui.label(p.player_name, 15, Ui.TEXT, true))
			line.add_child(Ui.spacer())
			var state := Ui.label("", 14, Ui.MUTED)
			line.add_child(state)
			list.add_child(line)
			_vote_rows[String(p.name)] = [state, p]
		set_votes({})

	_voting = true
	var choice: int = await _wait(2, false)
	for i in 2:
		_vote_buttons[i].disabled = true
		if i == choice:
			_vote_buttons[i].text = "%s  ✓" % labels[i]
			_vote_buttons[i].disabled = false
			_vote_buttons[i].mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voting = false
	return choice == 0


## Votos que já chegaram (nome do nó -> true para continuar).
func set_votes(votes: Dictionary) -> void:
	for n in _vote_rows:
		var state: Label = _vote_rows[n][0]
		if not votes.has(n):
			state.text = "votando..."
			state.add_theme_color_override("font_color", Ui.MUTED)
		elif votes[n]:
			state.text = "Continuar"
			state.add_theme_color_override("font_color", Ui.OK)
		else:
			state.text = "Terminar"
			state.add_theme_color_override("font_color", Ui.DANGER)


## Fecha a tela sem resposta (a partida seguiu, acabou ou a conexão caiu).
func close() -> void:
	visible = false
	_count = 0
	_voting = false


## Fundo escuro e uma coluna centralizada; devolve a coluna.
func _open() -> VBoxContainer:
	for child in get_children():
		child.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.035, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = Ui.theme()
	add_child(center)
	var column := Ui.vbox(22)
	center.add_child(column)
	return column


func _heading(title: String, subtitle: String) -> Control:
	var col := Ui.vbox(4)
	var t := Ui.label(title, 30, Ui.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := Ui.label(subtitle, 15, Ui.MUTED)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)
	return col


func _wait(count: int, hide_after := true) -> int:
	_count = count
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var index: int = await picked
	_count = 0
	if hide_after:
		visible = false
	return index


## Carta da escolha, no visual do editor: moldura do grupo, símbolo do grupo e tecla no
## topo, ícone, nome, grupo, raridade e cópias, e a descrição numa área fixa que rola.
func _card(id: String, index: int, owned: int) -> Control:
	var card: Dictionary = CardDB.CARDS[id]
	var color: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _count > 0:
			picked.emit(index))
	panel.mouse_entered.connect(_style_card.bind(index, true))
	panel.mouse_exited.connect(_style_card.bind(index, false))
	_cards.append([panel, card["cat"]])
	_style_card(index, false)
	var col := Ui.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var top := Ui.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(CardFrame.symbol_rect(card["cat"], 20))
	top.add_child(Ui.spacer())
	top.add_child(_chip(str(index + 1), Ui.SURFACE_HI, Ui.MUTED))

	var icon := CardIcon.make(id, 76, 1, false)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	var name_label := Ui.label(card["name"], 21, Ui.TEXT, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var tags := Ui.hbox(8)
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tags)
	for t in [[card["cat"], color.lerp(Color.WHITE, 0.15)], ["·", Ui.LINE.lightened(0.3)],
			[CardDB.rarity_name(id), CardDB.rarity_color(id)]]:
		var l := Ui.label(t[0], 13, t[1], true)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tags.add_child(l)
	if owned > 0:
		var have := _chip("você tem x%d" % owned, color, Ui.BG)
		have.tooltip_text = "Pegar de novo soma o efeito"
		have.mouse_filter = Control.MOUSE_FILTER_PASS
		tags.add_child(have)
	col.add_child(HSeparator.new())
	var desc := Ui.scroll_text(card["desc"], DESC_HEIGHT, 14, Ui.TEXT.darkened(0.15))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(desc)
	return panel


func _style_card(index: int, hot: bool) -> void:
	if index >= _cards.size():
		return
	var panel: PanelContainer = _cards[index][0]
	# Moldura do grupo (CardFrame); com o mouse em cima brilha mais e cresce um pouco.
	var style := CardFrame.style(_cards[index][1], "hot" if hot else "lit")
	style.content_margin_top = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.pivot_offset = CARD_SIZE / 2.0
	panel.scale = Vector2.ONE * (1.03 if hot else 1.0)


## Etiqueta pequena com fundo (tecla da carta, cópias que você já tem).
func _chip(text: String, bg: Color, fg: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_font_override("font", Ui.bold())
	l.add_theme_color_override("font_color", fg)
	var s := Ui.box(bg, 6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", s)
	return l


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or _count == 0 or GameState.menu_open or GameState.chat_open or key == null \
			or not key.pressed or key.echo:
		return
	var index := key.physical_keycode - KEY_1
	if index >= 0 and index < _count:
		get_viewport().set_input_as_handled()
		picked.emit(index)
