extends Node
## Catálogo de cartas. Para criar uma carta nova basta adicionar uma entrada em CARDS.
## Cada modificador mexe num atributo de Player.BASE_STATS:
##   "add": soma ao valor base
##   "mul": porcentagem, aplicada depois das somas; melhorias do mesmo atributo somam
##          entre si e pioras multiplicam (ver compute_stats)
## "max": quantas vezes a mesma carta pode ser escolhida na partida (sem "max", sem limite).
## Ideias tiradas de OVERKILL (Roblox) e ROUNDS (Landfall), os jogos que inspiraram o Furor.
## São 88 cartas para um baralho de no máximo 50: é preciso deixar algumas de fora.
##
## Cartas mestras ("master": true, em MASTERS): uma por baralho, fora da contagem, e o
## jogador começa toda partida com ela. Trazem uma mecânica própria, mais forte que a de
## uma carta comum; "cooldown" é a recarga da habilidade na tecla Q (sem ele, é passiva).

const DECK_MIN := 30
const DECK_MAX := 50
const MAX_COPIES := 3

## Raridade: por enquanto só uma etiqueta (o usuário vai ligá-la à forma de ganhar cartas).
## Comum: número puro com custo. Raro: efeito útil ou número forte. Épico: muda o jeito de
## jogar. Lendário: define uma build. Mítico: só as cartas mestras.
const RARITIES := {
	"comum": {"name": "Comum", "color": Color(0.72, 0.74, 0.78)},
	"raro": {"name": "Raro", "color": Color(0.35, 0.65, 1.0)},
	"epico": {"name": "Épico", "color": Color(0.78, 0.42, 1.0)},
	"lendario": {"name": "Lendário", "color": Color(1.0, 0.68, 0.15)},
	"mitico": {"name": "Mítico", "color": Color(1.0, 0.32, 0.38)},
}

const CATEGORY_COLORS := {
	"Arma": Color(1.0, 0.75, 0.3),
	"Balas": Color(1.0, 0.45, 0.4),
	"Escudo": Color(0.45, 0.85, 1.0),
	"Corpo": Color(0.5, 0.95, 0.5),
	"Movimento": Color(0.75, 0.6, 1.0),
}

## Limites para as combinações de cartas não quebrarem o jogo.
const LIMITS := {
	"max_health": [20.0, 1000.0],
	"mag_size": [1, 99],
	"fire_interval": [0.08, 5.0],
	"reload_time": [0.2, 10.0],
	"bullet_speed": [15.0, 400.0],
	"shield_cooldown": [0.3, 20.0],
	"slow": [0.0, 0.7],
	"move_speed": [3.0, 20.0],
	"body_scale": [0.45, 1.8],
	"shield_size": [1.0, 2.5],
	"blind": [0.0, 1.5],
	"crit_chance": [0.0, 0.6],
	"dash_cooldown": [0.2, 5.0],
	# Tetos dos efeitos que somam por cópia (2026-10-04): sem eles, 3 cópias de duas cartas
	# davam explosão de 21 m, roubo de vida de 75% etc.
	"explosion": [0.0, 6.0],
	"lifesteal": [0.0, 0.5],
	"poison": [0.0, 1.0],
	"knockback": [0.0, 24.0],
	"execute": [0.0, 1.0],
	"last_shot": [1.0, 4.0],
	"split": [0, 8],
	"bounces": [0, 6],
	"bounce_damage": [0.0, 1.0],
	"grow": [0.0, 1.6],
	"regen": [0.0, 12.0],
	"reflect_mult": [1.0, 2.5],
	"bullet_count": [1, 13],
}

## Atributos em que a porcentagem de melhoria soma em vez de multiplicar (ver compute_stats).
## Os que não estão aqui (gravidade da bala, tamanho do corpo) multiplicam sempre.
const HIGHER_BETTER := ["damage", "max_health", "bullet_speed", "bullet_radius", "move_speed",
	"jump_velocity", "dash_power", "air_control", "slide_boost", "shield_size", "mag_size"]
const LOWER_BETTER := ["fire_interval", "reload_time", "shield_cooldown", "dash_cooldown"]

## Piso das pioras (2026-10-04, pedido do usuário: investir em perder algo não pode afundar o
## atributo para sempre). As pioras de um atributo param em PENALTY_FLOOR x a base (ou
## PENALTY_CEIL x, nos de "menos é melhor"), e as melhorias contam a partir dali.
const PENALTY_FLOOR := 0.35
const PENALTY_CEIL := 2.5
const PENALTY_FLOOR_ABS := {"mag_size": 1}   # pente: as perdas param em 1 bala

const MASTER_DEFAULT := "corrente"
const MASTERS := {
	"bazuca": {"name": "Bazuca", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: troca a arma por uma bazuca por 6 s. 3 foguetes retos, com o dobro do dano, que explodem (4 m). Recarga de 18 s.",
		"mods": [{"stat": "bazooka", "add": 1}]},
	"perfurante": {"name": "Perfurante", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 12.0,
		"desc": "Q: os próximos 3 tiros vão retos, sem queda, 3x mais rápidos e atravessando paredes. Recarga de 12 s.",
		"mods": [{"stat": "pierce", "add": 1}]},
	"bastiao": {"name": "Bastião", "cat": "Escudo", "rarity": "mitico", "master": true, "cooldown": 14.0,
		"desc": "Q: ergue à sua frente uma parede de energia por 4 s que devolve as balas inimigas. As suas passam. Recarga de 14 s.",
		"mods": [{"stat": "barrier", "add": 1}]},
	"ultimo_suspiro": {"name": "Último Suspiro", "cat": "Corpo", "rarity": "mitico", "master": true,
		"desc": "Uma vez por rodada, o golpe fatal te deixa com 1 de vida e sem morrer por 3 s. Abata alguém nesse tempo e volte com metade da vida.",
		"mods": [{"stat": "last_stand", "add": 1}]},
	"corrente": {"name": "Corrente", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 8.0,
		"desc": "Q: impulso reto para cima, de uns 8 m. Funciona também no ar. Recarga de 8 s.",
		"mods": [{"stat": "updraft", "add": 1}]},
}

