class_name Hud
extends CanvasLayer
## Interface durante a luta. Tudo é criado por código; nada aqui captura o mouse.

const FROST_ICON := preload("res://assets/card_icons/marca_gelo.svg")   # selo do Congelamento
const HIT_SHOW := 0.22    # marcador de acerto (X branco)
const KILL_SHOW := 0.6    # marcador de abate (X vermelho, maior)
const AMMO_RADIUS := 26.0       # arco do pente, à direita da mira (px)
const AMMO_SPAN := 80.0         # graus que o arco ocupa
const FREE_FLASH := 0.3   # Cartucheira: piscada dourada das balas que saíram de graça
const FREE_COLOR := Color(1.0, 0.86, 0.35, 1.0)
const AMMO_SEGMENTS_MAX := 24   # acima disso vira barra contínua
const RELOAD_RING := 11.0       # anel da recarga no lugar da mira (px)
const RELOAD_RING_PERFECT := 18.0   # com a Recarga Perfeita: maior, para dar para mirar a faixa
const DAZE_RING := 48.0         # tonto: raio das estrelas em volta da mira (px; o pente fica a 26)
const DAZE_STAR := 13.0         # tonto: tamanho das estrelas da mira (px)
const DOWN_RING := 46.0         # caído: anel do prazo (vermelho) no lugar da mira...
const DOWN_REVIVE_RING := 36.0  # ...e o do reviver (verde) por dentro

var me: Player
var players: Array = []
var teams_on := false
## 2x2: barra do topo com o placar dos times e um cartão por jogador (TeamChip).
var team_bar: Control
var team_scores: Array = [null, null]   # Label do número de cada time
var team_round: Label
var chips: Array = []                   # [Player, cartão, barra de vida ou null]
var spectate_label: Label
var spectate_hint: Label
var spectate_modes: HBoxContainer   # 1a pessoa / 3a pessoa / livre, com a atual acesa
var spectate_view := -1
var spectate_aim := false           # assistindo em primeira pessoa: a mira volta
var death_fx: ColorRect             # morte em câmera lenta (Spectator): tela fria e bordas escuras
## Sem ler a tela (cópia da tela inteira pesa na Intel HD): um véu cinza-azulado por cima,
## mais forte nas bordas, e o preto do corte. Uma chamada de desenho.
const DEATH_FX_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float black = 0.0;
void fragment() {
	float edge = smoothstep(0.3, 0.78, length(UV - vec2(0.5)));
	vec3 tint = mix(vec3(0.42, 0.45, 0.52), vec3(0.03, 0.02, 0.05), edge);
	float a = amount * (0.3 + 0.55 * edge);
	COLOR = vec4(mix(tint, vec3(0.0), black), max(a, black));
}
"""
var dead_view := false
var downed_view := false
var scope: ColorRect      # luneta da Sniper: tela escura com um círculo e a cruz fina
## Luneta num shader só (um retângulo na tela toda): fora do círculo, preto; dentro, a
## cruz fina com um vão no meio e uma borda escura. Uma chamada de desenho, como a mira.
## Domínio do Rei: bordas roxas fechando como um túnel (veil) e o preto da travessia (black).
const REALM_VEIL_SHADER := """
shader_type canvas_item;
uniform float veil = 0.0;
uniform float black = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.6, 1.0);
	float edge = smoothstep(0.85 - veil * 0.6, 0.95, length(d)) * veil;
	COLOR = vec4(mix(vec3(0.22, 0.05, 0.38), vec3(0.0), black), max(edge * 0.95, black));
}
"""
const SCOPE_SHADER := """
shader_type canvas_item;
uniform vec2 screen = vec2(1280.0, 720.0);
void fragment() {
	vec2 p = (UV - 0.5) * screen;
	float r = length(p) / (screen.y * 0.46);
	float outside = smoothstep(0.985, 1.0, r);
	float rim = smoothstep(0.9, 1.0, r) * 0.6;
	float line = (abs(p.x) < 1.0 || abs(p.y) < 1.0) && length(p) > 18.0 ? 0.85 : 0.0;
	float a = max(max(outside, rim), line);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
var reviving_who: Player = null   # parceiro caído que você está revivendo (anel verde na mira)
var down_label: Label

var shield_tint: ColorRect
var damage_fx: DamageFeedback
var blind_tint: ColorRect
var realm_veil: ColorRect   # Domínio do Rei: tela fechando em roxo no puxão e o preto da travessia
var crosshair: Control
var center_label: Label
var toast_label: Label
var score_label: Label     # placar no topo (cada um por si), dentro de score_box
var score_round: Label     # "RODADA 3 DE 5" acima do placar
var score_box: Control
var timer_label: Label     # relógio da rodada no topo (o do layout do modo)
var timer_shown := -1
var toast_box: Control     # aviso rápido ("Fulano escolheu: ...") numa pílula no topo
var overtime: OvertimeBanner   # Prorrogação: contagem e estado, embaixo do aviso rápido
var vitals: Vitals         # canto inferior esquerdo: mestra, vida, escudo e dash
var ammo_box: Control      # canto inferior direito: munição e a arma especial
var ammo_label: Label
var ammo_max: Label
var ammo_sub: Label
var status_row: HBoxContainer   # estados (lento, envenenado...) em selos acima da vida
var card_timers: CardTimers     # esperas das cartas (ícones) acima dos selos
var _status_key := ""
var fps_label: Label
var scoreboard: Scoreboard
var mode := "ffa"
var start_lives := 3
var mode_label: Label
var duel_names: Array = []
var duel_hearts: Array = []
var duel_queue_label: Label
var kill_feed: KillFeed
var chat: ChatBox          # só online
var tab_hint: Label
var round_score := {}
var round_text := ""
var hit_time := 0.0
var hit_size := 1.0
var kill_time := 0.0
var toast_time := 0.0
var ended := false        # fim da partida: só o placar final na tela


func _ready() -> void:
	shield_tint = _rect(Color(0.4, 0.9, 1.0, 0.12))
	damage_fx = DamageFeedback.new()
	add_child(damage_fx)
	blind_tint = _rect(Color(1, 1, 1, 0))
	realm_veil = ColorRect.new()
	realm_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	realm_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var veil_mat := ShaderMaterial.new()
	veil_mat.shader = Shader.new()
	veil_mat.shader.code = REALM_VEIL_SHADER
	realm_veil.material = veil_mat
	realm_veil.visible = false
	add_child(realm_veil)
	scope = ColorRect.new()
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scope_mat := ShaderMaterial.new()
	scope_mat.shader = Shader.new()
	scope_mat.shader.code = SCOPE_SHADER
	scope.material = scope_mat
	scope.visible = false
	add_child(scope)
	death_fx = ColorRect.new()
	death_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var death_mat := ShaderMaterial.new()
	death_mat.shader = Shader.new()
	death_mat.shader.code = DEATH_FX_SHADER
	death_fx.material = death_mat
	death_fx.visible = false
	add_child(death_fx)
	crosshair = Control.new()
	_place(crosshair, Rect2(0.5, 0.5, 0, 0))
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)
	_build_score_box()
	overtime = OvertimeBanner.new()
	add_child(overtime)
	_build_toast()
	center_label = _label("", 46, Rect2(0, 0.15, 1, 0.3))
	center_label.add_theme_font_override("font", Ui.bold())
	tab_hint = _label("", 13, Rect2(0.79, 0.008, 0.2, 0.03), HORIZONTAL_ALIGNMENT_RIGHT)
	tab_hint.add_theme_constant_override("outline_size", 3)
	tab_hint.modulate.a = 0.55
	vitals = Vitals.new()
	_corner(vitals, false, Vector2(28, 26))
	add_child(vitals)
	_build_ammo()
	status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	_corner(status_row, false, Vector2(28, 132))
	add_child(status_row)
	card_timers = CardTimers.new()
	_corner(card_timers, false, Vector2(28, 162))
	add_child(card_timers)
	spectate_label = _label("", 20, Rect2(0.25, 0.79, 0.5, 0.045))
	spectate_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_build_spectate_modes()
	spectate_hint = _label("", 15, Rect2(0.15, 0.895, 0.7, 0.035))
	spectate_hint.modulate.a = 0.8
	down_label = _label("", 26, Rect2(0.2, 0.56, 0.6, 0.1))
	down_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.7))
	mode_label = _label("", 13, Rect2(0.008, 0.008, 0.3, 0.03), HORIZONTAL_ALIGNMENT_LEFT)
	mode_label.add_theme_constant_override("outline_size", 3)
	mode_label.modulate.a = 0.55
	fps_label = _label("", 14, Rect2(0.006, 0.035, 0.1, 0.03), HORIZONTAL_ALIGNMENT_LEFT)
	fps_label.visible = GameState.show_fps
	kill_feed = KillFeed.new()
	_place(kill_feed, Rect2(0.55, 0.045, 0.435, 0.35))
	add_child(kill_feed)
	if Net.online:
		# Chat no canto esquerdo, acima da vida; o fundo só aparece com o campo aberto.
		var holder := PanelContainer.new()
		_place(holder, Rect2(0.012, 0.47, 0.34, 0.33))
		add_child(holder)
		chat = ChatBox.new(true)
		holder.add_child(chat)
	scoreboard = Scoreboard.new()
	add_child(scoreboard)


