extends Node
## Conexão em rede (ENet, sobre UDP). Um jogador cria a sala, os outros entram pelo IP.
## A sala cabe até MAX_GUESTS convidados; o host começa quando quiser, com quem estiver
## na sala (2 a 4 jogadores, cada um por si). Com 4, o host pode escolher 2x2 e arrumar
## os times (team_mode, teams). Os convidados falam com o host, e o host repassa as mensagens entre
## eles (o ENet do Godot faz esse repasse sozinho).
##
## Quem manda em quê:
## - cada computador simula o próprio jogador e manda posição, mira e escudo ~60x por segundo;
## - quem LEVA o tiro decide se refletiu ou tomou dano (é a tela dele que mostra a bala chegando,
##   então o escudo vale exatamente quando ele aperta E);
## - o host decide o fluxo: mapa e seed de cada rodada, quem escolhe carta, placar e fim.

signal lobby_changed(count: int)   # todos: quantos jogadores há na sala (host incluído)
signal joined                      # convidado: conectou no host
signal match_starting              # todos: o host mandou começar
signal failed(reason: String)
signal disconnected
signal everyone_ready
signal chat_received(entry: Dictionary)   # todos: mensagem nova no chat (ver chat_log)

const PORT := 7777
const MAX_GUESTS := 3
const CHAT_MAX := 120        # letras por mensagem
const CHAT_KEEP := 60        # mensagens guardadas (a sala e a partida mostram as mesmas)
const CHAT_GAP := 0.35       # segundos mínimos entre duas mensagens da mesma pessoa

var online := false
var remote_ids: Array = []
## Jogadores na sala antes da partida, host incluído (o convidado sabe pelo host).
var lobby_count := 0
## Ordem dos jogadores na partida (o host é sempre o primeiro). Vale para todas as máquinas.
var match_peers: Array = []
## Quem já carregou a cena da partida. O host só começa (e ninguém manda estado)
## quando todos estão prontos; senão as mensagens chegariam antes da cena existir.
var ready_peers := {}
## Nome de cada jogador da sala (id -> nome; vazio se a pessoa não escolheu), já sem
## repetidos. O host junta em _raw_names e repassa: o convidado manda o próprio ao entrar
## (_hello).
var names := {}
var _raw_names := {}
## Visual de cada jogador (id -> {"skin", "gun"}, ids de Player.SKINS e GUN_SKINS),
## mandado junto com o nome. Só aparência: não muda nada no jogo.
var looks := {}
## Formato 2x2 escolhido pelo host e o time de cada um (id -> 0 Azul, 1 Vermelho). Na sala
## o host arruma; ao começar vai junto e vale para a partida inteira.
var team_mode := false
var teams := {}
## Chat da sala e da partida, o mesmo do começo ao fim da conexão. Cada mensagem guarda o
## nome e a cor de quem mandou no momento do envio: {"name", "color", "text", "system"}.
## O host carimba nome e cor e repassa a todos; ninguém escolhe a própria cor.
var chat_log: Array = []
var _chat_last := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func():
		_hello.rpc_id(1, GameState.nick, GameState.look())
		joined.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(func(): disconnected.emit())