## Mestras guardadas para voltar no futuro (fora do jogo: não entram em CARDS). O código
## continua em bullet.gd ("guided"). Piloto saiu em 2026-10-04: na prática ficou confuso.
const SHELVED_MASTERS := {
	"piloto": {"name": "Piloto", "cat": "Balas", "master": true,
		"desc": "Suas balas seguem a sua mira, sem queda: depois de atirar, mova o mouse para guiá-las em curva.",
		"mods": [{"stat": "guided", "add": 1}]},
}
## Baralho salvo com uma mestra que saiu passa para esta (ver GameState.load_decks).
const MASTER_REPLACED := {"piloto": "perfurante"}

## Arquétipos: etiquetas para achar cartas que combinam (filtro do editor de baralho, ideia
## do usuário inspirada no Marvel Snap). Uma carta pode estar em vários; misturar é livre.
## Toda carta comum precisa estar em pelo menos um (o autoteste confere).
const ARCHETYPES := {
	"Ricochete": {"desc": "Balas que quicam nas paredes ou voltam.",
		"cards": ["ricochete", "quique_certeiro", "tabelinha", "fragmentacao", "bumerangue"]},
	"Explosão": {"desc": "Dano em área.",
		"cards": ["explosiva", "morteiro", "detonacao", "fragmentacao", "pulo_foguete", "chuva_de_bombas", "meteoro"]},
	"Nuke": {"desc": "Poucas balas enormes, cada uma com muito dano.",
		"cards": ["calibre_pesado", "combinar", "bala_gigante", "bala_de_canhao", "canhao_de_vidro", "fragil",
			"ultima_bala", "sortudo", "bola_de_neve", "tabelinha", "preguicosa", "executor", "furia"]},
	"Chuva de balas": {"desc": "Muitas balas, pente cheio, tiro e recarga rápidos.",
		"cards": ["gatilho_leve", "pente_estendido", "maos_rapidas", "cano_duplo", "escopeta", "rajada",
			"transbordar", "imprudente", "metralhadora", "saque_rapido", "recarga_tatica"]},
	"Atirador": {"desc": "Acertar de longe e por trás das paredes.",
		"cards": ["polvora_extra", "olho_de_aguia", "fantasma", "teleguiada", "sortudo", "preguicosa", "radar", "camuflagem"]},
	"Controle": {"desc": "Atrapalhar o inimigo: lento, cego, envenenado, empurrado.",
		"cards": ["veneno", "congelante", "flash", "atordoante", "propulsao", "troca_troca", "onda_de_choque"]},
	"Espelho": {"desc": "Refletir as balas do inimigo com o escudo.",
		"cards": ["escudo_firme", "reflexos", "espelho_cortante", "adrenalina", "espelho_duplo",
			"espelho_perseguidor", "espelho_gigante", "escudo_duplo", "eco"]},
	"Escudo de ataque": {"desc": "O escudo como arma, de perto.",
		"cards": ["pancada", "onda_de_choque", "investida", "nova", "chuva_de_bombas", "teleporte",
			"couraca", "fortaleza", "restauracao", "recarga_tatica", "ultima_defesa"]},
	"Corpo a corpo": {"desc": "Encostar no inimigo e bater.",
		"cards": ["escopeta", "atropelar", "cacador", "sede_de_sangue", "meteoro", "troca_troca",
			"pancada", "investida", "cacada"]},
	"Tanque": {"desc": "Vida, cura e colete.",
		"cards": ["vigor", "tanque", "defensor", "sanguessuga", "regeneracao", "fenix", "gigantao",
			"fortaleza", "couraca", "restauracao", "eco"]},
	"Aéreo": {"desc": "Ficar no alto: pulos, parede, planar.",
		"cards": ["pulo_duplo", "impulso", "escalador", "pena", "molas", "planador", "embalo", "meteoro", "pulo_foguete"]},
	"Dash": {"desc": "Dash mais vezes, mais longe e com efeito.",
		"cards": ["impulso", "folego", "dash_longo", "deslize_turbo", "esquiva", "atropelar", "saque_rapido",
			"cacada", "botas_leves"]},
	"Tudo ou nada": {"desc": "Troca vida por poder.",
		"cards": ["fragil", "canhao_de_vidro", "imprudente", "nanico", "furia", "fenix", "molas"]},
}

## O corpo cresce com a vida máxima, de leve (como no Furor): 1,8x de vida = 19% maior,
## metade da vida = 19% menor. Soma-se ao tamanho das cartas (Nanico, Gigantão).
const HEALTH_SIZE_EXP := 0.3

