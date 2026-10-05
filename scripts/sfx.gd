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
const VOLUME := {"shot": -8.0, "shield": -6.0, "reflect": -2.0, "hit": -4.0, "hurt": -3.0,
	"explosion": -4.0, "death": -2.0, "pad": -8.0, "dash": -14.0, "pickup": -10.0,
	"hitmarker": -6.0, "kill": -5.0}

static var _cache := {}


static func _stream(sound: String) -> AudioStream:
	if TONES.has(sound):
		if not _cache.has(sound):
			_cache[sound] = _tone(TONES[sound])
		return _cache[sound]
	var file: String = SOUNDS[sound].pick_random()
	if not _cache.has(file):
		_cache[file] = load("res://assets/sounds/%s.ogg" % file)
	return _cache[file]


## Som com posição no mundo (fica mais baixo de longe).
static func at(parent: Node, sound: String, pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(sound)
	p.volume_db = VOLUME.get(sound, 0.0)
	p.pitch_scale = randf_range(0.93, 1.07)
	p.unit_size = 12.0
	p.max_distance = 120.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Som "na cabeça" do jogador local (acerto, dano).
static func ui(parent: Node, sound: String) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = _stream(sound)
	p.volume_db = VOLUME.get(sound, 0.0)
	p.pitch_scale = randf_range(0.95, 1.05)
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
