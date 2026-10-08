extends Node
## Coleção do jogador e loja (2026-10-08; desenho do usuário, números meus). Moedas compram
## pacotes (forma principal) e ofertas (3 cartas que trocam a cada 8 h e podem ser
## travadas); cada carta vai até 3 cópias (mestra até 1) e a cópia a mais vira ficha da
## raridade; fichas trocam por uma carta da raridade, à escolha.
##
## TODOS OS NÚMEROS SÃO PROVISÓRIOS: valem para as cartas de hoje e podem mudar com mais
## cartas ou outras estratégias. Nada depende da quantidade de cartas: pacotes, ofertas e
## trocas sorteiam entre as cartas que existirem na raridade (carta nova entra sozinha).
##
## MODO DE TESTE (TEST_MODE): moedas "infinitas" (Repor moedas, Zerar coleção) e a coleção
## ainda não bloqueia nada: os baralhos continuam com todas as cartas (pedido do usuário:
## ninguém perde carta até o sistema estar consolidado). Salvo em user://colecao.json.

signal changed

const TEST_MODE := true
const TEST_COINS := 999999
const PATH := "user://colecao.json"
const RARITY_ORDER := ["comum", "raro", "epico", "lendario", "mitico"]
## Para concordar com "carta" e "ficha" (CardDB.RARITIES tem o masculino: "Raro").
const RARITY_FEM := {"comum": "comum", "raro": "rara", "epico": "épica", "lendario": "lendária", "mitico": "mítica"}
const RARITY_FEM_PLURAL := {"comum": "comuns", "raro": "raras", "epico": "épicas", "lendario": "lendárias", "mitico": "míticas"}

## Deck inicial: 30 cartas, 1 cópia de cada, 6 por grupo, "faz de tudo um pouco":
## 14 comuns, 9 raras, 5 épicas, 2 lendárias. A mestra vem do Pacote de mestra.
const STARTER := [
	"calibre_pesado", "gatilho_leve", "maos_rapidas", "pente_estendido", "cano_duplo", "sortudo",
	"ricochete", "propulsao", "veneno", "congelante", "explosiva", "teleguiada",
	"escudo_firme", "reflexos", "restauracao", "onda_de_choque", "couraca", "adrenalina",
	"vigor", "tanque", "regeneracao", "blindado", "gigantao", "fenix",
	"botas_leves", "dash_longo", "pena", "pulo_duplo", "planador", "pulo_foguete",
]

## Pacotes. odds: chance de cada raridade nas cartas comuns do pacote; last: a última
## carta, a garantida. Simulado (só Avançado, com troca de fichas): 50% da coleção em ~26
## pacotes, 90% em ~74, todas as mestras em ~230.
const PACKS := {
	"basico": {"name": "Pacote Básico", "cards": 5, "price": 100, "color": Color(0.45, 0.65, 1.0),
		"promise": "1 rara ou melhor",
		"odds": {"comum": 0.62, "raro": 0.28, "epico": 0.08, "lendario": 0.017, "mitico": 0.003},
		"last": {"raro": 0.75, "epico": 0.20, "lendario": 0.04, "mitico": 0.01}},
	"avancado": {"name": "Pacote Avançado", "cards": 6, "price": 250, "color": Color(0.78, 0.45, 1.0),
		"promise": "1 épica ou melhor",
		"odds": {"comum": 0.45, "raro": 0.35, "epico": 0.15, "lendario": 0.04, "mitico": 0.01},
		"last": {"epico": 0.75, "lendario": 0.20, "mitico": 0.05}},
	"supremo": {"name": "Pacote Supremo", "cards": 7, "price": 500, "color": Color(1.0, 0.68, 0.15),
		"promise": "1 lendária ou melhor",
		"odds": {"comum": 0.30, "raro": 0.40, "epico": 0.20, "lendario": 0.08, "mitico": 0.02},
		"last": {"lendario": 0.85, "mitico": 0.15}},
	# Só o do começo: 1 carta, sempre uma mestra.
	"mestra": {"name": "Pacote de Mestra", "cards": 1, "price": 0, "color": Color(1.0, 0.32, 0.38),
		"promise": "1 mestra", "odds": {"mitico": 1.0}, "last": {"mitico": 1.0}},
}
const SHOP_PACKS := ["basico", "avancado", "supremo"]

