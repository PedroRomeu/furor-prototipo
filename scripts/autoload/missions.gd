extends Node
## Missões diárias e semanais (2026-10-11; desenho do usuário, números meus aprovados).
## A primeira forma de ganhar moedas. Contam só em partida online, no próprio jogador
## (cada máquina conta o seu); o treino contra bots não conta.
##
## Diárias: 3 sorteadas de DAILY, só moedas, trocam à meia-noite (relógio do PC); 1 troca
## por dia (reroll). Semanais: 3 vagas com recompensa fixa (WEEKLY): a mais difícil dá um
## Pacote de Mestra, a média fichas (3 comuns, 3 raras, 2 épicas, 1 lendária), a leve 800
## moedas; a missão de cada vaga é sorteada da lista dela e todas trocam na segunda às 00h.
## Cumprida, a missão espera o resgate (claim). Salvo em user://missoes.json.
##
## A partida chama begin_match, add(stat, n) a cada evento e, no fim, summary() para o
## aviso com o que andou. Teste: "-- --missoes" conta também fora do online.

signal changed
signal completed(text: String)   # uma missão acabou de ser cumprida (aviso na partida)

const PATH := "user://missoes.json"
const DAILY_COUNT := 3
const REROLLS_PER_DAY := 1

## Eventos contados (add): rodadas jogadas e vencidas, abates, assistências, dano causado,
## balas refletidas, usos da mestra (Q), partidas terminadas em 1º e diárias cumpridas.
const TEXTS := {
	"rounds": "Jogar %d rodadas",
	"round_wins": "Vencer %d rodadas",
	"kills": "Fazer %d abates",
	"assists": "Dar %d assistências",
	"damage": "Causar %d de dano",
	"reflects": "Refletir %d balas com o escudo",
	"master_uses": "Usar a carta mestra %d vezes",
	"match_wins": "Terminar %d partidas em 1º lugar",
	"dailies": "Cumprir %d missões diárias",
}

## id -> [evento, meta, moedas]
const DAILY := {
	"d_rodadas": ["rounds", 10, 50],
	"d_vitorias": ["round_wins", 3, 75],
	"d_abates": ["kills", 6, 75],
	"d_dano": ["damage", 1500, 75],
	"d_reflexos": ["reflects", 8, 75],
	"d_assist": ["assists", 4, 75],
	"d_mestra": ["master_uses", 8, 50],   # só sorteada com mestra ativa equipada
}

## Vagas semanais, da mais difícil para a mais leve: recompensa fixa e a lista da vaga
## (id -> [evento, meta]).
const WEEKLY := [
	{"reward": {"master_pack": 1}, "pool": {
		"s_vitorias": ["round_wins", 20], "s_abates": ["kills", 40], "s_partidas": ["match_wins", 3]}},
	{"reward": {"tokens": {"comum": 3, "raro": 3, "epico": 2, "lendario": 1}}, "pool": {
		"s_dano": ["damage", 10000], "s_reflexos": ["reflects", 50], "s_assist": ["assists", 25]}},
	{"reward": {"coins": 800}, "pool": {
		"s_rodadas": ["rounds", 60], "s_diarias": ["dailies", 10]}},
]

var day_key := ""
var week_key := ""
var dailies: Array = []    # [{id, progress, claimed}]
var weeklies: Array = []   # idem, uma por vaga de WEEKLY
var rerolls := REROLLS_PER_DAY
var _session := {}         # chave "d0"/"s1" -> progresso no começo da partida
var _force := false        # teste: conta fora do online
var _path := PATH          # autoteste: "" (nada em disco; vários processos na mesma máquina)
var tally := {}            # tudo o que contou nesta partida, de todos os eventos (autoteste)


func _ready() -> void:
	_force = "--missoes" in OS.get_cmdline_user_args()
	if "--autotest" in OS.get_cmdline_user_args():
		_path = ""
	_load()
	check_period()


# ---------------------------------------------------------------- consulta

func counting() -> bool:
	return Net.online or _force


static func daily_def(id: String) -> Array:
	return DAILY[id]


static func weekly_def(slot: int, id: String) -> Array:
	return WEEKLY[slot]["pool"][id]


