class_name Hud
extends CanvasLayer
## Interface durante a luta. Tudo é criado por código; nada aqui captura o mouse.

const HIT_SHOW := 0.22    # marcador de acerto (X branco)
const KILL_SHOW := 0.6    # marcador de abate (X vermelho, maior)
const AMMO_RADIUS := 26.0       # arco do pente, à direita da mira (px)
const AMMO_SPAN := 80.0         # graus que o arco ocupa
const AMMO_SEGMENTS_MAX := 24   # acima disso vira barra contínua
const RELOAD_RING := 11.0       # anel da recarga no lugar da mira (px)

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

var shield_tint: ColorRect
var damage_fx: DamageFeedback
var blind_tint: ColorRect
var crosshair: Control
var center_label: Label
var toast_label: Label
var score_label: Label
var hp_label: Label
var hp_bar: ProgressBar
var armor_bar: ProgressBar
var ammo_label: Label
var shield_label: Label
var perk_label: Label   # Restauração e Couraça: prontas ou quanto falta (acima da vida)
var shield_bar: ProgressBar
var status_label: Label
var dash_label: Label
var dash_bar: ProgressBar
var master_label: Label
var master_bar: ProgressBar
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


func _ready() -> void:
	shield_tint = _rect(Color(0.4, 0.9, 1.0, 0.12))
	damage_fx = DamageFeedback.new()
	add_child(damage_fx)
	blind_tint = _rect(Color(1, 1, 1, 0))
	crosshair = Control.new()
	_place(crosshair, Rect2(0.5, 0.5, 0, 0))
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)
	score_label = _label("", 28, Rect2(0, 0.01, 1, 0.06))
	toast_label = _label("", 22, Rect2(0, 0.08, 1, 0.06))
	center_label = _label("", 52, Rect2(0, 0.15, 1, 0.3))
	tab_hint = _label("", 14, Rect2(0.79, 0.005, 0.2, 0.03), HORIZONTAL_ALIGNMENT_RIGHT)
	tab_hint.modulate.a = 0.6
	hp_label = _label("", 22, Rect2(0.02, 0.87, 0.25, 0.05), HORIZONTAL_ALIGNMENT_LEFT)
	perk_label = _label("", 15, Rect2(0.02, 0.84, 0.25, 0.03), HORIZONTAL_ALIGNMENT_LEFT)
	hp_bar = _bar(Rect2(0.02, 0.92, 0.25, 0.03), Color(0.3, 0.85, 0.4))
	armor_bar = _bar(Rect2(0.02, 0.955, 0.25, 0.012), Color(1.0, 0.8, 0.3))
	armor_bar.max_value = Player.ARMOR_MAX
	ammo_label = _label("", 32, Rect2(0.73, 0.87, 0.25, 0.08), HORIZONTAL_ALIGNMENT_RIGHT)
	shield_label = _label("", 20, Rect2(0.4, 0.86, 0.2, 0.04))
	shield_bar = _bar(Rect2(0.4, 0.905, 0.2, 0.02), Color(0.4, 0.9, 1.0))
	shield_bar.max_value = 1.0
	dash_label = _label("", 16, Rect2(0.4, 0.925, 0.2, 0.035))
	dash_bar = _bar(Rect2(0.43, 0.962, 0.14, 0.012), Color(0.75, 0.6, 1.0))
	dash_bar.max_value = 1.0
	master_label = _label("", 18, Rect2(0.6, 0.86, 0.13, 0.04))
	master_bar = _bar(Rect2(0.615, 0.905, 0.1, 0.02), Color(1.0, 0.56, 0.22))
	master_bar.max_value = 1.0
	status_label = _label("", 18, Rect2(0.25, 0.81, 0.5, 0.04))
	spectate_label = _label("", 20, Rect2(0.25, 0.835, 0.5, 0.045))
	spectate_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	spectate_hint = _label("", 15, Rect2(0.15, 0.88, 0.7, 0.035))
	spectate_hint.modulate.a = 0.8
	mode_label = _label("", 14, Rect2(0.006, 0.005, 0.3, 0.03), HORIZONTAL_ALIGNMENT_LEFT)
	mode_label.modulate.a = 0.6
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
	scoreboard.setup(me, players)
	kill_feed.me = me
	damage_fx.me = me
	tab_hint.text = "[%s] placar e cartas" % GameState.key_text("scoreboard")
	if teams_on:
		_build_team_bar()
		score_label.visible = false
		_place(toast_label, Rect2(0, 0.115, 1, 0.06))
		_place(kill_feed, Rect2(0.55, 0.13, 0.435, 0.35))   # abaixo da barra dos times
	if mode == "duels":
		_build_duel_bar()
		score_label.visible = false
		_place(toast_label, Rect2(0, 0.115, 1, 0.06))


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
		c[1].modulate.a = 1.0 if p.alive else 0.35
		if c[2]:
			c[2].max_value = p.stats["max_health"]
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
	for c in [crosshair, shield_label, shield_bar, perk_label, dash_label, dash_bar, master_label, master_bar,
			ammo_label, status_label]:
		c.visible = not on


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
func _draw_crosshair() -> void:
	var white := Color(1, 1, 1, 0.9)
	var reloading := me != null and me.alive and me.reload_timer > 0.0 and me.bazooka_timer <= 0.0
	if reloading:
		var total: float = maxf(0.01, me.stats["reload_time"])
		var done := clampf(1.0 - me.reload_timer / total, 0.0, 1.0)
		crosshair.draw_arc(Vector2.ZERO, RELOAD_RING, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 4.5, true)
		crosshair.draw_arc(Vector2.ZERO, RELOAD_RING, 0.0, TAU, 40, Color(1, 1, 1, 0.22), 2.5, true)
		if done > 0.0:
			crosshair.draw_arc(Vector2.ZERO, RELOAD_RING, -PI / 2.0, -PI / 2.0 + TAU * done, 40, white, 2.5, true)
	else:
		var gap := 6.0 + (4.0 if me and me.recoil > 0.2 else 0.0)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			crosshair.draw_line(d * gap, d * (gap + 8.0), Color.BLACK, 4.0)
			crosshair.draw_line(d * gap, d * (gap + 8.0), white, 2.0)
		if me != null and me.alive:
			_draw_ammo_arc()
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
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var a: Vector2 = d.normalized() * 8.0 * pop
			var b: Vector2 = d.normalized() * 16.0 * pop
			crosshair.draw_line(a, b, shadow, 5.0)
			crosshair.draw_line(a, b, color, 2.5)


