extends Node3D
## Partida de 2 a 4 jogadores, contra bots ou em rede, num dos modos de GameModes: cada um
## por si, 2x2 (com 4) ou Duelos (1x1 em rodízio com vidas; ver _duel_over).
## Compra inicial de todos; a rodada acaba quando sobra um vivo (no 2x2, um time), que
## ganha o ponto; quem morreu escolhe uma carta (no 2x2, os dois do time que perdeu). A cada GameState.ROUNDS_PER_BLOCK rodadas pergunta se
## continua por mais um bloco ou termina; ganha quem tiver mais rodadas no fim.
## Cada rodada acontece numa arena nova, sorteada.
##
## Quem decide o fluxo é o host (contra bots, esta máquina é o host). As funções net_*
## são chamadas em todas as máquinas: pela rede quando online, direto quando não.

enum Phase { WAIT, DRAFT, COUNTDOWN, FIGHT, ROUND_OVER, MATCH_OVER }

const DRAFT_SIZE := 3
const AUTOTEST_ROUNDS := 10
const LOBBY_SEED := 12345

@onready var hud: Hud = $Hud
@onready var draft: DraftScreen = $DraftScreen
var pause_menu: PauseMenu

var me: Player            # o jogador desta máquina (câmera e HUD)
var players: Array = []   # na ordem dos lados; no online o host é sempre o primeiro
var score := {}           # nome do nó -> rodadas vencidas (no 2x2, os dois do time somam juntos)
var teams_on := false     # 2x2: Player.team de cada um é 0 (Azul) ou 1 (Vermelho)
var mode := "ffa"         # GameModes
## Duelos (todas as máquinas, mandado pelo host a cada duelo): quem duela agora, vidas de
## cada um (nome do nó -> vidas), a fila (só o host mexe) e a ordem em que saíram.
var duel_pair: Array = []
var lives := {}
var duel_queue: Array = []
var out_order: Array = []
## 2x2: morto, assiste o parceiro por uma câmera atrás dele.
var spectator: Spectator
var round_num := 0
var phase := Phase.WAIT
var arena: Arena
# Só usados no host:
var last_map := -1
var pending_picks: Array = []
var votes := {}
var last_losers: Array = []
## Placar (Tab): nome do nó -> [abates, assistências, mortes]. Contado em todas as máquinas
## com o que vem no aviso de morte (Player.death_killer, death_assists).
var kda := {}
var _board_open := false
var _board_took_mouse := false


func _ready() -> void:
	if GameState.autotest:
		Engine.time_scale = 2.0
	_apply_quality()
	GameState.quality_changed.connect(_apply_quality)
	mode = Net.mode if Net.online else GameState.mode
	if GameModes.blocked_reason(mode, (Net.match_peers.size() if Net.online else GameState.bot_count + 1)) != "":
		mode = "ffa"
	teams_on = mode == "teams"
	Player.downs_enabled = teams_on   # caído e reviver: só no 2x2
	var start_lives: int = Net.lives if Net.online else GameState.lives
	if Net.online:
		# No 2x2 o lado vem do time (Azul nasce nos lados 0 e 1, vizinhos; Vermelho no 2 e 3).
		var in_team := [0, 0]
		for i in Net.match_peers.size():
			var peer: int = Net.match_peers[i]
			var team: int = Net.teams.get(peer, -1) if teams_on else -1
			var side := i
			if team >= 0:
				side = team * 2 + in_team[team]
				in_team[team] += 1
			_spawn_player(peer, side, Net.display_name(peer), team)
		for p in players:
			if p.is_local:
				me = p
		Net.disconnected.connect(_on_connection_lost)
		if GameState.autotest:
			# Teste do chat: cada máquina manda uma mensagem e registra o que chega.
			Net.chat_received.connect(func(e): _log("chat: %s: %s" % [e["name"] if not e["system"] else "*", e["text"]]))
			get_tree().create_timer(4.0).timeout.connect(func(): Net.send_chat("oi, aqui é %s [b]sem negrito[/b]" % Net.display_name(Net.my_id())))
	else:
		me = _spawn_player(1, 0, "Você", 0 if teams_on else -1)
		for i in GameState.bot_count:
			var bot_name := "Bot" if GameState.bot_count == 1 else "Bot %d" % (i + 1)
			var team := -1
			if teams_on:
				team = 0 if i == 0 else 1
				bot_name = "Aliado" if i == 0 else "Bot %d" % i
			var bot := _spawn_player(1, i + 1, bot_name, team)
			bot.brain = BotBrain.new()
			bot.brain.player = bot
			bot.add_child(bot.brain)
			bot.deck = CardDB.random_deck()
	me.player_name = "Você"
	Player.viewer = me
	for p in players:
		lives[String(p.name)] = start_lives
	if GameState.autotest:
		me.brain = BotBrain.new()
		me.brain.player = me
		me.add_child(me.brain)
	hud.setup(me, players, teams_on, mode, start_lives)
	hud.set_kda(kda)
	for p in players:
		p.revived.connect(hud.toast.bind("Fênix: %s voltou!" % p.player_name if p != me else "Fênix: você voltou!"))
	me.died.connect(_on_me_died)
	me.void_bounced.connect(_on_me_void)
	spectator = Spectator.new()
	spectator.game = self
	add_child(spectator)
	pause_menu = PauseMenu.new()
	pause_menu.online = Net.online
	add_child(pause_menu)
	pause_menu.resumed.connect(_on_resumed)
	pause_menu.leave_requested.connect(_to_menu)
	pause_menu.quit_requested.connect(_quit)
	# Arena provisória (igual em todas as máquinas) até a primeira rodada.
	_build_arena(0, LOBBY_SEED)
	_reset_players()
	hud.show_center("Esperando os outros jogadores..." if Net.online else "")
	if Net.is_host():
		Net.everyone_ready.connect(_host_draft.bind(players, "Começo da partida"), CONNECT_ONE_SHOT)
	Net.announce_ready()


