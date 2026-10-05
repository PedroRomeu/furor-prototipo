class_name GameModes
extends RefCounted
## Modos de jogo (2026-10-05, pedido do usuário). Um modo novo é uma entrada a mais em
## MODES; a tela de escolha (ModePicker), a sala e a partida leem daqui.
## - ffa: cada um por si, o último de pé vence a rodada.
## - teams: 2x2, o time com alguém de pé vence (só com 4).
## - duels: Duelos (ideia do usuário): 1x1 em rodízio com vidas. Os dois primeiros da fila
##   duelam; o vencedor fica e o perdedor perde uma vida e vai para o fim da fila (o
##   vencedor fica sem limite, escolha do usuário: dá para ver até quando ele aguenta sem
##   ganhar cartas). Quem perde escolhe 1 de 3 cartas, ou 1 de 4 na última vida. Zerou as
##   vidas, está fora; vence quem sobrar. Os outros assistem.

const MODES := [
	{"id": "ffa", "name": "Cada um por si", "desc": "Último de pé vence a rodada. Quem morre escolhe carta.",
		"players": "2 a 4 jogadores", "min": 2, "max": 4},
	{"id": "teams", "name": "2x2", "desc": "Times de 2. Vence o time com alguém de pé; o time que perde escolhe carta.",
		"players": "4 jogadores", "min": 4, "max": 4},
	{"id": "duels", "name": "Duelos", "desc": "1x1 em rodízio. O vencedor fica, quem perde perde uma vida e ganha carta.",
		"players": "2 a 4 jogadores", "min": 2, "max": 4},
]
const LIVES_OPTIONS := [3, 5, 7]
const DEFAULT_LIVES := 3
const LAST_CHANCE_CARDS := 4   # Duelos: na última vida a escolha é entre 4 cartas


static func info(id: String) -> Dictionary:
	for m in MODES:
		if m["id"] == id:
			return m
	return MODES[0]


static func ids() -> Array:
	return MODES.map(func(m): return m["id"])


static func mode_name(id: String) -> String:
	return info(id)["name"]


## "" se dá para jogar com essa quantidade de jogadores; senão, o motivo.
static func blocked_reason(id: String, players: int) -> String:
	var m := info(id)
	if players < m["min"] or players > m["max"]:
		return "Precisa de %s" % m["players"]
	return ""


## Texto curto do modo com as opções ("Duelos · 3 vidas").
static func label(id: String, lives: int) -> String:
	return "%s  ·  %d vidas" % [mode_name(id), lives] if id == "duels" else mode_name(id)