func setup(p_me: Player, all_players: Array, p_teams := false, p_mode := "ffa", p_lives := 3) -> void:
	me = p_me
	players = all_players
	teams_on = p_teams
	mode = p_mode
	start_lives = p_lives
	mode_label.text = GameModes.label(mode, start_lives)
	me.damaged.connect(_on_me_damaged)
	me.damage_dealt.connect(_on_damage_dealt)
	me.chaos_drawn.connect(func(id): toast("%s: %s" % [CardDB.card_name("caos"), CardDB.card_name(id)]))
	me.unstable_drawn.connect(func(ids): toast(", ".join(ids.map(CardDB.card_name))))
	me.overtime_card.connect(overtime.on_card)
	overtime.me = me
	me.realm_changed.connect(_on_realm_changed)
	vitals.me = me
	scoreboard.setup(me, players)
	kill_feed.me = me
	damage_fx.me = me
	tab_hint.text = tr("[%s] scoreboard and cards") % GameState.key_text("scoreboard")
	if teams_on:
		_build_team_bar()
		score_box.visible = false
		_place_toast(96)
		_place(kill_feed, Rect2(0.55, 0.13, 0.435, 0.35))   # abaixo da barra dos times
	if mode == "duels":
		_build_duel_bar()
		score_box.visible = false
		_place_toast(96)


## Sala de teste: sem placar de rodadas no topo.
func set_practice() -> void:
	mode_label.text = tr("Test room")
	score_box.visible = false


## Duelos, no topo: [nome] [vidas]  x  [vidas] [nome], e embaixo a fila de quem vem depois.
func _build_duel_bar() -> void:
	var row := HBoxContainer.new()
	_place(row, Rect2(0, 0.015, 1, 0))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for side in 2:
		var name_label := _ui_label("", 22, Color.WHITE, true)
		var hearts := LivesIcons.new()
		duel_names.append(name_label)
		duel_hearts.append(hearts)
		if side == 0:
			row.add_child(name_label)
			row.add_child(hearts)
			timer_label = _timer_label(20)
			timer_label.custom_minimum_size.x = 64
			row.add_child(timer_label)
		else:
			row.add_child(hearts)
			row.add_child(name_label)
	duel_queue_label = _label("", 15, Rect2(0, 0.065, 1, 0.035))
	duel_queue_label.modulate.a = 0.75


## pair: nomes dos nós de quem duela; lives: nome -> vidas; queue: nomes na fila.
func set_duel(pair: Array, p_lives: Dictionary, queue: Array) -> void:
	if duel_names.is_empty():
		return
	scoreboard.lives = p_lives.duplicate()
	scoreboard.total_lives = start_lives
	scoreboard.duel_pair = pair.duplicate()
	for side in 2:
		var p: Player = null
		if side < pair.size():
			p = players.filter(func(x): return String(x.name) == pair[side]).front()
		duel_names[side].text = p.player_name if p else ""
		duel_names[side].add_theme_color_override("font_color", p.color.lightened(0.35) if p else Color.WHITE)
		duel_hearts[side].visible = p != null
		if p:
			duel_hearts[side].total = start_lives
			duel_hearts[side].custom_minimum_size = Vector2(start_lives * 20.0, 18.0)
			duel_hearts[side].left = p_lives.get(pair[side], 0)
			duel_hearts[side].queue_redraw()
	var waiting := PackedStringArray()
	for n in queue:
		for x in players:
			if String(x.name) == n:
				waiting.append(x.player_name)
	duel_queue_label.text = tr("Next: %s") % ", ".join(waiting) if not waiting.is_empty() else ""


## Corações das vidas: cheios os que restam, vazios (só contorno) os perdidos.
class LivesIcons extends Control:
	var total := 3
	var left := 3

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		for i in total:
			var c := Vector2(10.0 + i * 20.0, 9.0)
			var full := i < left
			var fill := Color(1.0, 0.3, 0.32) if full else Color(1, 1, 1, 0.18)
			_heart(c, 7.0, Color(0, 0, 0, 0.6), 1.6)
			_heart(c, 7.0, fill, 0.0)

	func _heart(c: Vector2, r: float, color: Color, grow: float) -> void:
		var k := r + grow
		draw_circle(c + Vector2(-k * 0.5, -k * 0.2), k * 0.55, color)
		draw_circle(c + Vector2(k * 0.5, -k * 0.2), k * 0.55, color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 1.02, 0.0), c + Vector2(k * 1.02, 0.0),
			c + Vector2(0.0, k * 1.05)]), color)


## Topo da tela no 2x2: [cartões do seu time] [placar do seu time] RODADA [placar do outro]
## [cartões do outro]. Seu time sempre à esquerda. O parceiro mostra a vida; os
## adversários, só se estão de pé.
func _build_team_bar() -> void:
	var row := HBoxContainer.new()
	_place(row, Rect2(0, 0.012, 1, 0))   # cresce para baixo a partir do topo
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	team_bar = row
	var mine := me.team
	var theirs := 1 - mine
	for p in _team_players(mine):
		row.add_child(_chip(p, true))
	row.add_child(_score_box(mine))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	mid.custom_minimum_size.x = 84
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_round = _ui_label("", 11, Color(1, 1, 1, 0.6), true)
	team_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(team_round)
	timer_label = _timer_label(18)
	mid.add_child(timer_label)
	row.add_child(mid)
	row.add_child(_score_box(theirs))
	for p in _team_players(theirs):
		row.add_child(_chip(p, false))