## Qualidade gráfica (Configurações). Medido num Intel HD (OpenGL via ANGLE), 1280x720:
## Alta ~14 FPS (o brilho é o que mais pesa), Média ~45, Baixa ~50 a 60. Reduzir a
## resolução 3D piorou nessa placa, por isso não entra.
func _apply_quality() -> void:
	var env: Environment = $WorldEnvironment.environment
	var sun: DirectionalLight3D = $Sun
	var q := GameState.quality
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == 1 		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 50.0 if q == 1 else 90.0
	env.glow_enabled = q >= 2
	env.ssao_enabled = q >= 2
	env.fog_enabled = q >= 2
	get_viewport().msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED


func _spawn_player(peer: int, side: int, pname: String, team := -1) -> Player:
	var p := Player.new()
	p.name = "P%d" % (side + 1) if not Net.online else "P%d" % peer
	p.peer_id = peer
	p.side = side
	p.team = team
	p.player_name = pname
	p.color = GameState.player_color(side, team)
	var look := _look_for(peer, side)
	p.skin = look["skin"]
	p.gun_skin = look["gun"]
	_log("visual de %s: %s, %s" % [pname, look["skin"], look["gun"]])
	p.is_local = not Net.online or peer == Net.my_id()
	p.is_human = p.is_local and side == 0 if not Net.online else p.is_local
	p.deck = GameState.player_deck.duplicate() if p.is_human else []
	p.set_multiplayer_authority(peer)
	add_child(p)
	p.died.connect(_on_player_died)
	p.went_down.connect(_on_player_down.bind(p))
	p.got_up.connect(_on_player_up.bind(p))
	p.reflected.connect(func(): _log("%s refletiu uma bala" % p.player_name))
	players.append(p)
	score[String(p.name)] = 0
	kda[String(p.name)] = [0, 0, 0]
	return p


# ---------------------------------------------------------------- envio

## Chama em todas as máquinas (inclusive esta).
func _all(method: StringName, args: Array) -> void:
	if Net.online:
		callv("rpc", [method] + args)
	else:
		callv(method, args)


## Chama só no host.
func _to_host(method: StringName, args: Array) -> void:
	if Net.online and not Net.is_host():
		callv("rpc_id", [1, method] + args)
	else:
		callv(method, args)


## Chama só na máquina dona do jogador.
func _to_owner(p: Player, method: StringName, args: Array) -> void:
	if Net.online and p.peer_id != Net.my_id():
		callv("rpc_id", [p.peer_id, method] + args)
	else:
		callv(method, args)


