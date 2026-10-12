class_name OvertimeBanner
extends VBoxContainer
## Aviso da Prorrogação (Overtime) no topo da tela (2026-10-12, pedido do usuário: claro e
## com tensão, como a contagem de uma bomba). 30 s antes das cartas e do fechamento aparece o
## aviso com o tempo; nos últimos 10 s o número fica grande, pulsa a cada segundo, vai do
## laranja ao vermelho e bipa; no zero, estouro com o nome da fase. Depois fica uma linha
## compacta (próxima carta, raio do círculo) e o nome de cada carta nova. Fora do círculo,
## "FORA DA ARENA" em vermelho. Os textos só mudam quando o número muda.

const BIG_SIZE := 72
const BURST_TIME := 1.6
const CARD_TIME := 2.5

var me: Player
var time := 0.0          # tempo de luta da rodada (posto pela partida)
var half := 35.0         # meio-lado da arena (raio do círculo)
var running := false     # luta rolando (fora dela o aviso some)

var _title: Label
var _big: Label
var _sub: Label
var _card: Label
var _out: Label
var _last_count := -1
var _burst := 0.0
var _card_time := 0.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 0)
	_title = _label(20, Ui.WARN, true)
	_big = _label(BIG_SIZE, Ui.WARN, true)
	_sub = _label(16, Color(1, 1, 1, 0.85))
	_card = _label(18, Ui.OK, true)
	_out = _label(26, Ui.DANGER, true)
	visible = false


func _label(size: int, color: Color, is_bold := false) -> Label:
	var l := Ui.label("", size, color, is_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 6 if size >= 40 else 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.visible = false
	add_child(l)
	return l


## Carta nova da prorrogação (sinal do Player): o nome aparece embaixo por CARD_TIME.
func on_card(id: String) -> void:
	_card.text = "+ " + CardDB.card_name(id)
	_card_time = CARD_TIME


func reset() -> void:
	_last_count = -1
	_burst = 0.0
	_card_time = 0.0


func _process(delta: float) -> void:
	visible = running and time >= Overtime.CARDS_AT - Overtime.WARN
	if not visible:
		return
	_burst = maxf(0.0, _burst - delta)
	_card_time = maxf(0.0, _card_time - delta)
	var t := time
	var zone_on := t >= Overtime.ZONE_AT
	var cards_on := t >= Overtime.CARDS_AT
	# Fase com contagem: a primeira que ainda não chegou e está a menos de WARN.
	var target := -1.0
	var what := ""
	if not cards_on:
		target = Overtime.CARDS_AT
		what = "PRORROGAÇÃO"
	elif not zone_on and t >= Overtime.ZONE_AT - Overtime.WARN:
		target = Overtime.ZONE_AT
		what = "A ARENA FECHA"
	var title := ""
	var big := ""
	var sub := ""
	var color := Ui.WARN
	if target > 0.0:
		var left := ceili(target - t)
		title = what + " EM"
		if left <= Overtime.COUNTDOWN:
			big = str(left)
			# Laranja no 10, vermelho no 1.
			color = Ui.WARN.lerp(Ui.DANGER, 1.0 - float(left - 1) / float(Overtime.COUNTDOWN - 1))
			if left != _last_count:
				_last_count = left
				_pulse()
				Sfx.ui(self, "count")
		else:
			title += " %d:%02d" % [left / 60, left % 60]
			_last_count = -1
		sub = "uma carta extra do seu baralho a cada %d s" % int(Overtime.CARD_EVERY) if not cards_on \
			else "o círculo vai encolher até o centro em %d min" % int(Overtime.ZONE_TIME / 60.0)
	elif _last_count >= 0:
		# Acabou a contagem: estouro.
		_last_count = -1
		_burst = BURST_TIME
		_pulse()
		Sfx.ui(self, "count_go")
	if target < 0.0:
		var r := Overtime.zone_radius(t, half)
		if zone_on:
			title = "ARENA FECHADA" if r <= Overtime.ZONE_MIN else "ARENA FECHANDO"
			color = Ui.DANGER
			sub = "raio %d m" % ceili(r)
		else:
			title = "PRORROGAÇÃO"
		var next := Overtime.next_card_in(t)
		var cards := "cartas extras %d/%d" % [Overtime.cards_due(t), Overtime.MAX_CARDS]
		if next >= 0.0:
			cards += "  ·  próxima em %d" % ceili(next)
		sub = cards if sub == "" else sub + "  ·  " + cards
		if _burst > 0.0:
			big = "FECHANDO!" if zone_on else "PRORROGAÇÃO!"
			color = Ui.DANGER
	_show(_title, title, color)
	_show(_big, big, color)
	_show(_sub, sub, Color(1, 1, 1, 0.85))
	_card.visible = _card_time > 0.0
	_card.modulate.a = clampf(_card_time * 2.0, 0.0, 1.0)
	var out := me != null and me.alive and me.zone_out
	_show(_out, "FORA DA ARENA: VOLTE PARA DENTRO" if out else "", Ui.DANGER)
	if out:
		_out.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.008))


func _show(l: Label, text: String, color: Color) -> void:
	l.visible = text != ""
	if l.text != text:
		l.text = text
	if l.get_theme_color("font_color") != color:
		l.add_theme_color_override("font_color", color)


## O número grande nasce 1,5x maior e volta ao tamanho em 0,35 s.
func _pulse() -> void:
	if _tween:
		_tween.kill()
	_big.pivot_offset = _big.size / 2.0
	_big.scale = Vector2(1.5, 1.5)
	_tween = create_tween()
	_tween.tween_property(_big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
