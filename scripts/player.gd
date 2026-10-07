class_name Player
extends CharacterBody3D
## Jogador do 1x1. As ações chegam pelas variáveis in_*, preenchidas pelo teclado e mouse
## ou por um BotBrain. Em rede, só o dono simula o jogador (is_local); a cópia nas outras
## máquinas só segue o que chega pela rede (_net_state).
##
## Movimento no estilo arena shooter: aceleração e atrito próprios, controle no ar que
## preserva o embalo, deslize, escalada de beirada, pulo na parede (2 por pulo, para
## escalar), gravidade mais forte
## na descida (pulo firme, sem flutuar), tolerância para pular depois de sair da beirada
## e pulo guardado antes de pousar. Dash no Ctrl: no chão (andando) dá um tiro curto de
## velocidade que, segurando, vira deslize; no ar dá uma corridinha reta, uma vez por pulo.

signal died(player: Player)
signal damaged(amount: float, from: Player)
signal damage_dealt(amount: float, lethal: bool)
signal reflected
signal revived
signal void_bounced(saved: bool)
signal went_down    # caiu no 2x2 (pode ser revivido)
signal got_up       # foi revivido
signal chaos_drawn(id: String)   # Caos sorteou outra mestra (a HUD avisa)
signal froze       # ficou preso no gelo (Prisão de Gelo; o registro do autoteste conta)
signal slapped(splat: bool)   # levou o Mega Tapa / bateu na parede (registro do autoteste)
signal beamed      # levou um toque do Canhão Arcano (registro do autoteste)
signal platform_made   # criou (ou recebeu pela rede) uma plataforma suspensa (registro do autoteste)
signal meteor_marked   # marca de meteoro no chão (registro do autoteste)
signal rocket_exploded # um Foguete explodiu (registro do autoteste)

## Atributos sem nenhuma carta. As cartas (CardDB) alteram estes valores.
const BASE_STATS := {
	"max_health": 100.0,
	"move_speed": 9.0,
	"jump_velocity": 12.0,   # sobe ~2,35 m com GRAVITY_RISE
	"gravity_mult": 1.0,
	"extra_jumps": 0,
	"wall_jumps": 2,
	"air_dashes": 1,
	"dash_cooldown": 0.9,
	"dash_dodge": 0,
	"dash_hit": 0.0,
	"dash_ammo": 0,
	"dash_power": 1.0,
	"hit_dash": 0,
	"air_control": 1.0,
	"glide": 0,
	"slide_boost": 1.0,
	# Tiro no estilo ROUNDS: poucas balas por pente, cada uma pesa (3 acertos matam),
	# projétil visível que cai com a distância.
	"damage": 34.0,
	"fire_interval": 0.3,
	"mag_size": 4,
	"reload_time": 1.3,
	"bullet_speed": 48.0,
	"bullet_gravity": 7.0,
	"bullet_count": 1,
	"spread": 4.0,
	"burst": 1,
	"bullet_radius": 0.15,
	"last_shot": 1.0,
	"crit_chance": 0.0,
	"bounces": 0,
	"homing": 0.0,
	"ghost": 0,
	"explosion": 0.0,
	"poison": 0.0,
	"slow": 0.0,
	"knockback": 0.0,
	"shield_break": 0,
	"target_bounce": 0,
	"execute": 0.0,
	"lifesteal": 0.0,
	"boomerang": 0,
	"bounce_damage": 0.0,
	"sticky": 0,
	"split": 0,
	"grow": 0.0,
	"swap": 0,
	"blind": 0.0,
	"lazy": 0,
	"auto_fire": 0,   # Metralhadora: segurar o botão repete o tiro
	"shield_duration": 0.35,
	"shield_cooldown": 2.0,
	"reflect_mult": 1.0,
	"reflect_refund": 0,
	"reflect_split": 0,
	"reflect_homing": 0.0,
	"shield_reload": 0,
	"shield_dash": 0,
	"shield_shockwave": 0,
	"shield_heal": 0.0,
	"shield_nova": 0,
	"shield_teleport": 0,
	"shield_bombs": 0,
	"shield_echo": 0,
	"shield_on_empty": 0,
	"shield_size": 1.0,
	"shield_charges": 1,
	"shield_bash": 0.0,
	"shield_armor": 0.0,
	"shield_saw": 0,      # Serra, Chamas, Geada e Mina (AreaField): áreas que nascem do escudo
	"shield_flames": 0,
	"shield_frost": 0,
	"shield_mine": 0,
	"toxic": 0,           # Nuvem Tóxica e Buraco Negro: nascem onde a bala bate (AreaField)
	"black_hole": 0,
	"stomp": 0,           # Pisão
	"bloodlust": 0.0,
	"rage": 0.0,
	"revives": 0,
	"regen": 0.0,
	"radar": 0,
	"body_scale": 1.0,
	"chase": 0.0,
	"camo": 0,
	"rocket_jump": 0,
	"rocket_boots": 0,   # Bota Foguete (carta mestra)
	"ground_slam": 0,
	# Cartas mestras (CardDB.MASTERS)
	"chaos": 0,     # Caos: sorteia outra mestra (_chaos_draw)
	"ice": 0,       # Prisão de Gelo
	"slap": 0,      # Mega Tapa
	"beam": 0,      # Canhão Arcano
	"platforms": 0, # Plataformas Suspensas
	"meteor": 0,    # Chuva de Meteoros
	"rocket_ride": 0,   # Foguete
	"updraft": 0,
	"bazooka": 0,
	"sniper": 0,
	"shrink": 0,    # Formiga
	"sword": 0,     # Espada
	"barrier": 0,
	"pierce": 0,
	"guided": 0,   # Piloto, mestra guardada (CardDB.SHELVED_MASTERS)
	"last_stand": 0,
}

## Skins: os 12 modelos do pacote Mini Characters da Kenney (CC0), [id, nome]. O jogador
## escolhe a sua em Personalizar (GameState.skin); bots e quem não tem skin usam a ordem da
## lista pelo lado da partida. Os 4 primeiros eram os modelos fixos de cada lado.
## Miniatura de cada uma em assets/skins/<id>.png (feitas com o próprio modelo).
const SKINS := [
	["male-b", "Barbudo"], ["female-c", "Marina"], ["male-e", "Engenheiro"], ["female-a", "Violeta"],
	["male-a", "Professor"], ["female-b", "Sol"], ["male-c", "Policial"], ["female-d", "Executiva"],
	["male-d", "Executivo"], ["female-e", "Doutora"], ["male-f", "Ranzinza"], ["female-f", "Mochileira"],
]
## Skins de arma: pistolas e armas pequenas do Blaster Kit da Kenney (CC0), parecidas com a
## padrão (pedido do usuário: nada muito diferente). Só aparência; o tiro é o mesmo.
## Miniaturas em assets/gun_skins/<id>.png.
const GUN_SKINS := [
	["blaster-b", "Padrão"], ["blaster-c", "Compacta"], ["blaster-k", "Dourada"],
	["blaster-l", "Ametista"], ["blaster-m", "Vespa"],
]
const DEFAULT_GUN := "blaster-b"
static var _gun_fronts := {}


static func gun_ids() -> Array:
	return GUN_SKINS.map(func(s): return s[0])


static func gun_name(id: String) -> String:
	for s in GUN_SKINS:
		if s[0] == id:
			return s[1]
	return ""


static func gun_model(id: String) -> String:
	return "res://assets/blasters/%s.glb" % (id if id in gun_ids() else DEFAULT_GUN)


static func gun_thumb(id: String) -> Texture2D:
	return load("res://assets/gun_skins/%s.png" % id)


## Visual vindo de fora (rede, arquivo): o que não existir vira "" (padrão).
static func clean_look(look) -> Dictionary:
	var out := {"skin": "", "gun": ""}
	if look is Dictionary:
		if String(look.get("skin", "")) in skin_ids():
			out["skin"] = String(look["skin"])
		if String(look.get("gun", "")) in gun_ids():
			out["gun"] = String(look["gun"])
	return out


## Ponta do cano no espaço do modelo (frente da caixa que envolve as peças, que apontam
## para -Z). O cano das outras armas fica onde o da padrão ficava, mais a diferença.
static func gun_front(id: String) -> Vector3:
	if not _gun_fronts.has(id):
		var root: Node3D = load(gun_model(id)).instantiate()
		var box := model_box(root)
		root.free()
		_gun_fronts[id] = Vector3(box.get_center().x, box.get_center().y, box.position.z)
	return _gun_fronts[id]