## Visual de quem entra: online o que a pessoa escolheu; no treino o seu e, para os bots,
## personagens da lista pela ordem, pulando o seu (o bot não fica igual a você), com a
## arma padrão.
func _look_for(peer: int, side: int) -> Dictionary:
	if Net.online:
		return Player.clean_look(Net.looks.get(peer, {}))
	if side == 0:
		return GameState.look()
	var others := Player.skin_ids().filter(func(id): return id != GameState.skin)
	return {"skin": others[(side - 1) % others.size()], "gun": ""}


func _player(node_name: String) -> Player:
	return get_node_or_null(node_name) as Player


func _scores() -> Array:
	return players.map(func(p): return score[String(p.name)])


## Rodadas do time (no 2x2 os dois do time têm sempre o mesmo número).
func team_score(team: int) -> int:
	for p in players:
		if p.team == team:
			return score[String(p.name)]
	return 0


# ---------------------------------------------------------------- fluxo (host)

func _host_draft(who: Array, title: String, size := DRAFT_SIZE) -> void:
	pending_picks = who.map(func(p): return String(p.name))
	for p: Player in who:
		_to_owner(p, "net_draft", [String(p.name), title, size])


func _host_start_round() -> void:
	# Mapa (MapList): online, os que o anfitrião deixou ligados; no treino, pelo número de bots.
	var arena_count := 2 if mode == "duels" else players.size()
	var pool := MapList.enabled(Net.maps, arena_count) if Net.online else MapList.training(players.size() - 1)
	var map_index := MapList.pick(pool, last_map)
	last_map = map_index
	var duel := {}
	if mode == "duels":
		if duel_pair.is_empty():
			# Primeiro duelo: fila sorteada, os dois primeiros duelam.
			duel_queue = players.map(func(p): return String(p.name))
			duel_queue.shuffle()
			duel_pair = [duel_queue.pop_front(), duel_queue.pop_front()]
		duel = {"pair": duel_pair, "lives": lives, "queue": duel_queue}
	_all("net_start_round", [round_num + 1, map_index, randi(), duel])


## Caído no 2x2: avisos para o time (a rodada só olha quem morreu; caído já conta como fora).
func _on_player_down(p: Player) -> void:
	_log("%s caiu (prazo de %d s)" % [p.player_name, roundi(p.bleed_total)])
	if phase != Phase.FIGHT:
		return
	if p == me:
		hud.toast("Você caiu! Seu parceiro pode te reviver")
	elif me.is_ally(p):
		hud.toast("%s caiu: fique perto dele por %d s para reviver" % [p.player_name, roundi(Player.REVIVE_TIME)])


func _on_player_up(p: Player) -> void:
	_log("%s foi revivido" % p.player_name)
	if p == me:
		hud.toast("Você foi revivido!")
	elif me.is_ally(p):
		hud.toast("%s voltou à luta" % p.player_name)


## A rodada acaba quando sobra no máximo um vivo (no 2x2, um time com alguém de pé).
## Quem morreu escolhe carta; no 2x2, os dois do time que perdeu.
func _on_player_died(dead: Player) -> void:
	_count_death(dead)
	var killer: Player = _player(dead.death_killer) if dead.death_killer != "" else null
	var assist: Player = _player(dead.death_assists[0]) if not dead.death_assists.is_empty() else null
	hud.kill_feed.add_kill(killer, dead, assist)
	if teams_on and me.is_ally(dead) and phase == Phase.FIGHT:
		hud.toast("Seu parceiro %s caiu" % dead.player_name)
	if not Net.is_host() or phase != Phase.FIGHT:
		return
	var alive := players.filter(func(p): return p.alive)
	if mode == "duels":
		if alive.size() <= 1:
			_duel_over(alive[0] if alive.size() == 1 else null)
		return
	var winner: Player = null
	var winner_team := -1
	if teams_on:
		var alive_teams := []
		for p in alive:
			if not p.team in alive_teams:
				alive_teams.append(p.team)
		if alive_teams.size() > 1:
			return
		winner_team = alive_teams[0] if alive_teams.size() == 1 else -1
		for p in players:
			if p.team == winner_team:
				score[String(p.name)] += 1
		last_losers = players.filter(func(p): return p.team != winner_team).map(func(p): return String(p.name))
	else:
		if alive.size() > 1:
			return
		winner = alive[0] if alive.size() == 1 else null
		if winner:
			score[String(winner.name)] += 1
		last_losers = players.filter(func(p): return p != winner).map(func(p): return String(p.name))
	phase = Phase.ROUND_OVER
	_all("net_round_over", [String(winner.name) if winner else "", winner_team, _scores()])
	await get_tree().create_timer(1.5, false).timeout
	if round_num % GameState.ROUNDS_PER_BLOCK == 0:
		votes.clear()
		_all("net_ask_continue", [])
	else:
		_draft_losers()


