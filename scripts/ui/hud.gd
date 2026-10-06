class_name Hud
extends CanvasLayer
## Interface durante a luta. Tudo é criado por código; nada aqui captura o mouse.

const HIT_SHOW := 0.22    # marcador de acerto (X branco)
const KILL_SHOW := 0.6    # marcador de abate (X vermelho, maior)
const AMMO_RADIUS := 26.0       # arco do pente, à direita da mira (px)
const AMMO_SPAN := 80.0         # graus que o arco ocupa
const AMMO_SEGMENTS_MAX := 24   # acima disso vira barra contínua
const RELOAD_RING := 11.0       # anel da recarga no lugar da mira (px)
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
var dead_view := false
var downed_view := false
var scope: ColorRect      # luneta da Sniper: tela escura com um círculo e a cruz fina
## Luneta num shader só (um retângulo na tela toda): fora do círculo, preto; dentro, a
## cruz fina com um vão no meio e uma borda escura. Uma chamada de desenho, como a mira.
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
var crosshair: Control
var center_label: Label
var toast_label: Label
var score_label: Label     # placar no topo (cada um por si), dentro de score_box
var score_round: Label     # "RODADA 3 DE 5" acima do placar
var score_box: Control
var toast_box: Control     # aviso rápido ("Fulano escolheu: ...") numa pílula no topo
var vitals: Vitals         # canto inferior esquerdo: mestra, vida, escudo e dash
var ammo_box: Control      # canto inferior direito: munição e a arma especial
var ammo_label: Label
var ammo_max: Label
var ammo_sub: Label
var status_row: HBoxContainer   # estados (lento, envenenado...) em selos acima da vida
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
	scope = ColorRect.new()
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scope_mat := ShaderMaterial.new()
	scope_mat.shader = Shader.new()
	scope_mat.shader.code = SCOPE_SHADER
	scope.material = scope_mat
	scope.visible = false
	add_child(scope)
	crosshair = Control.new()
	_place(crosshair, Rect2(0.5, 0.5, 0, 0))
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)
	_build_score_box()
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
	spectate_label = _label("", 20, Rect2(0.25, 0.835, 0.5, 0.045))
	spectate_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	spectate_hint = _label("", 15, Rect2(0.15, 0.88, 0.7, 0.035))
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
	vitals.me = me
	scoreboard.setup(me, players)
	kill_feed.me = me
	damage_fx.me = me
	tab_hint.text = "[%s] placar e cartas" % GameState.key_text("scoreboard")
	if teams_on:
		_build_team_bar()
		score_box.visible = false
		_place_toast(96)
		_place(kill_feed, Rect2(0.55, 0.13, 0.435, 0.35))   # abaixo da barra dos times
	if mode == "duels":
		_build_duel_bar()
		score_box.visible = false
		_place_toast(96)


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
			row.add_child(_ui_label("x", 20, Color(1, 1, 1, 0.6), true))
		else:
			row.add_child(hearts)
			row.add_child(name_label)
	duel_queue_label = _label("", 15, Rect2(0, 0.065, 1, 0.035))
	duel_queue_label.modulate.a = 0.75


## pair: nomes dos nós de quem duela; lives: nome -> vidas; queue: nomes na fila.
func set_duel(pair: Array, p_lives: Dictionary, queue: Array) -> void:
	if duel_names.is_empty():
		return
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
	duel_queue_label.text = "Próximos: " + ", ".join(waiting) if not waiting.is_empty() else ""


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
	var top := _ui_label("RODADA", 11, Color(1, 1, 1, 0.6), true)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(top)
	team_round = _ui_label("", 18, Color.WHITE, true)
	team_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(team_round)
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
	var name_label := _ui_label(String(GameState.TEAM_NAMES[team]).to_upper(), 11, color.lightened(0.45), true)
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


## Caído no 2x2: some o que é de luta; a mira vira o anel do prazo e do reviver.
func _update_downed() -> void:
	reviving_who = null
	if me.alive:
		for p in players:
			if p.downed and me.is_ally(p) and p.global_position.distance_to(me.global_position) < Player.REVIVE_RADIUS:
				reviving_who = p
	if reviving_who:
		down_label.text = "Revivendo %s..." % reviving_who.player_name
		return
	if me.downed != downed_view:
		downed_view = me.downed
		_hide_combat(downed_view or dead_view)
	if downed_view:
		var reviving := me.revive_progress > 0.0
		down_label.text = "CAÍDO   %d s\n%s" % [ceili(me.bleed_timer),
			"Revivendo..." if reviving else "Seu parceiro revive você ficando perto por %d s" % roundi(Player.REVIVE_TIME)]
	else:
		down_label.text = ""


