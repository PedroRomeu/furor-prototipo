extends Node
## Estado global: baralhos do jogador, regras da partida e mapa de teclas.
##
## O jogador pode ter vários baralhos com nome; o "equipado" é o usado nas partidas.
## Baralho incompleto (menos de CardDB.DECK_MIN cartas) fica salvo, mas não pode ser
## equipado.

const DECKS_PATH := "user://decks.json"
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SENS := 0.0025   # radianos por pixel de mouse
const OLD_DECK_PATH := "user://deck.json"   # versão antiga: um baralho só, sem nome
## A cada tantas rodadas o jogo pergunta se quer continuar ou terminar.
const ROUNDS_PER_BLOCK := 5

## Qualidade trocada (também pelo menu de pausa, com a partida aberta).
signal quality_changed

## [{"name": String, "cards": Array, "master": String}]. "master" é a carta mestra
## (CardDB.MASTERS): uma por baralho, fora da contagem de cartas.
var decks: Array = []
var equipped := 0
## Baralho aberto no editor (índice em decks).
var editing := 0
## As cartas do baralho equipado (ou o padrão, se ele estiver incompleto).
var player_deck: Array:
	get = _get_player_deck
## A carta mestra do baralho equipado.
var player_master: String:
	get = _get_player_master
## Sensibilidade do mouse (ajustada no menu, salva em settings.cfg).
var mouse_sens := DEFAULT_SENS
## Nome que os outros veem online (vazio: "Jogador 2" etc., pela vaga na sala).
var nick := ""
const NICK_MAX := 16
## Visual escolhido em Personalizar: personagem (Player.SKINS) e arma (Player.GUN_SKINS).
var skin := "male-b"
var gun_skin := "blaster-b"
## Quantos bots no treino: 1 a 3.
var bot_count := 1
## Treino com 3 bots em 2x2 (você e um bot aliado contra dois). Online quem decide é a
## sala (Net.teams). Teste: "-- --autotest --solo --bots=3 --2x2".
var team_mode := false
## Saiu da sala online para mexer nos baralhos: o menu volta direto para a sala.
var from_lobby := false
## Times: nomes e cores (Azul e Vermelho), duas cores por time, uma para cada jogador.
const TEAM_NAMES := ["Azul", "Vermelho"]
const TEAM_COLORS := [[Color(0.25, 0.55, 1.0), Color(0.3, 0.85, 0.95)],
	[Color(1.0, 0.3, 0.25), Color(1.0, 0.62, 0.2)]]
## Cada um por si: cor de cada vaga (a mesma na sala, no chat e na partida).
const PLAYER_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.35, 0.25), Color(0.35, 0.85, 0.35),
	Color(1.0, 0.8, 0.2)]


## Cor do jogador: pela vaga (cada um por si) ou pelo time e a ordem dentro dele (2x2).
static func player_color(slot: int, team := -1) -> Color:
	if team >= 0:
		return TEAM_COLORS[team][slot % 2]
	return PLAYER_COLORS[slot % PLAYER_COLORS.size()]

## Qualidade gráfica: 0 baixa, 1 média, 2 alta (ver match.gd, _apply_quality).
var quality := 1
## Contador de quadros por segundo no canto da tela.
var show_fps := false
## Rodando com "-- --autotest", os dois lados são bots e o jogo fecha ao fim da partida.
var autotest := false
## Menu de pausa aberto na partida: o jogador desta máquina não recebe comandos.
var menu_open := false
## Campo do chat aberto na partida: o personagem fica parado enquanto a pessoa digita.
var chat_open := false
## Teste: "-- --autotest --mestra=bastiao" troca a carta mestra deste processo.
var test_master := ""
## Teste: "--cartas=metralhadora,explosiva" dá essas cartas a todos no começo (mede desempenho).
var test_cards: Array = []
## Teste: "--tema=2" força o tema das arenas (índice em ArenaTheme.THEMES).
var test_theme := -1