## Todas as cartas: as comuns abaixo e as mestras (MASTERS, juntadas em _init).
var CARDS := {
	# Arma
	"calibre_pesado": {"name": "Calibre Pesado", "cat": "Arma", "rarity": "comum",
		"desc": "+35% de dano, mas atira 10% mais devagar.",
		"mods": [{"stat": "damage", "mul": 1.35}, {"stat": "fire_interval", "mul": 1.1}]},
	"gatilho_leve": {"name": "Gatilho Leve", "cat": "Arma", "rarity": "comum",
		"desc": "Atira 30% mais rápido, -10% de dano.",
		"mods": [{"stat": "fire_interval", "mul": 0.7}, {"stat": "damage", "mul": 0.9}]},
	"pente_estendido": {"name": "Pente Estendido", "cat": "Arma", "rarity": "comum",
		"desc": "+4 balas no pente, recarga 15% mais lenta.",
		"mods": [{"stat": "mag_size", "add": 4}, {"stat": "reload_time", "mul": 1.15}]},
	"maos_rapidas": {"name": "Mãos Rápidas", "cat": "Arma", "rarity": "comum",
		"desc": "Recarrega 40% mais rápido.",
		"mods": [{"stat": "reload_time", "mul": 0.6}]},
	"polvora_extra": {"name": "Pólvora Extra", "cat": "Arma", "rarity": "comum",
		"desc": "Balas 50% mais rápidas.",
		"mods": [{"stat": "bullet_speed", "mul": 1.5}]},
	"cano_duplo": {"name": "Cano Duplo", "cat": "Arma", "rarity": "raro",
		"desc": "+1 bala por tiro e +1 no pente, -25% de dano.",
		"mods": [{"stat": "bullet_count", "add": 1}, {"stat": "mag_size", "add": 1}, {"stat": "damage", "mul": 0.75}]},
	"escopeta": {"name": "Escopeta", "cat": "Arma", "rarity": "raro",
		"desc": "+4 balas por tiro, bem abertas. -55% de dano, +2 no pente.",
		"mods": [{"stat": "bullet_count", "add": 4}, {"stat": "spread", "add": 3.0},
			{"stat": "mag_size", "add": 2}, {"stat": "damage", "mul": 0.45}]},
	"rajada": {"name": "Rajada", "cat": "Arma", "rarity": "raro",
		"desc": "Cada tiro vira uma rajada de 3, gastando 1 bala. -40% de dano.",
		"mods": [{"stat": "burst", "add": 2}, {"stat": "damage", "mul": 0.6}]},
	"combinar": {"name": "Combinar", "cat": "Arma", "rarity": "raro",
		"desc": "+75% de dano, -2 balas no pente.",
		"mods": [{"stat": "damage", "mul": 1.75}, {"stat": "mag_size", "add": -2}]},
	"transbordar": {"name": "Transbordar", "cat": "Arma", "rarity": "raro",
		"desc": "+9 balas no pente, -33% de dano, recarga +0,8 s.",
		"mods": [{"stat": "mag_size", "add": 9}, {"stat": "damage", "mul": 0.67}, {"stat": "reload_time", "add": 0.8}]},
	"bala_gigante": {"name": "Bala Gigante", "cat": "Arma", "rarity": "raro",
		"desc": "Balas 3x maiores e +25% de dano. Recarga +0,25 s.",
		"mods": [{"stat": "bullet_radius", "mul": 3.0}, {"stat": "damage", "mul": 1.25}, {"stat": "reload_time", "add": 0.25}]},
	"bala_de_canhao": {"name": "Bala de Canhão", "cat": "Arma", "rarity": "raro",
		"desc": "+60% de dano e balas 2x maiores, mas 40% mais lentas.",
		"mods": [{"stat": "damage", "mul": 1.6}, {"stat": "bullet_radius", "mul": 2.0}, {"stat": "bullet_speed", "mul": 0.6}]},
	"imprudente": {"name": "Imprudente", "cat": "Arma", "rarity": "epico",
		"desc": "Atira 2x mais rápido. Recarga 50% mais lenta e -15% de vida.",
		"mods": [{"stat": "fire_interval", "mul": 0.5}, {"stat": "reload_time", "mul": 1.5}, {"stat": "max_health", "mul": 0.85}]},

	"metralhadora": {"name": "Metralhadora", "cat": "Arma", "rarity": "epico",
		"desc": "Automática: segure para atirar. Atira 3x mais rápido e +10 balas no pente, mas -65% de dano. Recarga +0,25 s.",
		"mods": [{"stat": "auto_fire", "add": 1}, {"stat": "fire_interval", "mul": 0.33}, {"stat": "mag_size", "add": 10},
			{"stat": "damage", "mul": 0.35}, {"stat": "reload_time", "add": 0.25}]},
	"canhao_de_vidro": {"name": "Canhão de Vidro", "cat": "Arma", "rarity": "epico",
		"desc": "+100% de dano, -50% de vida.",
		"mods": [{"stat": "damage", "mul": 2.0}, {"stat": "max_health", "mul": 0.5}]},
	"olho_de_aguia": {"name": "Olho de Águia", "cat": "Arma", "rarity": "epico",
		"desc": "Balas 2x mais rápidas e sem queda, +40% de dano. Atira 60% mais devagar, -1 bala no pente.",
		"mods": [{"stat": "bullet_speed", "mul": 2.0}, {"stat": "bullet_gravity", "mul": 0.0},
			{"stat": "damage", "mul": 1.4}, {"stat": "fire_interval", "mul": 1.6}, {"stat": "mag_size", "add": -1}]},
	"morteiro": {"name": "Morteiro", "cat": "Arma", "rarity": "epico",
		"desc": "Balas em arco alto que explodem (raio de 4 m), +30% de dano. 40% mais lentas.",
		"mods": [{"stat": "bullet_gravity", "mul": 3.5}, {"stat": "bullet_speed", "mul": 0.6},
			{"stat": "explosion", "add": 4.0}, {"stat": "damage", "mul": 1.3}]},
	"ultima_bala": {"name": "Última Bala", "cat": "Arma", "rarity": "raro",
		"desc": "A última bala do pente causa 2,5x o dano.",
		"mods": [{"stat": "last_shot", "add": 1.5}]},
	"sortudo": {"name": "Sortudo", "cat": "Arma", "rarity": "epico",
		"desc": "Cada bala tem 20% de chance de ser crítica: 2,5x o dano.",
		"mods": [{"stat": "crit_chance", "add": 0.2}]},

	# Balas
	"ricochete": {"name": "Ricochete", "cat": "Balas", "rarity": "comum",
		"desc": "As balas quicam uma vez a mais nas paredes.",
		"mods": [{"stat": "bounces", "add": 1}]},
	"teleguiada": {"name": "Teleguiada", "cat": "Balas", "rarity": "lendario",
		"desc": "Algumas balas procuram o inimigo que passar perto delas e curvam um pouco na direção dele. Mais cópias: mais balas, mais alcance, curva mais forte. -10% de dano, recarga +0,25 s.",
		"mods": [{"stat": "homing", "add": 1.0}, {"stat": "damage", "mul": 0.9}, {"stat": "reload_time", "add": 0.25}]},
	"fantasma": {"name": "Bala Fantasma", "cat": "Balas", "rarity": "lendario", "max": 2,
		"desc": "O primeiro tiro de cada pente atravessa paredes (com 2 cópias, os dois primeiros). -10% de dano.",
		"mods": [{"stat": "ghost", "add": 1}, {"stat": "damage", "mul": 0.9}]},
	"explosiva": {"name": "Explosiva", "cat": "Balas", "rarity": "epico",
		"desc": "As balas explodem ao bater (raio de 3 m). -15% de dano.",
		"mods": [{"stat": "explosion", "add": 3.0}, {"stat": "damage", "mul": 0.85}]},
	"veneno": {"name": "Veneno", "cat": "Balas", "rarity": "raro",
		"desc": "Quem você acerta perde mais 50% do dano ao longo de 3 s.",
		"mods": [{"stat": "poison", "add": 0.5}]},
	"congelante": {"name": "Congelante", "cat": "Balas", "rarity": "raro",
		"desc": "Quem você acerta fica 35% mais lento por 1,5 s.",
		"mods": [{"stat": "slow", "add": 0.35}]},
	"propulsao": {"name": "Propulsão", "cat": "Balas", "rarity": "comum",
		"desc": "As balas empurram quem levar o tiro. Recarga +0,25 s.",
		"mods": [{"stat": "knockback", "add": 12.0}, {"stat": "reload_time", "add": 0.25}]},
	"quique_certeiro": {"name": "Quique Certeiro", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "+1 quique. Ao quicar, a bala vira um pouco para o inimigo e passa a procurá-lo como a Teleguiada. Cópias de Teleguiada deixam isso mais forte. -20% de dano.",
		"mods": [{"stat": "target_bounce", "add": 1}, {"stat": "bounces", "add": 1}, {"stat": "damage", "mul": 0.8}]},
	"atordoante": {"name": "Atordoante", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Acertar o inimigo bloqueia o escudo dele por 1,5 s. Atira 10% mais devagar.",
		"mods": [{"stat": "shield_break", "add": 1}, {"stat": "fire_interval", "mul": 1.1}]},
	"sanguessuga": {"name": "Sanguessuga", "cat": "Balas", "rarity": "epico",
		"desc": "Recupera 25% do dano que causar. +25% de vida.",
		"mods": [{"stat": "lifesteal", "add": 0.25}, {"stat": "max_health", "mul": 1.25}]},
	"executor": {"name": "Executor", "cat": "Balas", "rarity": "raro",
		"desc": "+60% de dano em quem está abaixo de 40% da vida.",
		"mods": [{"stat": "execute", "add": 0.6}]},

	"bumerangue": {"name": "Bumerangue", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Depois de meio segundo as balas dão meia-volta e voltam para você, acertando de novo no caminho.",
		"mods": [{"stat": "boomerang", "add": 1}]},
	"tabelinha": {"name": "Tabelinha", "cat": "Balas", "rarity": "lendario",
		"desc": "+2 quiques, e cada quique soma +30% do dano de saída à bala.",
		"mods": [{"stat": "bounces", "add": 2}, {"stat": "bounce_damage", "add": 0.3}]},
	"detonacao": {"name": "Detonação", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "As balas grudam onde batem e explodem 0,6 s depois (raio de 3,5 m). Recarga +0,25 s.",
		"mods": [{"stat": "sticky", "add": 1}, {"stat": "reload_time", "add": 0.25}]},
	"fragmentacao": {"name": "Fragmentação", "cat": "Balas", "rarity": "epico",
		"desc": "Ao bater na parede, a bala se parte em 4 estilhaços com 40% do dano.",
		"mods": [{"stat": "split", "add": 4}]},
	"bola_de_neve": {"name": "Bola de Neve", "cat": "Balas", "rarity": "lendario",
		"desc": "Nos primeiros 2 s de voo a bala cresce e ganha até +80% de dano.",
		"mods": [{"stat": "grow", "add": 0.8}]},
	"troca_troca": {"name": "Troca-Troca", "cat": "Balas", "rarity": "lendario", "max": 1,
		"desc": "Acertar o inimigo troca vocês de lugar. -15% de dano.",
		"mods": [{"stat": "swap", "add": 1}, {"stat": "damage", "mul": 0.85}]},
	"flash": {"name": "Flash", "cat": "Balas", "rarity": "raro",
		"desc": "Acertar o inimigo deixa a tela dele branca por 0,6 s.",
		"mods": [{"stat": "blind", "add": 0.6}]},
	"preguicosa": {"name": "Bala Preguiçosa", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "As balas saem devagar e aceleram até 2,5x a velocidade. +25% de dano.",
		"mods": [{"stat": "lazy", "add": 1}, {"stat": "damage", "mul": 1.25}]},

	# Escudo
	"escudo_firme": {"name": "Escudo Firme", "cat": "Escudo", "rarity": "comum",
		"desc": "O escudo dura +0,15 s.",
		"mods": [{"stat": "shield_duration", "add": 0.15}]},
	"reflexos": {"name": "Reflexos", "cat": "Escudo", "rarity": "comum",
		"desc": "O escudo volta 30% mais rápido.",
		"mods": [{"stat": "shield_cooldown", "mul": 0.7}]},
	"defensor": {"name": "Defensor", "cat": "Escudo", "rarity": "comum",
		"desc": "+25% de vida e o escudo volta 0,4 s mais rápido.",
		"mods": [{"stat": "max_health", "mul": 1.25}, {"stat": "shield_cooldown", "add": -0.4}]},
	"espelho_cortante": {"name": "Espelho Cortante", "cat": "Escudo", "rarity": "raro",
		"desc": "Balas refletidas causam +75% de dano.",
		"mods": [{"stat": "reflect_mult", "add": 0.75}]},
	"adrenalina": {"name": "Adrenalina", "cat": "Escudo", "rarity": "epico", "max": 1,
		"desc": "Refletir uma bala recarrega o escudo na hora.",
		"mods": [{"stat": "reflect_refund", "add": 1}]},
	"espelho_duplo": {"name": "Espelho Duplo", "cat": "Escudo", "rarity": "epico",
		"desc": "Cada bala refletida volta acompanhada de mais uma.",
		"mods": [{"stat": "reflect_split", "add": 1}]},
	"espelho_perseguidor": {"name": "Espelho Perseguidor", "cat": "Escudo", "rarity": "epico",
		"desc": "Balas refletidas perseguem quem atirou.",
		"mods": [{"stat": "reflect_homing", "add": 3.0}]},
	"recarga_tatica": {"name": "Recarga Tática", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Levantar o escudo enche o pente.",
		"mods": [{"stat": "shield_reload", "add": 1}]},
	"investida": {"name": "Investida", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Levantar o escudo te lança para frente.",
		"mods": [{"stat": "shield_dash", "add": 1}]},
	"onda_de_choque": {"name": "Onda de Choque", "cat": "Escudo", "rarity": "raro",
		"desc": "O escudo empurra o inimigo a até 8 m e causa 10 de dano. Escudo +0,3 s de recarga.",
		"mods": [{"stat": "shield_shockwave", "add": 1}, {"stat": "shield_cooldown", "add": 0.3}]},
	"restauracao": {"name": "Restauração", "cat": "Escudo", "rarity": "comum",
		"desc": "Levantar o escudo cura 12 de vida.",
		"mods": [{"stat": "shield_heal", "add": 12.0}]},
	"nova": {"name": "Nova", "cat": "Escudo", "rarity": "epico",
		"desc": "O escudo dispara 6 balas em volta de você (meio dano). Escudo +0,5 s de recarga.",
		"mods": [{"stat": "shield_nova", "add": 6}, {"stat": "shield_cooldown", "add": 0.5}]},

	"teleporte": {"name": "Teleporte", "cat": "Escudo", "rarity": "lendario", "max": 1,
		"desc": "Levantar o escudo te teleporta 7 m para onde você olha. Escudo volta 0,3 s mais rápido.",
		"mods": [{"stat": "shield_teleport", "add": 1}, {"stat": "shield_cooldown", "add": -0.3}]},
	"chuva_de_bombas": {"name": "Chuva de Bombas", "cat": "Escudo", "rarity": "epico",
		"desc": "O escudo lança 5 bombas em arco à sua volta. Escudo +0,4 s de recarga.",
		"mods": [{"stat": "shield_bombs", "add": 5}, {"stat": "shield_cooldown", "add": 0.4}]},
	"eco": {"name": "Eco", "cat": "Escudo", "rarity": "lendario", "max": 1,
		"desc": "O escudo se levanta de novo sozinho 0,5 s depois. +20% de vida.",
		"mods": [{"stat": "shield_echo", "add": 1}, {"stat": "max_health", "mul": 1.2}]},
	"ultima_defesa": {"name": "Última Defesa", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Quando o pente esvazia, o escudo levanta sozinho (se estiver pronto).",
		"mods": [{"stat": "shield_on_empty", "add": 1}]},
	"pancada": {"name": "Pancada", "cat": "Escudo", "rarity": "raro",
		"desc": "Com o escudo de pé, quem estiver colado em você leva 25 de dano e é empurrado.",
		"mods": [{"stat": "shield_bash", "add": 25.0}]},
	"escudo_duplo": {"name": "Escudo Duplo", "cat": "Escudo", "rarity": "lendario", "max": 1,
		"desc": "Dá para levantar o escudo de novo meio segundo depois; aí ele recarrega 30% mais devagar.",
		"mods": [{"stat": "shield_charges", "add": 1}, {"stat": "shield_cooldown", "mul": 1.3}]},
	"couraca": {"name": "Couraça", "cat": "Escudo", "rarity": "raro",
		"desc": "Levantar o escudo dá 10 de colete (até 50), que absorve dano antes da vida.",
		"mods": [{"stat": "shield_armor", "add": 10.0}]},
	"fortaleza": {"name": "Fortaleza", "cat": "Escudo", "rarity": "comum",
		"desc": "+30 de vida e o escudo dura +0,1 s. 8% mais lento.",
		"mods": [{"stat": "max_health", "add": 30.0}, {"stat": "shield_duration", "add": 0.1},
			{"stat": "move_speed", "mul": 0.92}]},
	"espelho_gigante": {"name": "Espelho Gigante", "cat": "Escudo", "rarity": "raro",
		"desc": "O escudo pega balas 50% mais longe de você e dura +0,1 s.",
		"mods": [{"stat": "shield_size", "mul": 1.5}, {"stat": "shield_duration", "add": 0.1}]},

	# Corpo
	"vigor": {"name": "Vigor", "cat": "Corpo", "rarity": "comum",
		"desc": "+40 de vida máxima.",
		"mods": [{"stat": "max_health", "add": 40.0}]},
	"fragil": {"name": "Frágil", "cat": "Corpo", "rarity": "comum",
		"desc": "+50% de dano, -25% de vida.",
		"mods": [{"stat": "damage", "mul": 1.5}, {"stat": "max_health", "mul": 0.75}]},
	"tanque": {"name": "Tanque", "cat": "Corpo", "rarity": "comum",
		"desc": "+60% de vida, 12% mais lento.",
		"mods": [{"stat": "max_health", "mul": 1.6}, {"stat": "move_speed", "mul": 0.88}]},
	"sede_de_sangue": {"name": "Sede de Sangue", "cat": "Corpo", "rarity": "raro",
		"desc": "Causar dano te deixa 30% mais rápido por 3 s.",
		"mods": [{"stat": "bloodlust", "add": 0.3}]},
	"furia": {"name": "Fúria", "cat": "Corpo", "rarity": "raro",
		"desc": "+50% de dano enquanto estiver abaixo de 35% da vida.",
		"mods": [{"stat": "rage", "add": 0.5}]},
	"fenix": {"name": "Fênix", "cat": "Corpo", "rarity": "lendario", "max": 1,
		"desc": "Ao morrer, volta uma vez com metade da vida. -20% de vida.",
		"mods": [{"stat": "revives", "add": 1}, {"stat": "max_health", "mul": 0.8}]},
	"regeneracao": {"name": "Regeneração", "cat": "Corpo", "rarity": "raro",
		"desc": "Recupera 5 de vida por segundo depois de 3 s sem levar dano.",
		"mods": [{"stat": "regen", "add": 5.0}]},
	"radar": {"name": "Radar", "cat": "Corpo", "rarity": "epico", "max": 1,
		"desc": "Você vê a posição do inimigo através das paredes.",
		"mods": [{"stat": "radar", "add": 1}]},
	"nanico": {"name": "Nanico", "cat": "Corpo", "rarity": "raro",
		"desc": "Você fica 35% menor e mais difícil de acertar. -20% de vida.",
		"mods": [{"stat": "body_scale", "mul": 0.65}, {"stat": "max_health", "mul": 0.8}]},
	"gigantao": {"name": "Gigantão", "cat": "Corpo", "rarity": "epico",
		"desc": "Você fica 40% maior e ganha +80% de vida. 10% mais lento.",
		"mods": [{"stat": "body_scale", "mul": 1.4}, {"stat": "max_health", "mul": 1.8}, {"stat": "move_speed", "mul": 0.9}]},
	"camuflagem": {"name": "Camuflagem", "cat": "Corpo", "rarity": "epico", "max": 1,
		"desc": "Parado por 1 s, você fica invisível até se mexer ou atirar.",
		"mods": [{"stat": "camo", "add": 1}]},

	# Movimento
	"pulo_duplo": {"name": "Pulo Duplo", "cat": "Movimento", "rarity": "raro",
		"desc": "+1 pulo no ar.",
		"mods": [{"stat": "extra_jumps", "add": 1}]},
	"impulso": {"name": "Impulso", "cat": "Movimento", "rarity": "raro",
		"desc": "+1 dash no ar antes de tocar o chão.",
		"mods": [{"stat": "air_dashes", "add": 1}]},
	"escalador": {"name": "Escalador", "cat": "Movimento", "rarity": "comum",
		"desc": "+2 pulos na parede antes de tocar o chão (sem a carta são 2).",
		"mods": [{"stat": "wall_jumps", "add": 2}]},
	"deslize_turbo": {"name": "Deslize Turbo", "cat": "Movimento", "rarity": "comum",
		"desc": "O deslize (segurar Ctrl depois do dash) dá 70% mais impulso.",
		"mods": [{"stat": "slide_boost", "mul": 1.7}]},
	"pena": {"name": "Pena", "cat": "Movimento", "rarity": "comum",
		"desc": "Pula 15% mais alto e cai mais devagar.",
		"mods": [{"stat": "jump_velocity", "mul": 1.15}, {"stat": "gravity_mult", "mul": 0.8}]},
	"botas_leves": {"name": "Botas Leves", "cat": "Movimento", "rarity": "comum",
		"desc": "+15% de velocidade.",
		"mods": [{"stat": "move_speed", "mul": 1.15}]},
	"cacador": {"name": "Caçador", "cat": "Movimento", "rarity": "raro",
		"desc": "+40% de velocidade andando na direção do inimigo.",
		"mods": [{"stat": "chase", "add": 0.4}]},
	"pulo_foguete": {"name": "Pulo-Foguete", "cat": "Movimento", "rarity": "epico", "max": 1,
		"desc": "As balas explodem (raio de 2 m), e suas explosões te lançam longe sem te ferir.",
		"mods": [{"stat": "rocket_jump", "add": 1}, {"stat": "explosion", "add": 2.0}]},
	"meteoro": {"name": "Meteoro", "cat": "Movimento", "rarity": "epico",
		"desc": "No alto, olhe para baixo e aperte Ctrl para despencar: ao bater no chão, 25 de dano e empurrão a até 5 m.",
		"mods": [{"stat": "ground_slam", "add": 1}]},
	"folego": {"name": "Fôlego", "cat": "Movimento", "rarity": "comum",
		"desc": "O dash volta 40% mais rápido.",
		"mods": [{"stat": "dash_cooldown", "mul": 0.6}]},
	"dash_longo": {"name": "Dash Longo", "cat": "Movimento", "rarity": "comum",
		"desc": "O dash vai 40% mais longe.",
		"mods": [{"stat": "dash_power", "mul": 1.4}]},
	"esquiva": {"name": "Esquiva", "cat": "Movimento", "rarity": "lendario", "max": 1,
		"desc": "Durante o dash as balas te atravessam. O dash volta 0,3 s mais devagar.",
		"mods": [{"stat": "dash_dodge", "add": 1}, {"stat": "dash_cooldown", "add": 0.3}]},
	"atropelar": {"name": "Atropelar", "cat": "Movimento", "rarity": "raro",
		"desc": "Passar por um inimigo no dash causa 20 de dano e o empurra.",
		"mods": [{"stat": "dash_hit", "add": 20.0}]},
	"saque_rapido": {"name": "Saque Rápido", "cat": "Movimento", "rarity": "raro",
		"desc": "Cada dash põe 2 balas no pente.",
		"mods": [{"stat": "dash_ammo", "add": 2}]},
	"cacada": {"name": "Caçada", "cat": "Movimento", "rarity": "epico", "max": 1,
		"desc": "Acertar o inimigo recarrega o dash na hora e devolve um dash no ar.",
		"mods": [{"stat": "hit_dash", "add": 1}]},
	"planador": {"name": "Planador", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Segure Espaço caindo para planar devagar.",
		"mods": [{"stat": "glide", "add": 1}]},
	"embalo": {"name": "Embalo", "cat": "Movimento", "rarity": "comum",
		"desc": "Controle no ar 2x maior (curva sem perder velocidade) e +10% de velocidade.",
		"mods": [{"stat": "air_control", "mul": 2.0}, {"stat": "move_speed", "mul": 1.1}]},
	"molas": {"name": "Molas", "cat": "Movimento", "rarity": "comum",
		"desc": "Pula 20% mais alto. -10% de vida.",
		"mods": [{"stat": "jump_velocity", "mul": 1.2}, {"stat": "max_health", "mul": 0.9}]},
}


