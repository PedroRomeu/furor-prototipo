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
	{"id": "ffa", "name": "Free for all", "desc": "Last one standing wins the round. Whoever dies picks a card.",
		"players": "2 to 4 players", "min": 2, "max": 4},
	{"id": "teams", "name": "Teams", "desc": "Two teams of 2 (2v2). The team with someone standing wins; the losing team picks cards.",
		"players": "4 players", "min": 4, "max": 4},
	{"id": "duels", "name": "Duels", "desc": "1v1 in rotation. The winner stays; the loser loses a life and gets a card.",
		"players": "2 to 4 players", "min": 2, "max": 4},
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


## Textos do modo já traduzidos (MODES guarda o inglês).
static func mode_name(id: String) -> String:
	return Lang.t(info(id)["name"])


static func mode_desc(id: String) -> String:
	return Lang.t(info(id)["desc"])


static func players_text(id: String) -> String:
	return Lang.t(info(id)["players"])


## "" se dá para jogar com essa quantidade de jogadores; senão, o motivo.
static func blocked_reason(id: String, players: int) -> String:
	var m := info(id)
	if players < m["min"] or players > m["max"]:
		return Lang.t("Needs %s") % Lang.t(m["players"])
	return ""


## Texto curto do modo com as opções ("Duels · 3 lives").
static func label(id: String, lives: int) -> String:
	return Lang.t("%s  ·  %d lives") % [mode_name(id), lives] if id == "duels" else mode_name(id)


## Textos de MODES para a ferramenta de tradução (scenes/dev/i18n.tscn).
static func i18n_strings() -> Array:
	var out := []
	for m in MODES:
		for key in ["name", "desc", "players"]:
			out.append([m[key], "", "scripts/game_modes.gd"])
	return out
