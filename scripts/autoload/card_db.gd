extends Node
## Catálogo de cartas. Para criar uma carta nova basta adicionar uma entrada em CARDS.
## Cada modificador mexe num atributo de Player.BASE_STATS:
##   "add": soma ao valor base
##   "mul": porcentagem, aplicada depois das somas; melhorias do mesmo atributo somam
##          entre si e pioras multiplicam (ver compute_stats)
## "max": quantas vezes a mesma carta pode ser escolhida na partida (sem "max", sem limite).
## Ideias tiradas de OVERKILL (Roblox) e ROUNDS (Landfall), os jogos que inspiraram o Furor.
## São 94 cartas comuns para um baralho de no máximo 50: é preciso deixar algumas de fora.
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
	"bullet_speed": [9.0, 400.0],
	# Tamanho vindo das cartas (2026-10-11): até 4x a base; o crescimento pelo dano (Bullet,
	# DAMAGE_SIZE_EXP) vem por cima, então a nuke de quique não muda.
	"bullet_radius": [0.03, 0.6],
	"shield_cooldown": [1.0, 20.0],
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
	"poison": [0.0, 2.0],   # 1,0 até 2026-10-14 (Veneno 35% -> 60%: o total do veneno passa o do fogo)
	"burn": [0.0, 1.5],
	"knockback": [0.0, 24.0],
	"execute": [0.0, 1.0],
	"last_shot": [0, 3],
	"split": [0, 8],
	"bounces": [0, 12],   # 6 até 2026-10-07; subiu com a vida a mais por quique (nuke)
	"bounce_damage": [0.0, 1.0],
	"grow": [0.0, 1.6],
	"blast_radius": [-1.0, 3.0],
	"blast_damage": [0.0, 1.0],   # era 1,5 até 2026-10-08: o centro passava de 1,5x o tiro
	"blast_resist": [0.0, 0.7],
	"tenacity": [0.0, 0.6],
	"heavy": [0.0, 0.6],
	"regen": [0.0, 12.0],
	"reflect_mult": [1.0, 2.5],
	"bullet_count": [1, 13],
}

## Atributos em que a porcentagem de melhoria soma em vez de multiplicar (ver compute_stats).
## Os que não estão aqui (gravidade da bala, tamanho do corpo) multiplicam sempre.
const HIGHER_BETTER := ["damage", "max_health", "bullet_speed", "bullet_radius", "move_speed",
	"jump_velocity", "dash_power", "air_control", "slide_boost", "shield_size", "mag_size",
	"bullet_range"]
const LOWER_BETTER := ["fire_interval", "reload_time", "shield_cooldown", "dash_cooldown"]

## Piso das pioras (2026-10-04, pedido do usuário: investir em perder algo não pode afundar o
## atributo para sempre). As pioras de um atributo param em PENALTY_FLOOR x a base (ou
## PENALTY_CEIL x, nos de "menos é melhor"), e as melhorias contam a partir dali.
const PENALTY_FLOOR := 0.35
const PENALTY_CEIL := 2.5
const PENALTY_FLOOR_ABS := {"mag_size": 1}   # pente: as perdas param em 1 bala
## Atributos com piso próprio (x a base). Velocidade da bala (2026-10-11, pedido do usuário:
## a bala "lenta" das cartas de tamanho quase não pesava, parava em 16,8 m/s): 9,6 m/s.
## Alcance (2026-10-15): as perdas param em 12 m (0,06 x Player.RANGE_FREE).
## Tamanho da bala (2026-10-17, pedido do usuário: a bala da sniper ficava tão pequena que
## parecia acertar e não acertava): as perdas param em 60% (0,09 m); o dano cresce por cima.
const PENALTY_FLOOR_BY := {"bullet_speed": 0.2, "bullet_range": 0.06, "bullet_radius": 0.6}
## Recarga do escudo (2026-10-07): os custos das cartas (+1 s, +0,5 s) somam até este teto,
## no lugar do PENALTY_CEIL (2,5x apagaria o custo da 3a carta em diante). As porcentagens
## que pioram (Escudo Duplo) entram depois das reduções, sobre o total; LIMITS dá 1 a 20 s.
const SHIELD_COST_MAX := 12.0