func host(port := PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_GUESTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	lobby_count = 1
	names = {1: GameState.nick}
	_raw_names = names.duplicate()
	looks = {1: GameState.look()}
	teams = {1: 0}
	return OK


func join(ip: String, port := PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	return OK


func stop() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	lobby_count = 0
	remote_ids.clear()
	match_peers.clear()
	ready_peers.clear()
	names.clear()
	_raw_names.clear()
	looks.clear()
	team_mode = false
	teams.clear()
	chat_log.clear()
	_chat_last.clear()


func is_host() -> bool:
	return not online or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


## IPs desta máquina na rede local (o que o amigo digita para entrar).
func local_ips() -> Array:
	var ips := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			ips.append(ip)
	return ips


## Host: manda todo mundo abrir a partida com quem estiver na sala.
func start_match() -> void:
	var ids := _room_ids()
	if ids.size() < 2 or (team_mode and not teams_ready()):
		return
	var all_names := _unique_names(ids)
	var match_teams := teams.duplicate() if team_mode else {}
	for id in ids:
		if id != 1:
			_start.rpc_id(id, ids, all_names, match_teams, looks)
	_start(ids, all_names, match_teams, looks)


## 2x2 só começa com 4 na sala, 2 em cada time.
func teams_ready() -> bool:
	return lobby_count == 4 and teams.values().count(0) == 2 and teams.values().count(1) == 2


## Host: liga ou desliga o 2x2.
func set_team_mode(on: bool) -> void:
	if multiplayer.is_server():
		team_mode = on
		_broadcast_lobby()


## Host: passa o jogador para o outro time.
func switch_team(id: int) -> void:
	if multiplayer.is_server() and teams.has(id):
		teams[id] = 1 - int(teams[id])
		_broadcast_lobby()


## Host: times sorteados, 2 e 2 (com menos gente, o mais equilibrado possível).
func shuffle_teams() -> void:
	if not multiplayer.is_server():
		return
	var ids := _room_ids()
	ids.shuffle()
	for i in ids.size():
		teams[ids[i]] = i % 2
	_broadcast_lobby()


## Host: quem está na sala, host primeiro. Convidado só entra na conta depois de mandar o
## nome (_hello); senão uma partida começada às pressas o mostraria como "Jogador 2".
func _room_ids() -> Array:
	var guests := remote_ids.filter(func(id): return _raw_names.has(id))
	guests.sort()
	return [1] + guests


@rpc("authority", "call_local", "reliable")
func _start(ids: Array, all_names: Dictionary, match_teams: Dictionary, all_looks: Dictionary) -> void:
	match_peers = ids
	names = all_names
	looks = all_looks
	teams = match_teams
	team_mode = not match_teams.is_empty()
	ready_peers.clear()
	match_starting.emit()


func announce_ready() -> void:
	if online and not is_host():
		_mark_ready.rpc_id(1)
	else:
		_mark_ready()


@rpc("any_peer", "call_local", "reliable")
func _mark_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	ready_peers[id if id != 0 else my_id()] = true
	if not is_host() or not all_ready():
		return
	if online:
		_everyone_ready.rpc(match_peers)
	everyone_ready.emit()


@rpc("authority", "call_remote", "reliable")
func _everyone_ready(ids: Array) -> void:
	for id in ids:
		ready_peers[id] = true


func all_ready() -> bool:
	return ready_peers.size() >= (match_peers.size() if online else 1)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		if id != 1:
			remote_ids.append(id)
		return
	if not match_peers.is_empty():
		# Partida já começou: não cabe mais ninguém.
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	remote_ids.append(id)
	_broadcast_lobby()


func _on_peer_disconnected(id: int) -> void:
	var was_in_room := multiplayer.is_server() and _raw_names.has(id) and match_peers.is_empty()
	var leaving := display_name(id)
	remote_ids.erase(id)
	if id in match_peers:
		disconnected.emit()
	elif multiplayer.is_server():
		_broadcast_lobby()
		if was_in_room:
			_system_chat("%s saiu da sala" % leaving)


## Ordem da sala: host primeiro, convidados pela ordem dos ids (a mesma de start_match).
func lobby_ids() -> Array:
	var ids: Array = names.keys()
	ids.sort()
	return ids


## Nome para mostrar: o escolhido ou "Jogador N" pela vaga.
func display_name(id: int) -> String:
	var n: String = names.get(id, "")
	return n if n != "" else "Jogador %d" % (lobby_ids().find(id) + 1)


@rpc("any_peer", "call_remote", "reliable")
func _hello(nick: String, look: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and id in remote_ids:
		var first := not _raw_names.has(id)
		_raw_names[id] = GameState.clean_nick(nick)
		looks[id] = Player.clean_look(look)
		_broadcast_lobby()
		if first:
			_system_chat("%s entrou na sala" % display_name(id))


## Troca de nome na sala: vale na hora para todos (durante a partida os nomes ficam fixos).
func change_nick(nick: String) -> void:
	GameState.set_nick(nick)
	if not online or not match_peers.is_empty():
		return
	_resend_profile()


## Troca de personagem ou de arma (Personalizar): na sala vale na hora para todos.
func change_look(skin: String, gun: String) -> void:
	GameState.set_look(skin, gun)
	_resend_profile()


func _resend_profile() -> void:
	if not online or not match_peers.is_empty():
		return
	if multiplayer.is_server():
		_broadcast_lobby()
	else:
		_hello.rpc_id(1, GameState.nick, GameState.look())


## Dois com o mesmo nome: o segundo vira "Nome (2)".
func _unique_names(ids: Array) -> Dictionary:
	var out := {}
	var seen := {}
	for id in ids:
		var n: String = _raw_names.get(id, "")
		if n != "":
			seen[n] = seen.get(n, 0) + 1
			if seen[n] > 1:
				n = "%s (%d)" % [n, seen[n]]
		out[id] = n
	return out


func _broadcast_lobby() -> void:
	_raw_names[1] = GameState.nick
	looks[1] = GameState.look()
	for id in _raw_names.keys():
		if id != 1 and not id in remote_ids:
			_raw_names.erase(id)
			looks.erase(id)
	var ids := _room_ids()
	# Quem saiu perde a vaga no time; quem chegou entra no time com menos gente.
	for id in teams.keys():
		if not id in ids:
			teams.erase(id)
	for id in ids:
		if not teams.has(id):
			teams[id] = 0 if teams.values().count(0) <= teams.values().count(1) else 1
	_lobby.rpc(ids.size(), _unique_names(ids), team_mode, teams, looks)


@rpc("authority", "call_local", "reliable")
func _lobby(count: int, all_names: Dictionary, p_team_mode: bool, p_teams: Dictionary, all_looks: Dictionary) -> void:
	lobby_count = count
	names = all_names
	looks = all_looks
	team_mode = p_team_mode
	teams = p_teams
	lobby_changed.emit(count)


## Cor de quem está na sala ou na partida: a mesma vaga e o mesmo time que valem na partida
## (match.gd, _spawn_player), então o nome sai da mesma cor no chat, na sala e no jogo.
func color_of(id: int) -> Color:
	var ids: Array = match_peers if not match_peers.is_empty() else lobby_ids()
	if team_mode and teams.has(id):
		var team := int(teams[id])
		var mates := ids.filter(func(other): return teams.get(other, -1) == team)
		return GameState.player_color(maxi(0, mates.find(id)), team)
	return GameState.player_color(maxi(0, ids.find(id)))


## Manda uma mensagem no chat (o host confere e repassa a todos).
func send_chat(text: String) -> void:
	text = _clean_chat(text)
	if text == "" or not online:
		return
	if multiplayer.is_server():
		_accept_chat(1, text)
	else:
		_chat_request.rpc_id(1, text)


@rpc("any_peer", "call_remote", "reliable")
func _chat_request(text: String) -> void:
	if multiplayer.is_server():
		_accept_chat(multiplayer.get_remote_sender_id(), text)


## Host: confere quem mandou (o id vem da conexão, não da mensagem) e repassa a todos.
func _accept_chat(id: int, text: String) -> void:
	if id != 1 and not _raw_names.has(id) and not id in match_peers:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_chat_last.get(id, -10.0)) < CHAT_GAP:
		return
	_chat_last[id] = now
	text = _clean_chat(text)
	if text != "":
		_chat.rpc(display_name(id), color_of(id), text, false)


func _system_chat(text: String) -> void:
	_chat.rpc("", Color.WHITE, text, true)


@rpc("authority", "call_local", "reliable")
func _chat(sender: String, color: Color, text: String, system: bool) -> void:
	var entry := {"name": sender, "color": color, "text": text, "system": system}
	chat_log.append(entry)
	if chat_log.size() > CHAT_KEEP:
		chat_log.pop_front()
	chat_received.emit(entry)


static func _clean_chat(text: String) -> String:
	return text.replace("\n", " ").replace("\t", " ").strip_edges().left(CHAT_MAX)


func _on_connection_failed() -> void:
	stop()
	failed.emit("Não foi possível conectar. Confira o IP e se o host está esperando.")