## Texto, meta e recompensa de uma missão ("d", i) ou ("s", i).
func info(kind: String, i: int) -> Dictionary:
	var m: Dictionary = dailies[i] if kind == "d" else weeklies[i]
	var def: Array = daily_def(m["id"]) if kind == "d" else weekly_def(i, m["id"])
	var target: int = def[1]
	return {"text": TEXTS[def[0]].replace("%d", num(target)), "stat": def[0], "target": target,
		"progress": mini(int(m["progress"]), target), "done": int(m["progress"]) >= target,
		"claimed": m["claimed"], "reward": {"coins": def[2]} if kind == "d" else WEEKLY[i]["reward"]}


## Número com ponto nos milhares (10.000), como se escreve em português.
static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Texto curto da recompensa, para a tela.
static func reward_text(reward: Dictionary) -> String:
	if reward.has("coins"):
		return num(reward["coins"]) + " moedas"
	if reward.has("master_pack"):
		return "Pacote de Mestra"
	var parts := []
	for r in Collection.RARITY_ORDER:
		var n: int = reward.get("tokens", {}).get(r, 0)
		if n > 0:
			parts.append("%d %s" % [n, Collection.RARITY_FEM_PLURAL[r] if n > 1 else Collection.RARITY_FEM[r]])
	return "Fichas: " + ", ".join(parts)