## Duelos (host): o vencedor fica; o perdedor perde uma vida e vai para o fim da fila (ou
## sai, se zerou). Quem perdeu escolhe 1 de 3 cartas, ou 1 de 4 na última vida. Empate
## (os dois caíram): ninguém perde vida e o mesmo duelo se repete. Sobrou um com vida: fim.
func _duel_over(winner: Player) -> void:
	phase = Phase.ROUND_OVER
	var fought := duel_pair.duplicate()
	var loser_name := ""
	if winner:
		var winner_name := String(winner.name)
		loser_name = duel_pair[0] if duel_pair[1] == winner_name else duel_pair[1]
		score[winner_name] += 1
		lives[loser_name] -= 1
		if lives[loser_name] > 0:
			duel_queue.append(loser_name)
		duel_pair = [winner_name, duel_queue.pop_front()] if not duel_queue.is_empty() else [winner_name]
	_all("net_duel_over", [fought, String(winner.name) if winner else "", loser_name, lives, _scores()])
	await get_tree().create_timer(1.5, false).timeout
	var standing := lives.keys().filter(func(n): return lives[n] > 0)
	if standing.size() <= 1:
		_all("net_end_match", [])
	elif loser_name != "" and lives[loser_name] > 0:
		var last: bool = lives[loser_name] == 1
		_host_draft([_player(loser_name)], "Última vida: uma carta a mais para escolher" if last
			else "Você perdeu o duelo", GameModes.LAST_CHANCE_CARDS if last else DRAFT_SIZE)
	else:
		_host_start_round()


@rpc("authority", "call_local", "reliable")
func net_duel_over(fought: Array, winner_name: String, loser_name: String, p_lives: Dictionary, scores: Array) -> void:
	phase = Phase.ROUND_OVER
	lives = p_lives
	for i in players.size():
		score[String(players[i].name)] = scores[i]
	for p in players:
		p.frozen = true
	_clear_bullets()
	var winner := _player(winner_name)
	var loser := _player(loser_name)
	if loser and lives[loser_name] <= 0 and not loser_name in out_order:
		out_order.append(loser_name)
	hud.set_duel(fought, lives, [])
	if winner == null:
		hud.show_center("Os dois caíram: duelo repetido")
	elif lives[loser_name] <= 0:
		hud.show_center("%s venceu o duelo\n%s está fora" % [winner.player_name, loser.player_name])
	else:
		var left: int = lives[loser_name]
		hud.show_center("%s venceu o duelo\n%s perde uma vida (%d %s)" % [winner.player_name, loser.player_name,
			left, "restante" if left == 1 else "restantes"])
	_log("duelo %d: %s venceu, %s fica com %s vidas" % [round_num, winner.player_name if winner else "ninguém",
		loser.player_name if loser else "-", str(lives.get(loser_name, "-"))])


func _count_death(dead: Player) -> void:
	kda[String(dead.name)][2] += 1
	if kda.has(dead.death_killer):
		kda[dead.death_killer][0] += 1
	for n in dead.death_assists:
		if kda.has(n):
			kda[n][1] += 1
	hud.set_kda(kda)
	if dead.death_killer != "":
		_log("%s abateu %s%s" % [_player(dead.death_killer).player_name, dead.player_name,
			" (assistência: %s)" % ", ".join(dead.death_assists.map(func(n): return _player(n).player_name)) if not dead.death_assists.is_empty() else ""])


## Segurar Tab abre o placar e solta o mouse para passar sobre as cartas (sem atirar nesse
## meio-tempo); soltar Tab fecha e prende o mouse de novo se ele estava preso.
func _process(_delta: float) -> void:
	if GameState.autotest:
		_sample_perf()
	var want := not GameState.autotest and phase != Phase.MATCH_OVER and not draft.visible and not GameState.menu_open 		and not GameState.chat_open and Input.is_action_pressed("scoreboard")
	if want == _board_open:
		return
	_board_open = want
	hud.show_scoreboard(want)
	if want:
		_board_took_mouse = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if _board_took_mouse:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _board_took_mouse and _in_fight() and not GameState.menu_open:
		_capture_mouse()


