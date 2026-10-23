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
## Os nomes (aqui e nas tabelas abaixo) são o texto em inglês: mostrar sempre pelas funções
## card_name, card_desc, rarity_label, category_name... que traduzem (ver Lang).
const RARITIES := {
	"comum": {"name": "Common", "color": Color(0.72, 0.74, 0.78)},
	"raro": {"name": "Rare", "color": Color(0.35, 0.65, 1.0)},
	"epico": {"name": "Epic", "color": Color(0.78, 0.42, 1.0)},
	"lendario": {"name": "Legendary", "color": Color(1.0, 0.68, 0.15)},
	"mitico": {"name": "Mythic", "color": Color(1.0, 0.32, 0.38)},
}

## Grupos de cartas: a chave (em português) é o id usado no código e em "cat"; o valor é o
## nome mostrado.
const CATEGORY_NAMES := {"Arma": "Weapon", "Balas": "Bullets", "Escudo": "Shield", "Corpo": "Body",
	"Movimento": "Movement"}

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
	"bazuca": {"name": "Bazooka", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: swaps your weapon for a bazooka for 6 s. 3 straight rockets with double damage that explode (4 m, growing with Bullet size up to 7 m). Each extra bullet per shot adds +50% to the rocket, and Fire rate bonuses shorten the time between rockets. The explosion launches you like Rocket Jump, without hurting you. Cooldown 18 s.",
		"mods": [{"stat": "bazooka", "add": 1}]},
	# Espada (2026-10-06, desenho do usuário: combo de 3; números meus).
	"espada": {"name": "Sword", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 24.0,
		"desc": "Q: swaps your weapon for a sword for 8 s. Click attacks in a 3-hit combo: a slash to the right, a slash to the left and a thrust that launches you forward. Reach of 3.2 m; slashes deal the weapon's damage, the thrust 1.6x. Strikes follow your Fire rate: if it is slower than the base weapon's, the strikes are spaced further apart. A raised shield blocks, and whoever blocks leaves you dizzy for 0.6 s (no strikes and slowed). With the sword in hand, you move 25% slower and can't use the shield. Cooldown 24 s.",
		"mods": [{"stat": "sword", "add": 1}]},
	# Sniper (2026-10-06, desenho do usuário; números meus): como a Bazuca, troca de arma no Q.
	"sniper": {"name": "Sniper", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: swaps your weapon for a sniper with ONE shot, for up to 8 s. The shot is a laser: straight, almost instant, goes through every wall and deals 4x damage (100 at base). Right click aims with zoom. Cooldown 18 s.",
		"mods": [{"stat": "sniper", "add": 1}]},
	# Canhão Arcano (2026-10-06, desenho do usuário, "tipo Kamehameha"; números meus,
	# aprovados; andar devagar na carga foi escolha dele).
	"canhao_arcano": {"name": "Arcane Cannon", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: charges for 1 s (moving slowly) and fires a 40 m beam for 2.5 s that goes through walls. You stay in place, on the ground or floating in the air, and aim slowly. Each touch deals 22 damage, growing with your bullet Damage (44 with 50), applies your bullets' afflictions (poison, burn, frost, slow...) and throws the target out of the beam (the same target once every 0.6 s). A raised shield blocks the damage. Getting slapped, freezing or dying cuts the beam. Cooldown 18 s.",
		"mods": [{"stat": "beam", "add": 1}]},
	# Chuva de Meteoros (2026-10-06, ideia do usuário; números meus, aprovados; ignorar
	# telhados foi escolha dele).
	"chuva_de_meteoros": {"name": "Meteor Shower", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 16.0,
		"desc": "Q: your next 3 shots (within 8 s) mark the ground where they land. 1.5 s later a meteor falls on each mark: 30 + half the shot's damage at the center (up to 55), half that at the 4 m edge, and it knocks back. Everyone sees the mark. Cooldown 16 s.",
		"mods": [{"stat": "meteor", "add": 1}]},
	# Foguete (2026-10-06, desenho do usuário; números meus, aprovados; subir e descer,
	# explodir montado ao bater e o grupo Arma foram escolhas dele).
	"foguete": {"name": "Rocket Ride", "cat": "Arma", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: ride a rocket that always flies forward (10 m/s) and turns very slowly, for up to 5 s. Q again: you jump off and the rocket keeps going straight, speeds up a lot and explodes on first contact. While you ride it, it explodes if it hits a wall, touches an enemy or time runs out (you are launched upward, no damage). Explosion of 70 at the center, up to 7 m. Cooldown 18 s.",
		"mods": [{"stat": "rocket_ride", "add": 1}]},
	"perfurante": {"name": "Piercer", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 20.0,
		"desc": "Q: your next 3 shots fly straight, with no drop, 3x faster, with +30% damage and passing through everything: walls, players (each one is hit once), the shield and the Bastion, which can't reflect them. The damage ignores armor and goes straight to health. Cooldown 20 s.",
		"mods": [{"stat": "pierce", "add": 1}]},
	"bastiao": {"name": "Bastion", "cat": "Escudo", "rarity": "mitico", "master": true, "cooldown": 14.0,
		"desc": "Q: raises an energy wall in front of you for 4 s that reflects enemy bullets back at whoever fired them, with +50% damage. Yours pass through. Q again pushes the wall 10 m forward: whoever it runs over is pushed and takes 25 damage (growing with your bullet Damage; a raised shield blocks the damage). Cooldown 14 s.",
		"mods": [{"stat": "barrier", "add": 1}]},
	# Prisão de Gelo (2026-10-06, desenho do usuário; números meus, ele pediu 3 s; o bloco
	# quica no vazio e o dano do vazio vem quando o gelo derrete).
	# Reforço de 2026-10-15 (pedido do usuário: difícil de acertar e retorno baixo): caco
	# mais grosso que estilhaça no cenário, bloco que guarda dano, 1 camada por acerto, 12 s.
	"prisao_gelo": {"name": "Ice Prison", "cat": "Escudo", "rarity": "mitico", "master": true, "cooldown": 12.0,
		"desc": "Your hits apply 1 frost stack. Q: fires an ice shard (straight, up to 40 m). Whoever is hit is trapped in an ice block for 3 s: they can't act and don't lose health, but the block stores half the damage it takes (up to 50) and releases it all when it thaws, along with breaking the ice (+20). The block slides: shots, explosions and bumps push it. Over the void it bounces, and the damage comes when the ice melts. If the shard hits the scenery, it shatters: 2 stacks on anyone within 3 m. The shield reflects the shard. Cooldown 12 s.",
		"mods": [{"stat": "ice", "add": 1}, {"stat": "frost", "add": 1}]},
	# Mega Tapa (2026-10-06, ideia do usuário: tirar quem joga de perto; números meus e o
	# impacto na parede, escolhido por ele entre 3 extras).
	"mega_tapa": {"name": "Mega Slap", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 8.0,
		"desc": "Q: raises your hand and, 0.6 s later, slaps forward (4.5 m), dealing 20 damage (growing with your bullet Damage) and throwing the target far and upward, with no air control until they land. If the thrown player hits a wall in flight, they take 35 more and are dizzy for 1 s (slowed and unable to shoot). The slap also knocks enemy bullets in front of you back at whoever fired them. A raised shield blocks. Cooldown 8 s.",
		"mods": [{"stat": "slap", "add": 1}]},
	# Gancho (2026-10-06, ideia do usuário: fundiu as minhas propostas de gancho e de
	# agarrar e arremessar; números meus, aprovados).
	"gancho": {"name": "Hook", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 12.0,
		"desc": "Q: throws a hook (up to 28 m) that pulls the enemy right in front of you and holds them for up to 3 s: you move at 70% and can't shoot; they can't act. They serve as a human shield (in Teams, their own team hits them too). Click or Q throws them where you aim: hitting a wall deals 22 (growing with your bullet Damage); hitting another enemy deals the same to both and leaves both dizzy. Taking 30 damage while holding lets go. A raised shield blocks the hook. Cooldown 12 s (4 s if you miss).",
		"mods": [{"stat": "hook", "add": 1}]},
	# Domínio do Rei (2026-10-11, ideia e nome do usuário, inspirada na ultimate do
	# Mordekaiser; números meus, aprovados; começar só com o bônus e voltar para onde saíram
	# foram escolhas dele). Lógica em Player._realm_*, sala em KingRealm.
	"dominio_do_rei": {"name": "King's Domain", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 35.0,
		"desc": "Enemies in range (up to 30 m, in sight) get a crown with \"Q\" on your screen; the one in your crosshair lights up. Q on them: casts a shadow chain that chases them (24 m/s). They only escape by raising the shield when it arrives or by hiding behind a wall: then the cooldown is 12 s. With no one in your crosshair, Q isn't spent. Caught: you are both pulled for 0.8 s and taken to a closed room for 10 s, where no one else can enter. Inside, every second you gain +4% damage and they lose 4%, up to +30% and -30%. Whoever wins returns right away; if you win, you keep the bonus for 6 more s. When time runs out, you both return to where you were, and those left on the map see where and when you reappear. Cooldown 35 s.",
		"mods": [{"stat": "realm", "add": 1}]},
	# Mecha (2026-10-12, ideia do usuário: construir e entrar, seguir atirando com defesa;
	# construção peça por peça, míssil no E, explosão na saída que cresce com a blindagem
	# perdida e a Perfurante ignorando a blindagem foram dele; números meus, aprovados).
	# Lógica em Player._mech_*.
	"mecha": {"name": "Mecha", "cat": "Corpo", "rarity": "mitico", "master": true, "cooldown": 24.0,
		"desc": "Q: builds a mecha around you, piece by piece, in 1.2 s (meanwhile you move slowly and can't shoot). Inside, for 8 s: plating of 60 + 60% of your max health that takes damage before anything else, immune to pushes and pulls, you keep shooting with your weapon, and E launches a missile (1 every 2.5 s; 20 + 40% of bullet damage, up to 45, in 3.5 m) instead of the shield. Bigger, 25% slower, no extra jumps. Hold jump to charge a leap (1 s) toward where you look, with strong air control; hitting a wall in the leap, the mecha grabs it for 1.5 s and then slides down, and jump leaps again from it. Instead of the dash, hold dash to fire a back thruster that pushes you toward where you look (in the air, without falling) while its bar lasts: 1.5 s, refilling in 3 s. Q again exits early. On exit, it explodes (5 m): 20 damage with full plating, up to 50 with it depleted. Piercer ignores the plating. Cooldown 24 s, counted after you exit.",
		"mods": [{"stat": "mech", "add": 1}]},
	"ultimo_suspiro": {"name": "Last Breath", "cat": "Corpo", "rarity": "mitico", "master": true,
		"desc": "Once per round, the killing blow leaves you at 1 health and unable to die for 3 s, moving 40% faster; everyone sees the countdown above your name. Take someone down in that time to come back with half your health.",
		"mods": [{"stat": "last_stand", "add": 1}]},
	# Camuflagem virou mestra em 2026-10-06 (pedido do usuário; números meus, aprovados):
	# some mais rápido, anda agachada sem aparecer e, ao aparecer, ganha a Emboscada.
	"camuflagem": {"name": "Camouflage", "cat": "Corpo", "rarity": "mitico", "master": true,
		"desc": "Stand still for 0.6 s and you vanish. While invisible, you can crouch-walk without showing up; shooting, running, jumping, dash, shield or taking damage reveal you. After 1 s invisible, reappearing grants Ambush: 3 s with +40% shot damage and +20% speed (at most every 6 s), and the first shot goes through walls. The shot that reveals you already counts. After 8 s in a row invisible, the camouflage fails: you flicker visible for 0.4 s every 2 s until you reappear.",
		"mods": [{"stat": "camo", "add": 1}]},
	# Bota Foguete (2026-10-06, desenho do usuário a partir da minha proposta; números meus):
	# passiva. Bônus por estar no ar e um jato curto como a bota foguete do Terraria.
	"bota_foguete": {"name": "Rocket Boots", "cat": "Movimento", "rarity": "mitico", "master": true,
		"desc": "Each second in the air gives +15% shot damage, up to +50%; it lasts 1 s after you land (jump again in that time and it keeps growing). With no air jumps left, press and hold jump for a short jet (1 s) that brakes your fall and pushes you up. The jet recharges when you touch the ground.",
		"mods": [{"stat": "rocket_boots", "add": 1}]},
	# Formiga (2026-10-06, ideia do usuário; números meus, aprovados; cancelar no Q e o
	# impacto ao crescer foram sugestões minhas aceitas).
	# Plataformas Suspensas (2026-10-06, ideia e nome do usuário; números meus, aprovados;
	# todos pisam, escolha dele). Passiva com propulsor desde 2026-10-07 (pedido dele; 3
	# plataformas e 14 m/s meus, aprovados; a cor por jogador foi ideia dele; recarga de 6 s
	# dele e prazo de 2 s meu).
	"plataformas_suspensas": {"name": "Sky Platforms", "cat": "Movimento", "rarity": "mitico", "master": true,
		"desc": "With no air jumps left, jumping creates a platform under your feet. You can make up to 3 in a row, with 2 s to use each next one; using the 3rd, missing the deadline or touching the ground starts an 8 s cooldown. The platform is a launcher: it launches upward whoever steps on it, once per player (green: still launches you; purple: already launched you). Lasts 5 s; any player can step on it, and bullets pass through.",
		"mods": [{"stat": "platforms", "add": 1}]},
	"formiga": {"name": "Ant", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 16.0,
		"desc": "Q: for 6 s you shrink to 40% of your size (harder to hit) and move 60% faster. Q again returns early. When you return to size, an impact pushes anyone within 4 m and deals 15 damage. Cooldown 16 s.",
		"mods": [{"stat": "shrink", "add": 1}]},
	# Caos (2026-10-06, ideia do usuário; ritmo meu, aprovado; grupo Balas, escolha minha
	# com o voto dele de manter os 5 grupos): sorteia outra mestra. Entram todas as de
	# MASTERS, inclusive as futuras, menos ela mesma. Lógica em Player._chaos_*.
	"caos": {"name": "Chaos", "cat": "Balas", "rarity": "mitico", "master": true,
		"desc": "You get a random master card. Active: use it once; 8 s after its effect ends, another one comes. Passive: lasts 15 s and swaps. Never repeats the previous one; each round starts with a new draw.",
		"mods": [{"stat": "chaos", "add": 1}]},
	# Cartas Instáveis (2026-10-11, ideia e nome do usuário; números meus, aprovados para
	# começar fracos; cartas do baralho e grupo Balas, junto do Caos, escolhas dele).
	# Lógica em Player._unstable_*.
	# Clone (2026-10-12, a 2a das prometidas nas notas da v0.8.0; caminho "Clone Sombra" entre
	# 3 propostas minhas, com 8 s e o clone andando devagar, pedidos do usuário; grupo Balas,
	# escolha minha: o efeito é o tiro em dobro). Lógica em ShadowClone e Player._clone_*.
	"clone": {"name": "Clone", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 18.0,
		"desc": "Q: leaves a clone of you that walks slowly toward where you were looking, for 8 s. To others it looks just like you (name and health). Each of your shots also comes out of it, toward your crosshair, with half the damage: crossfire. Q again: you swap places with it, and it vanishes. Enemy bullets destroy it after 40 damage. Cooldown 18 s.",
		"mods": [{"stat": "clone", "add": 1}]},
	"cartas_instaveis": {"name": "Unstable Cards", "cat": "Balas", "rarity": "mitico", "master": true, "cooldown": 22.0,
		"desc": "Q: gain 3 random common cards from your deck for 8 s (respecting the per-match limit; Phoenix is excluded). Health follows max health as a percentage. The cards appear above your name for others. Cooldown 22 s.",
		"mods": [{"stat": "unstable", "add": 1}]},
	# Arpéu Ventoso (2026-10-12, ideia do usuário: os ganchos de Shingeki no Kyojin com cara
	# de desentupidor; nome dele; números meus, aprovados: 22 m/s, 8 s por carga, atirar a
	# qualquer momento). Lógica em Player._grapple_*.
	"arpeu_ventoso": {"name": "Plunger Grapple", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 6.0,
		"charges": 3,
		"desc": "Hold Q: fires a suction cup (up to 35 m). Stuck to the scenery: you swing from it, with half gravity, without losing momentum, and the movement keys steer the swing; the rope keeps shortening. Release Q to fly off with the momentum (+15% and one air jump); Space also releases, with an upward boost. Leaving a swing gives Momentum: +30% Damage for 2 s. Reaching the wall while still holding, you hang for up to 2 s (jump leaps off it). Stuck to an enemy: you are pulled to them and land a 20-damage kick (growing with your bullet Damage) that pushes them (a raised shield blocks). Dash cancels it. Missed: the charge returns in 1 s. Stores 3 uses: each comes back in 6 s, one at a time.",
		"mods": [{"stat": "grapple", "add": 1}]},
	"corrente": {"name": "Updraft", "cat": "Movimento", "rarity": "mitico", "master": true, "cooldown": 9.0,
		"charges": 2,
		"desc": "Q: straight upward boost of about 8 m. Also works in the air. Stores 2 uses: each comes back in 9 s, one at a time.",
		"mods": [{"stat": "updraft", "add": 1}]},
}