const MASTER_DEFAULT := "corrente"
const MASTERS := {
	"bazuca": {"name": "Bazuca", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: troca a arma por uma bazuca por 6 s. 3 foguetes retos, com o dobro do dano, que explodem (4 m). Recarga de 18 s.",
		"mods": [{"stat": "bazooka", "add": 1}]},
	# Espada (2026-10-06, desenho do usuário: combo de 3; números meus).
	"espada": {"name": "Espada", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 22.0,
		"desc": "Q: troca a arma por uma espada por 8 s. Clique ataca num combo de 3: corte para a direita, corte para a esquerda e uma estocada que te lança à frente. Alcance de 3,2 m; cortes com o dano da arma, estocada com 1,6x. Os golpes seguem a sua Cadência: se ela estiver mais lenta que a da arma base, os golpes ficam mais espaçados. Escudo levantado bloqueia. Com a espada na mão, você anda 20% mais devagar e não usa o escudo. Recarga de 22 s.",
		"mods": [{"stat": "sword", "add": 1}]},
	# Sniper (2026-10-06, desenho do usuário; números meus): como a Bazuca, troca de arma no Q.
	"sniper": {"name": "Sniper", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: troca a arma por uma sniper com UM tiro, por até 8 s. O tiro é um laser: reto, quase instantâneo, atravessa todas as paredes e causa 4x o dano (100 na base). Botão direito mira com zoom. Recarga de 18 s.",
		"mods": [{"stat": "sniper", "add": 1}]},
	# Canhão Arcano (2026-10-06, desenho do usuário, "tipo Kamehameha"; números meus,
	# aprovados; andar devagar na carga foi escolha dele).
	"canhao_arcano": {"name": "Canhão Arcano", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 24.0,
		"desc": "Q: carrega por 1 s (andando devagar) e solta um raio de 40 m por 2,5 s, que atravessa paredes. Parado, no chão ou flutuando no ar, você mira devagar. Cada toque causa 22 de dano e arremessa o alvo para fora do raio (o mesmo alvo a cada 0,6 s). Escudo levantado bloqueia o dano. Levar tapa, congelar ou morrer corta o raio. Recarga de 24 s.",
		"mods": [{"stat": "beam", "add": 1}]},
	# Chuva de Meteoros (2026-10-06, ideia do usuário; números meus, aprovados; ignorar
	# telhados foi escolha dele).
	"chuva_de_meteoros": {"name": "Chuva de Meteoros", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 16.0,
		"desc": "Q: os próximos 3 tiros (em até 8 s) marcam o chão onde batem. 1,5 s depois cai um meteoro em cada marca: 30 + metade do dano do tiro no centro (até 55), metade disso na borda de 4 m, e empurra. A marca aparece para todos. Recarga de 16 s.",
		"mods": [{"stat": "meteor", "add": 1}]},
	# Foguete (2026-10-06, desenho do usuário; números meus, aprovados; subir e descer,
	# explodir montado ao bater e o grupo Arma foram escolhas dele).
	"foguete": {"name": "Foguete", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: monta num foguete que voa sempre para a frente (10 m/s) e vira bem devagar, por até 5 s. Q de novo: você salta e o foguete segue reto, acelera muito e explode no primeiro contato. Montado, ele explode se bater numa parede, encostar num inimigo ou o tempo acabar (você é lançado para cima, sem dano). Explosão de 70 no centro, até 7 m. Recarga de 18 s.",
		"mods": [{"stat": "rocket_ride", "add": 1}]},
	"perfurante": {"name": "Perfurante", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 20.0,
		"desc": "Q: os próximos 3 tiros vão retos, sem queda, 3x mais rápidos, com +30% de dano e atravessando tudo: paredes, jogadores (cada um leva uma vez), o escudo e o Bastião, que não os devolvem. O dano ignora o colete e vai direto na vida. Recarga de 20 s.",
		"mods": [{"stat": "pierce", "add": 1}]},
	"bastiao": {"name": "Bastião", "cat": "Escudo", "rarity": "mitico", "master": true, "cooldown": 14.0,
		"desc": "Q: ergue à sua frente uma parede de energia por 4 s que devolve as balas inimigas. As suas passam. Recarga de 14 s.",
		"mods": [{"stat": "barrier", "add": 1}]},
	# Prisão de Gelo (2026-10-06, desenho do usuário; números meus, ele pediu 3 s; o bloco
	# quica no vazio e o dano do vazio vem quando o gelo derrete).
	# Reforço de 2026-10-15 (pedido do usuário: difícil de acertar e retorno baixo): caco
	# mais grosso que estilhaça no cenário, bloco que guarda dano, 1 camada por acerto, 12 s.
	"prisao_gelo": {"name": "Prisão de Gelo", "cat": "Escudo", "rarity": "mitico", "master": true, "cooldown": 12.0,
		"desc": "Seus acertos põem 1 camada de Congelamento. Q: dispara um caco de gelo (reto, até 40 m). Quem for atingido fica preso num bloco de gelo por 3 s: não age e não perde vida, mas o bloco guarda metade do dano que leva (até 50) e solta tudo no degelo, com a quebra do gelo (+20). O bloco desliza: tiros, explosões e encontrões o empurram. No vazio ele quica, e o dano vem quando o gelo derrete. Se o caco bater no cenário, estilhaça: 2 camadas em quem estiver a até 3 m. O escudo devolve o caco. Recarga de 12 s.",
		"mods": [{"stat": "ice", "add": 1}, {"stat": "frost", "add": 1}]},
	# Mega Tapa (2026-10-06, ideia do usuário: tirar quem joga de perto; números meus e o
	# impacto na parede, escolhido por ele entre 3 extras).
	"mega_tapa": {"name": "Mega Tapa", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 8.0,
		"desc": "Q: ergue a mão e, 0,6 s depois, dá um tapa à frente (4,5 m) que causa 10 de dano e arremessa longe e para cima, sem controle no ar até cair. Se o arremessado bater numa parede no voo, leva mais 20 e fica tonto por 0,6 s (lento e sem atirar). Escudo levantado bloqueia. Recarga de 8 s.",
		"mods": [{"stat": "slap", "add": 1}]},
	# Gancho (2026-10-06, ideia do usuário: fundiu as minhas propostas de gancho e de
	# agarrar e arremessar; números meus, aprovados).
	"gancho": {"name": "Gancho", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 16.0,
		"desc": "Q: lança um gancho (até 20 m) que puxa o inimigo até a sua frente e o segura por até 3 s: você anda a 70% e não atira; ele não age. Ele serve de escudo humano (nos Times, o time dele também o acerta). Clique ou Q arremessa na mira: bater numa parede dá 22; bater em outro inimigo dá 22 nos dois e deixa os dois tontos. Levar 30 de dano segurando solta. Escudo levantado bloqueia o gancho. Recarga de 16 s (6 s se errar).",
		"mods": [{"stat": "hook", "add": 1}]},
	# Domínio do Rei (2026-10-11, ideia e nome do usuário, inspirada na ultimate do
	# Mordekaiser; números meus, aprovados; começar só com o bônus e voltar para onde saíram
	# foram escolhas dele). Lógica em Player._realm_*, sala em KingRealm.
	"dominio_do_rei": {"name": "Domínio do Rei", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 35.0,
		"desc": "Inimigos ao alcance (até 30 m, à vista) ganham uma coroa com \"Q\" na sua tela; a do que está na sua mira fica acesa. Q nele: lança uma corrente sombria que o persegue (24 m/s). Ele só escapa levantando o escudo quando ela chega ou se escondendo atrás de uma parede: aí a recarga é de 12 s. Sem ninguém na mira, o Q não gasta. Pegou: vocês dois são puxados por 0,8 s e levados para uma sala fechada por 10 s, onde ninguém mais entra. Lá dentro, a cada segundo você ganha +4% de dano e ele perde 4%, até +30% e -30%. Quem vencer volta na hora; se você vencer, fica com o bônus por mais 6 s. No fim do tempo, os dois voltam para onde estavam, e quem ficou no mapa vê onde e quando vocês reaparecem. Recarga de 35 s.",
		"mods": [{"stat": "realm", "add": 1}]},
	# Mecha (2026-10-12, ideia do usuário: construir e entrar, seguir atirando com defesa;
	# construção peça por peça, míssil no E, explosão na saída que cresce com a blindagem
	# perdida e a Perfurante ignorando a blindagem foram dele; números meus, aprovados).
	# Lógica em Player._mech_*.
	"mecha": {"name": "Mecha", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 24.0,
		"desc": "Q: monta um mecha em volta de você, peça por peça, em 1,2 s (nesse tempo você anda devagar e não atira). Dentro, por 8 s: blindagem de 60 + 60% da vida máxima que leva o dano antes de tudo, imune a empurrões e puxões, segue atirando com a sua arma, e E lança um míssil (1 a cada 2,5 s; 20 + 40% do dano da bala, até 45, em 3,5 m) no lugar do escudo. Maior, 25% mais lento, sem dash nem pulos extras. Q de novo sai antes. Ao sair, ele explode (5 m): 20 de dano com a blindagem cheia, até 50 com ela zerada. A Perfurante ignora a blindagem. Recarga de 24 s, contada depois de sair.",
		"mods": [{"stat": "mech", "add": 1}]},
	"ultimo_suspiro": {"name": "Último Suspiro", "cat": "Corpo", "rarity": "mitico", "master": true,
		"desc": "Uma vez por rodada, o golpe fatal te deixa com 1 de vida e sem morrer por 3 s. Abata alguém nesse tempo e volte com metade da vida.",
		"mods": [{"stat": "last_stand", "add": 1}]},
	# Camuflagem virou mestra em 2026-10-06 (pedido do usuário; números meus, aprovados):
	# some mais rápido, anda agachada sem aparecer e, ao aparecer, ganha a Emboscada.
	"camuflagem": {"name": "Camuflagem", "cat": "Corpo", "rarity": "mitico", "master": true,
		"desc": "Parado por 0,6 s, você some. Invisível, dá para andar agachado sem aparecer; atirar, correr, pular, dash, escudo ou levar dano te revelam. Depois de 1 s invisível, aparecer dá Emboscada: 3 s com +40% de dano nos tiros e +20% de velocidade (no máximo a cada 6 s), e o primeiro tiro atravessa paredes. O tiro que te revela já conta. Depois de 8 s seguidos invisível, a camuflagem falha: você pisca visível por 0,4 s a cada 2 s até aparecer.",
		"mods": [{"stat": "camo", "add": 1}]},
	# Bota Foguete (2026-10-06, desenho do usuário a partir da minha proposta; números meus):
	# passiva. Bônus por estar no ar e um jato curto como a bota foguete do Terraria.
	"bota_foguete": {"name": "Bota Foguete", "cat": "Movimento", "rarity": "mitico", "master": true,
		"desc": "Cada segundo no ar dá +10% de dano nos tiros, até +40%; tocar o chão zera. Sem pulos no ar sobrando, aperte e segure pular para um jato curto (0,7 s) que freia a queda e te empurra para cima. O jato volta ao tocar o chão.",
		"mods": [{"stat": "rocket_boots", "add": 1}]},
	# Formiga (2026-10-06, ideia do usuário; números meus, aprovados; cancelar no Q e o
	# impacto ao crescer foram sugestões minhas aceitas).
	# Plataformas Suspensas (2026-10-06, ideia e nome do usuário; números meus, aprovados;
	# todos pisam, escolha dele). Passiva com propulsor desde 2026-10-07 (pedido dele; 3
	# plataformas e 14 m/s meus, aprovados; a cor por jogador foi ideia dele; recarga de 6 s
	# dele e prazo de 2 s meu).
	"plataformas_suspensas": {"name": "Plataformas Suspensas", "cat": "Movimento", "rarity": "mitico", "master": true,
		"desc": "Sem pulos no ar sobrando, pular cria uma plataforma sob os seus pés. Dá para fazer até 3 seguidas, com 2 s para usar cada próxima; ao usar a 3ª, passar o prazo ou tocar o chão, recarga de 8 s. A plataforma é um propulsor: lança para cima quem pisa nela, uma vez por jogador (verde: ainda te lança; roxa: já te lançou). Dura 5 s; qualquer jogador pode pisar, e as balas atravessam.",
		"mods": [{"stat": "platforms", "add": 1}]},
	"formiga": {"name": "Formiga", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 16.0,
		"desc": "Q: por 6 s você fica com 40% do tamanho (mais difícil de acertar) e 60% mais rápido. Q de novo volta antes. Ao voltar ao tamanho, um impacto empurra quem estiver a até 4 m e causa 15 de dano. Recarga de 16 s.",
		"mods": [{"stat": "shrink", "add": 1}]},
	# Caos (2026-10-06, ideia do usuário; ritmo meu, aprovado; grupo Balas, escolha minha
	# com o voto dele de manter os 5 grupos): sorteia outra mestra. Entram todas as de
	# MASTERS, inclusive as futuras, menos ela mesma. Lógica em Player._chaos_*.
	"caos": {"name": "Caos", "cat": "Balas", "rarity": "mitico", "master": true,
		"desc": "Você recebe uma mestra sorteada. Ativa: use uma vez; 8 s depois do efeito acabar, vem outra. Passiva: dura 15 s e troca. Nunca repete a anterior; cada rodada começa com um sorteio novo.",
		"mods": [{"stat": "chaos", "add": 1}]},
	# Cartas Instáveis (2026-10-11, ideia e nome do usuário; números meus, aprovados para
	# começar fracos; cartas do baralho e grupo Balas, junto do Caos, escolhas dele).
	# Lógica em Player._unstable_*.
	# Clone (2026-10-12, a 2a das prometidas nas notas da v0.8.0; caminho "Clone Sombra" entre
	# 3 propostas minhas, com 8 s e o clone andando devagar, pedidos do usuário; grupo Balas,
	# escolha minha: o efeito é o tiro em dobro). Lógica em ShadowClone e Player._clone_*.
	"clone": {"name": "Clone", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: deixa um clone seu que anda devagar para onde você olhava, por 8 s. Para os outros ele é igual a você (nome e vida). Cada tiro seu também sai dele, na direção da sua mira, com metade do dano: fogo cruzado. Q de novo: você troca de lugar com ele, e ele some. Balas inimigas o destroem com 40 de dano. Recarga de 18 s.",
		"mods": [{"stat": "clone", "add": 1}]},
	"cartas_instaveis": {"name": "Cartas Instáveis", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 22.0,
		"desc": "Q: ganha 3 cartas comuns sorteadas do seu baralho por 8 s (respeitando o limite por partida; a Fênix não sai). A vida acompanha a vida máxima em porcentagem. As cartas aparecem em cima do seu nome para os outros. Recarga de 22 s.",
		"mods": [{"stat": "unstable", "add": 1}]},
	# Arpéu Ventoso (2026-10-12, ideia do usuário: os ganchos de Shingeki no Kyojin com cara
	# de desentupidor; nome dele; números meus, aprovados: 22 m/s, 8 s por carga, atirar a
	# qualquer momento). Lógica em Player._grapple_*.
	"arpeu_ventoso": {"name": "Arpéu Ventoso", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 6.0,
		"charges": 3,
		"desc": "Segure Q: lança uma ventosa (até 35 m). Grudou no cenário: você balança preso a ela, com a gravidade pela metade, sem perder o embalo, e as teclas guiam o balanço; a corda vai encurtando. Solte Q para sair voando com o embalo (+15% e um pulo no ar); Espaço também solta, com um impulso para cima. Chegando à parede ainda segurando, fica pendurado até 2 s (pular salta dela). Grudou num inimigo: você é puxado até ele e dá um chute de 20 de dano que o empurra (escudo levantado bloqueia). Dash corta. Errou, a carga volta em 1 s. Guarda 3 usos: cada um volta em 6 s, um de cada vez.",
		"mods": [{"stat": "grapple", "add": 1}]},
	"corrente": {"name": "Corrente", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 9.0,
		"charges": 2,
		"desc": "Q: impulso reto para cima, de uns 8 m. Funciona também no ar. Guarda 2 usos: cada um volta em 9 s, um de cada vez.",
		"mods": [{"stat": "updraft", "add": 1}]},
}

