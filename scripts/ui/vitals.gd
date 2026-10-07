class_name Vitals
extends Control
## Canto inferior esquerdo da HUD (2026-10-06, pedido do usuário): a carta mestra numa
## moldura, a vida com o colete e, ao lado, os ícones do escudo e do dash, que enchem de
## baixo para cima enquanto recarregam.
##
## Desempenho (medido com janela no PC do usuário, partida pausada): cada forma desenhada
## à parte (caixa arredondada, polígono, linha) custava ~1 ms por quadro na Intel HD, e a
## primeira versão gastava ~11 ms. Agora moldura, escudo, setas, selos e barras saem de
## uma textura só (_atlas, gerada uma vez), desenhada por pedaços: o Godot junta tudo numa
## chamada. Os textos vêm no fim, todos juntos. Ordem importa: trocar de textura no meio
## quebra o lote.

const FRAME := 80.0           # moldura da carta mestra
const BAR_X := 98.0           # começo do bloco da vida
const BAR_W := 260.0
const BAR_H := 10.0
const ICON_X := BAR_X + BAR_W + 38.0   # centro do escudo; o dash vem DASH_DX px depois
const DASH_DX := 58.0
const ICON_Y := 36.0
const SHIELD_SIZE := Vector2(34, 40)
const DASH_SIZE := Vector2(32, 32)
const TRAIL_DELAY := 0.45     # o rastro do dano espera e depois desce
const TRAIL_SPEED := 90.0     # vida por segundo
const LOW := 0.3              # abaixo disso a barra fica vermelha e pulsa
const SHIELD_COLOR := Color(0.4, 0.88, 1.0)
const DASH_COLOR := Color(0.78, 0.64, 1.0)
const ARMOR_COLOR := Color(0.3, 0.55, 1.0)   # a mesma do item (Pickup.COLORS)
const CHAOS_COLOR := Color(1.0, 0.45, 0.4)   # cor do grupo Balas
const SHADOW := Color(0, 0, 0, 0.45)

## Pedaços da textura única (posição na imagem).
const R_WHITE := Rect2(1, 1, 2, 2)
const R_FRAME := Rect2(8, 0, 80, 80)
const R_RING := Rect2(96, 0, 80, 80)
const R_SHIELD := Rect2(184, 0, 34, 40)
const R_SHIELD_LINE := Rect2(222, 0, 34, 40)
const R_DASH := Rect2(184, 44, 32, 32)
const R_DASH_LINE := Rect2(222, 44, 32, 32)
const R_PILL := Rect2(8, 88, 20, 20)
const PILL_CAP := 7.0

static var _atlas: ImageTexture

var me: Player
var combat := true            # morto ou caído: só a vida aparece
var trail := 0.0
var trail_wait := 0.0
var _last_health := -1.0
var _font: Font
var _bold: Font
var _texts: Array = []        # textos do quadro, desenhados no fim: [fonte, pos, texto, tamanho, cor]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ICON_X + DASH_DX + 28.0, 96.0)
	_font = ThemeDB.fallback_font
	_bold = Ui.bold()
	if _atlas == null:
		_atlas = _build_atlas()


func tick(delta: float) -> void:
	if me == null:
		return
	if me.health < _last_health:
		trail_wait = TRAIL_DELAY
		trail = maxf(trail, _last_health)
	_last_health = me.health
	trail_wait -= delta
	if trail_wait <= 0.0:
		trail = maxf(me.health, trail - TRAIL_SPEED * delta)
	queue_redraw()


func _draw() -> void:
	if me == null:
		return
	_texts.clear()
	if combat:
		_draw_master()
		_draw_shield()
		_draw_dash()
	_draw_health()
	if combat:
		_draw_master_top()
	for t in _texts:
		draw_string_outline(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], 4, Color(0, 0, 0, 0.55))
	for t in _texts:
		draw_string(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[4])


# ---------------------------------------------------------------- vida