## Arco do pente: até AMMO_SEGMENTS_MAX balas, um segmento cada; mais que isso, uma barra
## contínua que esvazia. Na Bazuca conta os foguetes; tiros perfurantes saem roxos.
func _draw_ammo_arc() -> void:
	var count: int = me.stats["mag_size"]
	var left: int = me.ammo
	if me.bazooka_timer > 0.0:
		count = Player.BAZOOKA_ROCKETS
		left = me.rockets_left
	if count <= 0:
		return
	var span := deg_to_rad(AMMO_SPAN)
	var top := -span / 2.0
	var shadow := Color(0, 0, 0, 0.45)
	var empty := Color(1, 1, 1, 0.18)
	var full := Color(1, 1, 1, 0.85)
	var last := Color(1.0, 0.62, 0.25, 0.95)
	if count > AMMO_SEGMENTS_MAX:
		var cut := top + span * (1.0 - float(left) / count)
		crosshair.draw_arc(Vector2.ZERO, AMMO_RADIUS, top, top + span, 24, shadow, 5.0, true)
		crosshair.draw_arc(Vector2.ZERO, AMMO_RADIUS, top, top + span, 24, empty, 3.0, true)
		if left > 0:
			crosshair.draw_arc(Vector2.ZERO, AMMO_RADIUS, cut, top + span, 24, last if left == 1 else full, 3.0, true)
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
		crosshair.draw_arc(Vector2.ZERO, AMMO_RADIUS, a, a + seg, 6, shadow, 5.0, true)
		crosshair.draw_arc(Vector2.ZERO, AMMO_RADIUS, a, a + seg, 6, c, 3.0, true)