func _draft_losers() -> void:
	var title := "Seu time perdeu a rodada" if teams_on else "Você perdeu a rodada"
	_host_draft(last_losers.map(func(n): return _player(n)), title)


@rpc("any_peer", "call_local", "reliable")
func net_vote(keep_going: bool) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	votes["P%d" % sender if Net.online else String(me.name)] = keep_going
	var done := votes.size() >= (Net.match_peers.size() if Net.online else 1)
	_all("net_votes", [votes, done])
	if not done:
		return
	if votes.values().all(func(v): return v):
		_draft_losers()
	else:
		_all("net_end_match", [])


## Votos que já chegaram (nome do nó -> continuar), para a tela da votação. Todos votaram:
## a tela fecha (quem perdeu a rodada abre a escolha de carta logo depois).
@rpc("authority", "call_local", "reliable")
func net_votes(current: Dictionary, done: bool) -> void:
	draft.set_votes(current)
	if done:
		draft.close()


# ---------------------------------------------------------------- fluxo (todos)

## Na máquina dona do jogador: mostra as cartas (ou o bot escolhe) e avisa a escolha.
@rpc("authority", "call_local", "reliable")
func net_draft(node_name: String, title: String, size: int) -> void:
	var p := _player(node_name)
	phase = Phase.DRAFT
	hud.show_center("")
	if p.cards.is_empty():
		# Começo da partida: a carta mestra entra antes da primeira escolha.
		var master: String = GameState.player_master if p == me else CardDB.master_ids().pick_random()
		_all("net_master", [node_name, master])
	var options := CardDB.offer(p.deck if p.brain == null else _bot_deck(p), p.cards, size)
	var pick := ""
	if not options.is_empty():
		if p.brain:
			pick = options.pick_random()
		else:
			pick = await draft.choose(options, title, p.cards)
			if Net.online:
				hud.show_center("Esperando os outros...")
	_all("net_card_picked", [node_name, pick])


func _bot_deck(p: Player) -> Array:
	if p.deck.is_empty():
		p.deck = GameState.player_deck.duplicate() if p == me else CardDB.random_deck()
	return p.deck


@rpc("any_peer", "call_local", "reliable")
func net_master(node_name: String, card: String) -> void:
	var p := _player(node_name)
	if CardDB.is_master(card) and not p.cards.any(CardDB.is_master):
		p.cards.push_front(card)
		_log("%s tem a carta mestra %s" % [p.player_name, card])
		if GameState.autotest:
			p.cards.append_array(GameState.test_cards)
	hud.refresh_cards()


@rpc("any_peer", "call_local", "reliable")
func net_card_picked(node_name: String, card: String) -> void:
	var p := _player(node_name)
	if card != "":
		p.cards.append(card)
		_log("%s pegou %s" % [p.player_name, card])
		if p != me:
			hud.toast("%s escolheu: %s" % [p.player_name, CardDB.card_name(card)])
	hud.refresh_cards()
	if Net.is_host():
		pending_picks.erase(node_name)
		if pending_picks.is_empty():
			_host_start_round()


## map_index: o mapa (MapList, estilo e tamanho). duel: no Duelos, {"pair": [quem duela],
## "lives": vidas, "queue": a fila}; vazio nos outros.
@rpc("authority", "call_local", "reliable")
func net_start_round(number: int, map_index: int, seed_value: int, duel: Dictionary) -> void:
	round_num = number
	_clear_bullets()
	if not duel.is_empty():
		duel_pair = duel["pair"]
		lives = duel["lives"]
		duel_queue = duel["queue"]
	_build_arena(map_index, seed_value, 2 if mode == "duels" else players.size())
	_reset_players()
	hud.set_score(score, round_num, _block_end())
	var title := "Rodada %d" % round_num
	if mode == "duels":
		hud.set_duel(duel_pair, lives, duel_queue)
		title = "Duelo %d: %s x %s" % [round_num, _player(duel_pair[0]).player_name, _player(duel_pair[1]).player_name]
		if not String(me.name) in duel_pair:
			title += "\nVocê assiste este duelo" if lives.get(String(me.name), 0) > 0 else ""
	phase = Phase.COUNTDOWN
	_capture_mouse()
	_log("rodada %d: %s, ambiente %s%s" % [round_num, arena.map_name, arena.theme_name,
		" (duelo %s x %s)" % duel_pair.map(func(n): return _player(n).player_name) if mode == "duels" else ""])
	for n in [3, 2, 1]:
		hud.show_center("%s: %s (%s)\n%d" % [title, arena.map_name, arena.theme_name, n])
		await get_tree().create_timer(0.8, false).timeout
		if phase != Phase.COUNTDOWN:
			return
	hud.show_center("")
	phase = Phase.FIGHT
	for p in players:
		if p.alive:
			p.frozen = false