func _draw_health() -> void:
	var max_hp: float = maxf(1.0, me.stats["max_health"])
	var hp := maxf(0.0, me.health)
	var frac := hp / max_hp
	var low := frac < LOW and me.alive
	var x := BAR_X if combat else 0.0
	# Número grande e o máximo ao lado; colete em amarelo depois.
	var big := str(ceili(hp))
	_text(_bold, Vector2(x, 34), big, 30, Ui.DANGER.lerp(Color.WHITE, 0.15) if low else Color.WHITE)
	var after := x + _width(_bold, big, 30) + 6
	var max_text := "/ %d" % roundi(max_hp)
	_text(_font, Vector2(after, 34), max_text, 14, Color(1, 1, 1, 0.5))
	after += _width(_font, max_text, 14) + 14
	if me.armor > 0.0:
		var armor_text := "+%d colete" % ceili(me.armor)
		_text(_bold, Vector2(after, 34), armor_text, 14, ARMOR_COLOR)
		after += _width(_bold, armor_text, 14) + 14

	# Barra: fundo, rastro do dano, vida e marcas a cada 25.
	var bar := Rect2(x, 44, BAR_W, BAR_H)
	_rect(bar.grow(1), SHADOW)
	_rect(bar, Color(1, 1, 1, 0.1))
	if trail > hp:
		_rect(Rect2(bar.position, Vector2(BAR_W * clampf(trail / max_hp, 0, 1), BAR_H)), Color(1.0, 0.45, 0.4, 0.75))
	var fill := Color(1, 1, 1, 0.92)
	if low:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.009)
		fill = Ui.DANGER.lerp(Color.WHITE, 0.1) * Color(1, 1, 1, pulse)
	_rect(Rect2(bar.position, Vector2(BAR_W * clampf(frac, 0, 1), BAR_H)), fill)
	var v := 25.0
	while v < max_hp - 1.0:
		_rect(Rect2(bar.position.x + BAR_W * v / max_hp - 1.0, bar.position.y, 2, BAR_H), Color(0, 0, 0, 0.55))
		v += 25.0
	# Colete: faixa fina embaixo, na escala do máximo de colete.
	if me.armor > 0.0:
		var ar := Rect2(x, bar.end.y + 4, BAR_W * clampf(me.armor / Player.ARMOR_MAX, 0, 1), 4)
		_rect(ar.grow(1), SHADOW)
		_rect(ar, ARMOR_COLOR)


# ---------------------------------------------------------------- carta mestra

func _master_ready() -> bool:
	if not CardDB.CARDS[me.master_id].has("cooldown"):
		return me.plat_cd <= 0.0   # passiva: só as Plataformas Suspensas têm recarga
	return me.master_cd <= 0.0


## Recarga que falta e a total (ativa: a da carta; Plataformas Suspensas: a da passiva).
func _master_wait() -> Vector2:
	if CardDB.CARDS[me.master_id].has("cooldown"):
		return Vector2(me.master_cd, me.master_cd_total())
	return Vector2(me.plat_cd, Player.PLAT_COOLDOWN)


## Moldura (sombra, fundo e borda); o ícone, a recarga e a tecla vêm depois.
func _draw_master() -> void:
	var id := me.master_id
	if id == "":
		return
	var card: Dictionary = CardDB.CARDS[id]
	var cat: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var rect := Rect2(0, 2, FRAME, FRAME)
	var lit := _master_ready() and card.has("cooldown")
	_blit(R_FRAME, rect.grow(3), Color(0, 0, 0, 0.35))
	_blit(R_FRAME, rect, Color(cat.darkened(0.8), 0.94))
	_blit(R_RING, rect, CardDB.rarity_color(id) if lit else Color(cat.darkened(0.3), 0.9))