## Jogadores do time, com você primeiro.
func _team_players(team: int) -> Array:
	var out := players.filter(func(p): return p.team == team)
	out.sort_custom(func(a, b): return a == me and b != me)
	return out


func _score_box(team: int) -> Control:
	var color: Color = GameState.TEAM_COLORS[team][0]
	var box := PanelContainer.new()
	var style := Ui.box(Color(color.darkened(0.55), 0.88), 8, color, 2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(76, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var name_label := _ui_label(GameState.team_name(team).to_upper(), 11, color.lightened(0.45), true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var number := _ui_label("0", 30, Color.WHITE, true)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(number)
	team_scores[team] = number
	return box


func _chip(p: Player, ally: bool) -> Control:
	var box := PanelContainer.new()
	var style := Ui.box(Color(0.05, 0.06, 0.08, 0.72), 6)
	style.border_color = p.color
	style.border_width_bottom = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(118, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var name_label := _ui_label(p.player_name, 14, Color.WHITE, p == me)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	var bar: ProgressBar = null
	if ally:
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		bar.add_theme_stylebox_override("background", Ui.box(Color(1, 1, 1, 0.15), 2))
		bar.add_theme_stylebox_override("fill", Ui.box(p.color.lightened(0.2), 2))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(bar)
	else:
		# Vida do adversário não aparece; o espaço da barra fica para os cartões terem a mesma altura.
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var filler := Control.new()
		filler.custom_minimum_size.y = 4
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(filler)
	chips.append([p, box, bar])
	return box


## Vivo, o cartão fica aceso; fora da rodada, apagado.
func _update_team_bar() -> void:
	for c in chips:
		var p: Player = c[0]
		if p.downed:
			# Caído: pisca, e a barra mostra o prazo que falta.
			c[1].modulate.a = 0.55 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.008))
		else:
			c[1].modulate.a = 1.0 if p.alive else 0.35
		if c[2]:
			c[2].max_value = p.stats["max_health"]
			if p.downed:
				c[2].value = p.stats["max_health"] * p.bleed_timer / maxf(0.01, p.bleed_total)
			else:
				c[2].value = p.health if p.alive else 0.0


func _ui_label(text: String, size: int, color: Color, is_bold := false) -> Label:
	var l := Ui.label(text, size, color, is_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


## Morto assistindo (Spectator): some o que é de quem está vivo (mira, escudo, dash,
## munição, carta mestra); a vida fica, zerada.
func set_dead_view(on: bool) -> void:
	dead_view = on
	crosshair.visible = not on
	_hide_combat(on or downed_view)


## O que só serve a quem está de pé e lutando.
func _hide_combat(on: bool) -> void:
	vitals.combat = not on
	ammo_box.visible = not on
	status_row.visible = not on
	card_timers.visible = not on


## Caído no 2x2: some o que é de luta; a mira vira o anel do prazo e do reviver.
func _update_downed() -> void:
	reviving_who = null
	if me.alive:
		for p in players:
			if p.downed and me.is_ally(p) and p.global_position.distance_to(me.global_position) < Player.REVIVE_RADIUS:
				reviving_who = p
	if reviving_who:
		down_label.text = tr("Reviving %s...") % reviving_who.player_name
		return
	if me.downed != downed_view:
		downed_view = me.downed
		_hide_combat(downed_view or dead_view)
	if downed_view:
		var reviving := me.revive_progress > 0.0
		down_label.text = tr("DOWN   %d s\n%s") % [ceili(me.bleed_timer),
			tr("Reviving...") if reviving else tr("Your teammate revives you by staying close for %d s") % roundi(Player.REVIVE_TIME)]
	else:
		down_label.text = ""


## Morto assistindo: quem a câmera segue (ou "Câmera livre") e as teclas ("" esconde).
## view: modo aceso na fileira (Spectator.View; -1 esconde a fileira).
func set_spectating(text: String, hint := "", view := -1) -> void:
	if spectate_label.text != text:
		spectate_label.text = text
	if spectate_hint.text != hint:
		spectate_hint.text = hint
	if view == spectate_view:
		return
	spectate_view = view
	spectate_modes.visible = view >= 0
	for k in spectate_modes.get_child_count():
		var chip: PanelContainer = spectate_modes.get_child(k)
		var on := k == view
		chip.add_theme_stylebox_override("panel", _mode_style(on))
		var l: Label = chip.get_child(0)
		l.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1) if on else Ui.MUTED)


## amount: véu da morte em câmera lenta (0 a 1); black: preto do corte para a outra câmera.
func set_death_fx(amount: float, black: float) -> void:
	var on := amount > 0.0 or black > 0.0
	death_fx.visible = on
	if on:
		var mat: ShaderMaterial = death_fx.material
		mat.set_shader_parameter("amount", amount)
		mat.set_shader_parameter("black", black)


## Fileira dos modos de câmera de quem está morto, embaixo do nome de quem se assiste.
func _build_spectate_modes() -> void:
	spectate_modes = HBoxContainer.new()
	_place(spectate_modes, Rect2(0, 0.845, 1, 0.04))
	spectate_modes.alignment = BoxContainer.ALIGNMENT_CENTER
	spectate_modes.add_theme_constant_override("separation", 6)
	spectate_modes.visible = false
	add_child(spectate_modes)
	for title in ["1st person", "3rd person", "Free"]:   # i18n
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", _mode_style(false))
		var l := _ui_label(tr(title), 14, Ui.MUTED, true)
		l.add_theme_constant_override("outline_size", 0)
		chip.add_child(l)
		spectate_modes.add_child(chip)


func _mode_style(on: bool) -> StyleBoxFlat:
	var s := Ui.box(Color(0.85, 0.9, 1.0, 0.92) if on else Color(0, 0, 0, 0.45), 6)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


func _on_me_damaged(amount: float, from: Player) -> void:
	damage_fx.hit(amount, from)


## O X cresce com o dano do acerto (vários no mesmo quadro, como na escopeta, somam).
func _on_damage_dealt(amount: float, lethal: bool) -> void:
	var stacked := amount + (hit_size * float(Player.BASE_STATS["damage"]) if hit_time >= HIT_SHOW - 0.02 else 0.0)
	hit_size = clampf(stacked / float(Player.BASE_STATS["damage"]), 0.8, 1.6)
	hit_time = HIT_SHOW
	if lethal:
		kill_time = KILL_SHOW


## Mira: quatro traços e um ponto. Acerto: X branco que surge grande e encolhe.
## Abate: X vermelho maior, que fica mais tempo.
## Pente (2026-10-05, como no Furor): arco fino à direita da mira, um segmento por bala; os
## gastos apagam de cima para baixo e a última bala fica laranja. Recarregando, os traços
## somem e um anel se fecha no tempo da recarga; fechou, a mira volta.
##
## Desempenho (2026-10-05): na Intel HD (OpenGL via ANGLE) cada chamada draw_* custa de 0,3
## a 0,9 ms por quadro, então a mira junta tudo em poucas chamadas draw_multiline: uma
## para as sombras e outra para as cores. Com um draw_arc por bala, o pente de 14 da
## Metralhadora custava ~26 ms por quadro (medido com janela, _teste/).
func _draw_crosshair() -> void:
	var white := Color(1, 1, 1, 0.9)
	if me != null and me.downed:
		_draw_down_rings()
		return
	if reviving_who:
		_draw_revive_ring()
	var reloading := me != null and me.alive and me.reload_timer > 0.0 and me.bazooka_timer <= 0.0
	if reloading:
		var total: float = maxf(0.01, me.stats["reload_time"])
		var done := clampf(1.0 - me.reload_timer / total, 0.0, 1.0)
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var cut := -PI / 2.0 + TAU * done
		# Recarga Perfeita: a faixa dourada (some depois da tentativa).
		var band: bool = me.stats["perfect_reload"] > 0 and not me.perfect_tried
		var gold := Player.PERFECT_COLOR
		var ring := RELOAD_RING_PERFECT if me.stats["perfect_reload"] > 0 else RELOAD_RING
		# Anel inteiro em 40 pedaços: até o corte branco (já recarregado), depois apagado.
		for k in 40:
			var a0 := -PI / 2.0 + TAU * k / 40.0
			var a1 := -PI / 2.0 + TAU * (k + 1) / 40.0
			var mid := (k + 0.5) / 40.0
			var in_band := band and mid > Player.PERFECT_START and mid < Player.PERFECT_END
			var full := gold if in_band else white
			var dim := Color(gold, 0.6) if in_band else Color(1, 1, 1, 0.22)
			if a0 < cut and a1 > cut:
				_arc_piece(pts, cols, ring, a0, cut, full)
				_arc_piece(pts, cols, ring, cut, a1, dim)
			else:
				_arc_piece(pts, cols, ring, a0, a1, full if a1 <= cut else dim)
		crosshair.draw_multiline(pts, Color(0, 0, 0, 0.45), 4.5, true)
		crosshair.draw_multiline_colors(pts, cols, 2.5, true)
	else:
		var gap := 6.0 + (4.0 if me and me.recoil > 0.2 else 0.0)
		var ticks := PackedVector2Array()
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			ticks.append(d * gap)
			ticks.append(d * (gap + 8.0))
		crosshair.draw_multiline(ticks, Color.BLACK, 4.0)
		crosshair.draw_multiline(ticks, white, 2.0)
		if me != null and me.alive:
			_draw_ammo_arc()
			_draw_boot_fuel()
			_draw_mech_charge()
			_draw_mech_fuel()
	crosshair.draw_circle(Vector2.ZERO, 1.6, white)
	if me != null and me.daze_fx > 0.0:
		_draw_daze_stars()
	var color := Color.WHITE
	var size := 0.0
	var t := 0.0
	if kill_time > 0.0:
		t = kill_time / KILL_SHOW
		color = Color(1, 0.2, 0.2)
		size = 1.5
	elif hit_time > 0.0:
		t = hit_time / HIT_SHOW
		size = hit_size
	if size > 0.0:
		var pop := size * (1.0 + 0.35 * t * t)
		color.a = clampf(t * 2.5, 0.0, 1.0)
		var shadow := Color(0, 0, 0, color.a * 0.7)
		var x := PackedVector2Array()
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			x.append(d.normalized() * 8.0 * pop)
			x.append(d.normalized() * 16.0 * pop)
		crosshair.draw_multiline(x, shadow, 5.0)
		crosshair.draw_multiline(x, color, 2.5)


## Tonto: 3 estrelas (só o contorno, numa chamada de sombra e outra de cor) girando em volta
## da mira; encolhem no fim. Na cabeça, os outros veem as estrelas de verdade (DazeStars).
func _draw_daze_stars() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var k := clampf(me.daze_fx / DazeStars.SHRINK_TIME, 0.0, 1.0)
	var pts := PackedVector2Array()
	for i in 3:
		var a := t * 4.0 + TAU * i / 3.0
		var center := Vector2(cos(a), sin(a)) * DAZE_RING
		var spin := t * 3.0 + i
		var tip := PackedVector2Array()
		for j in 10:
			var r := DAZE_STAR * k * (1.0 if j % 2 == 0 else 0.45)
			var b := spin + TAU * j / 10.0
			tip.append(center + Vector2(cos(b), sin(b)) * r)
		for j in 10:
			pts.append(tip[j])
			pts.append(tip[(j + 1) % 10])
	crosshair.draw_multiline(pts, Color(0, 0, 0, 0.5), 5.5, true)
	crosshair.draw_multiline(pts, Color(1.0, 0.85, 0.2), 3.0, true)


## Bota Foguete: barra fina sob a mira, só enquanto o jato não está cheio.
func _draw_boot_fuel() -> void:
	if me.stats["rocket_boots"] <= 0 or me.boot_fuel >= Player.BOOT_FUEL:
		return
	var w := 64.0
	var top := Vector2(-w / 2.0, 30.0)
	crosshair.draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.5))
	crosshair.draw_rect(Rect2(top, Vector2(w * me.boot_fuel / Player.BOOT_FUEL, 5)), Color(1.0, 0.6, 0.25, 0.95))