## Glossário (2026-10-12, pedido do usuário: "bala mais rápida", "atira mais rápido" e
## "recarga" confundiam). As descrições das cartas usam só estes termos; o editor mostra a
## lista no botão "?".
const GLOSSARY := [
	["Damage", "How much health each bullet takes away (25 on the base weapon). Every Damage bonus adds into a single one, including momentary ones (Fury, Executioner, Cold Blood...): +45% and +30% = +75%. A card that multiplies damage says so, like Lucky's critical and Last Bullet."],
	["Fire rate", "How many shots per second. Fire rate +40% = 40% more shots in the same time; Fire rate x3 = triple."],
	["Bullet speed", "How fast the bullet flies to the target. Faster arrives sooner and is easier to land from far away."],
	["Bullet drop", "How much the bullet falls during flight. -50% falls half as much; x2 falls twice as much."],
	["Range", "How far the bullet goes: it vanishes once it is farther than this, in a straight line, from where the shot came out (bounces count while they stay inside; the Boomerang bullet turns 3 m before the end and comes back). Without Range losses on your cards there is no limit. Losses multiply and stop at 12 m; gains apply to what is left."],
	["Bullet size", "The size of the bullet: bigger is easier to land. It also grows a little with damage. Losses stop at 60% of normal."],
	["Magazine", "How many shots you fire before you need to reload."],
	["Reload", "The time to fill the magazine again (reload key or empty magazine)."],
	["Cooldown", "The wait before you can use the shield, the dash or the master card again."],
	["Movement speed", "How fast you walk and run."],
	["Health", "Max health. Your body grows a little with it."],
	["Affliction", "An effect that stays on the enemy for a while: Poison, Burn, Freeze, Slow, Blind, Dizzy and Shield locked. Tenacity shortens all of them; Armored reduces none."],
	["Poison", "Slow, long damage: 5 s. Stacks: each hit adds a new poison. Of the bullet damage above 40, it yields only 2/3."],
	["Burn", "Fast, short damage: a lot per second, for a short time. Doesn't stack: a new hit refreshes the time and the strongest one counts. Of the bullet damage above 40, it yields only 70%."],
	["Freeze", "Frost stacks, up to 5: each one makes the target's fire rate and reload 6% slower. At the 5th, they freeze for 0.5 s (can't act, but take damage) and the stacks reset; then they can't freeze again for 3 s. After 2 s without a new stack, they lose one per second."],
	["Breaking the ice", "The first hit on someone frozen deals +20 and ends the ice. Poison and burn don't break it."],
	["Once-per-hit effects", "Frost stacks, Ember heat-up and Pressure apply at most once every 0.25 s from each shooter on each target: several bullets from the same shot (shotgun) count once."],
	["Slow", "The target moves slower. Doesn't stack: the strongest one counts."],
	["How cards add up", "Upgrades to the same attribute add up (+20% and +20% = +40%). Downgrades multiply and have a limit: in general, no attribute drops below 35% of normal."],
]

## Mestras guardadas para voltar no futuro (fora do jogo: não entram em CARDS). O código
## continua em bullet.gd ("guided"). Piloto saiu em 2026-10-04: na prática ficou confuso.
const SHELVED_MASTERS := {
	"piloto": {"name": "Piloto", "cat": "Balas", "master": true,
		"desc": "Suas balas seguem a sua mira, sem queda: depois de atirar, mova o mouse para guiá-las em curva.",
		"mods": [{"stat": "guided", "add": 1}]},
}
## Mestras desligadas (2026-10-23, limpeza das mestras pedida pelo usuário): continuam em
## MASTERS e no código, mas não aparecem no editor, nos pacotes, no Caos nem nos bots, e
## baralho salvo com uma delas passa para MASTER_DEFAULT. `--mestra=<id>` ainda as liga
## num teste. Motivo de cada uma em .claude/mestras_desligadas.md. Religar: tirar daqui.
const MASTERS_OFF := ["chuva_de_meteoros", "formiga"]
## Baralho salvo com uma mestra que saiu passa para esta (ver GameState.load_decks).
const MASTER_REPLACED := {"piloto": "perfurante"}