func _ready() -> void:
	randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mestra=") and CardDB.is_master(arg.trim_prefix("--mestra=")):
			test_master = arg.trim_prefix("--mestra=")
		if arg.begins_with("--cartas="):
			test_cards = Array(arg.trim_prefix("--cartas=").split(",")).filter(func(c): return CardDB.CARDS.has(c))
		if arg.begins_with("--tema="):
			test_theme = int(arg.trim_prefix("--tema="))
	for n in [2, 3]:
		if "--bots=%d" % n in OS.get_cmdline_user_args():
			bot_count = n
	team_mode = "--2x2" in OS.get_cmdline_user_args()
	_register_inputs()
	load_decks()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sens = cfg.get_value("controles", "sensibilidade", DEFAULT_SENS)
		quality = cfg.get_value("video", "qualidade", 1)
		show_fps = cfg.get_value("video", "mostrar_fps", false)
		nick = clean_nick(cfg.get_value("jogador", "nome", ""))
		var saved := Player.clean_look({"skin": cfg.get_value("jogador", "skin", skin),
			"gun": cfg.get_value("jogador", "arma", gun_skin)})
		skin = saved["skin"] if saved["skin"] != "" else skin
		gun_skin = saved["gun"] if saved["gun"] != "" else gun_skin
	# Teste: "-- --autotest --nome=Fulano" troca o nome só neste processo (não salva), e
	# "--visual=female-a,blaster-k" o personagem e a arma.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nome="):
			nick = clean_nick(arg.trim_prefix("--nome="))
		if arg.begins_with("--visual="):
			var parts := arg.trim_prefix("--visual=").split(",")
			var look := Player.clean_look({"skin": parts[0], "gun": parts[1] if parts.size() > 1 else ""})
			skin = look["skin"] if look["skin"] != "" else skin
			gun_skin = look["gun"] if look["gun"] != "" else gun_skin


## O anfitrião começou a partida: vale de qualquer tela (menu, Baralhos ou editor).
func go_to_match() -> void:
	bot_count = 0
	from_lobby = false
	get_tree().change_scene_to_file("res://scenes/match.tscn")


func set_mouse_sens(value: float) -> void:
	mouse_sens = value
	_save_setting("controles", "sensibilidade", value)


func look() -> Dictionary:
	return {"skin": skin, "gun": gun_skin}


func set_look(p_skin: String, p_gun: String) -> void:
	if p_skin in Player.skin_ids():
		skin = p_skin
		_save_setting("jogador", "skin", skin)
	if p_gun in Player.gun_ids():
		gun_skin = p_gun
		_save_setting("jogador", "arma", gun_skin)


func set_nick(value: String) -> void:
	nick = clean_nick(value)
	_save_setting("jogador", "nome", nick)


static func clean_nick(value: String) -> String:
	return value.strip_edges().left(NICK_MAX).strip_edges()


func set_quality(value: int) -> void:
	quality = value
	_save_setting("video", "qualidade", value)
	quality_changed.emit()


func set_show_fps(value: bool) -> void:
	show_fps = value
	_save_setting("video", "mostrar_fps", value)


func _save_setting(section: String, key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)


func _get_player_deck() -> Array:
	if equipped < decks.size() and CardDB.is_valid_deck(decks[equipped]["cards"]):
		return decks[equipped]["cards"].duplicate()
	return CardDB.template_deck(0)


func _get_player_master() -> String:
	if test_master != "":
		return test_master
	return decks[equipped]["master"] if equipped < decks.size() else CardDB.MASTER_DEFAULT


func equipped_name() -> String:
	return decks[equipped]["name"] if equipped < decks.size() else ""