## Cair no vazio: a primeira vez na partida explica o escudo; depois só avisa o quique perfeito.
var _void_hint_shown := false


func _on_me_void(saved: bool) -> void:
	if saved:
		hud.toast("Quique perfeito: sem dano!")
	elif not _void_hint_shown:
		_void_hint_shown = true
		hud.toast("Vazio: -%d. Escudo (%s) na hora de bater = quique alto sem dano" % [Player.VOID_DAMAGE, GameState.key_text("shield")])


func _on_me_died(_p: Player) -> void:
	if phase != Phase.FIGHT or players.size() <= 2 or mode == "duels":
		return
	if players.any(func(p): return p != me and p.alive and (not teams_on or me.is_ally(p))):
		hud.show_center("")   # a câmera passa a seguir quem está vivo (Spectator)
	else:
		hud.show_center("Você caiu. Esperando a rodada acabar...")


@rpc("authority", "call_local", "reliable")
func net_round_over(winner_name: String, winner_team: int, scores: Array) -> void:
	phase = Phase.ROUND_OVER
	for i in players.size():
		score[String(players[i].name)] = scores[i]
	for p in players:
		p.frozen = true
	_clear_bullets()
	var winner := _player(winner_name) if winner_name != "" else null
	hud.set_score(score, round_num, _block_end())
	if teams_on:
		if winner_team < 0:
			hud.show_center("Ninguém sobrou: rodada sem ponto")
		elif winner_team == me.team:
			hud.show_center("Seu time venceu a rodada!")
		else:
			hud.show_center("Time %s venceu a rodada" % GameState.TEAM_NAMES[winner_team])
		_log("rodada %d: time %s venceu %s" % [round_num,
			GameState.TEAM_NAMES[winner_team] if winner_team >= 0 else "nenhum", str(scores)])
		return
	if winner == me:
		hud.show_center("Você venceu a rodada!")
	elif winner:
		hud.show_center("%s venceu a rodada" % winner.player_name)
	else:
		hud.show_center("Ninguém sobrou: rodada sem ponto")
	_log("rodada %d: %s venceu %s" % [round_num, winner.player_name if winner else "ninguém", str(scores)])


@rpc("authority", "call_local", "reliable")
func net_ask_continue() -> void:
	hud.show_center("")
	var keep_going := round_num < AUTOTEST_ROUNDS
	if not GameState.autotest:
		var voters := players.filter(func(p): return p.brain == null)
		keep_going = await draft.vote(round_num, GameState.ROUNDS_PER_BLOCK, hud.score_text(score),
			voters, Net.online)
	_to_host("net_vote", [keep_going])


@rpc("authority", "call_local", "reliable")
func net_end_match() -> void:
	phase = Phase.MATCH_OVER
	draft.close()
	if mode == "duels":
		_end_duels()
		return
	var mine: int = score[String(me.name)]
	var best_other := 0
	for p in players:
		if me.is_enemy(p):
			best_other = maxi(best_other, score[String(p.name)])
	var text := "EMPATE"
	if mine > best_other:
		text = "VITÓRIA"
	elif best_other > mine:
		text = "DERROTA"
	var color := Ui.TEXT
	if text != "EMPATE":
		color = Ui.OK if text == "VITÓRIA" else Ui.DANGER
	_log("fim: %s %s depois de %d rodadas" % [text, str(_scores()), round_num])
	if GameState.autotest:
		_log(_perf_report())
		await get_tree().create_timer(0.5).timeout
		_quit()
		return
	_show_end(text, color, "%d rodadas  ·  %s" % [round_num, GameModes.label(mode, GameState.lives)])