## Arquétipos: etiquetas para achar cartas que combinam (filtro do editor de baralho, ideia
## do usuário inspirada no Marvel Snap). Uma carta pode estar em vários; misturar é livre.
## Toda carta comum precisa estar em pelo menos um (o autoteste confere).
const ARCHETYPES := {
	"Ricochete": {"name": "Ricochet", "desc": "Bullets that bounce off walls or come back.",
		"cards": ["ricochete", "bola_borracha", "quique_certeiro", "tabelinha", "fragmentacao", "bumerangue"]},
	"Explosão": {"name": "Explosion", "desc": "Area damage.",
		"cards": ["explosiva", "morteiro", "detonacao", "fragmentacao", "pulo_foguete", "chuva_de_bombas", "meteoro",
			"mina", "buraco_negro", "dinamite", "carga_concentrada"]},
	"Nuke": {"name": "Nuke", "desc": "Few huge bullets, each with lots of damage.",
		"cards": ["calibre_pesado", "combinar", "bala_gigante", "bala_de_canhao", "canhao_de_vidro", "fragil",
			"ultima_bala", "sortudo", "nucleo_de_aco", "bola_de_neve", "tabelinha", "preguicosa", "executor", "furia", "vinganca"]},
	"Chuva de balas": {"name": "Bullet Storm", "desc": "Lots of bullets, big magazine, high fire rate and fast reload.",
		"cards": ["gatilho_leve", "pente_estendido", "maos_rapidas", "cano_duplo", "escopeta", "rajada",
			"transbordar", "imprudente", "metralhadora", "saque_rapido", "recarga_tatica", "recarga_perfeita",
			"reciclagem", "cinto_municao", "cartucheira"]},
	"Atirador": {"name": "Marksman", "desc": "Hitting from far away and behind walls.",
		"cards": ["polvora_extra", "olho_de_aguia", "fantasma", "teleguiada", "sortudo", "preguicosa", "radar",
			"sangue_frio", "nucleo_de_aco"]},
	"Controle": {"name": "Control", "desc": "Hinder the enemy: slowed, blinded, poisoned, pushed.",
		"cards": ["veneno", "congelante", "bala_de_gelo", "flash", "atordoante", "propulsao", "troca_troca", "onda_de_choque",
			"geada", "nuvem_toxica", "buraco_negro", "chamas"]},
	# Aflições (2026-10-14, pedido do usuário: sub-builds separadas desde já). Veneno e
	# Queimadura: cartas que aplicam ou melhoram só aquele efeito. Aflição: cartas que valem
	# para todas (efeitos que ficam no inimigo por um tempo; ver GLOSSARY).
	"Veneno": {"name": "Poison", "desc": "Apply and spread Poison, which stacks with every hit.",
		"cards": ["veneno", "nuvem_toxica", "contagio"]},
	"Queimadura": {"name": "Burn", "desc": "Apply Burn, which deals a lot per second and doesn't stack.",
		"cards": ["chamas", "incendiaria", "brasa", "combustivel", "combustao_lenta", "choque_termico"]},
	# Congelamento (2026-10-15, ideia do usuário): camadas que congelam e o gelo que quebra.
	"Congelamento": {"name": "Freeze", "desc": "Apply frost stacks until the target freezes, then break the ice.",
		"cards": ["bala_de_gelo", "hipotermia", "estilhaco", "choque_termico", "congelante", "geada"]},
	"Aflição": {"name": "Affliction", "desc": "Improve every effect that stays on the enemy: last longer, mark, burst, prevent healing.",
		"cards": ["marca", "persistencia", "acido", "corrosao", "estouro", "reacao_em_cadeia", "dose_extra", "raspao"]},
	"Espelho": {"name": "Mirror", "desc": "Reflect enemy bullets with the shield.",
		"cards": ["escudo_firme", "reflexos", "espelho_cortante", "adrenalina", "espelho_duplo",
			"espelho_perseguidor", "espelho_gigante", "escudo_duplo", "eco", "escudo_de_papel"]},
	"Escudo de ataque": {"name": "Offensive Shield", "desc": "The shield as a weapon, up close.",
		"cards": ["pancada", "onda_de_choque", "investida", "nova", "chuva_de_bombas", "teleporte",
			"couraca", "fortaleza", "restauracao", "recarga_tatica", "ultima_defesa",
			"serra", "chamas", "geada", "mina", "passo_ligeiro", "escudo_de_papel"]},
	"Corpo a corpo": {"name": "Close Quarters", "desc": "Get right up to the enemy and hit.",
		"cards": ["escopeta", "atropelar", "cacador", "sede_de_sangue", "meteoro", "troca_troca",
			"pancada", "investida", "cacada", "serra", "pisao", "bote", "cano_serrado", "arrancada",
			"pressao", "bumerangue", "choke", "silenciador"]},
	"Tanque": {"name": "Tank", "desc": "Health, healing and armor.",
		"cards": ["vigor", "tanque", "defensor", "sanguessuga", "regeneracao", "fenix", "gigantao",
			"fortaleza", "couraca", "restauracao", "eco", "blindado", "peso_pesado", "segunda_pele", "casca_dura",
			"couro_grosso", "banquete", "tenacidade", "metabolismo"]},
	"Aéreo": {"name": "Aerial", "desc": "Stay up high: jumps, walls, gliding.",
		"cards": ["pulo_duplo", "impulso", "escalador", "pena", "molas", "planador", "embalo", "meteoro", "pulo_foguete",
			"pisao", "parkour", "velocidade_letal", "vulto", "recarga_embalo", "leveza"]},
	"Dash": {"name": "Dash", "desc": "Dash more often, farther and with effects.",
		"cards": ["impulso", "folego", "dash_longo", "deslize_turbo", "esquiva", "atropelar", "saque_rapido",
			"cacada", "botas_leves", "pisao", "dash_duplo", "parkour", "velocidade_letal", "vulto", "bote"]},
	"Tudo ou nada": {"name": "All or Nothing", "desc": "Trade health for power.",
		"cards": ["fragil", "canhao_de_vidro", "imprudente", "nanico", "furia", "fenix", "molas",
			"escudo_de_papel", "instinto", "leveza", "mosquito"]},
	# Mosquito (2026-10-18, build dos amigos do usuário): pequeno, veneno, cura e movimento.
	"Mosquito": {"name": "Mosquito", "desc": "Small body and low health: fire rate, poison and healing to make up for it.",
		"cards": ["mosquito", "nanico", "fragil", "leveza", "sanguessuga", "metabolismo", "veneno",
			"pulo_duplo", "planador"]},
}

## O corpo cresce com a vida máxima, de leve (como no Furor): 1,8x de vida = 19% maior,
## metade da vida = 19% menor. Soma-se ao tamanho das cartas (Nanico, Gigantão).
const HEALTH_SIZE_EXP := 0.3