## Segundos até as diárias e as semanais trocarem.
func seconds_to_day() -> int:
	var t := Time.get_time_dict_from_system()
	return 86400 - (int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"]))


func seconds_to_week() -> int:
	var weekday: int = Time.get_date_dict_from_system()["weekday"]   # 0 = domingo
	var days_left := (8 - weekday) % 7   # até a próxima segunda (hoje segunda: 7)
	if days_left == 0:
		days_left = 7
	return (days_left - 1) * 86400 + seconds_to_day()


## Missões cumpridas esperando o resgate.
func claimable() -> int:
	var n := 0
	for kind in ["d", "s"]:
		for i in (dailies if kind == "d" else weeklies).size():
			var inf := info(kind, i)
			if inf["done"] and not inf["claimed"]:
				n += 1
	return n


func can_reroll(i: int) -> bool:
	return rerolls > 0 and not dailies[i]["claimed"] and int(dailies[i]["progress"]) == 0


# ---------------------------------------------------------------- partida

## Começo de uma partida: guarda o progresso de agora para o resumo do fim.
func begin_match() -> void:
	check_period()
	_session = {}
	tally = {}
	for i in dailies.size():
		_session["d%d" % i] = int(dailies[i]["progress"])
	for i in weeklies.size():
		_session["s%d" % i] = int(weeklies[i]["progress"])


## Evento da partida. Só conta online (ou com --missoes).
func add(stat: String, amount: int = 1) -> void:
	if amount <= 0 or not counting():
		return
	tally[stat] = int(tally.get(stat, 0)) + amount
	check_period()
	var dirty := false
	for i in dailies.size():
		dirty = _bump("d", i, stat, amount) or dirty
	for i in weeklies.size():
		dirty = _bump("s", i, stat, amount) or dirty
	if dirty:
		_save()


## Fim da partida: as missões que andaram desde begin_match, com antes e depois.
func summary() -> Array:
	var out := []
	for kind in ["d", "s"]:
		var list: Array = dailies if kind == "d" else weeklies
		for i in list.size():
			var key := "%s%d" % [kind, i]
			if not _session.has(key):
				continue
			var inf := info(kind, i)
			var before := mini(int(_session[key]), inf["target"])
			if inf["progress"] > before:
				inf["before"] = before
				inf["weekly"] = kind == "s"
				out.append(inf)
	_session = {}
	return out


# ---------------------------------------------------------------- ações

## Resgata a recompensa de uma missão cumprida.
func claim(kind: String, i: int) -> bool:
	check_period()
	var list: Array = dailies if kind == "d" else weeklies
	if i < 0 or i >= list.size():
		return false
	var inf := info(kind, i)
	if not inf["done"] or inf["claimed"]:
		return false
	list[i]["claimed"] = true
	var r: Dictionary = inf["reward"]
	if r.has("coins"):
		Collection.add_coins(r["coins"])
	if r.has("tokens"):
		Collection.add_tokens(r["tokens"])
	if r.has("master_pack"):
		Collection.add_master_pack()
	_save()
	return true


## Troca uma diária (sem progresso e não resgatada) por outra sorteada, 1 vez por dia.
func reroll(i: int) -> bool:
	check_period()
	if not can_reroll(i):
		return false
	var taken := dailies.map(func(m): return m["id"])
	var pool := _daily_pool().filter(func(id): return not id in taken)
	if pool.is_empty():
		return false
	dailies[i] = {"id": pool.pick_random(), "progress": 0, "claimed": false}
	rerolls -= 1
	_save()
	return true


## Dia ou semana virou: sorteia de novo (o que não foi resgatado se perde, como nos jogos
## do gênero).
func check_period() -> void:
	var d := _day_key()
	var w := _week_key()
	var dirty := false
	if d != day_key or dailies.size() != DAILY_COUNT:
		day_key = d
		dailies = []
		var pool := _daily_pool()
		pool.shuffle()
		for id in pool.slice(0, DAILY_COUNT):
			dailies.append({"id": id, "progress": 0, "claimed": false})
		rerolls = REROLLS_PER_DAY
		dirty = true
	if w != week_key or weeklies.size() != WEEKLY.size():
		week_key = w
		weeklies = []
		for slot in WEEKLY:
			weeklies.append({"id": slot["pool"].keys().pick_random(), "progress": 0, "claimed": false})
		dirty = true
	if dirty:
		_save()


# ---------------------------------------------------------------- interno

func _bump(kind: String, i: int, stat: String, amount: int) -> bool:
	var m: Dictionary = dailies[i] if kind == "d" else weeklies[i]
	var inf := info(kind, i)
	if inf["stat"] != stat or inf["done"]:
		return false
	m["progress"] = mini(int(m["progress"]) + amount, inf["target"])
	if int(m["progress"]) >= inf["target"]:
		completed.emit(inf["text"])
		if kind == "d":
			add("dailies")
	return true


## Diárias possíveis: "usar a mestra" só com mestra ativa (Q) no baralho equipado.
func _daily_pool() -> Array:
	var master: String = GameState.player_master
	var active: bool = master != "" and CardDB.CARDS.get(master, {}).has("cooldown")
	return DAILY.keys().filter(func(id): return id != "d_mestra" or active)


func _day_key() -> String:
	return Time.get_date_string_from_system()


## Semana: o dia (contado desde 1970) da segunda-feira desta semana, no relógio local.
func _week_key() -> String:
	var date := Time.get_date_dict_from_system()
	var days := int(Time.get_unix_time_from_datetime_dict({"year": date["year"], "month": date["month"],
		"day": date["day"], "hour": 0, "minute": 0, "second": 0}) / 86400)
	return str(days - (int(date["weekday"]) + 6) % 7)


func _load() -> void:
	if _path == "" or not FileAccess.file_exists(_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	day_key = str(data.get("dia", ""))
	week_key = str(data.get("semana", ""))
	rerolls = int(data.get("trocas", REROLLS_PER_DAY))
	dailies = []
	for m in data.get("diarias", []):
		if typeof(m) == TYPE_DICTIONARY and DAILY.has(m.get("id", "")):
			dailies.append({"id": m["id"], "progress": int(m.get("progress", 0)), "claimed": bool(m.get("claimed", false))})
	weeklies = []
	var saved: Array = data.get("semanais", [])
	for slot in WEEKLY.size():
		if slot >= saved.size() or typeof(saved[slot]) != TYPE_DICTIONARY \
				or not WEEKLY[slot]["pool"].has(saved[slot].get("id", "")):
			weeklies = []   # lista mudou numa versão nova: sorteia de novo
			break
		var m: Dictionary = saved[slot]
		weeklies.append({"id": m["id"], "progress": int(m.get("progress", 0)), "claimed": bool(m.get("claimed", false))})


func _save() -> void:
	if _path == "":
		changed.emit()
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"dia": day_key, "semana": week_key, "trocas": rerolls,
		"diarias": dailies, "semanais": weeklies}, "\t"))
	changed.emit()
