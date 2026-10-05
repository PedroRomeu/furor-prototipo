class_name ArenaTheme
extends RefCounted
## Temas visuais das arenas: cores, texturas, céu, névoa e luz. O tema é só aparência e
## independe do estilo (que decide a forma do mapa), então qualquer estilo sai em qualquer
## tema. Sai da seed, então todas as máquinas da partida veem o mesmo sem mandar nada.
##
## Cores neutras e pouco saturadas de propósito (pedido do usuário em 2026-10-04: nada
## chamativo). As texturas são geradas em código, em tons de cinza claros, e tingidas pela
## cor do material; cada uma cobre 2 m x 2 m no mundo.
##
## Para criar um tema novo: copie uma entrada de THEMES e troque os valores.
## Papéis: floor (chão), wall (muros e peças altas), cover (peças baixas e plataformas),
## moving (peças que se mexem; um pouco mais quente para avisar), accent (plataforma de
## salto), void (o vazio lá embaixo). Texturas: grid, tiles, bricks, planks, concrete, plates.

const THEMES := [
	{"name": "Concreto",
		"floor": Color(0.44, 0.44, 0.43), "wall": Color(0.64, 0.63, 0.61), "cover": Color(0.55, 0.55, 0.54),
		"moving": Color(0.6, 0.52, 0.46), "accent": Color(0.62, 0.59, 0.50), "void": Color(0.14, 0.14, 0.15),
		"tex": {"floor": "concrete", "wall": "concrete", "cover": "grid", "moving": "plates"},
		"sky_top": Color(0.42, 0.48, 0.56), "sky_horizon": Color(0.72, 0.74, 0.76),
		"fog": Color(0.7, 0.72, 0.74), "fog_density": 0.003,
		"sun": Color(1.0, 0.98, 0.94), "sun_energy": 0.46, "ambient": Color(0.82, 0.83, 0.86), "ambient_energy": 0.51},
	{"name": "Deserto",
		"floor": Color(0.56, 0.51, 0.43), "wall": Color(0.72, 0.65, 0.54), "cover": Color(0.6, 0.53, 0.44),
		"moving": Color(0.6, 0.48, 0.4), "accent": Color(0.66, 0.61, 0.48), "void": Color(0.2, 0.17, 0.14),
		"tex": {"floor": "tiles", "wall": "bricks", "cover": "bricks", "moving": "plates"},
		"sky_top": Color(0.5, 0.58, 0.66), "sky_horizon": Color(0.84, 0.78, 0.68),
		"fog": Color(0.82, 0.76, 0.66), "fog_density": 0.004,
		"sun": Color(1.0, 0.94, 0.84), "sun_energy": 0.50, "ambient": Color(0.88, 0.84, 0.78), "ambient_energy": 0.47},
	{"name": "Neve",
		"floor": Color(0.53, 0.55, 0.58), "wall": Color(0.48, 0.5, 0.53), "cover": Color(0.58, 0.6, 0.63),
		"moving": Color(0.58, 0.54, 0.52), "accent": Color(0.53, 0.59, 0.64), "void": Color(0.16, 0.18, 0.21),
		"tex": {"floor": "concrete", "wall": "bricks", "cover": "planks", "moving": "plates"},
		"sky_top": Color(0.62, 0.67, 0.72), "sky_horizon": Color(0.86, 0.88, 0.9),
		"fog": Color(0.82, 0.84, 0.86), "fog_density": 0.004,
		"sun": Color(0.94, 0.96, 1.0), "sun_energy": 0.40, "ambient": Color(0.86, 0.89, 0.94), "ambient_energy": 0.51},
	{"name": "Bosque",
		"floor": Color(0.42, 0.45, 0.38), "wall": Color(0.5, 0.45, 0.38), "cover": Color(0.46, 0.41, 0.34),
		"moving": Color(0.55, 0.46, 0.38), "accent": Color(0.56, 0.59, 0.48), "void": Color(0.12, 0.13, 0.11),
		"tex": {"floor": "tiles", "wall": "planks", "cover": "planks", "moving": "plates"},
		"sky_top": Color(0.46, 0.53, 0.56), "sky_horizon": Color(0.7, 0.74, 0.7),
		"fog": Color(0.64, 0.69, 0.64), "fog_density": 0.005,
		"sun": Color(1.0, 0.96, 0.88), "sun_energy": 0.50, "ambient": Color(0.78, 0.82, 0.76), "ambient_energy": 0.55},
	{"name": "Galpão",
		"floor": Color(0.38, 0.38, 0.39), "wall": Color(0.5, 0.5, 0.5), "cover": Color(0.56, 0.52, 0.45),
		"moving": Color(0.58, 0.47, 0.4), "accent": Color(0.58, 0.54, 0.45), "void": Color(0.1, 0.1, 0.11),
		"tex": {"floor": "plates", "wall": "plates", "cover": "grid", "moving": "plates"},
		"sky_top": Color(0.34, 0.37, 0.42), "sky_horizon": Color(0.6, 0.6, 0.6),
		"fog": Color(0.56, 0.56, 0.57), "fog_density": 0.004,
		"sun": Color(1.0, 0.93, 0.82), "sun_energy": 0.43, "ambient": Color(0.78, 0.78, 0.8), "ambient_energy": 0.55},
	{"name": "Crepúsculo",
		"floor": Color(0.42, 0.42, 0.46), "wall": Color(0.52, 0.51, 0.55), "cover": Color(0.47, 0.46, 0.5),
		"moving": Color(0.56, 0.48, 0.46), "accent": Color(0.56, 0.54, 0.59), "void": Color(0.1, 0.1, 0.13),
		"tex": {"floor": "tiles", "wall": "concrete", "cover": "grid", "moving": "plates"},
		"sky_top": Color(0.24, 0.28, 0.38), "sky_horizon": Color(0.66, 0.58, 0.54),
		"fog": Color(0.5, 0.48, 0.52), "fog_density": 0.004,
		"sun": Color(1.0, 0.84, 0.7), "sun_energy": 0.40, "ambient": Color(0.72, 0.72, 0.82), "ambient_energy": 0.59},
]

