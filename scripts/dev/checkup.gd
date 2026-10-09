extends Node
## Check-up de desempenho (2026-10-08, pedido do usuário: medir cada parte do jogo de
## tempos em tempos e chegar a um "ok" por parte). Roda COM JANELA, nas configurações de
## vídeo salvas do jogador (resolução, modo, qualidade), com o VSync desligado só aqui.
##   Godot --path . res://scenes/dev/checkup.tscn -- --bloco=1
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
		_: _note("bloco desconhecido")
	_save()
	get_tree().quit()


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


## Mede a cena com o que spawn cria e sem nada (depois de apagar balas e efeitos).
func _scene_cost(label: String, spawn: Callable) -> void:
	get_tree().paused = false
	spawn.call()
	await get_tree().create_timer(0.08).timeout
	get_tree().paused = true
	var with := (await measure()).x
	var drawn := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	game._clear_bullets()
	await _clear_effects()
	var without := (await measure()).x
	_note("%-34s %6.1f ms com  %6.1f sem  custo %+5.1f ms  (%d chamadas)" % [label, with, without, with - without, drawn])


## Apaga os efeitos soltos na partida (clarões, explosões, números, faíscas).
func _clear_effects() -> void:
	for n in game.get_children():
		if n is Bullet.TrailBatch:
			continue   # a malha única dos rastros fica (é reaproveitada)
		if n is MeshInstance3D or n is Label3D or n is CPUParticles3D:
			n.queue_free()
	await get_tree().process_frame