## Glossário (2026-10-12, pedido do usuário: "bala mais rápida", "atira mais rápido" e
## "recarga" confundiam). As descrições das cartas usam só estes termos; o editor mostra a
## lista no botão "?".
const GLOSSARY := [
	["Dano", "Quanto cada bala tira de vida (25 na arma base). Todo bônus de Dano soma num só, inclusive os de momento (Fúria, Executor, Sangue Frio...): +45% e +30% = +75%. Carta que multiplica o dano diz isso nela, como o crítico do Sortudo e a Última Bala."],
	["Cadência", "Quantos tiros por segundo. Cadência +40% = 40% mais tiros no mesmo tempo; Cadência x3 = o triplo."],
	["Velocidade da bala", "Quão rápido a bala voa até o alvo. Mais veloz chega antes e é mais fácil de acertar de longe."],
	["Queda da bala", "Quanto a bala cai durante o voo. -50% cai metade; x2 cai o dobro."],
	["Alcance", "Até onde a bala vai: ela some ao ficar mais longe que isso, em linha reta, de onde o tiro saiu (quiques valem enquanto estiverem dentro; a bala do Bumerangue vira 3 m antes do fim e volta). Sem perda de Alcance nas cartas não há limite. As perdas multiplicam e param em 12 m; os ganhos valem sobre o que sobrou."],
	["Tamanho da bala", "O tamanho da bala: maior é mais fácil de acertar. Ela também cresce um pouco com o dano. As perdas param em 60% do normal."],
	["Pente", "Quantos tiros você dá antes de precisar recarregar."],
	["Recarregar", "O tempo para encher o pente de novo (tecla de recarregar ou pente vazio)."],
	["Recarga", "A espera para usar de novo o escudo, o dash ou a carta mestra."],
	["Velocidade de movimento", "Quão rápido você anda e corre."],
	["Vida", "A vida máxima. O corpo cresce um pouco com ela."],
	["Aflição", "Efeito que fica no inimigo por um tempo: Veneno, Queimadura, Congelamento, Lentidão, Cegueira, Tontura e Escudo bloqueado. A Tenacidade encurta todas; o Blindado não reduz nenhuma."],
	["Veneno", "Dano lento e longo: 5 s. Empilha: cada acerto soma um veneno novo. Da parte do dano da bala acima de 40, rende só 2/3."],
	["Queimadura", "Dano rápido e curto: muito por segundo, por pouco tempo. Não empilha: um acerto novo renova o tempo e vale a mais forte. Da parte do dano da bala acima de 40, rende só 70%."],
	["Congelamento", "Camadas de gelo, até 5: cada uma deixa a cadência e o recarregar do alvo 6% mais lentos. Na 5ª ele congela por 0,5 s (não age, mas leva dano) e as camadas zeram; depois fica 3 s sem congelar de novo. 2 s sem camada nova, perde uma por segundo."],
	["Quebrar o gelo", "O primeiro golpe em quem está congelado causa +20 e acaba com o gelo. Veneno e queimadura não quebram."],
	["Efeito fixo por acerto", "Camada de gelo, aquecimento da Brasa e Pressão valem no máximo uma vez a cada 0,25 s de cada atirador em cada alvo: várias balas do mesmo tiro (escopeta) contam uma vez."],
	["Lentidão", "O alvo anda mais devagar. Não empilha: vale a mais forte."],
	["Como as cartas somam", "Melhorias do mesmo atributo somam (+20% e +20% = +40%). Pioras multiplicam e têm limite: em geral, nenhum atributo cai abaixo de 35% do normal."],
]

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
		"cards": ["ricochete", "bola_borracha", "quique_certeiro", "tabelinha", "fragmentacao", "bumerangue"]},
	"Explosão": {"desc": "Dano em área.",
		"cards": ["explosiva", "morteiro", "detonacao", "fragmentacao", "pulo_foguete", "chuva_de_bombas", "meteoro",
			"mina", "buraco_negro", "dinamite", "carga_concentrada"]},
	"Nuke": {"desc": "Poucas balas enormes, cada uma com muito dano.",
		"cards": ["calibre_pesado", "combinar", "bala_gigante", "bala_de_canhao", "canhao_de_vidro", "fragil",
			"ultima_bala", "sortudo", "nucleo_de_aco", "bola_de_neve", "tabelinha", "preguicosa", "executor", "furia", "vinganca"]},
	"Chuva de balas": {"desc": "Muitas balas, pente grande, cadência alta e recarregar rápido.",
		"cards": ["gatilho_leve", "pente_estendido", "maos_rapidas", "cano_duplo", "escopeta", "rajada",
			"transbordar", "imprudente", "metralhadora", "saque_rapido", "recarga_tatica", "recarga_perfeita",
			"reciclagem", "cinto_municao", "cartucheira"]},
	"Atirador": {"desc": "Acertar de longe e por trás das paredes.",
		"cards": ["polvora_extra", "olho_de_aguia", "fantasma", "teleguiada", "sortudo", "preguicosa", "radar",
			"sangue_frio", "nucleo_de_aco"]},
	"Controle": {"desc": "Atrapalhar o inimigo: lento, cego, envenenado, empurrado.",
		"cards": ["veneno", "congelante", "bala_de_gelo", "flash", "atordoante", "propulsao", "troca_troca", "onda_de_choque",
			"geada", "nuvem_toxica", "buraco_negro", "chamas"]},
	# Aflições (2026-10-14, pedido do usuário: sub-builds separadas desde já). Veneno e
	# Queimadura: cartas que aplicam ou melhoram só aquele efeito. Aflição: cartas que valem
	# para todas (efeitos que ficam no inimigo por um tempo; ver GLOSSARY).
	"Veneno": {"desc": "Aplicar e espalhar Veneno, que empilha a cada acerto.",
		"cards": ["veneno", "nuvem_toxica", "contagio"]},
	"Queimadura": {"desc": "Aplicar Queimadura, que tira muito por segundo e não empilha.",
		"cards": ["chamas", "incendiaria", "brasa", "combustivel", "combustao_lenta", "choque_termico"]},
	# Congelamento (2026-10-15, ideia do usuário): camadas que congelam e o gelo que quebra.
	"Congelamento": {"desc": "Pôr camadas de gelo até congelar e quebrar o gelo.",
		"cards": ["bala_de_gelo", "hipotermia", "estilhaco", "choque_termico", "congelante", "geada"]},
	"Aflição": {"desc": "Melhorar todo efeito que fica no inimigo: durar mais, marcar, estourar, impedir a cura.",
		"cards": ["marca", "persistencia", "acido", "corrosao", "estouro", "reacao_em_cadeia", "dose_extra", "raspao"]},
	"Espelho": {"desc": "Refletir as balas do inimigo com o escudo.",
		"cards": ["escudo_firme", "reflexos", "espelho_cortante", "adrenalina", "espelho_duplo",
			"espelho_perseguidor", "espelho_gigante", "escudo_duplo", "eco", "escudo_de_papel"]},
	"Escudo de ataque": {"desc": "O escudo como arma, de perto.",
		"cards": ["pancada", "onda_de_choque", "investida", "nova", "chuva_de_bombas", "teleporte",
			"couraca", "fortaleza", "restauracao", "recarga_tatica", "ultima_defesa",
			"serra", "chamas", "geada", "mina", "passo_ligeiro", "escudo_de_papel"]},
	"Corpo a corpo": {"desc": "Encostar no inimigo e bater.",
		"cards": ["escopeta", "atropelar", "cacador", "sede_de_sangue", "meteoro", "troca_troca",
			"pancada", "investida", "cacada", "serra", "pisao", "bote", "cano_serrado", "arrancada",
			"pressao", "bumerangue", "choke", "silenciador"]},
	"Tanque": {"desc": "Vida, cura e colete.",
		"cards": ["vigor", "tanque", "defensor", "sanguessuga", "regeneracao", "fenix", "gigantao",
			"fortaleza", "couraca", "restauracao", "eco", "blindado", "peso_pesado", "segunda_pele", "casca_dura",
			"couro_grosso", "banquete", "tenacidade", "metabolismo"]},
	"Aéreo": {"desc": "Ficar no alto: pulos, parede, planar.",
		"cards": ["pulo_duplo", "impulso", "escalador", "pena", "molas", "planador", "embalo", "meteoro", "pulo_foguete",
			"pisao", "parkour", "velocidade_letal", "vulto", "recarga_embalo", "leveza"]},
	"Dash": {"desc": "Dash mais vezes, mais longe e com efeito.",
		"cards": ["impulso", "folego", "dash_longo", "deslize_turbo", "esquiva", "atropelar", "saque_rapido",
			"cacada", "botas_leves", "pisao", "dash_duplo", "parkour", "velocidade_letal", "vulto", "bote"]},
	"Tudo ou nada": {"desc": "Troca vida por poder.",
		"cards": ["fragil", "canhao_de_vidro", "imprudente", "nanico", "furia", "fenix", "molas",
			"escudo_de_papel", "instinto", "leveza"]},
}

## O corpo cresce com a vida máxima, de leve (como no Furor): 1,8x de vida = 19% maior,
## metade da vida = 19% menor. Soma-se ao tamanho das cartas (Nanico, Gigantão).
const HEALTH_SIZE_EXP := 0.3