## Por cima da moldura: o ícone da carta, a recarga (escurece de cima para baixo, e os
## segundos no meio) e o selo da tecla na borda de baixo.
func _draw_master_top() -> void:
	var id := me.master_id
	if id == "":
		return
	var card: Dictionary = CardDB.CARDS[id]
	var cat: Color = CardDB.CATEGORY_COLORS[card["cat"]]
	var rect := Rect2(0, 2, FRAME, FRAME)
	var has_cd := card.has("cooldown")
	var ready := _master_ready()
	var tex := CardDB.icon(id)
	if tex:
		var tint := cat.lerp(Color.WHITE, 0.25)
		tint.a = 1.0 if ready else 0.4
		draw_texture_rect(tex, rect.grow(-14), false, tint)
	var wait := _master_wait()
	if wait.x > 0.0:
		var left: float = clampf(wait.x / wait.y, 0.0, 1.0)
		_blit(R_FRAME, rect, Color(0, 0, 0, 0.45), left, true)
		var secs := str(ceili(wait.x))
		_text(_bold, rect.get_center() + Vector2(-_width(_bold, secs, 24) / 2.0, 9), secs, 24, Color.WHITE)
	var key := GameState.key_text("master") if has_cd else "passiva"
	var lit := ready and has_cd
	_chip(Vector2(rect.get_center().x, rect.end.y - 10), key,
		Ui.ACCENT if lit else Color(0.08, 0.09, 0.11, 0.95), Color(0.1, 0.07, 0.04) if lit else Color(1, 1, 1, 0.7))
	if me.chaos:
		# Caos: selo no topo da moldura e, na passiva sorteada, a barra do tempo que falta.
		_chip(Vector2(rect.get_center().x, rect.position.y - 9), "CAOS", CHAOS_COLOR, Color(0.1, 0.07, 0.04))
		if me.chaos_timer > 0.0:
			var bar := Rect2(rect.position.x + 10, rect.end.y - 16, (rect.size.x - 20) * clampf(me.chaos_timer / Player.CHAOS_PASSIVE_TIME, 0, 1), 3)
			_rect(bar, CHAOS_COLOR)


# ---------------------------------------------------------------- escudo e dash

func _draw_shield() -> void:
	var total: float = me.stats["shield_duration"] + me.stats["shield_cooldown"]
	var silenced: bool = me.silence_timer > 0.0
	var active: bool = me.is_shielding()
	var charge := 1.0 if active or me.shield_cd <= 0.0 else clampf(1.0 - me.shield_cd / maxf(0.01, total), 0.0, 1.0)
	var color := Ui.DANGER if silenced else SHIELD_COLOR
	var rect := Rect2(Vector2(ICON_X, ICON_Y) - SHIELD_SIZE / 2.0, SHIELD_SIZE)
	if active:
		_blit(R_SHIELD, rect.grow(6), Color(SHIELD_COLOR, 0.25))
	_icon(R_SHIELD, R_SHIELD_LINE, rect, charge, color)
	if charge < 1.0 and not silenced:
		var secs := "%.1f" % me.shield_cd
		_text(_bold, Vector2(ICON_X - _width(_bold, secs, 12) / 2.0, ICON_Y + 5), secs, 12, Color.WHITE)
	if me.shield_extra > 0 and not active:
		_text(_bold, Vector2(ICON_X + 13, ICON_Y - 12), "x%d" % (me.shield_extra + 1), 12, Color.WHITE)
	_key(Vector2(ICON_X, ICON_Y + 26), GameState.key_text("shield"), charge >= 1.0 and not silenced)


func _draw_dash() -> void:
	var cx := ICON_X + DASH_DX
	var total: float = me.stats["dash_cooldown"]
	var charge := 1.0 if me.dash_cd <= 0.0 or total <= 0.0 else clampf(1.0 - me.dash_cd / total, 0.0, 1.0)
	_icon(R_DASH, R_DASH_LINE, Rect2(Vector2(cx, ICON_Y) - DASH_SIZE / 2.0, DASH_SIZE), charge, DASH_COLOR)
	# Dashes no ar que sobram: pontinhos acima da tecla.
	var n: int = me.stats["air_dashes"]
	if n > 1 or me.air_dashes_left < n:
		for i in n:
			var p := Vector2(cx - (n - 1) * 5.0 + i * 10.0, ICON_Y + 20)
			_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), DASH_COLOR if i < me.air_dashes_left else Color(1, 1, 1, 0.2))
	_key(Vector2(cx, ICON_Y + 26), GameState.key_text("dash"), charge >= 1.0)