## Morto assistindo: quem a câmera segue (ou "Câmera livre") e as teclas ("" esconde).
func set_spectating(text: String, hint := "") -> void:
	spectate_label.text = text
	spectate_hint.text = hint


func _on_me_damaged(amount: float, from: Player) -> void:
	damage_fx.hit(amount, from)


## O X cresce com o dano do acerto (vários no mesmo quadro, como na escopeta, somam).
func _on_damage_dealt(amount: float, lethal: bool) -> void:
	var stacked := amount + (hit_size * 34.0 if hit_time >= HIT_SHOW - 0.02 else 0.0)
	hit_size = clampf(stacked / 34.0, 0.8, 1.6)
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
		# Anel inteiro em 40 pedaços: até o corte branco (já recarregado), depois apagado.
		for k in 40:
			var a0 := -PI / 2.0 + TAU * k / 40.0
			var a1 := -PI / 2.0 + TAU * (k + 1) / 40.0
			if a0 < cut and a1 > cut:
				_arc_piece(pts, cols, RELOAD_RING, a0, cut, white)
				_arc_piece(pts, cols, RELOAD_RING, cut, a1, Color(1, 1, 1, 0.22))
			else:
				_arc_piece(pts, cols, RELOAD_RING, a0, a1, white if a1 <= cut else Color(1, 1, 1, 0.22))
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
	crosshair.draw_circle(Vector2.ZERO, 1.6, white)
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


## Bota Foguete: barra fina sob a mira, só enquanto o jato não está cheio.
func _draw_boot_fuel() -> void:
	if me.stats["rocket_boots"] <= 0 or me.boot_fuel >= Player.BOOT_FUEL:
		return
	var w := 64.0
	var top := Vector2(-w / 2.0, 30.0)
	crosshair.draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.5))
	crosshair.draw_rect(Rect2(top, Vector2(w * me.boot_fuel / Player.BOOT_FUEL, 5)), Color(1.0, 0.6, 0.25, 0.95))


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
	for i in count:
		# i = 0 é o de cima: some primeiro. Quem sobra fica embaixo.
		var a := top + i * (seg + gap)
		var has := i >= count - left
		var c := empty
		if has:
			c = last if left == 1 and me.bazooka_timer <= 0.0 else full
			if me.pierce_left > 0 and i - (count - left) < me.pierce_left and me.bazooka_timer <= 0.0:
				c = Color(Bullet.PIERCE_COLOR, 0.95)
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
	if me == null or ended:
		return
	fps_label.visible = GameState.show_fps   # pode mudar no menu de pausa
	vitals.tick(delta)
	scope.visible = me.scoping
	if scope.visible:
		(scope.material as ShaderMaterial).set_shader_parameter("screen", scope.size)
	crosshair.visible = not me.scoping and not dead_view
	_update_ammo()
	shield_tint.visible = me.alive and me.is_shielding()
	_update_downed()
	if team_bar:
		_update_team_bar()
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	_update_status()
	blind_tint.color.a = clampf(me.blind_timer / 0.3, 0.0, 1.0) * 0.97
	blind_tint.visible = blind_tint.color.a > 0.0   # camada de tela cheia: só quando cega
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
		sub = "ESPADA  %.0f s" % ceilf(me.sword_timer)
		sub_color = Ui.ACCENT
	elif me.sniper_timer > 0.0:
		big = str(me.sniper_shots)
		small = "/ 1"
		sub = "SNIPER  %.0f s" % ceilf(me.sniper_timer)
		sub_color = Ui.ACCENT
	elif me.bazooka_timer > 0.0:
		big = str(me.rockets_left)
		small = "/ %d" % Player.BAZOOKA_ROCKETS
		sub = "BAZUCA  %.0f s" % ceilf(me.bazooka_timer)
		sub_color = Ui.ACCENT
	elif me.reload_timer > 0.0:
		sub = "RECARREGANDO"
		sub_color = Color(1, 1, 1, 0.75)
	if me.pierce_left > 0 and me.bazooka_timer <= 0.0:
		sub = ("%s  ·  " % sub if sub != "" else "") + "PERFURANTES %d" % me.pierce_left
		sub_color = Bullet.PIERCE_COLOR.lerp(Color.WHITE, 0.3)
	ammo_label.text = big
	ammo_max.text = small
	ammo_sub.text = sub
	ammo_sub.add_theme_color_override("font_color", sub_color)
	var empty: bool = me.ammo <= 1 and me.reload_timer <= 0.0 and me.bazooka_timer <= 0.0 \
		and me.sniper_timer <= 0.0 and me.sword_timer <= 0.0
	ammo_label.add_theme_color_override("font_color", Ui.ACCENT if empty else Color.WHITE)