func load_decks() -> void:
	decks.clear()
	equipped = 0
	if FileAccess.file_exists(DECKS_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(DECKS_PATH))
		if data is Dictionary and data.get("decks") is Array:
			for d in data["decks"]:
				if d is Dictionary and d.get("cards") is Array:
					var master := str(d.get("master", ""))
					master = CardDB.MASTER_REPLACED.get(master, master)
					if not CardDB.is_master(master):
						master = CardDB.MASTER_DEFAULT   # baralho de antes das cartas mestras
					decks.append({"name": str(d.get("name", "Baralho")), "cards": _known(d["cards"]), "master": master})
			equipped = int(data.get("equipped", 0))
	elif FileAccess.file_exists(OLD_DECK_PATH):
		var old = JSON.parse_string(FileAccess.get_file_as_string(OLD_DECK_PATH))
		if old is Array:
			decks.append({"name": "Meu baralho", "cards": _known(old), "master": CardDB.MASTER_DEFAULT})
	if decks.is_empty():
		decks.append({"name": "Equilibrado", "cards": CardDB.template_deck(0), "master": CardDB.template_master(0)})
	if equipped < 0 or equipped >= decks.size() or not CardDB.is_valid_deck(decks[equipped]["cards"]):
		equipped = maxi(0, decks.find_custom(func(d): return CardDB.is_valid_deck(d["cards"])))


## Tira cartas que não existem mais (renomeadas ou removidas numa versão nova).
func _known(cards: Array) -> Array:
	var out: Array = []
	for id in cards:
		if CardDB.CARDS.has(id) and not CardDB.is_master(id) and out.count(id) < CardDB.MAX_COPIES and out.size() < CardDB.DECK_MAX:
			out.append(id)
	return out


func save_decks() -> void:
	var f := FileAccess.open(DECKS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"equipped": equipped, "decks": decks}, "	"))


func add_deck(deck_name: String, cards: Array, master: String) -> int:
	decks.append({"name": deck_name, "cards": cards.duplicate(), "master": master})
	save_decks()
	return decks.size() - 1


func delete_deck(index: int) -> void:
	if decks.size() <= 1:
		return
	decks.remove_at(index)
	if equipped == index or equipped >= decks.size():
		equipped = maxi(0, decks.find_custom(func(d): return CardDB.is_valid_deck(d["cards"])))
	elif equipped > index:
		equipped -= 1
	save_decks()


func equip(index: int) -> void:
	if CardDB.is_valid_deck(decks[index]["cards"]):
		equipped = index
		save_decks()


## Nome livre do tipo "Baralho 3".
func new_deck_name() -> String:
	var n := decks.size() + 1
	while decks.any(func(d): return d["name"] == "Baralho %d" % n):
		n += 1
	return "Baralho %d" % n


# ---------------------------------------------------------------- teclas
# Cada ação tem até 2 teclas (ou botões do mouse), trocáveis em Configurações e salvas em
# settings.cfg, seção "teclas". Código de uma tecla: "k:<physical_keycode>" ou
# "m:<botão do mouse>"; "" é a vaga vazia. As ações são registradas em código, por isso
# não aparecem no Input Map do editor do Godot.

## Ordem e nomes na tela de controles.
const ACTIONS := [
	["move_forward", "Frente"], ["move_back", "Trás"], ["move_left", "Esquerda"], ["move_right", "Direita"],
	["jump", "Pular"], ["shoot", "Atirar"], ["shield", "Escudo"], ["reload", "Recarregar"],
	["master", "Carta mestra"], ["dash", "Dash"], ["crouch", "Agachar / deslizar"],
	["scoreboard", "Placar e cartas (segurar)"], ["chat", "Chat (online)"],
]
## Ctrl é as duas coisas: dash ao apertar e agachar/deslizar enquanto segura. Por isso a
## mesma tecla nessas duas ações não conta como conflito.
const SHARED_OK := [["dash", "crouch"]]
const DEFAULT_BINDS := {
	"move_forward": ["k:%d" % KEY_W, ""],
	"move_back": ["k:%d" % KEY_S, ""],
	"move_left": ["k:%d" % KEY_A, ""],
	"move_right": ["k:%d" % KEY_D, ""],
	"jump": ["k:%d" % KEY_SPACE, ""],
	"shoot": ["m:%d" % MOUSE_BUTTON_LEFT, ""],
	"shield": ["k:%d" % KEY_E, "m:%d" % MOUSE_BUTTON_RIGHT],
	"reload": ["k:%d" % KEY_R, ""],
	"master": ["k:%d" % KEY_Q, ""],
	"dash": ["k:%d" % KEY_CTRL, "k:%d" % KEY_SHIFT],
	"crouch": ["k:%d" % KEY_CTRL, "k:%d" % KEY_C],
	"scoreboard": ["k:%d" % KEY_TAB, ""],
	"chat": ["k:%d" % KEY_ENTER, "k:%d" % KEY_KP_ENTER],
}
const KEY_NAMES := {
	KEY_SPACE: "Espaço", KEY_CTRL: "Ctrl", KEY_SHIFT: "Shift", KEY_ALT: "Alt", KEY_TAB: "Tab",
	KEY_CAPSLOCK: "Caps Lock", KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter (num.)", KEY_BACKSPACE: "Backspace",
	KEY_UP: "Seta cima", KEY_DOWN: "Seta baixo", KEY_LEFT: "Seta esq.", KEY_RIGHT: "Seta dir.",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Clique esq.", MOUSE_BUTTON_RIGHT: "Clique dir.", MOUSE_BUTTON_MIDDLE: "Botão do meio",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5",
	MOUSE_BUTTON_WHEEL_UP: "Roda p/ cima", MOUSE_BUTTON_WHEEL_DOWN: "Roda p/ baixo",
}