## Ícone que enche de baixo para cima: apagado inteiro, a parte carregada na cor e o
## contorno (claro quando cheio).
func _icon(fill: Rect2, line: Rect2, rect: Rect2, charge: float, color: Color) -> void:
	if charge < 1.0:
		_blit(fill, rect, Color(1, 1, 1, 0.12))
		if charge > 0.0:
			_blit(fill, rect, Color(color, 0.55), charge)
	else:
		_blit(fill, rect, color)
	_blit(line, rect, Color(color.lerp(Color.WHITE, 0.3), 0.95) if charge >= 1.0 else Color(1, 1, 1, 0.35))


## Selo da tecla embaixo de um ícone.
func _key(center: Vector2, text: String, lit: bool) -> void:
	_chip(center, text, Color(0.08, 0.09, 0.11, 0.9), Color(1, 1, 1, 0.9 if lit else 0.45),
		Color(1, 1, 1, 0.35 if lit else 0.12))


## Pílula com texto centrada em x, com o topo em center.y (três pedaços: as pontas
## arredondadas e o meio esticado). border: contorno de 1 px por baixo, opcional.
func _chip(center: Vector2, text: String, bg: Color, fg: Color, border := Color.TRANSPARENT) -> void:
	var w := _width(_bold, text, 12) + 14.0
	var r := Rect2(center.x - w / 2.0, center.y, w, 19)
	if border.a > 0.0:
		_pill(r.grow(1), border)
	_pill(r, bg)
	_text(_bold, r.position + Vector2(7, 14), text, 12, fg)


func _pill(r: Rect2, color: Color) -> void:
	var cap := minf(PILL_CAP, r.size.x / 2.0)
	var src_cap := R_PILL.size.x * 0.35
	_blit(Rect2(R_PILL.position, Vector2(src_cap, R_PILL.size.y)), Rect2(r.position, Vector2(cap, r.size.y)), color)
	_blit(Rect2(R_PILL.position + Vector2(src_cap, 0), Vector2(R_PILL.size.x - 2 * src_cap, R_PILL.size.y)),
		Rect2(r.position + Vector2(cap, 0), Vector2(r.size.x - 2 * cap, r.size.y)), color)
	_blit(Rect2(R_PILL.end.x - src_cap, R_PILL.position.y, src_cap, R_PILL.size.y),
		Rect2(r.end.x - cap, r.position.y, cap, r.size.y), color)


# ---------------------------------------------------------------- desenho

func _rect(r: Rect2, color: Color) -> void:
	draw_texture_rect_region(_atlas, r, R_WHITE, color)


## Pedaço da textura esticado no retângulo. part < 1: só a fração de baixo (ou de cima,
## from_top), para os ícones que enchem e a recarga da mestra.
func _blit(src: Rect2, dest: Rect2, color: Color, part := 1.0, from_top := false) -> void:
	if part >= 1.0:
		draw_texture_rect_region(_atlas, dest, src, color)
		return
	var k := clampf(part, 0.0, 1.0)
	var s := src
	var d := dest
	s.size.y *= k
	d.size.y *= k
	if not from_top:
		s.position.y = src.end.y - s.size.y
		d.position.y = dest.end.y - d.size.y
	draw_texture_rect_region(_atlas, d, s, color)


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	_texts.append([font, pos, text, size, color])


func _width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# ---------------------------------------------------------------- textura única