var _icons := {}


func _init() -> void:
	CARDS.merge(MASTERS)


## Cartas comuns (as que vão no baralho e aparecem na escolha de 1 de 3).
func all_ids() -> Array:
	return CARDS.keys().filter(func(id): return not is_master(id))


func master_ids() -> Array:
	return MASTERS.keys()


func is_master(id: String) -> bool:
	return MASTERS.has(id)


func card_name(id: String) -> String:
	return CARDS[id]["name"]


## Desenho da carta: assets/card_icons/<id>.svg (game-icons.net, CC BY 3.0, autores em
## LICENSE.txt na mesma pasta). Temporário, até ter arte própria.
func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://assets/card_icons/%s.svg" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


## Arquétipos da carta, na ordem de ARCHETYPES.
func archetypes_of(id: String) -> Array:
	return ARCHETYPES.keys().filter(func(a): return id in ARCHETYPES[a]["cards"])


func rarity_name(id: String) -> String:
	return RARITIES[CARDS[id]["rarity"]]["name"]


func rarity_color(id: String) -> Color:
	return RARITIES[CARDS[id]["rarity"]]["color"]


func is_valid_deck(deck: Array) -> bool:
	if deck.size() < DECK_MIN or deck.size() > DECK_MAX:
		return false
	for id in deck:
		if not CARDS.has(id) or is_master(id) or deck.count(id) > MAX_COPIES:
			return false
	return true