## ação -> [código, código]
var binds := {}


func _register_inputs() -> void:
	binds = DEFAULT_BINDS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section("teclas"):
		for action in binds:
			var saved = cfg.get_value("teclas", action) if cfg.has_section_key("teclas", action) else null
			if saved is Array and saved.size() == 2:
				binds[action] = [str(saved[0]), str(saved[1])]
	_apply_binds()


func _apply_binds() -> void:
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for code in binds[action]:
			var ev := _event(code)
			if ev:
				InputMap.action_add_event(action, ev)


## Troca a tecla de uma vaga (0 ou 1). code "" esvazia a vaga.
func set_bind(action: String, slot: int, code: String) -> void:
	binds[action][slot] = code
	_apply_binds()
	_save_setting("teclas", action, binds[action])


func reset_binds() -> void:
	binds = DEFAULT_BINDS.duplicate(true)
	_apply_binds()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if cfg.has_section("teclas"):
		cfg.erase_section("teclas")
	cfg.save(SETTINGS_PATH)


## Código de um evento de tecla ou mouse ("" se não servir).
static func code_of(event: InputEvent) -> String:
	if event is InputEventKey:
		var k: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "k:%d" % k if k != KEY_NONE else ""
	if event is InputEventMouseButton:
		return "m:%d" % event.button_index
	return ""


static func _event(code: String) -> InputEvent:
	if code.begins_with("k:"):
		var ev := InputEventKey.new()
		ev.physical_keycode = int(code.substr(2)) as Key
		return ev
	if code.begins_with("m:"):
		var mb := InputEventMouseButton.new()
		mb.button_index = int(code.substr(2)) as MouseButton
		return mb
	return null


## Nome curto da tecla para a tela ("Ctrl", "Clique dir.", "E").
static func code_text(code: String) -> String:
	if code.begins_with("m:"):
		var b := int(code.substr(2))
		return MOUSE_NAMES.get(b, "Mouse %d" % b)
	if code.begins_with("k:"):
		var k := int(code.substr(2)) as Key
		if KEY_NAMES.has(k):
			return KEY_NAMES[k]
		# Letra conforme o layout do teclado (a tecla é guardada pela posição física).
		var label := k
		if DisplayServer.get_name() != "headless":
			label = DisplayServer.keyboard_get_label_from_physical(k)
		return OS.get_keycode_string(label if label != KEY_NONE else k)
	return ""


## Teclas de uma ação para o HUD: "Ctrl", "E / Clique dir.".
func key_text(action: String, both := false) -> String:
	var names: Array = binds.get(action, []).filter(func(c): return c != "").map(code_text)
	if names.is_empty():
		return "sem tecla"
	return " / ".join(names) if both else names[0]


## Outras ações que usam a mesma tecla (fora os pares de SHARED_OK).
func conflicts(action: String, code: String) -> Array:
	var out := []
	if code == "":
		return out
	for other in binds:
		if other == action or not code in binds[other]:
			continue
		if SHARED_OK.any(func(pair): return action in pair and other in pair):
			continue
		out.append(other)
	return out


func action_label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action
