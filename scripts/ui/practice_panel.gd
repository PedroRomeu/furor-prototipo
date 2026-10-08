class_name PracticePanel
extends PanelContainer
## Painel de dano da sala de teste, no canto direito: DPS dos últimos 3 s, o melhor DPS,
## dano total, maior golpe, tiros e golpes, e em quanto tempo o melhor DPS tira 100 de
## vida. Conta todo dano que você causa (balas, áreas, mestras). Z zera.
## Textos atualizados 4 vezes por segundo (Label, sem desenho de formas).

const WINDOW := 3.0
const REFRESH := 0.25

var _events: Array = []   # [segundos, dano]
var _total := 0.0
var _best_dps := 0.0
var _biggest := 0.0
var _hits := 0
var _shots := 0
var _clock := 0.0
var _wait := 0.0
var _values := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Ui.box(Color(Ui.BG, 0.78), 10, Color(TestRoom.HOLO, 0.35))
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size.x = 230
	var col := Ui.vbox(6)
	add_child(col)
	col.add_child(Ui.label("DANO", 12, Color(TestRoom.HOLO, 0.9), true))
	_values["dps"] = _row(col, "DPS (3 s)", 26)
	_values["best"] = _row(col, "Melhor DPS")
	_values["ttk"] = _row(col, "100 de vida em")
	_values["total"] = _row(col, "Dano total")
	_values["big"] = _row(col, "Maior golpe")
	_values["hits"] = _row(col, "Tiros / golpes")
	col.add_child(Ui.gap(2))
	col.add_child(Ui.label("Z  zerar   ·   B  cartas e mestra", 12, Ui.MUTED))
	reset()


func _row(col: VBoxContainer, title: String, size := 17) -> Label:
	var row := Ui.hbox(8)
	col.add_child(row)
	row.add_child(Ui.label(title, 14, Ui.MUTED))
	row.add_child(Ui.spacer())
	var value := Ui.label("", size, Ui.TEXT, true)
	row.add_child(value)
	return value


func reset() -> void:
	_events.clear()
	_total = 0.0
	_best_dps = 0.0
	_biggest = 0.0
	_hits = 0
	_shots = 0
	_refresh()


func add_damage(amount: float, _lethal := false) -> void:
	_events.append([_clock, amount])
	_total += amount
	_biggest = maxf(_biggest, amount)
	_hits += 1


func add_shot() -> void:
	_shots += 1


func _process(delta: float) -> void:
	_clock += delta
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH
	_refresh()


func _refresh() -> void:
	while not _events.is_empty() and _events[0][0] < _clock - WINDOW:
		_events.pop_front()
	var sum := 0.0
	for e in _events:
		sum += e[1]
	var dps := sum / WINDOW
	_best_dps = maxf(_best_dps, dps)
	_values["dps"].text = "%.0f" % dps
	_values["best"].text = "%.0f" % _best_dps
	_values["ttk"].text = "%.1f s" % (100.0 / _best_dps) if _best_dps > 0.0 else "-"
	_values["total"].text = "%.0f" % _total
	_values["big"].text = "%.0f" % _biggest
	_values["hits"].text = "%d / %d" % [_shots, _hits]