## Placar final com o resultado; contra bots dá para jogar de novo direto.
func _show_end(result: String, color: Color, detail: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.round_text = detail
	if Net.online:
		hud.show_end(result, color, {"Voltar ao menu": _to_menu})
	else:
		hud.show_end(result, color, {"Jogar de novo": get_tree().reload_current_scene, "Voltar ao menu": _to_menu})


## Fim do Duelos: vence quem sobrou com vida; a classificação segue a ordem de saída.
func _end_duels() -> void:
	var ranking: Array = lives.keys().filter(func(n): return lives[n] > 0)
	var gone := out_order.duplicate()
	gone.reverse()
	ranking.append_array(gone)
	var winner := _player(ranking[0])
	var lines := PackedStringArray()
	for i in ranking.size():
		lines.append("%dº %s" % [i + 1, _player(ranking[i]).player_name])
	var text := "VITÓRIA" if winner == me else "%s VENCEU" % winner.player_name.to_upper()
	_log("fim: %s venceu os duelos; ordem %s depois de %d duelos" % [winner.player_name,
		", ".join(ranking.map(func(n): return _player(n).player_name)), round_num])
	if GameState.autotest:
		_log(_perf_report())
		await get_tree().create_timer(0.5).timeout
		_quit()
		return
	_show_end(text, Ui.OK if winner == me else Ui.TEXT, "   ".join(lines))


# ---------------------------------------------------------------- balas em rede

@rpc("any_peer", "call_remote", "reliable")
func net_spawn_bullet(data: Dictionary) -> void:
	Bullet.from_data(self, data)


@rpc("any_peer", "call_remote", "reliable")
func net_bullet_reflect(id: String, point: Vector3, dir: Vector3, owner_name: String, dmg: float, homing: float) -> void:
	var b := _bullet(id)
	if b:
		b.remote_reflect(point, dir, owner_name, dmg, homing)


@rpc("any_peer", "call_remote", "reliable")
func net_bullet_hit(id: String, point: Vector3, dmg: float) -> void:
	var b := _bullet(id)
	if b:
		b.remote_hit(point, dmg)


func _bullet(id: String) -> Bullet:
	for b in get_tree().get_nodes_in_group("bullets"):
		if b.id == id:
			return b
	return null


# ---------------------------------------------------------------- utilidades

func _build_arena(map_index: int, seed_value: int, count := -1) -> void:
	if arena:
		remove_child(arena)
		arena.queue_free()
	arena = Arena.new()
	add_child(arena)
	arena.build(map_index, seed_value, players.size() if count < 0 else count)
	ArenaTheme.apply_environment(arena.palette, $WorldEnvironment.environment, $Sun)
	for item in arena.pickups:
		item.taken.connect(_on_pickup_taken)


## Item pego pelo jogador desta máquina: some também nas outras.
func _on_pickup_taken(index: int) -> void:
	if Net.online:
		net_pickup_taken.rpc(round_num, index)


@rpc("any_peer", "call_remote", "reliable")
func net_pickup_taken(round_id: int, index: int) -> void:
	if round_id == round_num and index < arena.pickups.size():
		arena.pickups[index].take()


func _block_end() -> int:
	var block := GameState.ROUNDS_PER_BLOCK
	return ceili(float(round_num) / block) * block


## Duelos: os dois do duelo nascem nos dois lados da arena; os outros ficam no banco.
func _reset_players() -> void:
	var dueling := mode == "duels" and not duel_pair.is_empty()
	for p in players:
		p.net_round = round_num
		var spot: int = duel_pair.find(String(p.name)) if dueling else p.side
		p.reset_for_round(arena.spawns[maxi(0, spot) % arena.spawns.size()])
		p.frozen = true
		if dueling and spot < 0:
			p.bench()


func _on_connection_lost() -> void:
	if phase == Phase.MATCH_OVER:
		return
	phase = Phase.MATCH_OVER
	for p in players:
		p.frozen = true
	draft.close()
	hud.show_center("A conexão com um jogador caiu")
	_log("conexão caiu")
	await get_tree().create_timer(3.0).timeout
	if GameState.autotest:
		_quit()
	else:
		_to_menu()


func _to_menu() -> void:
	pause_menu.close()
	Net.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _quit() -> void:
	pause_menu.close()
	Net.stop()
	get_tree().quit()


func _clear_bullets() -> void:
	for b in get_tree().get_nodes_in_group("bullets"):
		b.remove_from_group("bullets")
		b.queue_free()
	for f in get_tree().get_nodes_in_group("fields"):
		f.remove_from_group("fields")
		f.queue_free()


func _capture_mouse() -> void:
	if not GameState.autotest and not GameState.menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _in_fight() -> bool:
	return phase == Phase.COUNTDOWN or phase == Phase.FIGHT


## Esc abre o menu de pausa (o próprio menu cuida do Esc enquanto está aberto). Clique
## com o mouse solto no meio da luta (depois de trocar de janela, por exemplo) prende o
## mouse de novo.
func _unhandled_input(event: InputEvent) -> void:
	if GameState.autotest or GameState.menu_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_open_pause()
	elif event is InputEventMouseButton and event.pressed and _in_fight() and not draft.visible 			and not _board_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()


## Trocar de janela no meio da luta abre o menu, como Esc.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_menu and not GameState.autotest 			and not GameState.menu_open and _in_fight():
		_open_pause()


func _open_pause() -> void:
	if _board_open:
		_board_open = false
		hud.show_scoreboard(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var info := "Rodada %d" % round_num if round_num > 0 else "Escolha de cartas"
	if mode == "duels":
		info = "Duelos  ·  duelo %d  ·  suas vidas: %d" % [round_num, lives.get(String(me.name), 0)]
	elif teams_on:
		info += "  ·  2x2, time %s" % GameState.TEAM_NAMES[me.team]
		if not Net.online:
			info += " (treino)"
	elif Net.online:
		info += "  ·  %d jogadores" % players.size()
	else:
		info += "  ·  Treino contra %d bot%s" % [players.size() - 1, "s" if players.size() > 2 else ""]
	pause_menu.open(info, hud.score_text(score))


func _on_resumed() -> void:
	if _in_fight() and not draft.visible:
		_capture_mouse()


## Saindo da partida por qualquer caminho, o jogo não pode ficar parado.
func _exit_tree() -> void:
	GameState.menu_open = false
	GameState.chat_open = false
	get_tree().paused = false
	Bullet.clear_cache()
	Effects.clear_cache()
	AreaField.clear_cache()


## Autoteste: tempo de CPU por quadro (scripts e física, sem o desenho), separado pelos
## quadros com muitas balas no ar. Impresso no fim da partida.
var _perf := {"frames": 0, "proc": 0.0, "phys": 0.0, "heavy": 0, "heavy_proc": 0.0,
	"heavy_phys": 0.0, "heavy_bullets": 0, "worst": 0.0, "peak_bullets": 0}


func _sample_perf() -> void:
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var bullets := get_tree().get_node_count_in_group("bullets")
	_perf["frames"] += 1
	_perf["proc"] += proc
	_perf["phys"] += phys
	_perf["worst"] = maxf(_perf["worst"], proc + phys)
	_perf["peak_bullets"] = maxi(_perf["peak_bullets"], bullets)
	if bullets >= 40:
		_perf["heavy"] += 1
		_perf["heavy_proc"] += proc
		_perf["heavy_phys"] += phys
		_perf["heavy_bullets"] += bullets


func _perf_report() -> String:
	var f := maxi(1, _perf["frames"])
	var h := maxi(1, _perf["heavy"])
	return "desempenho: media %.2f ms (process %.2f + fisica %.2f); com 40+ balas (%d quadros) %.2f + %.2f ms; media de %d balas; pior %.1f ms; pico %d balas" % [
		(_perf["proc"] + _perf["phys"]) / f, _perf["proc"] / f, _perf["phys"] / f, _perf["heavy"],
		_perf["heavy_proc"] / h, _perf["heavy_phys"] / h, _perf["heavy_bullets"] / h, _perf["worst"], _perf["peak_bullets"]]


func _log(msg: String) -> void:
	if GameState.autotest:
		var prefix := ""
		if Net.online:
			prefix = "[host] " if Net.is_host() else "[convidado %d] " % (me.side if me else Net.match_peers.find(Net.my_id()))
		print(prefix + msg)