## Todas as cartas: as comuns abaixo e as mestras (MASTERS, juntadas em _init).
var CARDS := {
	# Arma
	"calibre_pesado": {"name": "Heavy Caliber", "cat": "Arma", "rarity": "comum",
		"desc": "Damage +20%. Fire rate -10%. Reload +0.2 s.",
		"mods": [{"stat": "damage", "mul": 1.2}, {"stat": "fire_interval", "mul": 1.0 / 0.9}, {"stat": "reload_time", "add": 0.2}]},
	"gatilho_leve": {"name": "Hair Trigger", "cat": "Arma", "rarity": "comum",
		"desc": "Fire rate +40%. Damage -5%.",
		"mods": [{"stat": "fire_interval", "mul": 1.0 / 1.4}, {"stat": "damage", "mul": 0.95}]},
	"pente_estendido": {"name": "Extended Mag", "cat": "Arma", "rarity": "comum",
		"desc": "Magazine +4. Reload time +15%.",
		"mods": [{"stat": "mag_size", "add": 4}, {"stat": "reload_time", "mul": 1.15}]},
	"maos_rapidas": {"name": "Quick Hands", "cat": "Arma", "rarity": "comum", "max": 3,
		"desc": "Reload -0.25 s.",
		"mods": [{"stat": "reload_time", "add": -0.25}]},
	"polvora_extra": {"name": "Extra Powder", "cat": "Arma", "rarity": "comum",
		"desc": "Bullet speed +30%. Bullet size -10%. Each shot pushes you back a little; more copies push harder each time.",
		"mods": [{"stat": "bullet_speed", "mul": 1.3}, {"stat": "bullet_radius", "mul": 0.9}, {"stat": "recoil", "add": 1}]},
	"cano_duplo": {"name": "Double Barrel", "cat": "Arma", "rarity": "raro",
		"desc": "+1 bullet per shot. Magazine +1. Damage -20%.",
		"mods": [{"stat": "bullet_count", "add": 1}, {"stat": "mag_size", "add": 1}, {"stat": "damage", "mul": 0.8}]},
	# Escopeta refeita em 2026-10-13 (pedido do usuário, para a build de spam: cada bala do leque
	# gasta pente, como a Rajada; 4 balas, pente +4, dano -40%; leque de 5 graus, porque com 4
	# balas não há bala no meio e a 7 graus as duas do centro passavam dos lados a mais de 8 m).
	# Cano Serrado (2026-10-15, build de escopeta pedida pelo usuário; números meus aprovados).
	# Bullet.CLOSE_*: a distância vai de onde o tiro saiu até onde acertou.
	"cano_serrado": {"name": "Sawed-Off", "cat": "Arma", "rarity": "epico", "max": 1,
		"desc": "Your bullets deal +60% damage up to 5 m; the bonus drops to zero at 12 m, and from 15 m on the damage is -30%. Up close, bullets hit even when passing slightly beside the enemy. Spread 50% wider. Range -70%.",
		"mods": [{"stat": "close_range", "add": 1}, {"stat": "spread", "mul": 1.5}, {"stat": "bullet_range", "mul": 0.3}]},
	"escopeta": {"name": "Shotgun", "cat": "Arma", "rarity": "raro", "max": 1,
		"desc": "+3 bullets per shot (4 in total), in a spread, and each bullet uses 1 from the magazine (with the magazine almost empty, only the ones left come out). Magazine +4. Damage -25%.",
		"mods": [{"stat": "bullet_count", "add": 3}, {"stat": "shot_ammo", "add": 3}, {"stat": "spread", "add": 1.0},
			{"stat": "mag_size", "add": 4}, {"stat": "damage", "mul": 0.75}]},
	"rajada": {"name": "Burst", "cat": "Arma", "rarity": "raro", "max": 1,
		"desc": "Each click fires a burst of 3 shots in a row, each using 1 bullet from the magazine. Damage -10%.",
		"mods": [{"stat": "burst", "add": 2}, {"stat": "damage", "mul": 0.9}]},
	"combinar": {"name": "Merge", "cat": "Arma", "rarity": "raro",
		"desc": "Damage +40%. Magazine -2.",
		"mods": [{"stat": "damage", "mul": 1.4}, {"stat": "mag_size", "add": -2}]},
	"transbordar": {"name": "Overflow", "cat": "Arma", "rarity": "raro",
		"desc": "Magazine +9. Damage -30%. Reload +0.8 s.",
		"mods": [{"stat": "mag_size", "add": 9}, {"stat": "damage", "mul": 0.7}, {"stat": "reload_time", "add": 0.8}]},
	"bala_gigante": {"name": "Giant Bullet", "cat": "Arma", "rarity": "raro",
		"desc": "Bullet size x2. Damage +20%. Range -30%, bullet drop +20% and bullet speed -10%.",
		"mods": [{"stat": "bullet_radius", "mul": 2.0}, {"stat": "damage", "mul": 1.2}, {"stat": "bullet_range", "mul": 0.7},
			{"stat": "bullet_gravity", "mul": 1.2}, {"stat": "bullet_speed", "mul": 0.9}]},
	"bala_de_canhao": {"name": "Cannonball", "cat": "Arma", "rarity": "raro",
		"desc": "Damage +40%. Bullet size x2. Range -40%. Fire rate -20%. Reload +0.3 s.",
		"mods": [{"stat": "damage", "mul": 1.4}, {"stat": "bullet_radius", "mul": 2.0}, {"stat": "bullet_range", "mul": 0.6},
			{"stat": "fire_interval", "mul": 1.0 / 0.8}, {"stat": "reload_time", "add": 0.3}]},
	"imprudente": {"name": "Reckless", "cat": "Arma", "rarity": "epico",
		"desc": "Fire rate +70%. Reload time +50%. Health -20%.",
		"mods": [{"stat": "fire_interval", "mul": 1.0 / 1.7}, {"stat": "reload_time", "mul": 1.5}, {"stat": "max_health", "mul": 0.8}]},

	"metralhadora": {"name": "Machine Gun", "cat": "Arma", "rarity": "epico", "max": 1,
		"desc": "Automatic: hold to fire. Fire rate x3. Magazine +10. Damage -40%. Reload +0.3 s.",
		"mods": [{"stat": "auto_fire", "add": 1}, {"stat": "fire_interval", "mul": 0.33}, {"stat": "mag_size", "add": 10},
			{"stat": "damage", "mul": 0.6}, {"stat": "reload_time", "add": 0.3}]},
	"canhao_de_vidro": {"name": "Glass Cannon", "cat": "Arma", "rarity": "epico",
		"desc": "Damage +75%. Health -50%.",
		"mods": [{"stat": "damage", "mul": 1.75}, {"stat": "max_health", "mul": 0.5}]},
	"olho_de_aguia": {"name": "Eagle Eye", "cat": "Arma", "rarity": "epico",
		"desc": "Bullet speed +50% and bullet drop -50%. Damage +25%. Bullet size -15%. Magazine -1. Fire rate -30%. Reload +0.2 s.",
		"mods": [{"stat": "bullet_speed", "mul": 1.5}, {"stat": "bullet_gravity", "mul": 0.5},
			{"stat": "damage", "mul": 1.25}, {"stat": "fire_interval", "mul": 1.0 / 0.7}, {"stat": "mag_size", "add": -1},
			{"stat": "reload_time", "add": 0.2}, {"stat": "bullet_radius", "mul": 0.85}]},
	"morteiro": {"name": "Mortar", "cat": "Arma", "rarity": "epico",
		"desc": "Bullets fly in a high arc (bullet drop x3.5) and explode (4 m radius). Damage +30%. Bullet speed -40%.",
		"mods": [{"stat": "bullet_gravity", "mul": 3.5}, {"stat": "bullet_speed", "mul": 0.6},
			{"stat": "explosion", "add": 4.0}, {"stat": "damage", "mul": 1.3}]},
	# Recarga Perfeita (2026-10-07, proposta minha aprovada; como a recarga ativa do Gears of War).
	"recarga_perfeita": {"name": "Perfect Reload", "cat": "Arma", "rarity": "epico", "max": 1,
		"desc": "While you reload, a golden band appears on the crosshair ring: press reload again inside it to finish instantly, and the next magazine deals +15% damage. Outside the band, reloading is delayed by 0.4 s. One attempt at a time.",
		"mods": [{"stat": "perfect_reload", "add": 1}]},
	# Última Bala e Sortudo multiplicam (2026-10-17, pedido do usuário para a sniper; ver
	# Player.LAST_SHOT_MULT e CRIT_MULT). Antes somavam +150% (soma única, 2026-10-14).
	"ultima_bala": {"name": "Last Bullet", "cat": "Arma", "rarity": "raro", "max": 3,
		"desc": "The last bullet in the magazine deals x2 damage (multiplies). More copies: x2.5 and x3.",
		"mods": [{"stat": "last_shot", "add": 1}]},
	"sortudo": {"name": "Lucky", "cat": "Arma", "rarity": "epico",
		"desc": "Each bullet has a 20% chance to be critical: x2 damage (multiplies).",
		"mods": [{"stat": "crit_chance", "add": 0.2}]},
	# Munição (2026-10-11, pedido do usuário depois da Rajada gastar pente; números meus,
	# aprovados). Reciclagem: Player.bullet_refund (a bala leva o número do clique).
	"reciclagem": {"name": "Recycling", "cat": "Arma", "rarity": "raro", "max": 3,
		"desc": "Each bullet that hits an enemy returns 1 bullet to the magazine per copy: 1, 2 or 3.",
		"mods": [{"stat": "recycle", "add": 1}]},
	"cinto_municao": {"name": "Ammo Belt", "cat": "Arma", "rarity": "comum",
		"desc": "Magazine +50%. Reload +0.4 s.",
		"mods": [{"stat": "mag_size", "mul": 1.5}, {"stat": "reload_time", "add": 0.4}]},
	# Cartucheira (2026-10-13, ideia do usuário para a build de spam: chance de a bala não sair
	# do pente; custo só na velocidade da bala, para pesar no sniper e quase nada de perto;
	# 10% por cópia até 3, escolhas dele; Player._shoot sorteia por bala do pente). Desde
	# 2026-10-15 o custo é Alcance -15% (era velocidade -10%), que faz isso melhor.
	"cartucheira": {"name": "Bandolier", "cat": "Arma", "rarity": "comum", "max": 3,
		"desc": "Each bullet has a 10% chance not to come out of the magazine. Range -10%.",
		"mods": [{"stat": "free_ammo", "add": 0.1}, {"stat": "bullet_range", "mul": 0.9}]},
	# Alcance (2026-10-15, pedido do usuário para a build de escopeta: a bala de perto saía
	# lenta e caindo). As cartas de bala pesada cortam o Alcance no lugar da velocidade; quem
	# não tem perda de Alcance não tem limite nenhum. Choke e Silenciador devolvem parte, sobre
	# o que sobrou (números meus, para ele conferir); sem perda de Alcance, o ganho não muda nada.
	"choke": {"name": "Choke", "cat": "Arma", "rarity": "comum", "max": 3,
		"desc": "Range +25%. Spread 20% tighter.",
		"mods": [{"stat": "bullet_range", "mul": 1.25}, {"stat": "spread", "mul": 0.8}]},
	"silenciador": {"name": "Suppressor", "cat": "Arma", "rarity": "raro", "max": 1,
		"desc": "Range +60%. Bullet speed +20%. Bullet size -15%.",
		"mods": [{"stat": "bullet_range", "mul": 1.6}, {"stat": "bullet_speed", "mul": 1.2},
			{"stat": "bullet_radius", "mul": 0.85}]},
	# Núcleo de Aço (2026-10-17, ideia do usuário para a sniper recuperar tamanho sem perder
	# Alcance; números meus). Fura só o colete: furar o escudo do E fica para a Perfurante.
	"nucleo_de_aco": {"name": "Steel Core", "cat": "Arma", "rarity": "raro", "max": 3,
		"desc": "20% of your hits' damage that would go to the enemy's armor goes straight to health (40% and 60% with 2 and 3 copies). Bullet size +15%. Damage +10%. Reload +0.2 s.",
		"mods": [{"stat": "armor_pierce", "add": 0.2}, {"stat": "bullet_radius", "mul": 1.15},
			{"stat": "damage", "mul": 1.1}, {"stat": "reload_time", "add": 0.2}]},
	# Sangue Frio: o oposto da build de movimento (Player.still_aim).
	"sangue_frio": {"name": "Cold Blood", "cat": "Arma", "rarity": "raro", "max": 2,
		"desc": "Standing still or crouching on the ground: damage +25% and bullet speed +30%. With 2 copies, +50% and +60%.",
		"mods": [{"stat": "still_aim", "add": 1}]},

	# Balas
	"ricochete": {"name": "Ricochet", "cat": "Balas", "rarity": "comum",
		"desc": "Bullets bounce off walls one more time.",
		"mods": [{"stat": "bounces", "add": 1}]},
	# 2026-10-10, pedido do usuário depois que a Tabelinha deixou de dar quiques: +2 numa
	# carta só, com -20% de dano (ele quis 20 em vez dos 15 propostos, para ser conservador).
	"bola_borracha": {"name": "Rubber Ball", "cat": "Balas", "rarity": "raro",
		"desc": "Bullets bounce off walls two more times. Damage -20%.",
		"mods": [{"stat": "bounces", "add": 2}, {"stat": "damage", "mul": 0.8}]},
	"teleguiada": {"name": "Homing", "cat": "Balas", "rarity": "lendario",
		"desc": "Some bullets (35%) that pass near an enemy curve toward them and turn green. More copies: more bullets seek (never all, at most 70%) and from a bit farther away. Damage -20%. Reload +0.25 s.",
		"mods": [{"stat": "homing", "add": 1.0}, {"stat": "damage", "mul": 0.8}, {"stat": "reload_time", "add": 0.25}]},
	"fantasma": {"name": "Ghost Bullet", "cat": "Balas", "rarity": "lendario", "max": 2,
		"desc": "Each bullet goes through the first wall it hits (with 2 copies, the first two). Damage -15%.",
		"mods": [{"stat": "ghost", "add": 1}, {"stat": "damage", "mul": 0.85}]},
	"explosiva": {"name": "Explosive", "cat": "Balas", "rarity": "epico",
		"desc": "Bullets explode on impact (3 m radius). Damage -15%.",
		"mods": [{"stat": "explosion", "add": 3.0}, {"stat": "damage", "mul": 0.85}]},
	"veneno": {"name": "Poison", "cat": "Balas", "rarity": "raro",
		"desc": "Hitting applies Poison: an extra 60% of the damage (only 40% of the part above 40), dealt over 5 s. Magazine -1.",
		"mods": [{"stat": "poison", "add": 0.6}, {"stat": "mag_size", "add": -1}]},
	# Bala Incendiária (2026-10-14, pedido do usuário: Queimadura pelo tiro, rápida e curta
	# como no The Bazaar; números meus aprovados).
	"incendiaria": {"name": "Incendiary Bullet", "cat": "Balas", "rarity": "raro", "max": 3,
		"desc": "Hitting applies Burn: 50% of the bullet's damage per second (only 35% of the part above 40), for 1 s. More copies: +50% per second. Fire rate -10%.",
		"mods": [{"stat": "burn", "add": 0.5}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	# Brasa e Combustível (2026-10-14, propostas minhas aprovadas; números para testar).
	"brasa": {"name": "Ember", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Each hit on someone already burning from your fire increases that Burn by +25%, up to double. It goes back to normal when the burn ends. Reload +0.2 s.",
		"mods": [{"stat": "ember", "add": 1}, {"stat": "reload_time", "add": 0.2}]},
	"combustivel": {"name": "Fuel", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Your Burn deals 40% more to targets that also have another affliction: Poison, Freeze, Slow, Blind, Dizzy or Shield locked. Damage -5%.",
		"mods": [{"stat": "fuel", "add": 1}, {"stat": "damage", "mul": 0.95}]},
	# Combustão Lenta (2026-10-14, pedido do usuário: mais tempo de fogo sem desbalancear):
	# Player.SLOW_BURN_*; teto de 4 s na Queimadura (BURN_MAX_TIME).
	"combustao_lenta": {"name": "Slow Burn", "cat": "Balas", "rarity": "raro", "max": 2,
		"desc": "Your Burn lasts +0.5 s, but deals 10% less per second. Burn lasts at most 4 s.",
		"mods": [{"stat": "slow_burn", "add": 1}]},
	# Bala Letárgica: era "Bala Gelada" até 2026-10-15 (o nome confundia com o Congelamento;
	# id mantido para os baralhos salvos).
	"congelante": {"name": "Lethargic Bullet", "cat": "Balas", "rarity": "raro",
		"desc": "Hitting applies Slow: the target moves 35% slower for 1.5 s.",
		"mods": [{"stat": "slow", "add": 0.35}]},
	# Congelamento (2026-10-15, ideia do usuário; números meus aprovados; 1 camada por tiro e
	# o Choque Térmico como congelar + queimar foram pedidos dele). Código: Player.FROST_* etc.
	"bala_de_gelo": {"name": "Ice Bullet", "cat": "Balas", "rarity": "raro", "max": 2,
		"desc": "Hitting applies 1 frost stack (2 with 2 copies). Damage -10%.",
		"mods": [{"stat": "frost", "add": 1}, {"stat": "damage", "mul": 0.9}]},
	"hipotermia": {"name": "Hypothermia", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Hitting someone with Slow applies +1 frost stack. Those you freeze stay frozen for 0.8 s instead of 0.5. Reload +0.2 s.",
		"mods": [{"stat": "hypothermia", "add": 1}, {"stat": "reload_time", "add": 0.2}]},
	"estilhaco": {"name": "Shatter", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Breaking someone's ice also hits enemies within 4 m of them: half the blow and 2 frost stacks. Fire rate -10%.",
		"mods": [{"stat": "shatter", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	"choque_termico": {"name": "Thermal Shock", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "When the ice of someone you froze ends (broken or melted), they take +10 damage and a Burn of 10 per second for 1.5 s. Damage -5%.",
		"mods": [{"stat": "thermal", "add": 1}, {"stat": "damage", "mul": 0.95}]},
	"propulsao": {"name": "Knockback", "cat": "Balas", "rarity": "comum",
		"desc": "Bullets push whoever gets hit. Reload +0.25 s.",
		"mods": [{"stat": "knockback", "add": 12.0}, {"stat": "reload_time", "add": 0.25}]},
	"quique_certeiro": {"name": "Smart Bounce", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "+1 bounce. On bouncing, the bullet may turn a little toward the enemy and start seeking them like Homing (35% chance). Copies of Homing make this stronger. Damage -20%.",
		"mods": [{"stat": "target_bounce", "add": 1}, {"stat": "bounces", "add": 1}, {"stat": "damage", "mul": 0.8}]},
	"atordoante": {"name": "Stunner", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Hitting an enemy locks their shield for 1.5 s. After that, they can't be stunned again for 3 s. Fire rate -20%.",
		"mods": [{"stat": "shield_break", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.8}]},
	"sanguessuga": {"name": "Leech", "cat": "Balas", "rarity": "epico",
		"desc": "Recover 25% of the damage you deal. Damage -10%.",
		"mods": [{"stat": "lifesteal", "add": 0.25}, {"stat": "damage", "mul": 0.9}]},
	# Build de efeitos (2026-10-14, ideia do usuário; Marca, Persistência e Ácido com números
	# meus aprovados, Corrosão ideia dele). Código em Player (MARK_*, ACID_*, take_damage).
	"marca": {"name": "Mark", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Dealing damage marks the enemy for 3 s: you see them through walls and they take +15% of your damage. Only marks again 5 s later. Your Poison and your Burn also mark.",
		"mods": [{"stat": "mark", "add": 1}]},
	"persistencia": {"name": "Persistence", "cat": "Balas", "rarity": "raro", "max": 3,
		"desc": "Your Poison and your Burn last 30% longer (and deal more in total). Damage -5%.",
		"mods": [{"stat": "dot_time", "add": 0.3}, {"stat": "damage", "mul": 0.95}]},
	"acido": {"name": "Acid", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "While suffering your Poison or your Burn, the enemy heals 50% less.",
		"mods": [{"stat": "acid", "add": 1}]},
	"corrosao": {"name": "Corrosion", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Your Poison and your Burn ignore armor: they go straight to health.",
		"mods": [{"stat": "dot_pierce", "add": 1}]},
	# Contágio (2026-10-14, ideia minha aprovada; a volta para o próprio alvo é pedido dele).
	"contagio": {"name": "Contagion", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Your Poison jumps, at half strength, to enemies within 4 m of whoever is poisoned; with no one nearby, it goes back to the poisoned target itself. Each one catches it at most every 4 s, and poison that jumped doesn't jump again. Only works with Poison or Toxic Cloud. Magazine -1.",
		"mods": [{"stat": "contagion", "add": 1}, {"stat": "mag_size", "add": -1}]},
	# Reação em Cadeia (2026-10-14, ideia do usuário; números meus aprovados): Player.CHAIN_*.
	"reacao_em_cadeia": {"name": "Chain Reaction", "cat": "Balas", "rarity": "epico", "max": 2,
		"desc": "When one of your afflictions ends on an enemy, they explode: they take half your bullet damage (at least 5, up to 25) and deal the same to other enemies within 4 m, who catch the affliction that ended. Each one explodes at most every 3 s. With 2 copies, 80% of bullet damage (up to 40) and 5 m. Reload +0.3 s.",
		"mods": [{"stat": "chain_blast", "add": 1}, {"stat": "reload_time", "add": 0.3}]},
	# Dose Extra e Raspão (2026-10-17, ideias minhas aprovadas pelo usuário: a build de aflição
	# pura fica com 1 ou 2 balas no pente pelo Veneno e erra muito; números meus, para testar).
	"dose_extra": {"name": "Extra Dose", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Hitting and applying an affliction the enemy didn't have yet returns 1 bullet to the magazine. Reload +0.3 s.",
		"mods": [{"stat": "fresh_refund", "add": 1}, {"stat": "reload_time", "add": 0.3}]},
	"raspao": {"name": "Graze", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "A bullet that passes within 1 m of an enemy without hitting applies your afflictions to them, with no damage. At most once every 0.25 s on each enemy. Fire rate -10%.",
		"mods": [{"stat": "graze", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},
	"executor": {"name": "Executioner", "cat": "Balas", "rarity": "raro", "max": 2,
		"desc": "+40% damage to targets below 40% health. Fire rate -10%.",
		"mods": [{"stat": "execute", "add": 0.4}, {"stat": "fire_interval", "mul": 1.0 / 0.9}]},

	"bumerangue": {"name": "Boomerang", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "After half a second, or 3 m before the end of Range, bullets turn around and come back to you, hitting again along the way. Range doesn't apply on the way back.",
		"mods": [{"stat": "boomerang", "add": 1}]},
	"tabelinha": {"name": "Bank Shot", "cat": "Balas", "rarity": "lendario",
		"desc": "Each bounce adds +30% of the starting damage to the bullet. Gives no bounces: pair it with Ricochet or other bounce cards.",
		"mods": [{"stat": "bounce_damage", "add": 0.3}]},
	"detonacao": {"name": "Detonation", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Bullets stick where they hit and explode 0.6 s later (3.5 m radius). Reload +0.25 s.",
		"mods": [{"stat": "sticky", "add": 1}, {"stat": "reload_time", "add": 0.25}]},
	"fragmentacao": {"name": "Fragmentation", "cat": "Balas", "rarity": "epico",
		"desc": "On hitting a wall, the bullet splits into 4 shards with 40% of the damage.",
		"mods": [{"stat": "split", "add": 4}]},
	"bola_de_neve": {"name": "Snowball", "cat": "Balas", "rarity": "lendario",
		"desc": "The bullet grows with flight time and gains up to +100% damage over 5 s. Without bounces or another way to last longer, it vanishes before reaching the maximum.",
		"mods": [{"stat": "grow", "add": 1.0}]},
	"troca_troca": {"name": "Switcheroo", "cat": "Balas", "rarity": "lendario", "max": 1,
		"desc": "Hitting an enemy marks you both: 0.6 s later, you swap places. The same person can only be swapped again 2 s later. Damage -15%.",
		"mods": [{"stat": "swap", "add": 1}, {"stat": "damage", "mul": 0.85}]},
	"flash": {"name": "Flash", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Hitting an enemy turns their screen white for 0.9 s. After that, they can't be blinded again for 2 s.",
		"mods": [{"stat": "blind", "add": 0.9}]},
	"preguicosa": {"name": "Lazy Bullet", "cat": "Balas", "rarity": "raro", "max": 1,
		"desc": "Bullets start slow and accelerate up to 2.5x normal speed. Damage +25%.",
		"mods": [{"stat": "lazy", "add": 1}, {"stat": "damage", "mul": 1.25}]},
	# Dinamite e Carga Concentrada (2026-10-07, pedido do usuário: cartas que melhoram a
	# explosão; números meus, aprovados). Só valem com alguma carta de explosão.
	"dinamite": {"name": "Dynamite", "cat": "Balas", "rarity": "raro",
		"desc": "Your explosions get 1 m bigger and deal +30% damage. Without explosions, it does nothing.",
		"mods": [{"stat": "blast_radius", "add": 1.0}, {"stat": "blast_damage", "add": 0.3}]},
	"carga_concentrada": {"name": "Shaped Charge", "cat": "Balas", "rarity": "epico", "max": 1,
		"desc": "Your explosions deal +60% damage, but get 1 m smaller. Without explosions, it does nothing.",
		"mods": [{"stat": "blast_damage", "add": 0.6}, {"stat": "blast_radius", "add": -1.0}]},
	# Nuvem Tóxica e Buraco Negro (2026-10-06, cartas do Furor lembradas pelo usuário; números
	# meus). Desenho e limites em AreaField.
	"nuvem_toxica": {"name": "Toxic Cloud", "cat": "Balas", "rarity": "epico", "max": 3,
		"desc": "Where the bullet hits, a cloud stays (2.5 m, 3 s) that applies Poison to anyone inside: 30% of the bullet's damage per second inside (only 20% of the part above 40), dealt over 5 s. Your clouds don't stack on the same target. More copies: +0.75 m and +1 s. Fire rate -20%.",
		"mods": [{"stat": "toxic", "add": 1}, {"stat": "fire_interval", "mul": 1.0 / 0.8}]},
	"buraco_negro": {"name": "Black Hole", "cat": "Balas", "rarity": "epico", "max": 2,
		"desc": "Where the bullet hits, a black hole appears for 0.6 s and pulls enemies within 5 m to its center. With 2 copies it pulls harder and from 6 m. Damage -10%.",
		"mods": [{"stat": "black_hole", "add": 1}, {"stat": "damage", "mul": 0.9}]},

	# Escudo
	# Recarga do E (2026-10-07, regra do Furor descrita pelo usuário): toda carta que melhora
	# o escudo deixa a recarga mais longa, +1 s se o efeito é forte e +0,5 s se é fraco, por
	# cópia. Reflexos (-0,5 s, só isso) é a que mais tira sem custo; as que tiram e fazem
	# outra coisa tiram menos ou cobram algo. Somas limitadas em compute_stats.
	"escudo_firme": {"name": "Steady Shield", "cat": "Escudo", "rarity": "comum",
		"desc": "The shield lasts +0.15 s. Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_duration", "add": 0.15}, {"stat": "shield_cooldown", "add": 0.5}]},
	"reflexos": {"name": "Reflexes", "cat": "Escudo", "rarity": "comum",
		"desc": "Shield cooldown -0.5 s.",
		"mods": [{"stat": "shield_cooldown", "add": -0.5}]},
	"defensor": {"name": "Defender", "cat": "Escudo", "rarity": "comum",
		"desc": "Health +15%. Shield cooldown -0.25 s.",
		"mods": [{"stat": "max_health", "mul": 1.15}, {"stat": "shield_cooldown", "add": -0.25}]},
	"passo_ligeiro": {"name": "Light Step", "cat": "Escudo", "rarity": "comum",
		"desc": "Raising the shield gives +25% movement speed for 1.5 s. Shield cooldown -0.3 s.",
		"mods": [{"stat": "shield_haste", "add": 0.25}, {"stat": "shield_cooldown", "add": -0.3}]},
	"escudo_de_papel": {"name": "Paper Shield", "cat": "Escudo", "rarity": "raro",
		"desc": "Shield cooldown -1 s. Health -20%.",
		"mods": [{"stat": "shield_cooldown", "add": -1.0}, {"stat": "max_health", "mul": 0.8}]},
	"espelho_cortante": {"name": "Razor Mirror", "cat": "Escudo", "rarity": "raro",
		"desc": "Reflected bullets deal +75% damage. Shield cooldown +0.5 s.",
		"mods": [{"stat": "reflect_mult", "add": 0.75}, {"stat": "shield_cooldown", "add": 0.5}]},
	"adrenalina": {"name": "Adrenaline", "cat": "Escudo", "rarity": "epico", "max": 1,
		"desc": "Reflecting a bullet halves the remaining shield cooldown, once per shield raise. Shield cooldown +1 s.",
		"mods": [{"stat": "reflect_refund", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"espelho_duplo": {"name": "Double Mirror", "cat": "Escudo", "rarity": "epico",
		"desc": "Each reflected bullet comes back with one more. Shield cooldown +1 s.",
		"mods": [{"stat": "reflect_split", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"espelho_perseguidor": {"name": "Seeking Mirror", "cat": "Escudo", "rarity": "epico",
		"desc": "Reflected bullets chase the shooter. Shield cooldown +1 s.",
		"mods": [{"stat": "reflect_homing", "add": 3.0}, {"stat": "shield_cooldown", "add": 1.0}]},
	"recarga_tatica": {"name": "Tactical Reload", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Raising the shield refills the magazine. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_reload", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"investida": {"name": "Charge", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "Raising the shield launches you forward. Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_dash", "add": 1}, {"stat": "shield_cooldown", "add": 0.5}]},
	"onda_de_choque": {"name": "Shockwave", "cat": "Escudo", "rarity": "raro",
		"desc": "The shield pushes enemies within 8 m and deals 8 damage. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_shockwave", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"restauracao": {"name": "Restoration", "cat": "Escudo", "rarity": "comum",
		"desc": "Raising the shield heals 10 health. Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_heal", "add": 10.0}, {"stat": "shield_cooldown", "add": 0.5}]},
	"nova": {"name": "Nova", "cat": "Escudo", "rarity": "epico",
		"desc": "The shield fires 6 bullets around you (half damage). Shield cooldown +1 s.",
		"mods": [{"stat": "shield_nova", "add": 6}, {"stat": "shield_cooldown", "add": 1.0}]},

	"teleporte": {"name": "Teleport", "cat": "Escudo", "rarity": "lendario", "max": 1,
		"desc": "Raising the shield teleports you 7 m where you look, through walls. Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_teleport", "add": 1}, {"stat": "shield_cooldown", "add": 0.5}]},
	"chuva_de_bombas": {"name": "Bomb Rain", "cat": "Escudo", "rarity": "epico",
		"desc": "The shield lobs 5 bombs in an arc around you. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_bombs", "add": 5}, {"stat": "shield_cooldown", "add": 1.0}]},
	"eco": {"name": "Echo", "cat": "Escudo", "rarity": "lendario",
		"desc": "The shield raises itself again 0.5 s later, with the effects of your other Shield cards, one more time per copy. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_echo", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"ultima_defesa": {"name": "Final Guard", "cat": "Escudo", "rarity": "raro", "max": 1,
		"desc": "When the magazine empties, the shield raises itself (if it is ready). Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_on_empty", "add": 1}, {"stat": "shield_cooldown", "add": 0.5}]},
	"pancada": {"name": "Bash", "cat": "Escudo", "rarity": "raro",
		"desc": "With the shield up, anyone right against you takes 20 damage and is pushed. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_bash", "add": 20.0}, {"stat": "shield_cooldown", "add": 1.0}]},
	# Escudo Duplo (2026-10-07, pedido do usuário: sem o limite de 1 e repetindo os efeitos):
	# cada cópia é uma levantada a mais, 0,5 s depois, com todos os efeitos. Os +30% vêm
	# depois do teto das somas, então quanto mais efeitos no escudo, mais ela cobra: a partir
	# da 2a cópia o ganho por segundo para de crescer e só a rajada aumenta.
	"escudo_duplo": {"name": "Double Shield", "cat": "Escudo", "rarity": "lendario", "max": 3,
		"desc": "You can raise the shield one more time half a second later, with all effects again. Shield cooldown +1 s and, on top of the total, +30%.",
		"mods": [{"stat": "shield_charges", "add": 1}, {"stat": "shield_cooldown", "add": 1.0},
			{"stat": "shield_cooldown", "mul": 1.3}]},
	"couraca": {"name": "Cuirass", "cat": "Escudo", "rarity": "raro",
		"desc": "Raising the shield gives 10 armor. Armor absorbs damage before health and goes up to 50, together with armor from the map. Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_armor", "add": 10.0}, {"stat": "shield_cooldown", "add": 0.5}]},
	"fortaleza": {"name": "Fortress", "cat": "Escudo", "rarity": "comum",
		"desc": "+30 health and the shield lasts +0.1 s. Shield cooldown +0.5 s.",
		"mods": [{"stat": "max_health", "add": 30.0}, {"stat": "shield_duration", "add": 0.1},
			{"stat": "shield_cooldown", "add": 0.5}]},
	"espelho_gigante": {"name": "Giant Mirror", "cat": "Escudo", "rarity": "raro",
		"desc": "The shield catches bullets 50% farther from you. Shield cooldown +0.5 s.",
		"mods": [{"stat": "shield_size", "mul": 1.5}, {"stat": "shield_cooldown", "add": 0.5}]},
	# Áreas do escudo (2026-10-06, cartas do Furor lembradas pelo usuário; números meus, dano
	# fixo por escolha dele). Desde 2026-10-07 sem recarga própria: o custo é o +1 s no E.
	"serra": {"name": "Buzzsaw", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "The shield spins a saw around you for 2 s: 18 damage per second to anyone nearby. 2.5 m radius, +1 m per copy. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_saw", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"chamas": {"name": "Ring of Fire", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "The shield lights a ring of fire around you for 3 s that follows you: anyone inside gets Burn (9 per second), which continues 1 s after leaving. 4 m radius, +1 m per copy. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_flames", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	"geada": {"name": "Frost Wave", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "The shield releases a 5 m ice wave: 6 damage, 45% Slow for 2 s and 2 frost stacks. More copies: +1.5 m and +0.5 s. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_frost", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},
	# Estouro (2026-10-14, ideia do usuário, números meus; recarga +2 s pedida por ele; o
	# nome "Detonação" já era da bala que gruda).
	"estouro": {"name": "Rupture", "cat": "Escudo", "rarity": "epico", "max": 1,
		"desc": "Raising the shield bursts your Poison and your Burn on enemies within 30 m: they take what was left all at once, x1.5 (x2 with both together), and lose those effects. Your frost stacks also burst: 6 damage each. Up to 60 per target. Shield cooldown +2 s.",
		"mods": [{"stat": "shield_detonate", "add": 1}, {"stat": "shield_cooldown", "add": 2.0}]},
	"mina": {"name": "Mine", "cat": "Escudo", "rarity": "epico", "max": 3,
		"desc": "The shield drops a bomb on the ground that blinks and explodes 1 s later: 30 damage (half at the edge), 4 m radius. More copies: +15 damage and +0.5 m. Shield cooldown +1 s.",
		"mods": [{"stat": "shield_mine", "add": 1}, {"stat": "shield_cooldown", "add": 1.0}]},

	# Corpo
	"vigor": {"name": "Vigor", "cat": "Corpo", "rarity": "comum", "max": 3,
		"desc": "+25 max health.",
		"mods": [{"stat": "max_health", "add": 25.0}]},
	"fragil": {"name": "Fragile", "cat": "Corpo", "rarity": "comum",
		"desc": "Damage +30%. Health -30%.",
		"mods": [{"stat": "damage", "mul": 1.3}, {"stat": "max_health", "mul": 0.7}]},
	"tanque": {"name": "Tank", "cat": "Corpo", "rarity": "comum",
		"desc": "Health +60%. Movement speed -10%.",
		"mods": [{"stat": "max_health", "mul": 1.6}, {"stat": "move_speed", "mul": 0.9}]},
	"sede_de_sangue": {"name": "Bloodlust", "cat": "Corpo", "rarity": "raro",
		"desc": "Dealing damage gives +30% movement speed for 3 s.",
		"mods": [{"stat": "bloodlust", "add": 0.3}]},
	"furia": {"name": "Fury", "cat": "Corpo", "rarity": "raro",
		"desc": "+50% damage while below 35% health.",
		"mods": [{"stat": "rage", "add": 0.5}]},
	"fenix": {"name": "Phoenix", "cat": "Corpo", "rarity": "lendario", "max": 1,
		"desc": "When you die, come back once with half health. Health -20%.",
		"mods": [{"stat": "revives", "add": 1}, {"stat": "max_health", "mul": 0.8}]},
	"regeneracao": {"name": "Regeneration", "cat": "Corpo", "rarity": "raro",
		"desc": "Recover 5 health per second after 5 s without taking damage and without attacking (shot or Sword).",
		"mods": [{"stat": "regen", "add": 5.0}]},
	# Peso Pesado e Segunda Pele (2026-10-07, propostas minhas aprovadas pelo usuário).
	"peso_pesado": {"name": "Heavyweight", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "Pushes move you 60% less: explosions, Knockback, Shockwave, Mega Slap, Arcane Cannon and Black Hole. Movement speed -10%.",
		"mods": [{"stat": "heavy", "add": 0.6}, {"stat": "move_speed", "mul": 0.9}]},
	"segunda_pele": {"name": "Second Skin", "cat": "Corpo", "rarity": "raro",
		"desc": "Every 5 s without taking damage, gain 15 armor, up to 30 (copies: more armor each time and up to 50).",
		"mods": [{"stat": "armor_regen", "add": 15.0}]},
	# Casca Dura (2026-10-07, proposta minha escolhida pelo usuário no lugar dos Espinhos).
	"casca_dura": {"name": "Hard Shell", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "After taking a hit of 30 damage or more, you take 50% less damage for 1 s.",
		"mods": [{"stat": "tough", "add": 1}]},
	"blindado": {"name": "Armored", "cat": "Corpo", "rarity": "raro",
		"desc": "You take 40% less damage from explosions and areas (mines, saws, meteors). Doesn't apply to afflictions, such as poison and burn. Copies add up to 70%.",
		"mods": [{"stat": "blast_resist", "add": 0.4}]},
	"radar": {"name": "Radar", "cat": "Corpo", "rarity": "epico", "max": 3,
		"desc": "You see the name and health of enemies up to 30 m away through walls. Each copy adds +30 m.",
		"mods": [{"stat": "radar", "add": 1}]},
	"nanico": {"name": "Shorty", "cat": "Corpo", "rarity": "raro",
		"desc": "Body 30% smaller, harder to hit. Health -20%. Damage -10%.",
		"mods": [{"stat": "body_scale", "mul": 0.7}, {"stat": "max_health", "mul": 0.8}, {"stat": "damage", "mul": 0.9}]},
	"gigantao": {"name": "Giant", "cat": "Corpo", "rarity": "epico",
		"desc": "Body 40% bigger. Health +80%. Movement speed -15%.",
		"mods": [{"stat": "body_scale", "mul": 1.4}, {"stat": "max_health", "mul": 1.8}, {"stat": "move_speed", "mul": 0.85}]},
	# Corpo (2026-10-11, pedido do usuário: equilibrar os grupos; números meus, aprovados).
	# Couro Grosso refeito pelo usuário: redução que acumula enquanto apanha e zera parado.
	"couro_grosso": {"name": "Thick Hide", "cat": "Corpo", "rarity": "raro", "max": 2,
		"desc": "Each hit you take adds 1 reduction to the following ones (the first lands in full), up to 5 less damage per hit (8 with 2 copies; never below 1). 1.5 s without being hit resets it. Poison, burn and saw don't count.",
		"mods": [{"stat": "thick_skin", "add": 1}]},
	# Banquete refeito em 2026-10-18 (pedido do usuário; Fome com números meus aprovados):
	# Player.FEAST_*. kill_heal virou só a marca de que tem a carta.
	"banquete": {"name": "Feast", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "Getting a kill heals all your health and gives 1 Hunger stack: +8% damage and +5% max health per stack, up to 3. The stacks carry over from one round to the next; dying resets them.",
		"mods": [{"stat": "kill_heal", "add": 1.0}]},
	"tenacidade": {"name": "Tenacity", "cat": "Corpo", "rarity": "raro", "max": 2,
		"desc": "Every affliction lasts 35% less on you: slow, dizzy, blind, poison, burn and freeze (60% with 2 copies).",
		"mods": [{"stat": "tenacity", "add": 0.35}]},
	"metabolismo": {"name": "Metabolism", "cat": "Corpo", "rarity": "comum",
		"desc": "All healing you receive is 40% greater.",
		"mods": [{"stat": "heal_mult", "add": 0.4}]},
	"instinto": {"name": "Survival Instinct", "cat": "Corpo", "rarity": "raro",
		"desc": "Below 35% health, +25% speed.",
		"mods": [{"stat": "survival_speed", "add": 0.25}]},
	"vinganca": {"name": "Revenge", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "Your shots deal +25% damage to whoever killed you in the previous round.",
		"mods": [{"stat": "revenge", "add": 0.25}]},
	"leveza": {"name": "Lightweight", "cat": "Corpo", "rarity": "comum",
		"desc": "Movement speed +15%. Health -15%.",
		"mods": [{"stat": "move_speed", "mul": 1.15}, {"stat": "max_health", "mul": 0.85}]},
	# Mosquito (2026-10-18, ideia do usuário para formalizar a build "mosquito"; números meus,
	# vida -20% dele). Segue o tamanho do momento: Player.mosquito_small, MOSQUITO_*.
	"mosquito": {"name": "Mosquito", "cat": "Corpo", "rarity": "raro", "max": 1,
		"desc": "The smaller your body, the faster you shoot and the more health you steal: for every 10% below normal size, Fire rate +8% and lifesteal +2% (at most 55% below). Health -20%.",
		"mods": [{"stat": "mosquito", "add": 1}, {"stat": "max_health", "mul": 0.8}]},

	# Movimento
	"pulo_duplo": {"name": "Double Jump", "cat": "Movimento", "rarity": "raro",
		"desc": "+1 air jump.",
		"mods": [{"stat": "extra_jumps", "add": 1}]},
	"impulso": {"name": "Impulse", "cat": "Movimento", "rarity": "raro",
		"desc": "+1 air dash before touching the ground.",
		"mods": [{"stat": "air_dashes", "add": 1}]},
	"escalador": {"name": "Climber", "cat": "Movimento", "rarity": "comum",
		"desc": "+2 wall jumps before touching the ground (2 without the card).",
		"mods": [{"stat": "wall_jumps", "add": 2}]},
	"deslize_turbo": {"name": "Turbo Slide", "cat": "Movimento", "rarity": "comum",
		"desc": "The slide (holding Ctrl after the dash) gives 70% more boost.",
		"mods": [{"stat": "slide_boost", "mul": 1.7}]},
	"pena": {"name": "Feather", "cat": "Movimento", "rarity": "comum",
		"desc": "Jump 15% higher and fall 35% slower.",
		"mods": [{"stat": "jump_velocity", "mul": 1.15}, {"stat": "gravity_mult", "mul": 0.65}]},
	"botas_leves": {"name": "Light Boots", "cat": "Movimento", "rarity": "comum",
		"desc": "+8% speed.",
		"mods": [{"stat": "move_speed", "mul": 1.08}]},
	"cacador": {"name": "Hunter", "cat": "Movimento", "rarity": "raro",
		"desc": "For 2 s after hitting an enemy, +20% speed when moving toward them. Poison, burn and saw don't count.",
		"mods": [{"stat": "chase", "add": 0.2}]},
	"pulo_foguete": {"name": "Rocket Jump", "cat": "Movimento", "rarity": "epico", "max": 1,
		"desc": "Bullets explode (2 m radius). Your explosions launch you away from them without hurting you, adding to the speed you already had: 2 times before touching the ground, the 2nd one weaker. Enemies caught are pushed.",
		"mods": [{"stat": "rocket_jump", "add": 1}, {"stat": "explosion", "add": 2.0}]},
	"meteoro": {"name": "Ground Slam", "cat": "Movimento", "rarity": "epico",
		"desc": "Crouching in the air (Ctrl) slams you down instead of dashing; Shift still dashes. The higher you are, the stronger: 20 to 40 damage within 2.5 m and half that up to 5 m; from 4 m up, dizzy. You bounce upward. Cooldown 3 s.",
		"mods": [{"stat": "ground_slam", "add": 1}]},
	"folego": {"name": "Second Wind", "cat": "Movimento", "rarity": "comum",
		"desc": "Dash cooldown -40%.",
		"mods": [{"stat": "dash_cooldown", "mul": 0.6}]},
	"dash_longo": {"name": "Long Dash", "cat": "Movimento", "rarity": "comum",
		"desc": "The dash goes 40% farther.",
		"mods": [{"stat": "dash_power", "mul": 1.4}]},
	"esquiva": {"name": "Dodge", "cat": "Movimento", "rarity": "lendario", "max": 1,
		"desc": "During the dash, bullets pass through you. Dash cooldown +0.3 s.",
		"mods": [{"stat": "dash_dodge", "add": 1}, {"stat": "dash_cooldown", "add": 0.3}]},
	"atropelar": {"name": "Trample", "cat": "Movimento", "rarity": "raro",
		"desc": "Passing through an enemy with a dash deals 15 damage and pushes them.",
		"mods": [{"stat": "dash_hit", "add": 15.0}]},
	"saque_rapido": {"name": "Quick Draw", "cat": "Movimento", "rarity": "raro",
		"desc": "Each dash puts 2 bullets in the magazine.",
		"mods": [{"stat": "dash_ammo", "add": 2}]},
	"cacada": {"name": "Hunt", "cat": "Movimento", "rarity": "epico", "max": 1,
		"desc": "Hitting an enemy recharges the dash instantly and gives back an air dash. Poison, burn and saw don't count.",
		"mods": [{"stat": "hit_dash", "add": 1}]},
	"planador": {"name": "Glider", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Hold Space while falling to glide slowly. After gliding, until you touch the ground, you change direction in the air without losing speed.",
		"mods": [{"stat": "glide", "add": 1}]},
	"embalo": {"name": "Momentum", "cat": "Movimento", "rarity": "comum",
		"desc": "Air control 2x greater (turn without losing speed) and +5% speed.",
		"mods": [{"stat": "air_control", "mul": 2.0}, {"stat": "move_speed", "mul": 1.05}]},
	"molas": {"name": "Springs", "cat": "Movimento", "rarity": "comum",
		"desc": "Jump 20% higher.",
		"mods": [{"stat": "jump_velocity", "mul": 1.2}]},
	# Pisão (2026-10-06, ideia do usuário; números meus). Código em Player._check_stomp.
	# Parkour (2026-10-07, proposta minha; 1 s em vez de 1,5 a pedido do usuário).
	"parkour": {"name": "Parkour", "cat": "Movimento", "rarity": "raro",
		"desc": "Jumping off a wall gives you back an air dash and +20% movement speed for 1 s.",
		"mods": [{"stat": "parkour", "add": 1}]},
	# Dash Duplo (2026-10-07, ideia do usuário no estilo do Escudo Duplo; números meus).
	"dash_duplo": {"name": "Double Dash", "cat": "Movimento", "rarity": "lendario", "max": 2,
		"desc": "Each of your dashes chains another one on its own right after, toward where you are pressing (curving midway). Dash effects repeat, and in the air the extra one doesn't use up a dash. With 2 copies it's 3 dashes. Dash cooldown +0.3 s.",
		"mods": [{"stat": "dash_echo", "add": 1}, {"stat": "dash_cooldown", "add": 0.3}]},
	"pisao": {"name": "Stomp", "cat": "Movimento", "rarity": "raro", "max": 3,
		"desc": "Landing on an enemy's head (jumping or dashing through the air) deals 20 damage and bounces you up, restoring your dash and air jumps. Falling almost onto the head, the air pulls you gently to it (more with more copies). +10 damage per copy.",
		"mods": [{"stat": "stomp", "add": 1}]},
	# Build de movimento (2026-10-11, pedido do usuário: velocidade vira dano e defesa, e
	# chegar no corpo do inimigo; números meus, aprovados). Código em Player.shot_damage,
	# bullet_taken_mult, _tick (recarga) e _start_dash/_dash_seek_step (Bote).
	"velocidade_letal": {"name": "Lethal Speed", "cat": "Movimento", "rarity": "raro", "max": 2,
		"desc": "Your shots deal +2% damage per m/s above 9 m/s (walking speed), up to +30% while dashing. With 2 copies, double: +4% per m/s, up to +60%.",
		"mods": [{"stat": "speed_damage", "add": 0.3}]},
	"vulto": {"name": "Blur", "cat": "Movimento", "rarity": "epico", "max": 2,
		"desc": "Above 12 m/s you take 20% less bullet damage (35% with 2 copies).",
		"mods": [{"stat": "blur", "add": 1}]},
	"recarga_embalo": {"name": "Running Reload", "cat": "Movimento", "rarity": "comum",
		"desc": "In the air or sliding, reloading is 40% faster.",
		"mods": [{"stat": "air_reload", "add": 0.4}]},
	# Arrancada e Pressão (2026-10-15, build de escopeta; números meus aprovados). Player.STRIKE_*
	# e PRESSURE_*.
	"arrancada": {"name": "Rush", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Dashing toward an enemy in sight (within 20 m) makes your next shot, within 1 s, deal +30% damage. Dash cooldown +0.3 s.",
		"mods": [{"stat": "dash_strike", "add": 1}, {"stat": "dash_cooldown", "add": 0.3}]},
	"pressao": {"name": "Pressure", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Hitting an enemy within 6 m gives +25% movement speed for 1.5 s and advances the dash cooldown by 1 s (the shotgun spread counts once). Health -10%.",
		"mods": [{"stat": "pressure", "add": 1}, {"stat": "max_health", "mul": 0.9}]},
	"bote": {"name": "Pounce", "cat": "Movimento", "rarity": "raro", "max": 1,
		"desc": "Dashing almost toward an enemy in sight (within 10 m) makes the dash curve on its own toward them, up to 35 degrees.",
		"mods": [{"stat": "dash_seek", "add": 1}]},
}


var _icons := {}


func _init() -> void:
	CARDS.merge(MASTERS)


## Cartas comuns (as que vão no baralho e aparecem na escolha de 1 de 3).
func all_ids() -> Array:
	return CARDS.keys().filter(func(id): return not is_master(id))


func master_ids() -> Array:
	return MASTERS.keys().filter(func(id): return not id in MASTERS_OFF)


## Mestra fora do jogo por enquanto (MASTERS_OFF).
func is_off(id: String) -> bool:
	return id in MASTERS_OFF


## "No limit per match.", "Only once per match." ou "Up to 2 times per match."
func limit_text(id: String) -> String:
	var card: Dictionary = CARDS[id]
	if not card.has("max"):
		return tr("No limit per match.")
	if card["max"] == 1:
		return tr("Only once per match.")
	return tr("Up to %d times per match.") % card["max"]


## Versão curta para o editor: "" sem limite, "1 per match", "2 per match".
func limit_short(id: String) -> String:
	return tr("%d per match") % CARDS[id]["max"] if CARDS[id].has("max") else ""


func is_master(id: String) -> bool:
	return MASTERS.has(id)


## Textos das cartas no idioma do jogo. Contexto "card" nos .po: separa nome e descrição
## de carta dos outros textos iguais em inglês.
func card_name(id: String) -> String:
	return tr(CARDS[id]["name"], "card")


## Descrição; a das comuns termina com quantas vezes dá para pegar a carta na partida
## (2026-10-06, pedido do usuário: "máx." no editor parecia falar do baralho).
func card_desc(id: String) -> String:
	var desc := tr(CARDS[id]["desc"], "card")
	return desc if is_master(id) else desc + " " + limit_text(id)


func category_name(cat: String) -> String:
	return tr(CATEGORY_NAMES.get(cat, cat))


func archetype_name(arch: String) -> String:
	return tr(ARCHETYPES[arch].get("name", arch))


func archetype_desc(arch: String) -> String:
	return tr(ARCHETYPES[arch]["desc"])


func rarity_label(rarity: String) -> String:
	return tr(RARITIES[rarity]["name"])


## [termo, explicação] do glossário, traduzidos.
func glossary() -> Array:
	return GLOSSARY.map(func(e): return [tr(e[0]), tr(e[1])])


func template_name(index: int) -> String:
	return tr(TEMPLATES[index]["name"])


func template_desc(index: int) -> String:
	return tr(TEMPLATES[index]["desc"])


## Para a ferramenta de tradução (scenes/dev/i18n.tscn): [texto, contexto, origem].
func i18n_strings() -> Array:
	var out := []
	var src := "scripts/autoload/card_db.gd"
	for id in CARDS:
		out.append([CARDS[id]["name"], "card", src + " " + id])
		out.append([CARDS[id]["desc"], "card", src + " " + id])
	for r in RARITIES:
		out.append([RARITIES[r]["name"], "", src])
	for cat in CATEGORY_NAMES:
		out.append([CATEGORY_NAMES[cat], "", src])
	for a in ARCHETYPES:
		out.append([ARCHETYPES[a].get("name", a), "", src])
		out.append([ARCHETYPES[a]["desc"], "", src])
	for e in GLOSSARY:
		out.append([e[0], "", src])
		out.append([e[1], "", src])
	for t in TEMPLATES:
		out.append([t["name"], "", src])
		out.append([t["desc"], "", src])
	return out


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
	return rarity_label(CARDS[id]["rarity"])


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
	{"name": "Balanced", "desc": "a bit of every group", "per_cat": 10, "master": "corrente"},
	{"name": "Marksman", "desc": "weapon and bullets", "cats": ["Arma", "Balas"], "master": "bazuca"},
	{"name": "Bulwark", "desc": "close-range shield: defend, close in and hit", "cats": ["Escudo"], "copies": 2,
		"master": "bastiao",
		"ids": ["investida", "vigor", "tanque", "sanguessuga"]},
	{"name": "Acrobat", "desc": "movement and mobility", "cats": ["Movimento"], "copies": 2,
		"master": "corrente",
		"ids": ["investida", "teleporte", "sede_de_sangue", "nanico"]},
	{"name": "Chaos", "desc": "only the craziest cards", "master": "caos",
		"ids": ["bumerangue", "troca_troca", "bola_de_neve", "preguicosa", "fragmentacao", "tabelinha",
			"detonacao", "morteiro", "metralhadora", "escopeta", "bala_gigante", "teleguiada",
			"quique_certeiro", "espelho_duplo", "nova", "chuva_de_bombas", "teleporte", "nanico",
			"gigantao", "pulo_foguete", "meteoro", "flash", "pena", "escalador",
			"sortudo", "ultima_bala", "canhao_de_vidro", "fenix", "explosiva", "propulsao", "eco",
			"atropelar", "planador"]},
	{"name": "Random", "desc": "randomly drawn", "random": true},
	{"name": "Empty", "desc": "you choose everything"},
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
	stats["fire_bonus"] = bonus.get("fire_interval", 0.0)   # o Mosquito soma a este (Player.fire_interval)
	for stat in LIMITS:
		stats[stat] = clampf(stats[stat], LIMITS[stat][0], LIMITS[stat][1])
	var size: float = stats["body_scale"] * pow(stats["max_health"] / base["max_health"], HEALTH_SIZE_EXP)
	stats["body_scale"] = clampf(size, LIMITS["body_scale"][0], LIMITS["body_scale"][1])
	for stat in stats.keys():
		if base[stat] is int:
			stats[stat] = int(round(stats[stat]))
	return stats