## Todas as cartas: as comuns abaixo e as mestras (MASTERS, juntadas em _init).
var CARDS := {
	# Arma
	"calibre_pesado": {"name": "Calibre Pesado", "cat": "Arma", "rarity": "comum",
		"desc": "Dano +20%. Cadência -10%. Recarregar +0,2 s.",
		"mods": [{"stat": "damage", "mul": 1.2}, {"stat": "fire_interval", "mul": 1.0 / 0.9}, {"stat": "reload_time", "add": 0.2}]},
	"gatilho_leve": {"name": "Gatilho Leve", "cat": "Arma", "rarity": "comum",
		"desc": "Cadência +40%. Dano -5%.",
		"mods": [{"stat": "fire_interval", "mul": 1.0 / 1.4}, {"stat": "damage", "mul": 0.95}]},
	"pente_estendido": {"name": "Pente Estendido", "cat": "Arma", "rarity": "comum",
		"desc": "Pente +4. Tempo para recarregar +15%.",
		"mods": [{"stat": "mag_size", "add": 4}, {"stat": "reload_time", "mul": 1.15}]},
	"maos_rapidas": {"name": "Mãos Rápidas", "cat": "Arma", "rarity": "comum", "max": 3,
		"desc": "Recarregar -0,25 s.",
		"mods": [{"stat": "reload_time", "add": -0.25}]},
	"polvora_extra": {"name": "Pólvora Extra", "cat": "Arma", "rarity": "comum",
		"desc": "Velocidade da bala +30%. Tamanho da bala -10%. Cada tiro te empurra um pouco para trás; mais cópias empurram cada vez mais.",
		"mods": [{"stat": "bullet_speed", "mul": 1.3}, {"stat": "bullet_radius", "mul": 0.9}, {"stat": "recoil", "add": 1}]},
	"cano_duplo": {"name": "Cano Duplo", "cat": "Arma", "rarity": "raro",
		"desc": "+1 bala por tiro. Pente +1. Dano -30%.",
		"mods": [{"stat": "bullet_count", "add": 1}, {"stat": "mag_size", "add": 1}, {"stat": "damage", "mul": 0.7}]},
	# Escopeta refeita em 2026-10-13 (pedido do usuário, para a build de spam: cada bala do leque
	# gasta pente, como a Rajada; 4 balas, pente +4, dano -40%; leque de 5 graus, porque com 4
	# balas não há bala no meio e a 7 graus as duas do centro passavam dos lados a mais de 8 m).
	# Cano Serrado (2026-10-15, build de escopeta pedida pelo usuário; números meus aprovados).
	# Bullet.CLOSE_*: a distância vai de onde o tiro saiu até onde acertou.
	"cano_serrado": {"name": "Cano Serrado", "cat": "Arma", "rarity": "epico", "max": 1,
		"desc": "Suas balas causam +50% de dano a até 5 m; o bônus cai até zero aos 12 m, e a partir de 15 m o dano é -30%. Leque 50% mais aberto. Alcance -70%.",
		"mods": [{"stat": "close_range", "add": 1}, {"stat": "spread", "mul": 1.5}, {"stat": "bullet_range", "mul": 0.3}]},
	"escopeta": {"name": "Escopeta", "cat": "Arma", "rarity": "raro", "max": 1,
		"desc": "+3 balas por tiro (4 no total), em leque, e cada bala gasta 1 do pente (com o pente quase vazio, saem só as que houver). Pente +4. Dano -30%.",
		"mods": [{"stat": "bullet_count", "add": 3}, {"stat": "shot_ammo", "add": 3}, {"stat": "spread", "add": 1.0},
			{"stat": "mag_size", "add": 4}, {"stat": "damage", "mul": 0.7}]},
	"rajada": {"name": "Rajada", "cat": "Arma", "rarity": "raro", "max": 1,
		"desc": "Cada clique dispara uma rajada de 3 tiros seguidos, cada um gastando 1 bala do pente. Dano -10%.",
		"mods": [{"stat": "burst", "add": 2}, {"stat": "damage", "mul": 0.9}]},
	"combinar": {"name": "Combinar", "cat": "Arma", "rarity": "raro",
		"desc": "Dano +45%. Pente -2.",
		"mods": [{"stat": "damage", "mul": 1.45}, {"stat": "mag_size", "add": -2}]},
	"transbordar": {"name": "Transbordar", "cat": "Arma", "rarity": "raro",
		"desc": "Pente +9. Dano -30%. Recarregar +0,8 s.",
		"mods": [{"stat": "mag_size", "add": 9}, {"stat": "damage", "mul": 0.7}, {"stat": "reload_time", "add": 0.8}]},
	"bala_gigante": {"name": "Bala Gigante", "cat": "Arma", "rarity": "raro",
		"desc": "Tamanho da bala x2. Dano +10%. Alcance -30% e queda da bala +30%.",
		"mods": [{"stat": "bullet_radius", "mul": 2.0}, {"stat": "damage", "mul": 1.1}, {"stat": "bullet_range", "mul": 0.7},
			{"stat": "bullet_gravity", "mul": 1.3}]},
	"bala_de_canhao": {"name": "Bala de Canhão", "cat": "Arma", "rarity": "raro",
		"desc": "Dano +35%. Tamanho da bala x2. Alcance -40%. Cadência -20%. Recarregar +0,3 s.",
		"mods": [{"stat": "damage", "mul": 1.35}, {"stat": "bullet_radius", "mul": 2.0}, {"stat": "bullet_range", "mul": 0.6},
			{"stat": "fire_interval", "mul": 1.0 / 0.8}, {"stat": "reload_time", "add": 0.3}]},
	"imprudente": {"name": "Imprudente", "cat": "Arma", "rarity": "epico",
		"desc": "Cadência x2. Tempo para recarregar +50%. Vida -15%.",
		"mods": [{"stat": "fire_interval", "mul": 0.5}, {"stat": "reload_time", "mul": 1.5}, {"stat": "max_health", "mul": 0.85}]},

	"metralhadora": {"name": "Metralhadora", "cat": "Arma", "rarity": "epico",
		"desc": "Automática: segure para atirar. Cadência x3. Pente +10. Dano -50%. Recarregar +0,25 s.",
		"mods": [{"stat": "auto_fire", "add": 1}, {"stat": "fire_interval", "mul": 0.33}, {"stat": "mag_size", "add": 10},
			{"stat": "damage", "mul": 0.5}, {"stat": "reload_time", "add": 0.25}]},
	"canhao_de_vidro": {"name": "Canhão de Vidro", "cat": "Arma", "rarity": "epico",
		"desc": "Dano +75%. Vida -50%.",
		"mods": [{"stat": "damage", "mul": 1.75}, {"stat": "max_health", "mul": 0.5}]},
	"olho_de_aguia": {"name": "Olho de Águia", "cat": "Arma", "rarity": "epico",
		"desc": "Velocidade da bala x2 e queda da bala -50%. Dano +30%. Tamanho da bala -10%. Cadência -40%. Recarregar +0,3 s.",
		"mods": [{"stat": "bullet_speed", "mul": 2.0}, {"stat": "bullet_gravity", "mul": 0.5},
			{"stat": "damage", "mul": 1.3}, {"stat": "fire_interval", "mul": 1.0 / 0.6},
			{"stat": "reload_time", "add": 0.3}, {"stat": "bullet_radius", "mul": 0.9}]},
	"morteiro": {"name": "Morteiro", "cat": "Arma", "rarity": "epico",
		"desc": "Balas em arco alto (queda da bala x3,5) que explodem (raio de 4 m). Dano +30%. Velocidade da bala -40%.",
		"mods": [{"stat": "bullet_gravity", "mul": 3.5}, {"stat": "bullet_speed", "mul": 0.6},
			{"stat": "explosion", "add": 4.0}, {"stat": "damage", "mul": 1.3}]},
	# Recarga Perfeita (2026-10-07, proposta minha aprovada; como a recarga ativa do Gears of War).
	"recarga_perfeita": {"name": "Recarga Perfeita", "cat": "Arma", "rarity": "epico", "max": 1,
		"desc": "Enquanto você recarrega, aparece uma faixa dourada no anel da mira: aperte recarregar de novo nela para terminar na hora, e o pente seguinte causa +15% de dano. Fora da faixa, recarregar atrasa 0,4 s. Uma tentativa por vez.",
		"mods": [{"stat": "perfect_reload", "add": 1}]},
	# Última Bala e Sortudo multiplicam (2026-10-17, pedido do usuário para a sniper; ver
	# Player.LAST_SHOT_MULT e CRIT_MULT). Antes somavam +150% (soma única, 2026-10-14).
	"ultima_bala": {"name": "Última Bala", "cat": "Arma", "rarity": "raro",
		"desc": "A última bala do pente causa dano x2 (multiplica). Mais cópias: x2,5 e x3.",
		"mods": [{"stat": "last_shot", "add": 1}]},
	"sortudo": {"name": "Sortudo", "cat": "Arma", "rarity": "epico",
		"desc": "Cada bala tem 20% de chance de ser crítica: dano x2 (multiplica).",
		"mods": [{"stat": "crit_chance", "add": 0.2}]},
	# Munição (2026-10-11, pedido do usuário depois da Rajada gastar pente; números meus,
	# aprovados). Reciclagem: Player.bullet_refund (a bala leva o número do clique).
	"reciclagem": {"name": "Reciclagem", "cat": "Arma", "rarity": "raro", "max": 3,
		"desc": "Cada bala que acerta um inimigo devolve 1 bala ao pente por cópia: 1, 2 ou 3.",
		"mods": [{"stat": "recycle", "add": 1}]},
	"cinto_municao": {"name": "Cinto de Munição", "cat": "Arma", "rarity": "comum",
		"desc": "Pente +50%. Recarregar +0,4 s.",
		"mods": [{"stat": "mag_size", "mul": 1.5}, {"stat": "reload_time", "add": 0.4}]},
	# Cartucheira (2026-10-13, ideia do usuário para a build de spam: chance de a bala não sair
	# do pente; custo só na velocidade da bala, para pesar no sniper e quase nada de perto;
	# 10% por cópia até 3, escolhas dele; Player._shoot sorteia por bala do pente). Desde
	# 2026-10-15 o custo é Alcance -15% (era velocidade -10%), que faz isso melhor.
	"cartucheira": {"name": "Cartucheira", "cat": "Arma", "rarity": "comum", "max": 3,
		"desc": "Cada bala tem 10% de chance de não sair do pente. Alcance -10%.",
		"mods": [{"stat": "free_ammo", "add": 0.1}, {"stat": "bullet_range", "mul": 0.9}]},
	# Alcance (2026-10-15, pedido do usuário para a build de escopeta: a bala de perto saía
	# lenta e caindo). As cartas de bala pesada cortam o Alcance no lugar da velocidade; quem
	# não tem perda de Alcance não tem limite nenhum. Choke e Silenciador devolvem parte, sobre
	# o que sobrou (números meus, para ele conferir); sem perda de Alcance, o ganho não muda nada.
	"choke": {"name": "Choke", "cat": "Arma", "rarity": "comum", "max": 3,
		"desc": "Alcance +25%. Leque 20% mais fechado.",
		"mods": [{"stat": "bullet_range", "mul": 1.25}, {"stat": "spread", "mul": 0.8}]},
	"silenciador": {"name": "Silenciador", "cat": "Arma", "rarity": "raro", "max": 1,
		"desc": "Alcance +60%. Velocidade da bala +20%. Tamanho da bala -15%.",
		"mods": [{"stat": "bullet_range", "mul": 1.6}, {"stat": "bullet_speed", "mul": 1.2},
			{"stat": "bullet_radius", "mul": 0.85}]},
	# Núcleo de Aço (2026-10-17, ideia do usuário para a sniper recuperar tamanho sem perder
	# Alcance; números meus). Fura só o colete: furar o escudo do E fica para a Perfurante.
	"nucleo_de_aco": {"name": "Núcleo de Aço", "cat": "Arma", "rarity": "raro", "max": 3,
		"desc": "20% do dano dos seus acertos que iria para o colete do inimigo vai direto na vida (40% e 60% com 2 e 3 cópias). Tamanho da bala +25%. Dano +10%. Recarregar +0,3 s.",
		"mods": [{"stat": "armor_pierce", "add": 0.2}, {"stat": "bullet_radius", "mul": 1.25},
			{"stat": "damage", "mul": 1.1}, {"stat": "reload_time", "add": 0.3}]},
	# Sangue Frio: o oposto da build de movimento (Player.still_aim).
	"sangue_frio": {"name": "Sangue Frio", "cat": "Arma", "rarity": "raro", "max": 2,
		"desc": "Parado ou agachado no chão: dano +25% e velocidade da bala +30%. Com 2 cópias, +50% e +60%.",
		"mods": [{"stat": "still_aim", "add": 1}]},

	# Balas
	"ricochete": {"name": "Ricochete", "cat": "Balas", "rarity": "comum",
		"desc": "As balas quicam uma vez a mais nas paredes.",
		"mods": [{"stat": "bounces", "add": 1}]},
	# 2026-10-10, pedido do usuário depois que a Tabelinha deixou de dar quiques: +2 numa
	# carta só, com -20% de dano (ele quis 20 em vez dos 15 propostos, para ser conservador).
	"bola_borracha": {"name": "Bola de Borracha", "cat": "Balas", "rarity": "raro",
		"desc": "As balas quicam duas vezes a mais nas paredes. Dano -20%.",
		"mods": [{"stat": "bounces", "add": 2}, {"stat": "damage", "mul": 0.8}]},
	"teleguiada": {"name": "Teleguiada", "cat": "Balas", "rarity": "lendario",
		"desc": "Algumas balas (35%) que passam perto do inimigo curvam na direção dele e ficam verdes. Mais cópias: mais balas procuram (nunca todas, no máximo 70%) e de um pouco mais longe. Dano -20%. Recarregar +0,25 s.",
		"mods": [{"stat": "homing", "add": 1.0}, {"stat": "damage", "mul": 0.8}, {"stat": "reload_time", "add": 0.25}]},
	"fantasma": {"name": "Bala Fantasma", "cat": "Balas", "rarity": "lendario", "max": 2,
		"desc": "Cada bala atravessa a primeira parede em que bater (com 2 cópias, as duas primeiras). Dano -15%.",
		"mods": [{"stat": "ghost", "add": 1}, {"stat": "damage", "mul": 0.85}]},
	"explosiva": {"name": "Explosiva", "cat": "Balas", "rarity": "epico",
		"desc": "As balas explodem ao bater (raio de 3 m). Dano -15%.",
		"mods": [{"stat": "explosion", "add": 3.0}, {"stat": "damage", "mul": 0.85}]},
	"veneno": {"name": "Veneno", "cat": "Balas", "rarity": "raro",
		"desc": "Acertar aplica Veneno: mais 60% do dano (da parte acima de 40, só 40%), tirado ao longo de 5 s. Pente -1.",
		"mods": [{"stat": "poison", "add": 0.6}, {"stat": "mag_size", "add": -1}]},
	# Bala Incendiária (2026-10-14, pedido do usuário: Queimadura pelo tiro, rápida e curta
	# como no The Bazaar; números meus aprovados).
	"incendiaria": {"name": "Bala Incendiária", "cat": "Balas", "rarity": "raro", "max": 3,
		"desc": "Acertar aplica Queimadura: 50% do dano da bala por segundo (da parte acima de 40, só 35%), por 1 s. Mais cópias: +50% por segundo. Cadência -10%.",
		"mods": [{"stat": "burn", "add": 0.5}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	# Brasa e Combustível (2026-10-14, propostas minhas aprovadas; números para testar).
	"brasa": {"name": "Brasa", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Cada acerto em quem já queima com seu fogo aumenta essa Queimadura em +25%, até o dobro. Volta ao normal quando a queimadura acaba. Recarregar +0,2 s.",
		"mods": [{"stat": "ember", "add": 1}, {"stat": "reload_time", "add": 0.2}]},
	"combustivel": {"name": "Combustível", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Sua Queimadura tira 40% mais em quem também está com outra aflição: Veneno, Congelamento, Lentidão, Cegueira, Tontura ou Escudo bloqueado. Dano -5%.",
		"mods": [{"stat": "fuel", "add": 1}, {"stat": "damage", "mul": 0.95}]},
	# Combustão Lenta (2026-10-14, pedido do usuário: mais tempo de fogo sem desbalancear):
	# Player.SLOW_BURN_*; teto de 4 s na Queimadura (BURN_MAX_TIME).
	"combustao_lenta": {"name": "Combustão Lenta", "cat": "Balas", "rarity": "raro", "max": 2,
		"desc": "Sua Queimadura dura +0,5 s, mas tira 10% menos por segundo. A Queimadura dura no máximo 4 s.",
		"mods": [{"stat": "slow_burn", "add": 1}]},
	# Bala Letárgica: era "Bala Gelada" até 2026-10-15 (o nome confundia com o Congelamento;
	# id mantido para os baralhos salvos).
	"congelante": {"name": "Bala Letárgica", "cat": "Balas", "rarity": "raro",
		"desc": "Acertar aplica Lentidão: o alvo anda 35% mais devagar por 1,5 s.",
		"mods": [{"stat": "slow", "add": 0.35}]},
	# Congelamento (2026-10-15, ideia do usuário; números meus aprovados; 1 camada por tiro e
	# o Choque Térmico como congelar + queimar foram pedidos dele). Código: Player.FROST_* etc.
	"bala_de_gelo": {"name": "Bala de Gelo", "cat": "Balas", "rarity": "raro", "max": 2,
		"desc": "Acertar põe 1 camada de Congelamento (2 com 2 cópias). Dano -10%.",
		"mods": [{"stat": "frost", "add": 1}, {"stat": "damage", "mul": 0.9}]},
	"hipotermia": {"name": "Hipotermia", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Acertar quem está com Lentidão põe +1 camada de Congelamento. Quem você congela fica congelado 0,8 s em vez de 0,5. Recarregar +0,2 s.",
		"mods": [{"stat": "hypothermia", "add": 1}, {"stat": "reload_time", "add": 0.2}]},
	"estilhaco": {"name": "Estilhaço", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Quebrar o gelo de alguém acerta também os inimigos a até 4 m dele: metade do golpe e 2 camadas de Congelamento. Cadência -10%.",
		"mods": [{"stat": "shatter", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	"choque_termico": {"name": "Choque Térmico", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Quando o gelo de quem você congelou acaba (quebrado ou derretido), ele leva +10 de dano e Queimadura de 10 por segundo por 1,5 s. Dano -5%.",
		"mods": [{"stat": "thermal", "add": 1}, {"stat": "damage", "mul": 0.95}]},
	"propulsao": {"name": "Propulsão", "cat": "Balas", "rarity": "comum",
		"desc": "As balas empurram quem levar o tiro. Recarregar +0,25 s.",
		"mods": [{"stat": "knockback", "add": 12.0}, {"stat": "reload_time", "add": 0.25}]},
	"quique_certeiro": {"name": "Quique Certeiro", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "+1 quique. Ao quicar, a bala pode virar um pouco para o inimigo e passar a procurá-lo como a Teleguiada (35% de chance). Cópias de Teleguiada deixam isso mais forte. Dano -20%.",
		"mods": [{"stat": "target_bounce", "add": 1}, {"stat": "bounces", "add": 1}, {"stat": "damage", "mul": 0.8}]},
	"atordoante": {"name": "Atordoante", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Acertar o inimigo bloqueia o escudo dele por 2 s. Depois disso, ele fica 3 s sem poder ser atordoado de novo. Cadência -10%.",
		"mods": [{"stat": "shield_break", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	"sanguessuga": {"name": "Sanguessuga", "cat": "Balas", "rarity": "epico",
		"desc": "Recupera 25% do dano que causar. Dano -10%.",
		"mods": [{"stat": "lifesteal", "add": 0.25}, {"stat": "damage", "mul": 0.9}]},
	# Build de efeitos (2026-10-14, ideia do usuário; Marca, Persistência e Ácido com números
	# meus aprovados, Corrosão ideia dele). Código em Player (MARK_*, ACID_*, take_damage).
	"marca": {"name": "Marca", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Causar dano marca o inimigo por 3 s: você o vê através das paredes e ele leva +15% do seu dano. Só marca de novo 5 s depois. Seu Veneno e sua Queimadura também marcam.",
		"mods": [{"stat": "mark", "add": 1}]},
	"persistencia": {"name": "Persistência", "cat": "Balas", "rarity": "raro", "max": 3,
		"desc": "Seu Veneno e sua Queimadura duram 30% mais (e tiram mais no total). Dano -5%.",
		"mods": [{"stat": "dot_time", "add": 0.3}, {"stat": "damage", "mul": 0.95}]},
	"acido": {"name": "Ácido", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Enquanto sofre seu Veneno ou sua Queimadura, o inimigo cura 50% menos.",
		"mods": [{"stat": "acid", "add": 1}]},
	"corrosao": {"name": "Corrosão", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Seu Veneno e sua Queimadura ignoram o colete: tiram direto da vida.",
		"mods": [{"stat": "dot_pierce", "add": 1}]},
	# Contágio (2026-10-14, ideia minha aprovada; a volta para o próprio alvo é pedido dele).
	"contagio": {"name": "Contágio", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Seu Veneno pula, com metade da força, para inimigos a até 4 m de quem está envenenado; sem ninguém perto, volta para o próprio envenenado. Cada um pega isso no máximo a cada 4 s e o veneno que pulou não pula de novo. Só vale com Veneno ou Nuvem Tóxica. Pente -1.",
		"mods": [{"stat": "contagion", "add": 1}, {"stat": "mag_size", "add": -1}]},
	# Reação em Cadeia (2026-10-14, ideia do usuário; números meus aprovados): Player.CHAIN_*.
	"reacao_em_cadeia": {"name": "Reação em Cadeia", "cat": "Balas", "rarity": "epico", "max": 2,
		"desc": "Quando uma aflição sua termina num inimigo, ele explode: toma metade do dano da sua bala (no mínimo 5, até 25) e causa o mesmo a outros inimigos a até 4 m, que pegam de novo a aflição que terminou. Cada um explode no máximo a cada 3 s. Com 2 cópias, 80% do dano da bala (até 40) e 5 m. Recarregar +0,3 s.",
		"mods": [{"stat": "chain_blast", "add": 1}, {"stat": "reload_time", "add": 0.3}]},
	# Dose Extra e Raspão (2026-10-17, ideias minhas aprovadas pelo usuário: a build de aflição
	# pura fica com 1 ou 2 balas no pente pelo Veneno e erra muito; números meus, para testar).
	"dose_extra": {"name": "Dose Extra", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Acertar e aplicar uma aflição que o inimigo ainda não tinha devolve 1 bala ao pente. Recarregar +0,3 s.",
		"mods": [{"stat": "fresh_refund", "add": 1}, {"stat": "reload_time", "add": 0.3}]},
	"raspao": {"name": "Raspão", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "A bala que passa a até 1 m de um inimigo sem acertar aplica nele as suas aflições, sem dano. No máximo uma vez a cada 0,25 s em cada inimigo. Cadência -10%.",
		"mods": [{"stat": "graze", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	"executor": {"name": "Executor", "cat": "Balas", "rarity": "raro", "max": 2,
		"desc": "+40% de dano em quem está abaixo de 40% da vida. Cadência -10%.",
		"mods": [{"stat": "execute", "add": 0.4}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},

	"bumerangue": {"name": "Bumerangue", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Depois de meio segundo, ou 3 m antes do fim do Alcance, as balas dão meia-volta e voltam para você, acertando de novo no caminho. Na volta o Alcance não vale.",
		"mods": [{"stat": "boomerang", "add": 1}]},
	"tabelinha": {"name": "Tabelinha", "cat": "Balas", "rarity": "lendario",
		"desc": "Cada quique soma +30% do dano de saída à bala. Não dá quiques: junte com Ricochete ou outras cartas de quique.",
		"mods": [{"stat": "bounce_damage", "add": 0.3}]},
	"detonacao": {"name": "Detonação", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "As balas grudam onde batem e explodem 0,6 s depois (raio de 3,5 m). Recarregar +0,25 s.",
		"mods": [{"stat": "sticky", "add": 1}, {"stat": "reload_time", "add": 0.25}]},
	"fragmentacao": {"name": "Fragmentação", "cat": "Balas", "rarity": "epico",
		"desc": "Ao bater na parede, a bala se parte em 4 estilhaços com 40% do dano.",
		"mods": [{"stat": "split", "add": 4}]},
	"bola_de_neve": {"name": "Bola de Neve", "cat": "Balas", "rarity": "lendario",
		"desc": "A bala cresce com o tempo de voo e ganha até +100% de dano em 5 s. Sem quiques ou outro jeito de durar mais, ela some antes do máximo.",
		"mods": [{"stat": "grow", "add": 1.0}]},
	"troca_troca": {"name": "Troca-Troca", "cat": "Balas", "rarity": "lendario", "max": 1,
		"desc": "Acertar o inimigo marca vocês dois: 0,6 s depois, trocam de lugar. A mesma pessoa só é trocada de novo 2 s depois. Dano -15%.",
		"mods": [{"stat": "swap", "add": 1}, {"stat": "damage", "mul": 0.85}]},
	"flash": {"name": "Flash", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Acertar o inimigo deixa a tela dele branca por 0,9 s. Depois disso, ele fica 2 s sem poder ser cegado de novo.",
		"mods": [{"stat": "blind", "add": 0.9}]},
	"preguicosa": {"name": "Bala Preguiçosa", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "As balas saem devagar e aceleram até 2,5x a velocidade normal. Dano +25%.",
		"mods": [{"stat": "lazy", "add": 1}, {"stat": "damage", "mul": 1.25}]},
	# Dinamite e Carga Concentrada (2026-10-07, pedido do usuário: cartas que melhoram a
	# explosão; números meus, aprovados). Só valem com alguma carta de explosão.
	"dinamite": {"name": "Dinamite", "cat": "Balas", "rarity": "raro",
		"desc": "Suas explosões ficam 1 m maiores e causam +30% de dano. Sem explosão, não faz nada.",
		"mods": [{"stat": "blast_radius", "add": 1.0}, {"stat": "blast_damage", "add": 0.3}]},
	"carga_concentrada": {"name": "Carga Concentrada", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Suas explosões causam +60% de dano, mas ficam 1 m menores. Sem explosão, não faz nada.",
		"mods": [{"stat": "blast_damage", "add": 0.6}, {"stat": "blast_radius", "add": -1.0}]},
	# Nuvem Tóxica e Buraco Negro (2026-10-06, cartas do Furor lembradas pelo usuário; números
	# meus). Desenho e limites em AreaField.
	"nuvem_toxica": {"name": "Nuvem Tóxica", "cat": "Balas", "rarity": "epico", "max": 3,
		"desc": "Onde a bala bate fica uma nuvem (2,5 m, 3 s) que aplica Veneno em quem estiver dentro: 30% do dano da bala por segundo dentro (da parte acima de 40, só 20%), tirado ao longo de 5 s. Nuvens suas não somam no mesmo alvo. Mais cópias: +0,75 m e +1 s. Cadência -20%.",
		"mods": [{"stat": "toxic", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.8}]},
	"buraco_negro": {"name": "Buraco Negro", "cat": "Balas", "rarity": "epico", "max": 2,
		"desc": "Onde a bala bate surge por 0,6 s um buraco negro que puxa os inimigos a até 5 m para o centro. Com 2 cópias puxa mais forte e de 6 m. Dano -10%.",
		"mods": [{"stat": "black_hole", "add": 1}, {"stat": "damage", "mul": 0.9}]},

	# Escudo
	# Recarga do E (2026-10-07, regra do Furor descrita pelo usuário): toda carta que melhora
	# o escudo deixa a recarga mais longa, +1 s se o efeito é forte e +0,5 s se é fraco, por
	# cópia. Reflexos (-0,5 s, só isso) é a que mais tira sem custo; as que tiram e fazem
	# outra coisa tiram menos ou cobram algo. Somas limitadas em compute_stats.
	"escudo_firme": {"name": "Escudo Firme", "cat": "Escudo", "rarity": "comum",
		"desc": "O escudo dura +0,15 s. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_duration", "add": 0.15}, {"stat": "shield_cooldown", "add": 0.5}]},
	"reflexos": {"name": "Reflexos", "cat": "Escudo", "rarity": "comum",
		"desc": "Recarga do escudo -0,5 s.",
		"mods": [{"stat": "shield_cooldown", "add": -0.5}]},
	"defensor": {"name": "Defensor", "cat": "Escudo", "rarity": "comum",
		"desc": "Vida +15%. Recarga do escudo -0,25 s.",
		"mods": [{"stat": "max_health", "mul": 1.15}, {"stat": "shield_cooldown", "add": -0.25}]},
	"passo_ligeiro": {"name": "Passo Ligeiro", "cat": "Escudo", "rarity": "comum",
		"desc": "Levantar o escudo dá +25% de velocidade de movimento por 1,5 s. Recarga do escudo -0,3 s.",
		"mods": [{"stat": "shield_haste", "add": 0.25}, {"stat": "shield_cooldown", "add": -0.3}]},
	"escudo_de_papel": {"name": "Escudo de Papel", "cat": "Escudo", "rarity": "raro",
		"desc": "Recarga do escudo -1 s. Vida -20%.",
		"mods": [{"stat": "shield_cooldown", "add": -1.0}, {"stat": "max_health", "mul": 0.8}]},
	"espelho_cortante": {"name": "Espelho Cortante", "cat": "Escudo", "rarity": "raro",
		"desc": "Balas refletidas causam +75% de dano. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "reflect_mult", "add": 0.75}, {"stat": "shield_cooldown", "add": 0.5}]},
	"adrenalina": {"name": "Adrenalina", "cat": "Escudo", "rarity": "epico", "max": 1,
		"desc": "Refletir uma bala corta pela metade o que falta da recarga do escudo, uma vez por escudo levantado. Recarga do escudo +1 s.",
		"mods": [{"stat": "reflect_refund", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"espelho_duplo": {"name": "Espelho Duplo", "cat": "Escudo", "rarity": "epico",
		"desc": "Cada bala refletida volta acompanhada de mais uma. Recarga do escudo +1 s.",
		"mods": [{"stat": "reflect_split", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"espelho_perseguidor": {"name": "Espelho Perseguidor", "cat": "Escudo", "rarity": "epico",
		"desc": "Balas refletidas perseguem quem atirou. Recarga do escudo +1 s.",
		"mods": [{"stat": "reflect_homing", "add": 3.0}, {"stat": "shield_cooldown", "add": 1.0}]},
	"recarga_tatica": {"name": "Recarga Tática", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Levantar o escudo enche o pente. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_reload", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"investida": {"name": "Investida", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Levantar o escudo te lança para frente. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_dash", "add": 1}, {"stat": "shield_cooldown", "add": 0.5}]},
	"onda_de_choque": {"name": "Onda de Choque", "cat": "Escudo", "rarity": "raro",
		"desc": "O escudo empurra o inimigo a até 8 m e causa 8 de dano. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_shockwave", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"restauracao": {"name": "Restauração", "cat": "Escudo", "rarity": "comum",
		"desc": "Levantar o escudo cura 10 de vida. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_heal", "add": 10.0}, {"stat": "shield_cooldown", "add": 0.5}]},
	"nova": {"name": "Nova", "cat": "Escudo", "rarity": "epico",
		"desc": "O escudo dispara 6 balas em volta de você (meio dano). Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_nova", "add": 6}, {"stat": "shield_cooldown", "add": 1.0}]},

	"teleporte": {"name": "Teleporte", "cat": "Escudo", "rarity": "lendario", "max": 1,
		"desc": "Levantar o escudo te teleporta 7 m para onde você olha, atravessando paredes. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_teleport", "add": 1}, {"stat": "shield_cooldown", "add": 0.5}]},
	"chuva_de_bombas": {"name": "Chuva de Bombas", "cat": "Escudo", "rarity": "epico",
		"desc": "O escudo lança 5 bombas em arco à sua volta. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_bombs", "add": 5}, {"stat": "shield_cooldown", "add": 1.0}]},
	"eco": {"name": "Eco", "cat": "Escudo", "rarity": "lendario",
		"desc": "O escudo se levanta de novo sozinho 0,5 s depois, com os efeitos das suas outras cartas de Escudo, uma vez a mais por cópia. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_echo", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"ultima_defesa": {"name": "Última Defesa", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Quando o pente esvazia, o escudo levanta sozinho (se estiver pronto). Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_on_empty", "add": 1}, {"stat": "shield_cooldown", "add": 0.5}]},
	"pancada": {"name": "Pancada", "cat": "Escudo", "rarity": "raro",
		"desc": "Com o escudo de pé, quem estiver colado em você leva 20 de dano e é empurrado. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_bash", "add": 20.0}, {"stat": "shield_cooldown", "add": 1.0}]},
	# Escudo Duplo (2026-10-07, pedido do usuário: sem o limite de 1 e repetindo os efeitos):
	# cada cópia é uma levantada a mais, 0,5 s depois, com todos os efeitos. Os +30% vêm
	# depois do teto das somas, então quanto mais efeitos no escudo, mais ela cobra: a partir
	# da 2a cópia o ganho por segundo para de crescer e só a rajada aumenta.
	"escudo_duplo": {"name": "Escudo Duplo", "cat": "Escudo", "rarity": "lendario", "max": 3,
		"desc": "Dá para levantar o escudo mais uma vez meio segundo depois, com todos os efeitos de novo. Recarga do escudo +1 s e, sobre o total, +30%.",
		"mods": [{"stat": "shield_charges", "add": 1}, {"stat": "shield_cooldown", "add": 1.0},
			{"stat": "shield_cooldown", "mul": 1.3}]},
	"couraca": {"name": "Couraça", "cat": "Escudo", "rarity": "raro",
		"desc": "Levantar o escudo dá 10 de colete. O colete absorve dano antes da vida e vai até 50, junto com o do mapa. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_armor", "add": 10.0}, {"stat": "shield_cooldown", "add": 0.5}]},
	"fortaleza": {"name": "Fortaleza", "cat": "Escudo", "rarity": "comum",
		"desc": "+30 de vida e o escudo dura +0,1 s. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "max_health", "add": 30.0}, {"stat": "shield_duration", "add": 0.1},
			{"stat": "shield_cooldown", "add": 0.5}]},
	"espelho_gigante": {"name": "Espelho Gigante", "cat": "Escudo", "rarity": "raro",
		"desc": "O escudo pega balas 50% mais longe de você. Recarga do escudo +0,5 s.",
		"mods": [{"stat": "shield_size", "mul": 1.5}, {"stat": "shield_cooldown", "add": 0.5}]},
	# Áreas do escudo (2026-10-06, cartas do Furor lembradas pelo usuário; números meus, dano
	# fixo por escolha dele). Desde 2026-10-07 sem recarga própria: o custo é o +1 s no E.
	"serra": {"name": "Serra", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "O escudo faz uma serra girar em volta de você por 2 s: 18 de dano por segundo em quem estiver perto. Raio de 2,5 m, +1 m por cópia. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_saw", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"chamas": {"name": "Chamas", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "O escudo acende um círculo de fogo em volta de você por 3 s, que te acompanha: quem estiver dentro ganha Queimadura (9 por segundo), que continua 1 s depois de sair. Raio de 4 m, +1 m por cópia. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_flames", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"geada": {"name": "Geada", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "O escudo solta uma onda de gelo de 5 m: 6 de dano, Lentidão de 45% por 2 s e 2 camadas de Congelamento. Mais cópias: +1,5 m e +0,5 s. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_frost", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	# Estouro (2026-10-14, ideia do usuário, números meus; recarga +2 s pedida por ele; o
	# nome "Detonação" já era da bala que gruda).
	"estouro": {"name": "Estouro", "cat": "Escudo", "rarity": "epico", "max": 1,
		"desc": "Levantar o escudo estoura seu Veneno e sua Queimadura nos inimigos a até 30 m: eles tomam de uma vez o que faltava, x1,5 (x2 com os dois juntos), e perdem esses efeitos. Suas camadas de Congelamento também estouram: 6 de dano cada. Até 60 por alvo. Recarga do escudo +2 s.",
		"mods": [{"stat": "shield_detonate", "add": 1}, {"stat": "shield_cooldown", "add": 2.0}]},
	"mina": {"name": "Mina", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "O escudo larga uma bomba no chão que pisca e explode 1 s depois: 30 de dano (metade na borda), raio de 4 m. Mais cópias: +15 de dano e +0,5 m. Recarga do escudo +1 s.",
		"mods": [{"stat": "shield_mine", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},

	# Corpo
	"vigor": {"name": "Vigor", "cat": "Corpo", "rarity": "comum",
		"desc": "+40 de vida máxima.",
		"mods": [{"stat": "max_health", "add": 40.0}]},
	"fragil": {"name": "Frágil", "cat": "Corpo", "rarity": "comum",
		"desc": "Dano +30%. Vida -30%.",
		"mods": [{"stat": "damage", "mul": 1.3}, {"stat": "max_health", "mul": 0.7}]},
	"tanque": {"name": "Tanque", "cat": "Corpo", "rarity": "comum",
		"desc": "Vida +60%. Velocidade de movimento -10%.",
		"mods": [{"stat": "max_health", "mul": 1.6}, {"stat": "move_speed", "mul": 0.9}]},
	"sede_de_sangue": {"name": "Sede de Sangue", "cat": "Corpo", "rarity": "raro",
		"desc": "Causar dano dá +30% de velocidade de movimento por 3 s.",
		"mods": [{"stat": "bloodlust", "add": 0.3}]},
	"furia": {"name": "Fúria", "cat": "Corpo", "rarity": "raro",
		"desc": "+50% de dano enquanto estiver abaixo de 35% da vida.",
		"mods": [{"stat": "rage", "add": 0.5}]},
	"fenix": {"name": "Fênix", "cat": "Corpo", "rarity": "lendario", "max": 1,
		"desc": "Ao morrer, volta uma vez com metade da vida. Vida -20%.",
		"mods": [{"stat": "revives", "add": 1}, {"stat": "max_health", "mul": 0.8}]},
	"regeneracao": {"name": "Regeneração", "cat": "Corpo", "rarity": "raro",
		"desc": "Recupera 5 de vida por segundo depois de 5 s sem levar dano e sem atacar (tiro ou Espada).",
		"mods": [{"stat": "regen", "add": 5.0}]},
	# Peso Pesado e Segunda Pele (2026-10-07, propostas minhas aprovadas pelo usuário).
	"peso_pesado": {"name": "Peso Pesado", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "Empurrões te movem 60% menos: explosões, Propulsão, Onda de Choque, Mega Tapa, Canhão Arcano e Buraco Negro. Velocidade de movimento -10%.",
		"mods": [{"stat": "heavy", "add": 0.6}, {"stat": "move_speed", "mul": 0.9}]},
	"segunda_pele": {"name": "Segunda Pele", "cat": "Corpo", "rarity": "raro",
		"desc": "A cada 5 s sem levar dano, ganha 15 de colete, até 30 (cópias: mais colete por vez e até 50).",
		"mods": [{"stat": "armor_regen", "add": 15.0}]},
	# Casca Dura (2026-10-07, proposta minha escolhida pelo usuário no lugar dos Espinhos).
	"casca_dura": {"name": "Casca Dura", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "Depois de levar um golpe de 30 de dano ou mais, você leva 50% menos dano por 1 s.",
		"mods": [{"stat": "tough", "add": 1}]},
	"blindado": {"name": "Blindado", "cat": "Corpo", "rarity": "raro",
		"desc": "Você leva 40% menos dano de explosões e de áreas (minas, serras, meteoros). Não vale contra aflições, como veneno e queimadura. Cópias somam até 70%.",
		"mods": [{"stat": "blast_resist", "add": 0.4}]},
	"radar": {"name": "Radar", "cat": "Corpo", "rarity": "epico", "max": 3,
		"desc": "Você vê o nome e a vida dos inimigos a até 30 m através das paredes. Cada cópia soma +30 m.",
		"mods": [{"stat": "radar", "add": 1}]},
	"nanico": {"name": "Nanico", "cat": "Corpo", "rarity": "raro",
		"desc": "Corpo 30% menor, mais difícil de acertar. Vida -20%. Dano -10%.",
		"mods": [{"stat": "body_scale", "mul": 0.7}, {"stat": "max_health", "mul": 0.8}, {"stat": "damage", "mul": 0.9}]},
	"gigantao": {"name": "Gigantão", "cat": "Corpo", "rarity": "epico",
		"desc": "Corpo 40% maior. Vida +80%. Velocidade de movimento -15%.",
		"mods": [{"stat": "body_scale", "mul": 1.4}, {"stat": "max_health", "mul": 1.8}, {"stat": "move_speed", "mul": 0.85}]},
	# Corpo (2026-10-11, pedido do usuário: equilibrar os grupos; números meus, aprovados).
	# Couro Grosso refeito pelo usuário: redução que acumula enquanto apanha e zera parado.
	"couro_grosso": {"name": "Couro Grosso", "cat": "Corpo", "rarity": "raro", "max": 2,
		"desc": "Cada golpe que você leva soma 1 de redução nos seguintes (o primeiro entra cheio), até 5 de dano a menos por golpe (8 com 2 cópias; nunca abaixo de 1). 1,5 s sem levar golpe zera. Veneno, queimadura e serra não contam.",
		"mods": [{"stat": "thick_skin", "add": 1}]},
	"banquete": {"name": "Banquete", "cat": "Corpo", "rarity": "raro",
		"desc": "Fazer um abate cura 30 de vida.",
		"mods": [{"stat": "kill_heal", "add": 30.0}]},
	"tenacidade": {"name": "Tenacidade", "cat": "Corpo", "rarity": "raro", "max": 2,
		"desc": "Toda aflição dura 35% menos em você: lentidão, tontura, cegueira, veneno, queimadura e congelamento (60% com 2 cópias).",
		"mods": [{"stat": "tenacity", "add": 0.35}]},
	"metabolismo": {"name": "Metabolismo", "cat": "Corpo", "rarity": "comum",
		"desc": "Toda cura que você recebe é 40% maior.",
		"mods": [{"stat": "heal_mult", "add": 0.4}]},
	"instinto": {"name": "Instinto de Sobrevivência", "cat": "Corpo", "rarity": "raro",
		"desc": "Abaixo de 35% da vida, +25% de velocidade.",
		"mods": [{"stat": "survival_speed", "add": 0.25}]},
	"vinganca": {"name": "Vingança", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "Seus tiros causam +25% de dano em quem te matou na rodada anterior.",
		"mods": [{"stat": "revenge", "add": 0.25}]},
	"leveza": {"name": "Leveza", "cat": "Corpo", "rarity": "comum",
		"desc": "Velocidade de movimento +15%. Vida -15%.",
		"mods": [{"stat": "move_speed", "mul": 1.15}, {"stat": "max_health", "mul": 0.85}]},

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
		"desc": "Pula 15% mais alto e desce 35% mais devagar.",
		"mods": [{"stat": "jump_velocity", "mul": 1.15}, {"stat": "gravity_mult", "mul": 0.65}]},
	"botas_leves": {"name": "Botas Leves", "cat": "Movimento", "rarity": "comum",
		"desc": "+8% de velocidade.",
		"mods": [{"stat": "move_speed", "mul": 1.08}]},
	"cacador": {"name": "Caçador", "cat": "Movimento", "rarity": "raro",
		"desc": "Por 2 s depois de acertar um inimigo, +20% de velocidade andando na direção dele. Veneno, queimadura e serra não contam.",
		"mods": [{"stat": "chase", "add": 0.2}]},
	"pulo_foguete": {"name": "Pulo-Foguete", "cat": "Movimento", "rarity": "epico", "max": 1,
		"desc": "As balas explodem (raio de 2 m). Suas explosões te lançam para longe delas sem te ferir, somando à velocidade que você já tinha: 2 vezes antes de tocar o chão, a 2a mais fraca. Inimigos pegos são empurrados.",
		"mods": [{"stat": "rocket_jump", "add": 1}, {"stat": "explosion", "add": 2.0}]},
	"meteoro": {"name": "Meteoro", "cat": "Movimento", "rarity": "epico",
		"desc": "Agachar no ar (Ctrl) despenca em vez de dar dash; o Shift segue no dash. Quanto mais alto, mais forte: 20 a 40 de dano a até 2,5 m e metade até 5 m; de 4 m para cima, tontura. Você quica para cima. Recarga de 3 s.",
		"mods": [{"stat": "ground_slam", "add": 1}]},
	"folego": {"name": "Fôlego", "cat": "Movimento", "rarity": "comum",
		"desc": "Recarga do dash -40%.",
		"mods": [{"stat": "dash_cooldown", "mul": 0.6}]},
	"dash_longo": {"name": "Dash Longo", "cat": "Movimento", "rarity": "comum",
		"desc": "O dash vai 40% mais longe.",
		"mods": [{"stat": "dash_power", "mul": 1.4}]},
	"esquiva": {"name": "Esquiva", "cat": "Movimento", "rarity": "lendario", "max": 1,
		"desc": "Durante o dash as balas te atravessam. Recarga do dash +0,3 s.",
		"mods": [{"stat": "dash_dodge", "add": 1}, {"stat": "dash_cooldown", "add": 0.3}]},
	"atropelar": {"name": "Atropelar", "cat": "Movimento", "rarity": "raro",
		"desc": "Passar por um inimigo no dash causa 15 de dano e o empurra.",
		"mods": [{"stat": "dash_hit", "add": 15.0}]},
	"saque_rapido": {"name": "Saque Rápido", "cat": "Movimento", "rarity": "raro",
		"desc": "Cada dash põe 2 balas no pente.",
		"mods": [{"stat": "dash_ammo", "add": 2}]},
	"cacada": {"name": "Caçada", "cat": "Movimento", "rarity": "epico", "max": 1,
		"desc": "Acertar o inimigo recarrega o dash na hora e devolve um dash no ar. Veneno, queimadura e serra não contam.",
		"mods": [{"stat": "hit_dash", "add": 1}]},
	"planador": {"name": "Planador", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Segure Espaço caindo para planar devagar. Depois de planar, até tocar o chão, você muda de direção no ar sem perder velocidade.",
		"mods": [{"stat": "glide", "add": 1}]},
	"embalo": {"name": "Embalo", "cat": "Movimento", "rarity": "comum",
		"desc": "Controle no ar 2x maior (curva sem perder velocidade) e +5% de velocidade.",
		"mods": [{"stat": "air_control", "mul": 2.0}, {"stat": "move_speed", "mul": 1.05}]},
	"molas": {"name": "Molas", "cat": "Movimento", "rarity": "comum",
		"desc": "Pula 20% mais alto.",
		"mods": [{"stat": "jump_velocity", "mul": 1.2}]},
	# Pisão (2026-10-06, ideia do usuário; números meus). Código em Player._check_stomp.
	# Parkour (2026-10-07, proposta minha; 1 s em vez de 1,5 a pedido do usuário).
	"parkour": {"name": "Parkour", "cat": "Movimento", "rarity": "raro",
		"desc": "Pular de uma parede te devolve um dash no ar e dá +20% de velocidade de movimento por 1 s.",
		"mods": [{"stat": "parkour", "add": 1}]},
	# Dash Duplo (2026-10-07, ideia do usuário no estilo do Escudo Duplo; números meus).
	"dash_duplo": {"name": "Dash Duplo", "cat": "Movimento", "rarity": "lendario", "max": 2,
		"desc": "Cada dash seu emenda outro sozinho logo depois, para onde você estiver apertando (curva no meio). Os efeitos de dash se repetem e no ar o extra não gasta dash. Com 2 cópias são 3 dashes. Recarga do dash +0,3 s.",
		"mods": [{"stat": "dash_echo", "add": 1}, {"stat": "dash_cooldown", "add": 0.3}]},
	"pisao": {"name": "Pisão", "cat": "Movimento", "rarity": "raro", "max": 3,
		"desc": "Cair na cabeça de um inimigo (pulando ou no dash pelo ar) causa 20 de dano e te quica para cima, devolvendo o dash e os pulos no ar. +10 de dano por cópia.",
		"mods": [{"stat": "stomp", "add": 1}]},
	# Build de movimento (2026-10-11, pedido do usuário: velocidade vira dano e defesa, e
	# chegar no corpo do inimigo; números meus, aprovados). Código em Player.shot_damage,
	# bullet_taken_mult, _tick (recarga) e _start_dash/_dash_seek_step (Bote).
	"velocidade_letal": {"name": "Velocidade Letal", "cat": "Movimento", "rarity": "raro", "max": 2,
		"desc": "Seus tiros causam +2% de dano por m/s acima de 9 m/s (a velocidade de andar), até +30% no dash. Com 2 cópias, o dobro: +4% por m/s, até +60%.",
		"mods": [{"stat": "speed_damage", "add": 0.3}]},
	"vulto": {"name": "Vulto", "cat": "Movimento", "rarity": "epico", "max": 2,
		"desc": "Acima de 12 m/s você leva 20% menos dano de balas (35% com 2 cópias).",
		"mods": [{"stat": "blur", "add": 1}]},
	"recarga_embalo": {"name": "Recarga no Embalo", "cat": "Movimento", "rarity": "comum",
		"desc": "No ar ou deslizando, recarregar fica 40% mais rápido.",
		"mods": [{"stat": "air_reload", "add": 0.4}]},
	# Arrancada e Pressão (2026-10-15, build de escopeta; números meus aprovados). Player.STRIKE_*
	# e PRESSURE_*.
	"arrancada": {"name": "Arrancada", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Dar o dash na direção de um inimigo à vista (a até 20 m) faz o próximo tiro, em até 1 s, causar +30% de dano. Recarga do dash +0,5 s.",
		"mods": [{"stat": "dash_strike", "add": 1}, {"stat": "dash_cooldown", "add": 0.5}]},
	"pressao": {"name": "Pressão", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Acertar um inimigo a até 6 m dá +25% de velocidade de movimento por 1,5 s e adianta a recarga do dash em 1 s (o leque da escopeta conta uma vez). Vida -10%.",
		"mods": [{"stat": "pressure", "add": 1}, {"stat": "max_health", "mul": 0.9}]},
	"bote": {"name": "Bote", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Dar o dash quase na direção de um inimigo à vista (a até 10 m) faz o dash curvar sozinho até ele, até 35 graus.",
		"mods": [{"stat": "dash_seek", "add": 1}]},
}


var _icons := {}


func _init() -> void:
	# Toda carta comum diz no fim quantas vezes dá para pegá-la na partida (2026-10-06,
	# pedido do usuário: "máx." no editor parecia falar do baralho). Cópias no baralho só
	# aumentam a chance de ela aparecer; o limite é da partida.
	for id in CARDS:
		CARDS[id]["desc"] += " " + limit_text(id)
	CARDS.merge(MASTERS)


## Cartas comuns (as que vão no baralho e aparecem na escolha de 1 de 3).
func all_ids() -> Array:
	return CARDS.keys().filter(func(id): return not is_master(id))


func master_ids() -> Array:
	return MASTERS.keys()


## "Sem limite na partida.", "Só 1 vez na partida." ou "Até 2 vezes na partida."
func limit_text(id: String) -> String:
	var card: Dictionary = CARDS[id]
	if not card.has("max"):
		return "Sem limite na partida."
	if card["max"] == 1:
		return "Só 1 vez na partida."
	return "Até %d vezes na partida." % card["max"]


## Versão curta para o editor: "" sem limite, "1 por partida", "2 por partida".
func limit_short(id: String) -> String:
	return "%d por partida" % CARDS[id]["max"] if CARDS[id].has("max") else ""


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
	{"name": "Caos", "desc": "só as cartas mais malucas", "master": "caos",
		"ids": ["bumerangue", "troca_troca", "bola_de_neve", "preguicosa", "fragmentacao", "tabelinha",
			"detonacao", "morteiro", "metralhadora", "escopeta", "bala_gigante", "teleguiada",
			"quique_certeiro", "espelho_duplo", "nova", "chuva_de_bombas", "teleporte", "nanico",
			"gigantao", "pulo_foguete", "meteoro", "flash", "pena", "escalador",
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
		if stat != "shield_cooldown":
			stats[stat] *= muls[stat]
	for stat in HIGHER_BETTER:
		var floor_value: float = PENALTY_FLOOR_ABS.get(stat, base[stat] * PENALTY_FLOOR_BY.get(stat, PENALTY_FLOOR))
		if stat == "damage":
			# O piso do dano vale para o tiro inteiro (2026-10-07): com várias balas por
			# tiro, cada uma pode ficar abaixo dele. Senão Escopetas somadas passavam de 4x.
			# Só as balas de graça dividem: as que gastam pente (Rajada, Escopeta) não.
			floor_value /= maxf(1.0, stats["bullet_count"] - stats["shot_ammo"])
		stats[stat] = maxf(stats[stat], floor_value)
	for stat in LOWER_BETTER:
		var ceil_value: float = SHIELD_COST_MAX if stat == "shield_cooldown" else base[stat] * PENALTY_CEIL
		stats[stat] = minf(stats[stat], ceil_value)
	for stat in good_add:
		stats[stat] += good_add[stat]
	# Piso antes do Escudo Duplo, senão Reflexos repetido zeraria também o custo dele.
	stats["shield_cooldown"] = maxf(stats["shield_cooldown"], LIMITS["shield_cooldown"][0]) 		* muls.get("shield_cooldown", 1.0)
	for stat in bonus:
		if stat in LOWER_BETTER:
			stats[stat] /= 1.0 + bonus[stat]
		else:
			stats[stat] *= 1.0 + bonus[stat]
	# Os bônus de situação somam a este (Player.shot_damage), em vez de multiplicar o dano.
	stats["damage_bonus"] = bonus.get("damage", 0.0)
	for stat in LIMITS:
		stats[stat] = clampf(stats[stat], LIMITS[stat][0], LIMITS[stat][1])
	var size: float = stats["body_scale"] * pow(stats["max_health"] / base["max_health"], HEALTH_SIZE_EXP)
	stats["body_scale"] = clampf(size, LIMITS["body_scale"][0], LIMITS["body_scale"][1])
	for stat in stats.keys():
		if base[stat] is int:
			stats[stat] = int(round(stats[stat]))
	return stats
