class_name Sfx
extends RefCounted
## Sons do jogo (pacote Sci-Fi Sounds da Kenney, CC0). Cada nome sorteia entre variações.

const SOUNDS := {
	"shot": ["laserSmall_000", "laserSmall_001", "laserSmall_002"],
	"shield": ["forceField_000", "forceField_002"],
	"reflect": ["laserRetro_002"],
	"hit": ["impactMetal_000", "impactMetal_002"],
	"hurt": ["impactMetal_003"],
	"explosion": ["explosionCrunch_000"],
	"death": ["lowFrequency_explosion_000"],
	"pad": ["doorOpen_001"],
	"dash": ["doorOpen_001"],
	"pickup": ["laserRetro_002"],
}
## Sons gerados em código: o "tique" de acerto e o sino de abate, curtos e agudos como em
## Overwatch e Valorant, para se destacarem de todo o resto que soa na luta.
const TONES := {
	"hitmarker": {"freqs": [2200.0, 4400.0], "gains": [1.0, 0.3], "length": 0.07, "decay": 55.0},
	"kill": {"freqs": [1320.0, 1980.0, 2640.0], "gains": [1.0, 0.6, 0.25], "length": 0.4, "decay": 9.0},
}
## Volume base de cada som, em dB. Baixado em 2026-10-05 (o usuário achava explosões e
## efeitos altos demais): explosão -4 -> -11, tiro -8 -> -12, os outros uns 4 dB.
const VOLUME := {"shot": -12.0, "shield": -10.0, "reflect": -6.0, "hit": -8.0, "hurt": -6.0,
	"explosion": -11.0, "death": -7.0, "pad": -12.0, "dash": -17.0, "pickup": -13.0,
	"hitmarker": -7.0, "kill": -6.0}
## Canal de áudio: sons do mundo vão para Efeitos; os da tela (Sfx.ui) para Interface.
const BUS_WORLD := "Efeitos"
const BUS_UI := "Interface"

## Vozes ao mesmo tempo por som e no total (2026-10-05): numa chuva de balas cada tiro e
## cada explosão criavam um tocador de som 3D, e dezenas deles ao mesmo tempo pesavam e
## só faziam barulho. Passou do teto, o som novo não toca. Tique de acerto e sino de abate
## ficam fora do teto: dizem algo a quem atirou.
const VOICES := {"shot": 6, "explosion": 4, "hit": 4, "reflect": 4, "shield": 4, "hurt": 3}
const DEFAULT_VOICES := 3
const MAX_VOICES := 24
const UNLIMITED := ["hitmarker", "kill", "death"]

static var _cache := {}
static var _live := {}
static var _live_total := 0


static func _stream(sound: String) -> AudioStream:
	if TONES.has(sound):
		if not _cache.has(sound):
			_cache[sound] = _tone(TONES[sound])
		return _cache[sound]
	if test_wav:
		if not _cache.has("_wav"):
			_cache["_wav"] = _tone(TONES["kill"])
		return _cache["_wav"]
	var file: String = SOUNDS[sound].pick_random()
	if not _cache.has(file):
		_cache[file] = load("res://assets/sounds/%s.ogg" % file)
	return _cache[file]


## Gera os tons e carrega os sons uma vez, na abertura do jogo (GameState._ready).
## Check-up de 2026-10-08: o tom do abate era gerado no primeiro uso (~40 ms sem janela,
## mais no PC do usuário) e travava o primeiro abate da sessão e a abertura de pacote.
static func prewarm() -> void:
	for sound in TONES:
		_stream(sound)
	for sound in SOUNDS:
		for file in SOUNDS[sound]:
			if not _cache.has(file):
				_cache[file] = load("res://assets/sounds/%s.ogg" % file)


## Check-up de desempenho (scripts/dev/checkup.gd, "--sem-som"): nenhum som é criado.
static var disabled := false
static var test_wav := false   # "--som-wav": todo som vira o mesmo tom WAV (testa o custo do Ogg)


static func _allowed(sound: String) -> bool:
	if disabled:
		return false
	if sound in UNLIMITED:
		return true
	return _live_total < MAX_VOICES and _live.get(sound, 0) < VOICES.get(sound, DEFAULT_VOICES)


## Conta a voz enquanto toca (o tocador some no fim do som ou junto com quem o tocou).
static func _track(player: Node, sound: String) -> void:
	_live[sound] = _live.get(sound, 0) + 1
	_live_total += 1
	player.tree_exiting.connect(func():
		_live[sound] = maxi(0, _live.get(sound, 1) - 1)
		_live_total = maxi(0, _live_total - 1))


## Som com posição no mundo (fica mais baixo de longe).
static func at(parent: Node, sound: String, pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree() or not _allowed(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(sound)
	p.volume_db = VOLUME.get(sound, 0.0)
	p.pitch_scale = randf_range(0.93, 1.07)
	p.unit_size = 12.0
	p.max_distance = 120.0
	p.bus = BUS_WORLD
	_track(p, sound)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Som "na cabeça" do jogador local (acerto, dano).
static func ui(parent: Node, sound: String) -> void:
	if parent == null or not parent.is_inside_tree() or not _allowed(sound):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _stream(sound)
	p.volume_db = VOLUME.get(sound, 0.0)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.bus = BUS_UI
	_track(p, sound)
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Amostra para a barra de volume (Configurações): toca sem posição no canal escolhido.
static func preview(parent: Node, sound: String, bus: String) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = _stream(sound)
	p.volume_db = VOLUME.get(sound, 0.0)
	p.bus = bus
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Soma de senos com queda exponencial, em PCM de 16 bits.
static func _tone(spec: Dictionary) -> AudioStreamWAV:
	var rate := 44100
	var n := int(spec["length"] * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for k in spec["freqs"].size():
			v += sin(TAU * spec["freqs"][k] * t) * spec["gains"][k]
		v *= exp(-t * spec["decay"]) * minf(1.0, t * 2000.0)   # ataque de 0,5 ms, sem estalo
		data.encode_s16(i * 2, int(clampf(v * 0.4, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