## Mecha: barra do salto carregado sob a mira, enchendo enquanto segura o pulo (aço até o
## toque virar salto, laranja quando cheia).
func _draw_mech_charge() -> void:
	if me.mech_charge < 0.0:
		return
	var t := clampf(me.mech_charge / Player.MECH_CHARGE_TIME, 0.0, 1.0)
	var w := 64.0
	var top := Vector2(-w / 2.0, 38.0)
	var col := Player.MECH_JET_COLOR if t >= 1.0 else Player.MECH_COLOR
	crosshair.draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.5))
	crosshair.draw_rect(Rect2(top, Vector2(w * t, 5)), Color(col, 0.95))


## Mecha: barra da propulsão (segurar o dash), só enquanto não está cheia.
func _draw_mech_fuel() -> void:
	if me.mech_state != 2 or me.mech_fuel >= Player.MECH_THRUST_FUEL:
		return
	var w := 64.0
	var top := Vector2(-w / 2.0, 46.0)
	crosshair.draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.5))
	crosshair.draw_rect(Rect2(top, Vector2(w * me.mech_fuel / Player.MECH_THRUST_FUEL, 5)), Color(Player.MECH_JET_COLOR, 0.95))


## Caído: anel vermelho do prazo (esvazia) e, por dentro, o verde do reviver (enche). Duas
## chamadas de desenho para tudo, como a mira.
func _draw_down_rings() -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var bleed := clampf(me.bleed_timer / maxf(0.01, me.bleed_total), 0.0, 1.0)
	var revive := clampf(me.revive_progress / Player.REVIVE_TIME, 0.0, 1.0)
	for k in 48:
		var f0 := float(k) / 48.0
		var f1 := float(k + 1) / 48.0
		var a0 := -PI / 2.0 + TAU * f0
		var a1 := -PI / 2.0 + TAU * f1
		_arc_piece(pts, cols, DOWN_RING, a0, a1, Color(1.0, 0.3, 0.25, 0.95) if f1 <= bleed + 0.001 else Color(1, 1, 1, 0.15))
		if revive > 0.0:
			_arc_piece(pts, cols, DOWN_REVIVE_RING, a0, a1, Color(0.4, 1.0, 0.5, 0.95) if f1 <= revive + 0.001 else Color(1, 1, 1, 0.12))
	crosshair.draw_multiline(pts, Color(0, 0, 0, 0.45), 6.0, true)
	crosshair.draw_multiline_colors(pts, cols, 4.0, true)