const TEX_SIZE := 128   # pixels para 2 m; 128 com mipmaps é leve para a Intel HD

static var _textures := {}


## O tema da seed. Usa um gerador separado para não mudar o mapa que a seed já gerava.
static func pick(seed_value: int) -> int:
	if GameState.test_theme >= 0:
		return GameState.test_theme % THEMES.size()
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 7919 + 12345
	return r.randi() % THEMES.size()


static func texture(kind: String) -> Texture2D:
	if not _textures.has(kind):
		var img := _image(kind)
		img.generate_mipmaps()
		_textures[kind] = ImageTexture.create_from_image(img)
	return _textures[kind]


## Céu, névoa e luz do tema. A névoa só liga se a qualidade deixar (match._apply_quality).
static func apply_environment(t: Dictionary, env: Environment, sun: DirectionalLight3D) -> void:
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if sky:
		sky.sky_top_color = t["sky_top"]
		sky.sky_horizon_color = t["sky_horizon"]
		sky.ground_horizon_color = t["sky_horizon"]
		sky.ground_bottom_color = t["void"]
	env.fog_light_color = t["fog"]
	env.fog_density = t["fog_density"]
	env.ambient_light_color = t["ambient"]
	env.ambient_light_energy = t["ambient_energy"]
	sun.light_color = t["sun"]
	sun.light_energy = t["sun_energy"]


# ---------------------------------------------------------------- texturas

static func _image(kind: String) -> Image:
	var n := TEX_SIZE
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = kind.hash()
	noise.frequency = 0.06
	var grain := noise.get_seamless_image(n, n)
	var px := n / 2   # pixels por metro
	for y in n:
		for x in n:
			var g := grain.get_pixel(x, y).r - 0.5   # -0,5 a 0,5
			var v := 0.92 + g * 0.06
			match kind:
				"grid":
					# O xadrez antigo, bem mais suave: quadrados de 1 m ajudam a sentir a velocidade.
					v = 0.94 if ((x / px) + (y / px)) % 2 == 0 else 0.88
					if x % px == 0 or y % px == 0:
						v = 0.82
				"tiles":
					# Ladrilhos de 1 m, cada um num tom levemente diferente, rejunte fino.
					var cell := Vector2i(x / px, y / px)
					v = 0.9 + (float((cell.x * 37 + cell.y * 91) % 7) / 7.0 - 0.5) * 0.06 + g * 0.04
					if x % px < 2 or y % px < 2:
						v = 0.76
				"bricks":
					# Tijolos de 0,5 x 0,25 m, fileiras desencontradas.
					var bh := px / 4
					var row := y / bh
					var bx := (x + (px / 4 if row % 2 == 1 else 0)) % (px / 2)
					v = 0.9 + (float((row * 13 + (x + (px / 4 if row % 2 == 1 else 0)) / (px / 2) * 29) % 5) / 5.0 - 0.5) * 0.06 + g * 0.05
					if y % bh < 2 or bx < 2:
						v = 0.74
				"planks":
					# Tábuas de 0,25 m de largura, com veio esticado ao longo delas.
					var w := px / 4
					var stretched := grain.get_pixel((x * 4) % n, y).r - 0.5
					v = 0.88 + stretched * 0.1 + float((y / w * 17) % 4) / 4.0 * 0.04
					if y % w < 1:
						v = 0.72
				"concrete":
					# Manchas leves e uma junta a cada 2 m (a borda da textura).
					v = 0.9 + g * 0.05
					if x < 1 or y < 1:
						v = 0.78
				"plates":
					# Chapas de 1 m com emenda e rebites em dois cantos.
					v = 0.86 + g * 0.05
					var lx := x % px
					var ly := y % px
					if lx < 2 or ly < 2:
						v = 0.7
					elif Vector2(lx, ly).distance_to(Vector2(6, 6)) < 2.0 \
							or Vector2(lx, ly).distance_to(Vector2(px - 5, px - 5)) < 2.0:
						v = 0.98
			img.set_pixel(x, y, Color(v, v, v))
	return img
