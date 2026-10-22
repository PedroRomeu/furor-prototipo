class_name MapList
extends RefCounted
## Mapas (2026-10-05, item 2 das metas da v0.3.0; organização do usuário, números meus).
## Um mapa é um estilo do desenho (Arena.STYLES) num tamanho (SIZES): 4 x 3 = 12 mapas,
## numerados estilo * 3 + tamanho. Cada rodada gera um desenho novo do mapa sorteado; as
## cores, céu e luz (o "ambiente", ArenaTheme) saem à parte, também sorteados.
## - Online: o anfitrião liga e desliga cada mapa na sala (Net.maps, salvo em settings.cfg).
##   Mapa que ele nunca mexeu fica no automático: os grandes desligados com 2 na arena
##   (1x1 e Duelos), ligados com 3 ou 4. Clicou num mapa, vale o que ele escolheu.
## - Treino: decide o número de bots (training()).

const STYLE_IDS := ["patio", "ruinas", "torres", "fabrica"]   # na ordem de Arena.STYLES
## half: metade do lado do mapa com 2 jogadores (cada jogador a mais soma 4 m).
## density: quantas vezes mais peças que o pequeno (segue a área). items: rodadas de itens.
## divided: muros altos do centro até a borda, entre os lados de cada um (Arena._dividers),
## para lutas em cantos diferentes não se verem.
const SIZES := [
	{"id": "pequeno", "name": "Small", "half": Vector2(32, 42), "density": 1.0, "items": 1, "divided": false},
	{"id": "medio", "name": "Medium", "half": Vector2(50, 56), "density": 2.0, "items": 2, "divided": false},
	{"id": "grande", "name": "Large", "half": Vector2(70, 75), "density": 3.5, "items": 3, "divided": true},
]
const LARGE := 2


static func count() -> int:
	return STYLE_IDS.size() * SIZES.size()


static func style_of(index: int) -> int:
	return index / SIZES.size()


static func size_of(index: int) -> int:
	return index % SIZES.size()


static func id(index: int) -> String:
	return "%s_%s" % [STYLE_IDS[style_of(index)], SIZES[size_of(index)]["id"]]


## Nome traduzido do mapa ("Large Ruins" / "Ruínas grande").
static func map_name(index: int) -> String:
	return Lang.t("{size} {style}").format({"size": size_name(size_of(index)), "style": style_name(style_of(index))})


## Nome traduzido do estilo e do tamanho (SIZES e Arena.STYLES guardam o inglês; em
## português o tamanho vem minúsculo, "grande", como antes).
static func style_name(style: int) -> String:
	return Lang.t(Arena.STYLES[style])


static func size_name(z: int) -> String:
	return Lang.t(SIZES[z]["name"], "size")


## Ligado no automático: tudo, menos os grandes com 2 na arena.
static func auto_on(index: int, players: int) -> bool:
	return size_of(index) != LARGE or players >= 3


## choices: id -> true/false do que o anfitrião clicou; o que não está lá é automático.
static func is_on(choices: Dictionary, index: int, players: int) -> bool:
	return choices.get(id(index), auto_on(index, players))


static func enabled(choices: Dictionary, players: int) -> Array:
	var out := range(count()).filter(func(i): return is_on(choices, i, players))
	if out.is_empty():
		# Não deveria acontecer (a sala não deixa desligar o último), mas sem mapa não há jogo.
		out = range(count()).filter(func(i): return choices.get(id(i), true))
	if out.is_empty():
		out = range(count()).filter(func(i): return size_of(i) == 0)
	return out


## Treino: 1 bot só pequenos; 2 bots pequenos e médios; 3 bots todos (pedido do usuário).
## Teste: "--tamanho=grande" usa só os desse tamanho.
static func training(bots: int) -> Array:
	var sizes := range(clampi(bots, 1, SIZES.size()))
	if GameState.test_size >= 0:
		sizes = [GameState.test_size]
	return range(count()).filter(func(i): return size_of(i) in sizes)


## Sorteia um mapa da lista, sem repetir o da rodada anterior quando há outro.
static func pick(pool: Array, last: int) -> int:
	var options := pool.filter(func(i): return i != last)
	if options.is_empty():
		options = pool
	return options[randi() % options.size()]


## Nomes dos tamanhos para a ferramenta de tradução (scenes/dev/i18n.tscn).
static func i18n_strings() -> Array:
	return SIZES.map(func(z): return [z["name"], "size", "scripts/arena/map_list.gd"])


static func size_index(size_id: String) -> int:
	for i in SIZES.size():
		if SIZES[i]["id"] == size_id:
			return i
	return -1