## Revivendo o parceiro: anel verde em volta da mira, enchendo com o progresso dele.
func _draw_revive_ring() -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var done := clampf(reviving_who.revive_progress / Player.REVIVE_TIME, 0.0, 1.0)
	for k in 40:
		var f1 := float(k + 1) / 40.0
		_arc_piece(pts, cols, DOWN_REVIVE_RING, -PI / 2.0 + TAU * k / 40.0, -PI / 2.0 + TAU * f1,
			Color(0.4, 1.0, 0.5, 0.95) if f1 <= done + 0.001 else Color(1, 1, 1, 0.15))
	crosshair.draw_multiline(pts, Color(0, 0, 0, 0.45), 6.0, true)
	crosshair.draw_multiline_colors(pts, cols, 4.0, true)


## Arco do pente: até AMMO_SEGMENTS_MAX balas, um segmento cada; mais que isso, uma barra
## contínua que esvazia. Na Bazuca conta os foguetes; tiros perfurantes saem roxos.
func _draw_ammo_arc() -> void:
	var count: int = me.stats["mag_size"]
	var left: int = me.ammo
	if me.bazooka_timer > 0.0:
		count = Player.BAZOOKA_ROCKETS
		left = me.rockets_left
	elif me.sniper_timer > 0.0:
		count = 1
		left = me.sniper_shots
	elif me.sword_timer > 0.0:
		return   # a espada não tem pente
	if count <= 0:
		return
	var span := deg_to_rad(AMMO_SPAN)
	var top := -span / 2.0
	var shadow := Color(0, 0, 0, 0.45)
	var empty := Color(1, 1, 1, 0.18)
	var full := Color(1, 1, 1, 0.85)
	var last := Color(1.0, 0.62, 0.25, 0.95)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	if count > AMMO_SEGMENTS_MAX:
		# Barra contínua em 24 pedaços: apagada acima do corte, cheia abaixo.
		var cut := top + span * (1.0 - float(left) / count)
		var bar := last if left == 1 else full
		for k in 24:
			var a0 := top + span * k / 24.0
			var a1 := top + span * (k + 1) / 24.0
			if left > 0 and a0 < cut and a1 > cut:
				_arc_piece(pts, cols, AMMO_RADIUS, a0, cut, empty)
				_arc_piece(pts, cols, AMMO_RADIUS, cut, a1, bar)
			else:
				_arc_piece(pts, cols, AMMO_RADIUS, a0, a1, bar if left > 0 and a0 >= cut else empty)
		crosshair.draw_multiline(pts, shadow, 5.0, true)
		crosshair.draw_multiline_colors(pts, cols, 3.0, true)
		return
	var gap := deg_to_rad(clampf(40.0 / count, 2.5, 9.0))
	var seg := (span - gap * (count - 1)) / count
	# Cartucheira: as balas que saíram de graça no último tiro (as de cima das que sobram)
	# acendem em dourado e voltam ao branco em FREE_FLASH segundos.
	var free_k := 1.0 - (Time.get_ticks_msec() - me.free_ammo_flash) / (FREE_FLASH * 1000.0)
	for i in count:
		# i = 0 é o de cima: some primeiro. Quem sobra fica embaixo.
		var a := top + i * (seg + gap)
		var has := i >= count - left
		var c := empty
		if has:
			c = last if left == 1 and me.bazooka_timer <= 0.0 else full
			if me.pierce_left > 0 and i - (count - left) < me.pierce_left and me.bazooka_timer <= 0.0:
				c = Color(Bullet.PIERCE_COLOR, 0.95)
			elif me.meteor_left > 0 and i - (count - left) < me.meteor_left and me.bazooka_timer <= 0.0:
				c = Color(MeteorStrike.COLOR, 0.95)
			elif free_k > 0.0 and i - (count - left) < me.free_ammo_shown and me.bazooka_timer <= 0.0 \
					and me.sniper_timer <= 0.0:
				c = c.lerp(FREE_COLOR, free_k)
		for k in 3:
			_arc_piece(pts, cols, AMMO_RADIUS, a + seg * k / 3.0, a + seg * (k + 1) / 3.0, c)
	crosshair.draw_multiline(pts, shadow, 5.0, true)
	crosshair.draw_multiline_colors(pts, cols, 3.0, true)


## Um pedaço reto de arco (de a0 a a1, em radianos) para draw_multiline.
func _arc_piece(pts: PackedVector2Array, cols: PackedColorArray, radius: float, a0: float, a1: float, c: Color) -> void:
	pts.append(Vector2.from_angle(a0) * radius)
	pts.append(Vector2.from_angle(a1) * radius)
	cols.append(c)


func _process(delta: float) -> void:
	Effects.keep_states(get_viewport().get_camera_3d())   # sem isso cada explosão trava (Effects)
	if Prof.enabled:
		var t := Time.get_ticks_usec()
		_frame_step(delta)
		Prof.lap("HUD: quadro", t)
	else:
		_frame_step(delta)


func _frame_step(delta: float) -> void:
	if me == null or ended:
		return
	fps_label.visible = GameState.show_fps   # pode mudar no menu de pausa
	vitals.tick(delta)
	scope.visible = me.scoping
	if scope.visible:
		(scope.material as ShaderMaterial).set_shader_parameter("screen", scope.size)
	crosshair.visible = spectate_aim if dead_view else (not me.scoping and me.ice_timer <= 0.0)
	_update_ammo()
	shield_tint.visible = me.alive and me.is_shielding()
	_update_downed()
	if team_bar:
		_update_team_bar()
	_update_timer()
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	_update_status()
	card_timers.update_from(me)
	blind_tint.color.a = clampf(me.blind_timer / 0.3, 0.0, 1.0) * 0.97
	blind_tint.visible = blind_tint.color.a > 0.0   # camada de tela cheia: só quando cega
	_update_realm_veil()
	var chain := me.realm_threat()
	damage_fx.threat = chain.rchain_tip if chain else Vector3.INF
	hit_time = maxf(0.0, hit_time - delta)
	kill_time = maxf(0.0, kill_time - delta)
	crosshair.queue_redraw()
	toast_time -= delta
	toast_box.modulate.a = clampf(toast_time * 2.0, 0.0, 1.0)


## Munição no canto direito: número grande e o pente; embaixo, a arma especial ou o estado.
func _update_ammo() -> void:
	var big := str(me.ammo)
	var small := "/ %d" % me.stats["mag_size"]
	var sub := ""
	var sub_color := Ui.MUTED
	if me.sword_timer > 0.0:
		big = ["→", "←", "↑"][me.combo_step]
		small = ""
		sub = "%s  %.0f s" % [CardDB.card_name("espada").to_upper(), ceilf(me.sword_timer)]
		sub_color = Ui.ACCENT
	elif me.sniper_timer > 0.0:
		big = str(me.sniper_shots)
		small = "/ 1"
		sub = "%s  %.0f s" % [CardDB.card_name("sniper").to_upper(), ceilf(me.sniper_timer)]
		sub_color = Ui.ACCENT
	elif me.bazooka_timer > 0.0:
		big = str(me.rockets_left)
		small = "/ %d" % Player.BAZOOKA_ROCKETS
		sub = "%s  %.0f s" % [CardDB.card_name("bazuca").to_upper(), ceilf(me.bazooka_timer)]
		sub_color = Ui.ACCENT
	elif me.reload_timer > 0.0:
		sub = tr("RELOADING")
		sub_color = Color(1, 1, 1, 0.75)
	elif me.perfect_mag:
		sub = CardDB.card_name("recarga_perfeita").to_upper() + " +15%"
		sub_color = Player.PERFECT_COLOR
	if me.pierce_left > 0 and me.bazooka_timer <= 0.0:
		sub = ("%s  ·  " % sub if sub != "" else "") + tr("PIERCING %d") % me.pierce_left
	if me.meteor_left > 0 and me.bazooka_timer <= 0.0:
		sub = ("%s  ·  " % sub if sub != "" else "") + tr("METEORS %d  %.0f s") % [me.meteor_left, ceilf(me.meteor_window)]
		sub_color = MeteorStrike.COLOR
		sub_color = Bullet.PIERCE_COLOR.lerp(Color.WHITE, 0.3)
	ammo_label.text = big
	ammo_max.text = small
	ammo_sub.text = sub
	ammo_sub.add_theme_color_override("font_color", sub_color)
	var empty: bool = me.ammo <= 1 and me.reload_timer <= 0.0 and me.bazooka_timer <= 0.0 \
		and me.sniper_timer <= 0.0 and me.sword_timer <= 0.0
	ammo_label.add_theme_color_override("font_color", Ui.ACCENT if empty else Color.WHITE)


