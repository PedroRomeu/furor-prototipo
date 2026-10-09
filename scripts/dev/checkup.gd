extends Node
## Check-up de desempenho (2026-10-08, pedido do usuário: medir cada parte do jogo de
## tempos em tempos e chegar a um "ok" por parte). Roda COM JANELA, nas configurações de
## vídeo salvas do jogador (resolução, modo, qualidade), com o VSync desligado só aqui.
##   Godot --path . res://scenes/dev/checkup.tscn -- --bloco=1 [--parte=2] [--prints]
## Cada bloco cabe em 40 s de janela. Mede o tempo de quadro real (relógio entre quadros)
## com a partida pausada e a câmera parada, ligando e desligando cada parte, em rodadas
## alternadas (o ruído na Intel HD é de uns ±5 ms; por isso a média de várias). Imprime
## a tabela e grava em user://checkup.txt.

const SAMPLE := 1.0      # segundos por medida
const ROUNDS := 2        # vezes que cada par ligado/desligado se repete

var game: Node
var lines := PackedStringArray()
var _last := 0
var _frames: Array = []
var _sampling := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var block := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bloco="):
			block = int(arg.trim_prefix("--bloco="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_note("check-up bloco %d  ·  %s  ·  qualidade %d  ·  %s" % [block,
		str(get_window().size), GameState.quality, RenderingServer.get_video_adapter_name()])
	match block:
		1: await _block_match()
		2: await _block_combat()
		3: await _block_areas(_part())
		4: await _block_fight()
		5: await _block_new(_part())
		7: await _block_camo()
		_: _note("bloco desconhecido")
	_save()
	get_tree().quit()


## "--parte=2": segunda metade do bloco (os que não cabem em 40 s).
func _part() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--parte="):
			return int(arg.trim_prefix("--parte="))
	return 1


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _sampling and _last > 0:
		_frames.append((now - _last) / 1000.0)
	_last = now


## Tempo médio de quadro (ms) e o pior, durante SAMPLE segundos.
func measure() -> Vector2:
	await get_tree().process_frame
	await get_tree().process_frame
	_frames.clear()
	_sampling = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < SAMPLE * 1000.0:
		await get_tree().process_frame
	_sampling = false
	var sum := 0.0
	var worst := 0.0
	for f in _frames:
		sum += f
		worst = maxf(worst, f)
	return Vector2(sum / maxf(1, _frames.size()), worst)


## Custo de uma parte: mede com ela ligada e desligada, ROUNDS vezes alternando.
func cost(label: String, toggle: Callable) -> void:
	var on := 0.0
	var off := 0.0
	for r in ROUNDS:
		toggle.call(true)
		on += (await measure()).x
		toggle.call(false)
		off += (await measure()).x
	toggle.call(true)
	on /= ROUNDS
	off /= ROUNDS
	_note("%-34s %6.1f ms ligado  %6.1f desligado  custo %+5.1f ms" % [label, on, off, on - off])


func _note(text: String) -> void:
	print(text)
	lines.append(text)


func _save() -> void:
	var f := FileAccess.open("user://checkup.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://checkup.txt") else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string("\n".join(lines) + "\n\n")


# ---------------------------------------------------------------- partida

## Abre uma partida de treino com 3 bots (4 jogadores) e espera a luta começar.
func _start_match(size_index := 0) -> void:
	GameState.autotest = true          # escolhas de carta automáticas
	GameState.bot_count = 3
	GameState.test_size = size_index
	get_tree().change_scene_to_file("res://scenes/match.tscn")
	await get_tree().create_timer(0.5).timeout
	game = get_tree().current_scene
	while game.phase != game.Phase.FIGHT:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.6).timeout
	get_tree().paused = true
	# Ninguém se mexe sozinho entre as medidas (o "você" do autoteste também é bot), e a
	# câmera olha para o centro da arena, longe das paredes.
	for p in game.players:
		p.brain = null
		p.in_move = Vector2.ZERO
		p.in_shoot = false
		p.in_click = false
		p.velocity = Vector3.ZERO
	var me = game.me
	var to: Vector3 = -me.global_position
	me.look_yaw = atan2(-to.x, -to.z)
	me.rotation.y = me.look_yaw
	me.head.rotation.x = -0.08
	# A câmera de quem joga só se reposiciona com o jogo andando: dois quadros soltos.
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = true


## Bloco 1: a partida base. Arena pequena, média e grande com 4 (tempo de montar, quadro
## com a câmera de quem joga), HUD, placar do Tab e os personagens.
func _block_match() -> void:
	await _start_match(0)
	var me = game.me
	var base := await measure()
	_note("%-34s %6.1f ms (pior %.1f)" % ["partida, mapa pequeno, 4", base.x, base.y])
	await cost("HUD inteira", func(on): game.hud.visible = on)
	await cost("placar do Tab aberto", func(on): game.hud.show_scoreboard(on))
	await cost("3 outros personagens", func(on):
		for p in game.players:
			if p != me:
				p.visible = on)
	await cost("arma na tela (primeira pessoa)", func(on): me.viewmodel.visible = on)
	for size in [1, 2]:
		var index: int = 1 * 3 + size   # Ruínas, no tamanho
		var t0 := Time.get_ticks_usec()
		game._build_arena(index, 777, 4)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		game._reset_players()
		await get_tree().process_frame
		var first := Time.get_ticks_usec()
		await get_tree().process_frame
		var first_ms := (Time.get_ticks_usec() - first) / 1000.0
		var m := await measure()
		var meshes: int = game.arena.find_children("*", "MeshInstance3D", true, false).size()
		_note("%-34s %6.1f ms (pior %.1f)  montar %.0f ms  1o quadro %.0f ms  %d malhas" % [
			"mapa " + MapList.SIZES[size]["id"] + ", 4", m.x, m.y, build_ms, first_ms, meshes])
	_note("chamadas de desenho no último: %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


## Bloco 7 (2026-10-09): arma da primeira pessoa translúcida da Camuflagem, contra opaca.
func _block_camo() -> void:
	await _start_match(0)
	var me = game.me
	var base := await measure()
	_note("%-34s %6.1f ms (pior %.1f)" % ["partida, mapa pequeno, 4", base.x, base.y])
	await cost("arma translúcida (Camuflagem)", func(on):
		me._fade_viewmodel(Player.CAMO_VIEW_ALPHA if on else 0.0, 1.0))
	await cost("arma na tela (primeira pessoa)", func(on): me.viewmodel.visible = on)


# ---------------------------------------------------------------- combate

## Bloco 2: combate. Cada coisa é criada na frente da câmera, anda um instante (para os
## efeitos saírem do quadro zero e as balas terem rastro), a partida pausa e mede; depois
## some e mede de novo (o "sem nada" mais perto, contra a deriva). Os efeitos respeitam o
## teto de Effects.BUDGET (metade na qualidade Baixa), como na luta.
func _block_combat() -> void:
	await _start_match(0)
	var me = game.me
	var cam: Camera3D = me.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var eye := cam.global_position
	var spot := func(i: int, n: int, dist: float) -> Vector3:
		var t := (float(i) / maxf(1, n - 1)) - 0.5
		return eye + fwd * dist + right * t * dist * 0.9 + Vector3.UP * (randf() - 0.5) * 2.0
	await _scene_cost("40 balas com rastro", func():
		for i in 40:
			Bullet.fire(me, spot.call(i, 40, 14.0), right, 1.0, false, {"speed": 4.0}))
	await _scene_cost("150 balas com rastro", func():
		for i in 150:
			Bullet.fire(me, spot.call(i, 150, 16.0), right, 1.0, false, {"speed": 4.0}))
	await _scene_cost("nuke comum (raio 1,76 m) a 12 m", func():
		Bullet.fire(me, eye + fwd * 12.0, right, 1.0, false, {"speed": 3.0, "radius": 1.76}))
	await _scene_cost("nuke máxima (raio 9,25 m) a 20 m", func():
		Bullet.fire(me, eye + fwd * 20.0, right, 1.0, false, {"speed": 3.0, "radius": 9.25}))
	await _scene_cost("explosões de 6 m (teto)", func():
		for i in 14:
			Effects.explosion(game, spot.call(i, 14, 14.0), 6.0, Color(1.0, 0.55, 0.2)))
	await _scene_cost("clarões pequenos (teto)", func():
		for i in 36:
			Effects.burst(game, spot.call(i, 36, 10.0), 1.2, Color(1.0, 0.8, 0.3), 0.3))
	await _scene_cost("faíscas (teto)", func():
		for i in 16:
			Effects.sparks(game, spot.call(i, 16, 8.0), Color(1, 0.9, 0.5), 8, 6.0))
	await _scene_cost("números de dano (teto)", func():
		for i in 20:
			Effects.number(game, spot.call(i, 20, 8.0), 25.0 + i, i % 5 == 0))
	_note("chamadas de desenho no último: %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


## Mede a cena com o que spawn cria e sem nada (depois de apagar balas, áreas e efeitos;
## cleanup desfaz o que não é apagado assim, como o visual preso a um jogador).
func _scene_cost(label: String, spawn: Callable, cleanup := Callable()) -> void:
	var with := 0.0
	var without := 0.0
	var drawn := 0
	for r in ROUNDS:
		get_tree().paused = false
		spawn.call()
		await get_tree().create_timer(0.08).timeout
		get_tree().paused = true
		with += (await measure()).x
		drawn = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		if r == 0 and "--prints" in OS.get_cmdline_user_args():
			var file := label.to_lower().replace(" ", "_").replace("(", "").replace(")", "").replace(",", "").replace("+", "_")
			get_tree().root.get_texture().get_image().save_png("res://_prints/checkup_%s.png" % file.left(30))
		game._clear_bullets()
		if cleanup.is_valid():
			cleanup.call()
		await _clear_effects()
		without += (await measure()).x
	with /= ROUNDS
	without /= ROUNDS
	_note("%-34s %6.1f ms com  %6.1f sem  custo %+5.1f ms  (%d chamadas)" % [label, with, without, with - without, drawn])


## Apaga os efeitos soltos na partida (clarões, explosões, números, faíscas).
func _clear_effects() -> void:
	for n in game.get_children():
		if n is Bullet.TrailBatch:
			continue   # a malha única dos rastros fica (é reaproveitada)
		if n is MeshInstance3D or n is Label3D or n is CPUParticles3D or n is SkyPlatform 				or n.is_in_group("meteor_strikes"):
			n.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- áreas e mestras

## Bloco 3: áreas das cartas e mestras com visual próprio, os 3 bots postos na frente da
## câmera (donos das áreas), no teto de cada uma quando há teto.
func _block_areas(part: int) -> void:
	await _start_match(0)
	var me = game.me
	var cam: Camera3D = me.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var ground: Vector3 = me.global_position
	var bots: Array = game.players.filter(func(p): return p != me)
	for i in bots.size():
		bots[i].global_position = ground + fwd * 9.0 + right * (i - 1) * 4.0
		bots[i].velocity = Vector3.ZERO
	var at := func(i: int, dist := 9.0) -> Vector3:
		return ground + fwd * dist + right * (i - 1) * 4.0 + Vector3.UP * 0.2
	var area := func(k: int, r: float, per_bot: int) -> void:
		for i in bots.size():
			for j in per_bot:
				AreaField._spawn(bots[i], k, at.call(i) + right * j * 0.8, r, 10.0, 0.0)
	if part == 1:
		await _areas_part(area)
	else:
		await _masters_part(at, bots)
	_note("chamadas de desenho no último: %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _areas_part(area: Callable) -> void:
	await _scene_cost("Serra x3 (raio 3,5)", func(): area.call(AreaField.Kind.SAW, 3.5, 1))
	await _scene_cost("Chamas x3 (raio 5)", func(): area.call(AreaField.Kind.FLAMES, 5.0, 1))
	await _scene_cost("Mina x3", func(): area.call(AreaField.Kind.MINE, 4.0, 1))
	await _scene_cost("Nuvem Tóxica x18 (6 por dono)", func(): area.call(AreaField.Kind.CLOUD, 3.25, 6))
	await _scene_cost("Buraco Negro x12 (4 por dono)", func(): area.call(AreaField.Kind.HOLE, 5.0, 4))
	await _scene_cost("Serra+Chamas+Mina x3 (Escudo Duplo)", func():
		for k in [AreaField.Kind.SAW, AreaField.Kind.FLAMES, AreaField.Kind.MINE]:
			area.call(k, 4.0, 2))


func _masters_part(at: Callable, bots: Array) -> void:
	await _scene_cost("plataformas x9", func():
		for i in 9:
			SkyPlatform.spawn(game, at.call(i % 3, 7.0 + (i / 3) * 3.0) + Vector3.UP * (1.5 + i * 0.4), bots[i % 3].color))
	await _scene_cost("Chuva de Meteoros x3 marcas", func():
		for i in 3:
			MeteorStrike.spawn(game, at.call(i), bots[i], 40.0))
	await _scene_cost("Canhão Arcano (raio)", func(): bots[1]._beam_visual(2), func(): bots[1]._beam_visual(0))
	await _scene_cost("Foguete montado x3", func():
		for b in bots:
			b._ride_visual(true), func():
		for b in bots:
			b._ride_visual(false))
	await _scene_cost("Prisão de Gelo x3", func():
		for b in bots:
			b._ice_visual(true), func():
		for b in bots:
			b._ice_visual(false))


# ---------------------------------------------------------------- travadas

## Bloco 4: luta de verdade (sem pausa), 4 bots com uma build pesada, por FIGHT_TIME
## segundos. Conta os quadros acima de 50 e 100 ms só durante a luta (a troca de rodada,
## que monta a arena, fica de fora: bloco 1) e mostra o que havia nos piores. Suspeitos
## desligados pela linha de comando: --sem-som, --sem-efeitos (clarões, explosões,
## faíscas, números), --sem-numeros, --sem-faiscas.
const FIGHT_TIME := 24.0
const HEAVY := ["metralhadora", "tabelinha", "tabelinha", "teleguiada", "teleguiada", "explosiva",
	"dinamite", "fragmentacao"]


func _block_fight() -> void:
	var args := OS.get_cmdline_user_args()
	var off := []
	if "--sem-som" in args:
		Sfx.disabled = true
		off.append("som")
	for arg in args:
		if arg.begins_with("--passos="):
			Engine.max_physics_steps_per_frame = int(arg.trim_prefix("--passos="))
			off.append("limite de %d passos de física por quadro" % Engine.max_physics_steps_per_frame)
	if "--som-wav" in args:
		Sfx.test_wav = true
		off.append("som em WAV (tom)")
	if "--sem-efeitos" in args:
		Effects.disabled_kinds = ["burst", "explosion", "sparks", "number"]
		off.append("efeitos")
	if "--sem-numeros" in args:
		Effects.disabled_kinds.append("number")
		off.append("números")
	if "--sem-faiscas" in args:
		Effects.disabled_kinds.append("sparks")
		off.append("faíscas")
	_note("desligado: %s" % (", ".join(off) if not off.is_empty() else "nada"))
	GameState.test_cards = HEAVY
	GameState.autotest = true
	GameState.bot_count = 3
	GameState.test_size = 0
	get_tree().change_scene_to_file("res://scenes/match.tscn")
	await get_tree().create_timer(0.5).timeout
	game = get_tree().current_scene
	while game.phase != game.Phase.FIGHT:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var frames: Array = []   # [ms, balas, efeitos, passos de física, desenho cpu, desenho gpu]
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var last_phys := Engine.get_physics_frames()
	while Time.get_ticks_msec() - t0 < FIGHT_TIME * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var phys := Engine.get_physics_frames()
		if game.phase == game.Phase.FIGHT:
			frames.append([ms, get_tree().get_node_count_in_group("bullets"), Effects._live.duplicate(),
				phys - last_phys, RenderingServer.viewport_get_measured_render_time_cpu(vp),
				RenderingServer.viewport_get_measured_render_time_gpu(vp)])
		last_phys = phys
	var times: Array = frames.map(func(f): return f[0])
	times.sort()
	var n := times.size()
	var sum := 0.0
	for t in times:
		sum += t
	_note("luta: %d quadros, média %.1f ms, 95%% abaixo de %.1f, 99%% abaixo de %.1f, pior %.1f" % [
		n, sum / maxf(1, n), times[int(n * 0.95)], times[int(n * 0.99)], times[n - 1]])
	_note("quadros acima de 50 ms: %d   acima de 100 ms: %d" % [times.filter(func(t): return t > 50.0).size(),
		times.filter(func(t): return t > 100.0).size()])
	frames.sort_custom(func(a, b): return a[0] > b[0])
	var steps := {}
	for f in frames:
		steps[f[3]] = steps.get(f[3], 0) + 1
	_note("passos de física por quadro (passos: quadros): %s" % str(steps))
	for f in frames.slice(0, 8):
		_note("  %.0f ms  ·  %d passos de física  ·  desenho cpu %.1f gpu %.1f ms  ·  %d balas  ·  efeitos %s" % [
			f[0], f[3], f[4], f[5], f[1], str(f[2])])


# ---------------------------------------------------------------- novidades da release

## Bloco 5: o que entrou na release depois da v0.6.0. Parte 1: tela de escolha com
## moldura (por cima da partida) e a sala de teste (bonecos, atiradores, painéis). Parte
## 2: editor de baralho, loja e abertura de pacote (telas de menu). A coleção do jogador
## é guardada antes e devolvida no fim (a loja abre pacotes).
func _block_new(part: int) -> void:
	if part == 1:
		await _start_match(0)
		await cost("tela de escolha (3 cartas)", func(on):
			if on:
				game.draft.choose(CardDB.all_ids().slice(0, 3), "Teste", [])
			else:
				game.draft.close())
		get_tree().paused = false
		GameState.autotest = false
		GameState.practice = true
		get_tree().change_scene_to_file("res://scenes/match.tscn")
		await get_tree().create_timer(1.5).timeout
		game = get_tree().current_scene
		var me = game.me
		me.look_yaw = PI / 2.6
		me.rotation.y = me.look_yaw
		await get_tree().create_timer(0.3).timeout
		var base := await measure()
		_note("%-34s %6.1f ms (pior %.1f)  %d chamadas" % ["sala de teste, olhando o estande", base.x, base.y,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		await cost("4 bonecos holograma", func(on):
			for d in game.dummies:
				d.visible = on)
		await cost("painel de dano", func(on): game.practice_panel.visible = on)
		game.practice_cards.shooter_mode = 2
		me.global_position = TestRoom.DEFENSE_SPOT + Vector3(0, 0.1, 3)
		me.look_yaw = 0.0
		me.rotation.y = 0.0
		await get_tree().create_timer(1.5).timeout
		var fight := await measure()
		_note("%-34s %6.1f ms (pior %.1f)" % ["defesa com atiradores (normal)", fight.x, fight.y])
		game.practice_cards.shooter_mode = 0
		await cost("painel de cartas (B)", func(on):
			if on:
				game.practice_cards.open(me.cards, [], false)
			else:
				game.practice_cards.close())
		GameState.practice = false
		return
	var path := Collection.PATH
	var saved: Variant = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null
	get_tree().change_scene_to_file("res://scenes/deck_editor.tscn")
	await get_tree().create_timer(1.2).timeout
	var m := await measure()
	_note("%-34s %6.1f ms (pior %.1f)  %d chamadas" % ["editor de baralho", m.x, m.y,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().change_scene_to_file("res://scenes/shop.tscn")
	await get_tree().create_timer(1.0).timeout
	var shop = get_tree().current_scene
	shop.opening.visible = false
	m = await measure()
	_note("%-34s %6.1f ms (pior %.1f)" % ["loja, aba Pacotes", m.x, m.y])
	shop._open("supremo")
	await get_tree().process_frame
	await get_tree().process_frame
	var phase_worst := func(label: String, frames: Array) -> void:
		var worst := 0.0
		var sum := 0.0
		for f in frames:
			worst = maxf(worst, f)
			sum += f
		_note("%-34s %6.1f ms (pior %.1f)" % [label, sum / maxf(1, frames.size()), worst])
	_frames.clear()
	_sampling = true
	shop.opening._tear()
	await get_tree().create_timer(0.35).timeout
	_sampling = false
	phase_worst.call("abertura: rasgar", _frames.duplicate())
	_frames.clear()
	_sampling = true
	await get_tree().create_timer(0.9).timeout
	_sampling = false
	phase_worst.call("abertura: espalhar as cartas", _frames.duplicate())
	for k in 7:
		_frames.clear()
		_sampling = true
		var rarity: String = shop.opening.results[k]["rarity"]
		await shop.opening._reveal_next()
		_sampling = false
		phase_worst.call("abertura: revelar %d (%s)" % [k + 1, rarity], _frames.duplicate())
	m = await measure()
	_note("%-34s %6.1f ms (pior %.1f)" % ["abertura, 7 cartas reveladas", m.x, m.y])
	if saved == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(saved)
	_note("coleção do jogador devolvida")
