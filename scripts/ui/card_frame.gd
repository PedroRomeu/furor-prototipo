class_name CardFrame
## Moldura das cartas (escolha, editor, escolha da mestra): borda na cor do grupo, brilho
## por fora e o fundo tingido no topo, como as cartas do ícone do jogo. Cada moldura é uma
## textura pequena gerada uma vez e esticada em 9 partes (StyleBoxTexture): uma chamada de
## desenho por carta, sem formas desenhadas a cada quadro.

const SIZE := 64          # lado da textura
const RADIUS := 12.0      # canto arredondado
const GLOW := 10.0        # largura do brilho por fora da carta

## Estados: apagada (editor, fora do baralho), acesa e com o mouse em cima.
## [força do brilho, força da borda, tinta do fundo]
const LOOKS := {
	"dim": [0.0, 0.32, 0.03],
	"dim_hot": [0.0, 0.55, 0.06],
	"lit": [0.22, 0.85, 0.10],
	"hot": [0.42, 1.0, 0.16],
}

static var _cache := {}


## Estilo pronto para o painel da carta. cat: grupo; look: chave de LOOKS; thick: borda
## mais grossa (mestras); margin: espaço interno.
static func style(cat: String, look := "lit", thick := false, margin := 16.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _texture(cat, look, thick)
	s.set_texture_margin_all(GLOW + RADIUS)
	s.set_expand_margin_all(GLOW)      # o brilho fica fora da área da carta
	s.set_content_margin_all(margin)
	return s


## Símbolo do grupo (assets/card_icons/grupo_<grupo>.svg).
static func symbol(cat: String) -> Texture2D:
	var key := "sym_" + cat
	if not _cache.has(key):
		_cache[key] = load("res://assets/card_icons/grupo_%s.svg" % cat.to_lower())
	return _cache[key]


## TextureRect do símbolo na cor do grupo, para o canto da carta.
static func symbol_rect(cat: String, side := 18.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = symbol(cat)
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = CardDB.CATEGORY_COLORS[cat].lerp(Color.WHITE, 0.1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.tooltip_text = cat
	return r


static func _texture(cat: String, look: String, thick: bool) -> Texture2D:
	var key := "%s/%s/%s" % [cat, look, thick]
	if not _cache.has(key):
		var p: Array = LOOKS[look]
		_cache[key] = _make(CardDB.CATEGORY_COLORS[cat], p[0], p[1], p[2], 3.0 if thick else 2.0)
	return _cache[key]


static func _make(color: Color, glow: float, border: float, tint: float, width: float) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0 - GLOW                     # meia largura da carta
	var line := Ui.SURFACE.lerp(color, 0.15).lerp(color, border * 0.85)
	for y in SIZE:
		# Tinta da cor do grupo: forte no topo, some até o meio da textura (o meio estica
		# com a carta, então o degradê vai até perto do pé).
		var fade := clampf((y - GLOW) / (SIZE - 2.0 * GLOW), 0.0, 1.0)
		var fill := Ui.SURFACE.lerp(color, tint * (1.0 - fade))
		for x in SIZE:
			var q := Vector2(absf(x + 0.5 - SIZE / 2.0), absf(y + 0.5 - SIZE / 2.0)) \
				- Vector2(half - RADIUS, half - RADIUS)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - RADIUS
			var cover := clampf(0.5 - d, 0.0, 1.0)
			var body := fill.lerp(line, clampf(d + width + 0.5, 0.0, 1.0))
			var halo := 0.0
			if glow > 0.0 and d > -1.0:
				halo = glow * pow(clampf(1.0 - maxf(d, 0.0) / GLOW, 0.0, 1.0), 2.0)
			var a := cover + halo * (1.0 - cover)
			if a <= 0.0:
				img.set_pixel(x, y, Color(color, 0.0))
				continue
			var rgb := (Color(body.r, body.g, body.b) * cover + Color(color.r, color.g, color.b) * halo * (1.0 - cover)) / a
			img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return ImageTexture.create_from_image(img)