## Tela cheia só quando há puxão ou chegada. Puxão: as bordas fecham e, nos últimos 0,15 s,
## escurece tudo; chegada: clareia em REALM_FADE_IN.
func _update_realm_veil() -> void:
	var veil := 0.0
	var black := 0.0
	if me.realm_pull > 0.0:
		veil = 1.0 - me.realm_pull / Player.REALM_PULL
		black = clampf((0.15 - me.realm_pull) / 0.15, 0.0, 1.0)
	elif me.realm_fade > 0.0:
		black = me.realm_fade / Player.REALM_FADE_IN
		veil = black * 0.6
	realm_veil.visible = veil > 0.0 or black > 0.0
	if realm_veil.visible:
		var mat := realm_veil.material as ShaderMaterial
		mat.set_shader_parameter("veil", veil)
		mat.set_shader_parameter("black", black)


## Estados do jogador em selos acima da vida; só refaz quando a lista muda.
func _update_status() -> void:
	var items := []
	# Selos com nome de carta usam CardDB.card_name (já traduzido); os outros, tr(). Só os
	# selos ligados custam uma tradução por quadro.
	if me.revives_left > 0:
		items.append(["%s %d" % [_card_tag("fenix"), me.revives_left], Color(1.0, 0.6, 0.25)])
	if me.spawn_protect > 0.0:
		items.append([tr("PROTECTED %.1f  ·  attacking ends it") % me.spawn_protect, Player.PROTECT_COLOR])
	if me.slow_timer > 0.0:
		items.append([tr("SLOWED"), Color(0.55, 0.8, 1.0)])
	if not me.poisons.is_empty():
		items.append([tr("POISONED"), Color(0.55, 0.95, 0.35)])
	# Congelamento (2026-10-15, pedido do usuário): floco de gelo e o contador, sem mais nada.
	if me.frost_freeze > 0.0 and me.ice_timer <= 0.0:
		items.append([tr("FROZEN"), Player.FROST_COLOR, FROST_ICON])
	elif me.frost_layers > 0:
		items.append(["%d/%d" % [me.frost_layers, Player.FROST_MAX], Player.FROST_COLOR, FROST_ICON])
	if me.silence_timer > 0.0:
		items.append([tr("SHIELD BLOCKED"), Ui.DANGER])
	if me.is_too_high():
		items.append([tr("TOO HIGH  ·  get down  ·  damage in %.1f") % me.sky_timer, Player.SKY_COLOR])
	if me.zone_out:
		items.append([tr("OUTSIDE THE ARENA  ·  damage in %.1f") % me.zone_timer, Ui.DANGER])
	if me.is_hidden():
		items.append([tr("VISIBLE") if me.camo_blink() else (tr("INVISIBLE  ·  failing") if me.is_camo_tired() else tr("INVISIBLE")), Color(0.75, 0.6, 1.0)])
	if me.ambush_timer > 0.0:
		items.append([tr("AMBUSH %.1f") % me.ambush_timer, Color(0.8, 0.55, 1.0)])
	if me.beam_charge > 0.0:
		items.append([tr("CHARGING %.1f") % me.beam_charge, Player.BEAM_COLOR])
	elif me.beam_timer > 0.0:
		items.append([tr("CANNON %.1f") % me.beam_timer, Player.BEAM_COLOR])
	if me.hook_state == 3:
		items.append([tr("HOLDING  ·  click to throw"), Player.HOOK_COLOR])
	if me.hooked_by:
		items.append([tr("HOOKED"), Ui.DANGER])
	if me.ride_timer > 0.0:
		items.append([tr("%s %.1f  ·  [%s] jump off") % [_card_tag("foguete"), me.ride_timer, GameState.key_text("master")], Player.ROCKET_COLOR])
	if is_instance_valid(me.clone):
		items.append([tr("%s %.1f  ·  [%s] swap places") % [_card_tag("clone"), me.clone.life, GameState.key_text("master")], Player.CLONE_COLOR.lightened(0.3)])
	if me.mech_state == 1:
		items.append([tr("BOARDING THE MECH %.1f") % me.mech_timer, Player.MECH_COLOR.lightened(0.25)])
	elif me.mech_state == 2:
		items.append([tr("%s %.1f  ·  [%s] exit and explode") % [_card_tag("mecha"), me.mech_timer, GameState.key_text("master")], Player.MECH_COLOR.lightened(0.25)])
	if me.grapple_state == 2:
		items.append([tr("SWINGING  ·  release [%s] to fly off") % GameState.key_text("master"), Player.GRAPPLE_COLOR])
	elif me.grapple_state == 3:
		items.append([tr("HANGING %.1f  ·  [%s] to jump") % [me.grapple_timer, GameState.key_text("jump")], Player.GRAPPLE_COLOR])
	elif me.grapple_state == 4:
		items.append([tr("SUCTION KICK"), Player.GRAPPLE_COLOR])
	if me.plat_chain > 0.0:
		items.append([tr("PLATFORMS %d  ·  %.1f s") % [me.plat_left, me.plat_chain], SkyPlatform.READY_COLOR])
	if me.daze_timer > 0.0:
		items.append([tr("DIZZY %.1f") % me.daze_timer, Player.SLAP_COLOR])
	# Efeitos bons com duração (2026-10-11, pedido do usuário: antes não apareciam).
	if me.bloodlust_timer > 0.0:
		items.append(["%s +%d%%  %.1f" % [_card_tag("sede_de_sangue"), roundi(me.stats["bloodlust"] * 100.0), me.bloodlust_timer], CardDB.CATEGORY_COLORS["Corpo"]])
	if me.haste_timer > 0.0:
		items.append(["%s +%d%%  %.1f" % [_card_tag("passo_ligeiro"), roundi(me.stats["shield_haste"] * 100.0), me.haste_timer], CardDB.CATEGORY_COLORS["Escudo"]])
	if me.parkour_timer > 0.0 and me.stats["parkour"] > 0:
		items.append(["%s +%d%%  %.1f" % [_card_tag("parkour"), roundi(Player.PARKOUR_SPEED * me.stats["parkour"] * 100.0), me.parkour_timer], CardDB.CATEGORY_COLORS["Movimento"]])
	if me.strike_timer > 0.0:
		items.append(["%s +%d%%  %.1f" % [_card_tag("arrancada"), roundi(Player.STRIKE_DAMAGE * 100.0), me.strike_timer], CardDB.CATEGORY_COLORS["Movimento"]])
	if me.feast_stacks > 0:
		items.append([tr("HUNGER %d/%d  +%d%% DAMAGE") % [me.feast_stacks, Player.FEAST_MAX, roundi(Player.FEAST_DAMAGE * me.feast_stacks * 100.0)], CardDB.CATEGORY_COLORS["Corpo"]])
	if me.pressure_timer > 0.0:
		items.append(["%s +%d%%  %.1f" % [_card_tag("pressao"), roundi(Player.PRESSURE_SPEED * 100.0), me.pressure_timer], CardDB.CATEGORY_COLORS["Movimento"]])
	if me.tough_timer > 0.0:
		items.append(["%s %.1f" % [_card_tag("casca_dura"), me.tough_timer], Player.TOUGH_COLOR])
	if me.ice_timer > 0.0:
		items.append([tr("FROZEN %.1f") % me.ice_timer, Player.ICE_COLOR])
	if me.speed_orb_timer > 0.0:
		items.append([tr("SPEED +%d%%  %.1f") % [roundi(Player.SPEED_ORB * 100.0), me.speed_orb_timer], Pickup.COLORS[Pickup.Kind.SPEED]])
	if me.shrink_timer > 0.0:
		items.append([tr("%s %.1f  ·  [%s] grow back") % [_card_tag("formiga"), me.shrink_timer, GameState.key_text("master")], Color(0.78, 0.64, 1.0)])
	if me.air_bonus() > 0.0:
		items.append([tr("IN THE AIR +%d%% DAMAGE") % roundi(me.air_bonus() * 100.0), Ui.ACCENT])
	if me.swing_timer > 0.0:
		items.append([tr("MOMENTUM +%d%% DAMAGE  %.1f") % [roundi(Player.GRAPPLE_SWING_DAMAGE * 100.0), me.swing_timer], Player.GRAPPLE_COLOR])
	if me.rain_aim == 1:
		items.append([tr("MISSILE RAIN: CLICK TO MARK THE SPOT  %.1f") % me.rain_aim_time, MissileRain.COLOR])
	elif me.rain_aim == 2:
		items.append([tr("MISSILE RAIN: CLICK TO SET THE DIRECTION  %.1f") % me.rain_aim_time, MissileRain.COLOR])
	elif is_instance_valid(me.rain) and me.rain.owner_player == me and not me.rain.big_used:
		items.append([tr("MISSILE RAIN  ·  [%s] big missile") % GameState.key_text("master"), MissileRain.COLOR])
	# Velocidade Letal em degraus de 5% (o selo só é refeito quando o texto muda) e Vulto.
	var fast := snappedf(me.speed_bonus() * 100.0, 5.0)
	if fast > 0.0:
		items.append([tr("SPEED +%d%% DAMAGE") % roundi(fast), CardDB.CATEGORY_COLORS["Movimento"]])
	if me.skin_stacks > 0:
		items.append([tr("%s -%d PER HIT") % [_card_tag("couro_grosso"), me.skin_stacks], CardDB.CATEGORY_COLORS["Corpo"]])
	if me.is_surviving():
		items.append([tr("%s +%d%% SPEED") % [_card_tag("instinto"), roundi(me.stats["survival_speed"] * 100.0)], CardDB.CATEGORY_COLORS["Corpo"]])
	if me.stats["revenge"] > 0.0 and me.revenge_target != "":
		var foe := me.get_parent().get_node_or_null(me.revenge_target) as Player
		if foe and foe.alive:
			items.append(["%s: %s +%d%%" % [_card_tag("vinganca"), foe.player_name, roundi(me.stats["revenge"] * 100.0)], CardDB.CATEGORY_COLORS["Corpo"]])
	if me.is_still_aiming():
		items.append([tr("%s +%d%% DAMAGE") % [_card_tag("sangue_frio"), roundi(Player.STILL_DAMAGE * me.stats["still_aim"] * 100.0)], CardDB.CATEGORY_COLORS["Arma"]])
	if me.bullet_taken_mult() < 1.0:
		items.append([tr("%s -%d%% DAMAGE") % [_card_tag("vulto"), roundi((1.0 - me.bullet_taken_mult()) * 100.0)], CardDB.CATEGORY_COLORS["Movimento"]])
	if me.realm_threat():
		items.append([tr("SHADOW CHAIN  ·  [%s] to block") % GameState.key_text("shield"), KingRealm.MARK_COLOR])
	if me.realm > 0:
		var foe_name: String = me.realm_partner.player_name if is_instance_valid(me.realm_partner) else ""
		if me.realm_king:
			items.append([tr("%s +%d%% DAMAGE  ·  %.1f") % [_card_tag("dominio_do_rei"), roundi(me.realm_bonus() * 100.0), me.realm_timer], KingRealm.MARK_COLOR])
		else:
			items.append([tr("IN %s'S REALM -%d%% DAMAGE  ·  %.1f") % [foe_name.to_upper(), roundi(me.realm_weaken() * 100.0), me.realm_timer], Ui.DANGER])
	elif me.realm_bonus_timer > 0.0:
		items.append([tr("REALM +%d%% DAMAGE  %.1f") % [roundi(me.realm_bonus() * 100.0), me.realm_bonus_timer], KingRealm.MARK_COLOR])
	if me.last_stand_timer > 0.0:
		items.append([tr("%s %.1f: GET A KILL") % [_card_tag("ultimo_suspiro"), me.last_stand_timer], Ui.DANGER])
	var key := str(items)
	if key == _status_key:
		return
	_status_key = key
	for c in status_row.get_children():
		c.queue_free()
	for it in items:
		status_row.add_child(_status_chip(it[0], it[1], it[2] if it.size() > 2 else null))


