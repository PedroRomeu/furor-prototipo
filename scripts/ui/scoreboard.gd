class_name Scoreboard
extends Control
## Placar da partida, aberto segurando Tab (ação "scoreboard"): uma linha por jogador com
## rodadas vencidas, abates, assistências e mortes, e embaixo as cartas dele (ícones; passar
## o mouse mostra o efeito). Ordem: mais rodadas, depois mais abates.

const STATS := ["RODADAS", "ABATES", "ASSIST.", "MORTES"]
const STAT_WIDTH := 76.0
const ICON_SIZE := 34.0

var me: Player
var players: Array = []
var score := {}        # nome do nó -> rodadas vencidas
var kda := {}          # nome do nó -> [abates, assistências, mortes]
var round_text := ""
## Fim da partida (Hud.show_end): resultado no lugar de "PLACAR" e botões embaixo.
var result_text := ""
var result_color := Ui.TEXT
var buttons := {}            # texto -> Callable; o primeiro é o principal
var _rows: VBoxContainer
var _round_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35 if result_text == "" else 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := Ui.box(Color(Ui.BG, 0.95), 14, Ui.LINE)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 900
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var col := Ui.vbox(14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var header := Ui.hbox(12)
	col.add_child(header)
	if result_text == "":
		header.add_child(Ui.label("PLACAR", 15, Ui.TEXT, true))
	else:
		var result := Ui.vbox(0)
		result.add_child(Ui.label("FIM DA PARTIDA", 12, Ui.MUTED, true))
		result.add_child(Ui.label(result_text, 34, result_color, true))
		header.add_child(result)
	header.add_child(Ui.spacer())
	_round_label = Ui.label("", 14, Ui.MUTED)
	_round_label.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(_round_label)

	# Títulos das colunas, alinhados com os números das linhas.
	var titles := Ui.hbox(0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(titles)
	col.add_child(pad)
	var who := Ui.label("JOGADOR", 12, Ui.MUTED, true)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_indent(who))
	for t in STATS:
		titles.add_child(_cell(t, 12, Ui.MUTED, true))
	col.add_child(HSeparator.new())
	_rows = Ui.vbox(6)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_rows)
	if buttons.is_empty():
		col.add_child(Ui.label("Passe o mouse numa carta para ver o efeito.", 13, Ui.MUTED))
	else:
		col.add_child(HSeparator.new())
		var foot := Ui.hbox(10)
		col.add_child(foot)
		foot.add_child(Ui.label("Passe o mouse numa carta para ver o efeito.", 13, Ui.MUTED))
		foot.add_child(Ui.spacer())
		var first := true
		for text in buttons:
			var b := Ui.button(text, buttons[text], 170)
			b.custom_minimum_size.y = 44
			if first:
				Ui.accent(b)
			else:
				Ui.flat(b)
			foot.add_child(b)
			first = false
	visible = false


func setup(p_me: Player, all_players: Array) -> void:
	me = p_me
	players = all_players


func open() -> void:
	visible = true
	rebuild()


func close() -> void:
	visible = false


## Refaz as linhas (chamado ao abrir e quando placar ou cartas mudam com a tela aberta).
func rebuild() -> void:
	if not visible or me == null:
		return
	_round_label.text = round_text
	for c in _rows.get_children():
		c.queue_free()
	var order := players.duplicate()
	order.sort_custom(func(a: Player, b: Player):
		var sa: int = score.get(String(a.name), 0)
		var sb: int = score.get(String(b.name), 0)
		if sa != sb:
			return sa > sb
		return _kda(a)[0] > _kda(b)[0])
	if me.team < 0:
		for p in order:
			_rows.add_child(_row(p))
		return
	# 2x2: seu time em cima, cada um com um cabeçalho e o placar do time.
	for t in [me.team, 1 - me.team]:
		var members := order.filter(func(p): return p.team == t)
		if t != me.team:
			_rows.add_child(Ui.gap(6))
		_rows.add_child(_team_header(t, score.get(String(members[0].name), 0) if not members.is_empty() else 0))
		for p in members:
			_rows.add_child(_row(p))


func _team_header(team: int, rounds: int) -> Control:
	var color: Color = GameState.TEAM_COLORS[team][0]
	var line := Ui.hbox(10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip := ColorRect.new()
	strip.color = color
	strip.custom_minimum_size = Vector2(18, 4)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(strip)
	line.add_child(Ui.label("TIME %s" % String(GameState.TEAM_NAMES[team]).to_upper(), 14, color.lightened(0.35), true))
	if team == me.team:
		line.add_child(Ui.label("seu time", 13, Ui.MUTED))
	line.add_child(Ui.spacer())
	line.add_child(Ui.label("%d rodada%s" % [rounds, "" if rounds == 1 else "s"], 14, Ui.TEXT, true))
	for c in line.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _kda(p: Player) -> Array:
	return kda.get(String(p.name), [0, 0, 0])


func _row(p: Player) -> Control:
	var box := PanelContainer.new()
	var mine := p == me
	var style := Ui.box(Ui.SURFACE if mine else Color.TRANSPARENT, 10)
	style.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Ui.vbox(10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)

	var line := Ui.hbox(0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	var tag := Ui.hbox(10)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(tag)
	var swatch := ColorRect.new()
	swatch.color = p.color
	swatch.custom_minimum_size = Vector2(4, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(swatch)
	tag.add_child(Ui.label(p.player_name, 18, Ui.TEXT, true))
	if not p.alive:
		tag.add_child(Ui.label("fora da rodada", 13, Ui.MUTED))
	var k := _kda(p)
	var values := [score.get(String(p.name), 0), k[0], k[1], k[2]]
	for i in values.size():
		line.add_child(_cell(str(values[i]), 18, Ui.TEXT if i < 2 else Ui.MUTED, i < 2))

	var cards := _indent(_card_flow(p))
	col.add_child(cards)
	box.modulate.a = 1.0 if p.alive else 0.7
	return box


## Mestra primeiro, depois as cartas na ordem em que foram pegas, uma vez cada com o número
## de cópias.
func _card_flow(p: Player) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids: Array = p.cards.filter(CardDB.is_master)
	for id in p.cards:
		if not id in ids:
			ids.append(id)
	for id in ids:
		flow.add_child(CardIcon.make(id, ICON_SIZE, p.cards.count(id)))
	if ids.is_empty():
		flow.add_child(Ui.label("Nenhuma carta ainda", 14, Ui.MUTED))
	return flow


## Recuo que alinha nomes e cartas depois da faixa de cor.
func _indent(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


func _cell(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Ui.label(text, size, color, bold)
	l.custom_minimum_size.x = STAT_WIDTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