## Caixa que envolve as peças de um modelo, no espaço dele (sem a escala do próprio nó).
static func model_box(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Quanto o cano desta arma fica à frente (ou atrás) do da arma padrão, no espaço do modelo.
func _muzzle_shift() -> Vector3:
	var id := gun_skin if gun_skin in gun_ids() else DEFAULT_GUN
	return gun_front(id) - gun_front(DEFAULT_GUN)


static func skin_ids() -> Array:
	return SKINS.map(func(s): return s[0])


static func skin_name(id: String) -> String:
	for s in SKINS:
		if s[0] == id:
			return s[1]
	return ""


static func skin_model(id: String) -> String:
	return "res://assets/characters/character-%s.glb" % id


static func skin_thumb(id: String) -> Texture2D:
	return load("res://assets/skins/%s.png" % id)
const MODEL_SCALE := 2.6
## Arma na mão, no espaço do osso "arm-right" (ver AimArm): o braço vai de 0 a -0,28 em X.
const HAND_POS := Vector3(-0.25, -0.02, 0.0)
const HAND_ROT := Vector3(0, PI / 2.0, 0)
const LOOPING_ANIMS := ["idle", "walk", "sprint", "fall", "crouch"]

# Movimento
## Gravidade forte e impulsos maiores: as alturas continuam as mesmas, mas tudo no ar
## dura menos (~15% mais rápido que com 22/30), como em Valorant, Apex e Titanfall.
const GRAVITY_RISE := 30.0   # subindo
const GRAVITY_FALL := 42.0   # descendo: queda mais rápida que a subida
const APEX_SPEED := 1.2      # perto do topo do pulo...
const APEX_GRAVITY := 0.6    # ...a gravidade alivia um instante (pulo mais controlável)
const MAX_FALL_SPEED := 55.0
const GROUND_ACCEL := 12.0
const AIR_ACCEL := 3.2
const FRICTION := 7.0
const STOP_SPEED := 3.0
const MAX_HSPEED := 24.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const JUMP_CUT := 0.65
const CROUCH_SPEED_MULT := 0.5
const SLIDE_MIN_SPEED := 5.5
const SLIDE_STOP_SPEED := 4.0
const SLIDE_BOOST := 4.0
const SLIDE_FRICTION := 0.45
const SLIDE_COOLDOWN := 0.6
const WALL_JUMP_PUSH := 7.0  # pulo na parede soltando o movimento para longe dela
const WALL_CLIMB_PUSH := 1.5 # pulo na parede empurrando contra ela: sobe rente (escalada)
const WALL_GRACE := 0.15     # ainda vale pular na parede este tempo depois de desencostar
const MANTLE_REACH := 2.2    # altura máxima (a partir dos pés) de uma beirada que dá para escalar
const DASH_SPEED := 24.0
const DASH_TIME := 0.18
const DASH_EXIT := 1.3       # ao fim do dash sobra pelo menos 1,3x a velocidade de corrida
const DODGE_TIME := 0.24     # Esquiva: as balas atravessam por este tempo depois do dash
const DASH_HIT_RANGE := 1.4  # Atropelar
const GLIDE_FALL := 3.0     # Planador: velocidade máxima de queda segurando o pulo
## Planador (2026-10-05, pedido do usuário: ao soltar o pulo o personagem seguia embalado
## sem dar para mudar de rumo): depois de planar, até tocar o chão, segurar uma direção
## gira a velocidade para ela a este tanto por segundo (radianos; 90 graus em ~0,25 s),
## sem perder velocidade.
const GLIDE_TURN := 6.0
## Bota Foguete (carta mestra, 2026-10-06; como a bota foguete do Terraria): sem pulos no ar
## sobrando, apertar e segurar pular liga um jato que acelera para cima (BOOT_THRUST, contra
## a gravidade: caindo, primeiro freia; depois sobe até BOOT_MAX_UP). Dura BOOT_FUEL no
## total, em quantos toques quiser, e enche ao tocar o chão. Curto de propósito (pedido do
## usuário): é um controle breve no ar; voar de verdade continua com as cartas comuns.
## No ar, os tiros ganham AIR_DAMAGE_RATE por segundo, até AIR_DAMAGE_MAX.
const BOOT_FUEL := 0.7
const BOOT_THRUST := 72.0
const BOOT_MAX_UP := 4.5
const AIR_DAMAGE_RATE := 0.1
const AIR_DAMAGE_MAX := 0.4
const SLAM_LOOK := -0.6      # Meteoro: olhando mais para baixo que isto (uns 35 graus)
# Corpo
const RADIUS := 0.4
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const STAND_EYE := 1.6
const CROUCH_EYE := 0.95
## Tamanho do corpo (cartas e vida) na altura da câmera (2026-10-05, pedido do usuário):
## acompanha 85% da mudança, então quem cresce vê mais de cima e quem encolhe, de baixo.
const EYE_SIZE_FOLLOW := 0.85
const SHIELD_HIT_RADIUS := 0.9
# Vazio (Arena.VOID_Y, 1 m abaixo do chão): quem cai quica e leva dano. O quique normal é
# baixo e curto: perto da borda dá para voltar, longe precisa de vários (e cada um fere).
# Com o escudo de pé na hora, não leva dano e o quique é alto e longo.
const VOID_DAMAGE := 20.0
const VOID_BOUNCE := 11.1         # sobe ~2 m (1 m acima do chão), ~0,7 s no ar
const VOID_BOUNCE_SHIELD := 18.7  # sobe ~5,8 m, ~1,2 s no ar
const VOID_CREDIT := 4.0          # quem acertou você nestes segundos leva o crédito da queda
const ARMOR_MAX := 50.0      # colete (item do mapa): absorve dano antes da vida
# Combate
const SHOCKWAVE_RANGE := 8.0
const BASH_RANGE := 2.2         # Pancada: alcance do escudo, do peito de um ao do outro
const SHIELD_DOUBLE_GAP := 0.5  # Escudo Duplo: espera entre a primeira e a segunda vez
const SILENCE_TIME := 1.5
const SLOW_TIME := 1.5
const POISON_TIME := 3.0
const BLOODLUST_TIME := 3.0
const RAGE_THRESHOLD := 0.35
const REGEN_DELAY := 3.0
const BURST_GAP := 0.07
## Tiro semiautomático (2026-10-05): cada clique é um tiro; segurar não repete, só com a
## Metralhadora (auto_fire). Um clique um pouco antes de a arma ficar pronta fica guardado
## por este tempo e sai assim que der, como nos jogos de tiro com arma semiautomática:
## sem isso o clique adiantado se perderia e a arma pareceria falhar.
const SHOT_BUFFER := 0.15
const ADRENALINE_GAP := 0.4
const CRIT_MULT := 2.5
const TELEPORT_RANGE := 7.0
## Teleporte (refeito em 2026-10-05, como no Furor): atravessa paredes. Se o ponto cair
## dentro de uma peça, procura lugar livre na mesma linha, primeiro à frente até este
## tanto a mais, depois para trás; nunca sai pelo muro de fora do mapa.
const TELEPORT_OVERSHOOT := 4.0
const TELEPORT_STEP := 0.5
## Restauração e Couraça (2026-10-05, pedido do usuário: a build de escudo curava sem
## parar): o efeito tem recarga própria, separada da do escudo. Cartas que aceleram o
## escudo não multiplicam a cura; cópias aumentam a quantidade, não a frequência.
const SHIELD_PERK_COOLDOWN := 3.0
## Troca-Troca (2026-10-05, pedido do usuário: a troca instantânea confundia): os dois
## ficam marcados por SWAP_DELAY e só então trocam; quem foi trocado não troca de novo por
## SWAP_COOLDOWN depois disso.
const SWAP_DELAY := 0.6
const SWAP_COOLDOWN := 2.0
## Depois da troca os dois não colidem entre si por este tempo: o motor (e a rede) ainda
## veem o outro no lugar antigo por um instante, e quem chega por cima era empurrado para
## o alto e ficava subindo sem parar, carregado como numa plataforma.
const SWAP_GHOST := 0.5
const ECHO_DELAY := 0.5
## Camuflagem (carta mestra desde 2026-10-06): parado por CAMO_DELAY, some. Invisível,
## anda sem aparecer até CAMO_SNEAK da velocidade (agachado cabe). Aparecer depois de
## AMBUSH_MIN_HIDDEN invisível dá a Emboscada: AMBUSH_TIME com mais dano nos tiros e mais
## velocidade, no máximo a cada AMBUSH_COOLDOWN (senão ficaria ligada sem parar).
const CAMO_DELAY := 0.6
const CAMO_SNEAK := 0.55
const AMBUSH_MIN_HIDDEN := 1.0
const AMBUSH_TIME := 3.0
const AMBUSH_COOLDOWN := 6.0
const AMBUSH_DAMAGE := 0.4
const AMBUSH_SPEED := 0.2
## Orbes do mapa (2026-10-06, no lugar do orbe de reset; ideia do usuário, números meus,
## aprovados): Velocidade dá +30% de velocidade por 4 s; Impulso lança uns 6 m para cima
## (com GRAVITY_RISE 30) e devolve dash, pulos e jato no ar.
const SPEED_ORB := 0.3
const SPEED_ORB_TIME := 4.0
const LAUNCH_ORB_SPEED := 19.0
const AMBUSH_COLOR := Color(0.72, 0.4, 1.0)
const SLAM_SPEED := 32.0
const SLAM_MIN_HEIGHT := 2.5
const SLAM_RANGE := 5.0
const SLAM_DAMAGE := 25.0
## Pisão (2026-10-06, ideia do usuário; números meus): cair na cabeça de um inimigo, pulando
## ou no dash pelo ar, fere e quica para cima, devolvendo o dash e os pulos no ar (escolha
## dele) para emendar outro pisão. No dash a área é mais generosa: de lado é difícil
## acertar a cabeça. A mesma pessoa só leva outro pisão depois de STOMP_REPEAT.
const STOMP_DAMAGE := 25.0
const STOMP_DAMAGE_STEP := 15.0   # por cópia a mais
const STOMP_BOUNCE := 14.0        # sobe ~3,3 m com GRAVITY_RISE
const STOMP_REPEAT := 0.5
## Caído no 2x2 (2026-10-06, pedido do usuário; números meus, com base no Apex, que revive
## em 5 s e encolhe o prazo a cada queda, e no Fortnite, 10 s): com o parceiro de pé, o golpe
## fatal derruba em vez de matar. Caído, se arrasta devagar, não atira nem usa nada, e NINGUÉM
## pode finalizá-lo (escolha do usuário): só o prazo acabando mata. O parceiro revive ficando
## REVIVE_TIME perto (pode atirar enquanto isso); fora do círculo o progresso volta devagar.
## O prazo encolhe a cada queda na rodada, para não abusarem.
const DOWN_BLEED := [10.0, 6.0, 3.0]   # 1a, 2a e da 3a queda em diante
const DOWN_CRAWL := 0.25               # fração da velocidade
const DOWN_HEIGHT := 0.8
const DOWN_EYE := 0.5
const DOWN_LIE := 1.35        # caído: quanto o modelo deita para a frente (rad)
const DOWN_LIE_LIFT := 0.2    # ...e quanto sobe, para o corpo não entrar no chão
const REVIVE_RADIUS := 2.5
const REVIVE_TIME := 3.0
const REVIVE_HEALTH := 0.3             # da vida máxima
const REVIVE_PROTECT := 1.0            # segundos sem levar dano depois de levantar
## Chamas: a queimadura sai em pedaços deste tamanho (um aviso de dano a cada meio segundo,
## em vez de um por quadro).
const BURN_CHUNK := 6.0
# Cartas mestras
const UPDRAFT_SPEED := 21.9      # Corrente: sobe ~8 m em ~0,7 s
const BAZOOKA_TIME := 6.0        # Bazuca: quanto tempo dura...
const BAZOOKA_ROCKETS := 3       # ...e quantos foguetes dá
const BAZOOKA_INTERVAL := 0.7
const ROCKET_SPEED := 30.0
const ROCKET_DAMAGE := 2.0       # vezes o dano da arma
const ROCKET_EXPLOSION := 4.0
const LAST_STAND_TIME := 3.0     # Último Suspiro
## Sniper (2026-10-06, desenho do usuário; números meus): Q dá a sniper por SNIPER_TIME
## ou até o único tiro. O tiro é um laser: reto, SNIPER_SPEED (quase instantâneo),
## atravessa todas as paredes e causa SNIPER_DAMAGE x o dano da arma (3x 34 = 102: mata
## quem tem a vida base). Botão direito mira com zoom (campo de visão SCOPE_FOV, mouse
## mais lento na mesma proporção, anda a SCOPE_SPEED).
const SNIPER_TIME := 8.0
const SNIPER_DAMAGE := 3.0
const SNIPER_SPEED := 400.0
const SNIPER_DRAW := 0.35        # tempo para sacar a sniper antes de poder atirar
const SNIPER_COLOR := Color(1.0, 0.35, 0.3)
const SNIPER_MODEL := "res://assets/blasters/blaster-e.glb"
const SCOPE_FOV := 24.0
## O modelo da sniper (blaster-e) tem a origem na ponta do cano e 1,39 m para trás: nessa
## escala e posição a coronha fica logo à frente da câmera e o cano aponta para a mira.
const SWORD_VIEW_POS := Vector3(0.08, -0.05, 0.12)   # punho da espada na primeira pessoa
const SNIPER_VIEW_SCALE := 0.33
const SNIPER_VIEW_POS := Vector3(0.02, 0.0, -0.15)
const SCOPE_SPEED := 0.6
## Espada (2026-10-06, desenho do usuário; números meus): Q troca a arma por uma espada por
## SWORD_TIME. Cada clique é um golpe de um combo que se repete: corte para a direita, corte
## para a esquerda e estocada (lança à frente como um dash curto). Os cortes acertam quem
## estiver até SWORD_RANGE num leque de SWORD_ARC para cada lado; a estocada, até
## THRUST_RANGE num leque estreito, e também quem ela atravessar no avanço. Dano: a arma
## (shot_damage) vezes SWORD_DAMAGE[golpe]. Quem leva decide (receive_slash): com o escudo
## de pé, bloqueia. Sem golpe por COMBO_RESET, o combo volta ao primeiro.
const SWORD_TIME := 8.0
const SWORD_RANGE := 3.2
const SWORD_ARC := 65.0          # graus para cada lado
const THRUST_RANGE := 3.6
const THRUST_ARC := 25.0
const SWORD_DAMAGE := [1.0, 1.0, 1.6]
const SWORD_GAP := 0.38          # entre um golpe e outro
const THRUST_GAP := 0.55         # depois da estocada
const COMBO_RESET := 0.9
const THRUST_DASH := 0.13        # duração do avanço da estocada (na velocidade do dash)
const SWORD_COLOR := Color(0.75, 0.88, 1.0)
## Formiga (2026-10-06): Q encolhe por SHRINK_TIME (tamanho x SHRINK_SCALE, junto com a área
## que as balas acertam; a colisão com o cenário não muda, para não prender ninguém na
## parede ao crescer) e dá SHRINK_SPEED de velocidade. Q de novo volta antes. Ao crescer,
## impacto de SHRINK_SLAM_RANGE com SHRINK_SLAM_DAMAGE e empurrão.
const SHRINK_TIME := 6.0
const SHRINK_SCALE := 0.4
const SHRINK_SPEED := 0.6
const SHRINK_SLAM_RANGE := 4.0
const SHRINK_SLAM_DAMAGE := 20.0
const SHRINK_SLAM_PUSH := 1.25    # empurrão um pouco maior que o da Onda de Choque (pedido do usuário: nada exagerado)
const PIERCE_SHOTS := 3          # Perfurante: tiros por uso...
const PIERCE_SPEED := 3.0        # ...quantas vezes mais rápidos
# Câmera e arma em primeira pessoa
## FOV vertical (o Godot mede na altura). 74 graus dão uns 105 na horizontal em 16:9,
## perto do padrão de Apex, Valorant e Overwatch; mais que isso distorce as bordas.
const BASE_FOV := 74.0
const SPEED_FOV := 8.0
const VIEWMODEL_POS := Vector3(0.2, -0.19, -0.36)
const VIEWMODEL_SCALE := 0.55
const RECOIL_KICK := 0.03
const HIT_FLASH_TIME := 0.14   # o modelo atingido pisca em branco por este tempo
## Métodos que a outra máquina pode chamar neste jogador (ver remote_call).
const ASSIST_TIME := 10.0   # placar: dano nos últimos 10 s antes da morte conta assistência
const REMOTE_METHODS := ["receive_shockwave", "credit_damage", "teleport_to", "swap_to", "receive_stomp",
	"receive_slash", "ice_shove", "receive_slap", "receive_beam"]
## Canhão Arcano (mestra): carga de BEAM_CHARGE (andando a BEAM_CHARGE_SPEED), depois um
## raio de BEAM_TIME que atravessa o cenário. Parado (no ar, flutua); a mira gira no
## máximo BEAM_TURN por segundo. Cada toque: BEAM_DAMAGE e arremesso pelo raio; o mesmo
## alvo de novo só depois de BEAM_REHIT.
const BEAM_CHARGE := 1.0
const BEAM_CHARGE_SPEED := 0.4
const BEAM_TIME := 2.5
const BEAM_RANGE := 40.0
const BEAM_RADIUS := 0.8
const BEAM_DAMAGE := 30.0
## Empurrão para FORA do raio (escolha do usuário, 2026-10-06: empurrando ao longo, o
## alvo seguia na linha e levava 4 toques seguidos sem a mira se mexer).
const BEAM_PUSH_SIDE := 20.0
const BEAM_PUSH_ALONG := 8.0
const BEAM_LIFT := 8.0
const BEAM_REHIT := 0.6
const BEAM_SHIELD_PUSH := 0.5
const BEAM_TURN := deg_to_rad(30.0)
const BEAM_COLOR := Color(0.78, 0.5, 1.0)
var beam_charge := 0.0     # carregando (todas as máquinas, para o visual)
var beam_timer := 0.0      # raio ligado
var beam_hits := {}        # alvo -> tempo até poder levar de novo
var beam_aim := Vector2.ZERO   # (yaw, pitch) para onde o mouse quer ir; a mira segue devagar
var beam_fx: Node3D
## Plataformas Suspensas (mestra): Q no ar cria uma plataforma e liga o modo por PLAT_MODE; nesse
## tempo, pular no ar sem pulos sobrando cria outra (até PLAT_MAX). Recarga do card (18 s)
## = os 6 s do modo + 12 s.
const PLAT_MODE := 6.0
const PLAT_MAX := 4
var plat_mode := 0.0
var plat_left := 0
## Chuva de Meteoros (mestra): METEOR_SHOTS tiros marcados por até METEOR_WINDOW; o meteoro
## em si está em MeteorStrike.
const METEOR_SHOTS := 3
const METEOR_WINDOW := 8.0
var meteor_left := 0
var meteor_window := 0.0
var meteor_shot := false   # o disparo atual marca o chão
## Foguete (mestra): montado por RIDE_TIME a RIDE_SPEED, sem gravidade, na direção da mira
## (que gira devagar, como no Canhão Arcano; inclinação até RIDE_PITCH). Q de novo salta e
## solta o foguete (bala `rocket`, ROCKET_FREE_SPEED, explode no contato ou em
## ROCKET_FREE_TIME). Explosão: ROCKET_BLAST_DAMAGE no centro até ROCKET_BLAST_RADIUS.
const RIDE_TIME := 5.0
const RIDE_SPEED := 12.0
const RIDE_PITCH := deg_to_rad(20.0)
const RIDE_TURN := deg_to_rad(45.0)
const RIDE_JUMP := 10.0
const ROCKET_FREE_SPEED := 40.0
const ROCKET_FREE_TIME := 2.0
const ROCKET_BLAST_DAMAGE := 60.0
const ROCKET_BLAST_RADIUS := 5.0
const ROCKET_LIFT := 14.0      # quem estava montado quando explodiu é lançado para cima
const ROCKET_COLOR := Color(1.0, 0.55, 0.2)
const ROCKET_FAT := 0.5        # raio do corpo do foguete montado
const RIDE_LIFT := 0.6         # sobe ao montar, para o foguete caber embaixo
var ride_timer := 0.0
var ride_age := 0.0
var ride_fx: Node3D
## Mega Tapa (mestra): leque curto à frente; arremessa (SLAP_PUSH para o lado, SLAP_LIFT
## para cima). Por SLAP_FLIGHT segundos, bater numa parede ainda rápido (SPLAT_MIN_SPEED)
## dá SPLAT_DAMAGE e deixa tonto (DAZE_TIME: lento e sem atirar).
const SLAP_RANGE := 2.5
const SLAP_ARC := 50.0
const SLAP_DAMAGE := 15.0
const SLAP_PUSH := 22.0
const SLAP_LIFT := 12.0
const SLAP_FLIGHT := 1.0
const SPLAT_DAMAGE := 25.0
const SPLAT_MIN_SPEED := 6.0
const DAZE_TIME := 0.6
const DAZE_SLOW := 0.5
const SLAP_COLOR := Color(1.0, 0.75, 0.55)
var slap_flight := 0.0     # arremessado por um tapa: ainda pode bater na parede
var slap_from := ""        # quem deu o tapa (crédito do impacto)
var daze_timer := 0.0      # tonto: não atira
var hand_pivot: Node3D     # primeira pessoa: a mão do tapa
## Prisão de Gelo (mestra): caco reto que congela por ICE_TIME. Congelado: não age, não
## leva dano, desliza (ICE_FRICTION) e é empurrado por tiros (ICE_PUSH por ponto de dano,
## ~5 m/s no tiro base), explosões e encontrões (ice_shove). No vazio quica e o dano fica
## guardado (ice_debt) até derreter.
const ICE_TIME := 3.0
const ICE_SPEED := 60.0
const ICE_RANGE := 40.0
const ICE_PUSH := 0.15
const ICE_FRICTION := 2.5
const ICE_SHOVE_DASH := 1.5
const ICE_COLOR := Color(0.7, 0.95, 1.0)
const ICE_CAM_DISTANCE := 4.5
var ice_timer := 0.0      # congelado por mais quanto tempo (todas as máquinas, para o visual)
var ice_debt := 0.0       # dano do vazio guardado até derreter (no máximo um)
var ice_block: Node3D
## Carta mestra que este jogador tem (a primeira de cards; "" se nenhuma).
var master_id := ""      # mestra da vez (com o Caos, a sorteada)
var master_cd := 0.0
## Caos: espera depois de usar a ativa sorteada e duração da passiva sorteada.
const CHAOS_WAIT := 8.0
const CHAOS_PASSIVE_TIME := 15.0
var chaos := false        # tem a mestra Caos
var chaos_used := false   # a ativa sorteada já foi usada (esperando a próxima)
var chaos_timer := 0.0    # passiva sorteada: quanto falta para trocar
var _chaos_last := ""     # último sorteio recebido pela rede (ver reset_for_round)
var bazooka_timer := 0.0
var rockets_left := 0
var shrink_timer := 0.0    # Formiga: pequeno por mais quanto tempo
var sword_timer := 0.0     # Espada na mão por mais quanto tempo
var combo_step := 0        # próximo golpe do combo (0 direita, 1 esquerda, 2 estocada)
var combo_idle := 0.0
var thrust_timer := 0.0    # estocada avançando (acerta quem atravessar)
var swing_hits: Array = []
var swing_anim := 0.0      # terceira pessoa: tempo de animação de ataque que falta
var sword: Node3D          # espada na mão (primeira pessoa: dentro de sword_pivot)
var sword_pivot: Node3D
var sniper_timer := 0.0    # Sniper na mão por mais quanto tempo
var sniper_shots := 0
var scoping := false       # mirando com a luneta (botão direito com a Sniper)
var in_aim := false
var pierce_left := 0       # Perfurante: tiros carregados
var pierce_shot := false   # o disparo atual (com a rajada) é perfurante
var last_stand_timer := 0.0
var last_stand_used := false

var player_name := "Jogador"
var skin := ""          # id em SKINS (vazio: a do lado da partida)
var gun_skin := ""      # id em GUN_SKINS (vazio: a padrão)
var is_human := false   # este é o jogador da câmera desta máquina
var is_local := true    # esta máquina simula o jogador (falso = cópia de um jogador remoto)
var peer_id := 1
var side := 0
## Time no 2x2 (0 Azul, 1 Vermelho); -1 é cada um por si.
var team := -1
var color := Color.WHITE
## O jogador da câmera desta máquina (usado pelo Radar).
static var viewer: Player
var brain: BotBrain
var deck: Array = []
var cards: Array = []
var stats: Dictionary = BASE_STATS.duplicate()

var health := 100.0
var armor := 0.0
var ammo := 6
var alive := true
var frozen := true
var fire_timer := 0.0
var shoot_was := false     # in_shoot no quadro anterior (para achar o clique)
var shot_queued := 0.0     # clique guardado esperando a arma ficar pronta (SHOT_BUFFER)
var _clicked := false      # clique visto em _input desde o último passo de física
var reload_timer := 0.0
var burst_left := 0
var burst_timer := 0.0
var shield_timer := 0.0
var shield_cd := 0.0
var shield_extra := 0          # Escudo Duplo: usos rápidos que ainda restam neste ciclo
var bash_hits: Array = []      # Pancada: quem já apanhou deste escudo
var reflect_flash := 0.0

var height := STAND_HEIGHT
var crouching := false
var sliding := false
var slide_cd := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var jump_rising := false
var jumps_left := 0
var wall_jumps_left := 0
var wall_time := 0.0         # encostou numa parede há pouco (WALL_GRACE)
var wall_normal := Vector3.ZERO
var mantle_cd := 0.0
var air_dashes_left := 0
var dash_cd := 0.0
var dash_timer := 0.0
var dash_dir := Vector3.ZERO
var dash_air := false        # o dash atual começou no ar (sem gravidade enquanto dura)
var dash_exit := 0.0         # velocidade que sobra quando o dash acaba
var dodge_timer := 0.0
var dash_hits: Array = []    # inimigos já atropelados neste dash
var was_on_floor := true
var was_shielding := false
var eye_dip := 0.0

var slow_timer := 0.0
var slow_amount := 0.0
var poisons: Array = []   # [{dps, time, from}]
var silence_timer := 0.0
var bloodlust_timer := 0.0
var since_damage := 0.0
var last_attacker: Player       # quem causou o último dano (crédito de quem empurra no vazio)
## Placar (Tab): quem causou dano e quando (Time.get_ticks_msec), só na máquina dona. Na
## morte, o último que causou dano leva o abate e os outros dos últimos ASSIST_TIME s, a
## assistência. Vai junto com o aviso de morte, então todas as máquinas contam igual.
var recent_hits := {}           # Player -> ms
var death_killer := ""          # nome do nó de quem matou ("" = ninguém, ex.: a própria bala)
var death_assists: Array = []
var revives_left := 0
var blind_timer := 0.0
var echo_timer := 0.0
var glided := false       # Planador: planou neste salto (vale até tocar o chão)
var boot_fuel := BOOT_FUEL   # Bota Foguete: jato que sobra (s)
var boot_armed := false   # apertou pular no ar sem pulos sobrando; vale enquanto segurar
var boosting := false     # jato ligado neste quadro (vai para as outras máquinas no estado)
var air_time := 0.0       # há quanto tempo está no ar (bônus de dano da Bota Foguete)
var boot_fx: CPUParticles3D
var heal_cd := 0.0        # Restauração: falta quanto para curar de novo
var armor_cd := 0.0       # Couraça: falta quanto para dar colete de novo
var area_cd := {}         # Serra, Chamas, Geada, Mina: bit (AreaField.SHIELD_*) -> recarga própria
var stomp_hits := {}      # Pisão: inimigo -> quando levou o último (ms)
var burn_timer := 0.0     # Chamas: queimando por mais quanto tempo
var burn_dps := 0.0
var burn_acc := 0.0
var burn_from: Player = null
## Caído (2x2). Enquanto caído, alive é falso: balas, áreas, bots e o fim da rodada já o
## tratam como fora. Só a máquina dona decide cair, levantar e morrer; as outras só contam
## o tempo para mostrar.
static var downs_enabled := false   # a partida liga no 2x2
var downed := false
var bleed_timer := 0.0
var bleed_total := 1.0
var revive_progress := 0.0
var downs := 0                # quedas nesta rodada
var protect_timer := 0.0
var down_credit: Array = ["", []]   # abate e assistências de quando caiu (vale se o prazo acabar)
var down_marker: Node3D
var swap_timer := 0.0     # Troca-Troca: falta quanto para a troca (na máquina de quem levou o tiro)
var swap_lock := 0.0      # Troca-Troca: não começa outra troca enquanto for maior que zero
var swap_partner: Player = null
var still_time := 0.0     # parado há quanto tempo (Camuflagem)
var speed_orb_timer := 0.0   # orbe de Velocidade ligado por mais quanto tempo
var ambush_timer := 0.0   # Emboscada ligada por mais quanto tempo (todas as máquinas, para o brilho)
var ambush_cd := 0.0      # falta quanto para poder ganhar outra Emboscada (só a máquina dona)
var ambush_mat: ShaderMaterial
var slamming := false     # despencando com o Meteoro
var shot_mult := 1.0      # dano extra do disparo atual (Última Bala)

var in_move := Vector2.ZERO
var in_jump := false
var in_jump_held := false
var in_crouch := false
var in_shoot := false
var in_click := false      # clicou neste passo (um clique rápido cabe entre dois passos de física)
var in_shield := false
var in_dash := false
var in_reload := false
var in_master := false

# Rede
var net_round := 0
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_on_floor := true

var head: Node3D
var camera: Camera3D
var muzzle: Marker3D
var muzzle_light: OmniLight3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var model: Node3D
var anim: AnimationPlayer
var aim_arm: AimArm
var gun: Node3D
var bazooka: Node3D     # aparece no lugar da arma enquanto a Bazuca dura
var sniper: Node3D      # idem, com a Sniper
var ring: MeshInstance3D
var viewmodel: Node3D
var shield_mesh: MeshInstance3D
var shield_mat: StandardMaterial3D
var tag: Label3D
var recoil := 0.0
var sway := Vector2.ZERO
var bob_time := 0.0
var shake := 0.0
var cam_roll := 0.0
var look_yaw := 0.0
var hit_flash := 0.0
var flash_mat: StandardMaterial3D
var body_meshes: Array = []
static var _hit_sound_frame := -1
## 2x2 (2026-10-05, era difícil achar o parceiro): o aliado ganha um contorno na cor do
## time que aparece através das paredes (camada por cima do modelo, como no Valorant e no
## Overwatch) e uma seta sobre o nome. Só o parceiro de quem está olhando; adversário não.
const ALLY_RIM_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_back, shadows_disabled;
uniform vec4 rim_color : source_color;
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = rim_color.rgb;
	ALPHA = rim_color.a * (0.22 + 0.78 * edge);
}
"""
static var _rim_shader: Shader
static var _ambush_shader: Shader
static var _arrow_tex: ImageTexture
var ally_mat: ShaderMaterial
var ally_arrow: Sprite3D
var _ally_look := false


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1 | 2 | SkyPlatform.LAYER   # plataformas da Plataformas Suspensas: só jogadores pisam
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.3

	shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	shape.shape = capsule
	add_child(shape)

	head = Node3D.new()
	head.position.y = STAND_EYE
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.fov = BASE_FOV
	head.add_child(camera)
	camera.current = is_human
	if is_human:
		# A física roda a 60 Hz e o corpo é interpolado entre um passo e outro (sem tremer
		# em monitor de 120 ou 144 Hz). A câmera fica de fora da interpolação e é posta a
		# cada quadro em _place_camera: assim o mouse responde na hora, sem atraso.
		camera.top_level = true
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	if is_human:
		_build_viewmodel()
	else:
		_build_body()

	shield_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 2.1
	shield_mat = StandardMaterial3D.new()
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.22)
	sphere.material = shield_mat
	shield_mesh.mesh = sphere
	shield_mesh.visible = false
	shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_mesh)

	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.outline_size = 8
	tag.modulate = color.lightened(0.5)
	tag.visible = not is_human
	add_child(tag)
	_set_height(STAND_HEIGHT)


## Primeira pessoa: só a arma presa na câmera, com luz de disparo no cano.
func _build_viewmodel() -> void:
	viewmodel = Node3D.new()
	viewmodel.position = VIEWMODEL_POS
	camera.add_child(viewmodel)
	var g: Node3D = load(gun_model(gun_skin)).instantiate()
	_no_shadows(g)
	g.scale = Vector3.ONE * VIEWMODEL_SCALE
	g.rotation.y = 0.06   # cano levemente virado para a mira
	viewmodel.add_child(g)
	gun = g
	bazooka = _make_bazooka()
	_no_shadows(bazooka)
	bazooka.scale = Vector3.ONE * 0.6
	bazooka.position = Vector3(0.06, -0.02, 0.0)
	bazooka.visible = false
	viewmodel.add_child(bazooka)
	sniper = load(SNIPER_MODEL).instantiate()
	_no_shadows(sniper)
	sniper.scale = Vector3.ONE * SNIPER_VIEW_SCALE
	sniper.rotation.y = 0.06
	sniper.position = SNIPER_VIEW_POS
	sniper.visible = false
	viewmodel.add_child(sniper)
	# Espada: o pivô fica no punho; os golpes giram o pivô (tween em _show_swing).
	sword_pivot = Node3D.new()
	sword_pivot.position = SWORD_VIEW_POS
	viewmodel.add_child(sword_pivot)
	sword = _make_sword()
	_no_shadows(sword)
	sword.scale = Vector3.ONE * 0.55
	sword.visible = false
	sword_pivot.add_child(sword)
	_rest_sword()
	hand_pivot = Node3D.new()
	hand_pivot.visible = false
	viewmodel.add_child(hand_pivot)
	var hand := _make_hand()
	_no_shadows(hand)
	hand_pivot.add_child(hand)
	muzzle = Marker3D.new()
	muzzle.position = Vector3(-0.01, 0.025, -0.17) + _muzzle_shift() * VIEWMODEL_SCALE
	viewmodel.add_child(muzzle)
	_add_muzzle_light()


## Terceira pessoa: personagem animado com a arma na mão e um anel da cor do time no chão.
func _build_body() -> void:
	var id := skin if skin in skin_ids() else String(SKINS[side % SKINS.size()][0])
	model = load(skin_model(id)).instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	model.rotation.y = PI   # os modelos olham para +Z; o jogador olha para -Z
	add_child(model)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in LOOPING_ANIMS:
		if anim.has_animation(a):
			anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	_rigidify(model.find_children("*", "Skeleton3D", true, false)[0], skin_model(id))
	body_meshes = model.find_children("*", "MeshInstance3D", true, false)
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.albedo_color = Color(1, 1, 1, 0)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	aim_arm = AimArm.new()
	skeleton.add_child(aim_arm)
	var hand := BoneAttachment3D.new()
	hand.bone_name = "arm-right"
	skeleton.add_child(hand)
	gun = load(gun_model(gun_skin)).instantiate()
	gun.scale = Vector3.ONE * (1.3 / MODEL_SCALE)
	# Na ponta do braço (o osso sai para -X), com o cano ao longo dele (AimArm).
	gun.rotation = HAND_ROT
	gun.position = HAND_POS
	hand.add_child(gun)
	bazooka = _make_bazooka()
	bazooka.scale = Vector3.ONE * (3.0 / MODEL_SCALE)
	bazooka.rotation = gun.rotation
	bazooka.position = gun.position
	bazooka.visible = false
	hand.add_child(bazooka)
	sniper = load(SNIPER_MODEL).instantiate()
	sniper.scale = gun.scale
	sniper.rotation = gun.rotation
	# A origem da sniper é a ponta do cano e o corpo vai para +Z: a mão segura a 35% do
	# comprimento, de trás para a frente (no osso, +Z do modelo vira +X).
	var sniper_box := model_box(sniper)
	var grip_z := sniper_box.end.z - 0.35 * sniper_box.size.z
	sniper.position = gun.position - Vector3(sniper.scale.x * grip_z, 0, 0)
	sniper.visible = false
	hand.add_child(sniper)
	sword = _make_sword()
	sword.scale = Vector3.ONE * (2.4 / MODEL_SCALE)
	sword.rotation = gun.rotation
	sword.position = gun.position
	sword.visible = false
	hand.add_child(sword)
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, 0.04, -0.3) + _muzzle_shift()
	gun.add_child(muzzle)
	_add_muzzle_light()

	ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.02
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	disc.material = mat
	ring.mesh = disc
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


## Personagem em peças rígidas (check-up de desempenho de 2026-10-06): nos Mini Characters
## cada vértice segue um osso só (conferido nos 12), então a malha é cortada uma vez por
## osso e cada pedaço vai num BoneAttachment3D, que acompanha a animação e o AimArm. Medido
## com janela no PC do usuário: a deformação por esqueleto custava ~4 ms por personagem
## por quadro na Intel HD (ANGLE), mesmo com ele fora da tela; as peças não custam isso.
## Os pedaços ficam guardados por modelo (_rigid_parts) e são os mesmos para todos.
static var _rigid_parts := {}


func _rigidify(skeleton: Skeleton3D, path: String) -> void:
	var holders := {}
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", false, false):
		if mi.skin == null:
			continue
		var key := "%s:%s" % [path, mi.name]
		if not _rigid_parts.has(key):
			_rigid_parts[key] = _split_by_bone(mi)
		for part in _rigid_parts[key]:
			var bone: String = part[0]
			if not holders.has(bone):
				var att := BoneAttachment3D.new()
				att.bone_name = bone
				skeleton.add_child(att)
				holders[bone] = att
			var piece := MeshInstance3D.new()
			piece.mesh = part[1]
			piece.cast_shadow = mi.cast_shadow
			holders[bone].add_child(piece)
		mi.free()


## Uma malha por osso, com os vértices já no espaço do osso (pose de ligação do Skin).
static func _split_by_bone(mi: MeshInstance3D) -> Array:
	var skin: Skin = mi.skin
	var src: Mesh = mi.mesh
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	var colors = arr[Mesh.ARRAY_COLOR]
	var bones = arr[Mesh.ARRAY_BONES]
	var index = arr[Mesh.ARRAY_INDEX]
	if index == null or index.is_empty():
		index = PackedInt32Array(range(verts.size()))
	var per: int = bones.size() / verts.size()
	var groups := {}   # índice do bind -> {map, v, n, uv, c, i}
	for t in index.size():
		var old: int = index[t]
		var b: int = bones[old * per]
		if not groups.has(b):
			groups[b] = {"map": {}, "v": PackedVector3Array(), "n": PackedVector3Array(),
				"uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
		var g: Dictionary = groups[b]
		if not g["map"].has(old):
			var pose := skin.get_bind_pose(b)
			g["map"][old] = g["v"].size()
			g["v"].append(pose * verts[old])
			g["n"].append((pose.basis * normals[old]).normalized())
			if uvs != null:
				g["uv"].append(uvs[old])
			if colors != null:
				g["c"].append(colors[old])
		g["i"].append(g["map"][old])
	var material := mi.get_active_material(0)
	var out := []
	for b in groups:
		var g: Dictionary = groups[b]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = g["v"]
		a[Mesh.ARRAY_NORMAL] = g["n"]
		if uvs != null:
			a[Mesh.ARRAY_TEX_UV] = g["uv"]
		if colors != null:
			a[Mesh.ARRAY_COLOR] = g["c"]
		a[Mesh.ARRAY_INDEX] = g["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(0, material)
		var bone_name := String(skin.get_bind_name(b))
		if skin.get_bind_bone(b) >= 0:
			bone_name = String(mi.get_node(mi.skeleton).get_bone_name(skin.get_bind_bone(b)))
		out.append([bone_name, mesh])
	return out


func _add_muzzle_light() -> void:
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = color.lightened(0.5)
	muzzle_light.omni_range = 4.0
	muzzle_light.light_energy = 0.0
	muzzle_light.visible = false
	muzzle.add_child(muzzle_light)


func _no_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_no_shadows(c)


func _set_height(h: float) -> void:
	height = h
	capsule.height = h
	shape.position.y = h / 2.0
	if shield_mesh:
		shield_mesh.position.y = h / 2.0 + 0.05
	if tag:
		tag.position.y = h + 0.5


## Começo de rodada: recalcula os atributos com as cartas e volta ao ponto de partida.
func reset_for_round(spawn: Transform3D) -> void:
	stats = CardDB.compute_stats(BASE_STATS, cards)
	var masters := cards.filter(CardDB.is_master)
	master_id = masters[0] if not masters.is_empty() else ""
	master_cd = 0.0
	chaos = master_id == "caos"
	if chaos:
		master_id = ""
		if is_local:
			_chaos_draw()
		elif _chaos_last != "":
			# O sorteio desta rodada pode ter chegado antes deste reinício: reaplica.
			_chaos_set(_chaos_last)
	bazooka_timer = 0.0
	rockets_left = 0
	pierce_left = 0
	pierce_shot = false
	sniper_timer = 0.0
	sniper_shots = 0
	scoping = false
	shrink_timer = 0.0
	sword_timer = 0.0
	combo_step = 0
	thrust_timer = 0.0
	swing_anim = 0.0
	set_meta("shrunk", false)
	_show_bazooka(false)
	last_stand_timer = 0.0
	last_stand_used = false
	ice_timer = 0.0
	ice_debt = 0.0
	_ice_visual(false)
	slap_flight = 0.0
	daze_timer = 0.0
	_end_beam(false)
	plat_mode = 0.0
	plat_left = 0
	meteor_left = 0
	meteor_window = 0.0
	ride_timer = 0.0
	_ride_visual(false)
	get_tree().call_group("meteor_strikes", "queue_free")
	global_transform = spawn
	reset_physics_interpolation()
	net_pos = spawn.origin
	net_yaw = rotation.y
	look_yaw = rotation.y
	net_pitch = 0.0
	head.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	health = stats["max_health"]
	armor = 0.0
	ammo = stats["mag_size"]
	fire_timer = 0.0
	shot_queued = 0.0
	reload_timer = 0.0
	burst_left = 0
	shield_timer = 0.0
	shield_cd = 0.0
	shield_extra = stats["shield_charges"] - 1
	air_dashes_left = stats["air_dashes"]
	dash_timer = 0.0
	dash_cd = 0.0
	dodge_timer = 0.0
	crouching = false
	sliding = false
	_set_height(STAND_HEIGHT)
	slow_timer = 0.0
	poisons.clear()
	silence_timer = 0.0
	bloodlust_timer = 0.0
	since_damage = 0.0
	recent_hits.clear()
	last_attacker = null
	revives_left = stats["revives"]
	blind_timer = 0.0
	echo_timer = 0.0
	heal_cd = 0.0
	armor_cd = 0.0
	area_cd.clear()
	stomp_hits.clear()
	downed = false
	downs = 0
	bleed_timer = 0.0
	revive_progress = 0.0
	protect_timer = 0.0
	_clear_down_marker()
	burn_timer = 0.0
	burn_acc = 0.0
	burn_from = null
	glided = false
	boot_fuel = BOOT_FUEL
	boot_armed = false
	boosting = false
	air_time = 0.0
	swap_timer = 0.0
	swap_lock = 0.0
	swap_partner = null
	still_time = 0.0
	speed_orb_timer = 0.0
	ambush_timer = 0.0
	ambush_cd = 0.0
	_restore_overlay()
	slamming = false
	alive = true
	shape.disabled = false
	tag.visible = not is_human
	_apply_body_scale()
	if model:
		model.rotation.x = 0.0
		model.position.y = 0.0
		model.visible = true
		ring.visible = true
		anim.play("idle")


## Tamanho do corpo (cartas, vida e a Formiga) no modelo, no nome e no escudo.
func _apply_body_scale() -> void:
	var body_scale: float = stats["body_scale"]
	tag.position.y = height * body_scale + 0.5
	shield_mesh.scale = Vector3.ONE * maxf(body_scale, 1.0) * float(stats["shield_size"])
	if model:
		model.scale = Vector3.ONE * MODEL_SCALE * body_scale
	if ring:
		# O disco do chão acompanha só quando encolhe (Formiga, Nanico); maior, fica igual.
		ring.scale = Vector3.ONE * minf(body_scale, 1.0)


func _input(event: InputEvent) -> void:
	if not is_human or brain != null:
		return
	if event.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_clicked = true
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# O giro do corpo vai para look_yaw e é aplicado no passo de física (o corpo é
		# interpolado); a câmera já usa look_yaw no quadro seguinte.
		var sens := GameState.mouse_sens
		if scoping:
			sens *= camera.fov / BASE_FOV   # com zoom, o mouse anda na mesma proporção
		if beam_timer > 0.0 or ride_timer > 0.0:
			# Canhão Arcano e Foguete: o mouse move o alvo; a mira vai atrás devagar (_process).
			beam_aim.x = wrapf(beam_aim.x - motion.relative.x * sens, -PI, PI)
			beam_aim.y = clampf(beam_aim.y - motion.relative.y * sens, -1.5, 1.5)
			return
		look_yaw = wrapf(look_yaw - motion.relative.x * sens, -PI, PI)
		head.rotate_x(-motion.relative.y * sens)
		head.rotation.x = clampf(head.rotation.x, -1.5, 1.5)
		sway = (sway - motion.relative * 0.0004).limit_length(0.05)


func _read_local_input() -> void:
	if GameState.menu_open or GameState.chat_open:
		# Menu de pausa aberto online (o jogo não para) ou digitando no chat: fica parado.
		in_move = Vector2.ZERO
		in_jump = false
		in_jump_held = false
		in_crouch = false
		in_shoot = false
		in_click = false
		_clicked = false
		in_shield = false
		in_dash = false
		in_reload = false
		in_master = false
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	in_jump = Input.is_action_just_pressed("jump")
	in_jump_held = Input.is_action_pressed("jump")
	in_crouch = Input.is_action_pressed("crouch")
	in_shoot = captured and Input.is_action_pressed("shoot")
	in_click = _clicked
	_clicked = false
	in_shield = Input.is_action_just_pressed("shield")
	# Com a Sniper na mão, o botão direito é a luneta (fixo), mesmo que o escudo use ele.
	in_aim = captured and sniper_timer > 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if sniper_timer > 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		in_shield = false
	in_dash = Input.is_action_just_pressed("dash")
	in_reload = Input.is_action_just_pressed("reload")
	in_master = Input.is_action_just_pressed("master")


# ---------------------------------------------------------------- visual

func _process(delta: float) -> void:
	if (beam_timer > 0.0 or ride_timer > 0.0) and is_human:
		var turn := (BEAM_TURN if beam_timer > 0.0 else RIDE_TURN) * delta
		look_yaw = rotate_toward(look_yaw, beam_aim.x, turn)
		var pitch_aim := beam_aim.y if beam_timer > 0.0 else clampf(beam_aim.y, -RIDE_PITCH, RIDE_PITCH)
		head.rotation.x = rotate_toward(head.rotation.x, pitch_aim, turn)
	if ride_fx:
		_update_ride_fx()
	if beam_fx:
		_update_beam_fx(delta)
	var shielding := alive and is_shielding()
	if shielding and not was_shielding:
		Sfx.at(self, "shield", chest())
	was_shielding = shielding
	shield_mesh.visible = shielding
	reflect_flash = maxf(0.0, reflect_flash - delta * 4.0)
	shield_mat.albedo_color.a = 0.22 + reflect_flash * 0.5
	if muzzle_light:
		muzzle_light.light_energy = move_toward(muzzle_light.light_energy, 0.0, delta * 60.0)
		# Luz apagada fica invisível: no OpenGL cada luz ligada custa um passe a mais.
		muzzle_light.visible = muzzle_light.light_energy > 0.0
	_update_camo(delta)
	_update_boot_fx()
	if not is_human:
		# Aliado: nome e vida sempre à vista, através das paredes, na cor do time.
		var ally := viewer != null and viewer.is_ally(self)
		if ally != _ally_look:
			_set_ally_look(ally)
		tag.no_depth_test = ally or (viewer != null and viewer != self and viewer.stats["radar"] > 0)
		if tag.visible and downed:
			tag.text = "%s\nCAÍDO" % player_name
		elif tag.visible:
			tag.text = "%s\n%d" % [player_name, ceili(health)] + (" +%d" % ceili(armor) if armor > 0.0 else "")
		if ally_arrow:
			# Parceiro caído: a seta pisca para chamar atenção.
			ally_arrow.modulate.a = (0.35 + 0.65 * absf(sin(Time.get_ticks_msec() * 0.008))) if downed else 1.0
	if model:
		_update_animation()
		_update_hit_flash(delta)
	if is_human:
		_camera_feel(delta)


func _update_animation() -> void:
	aim_arm.pitch = head.rotation.x
	aim_arm.active = alive and swing_anim <= 0.0
	if swing_anim > 0.0:
		swing_anim -= get_process_delta_time()
		if alive:
			return   # golpe de espada tocando (attack-melee-right)
	# Caído: o modelo deita de bruços (gira para a frente sobre os pés) e "nada" no chão.
	var lie := DOWN_LIE if downed else 0.0
	if not is_equal_approx(model.rotation.x, lie):
		model.rotation.x = move_toward(model.rotation.x, lie, get_process_delta_time() * 8.0)
		model.position.y = DOWN_LIE_LIFT * model.rotation.x / DOWN_LIE
	if downed:
		var crawl := Vector2(velocity.x, velocity.z).length()
		var pose := "walk" if crawl > 0.3 else "idle"
		if anim.current_animation != pose:
			anim.play(pose, 0.2)
		anim.speed_scale = 0.6
		return
	if not alive:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var on_floor := is_on_floor() if is_local else net_on_floor
	var next := "idle"
	if not on_floor:
		next = "jump" if velocity.y > 0.0 else "fall"
	elif crouching:
		next = "crouch"
	elif hspeed > 7.0:
		next = "sprint"
	elif hspeed > 0.5:
		next = "walk"
	if anim.current_animation != next:
		anim.play(next, 0.15)
	anim.speed_scale = clampf(hspeed / 6.0, 0.8, 1.6) if next == "walk" or next == "sprint" else 1.0


## Liga ou desliga o visual de aliado (contorno através das paredes e seta sobre o nome).
func _set_ally_look(on: bool) -> void:
	_ally_look = on
	if model == null:
		return
	if on and ally_mat == null:
		if _rim_shader == null:
			_rim_shader = Shader.new()
			_rim_shader.code = ALLY_RIM_SHADER
		ally_mat = ShaderMaterial.new()
		ally_mat.shader = _rim_shader
		ally_mat.set_shader_parameter("rim_color", Color(color, 0.65))
		ally_arrow = Sprite3D.new()
		ally_arrow.texture = _arrow_texture()
		ally_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ally_arrow.no_depth_test = true
		ally_arrow.fixed_size = true
		ally_arrow.pixel_size = 0.001
		ally_arrow.render_priority = 2
		ally_arrow.modulate = color.lightened(0.35)
		ally_arrow.position.y = 0.55   # acima das duas linhas do nome (filha do tag, some com ele)
		tag.add_child(ally_arrow)
	if ally_arrow:
		ally_arrow.visible = on
	_restore_overlay()


## Seta para baixo, branca com borda escura (a cor vem do modulate), feita em código.
static func _arrow_texture() -> ImageTexture:
	if _arrow_tex:
		return _arrow_tex
	var w := 48
	var h := 34
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# Distância à borda do triângulo (topo largo, ponta embaixo).
			var half := (w / 2.0) * (1.0 - float(y) / h)
			var dx := absf(x + 0.5 - w / 2.0)
			var inside := half - dx
			var to_edge := minf(inside * float(h) / sqrt(h * h + (w / 2.0) * (w / 2.0)), float(y))
			if inside <= 0.0:
				continue
			var c := Color.WHITE if to_edge > 3.0 else Color(0.05, 0.05, 0.08)
			c.a = clampf(inside, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_arrow_tex = ImageTexture.create_from_image(img)
	return _arrow_tex


## Acerto visto de fora: o modelo pisca em branco e encolhe/achata um instante. A camada
## branca (material_overlay) só fica ligada enquanto pisca, porque custa um passe a mais.
func flash_hit() -> void:
	if model == null:
		return
	if hit_flash <= 0.0:
		for m in body_meshes:
			m.material_overlay = flash_mat
	hit_flash = 1.0


func _update_hit_flash(delta: float) -> void:
	if hit_flash <= 0.0:
		return
	hit_flash = maxf(0.0, hit_flash - delta / HIT_FLASH_TIME)
	flash_mat.albedo_color.a = hit_flash * 0.85
	var squash := Vector3(1.0 + 0.05 * hit_flash, 1.0 - 0.07 * hit_flash, 1.0 + 0.05 * hit_flash)
	model.scale = squash * MODEL_SCALE * float(stats["body_scale"])
	if hit_flash <= 0.0:
		_restore_overlay()


## Camuflagem: parado por CAMO_DELAY some da vista dos outros (o próprio jogador vê a
## tela escurecer nas bordas pelo HUD). Atirar ou levar dano revela (reveal).
func _update_camo(delta: float) -> void:
	if ambush_timer > 0.0:
		ambush_timer -= delta
		if ambush_timer <= 0.0:
			_restore_overlay()
	if stats["camo"] <= 0 or not alive:
		still_time = 0.0
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var still := velocity.length() < 0.6
	var sneaking := is_hidden() and hspeed <= float(stats["move_speed"]) * CAMO_SNEAK and absf(velocity.y) < 2.0
	if (still or sneaking) and not is_shielding():
		still_time += delta
	elif still_time > 0.0:
		reveal()
	if model and alive:
		var show := not is_hidden() or (viewer != null and viewer.is_ally(self))
		model.visible = show
		ring.visible = show
		tag.visible = show


## Fogo e som do jato da Bota Foguete, em todas as máquinas (as outras sabem pelo estado).
func _update_boot_fx() -> void:
	if not boosting and boot_fx == null:
		return
	if boot_fx == null:
		boot_fx = AreaField.flame_particles()
		boot_fx.amount = 12 if GameState.quality == 0 else 24
		boot_fx.lifetime = 0.3
		boot_fx.local_coords = false
		boot_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		boot_fx.emission_sphere_radius = 0.15
		boot_fx.direction = Vector3.DOWN
		boot_fx.spread = 20.0
		boot_fx.gravity = Vector3.ZERO
		boot_fx.initial_velocity_min = 4.0
		boot_fx.initial_velocity_max = 7.0
		boot_fx.scale_amount_min = 0.4
		boot_fx.scale_amount_max = 0.8
		boot_fx.position.y = 0.1
		add_child(boot_fx)
	if boosting and not boot_fx.emitting:
		Sfx.at(self, "dash", global_position)
	boot_fx.emitting = boosting


func is_hidden() -> bool:
	return still_time > CAMO_DELAY


func reveal() -> void:
	if is_local and alive and stats["camo"] > 0 and ambush_cd <= 0.0 \
			and still_time >= CAMO_DELAY + AMBUSH_MIN_HIDDEN:
		ambush_cd = AMBUSH_COOLDOWN
		if Net.online:
			_net_ambush.rpc()
		_start_ambush()
	still_time = 0.0


@rpc("authority", "call_remote", "reliable")
func _net_ambush() -> void:
	_start_ambush()


## Emboscada: o bônus vale na máquina dona (dano do tiro e velocidade); em todas, o modelo
## ganha um contorno roxo, para quem leva o ataque entender o que aconteceu.
func _start_ambush() -> void:
	ambush_timer = AMBUSH_TIME
	Effects.burst(get_parent(), chest(), 1.4, AMBUSH_COLOR, 0.25)
	if is_human:
		Sfx.ui(self, "dash")
	if model == null:
		return
	if ambush_mat == null:
		# O mesmo contorno do aliado, mas atrás das paredes não aparece (o do aliado
		# aparece de propósito; aqui entregaria a posição de quem atacou).
		if _ambush_shader == null:
			_ambush_shader = Shader.new()
			_ambush_shader.code = ALLY_RIM_SHADER.replace("depth_test_disabled, ", "")
		ambush_mat = ShaderMaterial.new()
		ambush_mat.shader = _ambush_shader
		ambush_mat.set_shader_parameter("rim_color", Color(AMBUSH_COLOR, 0.8))
	if hit_flash <= 0.0:
		for m in body_meshes:
			m.material_overlay = ambush_mat


## Camada por cima do modelo quando nada pisca: roxo na Emboscada, contorno de aliado ou nada.
func _restore_overlay() -> void:
	if model == null or hit_flash > 0.0:
		return
	var mat: Material = ambush_mat if ambush_timer > 0.0 else (ally_mat if _ally_look else null)
	for m in body_meshes:
		m.material_overlay = mat


## Câmera: abaixa ao agachar, afunda ao pousar, inclina de leve no deslize, abre o FOV
## com a velocidade, dá o coice do tiro e treme ao levar dano. A arma balança com o
## passo e atrasa com o mouse.
func _camera_feel(delta: float) -> void:
	eye_dip = move_toward(eye_dip, 0.0, delta * 1.2)
	var size := 1.0 + (float(stats["body_scale"]) - 1.0) * EYE_SIZE_FOLLOW
	var eye := (DOWN_EYE if downed else (CROUCH_EYE if crouching else STAND_EYE)) * size - eye_dip
	if size > 1.0:
		eye = minf(eye, _ceiling_room(eye))
	head.position.y = lerpf(head.position.y, eye, minf(1.0, delta * 14.0))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var fov := BASE_FOV + clampf((hspeed - 9.0) / 10.0, 0.0, 1.0) * SPEED_FOV
	if scoping:
		fov = SCOPE_FOV
	camera.fov = lerpf(camera.fov, fov, minf(1.0, delta * (18.0 if scoping else 6.0)))
	if viewmodel:
		viewmodel.visible = not downed and not scoping and ice_timer <= 0.0 and ride_timer <= 0.0
	var roll := -in_move.x * 0.012 + (0.04 if sliding else 0.0)
	cam_roll = lerpf(cam_roll, roll, minf(1.0, delta * 8.0))
	recoil = move_toward(recoil, 0.0, delta * 6.0)
	shake = move_toward(shake, 0.0, delta * 2.5)
	_place_camera()
	if viewmodel:
		var grounded := is_on_floor() and not sliding
		if grounded and hspeed > 1.0:
			bob_time += delta * hspeed * 1.3
		var bob := Vector3(sin(bob_time) * 0.012, -absf(cos(bob_time)) * 0.014, 0.0) * minf(hspeed / 9.0, 1.0)
		sway = sway.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
		viewmodel.position = VIEWMODEL_POS + bob + Vector3(sway.x, sway.y, recoil * 0.07)
		viewmodel.rotation = Vector3(recoil * 0.25, 0.0, 0.0)


## Gigante embaixo de laje: a câmera para um pouco abaixo do teto em vez de entrar nele
## (a colisão do corpo não cresce com o tamanho, só o modelo e a área de acerto).
func _ceiling_room(eye: float) -> float:
	var from := global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.UP * (eye + 0.25), 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return eye if hit.is_empty() else maxf(1.0, hit["position"].y - global_position.y - 0.25)


## Põe a câmera na posição interpolada do corpo, com a mira atual do mouse.
func _place_camera() -> void:
	if ice_timer > 0.0 and is_human:
		_place_ice_camera()
		return
	var yaw := look_yaw if brain == null else rotation.y
	var origin := get_global_transform_interpolated().origin + Vector3(0, head.position.y, 0)
	var jitter := Vector3.ZERO
	if shake > 0.0:
		jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.06
	var euler := Vector3(head.rotation.x + recoil * RECOIL_KICK + jitter.y, yaw + jitter.x, cam_roll)
	camera.global_transform = Transform3D(Basis.from_euler(euler), origin)


# ---------------------------------------------------------------- simulação

func _physics_process(delta: float) -> void:
	if not is_local:
		_follow_network(delta)
		if downed:
			_update_down(delta)
		return
	if brain:
		brain.think(delta)
	elif is_human:
		_read_local_input()
		rotation.y = look_yaw
	_tick(delta)
	if downed:
		_downed_move(delta)
		_update_down(delta)
		_send_state()
		return
	if not alive:
		return
	if frozen:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY_FALL * delta
		if global_position.y < Arena.VOID_Y:
			velocity.y = maxf(velocity.y, 0.0)   # rodada parada: fica no vazio, sem cair sem fim
		move_and_slide()
		_send_state()
		return
	if ice_timer > 0.0:
		_ice_move(delta)
		_send_state()
		return
	if ride_timer > 0.0:
		_ride_step(delta)
		_send_state()
		return
	if beam_charge > 0.0 or beam_timer > 0.0:
		_beam_step(delta)
		if beam_timer > 0.0:
			_send_state()
			return
		in_jump = false
		in_dash = false
	_update_crouch()
	_move(delta)
	_act(delta)
	var fall_speed := velocity.y
	var before_h := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if slap_flight > 0.0:
		_check_splat(before_h, delta)
	_check_wall()
	if is_on_floor() and not was_on_floor:
		_on_landed(fall_speed)
	was_on_floor = is_on_floor()
	if stats["stomp"] > 0:
		_check_stomp(fall_speed)
	if global_position.y < Arena.VOID_Y and velocity.y <= 0.0:
		_void_bounce()
	_shove_ice_blocks()
	_send_state()


func _tick(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	shield_timer = maxf(0.0, shield_timer - delta)
	shield_cd = maxf(0.0, shield_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	master_cd = maxf(0.0, master_cd - delta)
	if chaos and is_local and alive:
		_chaos_tick(delta)
	speed_orb_timer = maxf(0.0, speed_orb_timer - delta)
	daze_timer = maxf(0.0, daze_timer - delta)
	plat_mode = maxf(0.0, plat_mode - delta)
	if meteor_window > 0.0:
		meteor_window -= delta
		if meteor_window <= 0.0:
			meteor_left = 0   # o que sobrou se perde
	if bazooka_timer > 0.0:
		bazooka_timer -= delta
		if bazooka_timer <= 0.0 or (rockets_left <= 0 and fire_timer <= 0.0):
			bazooka_timer = 0.0
			_show_bazooka(false)
	if shrink_timer > 0.0:
		shrink_timer -= delta
		if shrink_timer <= 0.0:
			shrink_timer = 0.001
			_end_shrink(true)
	if sword_timer > 0.0:
		sword_timer -= delta
		thrust_timer = maxf(0.0, thrust_timer - delta)
		combo_idle -= delta
		if combo_idle <= 0.0:
			combo_step = 0
		if sword_timer <= 0.0:
			sword_timer = 0.0
			thrust_timer = 0.0
			_show_weapon(0)
	if sniper_timer > 0.0:
		sniper_timer -= delta
		if sniper_timer <= 0.0 or (sniper_shots <= 0 and fire_timer <= 0.0):
			sniper_timer = 0.0
			scoping = false
			_show_weapon(0)
	scoping = sniper_timer > 0.0 and sniper_shots > 0 and in_aim and alive
	if last_stand_timer > 0.0:
		last_stand_timer -= delta
		if last_stand_timer <= 0.0 and alive:
			_lethal()   # ninguém abatido a tempo
	heal_cd = maxf(0.0, heal_cd - delta)
	armor_cd = maxf(0.0, armor_cd - delta)
	protect_timer = maxf(0.0, protect_timer - delta)
	ambush_cd = maxf(0.0, ambush_cd - delta)
	for bit in area_cd:
		area_cd[bit] = maxf(0.0, area_cd[bit] - delta)
	swap_lock = maxf(0.0, swap_lock - delta)
	if swap_timer > 0.0:
		swap_timer -= delta
		if swap_timer <= 0.0:
			_finish_swap()
	dodge_timer = maxf(0.0, dodge_timer - delta)
	slide_cd = maxf(0.0, slide_cd - delta)
	mantle_cd = maxf(0.0, mantle_cd - delta)
	coyote = maxf(0.0, coyote - delta)
	wall_time = maxf(0.0, wall_time - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	slow_timer = maxf(0.0, slow_timer - delta)
	silence_timer = maxf(0.0, silence_timer - delta)
	bloodlust_timer = maxf(0.0, bloodlust_timer - delta)
	blind_timer = maxf(0.0, blind_timer - delta)
	since_damage += delta
	if echo_timer > 0.0:
		echo_timer -= delta
		if echo_timer <= 0.0 and alive and silence_timer <= 0.0:
			shield_timer = stats["shield_duration"]
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			ammo = stats["mag_size"]
	if not alive:
		return
	for p in poisons:
		p["time"] -= delta
		take_damage(p["dps"] * delta, p["from"], false)
	poisons = poisons.filter(func(p): return p["time"] > 0.0)
	if burn_timer > 0.0:
		burn_timer -= delta
		burn_acc += burn_dps * delta
		if burn_acc >= BURN_CHUNK or burn_timer <= 0.0:
			var who := burn_from if is_instance_valid(burn_from) else null
			var amount := burn_acc
			burn_acc = 0.0
			take_damage(amount, who)
	if stats["regen"] > 0.0 and since_damage > REGEN_DELAY:
		heal(stats["regen"] * delta)


func _target_speed() -> float:
	var speed: float = stats["move_speed"]
	if crouching and not sliding:
		speed *= CROUCH_SPEED_MULT
	if slow_timer > 0.0:
		speed *= 1.0 - slow_amount
	if bloodlust_timer > 0.0:
		speed *= 1.0 + stats["bloodlust"]
	if ambush_timer > 0.0:
		speed *= 1.0 + AMBUSH_SPEED
	if speed_orb_timer > 0.0:
		speed *= 1.0 + SPEED_ORB
	if beam_charge > 0.0:
		speed *= BEAM_CHARGE_SPEED
	if scoping:
		speed *= SCOPE_SPEED
	if shrink_timer > 0.0:
		speed *= 1.0 + SHRINK_SPEED
	if stats["chase"] > 0.0 and _toward_enemy():
		speed *= 1.0 + stats["chase"]
	return speed


## Caçador: andando na direção de algum inimigo (até 45 graus de desvio)?
func _toward_enemy() -> bool:
	var wish := _wish_dir()
	if wish == Vector3.ZERO:
		return false
	for enemy in enemies():
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1 and wish.normalized().dot(to.normalized()) > 0.7:
			return true
	return false


func _wish_dir() -> Vector3:
	var wish := global_transform.basis * Vector3(in_move.x, 0.0, -in_move.y)
	wish.y = 0.0
	return wish.limit_length(1.0)


func _update_crouch() -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if in_crouch and not crouching:
		crouching = true
		_set_height(CROUCH_HEIGHT)
		if stats["ground_slam"] > 0 and not is_on_floor() and head.rotation.x < SLAM_LOOK 				and _height_above_ground() > SLAM_MIN_HEIGHT:
			slamming = true
			velocity = Vector3(velocity.x * 0.3, -SLAM_SPEED, velocity.z * 0.3)
		if is_on_floor() and hspeed > SLIDE_MIN_SPEED and slide_cd <= 0.0:
			_start_slide(true)
	elif not in_crouch and crouching and _can_stand():
		crouching = false
		sliding = false
		_set_height(STAND_HEIGHT)
	if sliding and (hspeed < SLIDE_STOP_SPEED or not crouching):
		sliding = false


func _start_slide(boost: bool) -> void:
	sliding = true
	slide_cd = SLIDE_COOLDOWN
	if boost:
		var h := Vector3(velocity.x, 0.0, velocity.z)
		var add := h.normalized() * SLIDE_BOOST * float(stats["slide_boost"])
		velocity.x += add.x
		velocity.z += add.z


func _can_stand() -> bool:
	return not test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT))


func _height_above_ground() -> float:
	var from := global_position + Vector3.UP * 0.1
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 50.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return 50.0 if hit.is_empty() else from.y - hit["position"].y


## Meteoro: o impacto fere e empurra quem estiver perto.
func _slam_impact() -> void:
	slamming = false
	eye_dip = 0.35
	shake = maxf(shake, 0.6)
	Effects.burst(get_parent(), global_position + Vector3.UP * 0.3, SLAM_RANGE, Color(1.0, 0.55, 0.2))
	Sfx.at(self, "explosion", global_position)
	for enemy in enemies():
		if global_position.distance_to(enemy.global_position) < SLAM_RANGE:
			enemy.remote_call("receive_shockwave",
				[global_position, SLAM_DAMAGE * stats["ground_slam"], String(name)])


func _on_landed(fall_speed: float) -> void:
	if slamming:
		_slam_impact()
	if fall_speed < -9.0:
		eye_dip = clampf(-fall_speed * 0.01, 0.0, 0.3)
	# Agachado ao pousar com embalo vira deslize, sem precisar soltar e apertar de novo.
	if crouching and not sliding and Vector2(velocity.x, velocity.z).length() > SLIDE_MIN_SPEED:
		_start_slide(false)


func _move(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		coyote = COYOTE_TIME
		boot_fuel = BOOT_FUEL
		boot_armed = false
		air_time = 0.0
		jumps_left = stats["extra_jumps"]
		wall_jumps_left = stats["wall_jumps"]
		if dash_timer <= 0.0:
			air_dashes_left = stats["air_dashes"]
	if in_jump:
		jump_buffer = JUMP_BUFFER

	var wish := _wish_dir()
	var target := _target_speed()
	var h := Vector3(velocity.x, 0.0, velocity.z)

	var jumped := false
	if jump_buffer > 0.0:
		if on_floor or coyote > 0.0:
			jumped = true
		elif wall_time > 0.0 and wall_jumps_left > 0:
			# Empurrando contra a parede (ou sem tecla) sobe rente a ela; para outro lado, salta longe.
			wall_jumps_left -= 1
			wall_time = 0.0
			var climb := wish == Vector3.ZERO or wish.normalized().dot(-wall_normal) > 0.3
			h = h - wall_normal * h.dot(wall_normal) + wall_normal * (WALL_CLIMB_PUSH if climb else WALL_JUMP_PUSH)
			jumped = true
		elif jumps_left > 0:
			jumps_left -= 1
			# O pulo no ar deixa trocar de direção sem perder velocidade.
			if wish != Vector3.ZERO:
				h = wish.normalized() * maxf(h.length(), target)
			jumped = true
		elif plat_mode > 0.0 and plat_left > 0:
			# Plataformas Suspensas: plataforma sob os pés e pula dela.
			_make_platform()
			if wish != Vector3.ZERO:
				h = wish.normalized() * maxf(h.length(), target)
			jumped = true
	# Bota Foguete: o aperto que não virou pulo (sem pulos sobrando) arma o jato.
	if stats["rocket_boots"] > 0 and in_jump and not jumped and not on_floor:
		boot_armed = true
	if jumped:
		velocity.y = stats["jump_velocity"]
		jump_buffer = 0.0
		coyote = 0.0
		jump_rising = true
		sliding = false
		slamming = false
		on_floor = false
	elif not on_floor and _try_mantle(wish):
		h = Vector3(velocity.x, 0.0, velocity.z)

	if in_dash and not slamming and dash_cd <= 0.0 and dash_timer <= 0.0:
		if on_floor and wish != Vector3.ZERO:
			_start_dash(wish, h, target, false)
		elif not on_floor and air_dashes_left > 0:
			air_dashes_left -= 1
			_start_dash(wish, h, target, true)

	var dashing := dash_timer > 0.0
	dash_timer = maxf(0.0, dash_timer - delta)
	if dashing and dash_timer <= 0.0:
		_end_dash()
		h = Vector3(velocity.x, 0.0, velocity.z)
	elif dashing:
		h = dash_dir * DASH_SPEED
		if dash_air:
			velocity.y = 0.0
		_dash_hits()
	elif on_floor and sliding:
		h = _friction(h, SLIDE_FRICTION, delta)
		# Ladeira abaixo o deslize ganha velocidade.
		var n := get_floor_normal()
		var down := Vector3.DOWN * GRAVITY_FALL
		var along := down - n * down.dot(n)
		h += Vector3(along.x, 0.0, along.z) * delta
		h = _accelerate(h, wish, 3.0, 4.0, delta)
	elif on_floor:
		h = _friction(h, FRICTION, delta)
		h = _accelerate(h, wish, target, GROUND_ACCEL, delta)
	elif glided and wish != Vector3.ZERO and h.length() > 1.0:
		# Depois de planar: gira para onde a pessoa aponta, mantendo a velocidade.
		var turn := h.signed_angle_to(wish, Vector3.UP)
		var speed := maxf(h.length(), move_toward(h.length(), target * wish.length(), AIR_ACCEL * target * delta))
		h = h.rotated(Vector3.UP, clampf(turn, -GLIDE_TURN * delta, GLIDE_TURN * delta)).normalized() * speed
	else:
		h = _accelerate(h, wish, target, AIR_ACCEL * float(stats["air_control"]), delta)
	if on_floor:
		glided = false
	h = h.limit_length(MAX_HSPEED)
	velocity.x = h.x
	velocity.z = h.z

	# Soltar o pulo cedo corta a subida: toque curto = pulo baixo.
	if jump_rising and velocity.y > 0.0 and not in_jump_held:
		velocity.y *= JUMP_CUT
		jump_rising = false
	if velocity.y <= 0.0:
		jump_rising = false
	var was_boosting := boosting
	boosting = false
	if not on_floor:
		air_time += delta
		if boot_armed and in_jump_held and boot_fuel > 0.0 and not slamming and dash_timer <= 0.0:
			boosting = true
			boot_fuel = maxf(0.0, boot_fuel - delta)
			jump_rising = false
			if velocity.y < BOOT_MAX_UP:
				velocity.y = minf(velocity.y + BOOT_THRUST * delta, BOOT_MAX_UP)
		elif not in_jump_held:
			boot_armed = false   # soltou: o próximo toque arma de novo
		if not (dash_timer > 0.0 and dash_air):
			velocity.y = maxf(velocity.y - _gravity() * delta, -MAX_FALL_SPEED)
		if stats["glide"] > 0 and in_jump_held and not boosting and not slamming and velocity.y < -GLIDE_FALL:
			velocity.y = move_toward(velocity.y, -GLIDE_FALL, 60.0 * delta)
			glided = true


## Pulo na parede: lembra a última parede tocada no ar (jogadores não contam como parede).
func _check_wall() -> void:
	if is_on_floor():
		wall_time = 0.0
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) < 0.35 and c.get_collider() is not Player:
			wall_normal = Vector3(n.x, 0.0, n.z).normalized()
			wall_time = WALL_GRACE
			return


## Dash: tiro curto e reto na direção em que anda (ou para a frente, sem tecla).
func _start_dash(wish: Vector3, h: Vector3, target: float, air: bool) -> void:
	dash_dir = wish.normalized() if wish != Vector3.ZERO else _flat_forward()
	dash_timer = DASH_TIME * float(stats["dash_power"])
	dash_cd = stats["dash_cooldown"]
	dash_air = air
	dash_exit = maxf(h.length(), target * DASH_EXIT)
	dash_hits.clear()
	jump_rising = false
	if stats["dash_dodge"] > 0:
		dodge_timer = DODGE_TIME
	if stats["dash_ammo"] > 0 and reload_timer <= 0.0:
		ammo = mini(stats["mag_size"], ammo + int(stats["dash_ammo"]))
	if is_human:
		Sfx.ui(self, "dash")
	reveal()


## Fim do dash: sobra a velocidade de saída, e se o Ctrl ainda está seguro no chão, desliza.
func _end_dash() -> void:
	var speed := dash_exit
	if not dash_air and crouching and is_on_floor():
		speed += SLIDE_BOOST * float(stats["slide_boost"])
		sliding = true
		slide_cd = SLIDE_COOLDOWN
	velocity.x = dash_dir.x * speed
	velocity.z = dash_dir.z * speed
	dash_air = false


## Atropelar: o dash fere e empurra quem estiver no caminho (uma vez por dash).
func _dash_hits() -> void:
	if stats["dash_hit"] <= 0.0:
		return
	for enemy in enemies():
		if enemy in dash_hits or chest().distance_to(enemy.chest()) > DASH_HIT_RANGE:
			continue
		dash_hits.append(enemy)
		enemy.remote_call("receive_shockwave", [global_position, float(stats["dash_hit"]), String(name)])
		Effects.burst(get_parent(), enemy.chest(), 1.2, Color(1.0, 0.8, 0.3), 0.2)


## Pisão: os pés na altura da cabeça de um inimigo, caindo ou no dash pelo ar. Vale também
## quem pousou em cima dele (a colisão entre jogadores segura os pés ali).
func _check_stomp(fall_speed: float) -> void:
	var air_dash := dash_timer > 0.0 and dash_air
	if is_on_floor() and not _standing_on_player():
		return
	if fall_speed > 0.5 and not air_dash:
		return
	var now := Time.get_ticks_msec()
	var my_scale: float = stats["body_scale"]
	for enemy in enemies():
		if now - int(stomp_hits.get(enemy, -100000)) < STOMP_REPEAT * 1000.0:
			continue
		var their_scale: float = enemy.stats["body_scale"]
		var top: float = enemy.global_position.y + enemy.height * their_scale
		var dy := global_position.y - top
		var flat := Vector2(global_position.x - enemy.global_position.x, global_position.z - enemy.global_position.z).length()
		var reach := RADIUS * (my_scale + their_scale) * (1.4 if air_dash else 1.1)
		var low := -0.8 * their_scale if air_dash else -0.4 * their_scale
		if flat < reach and dy > low and dy < 0.35:
			_stomp(enemy, now)
			return


func _standing_on_player() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is Player and c.get_normal().y > 0.5:
			return true
	return false


func _stomp(enemy: Player, now: int) -> void:
	stomp_hits[enemy] = now
	var dmg := STOMP_DAMAGE + STOMP_DAMAGE_STEP * (int(stats["stomp"]) - 1)
	enemy.remote_call("receive_stomp", [dmg, String(name)])
	velocity.y = STOMP_BOUNCE
	jump_rising = false
	slamming = false
	if dash_timer > 0.0 and dash_air:
		dash_timer = 0.0
		_end_dash()
	# Devolve o dash e os pulos no ar, como tocar o chão (escolha do usuário).
	air_dashes_left = stats["air_dashes"]
	jumps_left = stats["extra_jumps"]
	wall_jumps_left = stats["wall_jumps"]
	boot_fuel = BOOT_FUEL
	dash_cd = 0.0
	eye_dip = 0.2
	var head_pos := enemy.global_position + Vector3.UP * enemy.height * float(enemy.stats["body_scale"])
	Effects.burst(get_parent(), head_pos, 1.2, Color(1.0, 0.85, 0.3), 0.2)
	Sfx.at(self, "hit", head_pos)
	reveal()


## Levou um pisão: dano e um tranco para baixo.
func receive_stomp(dmg: float, from_name: String) -> void:
	velocity.y = minf(velocity.y, -6.0)
	jump_rising = false
	take_damage(dmg, get_parent().get_node_or_null(from_name) as Player)


## Bateu no vazio: quica e leva dano, ou, com o escudo de pé, quica alto sem dano. O
## quique devolve os pulos e dashes no ar, como tocar o chão, para dar chance de voltar.
func _void_bounce() -> void:
	var saved := is_shielding()
	global_position.y = Arena.VOID_Y
	velocity.y = VOID_BOUNCE_SHIELD if saved else VOID_BOUNCE
	jump_rising = false
	slamming = false
	sliding = false
	air_dashes_left = stats["air_dashes"]
	jumps_left = stats["extra_jumps"]
	wall_jumps_left = stats["wall_jumps"]
	boot_fuel = BOOT_FUEL
	eye_dip = 0.25
	var feet := global_position + Vector3.UP * 0.2
	if saved:
		reflect_flash = 1.0
		Effects.burst(get_parent(), feet, 3.0, Color(0.5, 0.9, 1.0), 0.3)
		Sfx.at(self, "reflect", feet)
	else:
		Effects.burst(get_parent(), feet, 2.0, Color(0.7, 0.35, 1.0), 0.3)
		var who := last_attacker if since_damage < VOID_CREDIT and is_instance_valid(last_attacker) else null
		if ice_timer > 0.0:
			# Congelado: o dano vem quando o gelo derrete, uma vez só (o bloco não sai do
			# vazio sozinho e quicaria várias vezes no mesmo lugar).
			ice_debt = VOID_DAMAGE
		else:
			take_damage(VOID_DAMAGE, who)
	void_bounced.emit(saved)


## Orbe de movimento: devolve os dashes no ar, zera a recarga e dá ao menos um pulo no ar.
func refresh_movement() -> void:
	boot_fuel = BOOT_FUEL
	air_dashes_left = stats["air_dashes"]
	dash_cd = 0.0
	jumps_left = maxi(jumps_left, maxi(int(stats["extra_jumps"]), 1))
	wall_jumps_left = stats["wall_jumps"]
	Effects.burst(get_parent(), chest(), 1.0, Pickup.COLORS[Pickup.Kind.LAUNCH], 0.2)


## Orbe de Velocidade: +SPEED_ORB de velocidade por SPEED_ORB_TIME segundos.
func speed_boost() -> void:
	speed_orb_timer = SPEED_ORB_TIME
	Effects.burst(get_parent(), chest(), 1.0, Pickup.COLORS[Pickup.Kind.SPEED], 0.2)


## Orbe de Impulso: para cima sem perder o embalo de lado, e o movimento no ar renovado.
func launch_up() -> void:
	if not is_local:
		return
	refresh_movement()
	velocity.y = maxf(velocity.y, LAUNCH_ORB_SPEED)
	jump_rising = false
	coyote = 0.0
	sliding = false


func is_dodging() -> bool:
	return dodge_timer > 0.0


func _gravity() -> float:
	var g := GRAVITY_RISE if velocity.y > 0.0 else GRAVITY_FALL
	if absf(velocity.y) < APEX_SPEED and in_jump_held:
		g *= APEX_GRAVITY
	return g * float(stats["gravity_mult"])


## Escalada de beirada (como em Apex e Titanfall): no ar, empurrando contra uma parede
## cujo topo está ao alcance, o jogador sobe por cima dela.
func _try_mantle(wish: Vector3) -> bool:
	if mantle_cd > 0.0 or velocity.y > 3.0 or wish == Vector3.ZERO or not is_on_wall():
		return false
	var n := get_wall_normal()
	n.y = 0.0
	if n.length() < 0.5:
		return false
	var forward := -n.normalized()
	if wish.normalized().dot(forward) < 0.5:
		return false
	var space := get_world_3d().direct_space_state
	var top := global_position + forward * (RADIUS + 0.35) + Vector3.UP * (MANTLE_REACH + 0.3)
	var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (MANTLE_REACH + 0.3), 1, [get_rid()])
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit["normal"].y < 0.7:
		return false
	var rise: float = hit["position"].y - global_position.y
	if rise < 0.3 or rise > MANTLE_REACH:
		return false
	# Precisa caber em cima da beirada.
	var room := PhysicsShapeQueryParameters3D.new()
	room.shape = capsule
	room.collision_mask = 1
	room.transform = Transform3D(Basis(), hit["position"] + Vector3.UP * (height / 2.0 + 0.05))
	if not space.intersect_shape(room, 1).is_empty():
		return false
	velocity.y = sqrt(2.0 * GRAVITY_RISE * (rise + 0.3))
	var keep := maxf(Vector3(velocity.x, 0.0, velocity.z).dot(forward), 4.0)
	velocity.x = forward.x * keep
	velocity.z = forward.z * keep
	mantle_cd = 0.5
	jump_rising = false
	return true


## Aceleração no estilo Quake: só acelera até a velocidade alvo na direção desejada,
## sem frear o que já passa dela. É isso que preserva o embalo de deslizes e pulos.
func _accelerate(h: Vector3, wish: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	if wish == Vector3.ZERO:
		return h
	var dir := wish.normalized()
	var speed := wish_speed * wish.length()
	var add := speed - h.dot(dir)
	if add <= 0.0:
		return h
	return h + dir * minf(accel * speed * delta, add)


func _friction(h: Vector3, friction: float, delta: float) -> Vector3:
	var speed := h.length()
	if speed < 0.01:
		return Vector3.ZERO
	var drop := maxf(speed, STOP_SPEED) * friction * delta
	return h * maxf(speed - drop, 0.0) / speed


func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	return Vector3(f.x, 0.0, f.z).normalized()


## Usado por plataformas de salto, explosões e empurrões.
func launch(v: Vector3) -> void:
	if not is_local:
		return
	velocity = Vector3(velocity.x * 0.5 + v.x, v.y, velocity.z * 0.5 + v.z)
	jump_rising = false
	coyote = 0.0
	sliding = false


func knockback(v: Vector3) -> void:
	velocity += v
	jump_rising = false


# ---------------------------------------------------------------- rede

## Manda o estado deste jogador para a outra máquina, a cada quadro de física.
func _send_state() -> void:
	if not Net.online or not Net.all_ready():
		return
	var flags := (1 if is_on_floor() else 0) | (2 if crouching else 0) | (4 if sliding else 0) \
		| (8 if boosting else 0)
	_net_state.rpc(net_round, global_position, velocity, rotation.y, head.rotation.x, flags, shield_timer, health, armor)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(round_id: int, pos: Vector3, vel: Vector3, yaw: float, pitch: float,
		flags: int, shield: float, hp: float, vest: float) -> void:
	if round_id != net_round:
		return   # pacote atrasado da rodada anterior
	if hp < health - 1.0:
		flash_hit()   # levou dano na máquina dele (o veneno tira menos que isso por pacote)
	net_pos = pos
	velocity = vel
	net_yaw = yaw
	net_pitch = pitch
	shield_timer = shield
	health = hp
	armor = vest
	net_on_floor = (flags & 1) != 0
	boosting = (flags & 8) != 0
	sliding = (flags & 4) != 0
	var crouch := (flags & 2) != 0
	if crouch != crouching:
		crouching = crouch
		_set_height(CROUCH_HEIGHT if crouch else STAND_HEIGHT)


func _follow_network(delta: float) -> void:
	shield_timer = maxf(0.0, shield_timer - delta)
	if global_position.distance_to(net_pos) > 4.0:
		global_position = net_pos
		reset_physics_interpolation()
	else:
		global_position = global_position.lerp(net_pos, minf(1.0, delta * 18.0))
	rotation.y = lerp_angle(rotation.y, net_yaw, minf(1.0, delta * 20.0))
	head.rotation.x = lerpf(head.rotation.x, net_pitch, minf(1.0, delta * 20.0))


## Chama um método no dono deste jogador: direto se ele é desta máquina, pela rede se não.
func remote_call(method: String, args: Array = []) -> void:
	if is_local:
		callv(method, args)
	else:
		_net_call.rpc_id(peer_id, method, args)


@rpc("any_peer", "call_remote", "reliable")
func _net_call(method: String, args: Array) -> void:
	if method in REMOTE_METHODS and is_local:
		callv(method, args)


## power: força do empurrão (1 = Onda de Choque, Pancada, Meteoro; a Formiga empurra mais).
func receive_shockwave(from_pos: Vector3, dmg: float, from_name: String, power := 1.0) -> void:
	var push := global_position - from_pos
	push.y = 0.0
	knockback(push.normalized() * 14.0 * power + Vector3.UP * 5.0 * power)
	take_damage(dmg, get_parent().get_node_or_null(from_name) as Player)


## Troca-Troca (e Teleporte): vai direto para o ponto, sem interpolar o caminho.
func teleport_to(pos: Vector3) -> void:
	global_position = pos
	net_pos = pos
	reset_physics_interpolation()
	if is_human:
		_place_camera()


## Quem causou dano recebe o crédito: roubo de vida, Sede de Sangue e o som de acerto.
func credit_damage(amount: float, lethal := false) -> void:
	if not alive:
		return
	if stats["lifesteal"] > 0.0:
		heal(amount * stats["lifesteal"])
	if stats["bloodlust"] > 0.0:
		bloodlust_timer = BLOODLUST_TIME
	if stats["hit_dash"] > 0:
		dash_cd = 0.0
		air_dashes_left = mini(air_dashes_left + 1, stats["air_dashes"])
	if lethal and last_stand_timer > 0.0:
		# Último Suspiro: abateu alguém a tempo, volta com metade da vida.
		last_stand_timer = 0.0
		health = maxf(health, stats["max_health"] * 0.5)
		Effects.burst(get_parent(), chest(), 3.0, Color(0.5, 0.95, 0.5))
		revived.emit()
	damage_dealt.emit(amount, lethal)
	# Um som por quadro: os chumbos de uma escopeta soam como um acerto só.
	if is_human and (lethal or _hit_sound_frame != Engine.get_physics_frames()):
		_hit_sound_frame = Engine.get_physics_frames()
		Sfx.ui(self, "kill" if lethal else "hitmarker")


# ---------------------------------------------------------------- combate

func _act(delta: float) -> void:
	if ride_timer > 0.0:
		return   # montado: o Q (saltar) é tratado em _ride_step
	if in_master and shrink_timer > 0.0:
		_end_shrink(true)   # Formiga: Q de novo volta ao tamanho antes do tempo
	elif in_master and master_cd <= 0.0 and master_id != "" and CardDB.CARDS[master_id].has("cooldown") \
			and not (stats["platforms"] > 0 and is_on_floor()):
		_use_master()
	if in_shield and shield_cd <= 0.0 and silence_timer <= 0.0:
		_activate_shield()
	_shield_bash()
	shot_queued = maxf(0.0, shot_queued - delta)
	if daze_timer > 0.0 or beam_charge > 0.0 or beam_timer > 0.0:
		shot_queued = 0.0
		shoot_was = in_shoot
		return
	if in_click or (in_shoot and not shoot_was):
		shot_queued = SHOT_BUFFER
	shoot_was = in_shoot
	var trigger: bool = shot_queued > 0.0 or (in_shoot and stats["auto_fire"] > 0)
	if bazooka_timer > 0.0:
		if trigger and not is_shielding() and fire_timer <= 0.0 and rockets_left > 0:
			shot_queued = 0.0
			_fire_rocket()
		return
	if sniper_timer > 0.0:
		if trigger and not is_shielding() and fire_timer <= 0.0 and sniper_shots > 0:
			shot_queued = 0.0
			_fire_sniper()
		return
	if sword_timer > 0.0:
		if thrust_timer > 0.0:
			_sword_hits(2)   # a estocada acerta quem atravessar no avanço
		if trigger and not is_shielding() and fire_timer <= 0.0:
			shot_queued = 0.0
			_swing()
		return
	if in_reload and reload_timer <= 0.0 and ammo < stats["mag_size"] and burst_left == 0:
		_start_reload()
	if burst_left > 0:
		burst_timer -= delta
		if burst_timer <= 0.0:
			burst_left -= 1
			burst_timer = BURST_GAP
			_volley()
	elif trigger and not is_shielding() and fire_timer <= 0.0 and reload_timer <= 0.0:
		shot_queued = 0.0
		if ammo > 0:
			_fire()
		else:
			_start_reload()
	if ammo == 0 and reload_timer <= 0.0 and burst_left == 0:
		_start_reload()


# ---------------------------------------------------------------- Caos

## Sorteia outra mestra (nunca o próprio Caos nem a da vez) e liga os atributos dela no
## lugar dos da anterior. Só na máquina dona; as outras recebem pelo _net_chaos.
func _chaos_draw() -> void:
	var pool := CardDB.master_ids().filter(func(id): return id != "caos" and id != master_id)
	if pool.is_empty():
		return
	var id: String = pool.pick_random()
	_chaos_set(id)
	chaos_used = false
	master_cd = 0.0
	chaos_timer = 0.0 if CardDB.CARDS[id].has("cooldown") else CHAOS_PASSIVE_TIME
	chaos_drawn.emit(id)
	if Net.online and is_inside_tree():
		_net_chaos.rpc(id)


@rpc("authority", "call_remote", "reliable")
func _net_chaos(id: String) -> void:
	if CardDB.is_master(id):
		_chaos_last = id
		if chaos:
			_chaos_set(id)


func _chaos_set(id: String) -> void:
	for m in CardDB.master_ids():
		if m == "caos":
			continue
		for mod in CardDB.CARDS[m]["mods"]:
			stats[mod["stat"]] = 0
	for mod in CardDB.CARDS[id]["mods"]:
		stats[mod["stat"]] = mod["add"]
	master_id = id


## Passiva: troca quando o tempo acaba. Ativa usada: a espera (master_cd) fica parada
## enquanto o efeito dura e, quando zera, vem a próxima.
func _chaos_tick(delta: float) -> void:
	if master_id == "":
		return
	if chaos_timer > 0.0:
		chaos_timer -= delta
		if chaos_timer <= 0.0:
			_chaos_draw()
		return
	if not chaos_used:
		return
	if bazooka_timer > 0.0 or sniper_timer > 0.0 or sword_timer > 0.0 or shrink_timer > 0.0 or pierce_left > 0 \
			or beam_timer > 0.0 or beam_charge > 0.0 or plat_mode > 0.0 or meteor_left > 0 or ride_timer > 0.0:
		master_cd = CHAOS_WAIT
	elif master_cd <= 0.0:
		_chaos_draw()


## Recarga total mostrada na HUD (com o Caos, a espera até a próxima).
func master_cd_total() -> float:
	if chaos:
		return CHAOS_WAIT
	return float(CardDB.CARDS[master_id].get("cooldown", 1.0)) if master_id != "" else 1.0


## Habilidade da carta mestra (tecla Q).
func _use_master() -> void:
	master_cd = CardDB.CARDS[master_id]["cooldown"]
	if chaos:
		master_cd = CHAOS_WAIT
		chaos_used = true
	reveal()
	if stats["updraft"] > 0:
		# Corrente: impulso reto para cima, também no ar (como o da Jett, de Valorant).
		velocity.y = maxf(velocity.y, UPDRAFT_SPEED)
		jump_rising = false
		coyote = 0.0
		sliding = false
		slamming = false
		dash_timer = 0.0
		Effects.burst(get_parent(), global_position + Vector3.UP * 0.2, 2.2, Color(0.75, 0.6, 1.0), 0.25)
		Sfx.at(self, "pad", global_position)
	if stats["bazooka"] > 0:
		bazooka_timer = BAZOOKA_TIME
		rockets_left = BAZOOKA_ROCKETS
		burst_left = 0
		fire_timer = 0.25
		_show_bazooka(true)
		Sfx.at(self, "pickup", chest())
	if stats["shrink"] > 0:
		_start_shrink()
	if stats["sword"] > 0:
		sword_timer = SWORD_TIME
		combo_step = 0
		burst_left = 0
		fire_timer = 0.2
		_show_weapon(3)
		Sfx.at(self, "pickup", chest())
	if stats["sniper"] > 0:
		sniper_timer = SNIPER_TIME
		sniper_shots = 1
		burst_left = 0
		fire_timer = SNIPER_DRAW
		_show_weapon(2)
		Sfx.at(self, "pickup", chest())
	if stats["pierce"] > 0:
		pierce_left = PIERCE_SHOTS
		Effects.burst(get_parent(), muzzle.global_position, 0.6, Bullet.PIERCE_COLOR, 0.2)
		Sfx.at(self, "pickup", chest())
	if stats["ice"] > 0:
		_fire_ice()
	if stats["slap"] > 0:
		_slap()
	if stats["beam"] > 0:
		_start_beam()
	if stats["rocket_ride"] > 0:
		_start_ride()
	if stats["meteor"] > 0:
		meteor_left = METEOR_SHOTS
		meteor_window = METEOR_WINDOW
		Effects.burst(get_parent(), muzzle.global_position, 0.6, MeteorStrike.COLOR, 0.2)
		Sfx.at(self, "pickup", chest())
	if stats["platforms"] > 0:
		plat_mode = PLAT_MODE
		plat_left = PLAT_MAX
		_make_platform()
		# Pousa na primeira: a queda para (salva do vazio).
		velocity.y = maxf(velocity.y, 0.0)
	if stats["barrier"] > 0:
		var pos := global_position + _flat_forward() * 2.5
		_make_barrier(pos, rotation.y)
		if Net.online:
			_net_barrier.rpc(pos, rotation.y)


## Bazuca montada com formas simples (o Blaster Kit não tem uma): tubo largo apontando
## para -Z como as armas do kit, bocas mais grossas, empunhadura, gatilho e mira. Medidas
## em metros; o tamanho na mão é ajustado por quem chama.
func _make_bazooka() -> Node3D:
	var root := Node3D.new()
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.32, 0.4, 0.24)
	green.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.roughness = 0.6
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.95, 0.65, 0.15)
	var tube := func(radius: float, length: float, z: float, mat: Material, y := 0.0) -> void:
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = length
		m.radial_segments = 14
		m.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.rotation.x = PI / 2.0
		mi.position = Vector3(0.0, y, z)
		root.add_child(mi)
	var box := func(size: Vector3, pos: Vector3, mat: Material, tilt := 0.0) -> void:
		var m := BoxMesh.new()
		m.size = size
		m.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = pos
		mi.rotation.x = tilt
		root.add_child(mi)
	tube.call(0.055, 0.78, -0.05, green)          # corpo
	tube.call(0.07, 0.1, -0.46, dark)             # boca da frente
	tube.call(0.072, 0.025, -0.39, stripe)        # faixa de aviso
	tube.call(0.075, 0.14, 0.36, dark)            # boca de trás (escape)
	tube.call(0.06, 0.04, 0.12, dark)             # anel do meio
	box.call(Vector3(0.035, 0.11, 0.045), Vector3(0.0, -0.1, 0.05), dark, -0.25)    # empunhadura
	box.call(Vector3(0.035, 0.09, 0.04), Vector3(0.0, -0.09, -0.2), dark, 0.2)      # apoio da frente
	box.call(Vector3(0.012, 0.04, 0.05), Vector3(0.0, -0.065, 0.0), dark)            # gatilho
	box.call(Vector3(0.02, 0.035, 0.09), Vector3(-0.06, 0.035, -0.08), dark)         # mira, de lado
	return root


func _show_bazooka(on: bool) -> void:
	_show_weapon(1 if on else 0)


## Arma na mão: 0 a de sempre, 1 Bazuca, 2 Sniper. Avisa as outras máquinas.
func _show_weapon(kind: int) -> void:
	_set_weapon(kind)
	if Net.online and is_local and is_inside_tree() and Net.all_ready():
		_net_weapon.rpc(kind)


@rpc("authority", "call_remote", "reliable")
func _net_weapon(kind: int) -> void:
	_set_weapon(kind)


func _set_weapon(kind: int) -> void:
	if gun == null:
		return
	gun.visible = kind == 0
	if bazooka:
		bazooka.visible = kind == 1
	if sniper:
		sniper.visible = kind == 2
	if sword:
		sword.visible = kind == 3


## Bastião: a parede existe em todas as máquinas; quem decide o reflexo é a do dono.
func _make_barrier(pos: Vector3, yaw: float) -> void:
	var b := Barrier.new()
	b.owner_player = self
	get_parent().add_child(b)
	b.global_position = pos
	b.rotation.y = yaw
	Sfx.at(self, "shield", pos + Vector3.UP)


@rpc("authority", "call_remote", "reliable")
func _net_barrier(pos: Vector3, yaw: float) -> void:
	_make_barrier(pos, yaw)


## Formiga: só a máquina dona decide; as outras recebem o tamanho pelo _net_shrink.
func _start_shrink() -> void:
	shrink_timer = SHRINK_TIME
	_set_shrunk(true)
	if Net.online:
		_net_shrink.rpc(true)


## Volta ao tamanho; slam: com o impacto (fim do tempo ou Q de novo), não quando cai ou morre.
func _end_shrink(slam: bool) -> void:
	if shrink_timer <= 0.0:
		return
	shrink_timer = 0.0
	_set_shrunk(false)
	if Net.online:
		_net_shrink.rpc(false)
	if slam and alive:
		for enemy in enemies():
			if global_position.distance_to(enemy.global_position) < SHRINK_SLAM_RANGE:
				enemy.remote_call("receive_shockwave", [global_position, SHRINK_SLAM_DAMAGE, String(name), SHRINK_SLAM_PUSH])


@rpc("authority", "call_remote", "reliable")
func _net_shrink(on: bool) -> void:
	_set_shrunk(on)


func _set_shrunk(on: bool) -> void:
	var was: bool = has_meta("shrunk") and get_meta("shrunk")
	if on == was:
		return
	set_meta("shrunk", on)
	stats["body_scale"] = float(stats["body_scale"]) * (SHRINK_SCALE if on else 1.0 / SHRINK_SCALE)
	_apply_body_scale()
	if on:
		Effects.burst(get_parent(), chest(), 1.0, Color(0.75, 0.6, 1.0), 0.2)
		Sfx.at(self, "dash", global_position)
	else:
		Effects.burst(get_parent(), global_position + Vector3.UP * 0.3, SHRINK_SLAM_RANGE, Color(0.75, 0.6, 1.0), 0.3)
		Sfx.at(self, "explosion", global_position)
		eye_dip = 0.3


# ---------------------------------------------------------------- espada

## Espada montada com formas simples (os pacotes da Kenney que usamos não têm uma): lâmina
## larga e longa apontando para -Z, como as armas, guarda dourada, cabo e pomo. O punho
## fica na origem; medidas em metros (lâmina de 1 m), o tamanho na mão vem de quem chama.
func _make_sword() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.86, 0.92)
	steel.metallic = 0.6
	steel.roughness = 0.3
	steel.emission_enabled = true
	steel.emission = SWORD_COLOR * 0.25   # a lâmina aparece mesmo na sombra e na qualidade Baixa
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.2)
	gold.metallic = 0.5
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.2, 0.13, 0.08)
	var part := func(mesh: PrimitiveMesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = pos
		mi.rotation = rot
		root.add_child(mi)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.11, 0.025, 1.0)
	part.call(blade, steel, Vector3(0, 0, -0.62))
	var tip := PrismMesh.new()                     # ponta triangular
	tip.size = Vector3(0.11, 0.14, 0.025)
	part.call(tip, steel, Vector3(0, 0, -1.19), Vector3(-PI / 2.0, 0, 0))
	var guard := BoxMesh.new()
	guard.size = Vector3(0.32, 0.05, 0.06)
	part.call(guard, gold, Vector3(0, 0, -0.1))
	var handle := CylinderMesh.new()
	handle.top_radius = 0.025
	handle.bottom_radius = 0.025
	handle.height = 0.2
	handle.radial_segments = 8
	part.call(handle, grip, Vector3(0, 0, 0.02), Vector3(PI / 2.0, 0, 0))
	var pommel := SphereMesh.new()
	pommel.radius = 0.04
	pommel.height = 0.08
	pommel.radial_segments = 8
	pommel.rings = 4
	part.call(pommel, gold, Vector3(0, 0, 0.13))
	return root


## Primeira pessoa: espada em repouso, inclinada para cima e para a esquerda.
func _rest_sword() -> void:
	if sword_pivot:
		sword_pivot.rotation = Vector3(0.9, -0.35, -0.35)
		sword_pivot.position = SWORD_VIEW_POS


## Um golpe do combo: decide os acertos (máquina dona), anima e avisa as outras máquinas.
func _swing() -> void:
	var step := combo_step
	combo_step = (step + 1) % 3
	combo_idle = COMBO_RESET
	fire_timer = THRUST_GAP if step == 2 else SWORD_GAP
	swing_hits.clear()
	reveal()
	if step == 2:
		# Estocada: avança como um dash curto, sem gastar o dash.
		dash_dir = _flat_forward()
		dash_timer = THRUST_DASH
		dash_air = not is_on_floor()
		dash_exit = maxf(Vector3(velocity.x, 0.0, velocity.z).length(), float(stats["move_speed"]))
		thrust_timer = THRUST_DASH + 0.05
	_sword_hits(step)
	_show_swing(step)
	if Net.online:
		_net_swing.rpc(step)


@rpc("authority", "call_remote", "reliable")
func _net_swing(step: int) -> void:
	_show_swing(step)


## Quem está no alcance e no leque do golpe (cada um uma vez por golpe).
func _sword_hits(step: int) -> void:
	var forward := _flat_forward()
	var reach := THRUST_RANGE if step == 2 else SWORD_RANGE
	var arc := deg_to_rad(THRUST_ARC if step == 2 else SWORD_ARC)
	var dmg := shot_damage() * float(SWORD_DAMAGE[step])
	for enemy in enemies():
		if enemy in swing_hits:
			continue
		var to: Vector3 = enemy.chest() - chest()
		if absf(to.y) > 2.0:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		if dist > reach + enemy.hit_radius():
			continue
		# Colado no corpo vale de qualquer ângulo; senão, só dentro do leque.
		if dist > 0.9 and forward.angle_to(flat / dist) > arc:
			continue
		swing_hits.append(enemy)
		var push := forward * (9.0 if step == 2 else 4.0)
		if step < 2:
			# Os cortes empurram para o lado do corte.
			push += forward.cross(Vector3.UP) * (3.0 if step == 0 else -3.0)
		enemy.remote_call("receive_slash", [dmg, String(name), push])
		Effects.sparks(get_parent(), enemy.chest(), SWORD_COLOR, 10, 7.0)


## Levou um golpe de espada (na máquina dona do alvo): o escudo de pé bloqueia.
func receive_slash(dmg: float, from_name: String, push: Vector3) -> void:
	if not alive:
		return
	if is_shielding():
		reflect_flash = 1.0
		Sfx.at(self, "reflect", chest())
		Effects.burst(get_parent(), chest(), 1.2, Color(0.5, 0.9, 1.0), 0.15)
		return
	knockback(push + Vector3.UP * 2.5)
	take_damage(dmg, get_parent().get_node_or_null(from_name) as Player)


## Visual do golpe: arco (ou traço, na estocada) na frente do corpo, som e animação.
func _show_swing(step: int) -> void:
	Sfx.at(self, "dash", chest())
	var forward := _flat_forward()
	var right := forward.cross(Vector3.UP)
	var center := chest() + Vector3.UP * 0.1
	# Na própria tela o golpe aparece pela espada; o rastro fica quase invisível (cheio, ele
	# cobria a tela). Para os outros, rastro do corte e traço da estocada.
	var own := is_human
	if step == 2:
		if not own:
			Effects.beam(get_parent(), center + forward * 0.6, center + forward * THRUST_RANGE, SWORD_COLOR, 0.08, 0.2)
	else:
		Effects.slash(get_parent(), center - Vector3.UP * (0.35 if own else 0.0), forward, right, SWORD_RANGE * 0.85,
			step == 0, SWORD_COLOR, 0.22, 0.35 if own else 1.0, 0.85 if own else 0.6)
	if model:
		swing_anim = 0.4
		anim.play("attack-melee-right", 0.05)
		anim.speed_scale = 1.4 if step == 2 else 1.0
	if sword_pivot and is_human:
		var t := create_tween()
		match step:
			0:   # da esquerda para a direita, lâmina deitada
				sword_pivot.rotation = Vector3(0.1, 1.1, -1.4)
				t.tween_property(sword_pivot, "rotation", Vector3(0.1, -1.2, -1.4), 0.16) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			1:   # da direita para a esquerda
				sword_pivot.rotation = Vector3(0.1, -1.2, 1.4)
				t.tween_property(sword_pivot, "rotation", Vector3(0.1, 1.1, 1.4), 0.16) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			2:   # estocada: aponta para a mira e avança
				sword_pivot.rotation = Vector3(0.05, 0.05, 0.0)
				sword_pivot.position = SWORD_VIEW_POS + Vector3(0.0, 0.0, 0.1)
				t.tween_property(sword_pivot, "position", SWORD_VIEW_POS + Vector3(-0.08, 0.04, -0.3), 0.1)
		t.tween_interval(0.12)
		t.tween_callback(_rest_sword)


## Sniper: um tiro que é um laser. Mira no que está sob a mira (atravessando o cenário: o
## raio só procura jogadores) e sai do cano nessa direção.
func _fire_sniper() -> void:
	sniper_shots -= 1
	fire_timer = 0.5   # a arma fica na mão um instante depois do tiro
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	shot_mult = 1.0
	Bullet.fire(self, muzzle.global_position, (target - muzzle.global_position).normalized(), SNIPER_DAMAGE, true,
		{"speed": SNIPER_SPEED, "gravity": 0.0, "ghost": true, "pierce": true, "laser": true, "bounces": 0,
		"split": 0, "sticky": false, "boomerang": false, "guided": false, "seek": 0.0, "homing": 0.0,
		"target_bounce": 0.0, "lazy_top": 0.0})
	recoil = 2.5
	shake = maxf(shake, 0.25)
	scoping = false
	reveal()


# ---------------------------------------------------------------- Prisão de Gelo

## Caco de gelo: reto, sem queda, sem os efeitos das cartas; congela quem acertar.
func _fire_ice() -> void:
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * ICE_RANGE, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * ICE_RANGE
	shot_mult = 1.0
	Bullet.fire(self, muzzle.global_position, (target - muzzle.global_position).normalized(), 0.0, true,
		{"speed": ICE_SPEED, "ice": true, "radius": 0.22, "gravity": 0.0, "bounces": 0, "ghost_walls": 0,
		"explosion": 0.0, "poison": 0.0, "slow": 0.0, "push": 0.0, "shield_break": false, "execute": 0.0,
		"split": 0, "sticky": false, "boomerang": false, "guided": false, "seek": 0.0, "homing": 0.0,
		"target_bounce": 0.0, "lazy_top": 0.0, "grow": 0.0, "swap": false, "blind": 0.0, "toxic": 0,
		"hole": 0, "bounce_damage": 0.0})
	Sfx.at(self, "pickup", chest())
	recoil = 1.0
	reveal()


## Na máquina dona: preso no gelo. Cancela o que estava fazendo (escudo, dash, deslize).
func freeze() -> void:
	if not alive or downed or ice_timer > 0.0:
		return
	ice_timer = ICE_TIME
	_end_beam(true)
	_ride_crash()
	froze.emit()
	shield_timer = 0.0
	dash_timer = 0.0
	sliding = false
	slamming = false
	scoping = false
	_ice_visual(true)
	if Net.online and is_inside_tree():
		_net_ice.rpc(true)


func _thaw() -> void:
	ice_timer = 0.0
	_ice_visual(false)
	if Net.online and is_inside_tree():
		_net_ice.rpc(false)
	if ice_debt > 0.0:
		var who := last_attacker if since_damage < VOID_CREDIT and is_instance_valid(last_attacker) else null
		var debt := ice_debt
		ice_debt = 0.0
		take_damage(debt, who)


@rpc("authority", "call_remote", "reliable")
func _net_ice(on: bool) -> void:
	ice_timer = ICE_TIME if on else 0.0
	_ice_visual(on)
	if on:
		froze.emit()


## Congelado: só a física. Desliza com pouco atrito, cai das beiradas, quica no vazio.
func _ice_move(delta: float) -> void:
	ice_timer -= delta
	if ice_timer <= 0.0:
		_thaw()
		return
	velocity.y -= (GRAVITY_RISE if velocity.y > 0.0 else GRAVITY_FALL) * delta
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, ICE_FRICTION * delta)
	velocity.x = h.x
	velocity.z = h.y
	move_and_slide()
	if global_position.y < Arena.VOID_Y and velocity.y <= 0.0:
		_void_bounce()


## Tiro num bloco de gelo (na máquina do congelado): empurra na direção do tiro.
func ice_push(dir: Vector3, dmg: float) -> void:
	var v := dir.normalized() * dmg * ICE_PUSH
	velocity += Vector3(v.x, maxf(v.y, 0.0) * 0.3, v.z)


## Encontrão: o bloco anda pelo menos na velocidade de quem empurra (não soma a cada passo).
func ice_shove(v: Vector3) -> void:
	if ice_timer <= 0.0:
		return
	var dir := Vector3(v.x, 0.0, v.z)
	var speed := dir.length()
	if speed < 0.5:
		return
	dir /= speed
	var along := Vector3(velocity.x, 0.0, velocity.z).dot(dir)
	if along < speed:
		velocity += dir * (speed - along)


## Quem anda contra um bloco de gelo o empurra (dash e deslize empurram mais forte).
func _shove_ice_blocks() -> void:
	for i in get_slide_collision_count():
		var other := get_slide_collision(i).get_collider() as Player
		if other == null or other.ice_timer <= 0.0:
			continue
		var push := Vector3(velocity.x, 0.0, velocity.z)
		var toward := other.global_position - global_position
		toward.y = 0.0
		if push.dot(toward) <= 0.0:
			continue
		if dash_timer > 0.0 or sliding:
			push *= ICE_SHOVE_DASH
		other.remote_call("ice_shove", [push])


## Bloco de gelo em volta do jogador (todas as máquinas). Quem está na primeira pessoa
## não tem modelo: um boneco simples na cor dele fica dentro do bloco, para a câmera de
## fora. Os modelos param a animação enquanto congelados.
static var _ice_mat: StandardMaterial3D

func _ice_visual(on: bool) -> void:
	if anim:
		anim.speed_scale = 0.0 if on else 1.0
	if viewmodel:
		viewmodel.visible = not on
	if not on:
		if ice_block:
			ice_block.queue_free()
			ice_block = null
		return
	if ice_block:
		return
	if _ice_mat == null:
		_ice_mat = StandardMaterial3D.new()
		_ice_mat.albedo_color = Color(ICE_COLOR, 0.45)
		_ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_mat.emission_enabled = true
		_ice_mat.emission = ICE_COLOR
		_ice_mat.emission_energy_multiplier = 0.25
		_ice_mat.roughness = 0.15
	ice_block = Node3D.new()
	add_child(ice_block)
	var scale_k: float = stats["body_scale"]
	var box := BoxMesh.new()
	box.size = Vector3(1.25, height + 0.35, 1.25) * Vector3(scale_k, 1.0, scale_k)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _ice_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = (height + 0.35) / 2.0 - 0.05
	ice_block.add_child(mi)
	if model == null:
		var doll := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = height * 0.9
		doll.mesh = cap
		var dm := StandardMaterial3D.new()
		dm.albedo_color = color
		doll.material_override = dm
		doll.position.y = height * 0.45
		doll.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ice_block.add_child(doll)
	Effects.burst(get_parent(), chest(), 1.6, ICE_COLOR, 0.25)


## Congelado na sua tela: câmera atrás e acima do bloco; o mouse gira em volta.
func _place_ice_camera() -> void:
	var center := get_global_transform_interpolated().origin + Vector3(0, height * 0.7, 0)
	var basis := Basis.from_euler(Vector3(clampf(head.rotation.x, -1.2, 0.6) - 0.25, look_yaw, 0.0))
	var want := center + basis * Vector3(0, 0, ICE_CAM_DISTANCE)
	var query := PhysicsRayQueryParameters3D.create(center, want, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var pos: Vector3 = want if hit.is_empty() else center.lerp(hit["position"], 0.85)
	camera.global_transform = Transform3D(basis, pos)


# ---------------------------------------------------------------- Mega Tapa

## Tapa: quem está no leque curto à frente leva (a máquina do alvo decide o escudo).
func _slap() -> void:
	var forward := _flat_forward()
	var arc := deg_to_rad(SLAP_ARC)
	reveal()
	for enemy in enemies():
		var to: Vector3 = enemy.chest() - chest()
		if absf(to.y) > 2.0:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		if dist > SLAP_RANGE + enemy.hit_radius():
			continue
		if dist > 0.9 and forward.angle_to(flat / dist) > arc:
			continue
		enemy.remote_call("receive_slap", [String(name), forward])
		Effects.burst(get_parent(), enemy.chest(), 1.1, SLAP_COLOR, 0.15)
	_show_slap()
	if Net.online:
		_net_slap.rpc()


@rpc("authority", "call_remote", "reliable")
func _net_slap() -> void:
	_show_slap()


## Levou o tapa (máquina dona): escudo bloqueia; congelado só voa; senão dano e voo.
func receive_slap(from_name: String, dir: Vector3) -> void:
	if not alive:
		return
	if is_shielding():
		reflect_flash = 1.0
		Sfx.at(self, "reflect", chest())
		Effects.burst(get_parent(), chest(), 1.2, Color(0.5, 0.9, 1.0), 0.15)
		return
	_end_beam(true)
	_ride_crash()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	velocity = flat * SLAP_PUSH + Vector3.UP * SLAP_LIFT
	jump_rising = false
	coyote = 0.0
	sliding = false
	dash_timer = 0.0
	if ice_timer > 0.0:
		return
	slap_flight = SLAP_FLIGHT
	slap_from = from_name
	slapped.emit(false)
	take_damage(SLAP_DAMAGE, get_parent().get_node_or_null(from_name) as Player)


## No voo do tapa: bateu numa parede (superfície em pé, sem ser outro jogador) ainda
## rápido? Leva o impacto e fica tonto.
func _check_splat(before_h: Vector3, delta: float) -> void:
	slap_flight -= delta
	if before_h.length() < SPLAT_MIN_SPEED:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is Player or absf(c.get_normal().y) > 0.6:
			continue
		if before_h.normalized().dot(-c.get_normal()) < 0.3:
			continue   # raspou de lado
		slap_flight = 0.0
		daze_timer = DAZE_TIME
		apply_slow(DAZE_SLOW, DAZE_TIME)
		shake = maxf(shake, 0.6)
		take_damage(SPLAT_DAMAGE, get_parent().get_node_or_null(slap_from) as Player)
		_show_splat(c.get_position())
		slapped.emit(true)
		if Net.online:
			_net_splat.rpc(c.get_position())
		return


@rpc("authority", "call_remote", "reliable")
func _net_splat(pos: Vector3) -> void:
	_show_splat(pos)


func _show_splat(pos: Vector3) -> void:
	Effects.burst(get_parent(), pos, 1.8, SLAP_COLOR, 0.25)
	Effects.sparks(get_parent(), pos, Color(1, 1, 1), 12, 8.0)
	Sfx.at(get_parent(), "explosion", pos)


## Visual do tapa: rastro do arco, animação de ataque e, na própria tela, a mão.
func _show_slap() -> void:
	Sfx.at(self, "dash", chest())
	var forward := _flat_forward()
	var right := forward.cross(Vector3.UP)
	var own := is_human
	Effects.slash(get_parent(), chest() - Vector3.UP * (0.35 if own else 0.0), forward, right, SLAP_RANGE * 0.8,
		false, SLAP_COLOR, 0.2, 0.35 if own else 1.0, 0.85 if own else 0.6)
	if model:
		swing_anim = 0.4
		anim.play("attack-melee-right", 0.05)
		anim.speed_scale = 1.3
	if hand_pivot and is_human:
		hand_pivot.visible = true
		hand_pivot.position = Vector3(0.35, -0.12, -0.05)
		hand_pivot.rotation = Vector3(0.0, 0.9, 0.2)
		var t := create_tween()
		t.tween_property(hand_pivot, "position", Vector3(-0.25, -0.05, -0.32), 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(hand_pivot, "rotation", Vector3(0.0, -0.6, -0.1), 0.12)
		t.tween_interval(0.08)
		t.tween_callback(func(): hand_pivot.visible = false)


## Mão aberta montada em código (palma e quatro dedos juntos, polegar de lado), cor de pele.
static var _hand_mat: StandardMaterial3D

func _make_hand() -> Node3D:
	if _hand_mat == null:
		_hand_mat = StandardMaterial3D.new()
		_hand_mat.albedo_color = Color(0.93, 0.72, 0.56)
	var root := Node3D.new()
	var parts := [[Vector3(0.16, 0.05, 0.16), Vector3(0, 0, 0)],
		[Vector3(0.15, 0.045, 0.14), Vector3(0, 0, -0.15)],
		[Vector3(0.05, 0.045, 0.1), Vector3(0.1, 0, 0.0)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		mi.mesh = box
		mi.material_override = _hand_mat
		mi.position = p[1]
		root.add_child(mi)
	root.rotation = Vector3(PI / 2.0, 0.0, 0.0)   # palma virada para a frente, dedos para cima
	return root


# ---------------------------------------------------------------- Foguete

func _ride_dir() -> Vector3:
	var pitch := clampf(head.rotation.x, -RIDE_PITCH, RIDE_PITCH)
	return Basis.from_euler(Vector3(pitch, rotation.y, 0.0)) * Vector3.FORWARD


func _start_ride() -> void:
	ride_timer = RIDE_TIME
	ride_age = 0.0
	beam_aim = Vector2(look_yaw, clampf(head.rotation.x, -RIDE_PITCH, RIDE_PITCH))
	if is_on_floor():
		global_position.y += RIDE_LIFT
	reveal()
	sliding = false
	dash_timer = 0.0
	_ride_visual(true)
	Sfx.at(self, "explosion", chest())
	if Net.online and is_inside_tree():
		_net_ride.rpc(true)


@rpc("authority", "call_remote", "reliable")
func _net_ride(on: bool) -> void:
	ride_timer = RIDE_TIME if on else 0.0
	_ride_visual(on)


## Montado: sempre para a frente, sem gravidade. Q de novo salta (depois de 0,2 s, para o
## mesmo aperto não montar e saltar). Parede, chão de frente, inimigo ou fim do tempo:
## explode com você em cima.
func _ride_step(delta: float) -> void:
	ride_timer -= delta
	ride_age += delta
	if not alive:
		_ride_crash()
		return
	if in_master and ride_age > 0.2:
		_ride_jump()
		return
	if ride_timer <= 0.0:
		_ride_crash()
		return
	var dir := _ride_dir()
	velocity = dir * RIDE_SPEED
	move_and_slide()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider() as Player
		if other:
			if is_enemy(other) and other.alive:
				_ride_crash()
				return
			continue
		if c.get_normal().dot(-dir) > 0.3:   # bateu de frente (parede, ou o chão descendo a 20 graus)
			_ride_crash()
			return
	if global_position.y < Arena.VOID_Y and velocity.y <= 0.0:
		_void_bounce()


## Salta do foguete: ele segue reto, rápido, e explode no primeiro contato.
func _ride_jump() -> void:
	var dir := _ride_dir()
	ride_timer = 0.0
	_ride_visual(false)
	if Net.online and is_inside_tree():
		_net_ride.rpc(false)
	Bullet.fire(self, chest() + dir * 1.6, dir, 0.0, false,
		{"speed": ROCKET_FREE_SPEED, "rocket": true, "radius": 0.35, "gravity": 0.0, "bounces": 0,
		"ghost_walls": 0, "explosion": 0.0, "poison": 0.0, "slow": 0.0, "push": 0.0, "shield_break": false,
		"execute": 0.0, "split": 0, "sticky": false, "boomerang": false, "guided": false, "seek": 0.0,
		"homing": 0.0, "target_bounce": 0.0, "lazy_top": 0.0, "grow": 0.0, "swap": false, "blind": 0.0,
		"toxic": 0, "hole": 0, "bounce_damage": 0.0})
	velocity = dir * RIDE_SPEED + Vector3.UP * RIDE_JUMP
	jump_rising = false
	Sfx.at(self, "pad", chest())


## O foguete explode com você em cima (onde estiver).
func _ride_crash() -> void:
	if ride_timer <= 0.0 and ride_fx == null:
		return
	ride_timer = 0.0
	_ride_visual(false)
	if Net.online and is_inside_tree():
		_net_ride.rpc(false)
	var pos := global_position + Vector3.UP * 0.3
	if Net.online and is_inside_tree():
		_net_rocket_blast.rpc(pos)
	else:
		_net_rocket_blast(pos)


@rpc("authority", "call_local", "reliable")
func _net_rocket_blast(pos: Vector3) -> void:
	rocket_blast(get_parent(), pos, self)


## Explosão do Foguete (em cada máquina, só nos jogadores dela; nunca no dono, que é
## lançado para cima se estava perto, nem no aliado).
static func rocket_blast(parent: Node, pos: Vector3, owner_p: Player) -> void:
	if is_instance_valid(owner_p):
		owner_p.rocket_exploded.emit()
	Effects.burst(parent, pos, ROCKET_BLAST_RADIUS, ROCKET_COLOR, 0.35)
	Effects.sparks(parent, pos, ROCKET_COLOR, 16, 9.0)
	Sfx.at(parent, "explosion", pos)
	for node in parent.get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.is_local or not p.alive:
			continue
		var d := p.chest().distance_to(pos)
		if d > ROCKET_BLAST_RADIUS + p.hit_radius():
			continue
		var away := p.chest() - pos
		away.y = 0.0
		if p == owner_p:
			p.launch(away.normalized() * 4.0 + Vector3.UP * ROCKET_LIFT)
			continue
		if is_instance_valid(owner_p) and owner_p.is_ally(p):
			continue
		p.knockback(away.normalized() * 8.0 + Vector3.UP * 5.0)
		p.take_damage(ROCKET_BLAST_DAMAGE * (1.0 - 0.5 * clampf(d / ROCKET_BLAST_RADIUS, 0.0, 1.0)),
			owner_p if is_instance_valid(owner_p) else null)


## Foguete sob os pés (todas as máquinas): corpo, ponta e chama, montado em código.
static var _rocket_parts: Array = []

func _ride_visual(on: bool) -> void:
	if ride_fx:
		ride_fx.queue_free()
		ride_fx = null
	if not on:
		return
	if _rocket_parts.is_empty():
		var body := StandardMaterial3D.new()
		body.albedo_color = Color(0.85, 0.86, 0.9)
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.85, 0.2, 0.15)
		var flame := StandardMaterial3D.new()
		flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.albedo_color = Color(1.0, 0.7, 0.2)
		# Gordo (pedido do usuário: o primeiro, de 0,28 m de raio, ficou fininho).
		var tube := CylinderMesh.new()
		tube.top_radius = ROCKET_FAT; tube.bottom_radius = ROCKET_FAT; tube.height = 2.4; tube.radial_segments = 14
		tube.material = body
		var nose := CylinderMesh.new()
		nose.top_radius = 0.0; nose.bottom_radius = ROCKET_FAT; nose.height = 0.9; nose.radial_segments = 14
		nose.material = red
		var fire := CylinderMesh.new()
		fire.top_radius = ROCKET_FAT * 0.8; fire.bottom_radius = 0.0; fire.height = 0.9; fire.radial_segments = 10
		fire.material = flame
		var fin := BoxMesh.new()
		fin.size = Vector3(0.08, 0.6, ROCKET_FAT * 1.1)
		fin.material = red
		# [malha, posição ao longo do foguete (+ = frente), giro da aleta em volta do eixo]
		_rocket_parts = [[tube, 0.0, -1.0], [nose, 1.65, -1.0], [fire, -1.65, -1.0],
			[fin, -0.95, 0.0], [fin, -0.95, PI / 2.0], [fin, -0.95, PI], [fin, -0.95, PI * 1.5]]
	ride_fx = Node3D.new()
	ride_fx.top_level = true
	add_child(ride_fx)
	for part in _rocket_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part[2] < 0.0:
			# Cilindro em pé (Y): deita para apontar para -Z (frente do nó).
			mi.rotation.x = -PI / 2.0
			mi.position = Vector3(0, 0, -part[1])
		else:
			# Aleta: em volta do corpo, para fora a partir da superfície.
			var out := Vector3(cos(part[2]), sin(part[2]), 0.0)
			mi.rotation.z = part[2] + PI / 2.0
			mi.position = Vector3(0, 0, -part[1]) + out * (ROCKET_FAT + 0.25)
		ride_fx.add_child(mi)
	_update_ride_fx()


func _update_ride_fx() -> void:
	var dir := _ride_dir()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK
	if is_human:
		# Na própria tela o foguete fica embaixo e à frente da câmera (nos pés não aparece).
		var pos := camera.global_position + Vector3.DOWN * 0.95 + dir * 1.6
		ride_fx.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3.ONE * 0.6), pos)
		return
	# Logo abaixo dos pés (o jogador sobe RIDE_LIFT ao montar, para o foguete não entrar no chão).
	var pos := get_global_transform_interpolated().origin + Vector3.UP * (0.05 - ROCKET_FAT) + dir * 0.3
	ride_fx.global_transform = Transform3D(Basis.looking_at(dir, up), pos)


# ---------------------------------------------------------------- Chuva de Meteoros

## Bala marcada bateu (na máquina de quem atirou): marca o chão logo abaixo e avisa todas.
func meteor_mark(point: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 60.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var ground: Vector3 = hit["position"] if not hit.is_empty() else point
	if Net.online and is_inside_tree():
		_net_meteor.rpc(ground)
	else:
		_net_meteor(ground)


@rpc("authority", "call_local", "reliable")
func _net_meteor(pos: Vector3) -> void:
	MeteorStrike.spawn(get_parent(), pos, self)
	meteor_marked.emit()


# ---------------------------------------------------------------- Plataformas Suspensas

## Plataforma sob os pés, nesta e nas outras máquinas (para todo mundo poder pisar).
func _make_platform() -> void:
	plat_left -= 1
	var pos := global_position + Vector3.DOWN * (SkyPlatform.SIZE.y / 2.0 + 0.02)
	SkyPlatform.spawn(get_parent(), pos, color)
	platform_made.emit()
	Sfx.at(self, "pad", pos)
	if Net.online and is_inside_tree():
		_net_platform.rpc(pos)


@rpc("authority", "call_remote", "reliable")
func _net_platform(pos: Vector3) -> void:
	SkyPlatform.spawn(get_parent(), pos, color)
	platform_made.emit()


# ---------------------------------------------------------------- Canhão Arcano

func _start_beam() -> void:
	beam_charge = BEAM_CHARGE
	beam_timer = 0.0
	beam_hits.clear()
	reveal()
	_beam_visual(1)
	Sfx.at(self, "pickup", chest())
	if Net.online and is_inside_tree():
		_net_beam.rpc(1)


## Fim do raio (acabou o tempo, ou cortado por tapa, gelo ou morte).
func _end_beam(send: bool) -> void:
	if beam_charge <= 0.0 and beam_timer <= 0.0 and beam_fx == null:
		return
	beam_charge = 0.0
	beam_timer = 0.0
	_beam_visual(0)
	if send and Net.online and is_inside_tree() and is_local:
		_net_beam.rpc(0)


@rpc("authority", "call_remote", "reliable")
func _net_beam(state: int) -> void:
	beam_charge = BEAM_CHARGE if state == 1 else 0.0
	beam_timer = BEAM_TIME if state == 2 else 0.0
	_beam_visual(state)


## Carga (andando devagar) e raio (parado, flutuando no ar). Acertos na máquina dona.
func _beam_step(delta: float) -> void:
	if not alive:
		_end_beam(true)
		return
	if beam_charge > 0.0:
		beam_charge -= delta
		if beam_charge <= 0.0:
			beam_charge = 0.0
			beam_timer = BEAM_TIME
			beam_aim = Vector2(look_yaw, head.rotation.x)
			_beam_visual(2)
			Sfx.at(self, "explosion", chest())
			if Net.online and is_inside_tree():
				_net_beam.rpc(2)
		return
	beam_timer -= delta
	velocity = Vector3.ZERO
	if beam_timer <= 0.0:
		_end_beam(true)
		return
	for k in beam_hits.keys():
		beam_hits[k] -= delta
	var origin := head.global_position
	var dir := -head.global_transform.basis.z
	for enemy: Player in enemies():
		if beam_hits.get(enemy, 0.0) > 0.0:
			continue
		var c := enemy.chest()
		var t := (c - origin).dot(dir)
		if t < 0.0 or t > BEAM_RANGE:
			continue
		if (origin + dir * t).distance_to(c) > BEAM_RADIUS + enemy.hit_radius():
			continue
		beam_hits[enemy] = BEAM_REHIT
		# Para o lado em que ele está em relação ao eixo (no meio, para a direita do raio).
		var side := c - (origin + dir * t)
		side.y = 0.0
		if side.length() < 0.1:
			side = dir.cross(Vector3.UP)
		var along := Vector3(dir.x, 0.0, dir.z).normalized()
		var push := side.normalized() * BEAM_PUSH_SIDE + along * BEAM_PUSH_ALONG + Vector3.UP * BEAM_LIFT
		enemy.remote_call("receive_beam", [String(name), push])
		Effects.burst(get_parent(), c, 1.3, BEAM_COLOR, 0.15)


## Raio acertou (máquina dona do alvo): arremessa para fora do raio (push vem de quem
## atirou); escudo bloqueia o dano e segura metade do empurrão; bloco de gelo só voa.
func receive_beam(from_name: String, push: Vector3) -> void:
	if not alive:
		return
	if is_shielding():
		reflect_flash = 1.0
		Sfx.at(self, "reflect", chest())
		velocity = push * BEAM_SHIELD_PUSH
		return
	velocity = push
	jump_rising = false
	coyote = 0.0
	sliding = false
	dash_timer = 0.0
	beamed.emit()
	take_damage(BEAM_DAMAGE, get_parent().get_node_or_null(from_name) as Player)


## Visual: 1 carga (esfera na mão crescendo), 2 raio (cilindro pela mira), 0 nada.
static var _beam_mat: StandardMaterial3D
static var _beam_mesh: CylinderMesh
static var _orb_mesh: SphereMesh

func _beam_visual(state: int) -> void:
	if beam_fx:
		beam_fx.queue_free()
		beam_fx = null
	if state == 0:
		return
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.albedo_color = Color(BEAM_COLOR.lightened(0.3), 0.75)
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mesh = CylinderMesh.new()
		_beam_mesh.top_radius = 1.0
		_beam_mesh.bottom_radius = 1.0
		_beam_mesh.height = 1.0
		_beam_mesh.radial_segments = 12
		_beam_mesh.rings = 1
		_orb_mesh = SphereMesh.new()
		_orb_mesh.radius = 1.0
		_orb_mesh.height = 2.0
		_orb_mesh.radial_segments = 12
		_orb_mesh.rings = 6
	beam_fx = Node3D.new()
	beam_fx.top_level = true
	add_child(beam_fx)
	var mi := MeshInstance3D.new()
	mi.mesh = _beam_mesh if state == 2 else _orb_mesh
	mi.material_override = _beam_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_fx.add_child(mi)
	_update_beam_fx(0.0)


## A cada quadro: a esfera cresce na carga; o raio acompanha a mira. Na própria tela o
## raio é mais fino e começa mais à frente (cobrir a tela custa caro na Intel HD).
func _update_beam_fx(_delta: float) -> void:
	var dir := -head.global_transform.basis.z
	var own := is_human
	if beam_timer > 0.0:
		# Na própria tela o raio sai da mão (embaixo à direita) e vai até o ponto da mira;
		# de frente para a câmera ele virava um disco no meio da tela.
		var radius := BEAM_RADIUS * (0.3 if own else 1.0)
		var right := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
		var start := head.global_position + dir * 0.6 + Vector3.DOWN * 0.3
		if own:
			start = head.global_position + dir * 0.9 + Vector3.DOWN * 0.42 + right * 0.32
		var end := head.global_position + dir * BEAM_RANGE
		var axis := (end - start).normalized()
		var length := start.distance_to(end)
		var center := (start + end) / 2.0
		# O cilindro tem o eixo em Y: Y vira a direção do raio.
		var x := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
		var z := x.cross(axis).normalized()
		dir = axis
		var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.03)
		beam_fx.global_transform = Transform3D(Basis(x * radius * pulse, dir * length, z * radius * pulse), center)
	elif beam_charge > 0.0:
		# Carga: esfera na mão que cresce. Na própria tela, pequena e embaixo à direita.
		var k := 1.0 - beam_charge / BEAM_CHARGE
		var right := dir.cross(Vector3.UP).normalized()
		var pos := head.global_position + dir * (1.2 if own else 0.7) + Vector3.DOWN * (0.35 if own else 0.3) 			+ right * (0.25 if own else 0.0)
		var size := (0.04 + 0.1 * k) if own else (0.12 + 0.3 * k)
		beam_fx.global_transform = Transform3D(Basis().scaled(Vector3.ONE * size), pos)


## Bazuca: foguete reto, lento, com o dobro do dano e explosão grande.
func _fire_rocket() -> void:
	rockets_left -= 1
	fire_timer = BAZOOKA_INTERVAL
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	shot_mult = 1.0
	Bullet.fire(self, muzzle.global_position, (target - muzzle.global_position).normalized(), ROCKET_DAMAGE, true,
		{"speed": ROCKET_SPEED, "gravity": 0.0, "explosion": maxf(ROCKET_EXPLOSION, float(stats["explosion"])),
		"bounces": 0, "split": 0, "sticky": false, "boomerang": false, "guided": false, "pierce": false})
	recoil = 1.6
	shake = maxf(shake, 0.25)
	muzzle_light.light_energy = 5.0
	muzzle_light.visible = true
	reveal()


## Pancada: com o escudo de pé, quem estiver colado leva dano e um empurrão (uma vez por escudo).
func _shield_bash() -> void:
	if stats["shield_bash"] <= 0.0 or not is_shielding():
		return
	for enemy in enemies():
		if enemy in bash_hits or chest().distance_to(enemy.chest()) > BASH_RANGE * maxf(1.0, float(stats["shield_size"])):
			continue
		bash_hits.append(enemy)
		enemy.remote_call("receive_shockwave", [global_position, float(stats["shield_bash"]), String(name)])
		Effects.burst(get_parent(), enemy.chest(), 1.4, Color(0.5, 0.9, 1.0), 0.2)
		Sfx.at(self, "hit", enemy.chest())


func _start_reload() -> void:
	reload_timer = stats["reload_time"]


func _fire() -> void:
	ammo -= 1
	pierce_shot = pierce_left > 0
	if pierce_shot:
		pierce_left -= 1
	meteor_shot = meteor_left > 0
	if meteor_shot:
		meteor_left -= 1
	shot_mult = float(stats["last_shot"]) if ammo == 0 else 1.0
	burst_left = stats["burst"] - 1
	burst_timer = BURST_GAP
	fire_timer = maxf(stats["fire_interval"], stats["burst"] * BURST_GAP)
	_volley()
	if ammo == 0 and stats["shield_on_empty"] > 0 and shield_cd <= 0.0 and silence_timer <= 0.0:
		_activate_shield()


## Um disparo: a mira é o centro da câmera. Um raio acha o ponto mirado e as balas
## saem do cano até ele, abertas em leque quando há mais de uma.
func _volley() -> void:
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	# Bala que atravessa parede mira só nos jogadores: o ponto na parede a entortaria.
	var mask := 2 if pierce_shot or stats["ghost"] > 0 else 1 | 2
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	var count: int = stats["bullet_count"]
	var spread := deg_to_rad(stats["spread"])
	for k in count:
		var dir := (target - muzzle.global_position).normalized()
		if count > 1:
			dir = dir.rotated(Vector3.UP, spread * (k - (count - 1) / 2.0))
		var mult := shot_mult
		var crit := randf() < float(stats["crit_chance"])
		if crit:
			mult *= CRIT_MULT
		var extra := {"crit": crit}
		if pierce_shot:
			# Perfurante: reta, bem mais rápida e atravessando paredes.
			extra.merge({"speed": float(stats["bullet_speed"]) * PIERCE_SPEED, "gravity": 0.0,
				"ghost": true, "pierce": true})
		if meteor_shot and k == 0:
			extra["meteor"] = true   # só a primeira bala do disparo marca (escopeta)
		Bullet.fire(self, muzzle.global_position, dir, mult, k == 0, extra)
	recoil = 1.0
	muzzle_light.light_energy = 3.0
	muzzle_light.visible = true
	reveal()


func shot_damage() -> float:
	var dmg: float = stats["damage"]
	if health < stats["max_health"] * RAGE_THRESHOLD:
		dmg *= 1.0 + stats["rage"]
	if ambush_timer > 0.0:
		dmg *= 1.0 + AMBUSH_DAMAGE
	if stats["rocket_boots"] > 0:
		dmg *= 1.0 + air_bonus()
	return dmg


## Bota Foguete: bônus de dano pelo tempo no ar (0 sem a carta ou no chão).
func air_bonus() -> float:
	if stats["rocket_boots"] <= 0:
		return 0.0
	return minf(AIR_DAMAGE_MAX, air_time * AIR_DAMAGE_RATE)


func _activate_shield() -> void:
	shield_timer = stats["shield_duration"]
	if shield_extra > 0:
		shield_extra -= 1
		shield_cd = stats["shield_duration"] + SHIELD_DOUBLE_GAP
	else:
		shield_cd = stats["shield_duration"] + stats["shield_cooldown"]
		shield_extra = stats["shield_charges"] - 1
	bash_hits.clear()
	# O colete da Couraça é o mesmo do item do mapa: um só, até ARMOR_MAX.
	if stats["shield_armor"] > 0.0 and armor_cd <= 0.0:
		armor = minf(ARMOR_MAX, armor + stats["shield_armor"])
		armor_cd = SHIELD_PERK_COOLDOWN
	if stats["shield_reload"] > 0:
		ammo = stats["mag_size"]
		reload_timer = 0.0
	if stats["shield_heal"] > 0.0 and heal_cd <= 0.0:
		heal(stats["shield_heal"])
		heal_cd = SHIELD_PERK_COOLDOWN
	if stats["shield_dash"] > 0:
		dash_dir = _flat_forward()
		dash_timer = DASH_TIME * 1.4
		dash_air = false
		dash_exit = maxf(Vector3(velocity.x, 0.0, velocity.z).length(), float(stats["move_speed"]))
		dash_hits.clear()
	if stats["shield_shockwave"] > 0:
		Effects.burst(get_parent(), chest(), SHOCKWAVE_RANGE, Color(0.5, 0.9, 1.0))
		for enemy in enemies():
			if chest().distance_to(enemy.chest()) < SHOCKWAVE_RANGE:
				enemy.remote_call("receive_shockwave", [global_position, 10.0 * stats["shield_shockwave"], String(name)])
	var nova: int = stats["shield_nova"]
	for k in nova:
		var dir := _flat_forward().rotated(Vector3.UP, TAU * k / nova)
		Bullet.fire(self, chest() + dir * 1.2, dir, 0.5, k == 0)
	# Chuva de Bombas: bombas lentas em arco, que explodem ao tocar qualquer coisa.
	var bombs: int = stats["shield_bombs"]
	for k in bombs:
		var dir := _flat_forward().rotated(Vector3.UP, TAU * k / bombs) * 0.55 + Vector3.UP * 0.85
		Bullet.fire(self, chest() + Vector3.UP * 0.6, dir.normalized(), 0.8, k == 0,
			{"speed": 11.0, "gravity": 18.0, "explosion": maxf(3.0, float(stats["explosion"])),
			"radius": 0.25, "bounces": 0, "homing": 0.0, "seek": 0.0, "boomerang": false, "split": 0, "sticky": false})
	if stats["shield_echo"] > 0 and echo_timer <= 0.0:
		echo_timer = stats["shield_duration"] + ECHO_DELAY
	if stats["shield_teleport"] > 0:
		_teleport_forward()
	var mask := _shield_area_mask()
	if mask != 0:
		AreaField.shield(self, mask, global_position)
		if Net.online:
			_net_shield_area.rpc(mask, global_position)


## Quais áreas do escudo saem agora: as cartas que tem e cuja recarga própria acabou.
func _shield_area_mask() -> int:
	var mask := 0
	for pair in [[AreaField.SHIELD_SAW, "shield_saw"], [AreaField.SHIELD_FLAMES, "shield_flames"],
			[AreaField.SHIELD_FROST, "shield_frost"], [AreaField.SHIELD_MINE, "shield_mine"]]:
		var bit: int = pair[0]
		if stats[pair[1]] > 0 and area_cd.get(bit, 0.0) <= 0.0:
			mask |= bit
			area_cd[bit] = AreaField.SHIELD_COOLDOWNS[bit]
	return mask


@rpc("authority", "call_remote", "reliable")
func _net_shield_area(mask: int, pos: Vector3) -> void:
	AreaField.shield(self, mask, pos)


## Teleporte: TELEPORT_RANGE para onde a mira aponta, atravessando paredes e peças. Se o
## ponto cair dentro de algo, tenta mais à frente (até TELEPORT_OVERSHOOT) e depois mais
## perto; sem lugar livre na linha, não teleporta.
func _teleport_forward() -> void:
	var aim := -head.global_transform.basis.z
	var tries: Array = [TELEPORT_RANGE]
	var d := TELEPORT_RANGE + TELEPORT_STEP
	while d <= TELEPORT_RANGE + TELEPORT_OVERSHOOT + 0.01:
		tries.append(d)
		d += TELEPORT_STEP
	d = TELEPORT_RANGE - TELEPORT_STEP
	while d >= 1.0:
		tries.append(d)
		d -= TELEPORT_STEP
	var arena = get_parent().get("arena")
	var limit: float = arena.half - RADIUS - 0.2 if arena else INF
	var room := PhysicsShapeQueryParameters3D.new()
	room.shape = capsule
	room.collision_mask = 1
	room.exclude = [get_rid()]
	for dist in tries:
		var dest: Vector3 = global_position + aim * dist
		dest.y = maxf(dest.y, 0.05)   # olhando para baixo, para no chão
		if absf(dest.x) > limit or absf(dest.z) > limit:
			continue   # não sai pelo muro de fora
		room.transform = Transform3D(Basis(), dest + Vector3.UP * (height / 2.0 + 0.05))
		if not get_world_3d().direct_space_state.intersect_shape(room, 1).is_empty():
			continue
		Effects.burst(get_parent(), chest(), 1.2, Color(0.6, 0.5, 1.0), 0.2)
		teleport_to(dest)
		Effects.burst(get_parent(), chest(), 1.2, Color(0.6, 0.5, 1.0), 0.2)
		return


## Troca-Troca, na máquina de quem levou o tiro: marca os dois e troca depois de SWAP_DELAY.
func begin_swap(shooter: Player) -> void:
	if swap_lock > 0.0 or not alive or not is_instance_valid(shooter) or not shooter.alive:
		return
	swap_partner = shooter
	swap_timer = SWAP_DELAY
	swap_lock = SWAP_DELAY + SWAP_COOLDOWN
	_show_swap(String(shooter.name))
	if Net.online:
		_net_swap_mark.rpc(String(shooter.name))


## A troca usa onde cada um está no fim da espera. Se um dos dois morreu, não acontece.
func _finish_swap() -> void:
	var other := swap_partner
	swap_partner = null
	if not alive or not is_instance_valid(other) or not other.alive:
		return
	var here := global_position
	var there := other.global_position
	Effects.burst(get_parent(), chest(), 1.4, SwapLink.COLOR, 0.25)
	swap_to(there, String(other.name))
	other.remote_call("swap_to", [here, String(name)])
	Effects.burst(get_parent(), chest(), 1.4, SwapLink.COLOR, 0.25)


## Vai para o lugar do outro sem colidir com ele por SWAP_GHOST.
func swap_to(pos: Vector3, other_name: String) -> void:
	var other := get_parent().get_node_or_null(other_name) as Player
	if other:
		add_collision_exception_with(other)
		get_tree().create_timer(SWAP_GHOST, false).timeout.connect(func():
			if is_instance_valid(other):
				remove_collision_exception_with(other))
	teleport_to(pos)


## Linha e anéis roxos entre os dois enquanto a troca carrega (em todas as máquinas).
func _show_swap(other_name: String) -> void:
	var other := get_parent().get_node_or_null(other_name) as Player
	if other == null:
		return
	var link := SwapLink.new()
	link.a = self
	link.b = other
	link.time = SWAP_DELAY
	get_parent().add_child(link)
	Sfx.at(self, "pad", chest())


@rpc("authority", "call_remote", "reliable")
func _net_swap_mark(other_name: String) -> void:
	_show_swap(other_name)


## Os adversários vivos: todos os outros no cada um por si, o outro time no 2x2.
func enemies() -> Array:
	return get_tree().get_nodes_in_group("players").filter(func(p): return p.alive and is_enemy(p))


func is_enemy(other: Player) -> bool:
	return other != self and (team < 0 or other.team != team)


## Parceiro de time (nunca o próprio jogador). Bala e explosão atravessam aliados.
func is_ally(other: Player) -> bool:
	return other != null and other != self and team >= 0 and other.team == team


func is_shielding() -> bool:
	return shield_timer > 0.0


func on_reflect() -> void:
	reflect_flash = 1.0
	reflected.emit()
	Sfx.at(self, "reflect", chest())
	if stats["reflect_refund"] > 0:
		# O escudo fica pronto pouco depois de o atual acabar (sem a folga, ficaria permanente).
		shield_cd = minf(shield_cd, shield_timer + ADRENALINE_GAP)


func chest() -> Vector3:
	return global_position + Vector3(0, height * 0.66 * float(stats["body_scale"]), 0)


## Eixo da cápsula, usado pelas balas para testar o acerto com o raio de cada uma.
func hit_segment() -> Array:
	var s: float = stats["body_scale"]
	return [global_position + Vector3(0, RADIUS * s, 0), global_position + Vector3(0, (height - RADIUS) * s, 0)]


func hit_radius() -> float:
	var s: float = stats["body_scale"]
	if is_shielding():
		return SHIELD_HIT_RADIUS * maxf(s, 1.0) * float(stats["shield_size"])
	return RADIUS * s


func heal(amount: float) -> void:
	health = minf(stats["max_health"], health + amount)


func apply_slow(amount: float, time := SLOW_TIME) -> void:
	slow_amount = clampf(maxf(slow_amount if slow_timer > 0.0 else 0.0, amount), 0.0, 0.7)
	slow_timer = maxf(slow_timer, time)


## Chamas: queima por time segundos (renovado enquanto estiver no fogo).
func apply_burn(dps: float, time: float, from: Player) -> void:
	burn_dps = dps
	burn_timer = maxf(burn_timer, time)
	burn_from = from


func apply_poison(total: float, from: Player) -> void:
	poisons.append({"dps": total / POISON_TIME, "time": POISON_TIME, "from": from})


## Flash: a tela de quem levou o tiro fica branca (o bot erra mais a mira).
func apply_blind(time: float) -> void:
	blind_timer = maxf(blind_timer, time)


func silence() -> void:
	silence_timer = SILENCE_TIME
	shield_timer = 0.0


## Só é chamado na máquina dona deste jogador.
func take_damage(amount: float, from: Player, flash := true) -> void:
	if not alive or amount <= 0.0 or protect_timer > 0.0 or ice_timer > 0.0:
		return
	if from and from != self:
		last_attacker = from
		recent_hits[from] = Time.get_ticks_msec()
	var absorbed := minf(armor, amount)
	armor -= absorbed
	health -= amount - absorbed
	if last_stand_timer > 0.0:
		health = maxf(health, 1.0)   # Último Suspiro: não morre enquanto dura
	elif health <= 0.0 and stats["last_stand"] > 0 and not last_stand_used:
		last_stand_used = true
		last_stand_timer = LAST_STAND_TIME
		health = 1.0
		poisons.clear()
		Effects.burst(get_parent(), chest(), 2.0, Color(1.0, 0.3, 0.3), 0.3)
	since_damage = 0.0
	reveal()
	if flash:
		shake = maxf(shake, clampf(amount / 40.0, 0.15, 0.6))
		flash_hit()
		damaged.emit(amount, from)
		if is_human:
			Sfx.ui(self, "hurt")
		if from and from != self:
			from.remote_call("credit_damage", [amount, health <= 0.0 and revives_left == 0])
	if health <= 0.0:
		_lethal()


## Vida zerada: a Fênix segura, senão morre.
func _lethal() -> void:
	last_stand_timer = 0.0
	if revives_left > 0:
		revives_left -= 1
		health = stats["max_health"] * 0.5
		poisons.clear()
		Effects.burst(get_parent(), chest(), 3.0, Color(1.0, 0.6, 0.2))
		revived.emit()
	else:
		health = 0.0
		if _can_go_down():
			_go_down()
		else:
			_die()


## Abate e assistências: o último que causou dano nos ASSIST_TIME s antes leva o abate, os
## outros, assistência.
func _death_credit() -> Array:
	var now := Time.get_ticks_msec()
	var window := int(ASSIST_TIME * 1000.0)
	var killer := ""
	if is_instance_valid(last_attacker) and now - int(recent_hits.get(last_attacker, -window)) < window:
		killer = String(last_attacker.name)
	var assists: Array = []
	for p in recent_hits:
		if is_instance_valid(p) and String(p.name) != killer and now - int(recent_hits[p]) < window:
			assists.append(String(p.name))
	return [killer, assists]


func _die(credit: Array = []) -> void:
	if credit.is_empty():
		credit = _death_credit()
	if Net.online:
		_net_die.rpc(credit[0], credit[1])
	_apply_death(credit[0], credit[1])


@rpc("authority", "call_remote", "reliable")
func _net_die(killer: String, assists: Array) -> void:
	_apply_death(killer, assists)


func _apply_death(killer := "", assists: Array = []) -> void:
	if not alive and not downed:
		return
	downed = false
	_clear_down_marker()
	if shrink_timer > 0.0:
		shrink_timer = 0.0
		_set_shrunk(false)
	death_killer = killer
	death_assists = assists
	alive = false
	health = 0.0
	shape.set_deferred("disabled", true)
	tag.visible = false
	if model:
		anim.speed_scale = 1.0
		anim.play("die")
	Sfx.at(self, "death", chest())
	died.emit(self)


# ---------------------------------------------------------------- caído (2x2)

func _can_go_down() -> bool:
	if not downs_enabled or team < 0 or frozen:
		return false
	return get_tree().get_nodes_in_group("players").any(func(p): return is_ally(p) and p.alive)


## Só na máquina dona: guarda quem derrubou (se o prazo acabar, o abate é dele, mesmo que
## já tenham passado os ASSIST_TIME s) e avisa as outras.
func _go_down() -> void:
	down_credit = _death_credit()
	var bleed: float = DOWN_BLEED[mini(downs, DOWN_BLEED.size() - 1)]
	if Net.online:
		_net_down.rpc(bleed)
	_apply_down(bleed)


@rpc("authority", "call_remote", "reliable")
func _net_down(bleed: float) -> void:
	_apply_down(bleed)


func _apply_down(bleed: float) -> void:
	if not alive:
		return
	alive = false
	downed = true
	downs += 1
	bleed_timer = bleed
	bleed_total = bleed
	revive_progress = 0.0
	health = 0.0
	shield_timer = 0.0
	dash_timer = 0.0
	burst_left = 0
	sliding = false
	slamming = false
	poisons.clear()
	burn_timer = 0.0
	slow_timer = 0.0
	swap_timer = 0.0
	echo_timer = 0.0
	crouching = true
	_set_height(DOWN_HEIGHT)
	_end_shrink(false)
	if bazooka_timer > 0.0 or sniper_timer > 0.0 or sword_timer > 0.0:
		bazooka_timer = 0.0
		sniper_timer = 0.0
		sword_timer = 0.0
		thrust_timer = 0.0
		scoping = false
		_show_weapon(0)
	_clear_down_marker()
	down_marker = DownedMarker.new()
	down_marker.player = self
	add_child(down_marker)
	Effects.burst(get_parent(), chest(), 1.5, Color(1.0, 0.35, 0.3), 0.25)
	went_down.emit()


## Arrastando: só anda devagar no chão (sem pulo, dash nem deslize) e cai com a gravidade.
func _downed_move(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var wish := _wish_dir() if not frozen else Vector3.ZERO
	var speed: float = stats["move_speed"] * DOWN_CRAWL
	if is_on_floor():
		h = _friction(h, FRICTION, delta)
		h = _accelerate(h, wish, speed, GROUND_ACCEL, delta)
	else:
		h = _accelerate(h, wish, speed, AIR_ACCEL, delta)
		velocity.y = maxf(velocity.y - GRAVITY_FALL * delta, -MAX_FALL_SPEED)
	velocity.x = h.x
	velocity.z = h.z
	move_and_slide()
	if global_position.y < Arena.VOID_Y and velocity.y <= 0.0:
		_void_bounce()   # caído não leva dano: só quica


## Prazo e reviver, em todas as máquinas (as outras só para mostrar o anel). O progresso
## sobe com um parceiro de pé dentro do círculo e volta devagar sem ninguém.
func _update_down(delta: float) -> void:
	if frozen:
		return   # rodada acabou ou ainda não começou
	bleed_timer = maxf(0.0, bleed_timer - delta)
	var helped := false
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if is_ally(p) and p.alive and p.global_position.distance_to(global_position) < REVIVE_RADIUS:
			helped = true
			break
	revive_progress = clampf(revive_progress + (delta if helped else -delta), 0.0, REVIVE_TIME)
	if not is_local:
		return
	if revive_progress >= REVIVE_TIME:
		if Net.online:
			_net_revive.rpc()
		_apply_revive()
	elif bleed_timer <= 0.0:
		_die(down_credit)


@rpc("authority", "call_remote", "reliable")
func _net_revive() -> void:
	_apply_revive()


func _apply_revive() -> void:
	if not downed:
		return
	downed = false
	alive = true
	health = stats["max_health"] * REVIVE_HEALTH
	protect_timer = REVIVE_PROTECT
	revive_progress = 0.0
	crouching = false
	_set_height(STAND_HEIGHT)
	_clear_down_marker()
	Effects.burst(get_parent(), chest(), 2.0, Color(0.5, 1.0, 0.6), 0.3)
	Sfx.at(self, "pickup", chest())
	got_up.emit()


func _clear_down_marker() -> void:
	if is_instance_valid(down_marker):
		down_marker.queue_free()
	down_marker = null


## Duelos: quem espera a vez fica fora da luta (invisível, sem colisão, sem levar nem dar
## tiro, ignorado pelos bots e pelas balas) até a próxima rodada; reset_for_round desfaz.
func bench() -> void:
	alive = false
	frozen = true
	velocity = Vector3.ZERO
	shape.set_deferred("disabled", true)
	tag.visible = false
	if model:   # o jogador desta tela não tem modelo nem anel (primeira pessoa)
		model.visible = false
		ring.visible = false


## Usado pelo bot para mirar: gira o corpo (horizontal) e a cabeça (vertical) até o ponto.
func look_at_point(point: Vector3, max_step: float) -> void:
	if beam_timer > 0.0 or ride_timer > 0.0:
		max_step = minf(max_step, (BEAM_TURN if beam_timer > 0.0 else RIDE_TURN) * get_physics_process_delta_time())
	var to := point - head.global_position
	rotation.y = rotate_toward(rotation.y, atan2(-to.x, -to.z), max_step)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	head.rotation.x = rotate_toward(head.rotation.x, pitch, max_step)