## Nome da carta em maiúsculas, no idioma do jogo, para os selos.
func _card_tag(id: String) -> String:
	return CardDB.card_name(id).to_upper()


## Domínio do Rei: aviso ao entrar e ao vencer (o tempo e o bônus ficam no selo).
func _on_realm_changed(entered: bool, won: bool) -> void:
	if entered:
		if me.realm_king:
			toast(tr("%s: just you two for %d s") % [CardDB.card_name("dominio_do_rei"), int(Player.REALM_TIME)])
		elif is_instance_valid(me.realm_partner):
			toast(tr("%s pulled you into %s") % [me.realm_partner.player_name, CardDB.card_name("dominio_do_rei")])
	elif won:
		toast(tr("You won the Realm") + (tr(": +%d%% damage for %d s") % [roundi(me.realm_bonus() * 100.0), int(Player.REALM_WIN_TIME)] if me.realm_king else ""))


## Selo de estado: texto em negrito na cor, fundo escuro e um traço da cor à esquerda.
## Com ícone (icon): o desenho na cor antes do texto.
func _status_chip(text: String, color: Color, icon: Texture2D = null) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_font_override("font", Ui.bold())
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.2))
	var box := Ui.box(Color(0.05, 0.06, 0.08, 0.8), 6)
	box.border_color = color
	box.border_width_left = 3
	box.content_margin_left = 9
	box.content_margin_right = 9
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon == null:
		l.add_theme_stylebox_override("normal", box)
		return l
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.texture = icon
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(14, 14)
	pic.modulate = color.lerp(Color.WHITE, 0.2)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	row.add_child(l)
	panel.add_child(row)
	return panel