func _process(delta: float) -> void:
	if me == null:
		return
	fps_label.visible = GameState.show_fps   # pode mudar no menu de pausa
	hp_bar.max_value = me.stats["max_health"]
	hp_bar.value = me.health
	hp_label.text = "Vida %d" % ceili(me.health)
	armor_bar.value = me.armor
	armor_bar.visible = me.armor > 0.0
	if me.armor > 0.0:
		hp_label.text += "   Colete %d" % ceili(me.armor)
	if me.bazooka_timer > 0.0:
		ammo_label.text = "Foguetes %d" % me.rockets_left
	elif me.reload_timer > 0.0:
		ammo_label.text = "Recarregando..."
	else:
		ammo_label.text = "%d / %d" % [me.ammo, me.stats["mag_size"]]
	if me.pierce_left > 0 and me.bazooka_timer <= 0.0:
		ammo_label.text += "   Perfurantes %d" % me.pierce_left

	var total: float = me.stats["shield_duration"] + me.stats["shield_cooldown"]
	if me.is_shielding():
		shield_label.text = "ESCUDO ATIVO"
		shield_bar.value = 1.0
	elif me.shield_cd > 0.0:
		shield_label.text = "Escudo [%s]" % GameState.key_text("shield")
		shield_bar.value = 1.0 - me.shield_cd / total
	else:
		shield_label.text = "Escudo pronto [%s]" % GameState.key_text("shield") + ("  x%d" % (me.shield_extra + 1) if me.shield_extra > 0 else "")
		shield_bar.value = 1.0
	shield_tint.visible = me.alive and me.is_shielding()
	# Restauração e Couraça têm recarga própria: diz quando o escudo volta a curar.
	var perks: Array = []
	if me.stats["shield_heal"] > 0.0:
		perks.append(_perk_text("Cura", "pronta", me.heal_cd))
	if me.stats["shield_armor"] > 0.0:
		perks.append(_perk_text("Colete", "pronto", me.armor_cd))
	perk_label.text = "   ".join(perks)

	# Dash: a barra enche com a recarga; ao lado, quantos dashes no ar ainda restam.
	var dash_total: float = me.stats["dash_cooldown"]
	dash_bar.value = 1.0 - me.dash_cd / dash_total if dash_total > 0.0 else 1.0
	dash_label.text = "Dash [%s]   no ar: %d" % [GameState.key_text("dash"), me.air_dashes_left]
	dash_label.modulate.a = 1.0 if me.dash_cd <= 0.0 else 0.6
	_update_master()
	if team_bar:
		_update_team_bar()
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	var status := PackedStringArray()
	if me.revives_left > 0:
		status.append("Fênix: %d" % me.revives_left)
	if me.slow_timer > 0.0:
		status.append("LENTO")
	if not me.poisons.is_empty():
		status.append("ENVENENADO")
	if me.silence_timer > 0.0:
		status.append("ESCUDO BLOQUEADO")
	if me.is_hidden():
		status.append("INVISÍVEL")
	if me.last_stand_timer > 0.0:
		status.append("ÚLTIMO SUSPIRO: abata alguém! %.1f" % me.last_stand_timer)
	status_label.text = "   ".join(status)
	blind_tint.color.a = clampf(me.blind_timer / 0.3, 0.0, 1.0) * 0.97
	hit_time = maxf(0.0, hit_time - delta)
	kill_time = maxf(0.0, kill_time - delta)
	crosshair.queue_redraw()
	toast_time -= delta
	toast_label.modulate.a = clampf(toast_time, 0.0, 1.0)


## Carta mestra: nome e tecla quando pronta, segundos na recarga; passiva só mostra o nome.
func _update_master() -> void:
	var id := me.master_id
	master_label.visible = id != "" and not dead_view
	master_bar.visible = id != "" and CardDB.CARDS[id].has("cooldown") and not dead_view
	if id == "":
		return
	var card: Dictionary = CardDB.CARDS[id]
	master_label.add_theme_color_override("font_color", CardDB.CATEGORY_COLORS[card["cat"]].lerp(Color.WHITE, 0.3))
	if not card.has("cooldown"):
		master_label.text = card["name"]
		master_label.modulate.a = 0.7
		return
	var total: float = card["cooldown"]
	master_bar.value = 1.0 - me.master_cd / total
	if me.master_cd > 0.0:
		master_label.text = "%s  %d" % [card["name"], ceili(me.master_cd)]
		master_label.modulate.a = 0.6
	else:
		master_label.text = "%s [%s]" % [card["name"], GameState.key_text("master")]
		master_label.modulate.a = 1.0


func set_score(p_score: Dictionary, round_num: int, block_end: int) -> void:
	round_score = p_score
	round_text = "Rodada %d de %d" % [round_num, block_end]
	score_label.text = "%s     (rodada %d de %d)" % [score_text(round_score), round_num, block_end]
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
	for l in [center_label, toast_label, score_label, spectate_label]:
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


## As cartas agora ficam no placar (Tab); com ele aberto, atualiza na hora.
func refresh_cards() -> void:
	scoreboard.rebuild()


## Botões do fim da partida: {"texto": Callable}.
func show_end_buttons(buttons: Dictionary) -> void:
	var box := HBoxContainer.new()
	box.anchor_left = 0.25
	box.anchor_right = 0.75
	box.anchor_top = 0.55
	box.anchor_bottom = 0.63
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	add_child(box)
	for text in buttons:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(200, 50)
		b.pressed.connect(buttons[text])
		box.add_child(b)


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


## Label esticado sobre uma região da tela (em frações: 0 a 1), com o texto alinhado dentro dela.
func _perk_text(what: String, ready_word: String, cd: float) -> String:
	return "%s no escudo: %s" % [what, ready_word] if cd <= 0.0 else "%s no escudo: %.1f s" % [what, cd]


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


func _bar(area: Rect2, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	_place(bar, area)
	bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	bar.add_theme_stylebox_override("fill", style)
	add_child(bar)
	return bar


func _place(c: Control, area: Rect2) -> void:
	c.anchor_left = area.position.x
	c.anchor_top = area.position.y
	c.anchor_right = area.end.x
	c.anchor_bottom = area.end.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