## Ofertas: uma carta de cada uma destas raridades, trocadas a cada OFFER_PERIOD (no mesmo
## horário para todos, contado do relógio do sistema). Travada, a vaga não troca.
const OFFER_RARITIES := ["epico", "lendario", "mitico"]
const OFFER_PRICES := {"epico": 300, "lendario": 700, "mitico": 1500}
const OFFER_PERIOD := 8 * 3600

## Fichas por carta na troca (a cópia além do máximo vira 1 ficha da raridade).
const TOKEN_RATES := {"comum": 5, "raro": 5, "epico": 4, "lendario": 3, "mitico": 2}

var coins := 0
var copies := {}        # id -> cópias
var tokens := {}        # raridade -> fichas
var master_pack := false   # Pacote de Mestra inicial ainda fechado
var offers: Array = []  # [{rarity, id, locked, bought}]
var offer_window := -1


func _ready() -> void:
	_load()
	refresh_offers()


# ---------------------------------------------------------------- consulta

func has_card(id: String) -> int:
	return copies.get(id, 0)


func max_copies(id: String) -> int:
	return 1 if CardDB.is_master(id) else CardDB.MAX_COPIES


func is_full(id: String) -> bool:
	return has_card(id) >= max_copies(id)


static func rarity_of(id: String) -> String:
	return CardDB.CARDS[id]["rarity"]


## Todas as cartas da raridade (mítica = mestras), as de hoje e as que entrarem depois.
static func ids_of(rarity: String) -> Array:
	return CardDB.CARDS.keys().filter(func(id): return CardDB.CARDS[id]["rarity"] == rarity)


## Quanto da coleção você tem (cópias contadas até o máximo de cada carta).
func progress() -> Vector2i:
	var have := 0
	var total := 0
	for id in CardDB.CARDS:
		have += mini(has_card(id), max_copies(id))
		total += max_copies(id)
	return Vector2i(have, total)


func seconds_to_rotation() -> int:
	var now := int(Time.get_unix_time_from_system())
	return OFFER_PERIOD - now % OFFER_PERIOD


# ---------------------------------------------------------------- ações

## Abre um pacote: cobra e devolve as cartas da mais comum para a mais rara (a revelação
## guarda as melhores para o fim). Cada uma: {id, rarity, copy (cópias depois), new, token}.
func open_pack(pack_id: String) -> Array:
	var pack: Dictionary = PACKS[pack_id]
	if pack_id == "mestra":
		if not master_pack:
			return []
		master_pack = false
	elif coins < pack["price"]:
		return []
	else:
		coins -= pack["price"]
	var results := []
	for i in pack["cards"]:
		var odds: Dictionary = pack["last"] if i == pack["cards"] - 1 else pack["odds"]
		var rarity := _roll(odds)
		var pool := ids_of(rarity)
		if pool.is_empty():
			continue
		results.append(_give(pool.pick_random()))
	results.sort_custom(func(a, b): return RARITY_ORDER.find(a["rarity"]) < RARITY_ORDER.find(b["rarity"]))
	_save()
	return results


func buy_offer(slot: int) -> bool:
	var o: Dictionary = offers[slot]
	var price: int = OFFER_PRICES[o["rarity"]]
	if o["id"] == "" or o["bought"] or coins < price or is_full(o["id"]):
		return false
	coins -= price
	_give(o["id"])
	o["bought"] = true
	o["locked"] = false
	_save()
	return true