## Modelos para começar um baralho novo. "per_cat": as primeiras N cartas de cada
## categoria; "cats" x "copies": todas as cartas dessas categorias; "ids": cartas avulsas.
const TEMPLATES := [
	{"name": "Equilibrado", "desc": "um pouco de cada grupo", "per_cat": 10, "master": "corrente"},
	{"name": "Atirador", "desc": "arma e balas", "cats": ["Arma", "Balas"], "master": "bazuca"},
	{"name": "Muralha", "desc": "escudo de perto: defende, encosta e bate", "cats": ["Escudo"], "copies": 2,
		"master": "bastiao",
		"ids": ["investida", "vigor", "tanque", "sanguessuga"]},
	{"name": "Acrobata", "desc": "movimento e mobilidade", "cats": ["Movimento"], "copies": 2,
		"master": "corrente",
		"ids": ["investida", "teleporte", "sede_de_sangue", "nanico"]},
	{"name": "Caos", "desc": "só as cartas mais malucas", "master": "perfurante",
		"ids": ["bumerangue", "troca_troca", "bola_de_neve", "preguicosa", "fragmentacao", "tabelinha",
			"detonacao", "morteiro", "metralhadora", "escopeta", "bala_gigante", "teleguiada",
			"quique_certeiro", "espelho_duplo", "nova", "chuva_de_bombas", "teleporte", "nanico",
			"gigantao", "pulo_foguete", "meteoro", "camuflagem", "flash", "pena", "escalador",
			"sortudo", "ultima_bala", "canhao_de_vidro", "fenix", "explosiva", "propulsao", "eco",
			"atropelar", "planador"]},
	{"name": "Aleatório", "desc": "sorteado", "random": true},
	{"name": "Vazio", "desc": "você escolhe tudo"},
]