## Estados do jogador em selos acima da vida; só refaz quando a lista muda.
func _update_status() -> void:
	var items := []
	if me.revives_left > 0:
		items.append(["FÊNIX %d" % me.revives_left, Color(1.0, 0.6, 0.25)])
	if me.slow_timer > 0.0:
		items.append(["LENTO", Color(0.55, 0.8, 1.0)])
	if not me.poisons.is_empty():
		items.append(["ENVENENADO", Color(0.55, 0.95, 0.35)])
	if me.silence_timer > 0.0:
		items.append(["ESCUDO BLOQUEADO", Ui.DANGER])
	if me.is_hidden():
		items.append(["INVISÍVEL", Color(0.75, 0.6, 1.0)])
	if me.ambush_timer > 0.0:
		items.append(["EMBOSCADA %.1f" % me.ambush_timer, Color(0.8, 0.55, 1.0)])
	if me.speed_orb_timer > 0.0:
		items.append(["VELOCIDADE +%d%%  %.1f" % [roundi(Player.SPEED_ORB * 100.0), me.speed_orb_timer], Pickup.COLORS[Pickup.Kind.SPEED]])
	if me.shrink_timer > 0.0:
		items.append(["FORMIGA %.1f  ·  [%s] volta" % [me.shrink_timer, GameState.key_text("master")], Color(0.78, 0.64, 1.0)])
	if me.air_bonus() > 0.0:
		items.append(["NO AR +%d%% DE DANO" % roundi(me.air_bonus() * 100.0), Ui.ACCENT])
	if me.last_stand_timer > 0.0:
		items.append(["ÚLTIMO SUSPIRO %.1f: ABATA ALGUÉM" % me.last_stand_timer, Ui.DANGER])
	var key := str(items)
	if key == _status_key:
		return
	_status_key = key
	for c in status_row.get_children():
		c.queue_free()
	for it in items:
		status_row.add_child(_status_chip(it[0], it[1]))


## Selo de estado: texto em negrito na cor, fundo escuro e um traço da cor à esquerda.
func _status_chip(text: String, color: Color) -> Control:
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
	l.add_theme_stylebox_override("normal", box)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_score(p_score: Dictionary, round_num: int, block_end: int) -> void:
	round_score = p_score
	round_text = "Rodada %d de %d" % [round_num, block_end]
	score_label.text = score_text(round_score)
	score_round.text = "RODADA %d DE %d" % [round_num, block_end]
	if team_bar:
		for t in 2:
			team_scores[t].text = str(_team_score(t))
		team_round.text = "%d / %d" % [round_num, block_end]
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
	for l in [center_label, toast_box, score_box, spectate_label]:
		l.self_modulate.a = 0.0 if on else 1.0   # o placar já mostra isso; texto solto atrapalha
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
		return "%s %d  x  %d %s" % [GameState.TEAM_NAMES[mine], _team_score(mine, score),
			_team_score(1 - mine, score), GameState.TEAM_NAMES[1 - mine]]
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
	var col := Ui.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(col)
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
func show_end(result: String, color: Color, buttons: Dictionary) -> void:
	show_center("")
	scoreboard.close()
	var board := Scoreboard.new()
	board.result_text = result
	board.result_color = color
	board.buttons = buttons
	add_child(board)
	board.setup(me, players)
	board.kda = scoreboard.kda
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