func toggle_lock(slot: int) -> void:
	var o: Dictionary = offers[slot]
	if o["id"] == "" or o["bought"]:
		return
	o["locked"] = not o["locked"]
	_save()


## Troca fichas da raridade por uma cópia da carta escolhida.
func exchange(id: String) -> bool:
	var rarity := rarity_of(id)
	if tokens.get(rarity, 0) < TOKEN_RATES[rarity] or is_full(id):
		return false
	tokens[rarity] -= TOKEN_RATES[rarity]
	copies[id] = has_card(id) + 1
	_save()
	return true


## Na virada das 8 h: as vagas não travadas sorteiam outra carta (das que você não completou).
func refresh_offers() -> void:
	var window := int(Time.get_unix_time_from_system()) / OFFER_PERIOD
	if window == offer_window and offers.size() == OFFER_RARITIES.size():
		return
	var old := offers
	offers = []
	for i in OFFER_RARITIES.size():
		var keep: bool = i < old.size() and old[i]["locked"] and old[i]["id"] != ""
		offers.append(old[i] if keep else _roll_offer(OFFER_RARITIES[i]))
	offer_window = window
	_save()


# ---------------------------------------------------------------- teste

func test_refill() -> void:
	coins = TEST_COINS
	_save()


## Volta ao começo: deck inicial, Pacote de Mestra fechado, sem fichas, ofertas novas.
func test_reset() -> void:
	_start()
	_save()


# ---------------------------------------------------------------- interno

func _give(id: String) -> Dictionary:
	var rarity := rarity_of(id)
	var r := {"id": id, "rarity": rarity, "new": has_card(id) == 0, "token": false}
	if is_full(id):
		tokens[rarity] = tokens.get(rarity, 0) + 1
		r["token"] = true
	else:
		copies[id] = has_card(id) + 1
	r["copy"] = has_card(id)
	return r


func _roll(odds: Dictionary) -> String:
	var x := randf()
	var acc := 0.0
	var last := ""
	for k in odds:
		acc += odds[k]
		last = k
		if x < acc:
			return k
	return last


func _roll_offer(rarity: String) -> Dictionary:
	var pool := ids_of(rarity).filter(func(id): return not is_full(id))
	return {"rarity": rarity, "id": pool.pick_random() if not pool.is_empty() else "", "locked": false, "bought": false}


func _start() -> void:
	copies = {}
	for id in STARTER:
		if CardDB.CARDS.has(id):
			copies[id] = 1
	tokens = {}
	for r in RARITY_ORDER:
		tokens[r] = 0
	coins = TEST_COINS if TEST_MODE else 0
	master_pack = true
	offers = []
	offer_window = -1
	refresh_offers()


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		_start()
		_save()
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		_start()
		return
	coins = int(data.get("moedas", 0))
	copies = {}
	var saved: Dictionary = data.get("copias", {})
	for id in saved:
		if CardDB.CARDS.has(id):   # carta que saiu do jogo some da coleção
			copies[id] = int(saved[id])
	tokens = {}
	var t: Dictionary = data.get("fichas", {})
	for r in RARITY_ORDER:
		tokens[r] = int(t.get(r, 0))
	master_pack = bool(data.get("pacote_mestra", false))
	offer_window = int(data.get("janela_ofertas", -1))
	offers = []
	for o in data.get("ofertas", []):
		if typeof(o) == TYPE_DICTIONARY and o.get("rarity", "") in OFFER_RARITIES:
			var id: String = o.get("id", "")
			offers.append({"rarity": o["rarity"], "id": id if CardDB.CARDS.has(id) else "",
				"locked": bool(o.get("locked", false)), "bought": bool(o.get("bought", false))})


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"moedas": coins, "copias": copies, "fichas": tokens,
		"pacote_mestra": master_pack, "janela_ofertas": offer_window, "ofertas": offers}, "\t"))
	changed.emit()