func set_score(p_score: Dictionary, round_num: int, block_end: int) -> void:
	round_score = p_score
	round_text = tr("Round %d of %d") % [round_num, block_end]
	score_label.text = score_text(round_score)
	score_round.text = tr("ROUND %d OF %d") % [round_num, block_end]
	if team_bar:
		for t in 2:
			team_scores[t].text = str(_team_score(t))
		team_round.text = tr("ROUND %d / %d") % [round_num, block_end]
	_sync_scoreboard()


## Abates, assistências e mortes: nome do nó -> [a, as, m].
func set_kda(kda: Dictionary) -> void:
	scoreboard.kda = kda
	_sync_scoreboard()


func _sync_scoreboard() -> void:
	scoreboard.score = round_score
	scoreboard.round_text = round_text
	scoreboard.rebuild()


func show_scoreboard(on: bool) -> void:
	for l in [center_label, toast_box, score_box, spectate_label, overtime]:
		l.self_modulate.a = 0.0 if on else 1.0   # o placar já mostra isso; texto solto atrapalha
	spectate_modes.modulate.a = 0.0 if on else 1.0   # self_modulate não passa para os filhos
	if team_bar:
		team_bar.visible = not on
	if on:
		_sync_scoreboard()
		scoreboard.open()
	else:
		scoreboard.close()


## "Você 3  x  2 Bot" no 1x1; "Você 3  |  Bot 1: 2  |  Bot 2: 1" com três;
## "Azul 3  x  2 Vermelho" no 2x2, com o seu time primeiro.
func score_text(score: Dictionary) -> String:
	if teams_on:
		var mine := me.team
		return "%s %d  x  %d %s" % [GameState.team_name(mine), _team_score(mine, score),
			_team_score(1 - mine, score), GameState.team_name(1 - mine)]
	if players.size() == 2:
		var other: Player = players[1] if players[0] == me else players[0]
		return "%s %d  x  %d %s" % [me.player_name, score[String(me.name)], score[String(other.name)], other.player_name]
	var parts := PackedStringArray()
	for p in players:
		parts.append("%s: %d" % [p.player_name, score[String(p.name)]])
	return "  |  ".join(parts)


func _team_score(team: int, score := round_score) -> int:
	for p in players:
		if p.team == team:
			return score.get(String(p.name), 0)
	return 0


func show_center(text: String) -> void:
	center_label.text = text


func toast(text: String) -> void:
	toast_label.text = text
	toast_time = 3.0


## Relógio da rodada (2026-10-12, pedido do usuário, como no Furor): o tempo de luta da
## partida (o mesmo da prorrogação: parado na contagem e na pausa contra bots). Laranja a
## partir das cartas extras, vermelho quando a arena fecha. O texto só muda a cada segundo.
func _timer_label(size: int) -> Label:
	var l := _ui_label("0:00", size, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	return l


func _update_timer() -> void:
	var sec := int(overtime.time)
	if timer_label == null or sec == timer_shown:
		return
	timer_shown = sec
	timer_label.text = "%d:%02d" % [sec / 60, sec % 60]
	var color := Color.WHITE
	if sec >= int(Overtime.ZONE_AT):
		color = Ui.DANGER
	elif sec >= int(Overtime.CARDS_AT):
		color = Ui.WARN
	timer_label.add_theme_color_override("font_color", color)


## Placar do topo (cada um por si): pílula com a rodada pequena em cima e o placar.
func _build_score_box() -> void:
	var holder := CenterContainer.new()
	_place(holder, Rect2(0, 0, 1, 0))
	holder.offset_top = 12
	add_child(holder)
	score_box = holder
	var pill := PanelContainer.new()
	var style := Ui.box(Color(0.05, 0.06, 0.08, 0.72), 10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)
	var row := Ui.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	timer_label = _timer_label(22)
	row.add_child(timer_label)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.18)
	bar.custom_minimum_size = Vector2(1, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var col := Ui.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	score_round = _ui_label("", 11, Color(1, 1, 1, 0.55), true)
	score_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(score_round)
	score_label = _ui_label("", 20, Color.WHITE, true)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(score_label)


func _build_toast() -> void:
	var holder := CenterContainer.new()
	add_child(holder)
	toast_box = holder
	_place_toast(78)
	var pill := PanelContainer.new()
	var style := Ui.box(Color(0.05, 0.06, 0.08, 0.72), 8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)
	toast_label = _ui_label("", 15, Color(1, 1, 1, 0.9))
	pill.add_child(toast_label)
	holder.modulate.a = 0.0


func _place_toast(top: float) -> void:
	_place(toast_box, Rect2(0, 0, 1, 0))
	toast_box.offset_top = top
	_place(overtime, Rect2(0, 0, 1, 0))
	overtime.offset_top = top + 40


## Munição no canto inferior direito: o número grande, o pente ao lado e uma linha embaixo.
func _build_ammo() -> void:
	var col := Ui.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(220, 70)
	_corner(col, true, Vector2(28, 22))
	add_child(col)
	ammo_box = col
	var row := Ui.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	ammo_label = _ui_label("", 40, Color.WHITE, true)
	row.add_child(ammo_label)
	ammo_max = _ui_label("", 16, Color(1, 1, 1, 0.5))
	ammo_max.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ammo_max.size_flags_vertical = Control.SIZE_FILL
	ammo_max.custom_minimum_size.y = 46
	row.add_child(ammo_max)
	ammo_sub = _ui_label("", 12, Ui.MUTED, true)
	ammo_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(ammo_sub)


## Prende um controle num canto de baixo, a "margin" px das bordas, crescendo para cima.
func _corner(c: Control, right: bool, margin: Vector2) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = 1.0 if right else 0.0
	c.anchor_right = c.anchor_left
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = -margin.x if right else margin.x
	c.offset_right = c.offset_left
	c.offset_bottom = -margin.y
	c.offset_top = -margin.y


## As cartas agora ficam no placar (Tab); com ele aberto, atualiza na hora.
func refresh_cards() -> void:
	scoreboard.rebuild()


## Fim da partida: o placar final com o resultado em cima e os botões embaixo.
## buttons: {"texto": Callable}, o primeiro é o principal.
func show_end(result: String, color: Color, buttons: Dictionary, missions: Array = []) -> void:
	show_center("")
	scoreboard.close()
	var board := Scoreboard.new()
	board.result_text = result
	board.result_color = color
	board.buttons = buttons
	board.missions = missions
	add_child(board)
	board.setup(me, players)
	board.kda = scoreboard.kda
	board.lives = scoreboard.lives
	board.total_lives = scoreboard.total_lives
	board.duel_pair = scoreboard.duel_pair
	board.score = round_score
	board.round_text = round_text
	board.open()
	# Some o resto da HUD (fica só o chat, online).
	ended = true
	for c in get_children():
		c.visible = c == board or (chat != null and c == chat.get_parent())


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


## Label esticado sobre uma região da tela (em frações: 0 a 1), com o texto alinhado dentro dela.
func _label(text: String, size: int, area: Rect2,
		h := HORIZONTAL_ALIGNMENT_CENTER, v := VERTICAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	_place(l, area)
	l.horizontal_alignment = h
	l.vertical_alignment = v
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(l)
	return l


func _place(c: Control, area: Rect2) -> void:
	c.anchor_left = area.position.x
	c.anchor_top = area.position.y
	c.anchor_right = area.end.x
	c.anchor_bottom = area.end.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