## Gera a imagem com as formas brancas (a cor vem na hora de desenhar). Bordas suaves por
## amostragem 3x3 em cada pixel.
static func _build_atlas() -> ImageTexture:
	var img := Image.create(256, 112, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	_paint(img, Rect2i(0, 0, 4, 4), func(_p): return 1.0)
	_paint(img, Rect2i(R_FRAME), func(p): return 1.0 if _round_rect_sd(p, Vector2(80, 80), 12.0) <= 0.0 else 0.0)
	_paint(img, Rect2i(R_RING), func(p):
		var d := _round_rect_sd(p, Vector2(80, 80), 12.0)
		return 1.0 if d <= 0.0 and d >= -2.0 else 0.0)
	_paint(img, Rect2i(R_PILL), func(p): return 1.0 if _round_rect_sd(p, Vector2(20, 20), 6.0) <= 0.0 else 0.0)
	var shield := _shield_shape(SHIELD_SIZE)
	_paint(img, Rect2i(R_SHIELD), func(p): return 1.0 if Geometry2D.is_point_in_polygon(p, shield) else 0.0)
	_paint(img, Rect2i(R_SHIELD_LINE), func(p): return 1.0 if _edge_dist(p, shield) <= 1.1 else 0.0)
	var chevrons := _chevrons(DASH_SIZE)
	_paint(img, Rect2i(R_DASH), func(p):
		for poly in chevrons:
			if Geometry2D.is_point_in_polygon(p, poly):
				return 1.0
		return 0.0)
	_paint(img, Rect2i(R_DASH_LINE), func(p):
		for poly in chevrons:
			if _edge_dist(p, poly) <= 1.0:
				return 1.0
		return 0.0)
	return ImageTexture.create_from_image(img)


## Pinta o pedaço: cobertura (0 a 1) média de 9 amostras por pixel, em coordenadas locais.
static func _paint(img: Image, area: Rect2i, inside: Callable) -> void:
	for y in area.size.y:
		for x in area.size.x:
			var hits := 0.0
			for sy in 3:
				for sx in 3:
					hits += inside.call(Vector2(x + (sx + 0.5) / 3.0, y + (sy + 0.5) / 3.0))
			if hits > 0.0:
				img.set_pixel(area.position.x + x, area.position.y + y, Color(1, 1, 1, hits / 9.0))


## Distância com sinal até uma caixa arredondada de tamanho s com o canto em 0,0.
static func _round_rect_sd(p: Vector2, s: Vector2, r: float) -> float:
	var q := (p - s / 2.0).abs() - s / 2.0 + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Escudo clássico (canto em 0,0): topo reto com cantos, laterais retas e a ponta embaixo.
static func _shield_shape(size: Vector2) -> PackedVector2Array:
	var w := size.x - 2.0
	var h := size.y - 2.0
	var c := size / 2.0
	var hw := w / 2.0
	var top := c.y - h / 2.0
	var pts := PackedVector2Array([Vector2(c.x - hw, top + 3), Vector2(c.x - hw + 3, top),
		Vector2(c.x + hw - 3, top), Vector2(c.x + hw, top + 3), Vector2(c.x + hw, top + h * 0.42)])
	for k in range(1, 10):
		var t := k / 10.0
		var a := Vector2(c.x + hw, top + h * 0.42)
		var ctrl := Vector2(c.x + hw, top + h * 0.82)
		var b := Vector2(c.x, top + h)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	pts.append(Vector2(c.x, top + h))
	for k in range(1, 10):
		var t := k / 10.0
		var a := Vector2(c.x, top + h)
		var ctrl := Vector2(c.x - hw, top + h * 0.82)
		var b := Vector2(c.x - hw, top + h * 0.42)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	pts.append(Vector2(c.x - hw, top + h * 0.42))
	return pts


## Duas setas ">>" (canto em 0,0).
static func _chevrons(size: Vector2) -> Array:
	var out := []
	var c := size / 2.0
	var hh := size.y / 2.0 - 1.0
	for dx in [-8.0, 6.0]:
		var x: float = c.x + dx
		out.append(PackedVector2Array([
			Vector2(x - 7, c.y - hh), Vector2(x, c.y - hh), Vector2(x + 9, c.y),
			Vector2(x, c.y + hh), Vector2(x - 7, c.y + hh), Vector2(x + 2, c.y)]))
	return out