func template_deck(index: int) -> Array:
	var tpl: Dictionary = TEMPLATES[index]
	if tpl.get("random", false):
		return random_deck()
	var deck := []
	for cat in CATEGORY_COLORS:
		var in_cat := all_ids().filter(func(id): return CARDS[id]["cat"] == cat)
		if tpl.has("per_cat"):
			deck.append_array(in_cat.slice(0, tpl["per_cat"]))
		elif cat in tpl.get("cats", []):
			for k in tpl.get("copies", 1):
				deck.append_array(in_cat)
	for id in tpl.get("ids", []):
		if deck.count(id) < MAX_COPIES:
			deck.append(id)
	return deck.slice(0, DECK_MAX)


func template_master(index: int) -> String:
	var tpl: Dictionary = TEMPLATES[index]
	return master_ids().pick_random() if tpl.get("random", false) else tpl.get("master", MASTER_DEFAULT)


func random_deck() -> Array:
	var ids := all_ids()
	var size := randi_range(DECK_MIN, DECK_MAX)
	var deck := []
	while deck.size() < size:
		var id: String = ids.pick_random()
		if deck.count(id) < MAX_COPIES:
			deck.append(id)
	return deck


## Pode escolher de novo? Cartas com "max" param de aparecer quando o limite é atingido.
func can_take(id: String, owned: Array) -> bool:
	return not CARDS[id].has("max") or owned.count(id) < CARDS[id]["max"]


