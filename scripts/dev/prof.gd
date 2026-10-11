class_name Prof
## Cronômetro de travadas (2026-10-10, bloco 4 do check-up: achar o que causa os quadros
## de 50 a 180 ms na luta pesada). Desligado por padrão; "--cronometro" na linha de comando
## liga (autoteste ou check-up). Com ele desligado, cada ponto cronometrado custa só um
## "if Prof.enabled".
##
## Uso: t = Prof.now() ... Prof.lap("nome", t). Os pontos de primeiro nível (laços do
## motor: física do jogador, da bala, quadro da HUD...) somam no quadro; os aninhados
## (nested = true: bot pensando dentro da física do jogador, explosão dentro da bala) só
## entram na tabela. frame_end() é chamado uma vez por quadro e guarda os quadros lentos
## com o que havia neles; o que sobra do quadro sem dono é "fora dos scripts" (física do
## motor, desenho, criar e apagar nós no fim do quadro).

static var enabled := false
const SLOW_CALL_MS := 10.0    # chamada única acima disto é registrada
const SLOW_FRAME_MS := 50.0   # quadro acima disto é registrado
const KEEP := 12              # quantos registros de cada tipo o relatório mostra

static var _totals := {}          # nome -> [chamadas, total us, pior us]
static var _frame := {}           # nome -> us neste quadro (só primeiro nível)
static var _slow_calls: Array = []    # [ms, nome, segundos desde o começo]
static var _slow_frames: Array = []   # [ms, passos de física, {nome: us}, balas]
static var _last_frame := 0
static var _last_phys := 0
static var _frames := 0
static var _start := 0
static var _fight_start := 0      # começo da luta atual (us)
static var _counts := {}          # nome -> vezes neste quadro (Prof.count)
static var _counts_prev := {}     # as do quadro anterior: o desenho dele cai no quadro seguinte


static func now() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func lap(label: String, t0: int, nested := false) -> void:
	if not enabled:
		return
	var us := Time.get_ticks_usec() - t0
	var e: Array = _totals.get(label, [0, 0, 0])
	e[0] += 1
	e[1] += us
	e[2] = maxi(e[2], us)
	_totals[label] = e
	if not nested:
		_frame[label] = _frame.get(label, 0) + us
	if us >= SLOW_CALL_MS * 1000.0:
		_slow_calls.append([us / 1000.0, label, (Time.get_ticks_usec() - _start) / 1e6])


## Conta um acontecimento (um clarão nasceu...) para mostrar nos quadros lentos.
static func count(label: String) -> void:
	if enabled:
		_counts[label] = _counts.get(label, 0) + 1


## Uma vez por quadro (match._process). Mede o quadro inteiro pelo relógio. Fora da luta
## (troca de rodada, que monta a arena: bloco 1) o quadro não conta.
static func frame_end(bullets: int, counting: bool) -> void:
	if not enabled:
		return
	var t := Time.get_ticks_usec()
	var phys := Engine.get_physics_frames()
	if _start == 0:
		_start = t
	if not counting:
		_last_frame = 0
		_fight_start = 0
		_frame.clear()
		_counts.clear()
		_counts_prev.clear()
		return
	if _fight_start == 0:
		_fight_start = t
	if _last_frame != 0:
		_frames += 1
		var ms := (t - _last_frame) / 1000.0
		if ms >= SLOW_FRAME_MS:
			var seen := _counts_prev.duplicate()
			for k in _counts:
				seen[k] = seen.get(k, 0) + _counts[k]
			_slow_frames.append([ms, phys - _last_phys, _frame.duplicate(), bullets,
				(t - _fight_start) / 1e6, seen])
	_last_frame = t
	_last_phys = phys
	_frame.clear()
	_counts_prev = _counts.duplicate()
	_counts.clear()


static func reset() -> void:
	_totals.clear()
	_frame.clear()
	_slow_calls.clear()
	_slow_frames.clear()
	_last_frame = 0
	_frames = 0
	_start = 0


static func report() -> PackedStringArray:
	var out := PackedStringArray()
	if not enabled:
		return out
	out.append("cronômetro: %d quadros, %d acima de %d ms, %d chamadas acima de %d ms" % [
		_frames, _slow_frames.size(), SLOW_FRAME_MS, _slow_calls.size(), SLOW_CALL_MS])
	var names := _totals.keys()
	names.sort_custom(func(a, b): return _totals[a][1] > _totals[b][1])
	out.append("  %-26s %9s %10s %9s %9s" % ["parte", "chamadas", "total ms", "média us", "pior ms"])
	for n in names:
		var e: Array = _totals[n]
		out.append("  %-26s %9d %10.1f %9.1f %9.1f" % [n, e[0], e[1] / 1000.0, float(e[1]) / maxi(1, e[0]), e[2] / 1000.0])
	_slow_calls.sort_custom(func(a, b): return a[0] > b[0])
	if not _slow_calls.is_empty():
		out.append("chamadas lentas (as %d piores):" % mini(KEEP, _slow_calls.size()))
		for c in _slow_calls.slice(0, KEEP):
			out.append("  %6.1f ms  %s  (aos %.1f s)" % [c[0], c[1], c[2]])
	_slow_frames.sort_custom(func(a, b): return a[0] > b[0])
	if not _slow_frames.is_empty():
		out.append("quadros lentos (os %d piores):" % mini(KEEP, _slow_frames.size()))
		for f in _slow_frames.slice(0, KEEP):
			var parts: Dictionary = f[2]
			var keys := parts.keys()
			keys.sort_custom(func(a, b): return parts[a] > parts[b])
			var known := 0
			var top := PackedStringArray()
			for k in keys:
				known += parts[k]
			for k in keys.slice(0, 4):
				top.append("%s %.1f" % [k, parts[k] / 1000.0])
			out.append("  %6.1f ms  aos %4.1f s da luta  %d passos  %d balas  scripts %.1f  fora %.1f  nasceram %s  |  %s" % [
				f[0], f[4], f[1], f[3], known / 1000.0, f[0] - known / 1000.0, str(f[5]), ", ".join(top)])
		# Todos os quadros lentos em ordem de tempo: concentrados no começo = primeira vez.
		var when: Array = _slow_frames.map(func(f): return snappedf(f[4], 0.1))
		when.sort()
		out.append("segundos da luta com quadro lento: %s" % str(when))
	return out