## Sorteia até n cartas diferentes do baralho. Cópias no baralho aumentam a chance.
## As cartas nunca saem do baralho: a mesma pode aparecer de novo nas próximas rodadas.
func offer(deck: Array, owned: Array, n: int) -> Array:
	var pool := deck.filter(func(id): return can_take(id, owned))
	var options := []
	while options.size() < n and not pool.is_empty():
		var id: String = pool.pick_random()
		options.append(id)
		pool = pool.filter(func(other): return other != id)
	return options


## Aplica as cartas sobre os atributos base: primeiro as somas, depois as porcentagens.
## Porcentagem que melhora o atributo SOMA com as outras do mesmo atributo (3x +35% de dano
## = +105%, não 2,46x); a que piora multiplica (o custo continua valendo inteiro). Assim o
## bônus cresce em linha reta com as cartas, e não exponencialmente: era isso que deixava a
## rodada 50 absurda. Atributos de "menos é melhor" (intervalo de tiro, recargas) somam em
## velocidade: 0,7x = +43% de cadência, e o valor final é base / (1 + soma).
## Ordem: pioras (somas e porcentagens), piso das pioras, melhorias que somam, porcentagens
## que melhoram. Assim 3x -55% de dano ficam em 0,35x (não 0,09x) e uma carta de +75% leva
## a 0,61x; pente 4 com -2, -2 e -2 fica em 1, e um +5 depois leva a 6.
func compute_stats(base: Dictionary, card_ids: Array) -> Dictionary:
	var stats := base.duplicate()
	var bonus := {}      # atributo -> soma das melhorias (+0,35 = +35%)
	var muls := {}       # atributo -> produto das pioras e dos neutros
	var good_add := {}   # atributo -> somas que melhoram, aplicadas depois do piso
	for id in card_ids:
		for mod in CARDS[id]["mods"]:
			var stat: String = mod["stat"]
			if mod.has("add"):
				var a: float = mod["add"]
				if (stat in HIGHER_BETTER and a > 0.0) or (stat in LOWER_BETTER and a < 0.0):
					good_add[stat] = good_add.get(stat, 0.0) + a
				else:
					stats[stat] += a
			if not mod.has("mul"):
				continue
			var m: float = mod["mul"]
			if stat in HIGHER_BETTER and m > 1.0:
				bonus[stat] = bonus.get(stat, 0.0) + (m - 1.0)
			elif stat in LOWER_BETTER and m > 0.0 and m < 1.0:
				bonus[stat] = bonus.get(stat, 0.0) + (1.0 / m - 1.0)
			else:
				muls[stat] = muls.get(stat, 1.0) * m
	for stat in muls:
		stats[stat] *= muls[stat]
	for stat in HIGHER_BETTER:
		stats[stat] = maxf(stats[stat], PENALTY_FLOOR_ABS.get(stat, base[stat] * PENALTY_FLOOR))
	for stat in LOWER_BETTER:
		stats[stat] = minf(stats[stat], base[stat] * PENALTY_CEIL)
	for stat in good_add:
		stats[stat] += good_add[stat]
	for stat in bonus:
		if stat in LOWER_BETTER:
			stats[stat] /= 1.0 + bonus[stat]
		else:
			stats[stat] *= 1.0 + bonus[stat]
	for stat in LIMITS:
		stats[stat] = clampf(stats[stat], LIMITS[stat][0], LIMITS[stat][1])
	var size: float = stats["body_scale"] * pow(stats["max_health"] / base["max_health"], HEALTH_SIZE_EXP)
	stats["body_scale"] = clampf(size, LIMITS["body_scale"][0], LIMITS["body_scale"][1])
	for stat in stats.keys():
		if base[stat] is int:
			stats[stat] = int(round(stats[stat]))
	return stats
