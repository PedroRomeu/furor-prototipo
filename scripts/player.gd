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
signal fired       # um disparo da arma (o painel da sala de teste conta)
signal damaged(amount: float, from: Player)
signal damage_dealt(amount: float, lethal: bool)
signal reflected
signal master_used   # apertou Q e a mestra saiu (as missões contam)
signal revived
signal void_bounced(saved: bool)
signal went_down    # caiu no 2x2 (pode ser revivido)
signal got_up       # foi revivido
signal chaos_drawn(id: String)   # Caos sorteou outra mestra (a HUD avisa)
signal froze       # ficou preso no gelo (Prisão de Gelo; o registro do autoteste conta)
signal slapped(splat: bool)   # levou o Mega Tapa / bateu na parede (registro do autoteste)
signal beamed      # levou um toque do Canhão Arcano (registro do autoteste)
signal platform_made   # criou (ou recebeu pela rede) uma plataforma suspensa (registro do autoteste)
signal slammed(height: float, damage: float)   # Meteoro bateu no chão (registro do autoteste)
signal meteor_marked   # marca de meteoro no chão (registro do autoteste)
signal rocket_exploded # um Foguete explodiu (registro do autoteste)

## Atributos sem nenhuma carta. As cartas (CardDB) alteram estes valores.
const BASE_STATS := {
	"max_health": 100.0,
	"move_speed": 9.0,
	"jump_velocity": 12.0,   # sobe ~2,35 m com GRAVITY_RISE
	"gravity_mult": 1.0,   # Pena: só na descida
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
	"damage": 25.0,   # 4 tiros na vida base (2026-10-07; era 34)
	"damage_bonus": 0.0,   # soma dos bônus de Dano das cartas, já dentro de "damage" (compute_stats)
	"fire_interval": 0.3,
	"mag_size": 4,
	"reload_time": 1.3,
	"bullet_speed": 48.0,
	"bullet_gravity": 7.0,
	"bullet_range": 200.0,   # Alcance (m); RANGE_FREE ou mais = sem limite
	"bullet_count": 1,
	"free_ammo": 0.0,   # Cartucheira: chance de cada bala não sair do pente
	"shot_ammo": 0,     # balas do pente a mais por tiro (Escopeta: cada bala do leque gasta 1)
	"spread": 4.0,
	"burst": 1,
	"bullet_radius": 0.15,
	"last_shot": 1.0,
	"crit_chance": 0.0,
	"bounces": 0,
	"homing": 0.0,
	"ghost": 0,
	"explosion": 0.0,
	"blast_radius": 0.0,   # Pólvora (+1), Carga Concentrada (-1): só vale com explosão
	"blast_damage": 0.0,   # Pólvora (+0,3), Carga Concentrada (+0,6)
	"blast_resist": 0.0,   # Blindado: fração a menos do dano de explosões e áreas
	"poison": 0.0,
	"burn": 0.0,           # Bala Incendiária: Queimadura por segundo, em fração do dano da bala
	"ember": 0,            # Brasa: acertar quem queima com seu fogo esquenta a queimadura
	"fuel": 0,             # Combustível: sua queimadura tira mais em quem tem outra aflição
	"slow": 0.0,
	"frost": 0,            # Bala de Gelo (e Prisão de Gelo): camadas de Congelamento por acerto (FROST_*)
	"hypothermia": 0,      # Hipotermia: +1 camada em quem está lento; congelado dura mais
	"shatter": 0,          # Estilhaço: quebrar o gelo acerta quem está perto (SHATTER_*)
	"thermal": 0,          # Choque Térmico: congelar dá dano e Queimadura (THERMAL_*)
	"knockback": 0.0,
	"shield_break": 0,
	"target_bounce": 0,
	"execute": 0.0,
	"lifesteal": 0.0,
	"mark": 0,            # Marca: acerto ou tick seu marca o alvo (MARK_*)
	"dot_time": 0.0,      # Persistência: fração a mais na duração do seu veneno e da sua queimadura
	"slow_burn": 0,       # Combustão Lenta: sua queimadura dura mais e tira menos por segundo (SLOW_BURN_*)
	"acid": 0,            # Ácido: alvo sob dano seu ao longo do tempo cura menos (ACID_*)
	"dot_pierce": 0,      # Corrosão: seus ticks de aflição ignoram o colete
	"contagion": 0,       # Contágio: seu veneno pula para inimigos perto (CONTAGION_*)
	"shield_detonate": 0, # Estouro: o escudo estoura seu veneno e sua queimadura (DETONATE_*)
	"chain_blast": 0,     # Reação em Cadeia: aflição sua que termina faz o alvo explodir (CHAIN_*)
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
	"shield_haste": 0.0,  # Passo Ligeiro: velocidade a mais por SHIELD_HASTE_TIME ao levantar
	"toxic": 0,           # Nuvem Tóxica e Buraco Negro: nascem onde a bala bate (AreaField)
	"black_hole": 0,
	"stomp": 0,           # Pisão
	"heavy": 0.0,         # Peso Pesado: fração a menos dos empurrões
	"armor_regen": 0.0,   # Segunda Pele: colete a cada SKIN_DELAY sem levar dano
	"parkour": 0,         # Parkour: pulo de parede devolve dash no ar e dá velocidade
	"perfect_reload": 0,  # Recarga Perfeita
	"tough": 0,           # Casca Dura
	"dash_echo": 0,       # Dash Duplo: dashes extras automáticos depois do seu
	"speed_damage": 0.0,  # Velocidade Letal: teto do bônus de dano pela velocidade
	"blur": 0,            # Vulto: cópias (menos dano de balas acima de BLUR_SPEED)
	"air_reload": 0.0,    # Recarga no Embalo: recarga mais rápida no ar ou deslizando
	"dash_seek": 0,       # Bote: o dash curva até o inimigo
	"close_range": 0,     # Cano Serrado: dano maior de perto, menor de longe (Bullet.CLOSE_*)
	"dash_strike": 0,     # Arrancada: dash na direção de um inimigo fortalece o próximo tiro (STRIKE_*)
	"pressure": 0,        # Pressão: acertar de perto dá velocidade e adianta o dash (PRESSURE_*)
	"recycle": 0,         # Reciclagem: cada bala que acerta devolve 1 ao pente por cópia
	"still_aim": 0,       # Sangue Frio: cópias (bônus parado ou agachado no chão)
	"thick_skin": 0,      # Couro Grosso: cópias (redução que acumula por golpe levado)
	"kill_heal": 0.0,     # Banquete: cura por abate
	"tenacity": 0.0,      # Tenacidade: fração a menos na duração dos efeitos de controle
	"heal_mult": 0.0,     # Metabolismo: cura recebida a mais
	"survival_speed": 0.0,  # Instinto de Sobrevivência: velocidade abaixo de RAGE_THRESHOLD
	"revenge": 0.0,       # Vingança: dano a mais em quem te matou na rodada anterior
	"bloodlust": 0.0,
	"rage": 0.0,
	"revives": 0,
	"regen": 0.0,
	"radar": 0,
	"recoil": 0,          # Pólvora Extra: cópias; o coice cresce mais rápido que elas (_recoil)
	"body_scale": 1.0,
	"chase": 0.0,
	"camo": 0,
	"rocket_jump": 0,
	"rocket_boots": 0,   # Bota Foguete (carta mestra)
	"ground_slam": 0,
	# Cartas mestras (CardDB.MASTERS)
	"chaos": 0,     # Caos: sorteia outra mestra (_chaos_draw)
	"unstable": 0,  # Cartas Instáveis: cartas comuns por alguns segundos (_unstable_draw)
	"realm": 0,     # Domínio do Rei: x1 numa sala à parte (_realm_*, KingRealm)
	"grapple": 0,   # Arpéu Ventoso: ventosa que puxa até o cenário (_grapple_*)
	"ice": 0,       # Prisão de Gelo
	"slap": 0,      # Mega Tapa
	"beam": 0,      # Canhão Arcano
	"platforms": 0, # Plataformas Suspensas
	"meteor": 0,    # Chuva de Meteoros
	"rocket_ride": 0,   # Foguete
	"mech": 0,      # Mecha
	"clone": 0,     # Clone
	"hook": 0,      # Gancho
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
const VOID_DAMAGE := 15.0
const VOID_BOUNCE := 11.1         # sobe ~2 m (1 m acima do chão), ~0,7 s no ar
const VOID_BOUNCE_SHIELD := 18.7  # sobe ~5,8 m, ~1,2 s no ar
const VOID_CREDIT := 4.0          # quem acertou você nestes segundos leva o crédito da queda
# Alto demais (2026-10-10, como no Furor): com o centro do corpo acima do teto das balas
# (Bullet.CEILING_Y), ninguém te acerta. Depois de SKY_GRACE, a cada SKY_TICK leva uma parte
# da vida máxima que cresce (10%, 13%, 16%...: morre em ~7 s sem cura). A conta só zera
# depois de SKY_RESET abaixo do teto. Escudo e Blindado não reduzem; o colete absorve.
const SKY_GRACE := 1.0
const SKY_TICK := 1.0
const SKY_FIRST := 0.10
const SKY_STEP := 0.03
const SKY_RESET := 2.0
const SKY_COLOR := Color(1.0, 0.35, 0.3)
# Prorrogação (2026-10-12, rodada longa demais; tempos em match.OVERTIME_*): fora do círculo
# que fecha (centro na origem, raio zone_radius, posto pela partida), depois de ZONE_GRACE leva
# ZONE_PART da vida máxima a cada ZONE_TICK. Voltar para dentro recarrega a tolerância no
# mesmo ritmo (entrar e sair não zera). Escudo e Blindado não reduzem; o colete absorve.
const ZONE_GRACE := 1.0
const ZONE_TICK := 1.0
const ZONE_PART := 0.08
const ZONE_COLOR := Color(0.45, 0.8, 1.0)
static var zone_radius := INF   # INF = sem círculo
const ARMOR_MAX := 50.0      # colete (item do mapa): absorve dano antes da vida
# Combate
const SHOCKWAVE_RANGE := 8.0
const BASH_RANGE := 2.2         # Pancada: alcance do escudo, do peito de um ao do outro
const SHIELD_DOUBLE_GAP := 0.5  # Escudo Duplo: espera entre a primeira e a segunda vez
## Atordoante: escudo bloqueado SILENCE_TIME e depois SILENCE_GUARD s sem poder ser atordoado
## de novo (2026-10-11; era 1,5 s renovando a cada acerto: com muitas balas, sem escudo direto).
const SILENCE_TIME := 2.0
const SILENCE_GUARD := 3.0
## Flash: depois de cegar, o mesmo alvo fica BLIND_GUARD s sem poder ser cegado de novo, de
## quem for (2026-10-11; renovando a cada acerto, muitas balas deixavam a tela branca direto).
const BLIND_GUARD := 2.0
const SLOW_TIME := 1.5
## Veneno lento e longo, Queimadura rápida e curta (2026-10-14, pedido do usuário, como no The
## Bazaar): o veneno passou de 3 para 5 s com o mesmo total; a Bala Incendiária queima 1 s.
const POISON_TIME := 5.0
const BURN_HIT_TIME := 1.0
## Combustão Lenta (2026-10-14, desenho do usuário; ele quis -10%, eu tinha proposto -15%): por
## cópia, a Queimadura de quem a tem dura SLOW_BURN_TIME s a mais (antes da Persistência) e
## tira SLOW_BURN_DPS do dano por segundo (multiplica). Teto da Queimadura: BURN_MAX_TIME, abaixo
## dos 5 s do veneno base (filosofia: fogo curto e forte, veneno longo e com mais dano no total).
const SLOW_BURN_TIME := 0.5
const SLOW_BURN_DPS := 0.9
const BURN_MAX_TIME := 4.0
## Brasa e Combustível (2026-10-14, propostas minhas aprovadas pelo usuário para a build de
## fogo; números para testar com os amigos).
const BRASA_STEP := 0.25
const BRASA_MAX := 1.0
const FUEL_BONUS := 0.4
## Veneno em pedaços de POISON_TICK s, somados por atacante (2026-10-14): antes tirava vida a
## cada quadro sem dar crédito, e a Sanguessuga não curava com ele.
const POISON_TICK := 0.5
## Marca (2026-10-14, ideia do usuário, números aprovados): qualquer dano de quem tem a carta
## marca o alvo por MARK_TIME s (contorno através das paredes, só na tela de quem marcou);
## marcado, leva MARK_BONUS a mais do dano dele. Só marca de novo MARK_WAIT s depois da anterior.
const MARK_TIME := 3.0
const MARK_WAIT := 5.0
const MARK_BONUS := 0.15
const MARK_COLOR := Color(1.0, 0.3, 0.25)
## Ácido: depois de um tick de quem tem a carta, a cura cai ACID_HEAL por ACID_WINDOW s
## (renovado pelos ticks; o veneno e a queimadura dele valem pela duração inteira).
const ACID_HEAL := 0.5
const ACID_WINDOW := 1.0
## Sanguessuga: brilho verde no modelo (e borda verde na tela, HUD) quando cura.
const HEAL_GLOW_TIME := 0.45
const HEAL_GLOW_COLOR := Color(0.3, 1.0, 0.4)
## Contágio (2026-10-14, ideia minha aprovada pelo usuário; a volta para o próprio alvo no 1x1
## é pedido dele): o veneno original de quem tem a carta pula para inimigos a até
## CONTAGION_RANGE m com CONTAGION_SHARE da força; a cópia não pula; cada alvo pega no máximo
## uma cópia a cada CONTAGION_GUARD s. Sem ninguém perto, a cópia volta para o envenenado.
const CONTAGION_RANGE := 4.0
const CONTAGION_SHARE := 0.5
const CONTAGION_GUARD := 4.0
const CONTAGION_COLOR := Color(0.45, 0.95, 0.3)
## Estouro (2026-10-14, ideia do usuário, números meus; recarga do escudo +2 s pedida por
## ele): levantar o escudo estoura o veneno e a queimadura de quem a tem nos inimigos a até
## DETONATE_RANGE m: o que faltava sai de uma vez, x DETONATE_MULT (x DETONATE_BOTH com os
## dois), até DETONATE_CAP por alvo, e esses efeitos acabam. Conta como golpe (não tick).
const DETONATE_RANGE := 30.0
const DETONATE_MULT := 1.5
const DETONATE_BOTH := 2.0
const DETONATE_CAP := 60.0
const BURN_COLOR := Color(1.0, 0.5, 0.15)
## Reação em Cadeia (2026-10-14, ideia do usuário, números meus aprovados): quando uma
## aflição de quem tem a carta termina num inimigo (fica livre dela; Estouro e morte não
## contam), ele explode: toma CHAIN_DAMAGE e causa o mesmo a outros inimigos a até
## CHAIN_RANGE m, que pegam de novo a aflição que terminou, do mesmo dono (pode voltar e
## explodir de novo: o usuário achou justo). Cada alvo explode no máximo a cada CHAIN_GUARD s.
## Valores por cópias (1, 2). Dano fixo: não cresce com as cartas de Dano.
const CHAIN_DAMAGE := [12.0, 20.0]
const CHAIN_RANGE := [4.0, 5.0]
const CHAIN_GUARD := 3.0
## Cor da explosão pela aflição que terminou (pedido do usuário).
const CHAIN_COLORS := {"poison": CONTAGION_COLOR, "burn": Color(1.0, 0.28, 0.15),
	"slow": Color(0.45, 0.7, 1.0), "blind": Color(1.0, 1.0, 0.85), "silence": Color(0.75, 0.5, 1.0),
	"daze": Color(1.0, 0.85, 0.3), "frost": Color(0.55, 0.85, 1.0)}
const BLOODLUST_TIME := 3.0
const RAGE_THRESHOLD := 0.35
## Regeneração: cura depois de REGEN_DELAY sem levar dano e sem atacar (tiro ou Espada).
## Era 3 s só sem dano até 2026-10-11 (o usuário achou fácil demais, no começo sobretudo).
const REGEN_DELAY := 5.0
## Radar: alcance através das paredes por cópia (2026-10-11; antes via o mapa inteiro com 1).
const RADAR_RANGE := 30.0
## Pólvora Extra: coice para trás da mira a cada clique, só na horizontal (para cima viraria
## voo atirando no chão). RECOIL_BASE x cópias^RECOIL_EXP m/s, até RECOIL_MAX: pouco com uma,
## incômodo com muitas (pedido do usuário, 2026-10-11; números meus).
const RECOIL_BASE := 1.2
const RECOIL_EXP := 1.5
const RECOIL_MAX := 10.0
const BURST_GAP := 0.07
## Tiro semiautomático (2026-10-05): cada clique é um tiro; segurar não repete, só com a
## Metralhadora (auto_fire). Um clique um pouco antes de a arma ficar pronta fica guardado
## por este tempo e sai assim que der, como nos jogos de tiro com arma semiautomática:
## sem isso o clique adiantado se perderia e a arma pareceria falhar.
const SHOT_BUFFER := 0.15
const ADRENALINE_GAP := 0.4
const ADRENALINE_CUT := 0.5   # Adrenalina: parte da recarga que falta cortada ao refletir
const CRIT_BONUS := 1.5   # crítico: +150% de dano, somado aos outros bônus (shot_damage)
const TELEPORT_RANGE := 7.0
## Teleporte (refeito em 2026-10-05, como no Furor): atravessa paredes. Se o ponto cair
## dentro de uma peça, procura lugar livre na mesma linha, primeiro à frente até este
## tanto a mais, depois para trás; nunca sai pelo muro de fora do mapa.
const TELEPORT_OVERSHOOT := 4.0
const TELEPORT_STEP := 0.5
const SHIELD_HASTE_TIME := 1.5   # Passo Ligeiro
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
## Invisível, a arma da própria tela fica translúcida (pedido do usuário, 2026-10-09):
## CAMO_VIEW_ALPHA de transparência, chegando nela em 1 / CAMO_VIEW_FADE s.
const CAMO_VIEW_ALPHA := 0.6
const CAMO_VIEW_FADE := 6.0
## Camuflagem que falha (2026-10-11, pedido do usuário: dava para ficar num canto e nunca ser
## achado): depois de CAMO_TIRE s seguidos invisível, pisca visível para todos por
## CAMO_BLINK_TIME a cada CAMO_BLINK_EVERY, até aparecer (andar agachado não zera). Piscar não dá Emboscada.
const CAMO_TIRE := 8.0
const CAMO_BLINK_EVERY := 2.0
const CAMO_BLINK_TIME := 0.4
## Orbes do mapa (2026-10-06, no lugar do orbe de reset; ideia do usuário, números meus,
## aprovados): Velocidade dá +30% de velocidade por 4 s; Impulso lança uns 6 m para cima
## (com GRAVITY_RISE 30) e devolve dash, pulos e jato no ar.
const SPEED_ORB := 0.3
const SPEED_ORB_TIME := 4.0
const LAUNCH_ORB_SPEED := 19.0
const AMBUSH_COLOR := Color(0.72, 0.4, 1.0)
## Meteoro (refeito em 2026-10-09, pedido do usuário: com o Ctrl também no dash, só saía
## dash; números meus, aprovados; tontura de 0,8 s no alto foi pedido dele). Agachar no ar
## despenca (no ar não dá dash: o Shift continua dando). A altura no aperto decide a força:
## dano no centro de SLAM_DAMAGE a SLAM_DAMAGE_MAX entre SLAM_MIN_HEIGHT e SLAM_HIGH, metade
## na borda; tontura no centro a partir de SLAM_DAZE_HEIGHT. Quica para cima e espera
## SLAM_COOLDOWN para o próximo.
## Pulo-Foguete (refeito em 2026-10-09, pedido do usuário: carta para quem sabe se mover,
## inspirada na mochila da Raze do Valorant, sem ficar absurda; números meus, aprovados).
## Tiro no pé sobe ~4 m (era ~2,5, quase o pulo), soma o embalo em vez de cortar metade,
## 2 lançamentos por vez no ar (o 2o a 60%), inimigos levam RJ_ENEMY do empurrão.
const RJ_UP := 19.0
const RJ_SIDE := 15.0
const RJ_MIN_UP := 8.0
const RJ_CHARGES := 2
const RJ_SECOND := 0.6
const RJ_ENEMY := 0.4
const SLAM_SPEED := 32.0
const SLAM_MIN_HEIGHT := 1.2
const SLAM_HIGH := 8.0
const SLAM_INNER := 2.5            # centro: dano cheio e tontura
const SLAM_RANGE := 5.0            # borda: metade do dano
const SLAM_DAMAGE := 20.0
const SLAM_DAMAGE_MAX := 40.0
const SLAM_DAMAGE_STEP := 10.0     # por cópia a mais, no centro
const SLAM_DAZE_HEIGHT := 4.0
const SLAM_DAZE := 0.6
const SLAM_DAZE_TOP := 0.8         # caindo de SLAM_HIGH ou mais
const SLAM_BOUNCE := 14.0          # ~3,3 m, como o Pisão
const SLAM_COOLDOWN := 3.0
## Pisão (2026-10-06, ideia do usuário; números meus): cair na cabeça de um inimigo, pulando
## ou no dash pelo ar, fere e quica para cima, devolvendo o dash e os pulos no ar (escolha
## dele) para emendar outro pisão. No dash a área é mais generosa: de lado é difícil
## acertar a cabeça. A mesma pessoa só leva outro pisão depois de STOMP_REPEAT.
const STOMP_DAMAGE := 20.0
const STOMP_DAMAGE_STEP := 10.0   # por cópia a mais
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
## atravessa todas as paredes e causa SNIPER_DAMAGE x o dano da arma (4x 25 = 100: mata
## quem tem a vida base). Botão direito mira com zoom (campo de visão SCOPE_FOV, mouse
## mais lento na mesma proporção, anda a SCOPE_SPEED).
const SNIPER_TIME := 8.0
const SNIPER_DAMAGE := 4.0
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
const SHRINK_SLAM_DAMAGE := 15.0
const SHRINK_SLAM_PUSH := 1.25    # empurrão um pouco maior que o da Onda de Choque (pedido do usuário: nada exagerado)
const PIERCE_SHOTS := 3          # Perfurante: tiros por uso...
const PIERCE_SPEED := 3.0        # ...quantas vezes mais rápidos
const PIERCE_CONVERGE := 30.0   # ...e convergem com a mira a pelo menos 30 m (atravessar a fila)
const PIERCE_DAMAGE := 1.3       # ...e +30% de dano (2026-10-07; com atravessar jogadores, escudo e colete)
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
const REMOTE_METHODS := ["receive_grapple_kick", "receive_shockwave", "credit_damage", "bullet_refund", "teleport_to", "swap_to", "receive_stomp",
	"receive_slash", "ice_shove", "receive_slap", "receive_beam", "receive_hook", "hook_blocked",
	"hook_throw", "hook_release", "receive_bowl", "receive_slam", "receive_realm", "realm_blocked",
	"mark_seen", "receive_contagion", "receive_detonation", "receive_chain", "receive_shatter",
	"pressure_hit"]
## Gancho (mestra). Quem lança move a ponta (HOOK_SPEED, até HOOK_RANGE) e acha o alvo; a
## máquina do alvo decide (escudo bloqueia), puxa o próprio corpo (HOOK_PULL) até a frente
## de quem segura e fica lá por HOOK_HOLD. Arremesso a HOOK_THROW: parede dá HOOK_IMPACT e
## tontura (voo do Mega Tapa); outro jogador, HOOK_IMPACT nos dois. Quem segura solta ao
## levar HOOK_ESCAPE de dano. hook_state: 0 nada, 1 ponta voando, 2 puxando, 3 segurando.
const HOOK_RANGE := 20.0
const HOOK_SPEED := 60.0
const HOOK_PULL := 25.0
const HOOK_HOLD := 3.0
const HOOK_HOLD_DIST := 2.0
const HOOK_HOLD_SIDE := 0.9    # à direita de quem segura: no meio da tela tapava a mira
const HOOK_THROW := 25.0
const HOOK_THROW_LIFT := 6.0   # arco do arremesso (~0,5 s no ar, ~12 m em campo aberto)
const HOOK_IMPACT := 22.0
const HOOK_ESCAPE := 30.0
const HOOK_MISS_CD := 6.0
## Ímã leve (2026-10-07, o usuário achou difícil acertar): a menos de HOOK_MAGNET_RANGE da
## ponta, um inimigo à frente dela (até HOOK_MAGNET_CONE do rumo) e à vista puxa a ponta a
## HOOK_MAGNET_TURN rad/s. Medido: pega quem passa a até 1,3 m da ponta (sem o ímã, 0,9;
## com 2 rad/s seriam só 1,1 m).
## Nas outras máquinas a ponta desenhada segue reta (só o desenho; quem decide é quem lança).
const HOOK_MAGNET_RANGE := 4.0
const HOOK_MAGNET_TURN := 4.0
const HOOK_MAGNET_CONE := 0.5   # cosseno: 60 graus
const HOOK_CARRY_SPEED := 0.7
const HOOK_COLOR := Color(0.75, 0.75, 0.8)
var hook_state := 0
var hook_dir := Vector3.ZERO
var hook_tip := Vector3.ZERO
var hook_dist := 0.0
var hook_target: Player       # quem eu pego (na máquina de quem lança e nas outras, para a corrente)
var hooked_by: Player         # quem me pegou (todas as máquinas)
var hook_hold := 0.0          # tempo segurando que falta (máquina do alvo decide o fim)
var hook_taken := 0.0         # dano que levei segurando (solta em HOOK_ESCAPE)
var bowl := false             # fui arremessado pelo Gancho: bater em alguém machuca os dois
var splat_damage := SPLAT_DAMAGE
var hook_fx: MeshInstance3D
## Canhão Arcano (mestra): carga de BEAM_CHARGE (andando a BEAM_CHARGE_SPEED), depois um
## raio de BEAM_TIME que atravessa o cenário. Parado (no ar, flutua); a mira gira no
## máximo BEAM_TURN por segundo. Cada toque: BEAM_DAMAGE e arremesso pelo raio; o mesmo
## alvo de novo só depois de BEAM_REHIT.
const BEAM_CHARGE := 1.0
const BEAM_CHARGE_SPEED := 0.4
const BEAM_TIME := 2.5
const BEAM_RANGE := 40.0
const BEAM_RADIUS := 0.8
const BEAM_DAMAGE := 22.0
## Empurrão para FORA do raio (escolha do usuário, 2026-10-06: empurrando ao longo, o
## alvo seguia na linha e levava 4 toques seguidos sem a mira se mexer).
const BEAM_PUSH_SIDE := 20.0
const BEAM_PUSH_ALONG := 8.0
const BEAM_LIFT := 8.0
const BEAM_REHIT := 0.6
const BEAM_SHIELD_PUSH := 0.5
const BEAM_TURN := deg_to_rad(30.0)
const SLOW_AIM_LEAD := deg_to_rad(75.0)   # Canhão e Foguete: quanto o alvo do mouse pode ir à frente
const BEAM_COLOR := Color(0.78, 0.5, 1.0)
var beam_charge := 0.0     # carregando (todas as máquinas, para o visual)
var beam_timer := 0.0      # raio ligado
var beam_hits := {}        # alvo -> tempo até poder levar de novo
var beam_aim := Vector2.ZERO   # (yaw, pitch) para onde o mouse quer ir; a mira segue devagar
var beam_fx: Node3D
## Plataformas Suspensas (mestra, passiva desde 2026-10-07): sem pulos no ar sobrando, pular
## cria uma plataforma sob os pés, até PLAT_MAX em sequência, com PLAT_CHAIN para usar a
## próxima. A sequência acaba na última, quando o prazo passa ou ao tocar o chão, e então
## entra a recarga PLAT_COOLDOWN, que devolve as 3. A plataforma é um propulsor: lança quem
## pisa a PLAT_LAUNCH para cima, uma vez por jogador (SkyPlatform).
const PLAT_MAX := 3
const PLAT_LAUNCH := 14.0   # ~3,3 m de subida (o pulo normal sobe ~2,4)
const PLAT_CHAIN := 2.0
const PLAT_COOLDOWN := 8.0   # era 6 (2026-10-07, pedido do usuário: forte demais)
var plat_left := PLAT_MAX
var plat_chain := 0.0   # prazo para a próxima plataforma da sequência
var plat_cd := 0.0      # recarga da passiva
var on_sky_floor := false   # pisando numa plataforma no último passo (posto em _check_sky_pad)
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
const RIDE_SPEED := 10.0       # era 12 (2026-10-08, pedido do usuário: mais fácil de manobrar)
const RIDE_PITCH := deg_to_rad(20.0)
const RIDE_TURN := deg_to_rad(45.0)
const RIDE_JUMP := 10.0
const ROCKET_FREE_SPEED := 40.0
const ROCKET_FREE_TIME := 2.0
const ROCKET_BLAST_DAMAGE := 70.0   # era 45 (2026-10-08, pedido do usuário: difícil de acertar)
const ROCKET_BLAST_RADIUS := 7.0    # era 5 (2026-10-08, idem)
const ROCKET_LIFT := 14.0      # quem estava montado quando explodiu é lançado para cima
const ROCKET_COLOR := Color(1.0, 0.55, 0.2)
const ROCKET_FAT := 0.5        # raio do corpo do foguete montado
const RIDE_LIFT := 0.6         # sobe ao montar, para o foguete caber embaixo
var ride_timer := 0.0
var ride_age := 0.0
var ride_fx: Node3D
## Mecha (mestra): Q monta por MECH_BUILD (anda a MECH_BUILD_SPEED, sem atirar), depois
## MECH_TIME dentro: blindagem (MECH_ARMOR_BASE + MECH_ARMOR_PART da vida máxima) que leva o
## dano antes de tudo, imune a empurrões e puxões, corpo MECH_SCALE, MECH_SPEED, sem dash nem
## pulos extras, e o E lança mísseis (bala `missile`) no lugar do escudo. Q de novo, o tempo
## acabar ou a blindagem zerar: sai e explode (MECH_BLAST_*, maior com menos blindagem).
const MECH_BUILD := 1.2
const MECH_TIME := 8.0
const MECH_BUILD_SPEED := 0.4
const MECH_SPEED := 0.75
const MECH_SCALE := 1.4
const MECH_JUMP := 0.894        # raiz de 0,8: pulo com 80% da altura
const MECH_ARMOR_BASE := 60.0
const MECH_ARMOR_PART := 0.6
const MECH_EXIT_LOCK := 0.25    # o Q que montou não pode já sair
const MECH_BLAST_RADIUS := 5.0
const MECH_BLAST_MIN := 20.0    # blindagem cheia
const MECH_BLAST_MAX := 50.0    # blindagem zerada
const MISSILE_SPEED := 30.0
const MISSILE_CD := 2.5
const MISSILE_RADIUS := 3.5
const MISSILE_BASE := 20.0
const MISSILE_SCALE := 0.4      # do dano da bala
const MISSILE_MAX := 45.0
const MISSILE_SEEK := 5.0       # inimigo a até isto da linha do míssil puxa a curva
const MISSILE_TURN := deg_to_rad(60.0)
const MECH_PILOT := 0.8         # tamanho do personagem dentro (o mecha é que cresce)
const MECH_SEAT := 0.95         # altura do assento (o piloto aparece da cintura para cima)
const MECH_COLOR := Color(0.62, 0.68, 0.76)   # aço (barra da blindagem)
const MISSILE_COLOR := Color(1.0, 0.4, 0.2)
var mech_state := 0             # 0 nada, 1 montando, 2 dentro
var mech_timer := 0.0           # tempo que falta da montagem ou de dentro (todas as máquinas)
var mech_armor := 0.0
var mech_armor_max := 0.0
var mech_missile_cd := 0.0
var mech_fx: Node3D             # o modelo (os outros) ou a cabine na tela (quem joga)
var _mech_parts: Array = []
## Clone (mestra, ShadowClone): o clone vivo, o eco dos tiros (CLONE_ECHO do dano) e a troca.
const CLONE_ECHO := 0.5
const CLONE_SWAP_LOCK := 0.25   # o Q que criou não pode já trocar
const CLONE_COLOR := Color(0.55, 0.45, 0.95)
var clone: ShadowClone
signal clone_changed(event: String)   # registro do autoteste
signal mech_changed(state: int)     # registro do autoteste
signal mech_exploded(damage: float)
## Mega Tapa (mestra): Q ergue a mão por SLAP_WINDUP (aviso para o inimigo; anda normal,
## sem atirar) e então o tapa sai no leque curto à frente; arremessa (SLAP_PUSH para o lado, SLAP_LIFT
## para cima, sem controle no ar até pousar: slap_lock). Por SLAP_FLIGHT segundos, bater numa parede ainda rápido (SPLAT_MIN_SPEED)
## dá SPLAT_DAMAGE e deixa tonto (DAZE_TIME: lento e sem atirar).
const SLAP_RANGE := 4.5   # era 2,5, 3,2 e 3,6 (2026-10-07/08, pedidos do usuário; recarga 10 -> 8 s)
const SLAP_ARC := 50.0
const SLAP_SWIPE := 0.09    # a passada da mão (na tela e no modelo)
const SLAP_GHOSTS := 4      # cópias do rastro por tapa
const SLAP_GHOST_FADE := 0.18
const SLAP_WINDUP := 0.6   # 2026-10-07, pedido do usuário (ele pensou em 1 s; 0,6 escolhido por ele)
const SLAP_DAMAGE := 10.0
const SLAP_PUSH := 30.0   # era 22 e 24,5 (2026-10-08, pedido do usuário: a carta para tirar alguém de perto)
const SLAP_LIFT := 14.0   # era 12; subir junto alonga o voo (2026-10-08)
const SLAP_FLIGHT := 1.0
const SPLAT_DAMAGE := 20.0
const SPLAT_MIN_SPEED := 6.0
const DAZE_TIME := 0.6
const DAZE_SLOW := 0.5
# Visual do tonto (2026-10-09, pedido do usuário): estrelinhas na cabeça para os outros e,
# na própria tela, estrelas em volta da mira e a câmera balançando. Fica 1 s na tela (a
# tontura é 0,6 s e passaria quase sem ser vista).
const DAZE_FX_TIME := 1.0
const DAZE_ROLL := 0.07    # balanço da câmera (rad)
const SLAP_COLOR := Color(1.0, 0.75, 0.55)
var slap_flight := 0.0     # arremessado por um tapa: ainda pode bater na parede
var slap_lock := false     # no voo do tapa: sem controle no ar e sem o teto MAX_HSPEED até pousar
var slap_from := ""        # quem deu o tapa (crédito do impacto)
var daze_timer := 0.0      # tonto: não atira
var daze_fx := 0.0         # quanto falta do visual do tonto (todas as máquinas)
var daze_stars: DazeStars
var _net_dazed := false
var hand_pivot: Node3D     # primeira pessoa: a mão do tapa
var hand_3p: Node3D        # terceira pessoa: a mão grande erguida (o aviso que os outros veem)
var slap_windup := 0.0     # preparando o tapa (máquina dona)
var _hand_tween: Tween
var _hand_3p_tween: Tween
## Prisão de Gelo (mestra): caco reto que congela por ICE_TIME. Congelado: não age, não
## leva dano, desliza (ICE_FRICTION) e é empurrado por tiros (ICE_PUSH por ponto de dano,
## 5 m/s no tiro base de 25), explosões e encontrões (ice_shove). No vazio quica e o dano
## fica guardado (ice_debt) até derreter. Congelado, a área de acerto é a do bloco
## (ICE_HIT_RADIUS; antes era o corpo e o tiro na borda do gelo atravessava sem empurrar).
const ICE_TIME := 3.0
const ICE_SPEED := 60.0
const ICE_RANGE := 40.0
const ICE_PUSH := 0.2   # era 0,15 até 2026-10-07
const ICE_HIT_RADIUS := 0.625   # metade da largura do bloco (1,25 m)
const ICE_FRICTION := 2.5
const ICE_SHOVE_DASH := 1.5
const ICE_COLOR := Color(0.7, 0.95, 1.0)
const ICE_CAM_DISTANCE := 4.5
## Reforço de 2026-10-15 (pedido do usuário: difícil de acertar e retorno baixo; números meus
## aprovados): caco mais grosso (ICE_SHARD_RADIUS; era 0,22); no cenário estilhaça e põe
## ICE_SHARD_LAYERS camadas de Congelamento a até ICE_SHARD_RANGE m; o bloco guarda ICE_STORE
## do dano que leva de inimigos (até ICE_STORE_MAX) e solta tudo no degelo, com a quebra do
## gelo (FROST_BREAK). A carta também dá 1 camada por acerto (stat frost) e recarga 12 s (era 14).
const ICE_SHARD_RADIUS := 0.4
const ICE_SHARD_RANGE := 3.0
const ICE_SHARD_LAYERS := 2
const ICE_STORE := 0.5
const ICE_STORE_MAX := 50.0
var ice_timer := 0.0      # congelado por mais quanto tempo (todas as máquinas, para o visual)
var ice_debt := 0.0       # dano do vazio guardado até derreter (no máximo um)
var ice_store := 0.0      # dano guardado no bloco (máquina dona)
var ice_from: Player      # quem pôs dano no bloco por último (leva o crédito no degelo)
var ice_block: Node3D
## Congelamento (aflição, 2026-10-15; ideia do usuário, números meus aprovados): camadas de
## gelo, até FROST_MAX. Cada uma deixa a cadência e o recarregar FROST_STEP mais lentos. Na
## última o alvo congela por FROST_FREEZE s (não age, mas leva dano; FROST_FREEZE_HYPO com a
## Hipotermia de quem congelou) e as camadas zeram. O primeiro golpe nele (não conta veneno,
## queimadura e outros ticks) quebra o gelo: +FROST_BREAK de dano e acaba o congelado. Sem
## camada nova por FROST_HOLD s, perde uma a cada FROST_DECAY s. Depois de congelar, fica
## FROST_GUARD s sem congelar de novo (as camadas param em FROST_MAX - 1). Tenacidade encurta
## o congelado e o tempo das camadas.
const FROST_MAX := 5
const FROST_STEP := 0.06
const FROST_FREEZE := 0.5
const FROST_FREEZE_HYPO := 0.8
const FROST_BREAK := 20.0
const FROST_HOLD := 2.0
const FROST_DECAY := 1.0
const FROST_GUARD := 3.0
const FROST_COLOR := Color(0.55, 0.85, 1.0)
## Estilhaço: quebrar o gelo acerta inimigos a até SHATTER_RANGE m com metade do golpe e
## SHATTER_LAYERS camadas. É também quantas camadas a Reação em Cadeia repassa.
const SHATTER_RANGE := 4.0
const SHATTER_LAYERS := 2
## Choque Térmico (ideia do usuário, números meus): até congelar não muda nada; quando o
## congelado das camadas que você pôs acaba (quebrado ou pelo tempo), ele leva THERMAL_DAMAGE
## a mais (somado à quebra, se quebrou) e Queimadura de THERMAL_DPS por THERMAL_TIME s
## (Combustão Lenta e Persistência valem). Até 2026-10-15 valia no momento de congelar.
const THERMAL_DAMAGE := 10.0
const THERMAL_DPS := 10.0
const THERMAL_TIME := 1.5
## Estouro: dano por camada de quem estourou.
const DETONATE_FROST := 6.0
var frost_layers := 0       # camadas (máquina dona; nas outras, vem do estado em rede)
var frost_timer := 0.0      # até perder uma camada
var frost_freeze := 0.0     # congelado pelas camadas por mais quanto tempo (máquina dona)
var frost_guard := 0.0
var frost_from: Player      # quem pôs a última camada
var thermal_from: Player    # Choque Térmico de quem congelou (vale quando o congelado acabar)
var _frost_shown := false   # bloco do congelado à mostra (todas as máquinas)
var frost_mark: Node3D      # no inimigo: gelo e "n/5" em cima do corpo, criado no 1o uso
var _frost_mark_label: Label3D
var _frost_mark_n := -1
## Carta mestra que este jogador tem (a primeira de cards; "" se nenhuma).
var master_id := ""      # mestra da vez (com o Caos, a sorteada)
var master_cd := 0.0
## Mestra com cargas ("charges" na carta, desde 2026-10-10: Corrente com 2). master_cd é o
## tempo até a próxima carga voltar; elas voltam uma de cada vez.
var master_charges := 1
var master_gap := 0.0   # espera mínima entre dois usos seguidos (MASTER_CHARGE_GAP)
const MASTER_CHARGE_GAP := 0.4
## Caos: espera depois de usar a ativa sorteada e duração da passiva sorteada.
const CHAOS_WAIT := 8.0
const CHAOS_PASSIVE_TIME := 15.0
var chaos := false        # tem a mestra Caos
var chaos_used := false   # a ativa sorteada já foi usada (esperando a próxima)
var chaos_timer := 0.0    # passiva sorteada: quanto falta para trocar
var _chaos_last := ""     # último sorteio recebido pela rede (ver reset_for_round)
# Cartas Instáveis (mestra): cartas comuns que valem por UNSTABLE_TIME, por cima de `cards`.
const UNSTABLE_COUNT := 3
const UNSTABLE_TIME := 8.0
const UNSTABLE_EXCLUDED := ["fenix"]   # renascer por 8 s não faz sentido
var unstable_cards: Array = []
## Prorrogação: cartas comuns do baralho ganhas na rodada longa (match._overtime_step), até o
## fim da rodada, por cima de `cards`.
var overtime_cards: Array = []
signal overtime_card(id: String)   # aviso da HUD e registro do autoteste
var unstable_timer := 0.0
var unstable_icons: Array = []   # Sprite3D em cima do nome, criados no 1o uso
signal unstable_drawn(ids: Array)   # registro do autoteste e aviso da HUD
# Domínio do Rei (mestra): Q lança a corrente sombria (projétil, RCHAIN_*); pegou, os dois
# são puxados por REALM_PULL (sobem REALM_LIFT, a tela escurece) e vão para uma sala à parte
# (KingRealm, uma por lado) por REALM_TIME. `realm` = vaga + 1 dos dois lá dentro (0 = no
# mapa); só se enxergam, miram e se acertam jogadores no mesmo lugar (enemies). A volta é
# para onde cada um estava (realm_return), marcado no mapa (KingRealm.Marker).
# Refeita em 2026-10-12 (o usuário: tempo curto demais, faltava "ser levado" e algo que
# enfraqueça o alvo, como no Mordekaiser; números meus, aprovados): era mirar e ir, 6 s,
# +6%/s e recarga de 30 s.
# Refeita de novo em 2026-10-13 (pedido do usuário, como os "olhar e usar" do Paladins):
# Q com um inimigo na mira (até RCHAIN_RANGE, a até REALM_AIM_ANGLE do centro, à vista)
# lança a corrente, que o persegue a RCHAIN_SPEED; ele só escapa com o escudo levantado
# quando ela chega ou atrás de uma parede (ela não contorna). Sem alvo o Q não gasta. Em
# cima dos inimigos ao alcance, na tela de quem tem a mestra pronta, uma coroa com "Q"
# (_update_realm_mark), acesa no que o Q pegaria. Números meus, aprovados.
const RCHAIN_SPEED := 24.0
const RCHAIN_RANGE := 30.0
const RCHAIN_LIFE := 2.0          # não chegou nesse tempo: some (conta como erro)
const REALM_AIM_ANGLE := 0.105    # ~6 graus do centro da mira
const RCHAIN_COLOR := Color(0.6, 0.25, 0.95)
const REALM_PULL := 0.8
const REALM_LIFT := 1.5
const REALM_FADE_IN := 0.3
const REALM_TIME := 10.0
const REALM_BLOCKED_CD := 12.0    # escudo, parede ou tempo: recarga menor que a cheia (35 s)
const REALM_BONUS_RATE := 0.04   # quem lançou: +4% de dano por segundo lá dentro...
const REALM_BONUS_MAX := 0.3     # ...até +30% (aos 7,5 s)
const REALM_WEAKEN_RATE := 0.04  # o alvo: -4% de dano por segundo...
const REALM_WEAKEN_MAX := 0.3    # ...até -30%
const REALM_WIN_TIME := 6.0      # venceu lá dentro: fica com o bônus por mais 6 s
var rchain_state := 0         # corrente sombria: 0 nada, 1 voando, 2 esperando o alvo, 3 puxando
var rchain_tip := Vector3.ZERO
var rchain_dir := Vector3.FORWARD
var rchain_fx: MeshInstance3D
var rchain_target: Player     # quem a corrente persegue (em todas as máquinas)
var rchain_time := 0.0
var rchain_serial := 0        # um número por lançamento (o bot julga o escudo uma vez por corrente)
var rchain_incoming: Player   # no alvo: quem lançou a corrente nele (aviso da HUD, bots)
var realm_in_range: Array = []   # jogador local com a mestra pronta: inimigos com a coroa
var realm_aim: Player            # ...e o que o Q pegaria agora (coroa acesa)
var realm_mark: Sprite3D         # no inimigo: a coroa em cima do nome, criada no 1o uso
signal rchain_event(hit: bool)   # registro do autoteste: lançou e pegou ou errou
var realm_pull := 0.0         # sendo puxado para o Domínio (os dois), quanto falta
var realm_pull_partner: Player
var realm_pull_king := false
var realm_pull_from := Vector3.ZERO   # onde estava ao ser puxado (a volta é para cá, não para o alto)
var realm_fade := 0.0         # acabou de chegar: a tela clareia (HUD)
var realm := 0
var realm_bonus_timer := 0.0     # depois de vencer: quanto falta do bônus guardado
var realm_bonus_kept := 0.0
var realm_timer := 0.0
var realm_partner: Player
var realm_king := false       # foi quem lançou
var realm_return := Vector3.ZERO
var realm_marker: Node3D
var realm_crown: RealmCrown   # coroa de quem lançou (para os outros), criada no 1o uso
# Arpéu Ventoso (mestra, 3 cargas). Refeito em 2026-10-12 (o usuário: travado, abaixo das
# outras de movimento; referências: Homem-Aranha, Shingeki no Kyojin, Titanfall 2; números
# meus, aprovados). SEGURAR Q lança e prende; SOLTAR Q solta com o embalo (x
# GRAPPLE_RELEASE_BOOST e um pulo no ar). Preso, é um balanço: a corda puxa a GRAPPLE_ACCEL
# na direção do ponto sem apagar o embalo, não deixa se afastar e encurta a GRAPPLE_REEL;
# gravidade pela metade; WASD guia (GRAPPLE_AIR_STEER). Chegando segurando: pendura até
# GRAPPLE_HANG (pular salta da parede). Espaço preso solta com +GRAPPLE_LIFT para cima.
# Ventosa num inimigo: chute (GRAPPLE_KICK_*), puxado até ele. Era: puxão reto a 22 m/s sem
# gravidade, pendurado 3 s, Q prende e Espaço solta, 2 cargas de 8 s. O "segurar Q" é teste
# (o usuário prefere apertar; memória furor-arpeu-segurar-q).
# Só a máquina dona simula; o estado vai para as outras desenharem a corda.
const GRAPPLE_SPEED := 80.0
const GRAPPLE_COLOR := Color(0.95, 0.35, 0.3)   # selo da HUD, o vermelho da ventosa
const GRAPPLE_RANGE := 35.0
const GRAPPLE_ACCEL := 35.0
const GRAPPLE_REEL := 6.0
const GRAPPLE_GRAVITY := 0.5
const GRAPPLE_AIR_STEER := 14.0   # m/s² com as teclas (o dobro do controle no ar comum, ~7)
const GRAPPLE_MAX_SPEED := 28.0
const GRAPPLE_RELEASE_BOOST := 1.15
const GRAPPLE_MAX_TIME := 4.0     # preso balançando no máximo isso
const GRAPPLE_MIN_HOLD := 0.2     # soltar o Q antes disso não solta (um toque ainda dá um puxão curto)
const GRAPPLE_ARRIVE := 1.5    # a esta distância do ponto (do peito), chegou
const GRAPPLE_HANG := 2.0
const GRAPPLE_LIFT := 3.0
const GRAPPLE_REFUND := 1.0    # errou: a carga volta neste tempo
const GRAPPLE_KICK_SPEED := 30.0
const GRAPPLE_KICK_DAMAGE := 20.0
const GRAPPLE_KICK_REACH := 1.6
var grapple_state := 0         # 0 nada, 1 ventosa voando, 2 balançando, 3 pendurado, 4 indo chutar
var grapple_len := 0.0         # comprimento da corda (encurta a GRAPPLE_REEL)
var grapple_target: Player     # chute: o inimigo onde a ventosa grudou
var grapple_age := 0.0         # tempo preso (balanço ou chute)
var in_master_held := false
var grapple_tip := Vector3.ZERO      # onde está a ventosa (voando ou grudada)
var grapple_dir := Vector3.ZERO
var grapple_dist := 0.0
var grapple_normal := Vector3.ZERO   # da superfície onde grudou
var grapple_timer := 0.0       # puxando: tempo máximo (preso numa quina); pendurado: quanto falta
var grapple_refund := 0.0
var grapple_fx: Node3D         # desentupidor e corda (_grapple_visual), criados no 1o uso
var grapple_plunger: Node3D
var grapple_cord: MeshInstance3D
signal grappled(state: int)    # registro do autoteste
signal realm_changed(entered: bool, won: bool)   # registro do autoteste e HUD
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
var dash_seek_target: Player = null   # Bote: alvo deste dash
var dash_seek_left := 0.0             # Bote: quanto o dash ainda pode curvar (rad)
var click_id := 0       # número do clique; vai na bala (Reciclagem: 0 = não devolve)
var skin_stacks := 0          # Couro Grosso: redução atual por golpe
var skin_stack_timer := 0.0   # Couro Grosso: tempo desde o último golpe levado
var revenge_target := ""      # Vingança: nome do nó de quem te matou na rodada anterior
var was_on_floor := true
var was_shielding := false
var eye_dip := 0.0

var slow_timer := 0.0
var slow_amount := 0.0
var poisons: Array = []   # [{dps, time, from, acc, copy}] (copy: veio do Contágio, não pula)
var contagion_guard := 0.0   # Contágio: enquanto > 0, não pega outra cópia
var _contagion_sent := {}    # Contágio, na máquina do envenenado: nome -> pode mandar de novo (ms)
var poison_tick := POISON_TICK
var marks := {}    # Marca, na máquina do marcado: atacante -> [fim, pode marcar de novo] em ms
var marked := {}   # Marca, na máquina de quem marcou: nome do alvo -> fim do contorno em ms
var acid_timer := 0.0
var heal_glow := 0.0   # Sanguessuga: 1 -> 0 em HEAL_GLOW_TIME (modelo e HUD)
var _net_heal := false
var silence_timer := 0.0
var silence_guard := 0.0   # Atordoante: enquanto > 0, novo atordoamento não pega
var bloodlust_timer := 0.0
var since_damage := 0.0
var since_attack := 0.0   # tiro ou golpe de Espada (Regeneração)
var last_attacker: Player       # quem causou o último dano (crédito de quem empurra no vazio)
var sky_active := false         # Alto demais: contando (até SKY_RESET abaixo do teto)
var sky_timer := 0.0            # tempo até o próximo dano lá em cima
var sky_ticks := 0              # danos já levados nesta subida
var sky_low := 0.0              # tempo abaixo do teto desde que desceu
var sky_credit: Player          # quem acertou antes de subir (leva o abate)
var zone_timer := ZONE_GRACE    # Prorrogação: tempo até o próximo dano fora do círculo
var zone_out := false           # fora do círculo agora (para a HUD)
var zone_credit: Player         # quem acertou antes de sair (leva o abate)
## Placar (Tab): quem causou dano e quando (Time.get_ticks_msec), só na máquina dona. Na
## morte, o último que causou dano leva o abate e os outros dos últimos ASSIST_TIME s, a
## assistência. Vai junto com o aviso de morte, então todas as máquinas contam igual.
var recent_hits := {}           # Player -> ms
var death_killer := ""          # nome do nó de quem matou ("" = ninguém, ex.: a própria bala)
var death_assists: Array = []
var revives_left := 0
var blind_timer := 0.0
var blind_guard := 0.0   # Flash: enquanto > 0, novo Flash não pega (efeito + BLIND_GUARD)
var blind_guard_total := 1.0   # ...o tamanho dela quando começou (HUD)
var net_guards := 0   # outra máquina: bit 1 protegido do Flash, 2 da Atordoante, 4 da Troca-Troca
var guard_icons := {}   # ícones em cima do nome (Flash/Atordoante), criados no 1o uso
var echo_timer := 0.0
var echo_left := 0        # Eco: levantadas automáticas que ainda faltam neste ciclo
var adrenaline_used := false   # Adrenalina: já cortou a recarga neste escudo levantado
var haste_timer := 0.0    # Passo Ligeiro: mais rápido por mais quanto tempo
## Cartas de 2026-10-07 (números meus, aprovados; Parkour com 1 s a pedido do usuário).
## Segunda Pele: a cada SKIN_DELAY sem levar dano, +armor_regen de colete, até SKIN_CAP por
## cópia (no máximo ARMOR_MAX). Parkour: pulo de parede devolve um dash no ar e dá
## PARKOUR_SPEED por cópia durante PARKOUR_TIME. Recarga Perfeita: R de novo com o anel entre
## PERFECT_START e PERFECT_END termina a recarga e o pente vale +PERFECT_DAMAGE; fora da
## faixa, a recarga atrasa PERFECT_MISS. Uma tentativa por recarga.
const SKIN_DELAY := 5.0
const SKIN_CAP := 30.0
const PARKOUR_SPEED := 0.2
## Build de movimento (2026-10-11). Velocidade Letal: +2% de dano por m/s acima de andar.
const SPEED_DAMAGE_FROM := 9.0
const SPEED_DAMAGE_RATE := 0.02
## Vulto: acima de 12 m/s (não vale andando, só no embalo), menos dano de balas por cópia.
const BLUR_SPEED := 12.0
const BLUR_REDUCE := [0.0, 0.2, 0.35]
## Recarga no Embalo: a recarga no ar ou deslizando anda até 2x mais rápido.
const AIR_RELOAD_MAX := 1.0
## Bote: inimigo à vista a até 10 m e até 35 graus da direção do dash; o dash curva até ele
## a 8 rad/s, no máximo 35 graus no total.
const DASH_SEEK_RANGE := 10.0
const DASH_SEEK_ANGLE := deg_to_rad(35.0)
const DASH_SEEK_TURN := 8.0
## Build de escopeta (2026-10-15, pedido do usuário: alto dano de perto, ruim de longe, com
## movimento para chegar; cartas e números meus aprovados). Arrancada: dash com um inimigo à
## vista a até STRIKE_RANGE m e até DASH_SEEK_ANGLE da direção do dash: o próximo tiro, em até
## STRIKE_TIME s, soma STRIKE_DAMAGE ao dano (soma única). Pressão: acertar a até PRESSURE_RANGE
## m dá PRESSURE_SPEED de velocidade por PRESSURE_TIME s e adianta a recarga do dash em
## PRESSURE_DASH s, no máximo uma vez a cada FLAT_GAP s (o leque da escopeta conta uma vez).
const STRIKE_RANGE := 20.0
const STRIKE_TIME := 1.0
const STRIKE_DAMAGE := 0.3
const PRESSURE_RANGE := 6.0
const PRESSURE_SPEED := 0.25
const PRESSURE_TIME := 1.5
const PRESSURE_DASH := 1.0
## Efeitos de valor fixo por acerto (camada de gelo, Brasa, Hipotermia, Pressão) contam no
## máximo uma vez a cada FLAT_GAP s de cada atirador em cada alvo (2026-10-15, pedido do
## usuário: o baralho de spam não pode ser o principal das aflições; não proíbe, só
## desacelera). Arma normal (0,3 s por tiro) não sente; o leque da escopeta conta uma vez.
const FLAT_GAP := 0.25
var strike_timer := 0.0     # Arrancada: o próximo tiro sai mais forte enquanto > 0
var pressure_timer := 0.0   # Pressão: mais rápido enquanto > 0
var _pressure_next := 0     # Pressão: ms em que pode valer de novo
var _flat_next := {}        # FLAT_GAP: atirador -> ms em que o próximo efeito fixo vale (máquina do alvo)
## Alcance (2026-10-15, build de escopeta): a bala some ao ficar a mais de stats["bullet_range"]
## m, em linha reta, de onde saiu. A base é RANGE_FREE, que quer dizer sem limite: só quem tem
## perda de Alcance nas cartas sente (os ganhos sozinhos voltam a RANGE_FREE ou mais).
const RANGE_FREE := 200.0


## Alcance desta arma em metros, ou 0.0 se não tiver limite.
func bullet_reach() -> float:
	var r := float(stats["bullet_range"])
	return r if r < RANGE_FREE - 0.01 else 0.0


## Sangue Frio: por cópia, +25% de dano e balas 30% mais rápidas parado (abaixo de 1 m/s) ou
## agachado sem deslizar, no chão.
const STILL_DAMAGE := 0.25
const STILL_SPEED := 0.3
const STILL_MAX_SPEED := 1.0
## Couro Grosso (desenho do usuário): cada golpe soma 1 de redução nos seguintes, até 5 (8
## com 2 cópias); 1,5 s sem golpe zera. Dano contínuo (tick) não conta nem é reduzido.
const SKIN_STACK_MAX := [0, 5, 8]
const SKIN_STACK_RESET := 1.5
const PARKOUR_TIME := 1.0
const PERFECT_START := 0.5
const PERFECT_END := 0.7
const PERFECT_DAMAGE := 0.15
const PERFECT_MISS := 0.4
const PERFECT_COLOR := Color(1.0, 0.82, 0.3)
## Casca Dura: um golpe de TOUGH_TRIGGER ou mais deixa TOUGH_TIME levando TOUGH_REDUCE a
## menos. Dash Duplo (como o Escudo Duplo): cada cópia é um dash a mais, sozinho,
## DASH_ECHO_DELAY depois do anterior acabar, para onde você estiver apertando; repete os
## efeitos do dash (Atropelar, Saque Rápido, Esquiva) e no ar não gasta dash.
const TOUGH_TRIGGER := 30.0
const TOUGH_TIME := 1.0
const TOUGH_REDUCE := 0.5
const TOUGH_COLOR := Color(0.85, 0.7, 0.45)
const DASH_ECHO_DELAY := 0.1
var tough_timer := 0.0
var dash_echo_left := 0
var dash_echo_wait := 0.0
var skin_timer := 0.0
var parkour_timer := 0.0
var perfect_tried := false   # já tentou nesta recarga
var perfect_mag := false     # pente atual veio de uma recarga perfeita
signal perfect_reloaded(ok: bool)   # registro do autoteste
var glided := false       # Planador: planou neste salto (vale até tocar o chão)
var boot_fuel := BOOT_FUEL   # Bota Foguete: jato que sobra (s)
var boot_armed := false   # apertou pular no ar sem pulos sobrando; vale enquanto segurar
var boosting := false     # jato ligado neste quadro (vai para as outras máquinas no estado)
var air_time := 0.0       # há quanto tempo está no ar (bônus de dano da Bota Foguete)
var boot_fx: CPUParticles3D
var stomp_hits := {}      # Pisão: inimigo -> quando levou o último (ms)
var burn_timer := 0.0     # Chamas: queimando por mais quanto tempo
var burn_dps := 0.0
var burn_acc := 0.0
var burn_from: Player = null
var aff_from := {}        # Reação em Cadeia: aflição -> quem a pôs por último (lentidão, cegueira, escudo bloqueado, tontura)
var blind_time := 0.0     # Reação em Cadeia: duração da última cegueira (para repassar)
var chain_guard := 0.0    # Reação em Cadeia: enquanto > 0, não explode de novo
var _chain_ended := []    # Reação em Cadeia: aflições suas que terminaram neste passo
var burn_heat := 0.0      # Brasa: +BRASA_STEP por acerto de quem pôs o fogo, até BRASA_MAX; zera no fim
## Caído (2x2). Enquanto caído, alive é falso: balas, áreas, bots e o fim da rodada já o
## tratam como fora. Só a máquina dona decide cair, levantar e morrer; as outras só contam
## o tempo para mostrar.
static var downs_enabled := false   # a partida liga no 2x2
var immortal := false   # sala de teste: a vida para em 1
var downed := false
var bleed_timer := 0.0
var bleed_total := 1.0
var revive_progress := 0.0
var downs := 0                # quedas nesta rodada
var protect_timer := 0.0
# Proteção do começo da rodada (2026-10-12, pedido do usuário: quem matava com um tiro
# abria a rodada matando alguém sempre). SPAWN_PROTECT s sem levar dano desde o fim da
# contagem; atacar (tiro, mestra, espada) encerra a própria proteção. Em todas as máquinas
# para o contorno; o dano é decidido na dona. Rede: bit 256 do estado.
const SPAWN_PROTECT := 3.0
const PROTECT_COLOR := Color(1.0, 0.9, 0.55)
var spawn_protect := 0.0
var protect_mat: ShaderMaterial
var _protect_shown := false
var _net_protected := false
var down_credit: Array = ["", []]   # abate e assistências de quando caiu (vale se o prazo acabar)
var down_marker: Node3D
var swap_timer := 0.0     # Troca-Troca: falta quanto para a troca (na máquina de quem levou o tiro)
var swap_lock := 0.0      # Troca-Troca: não começa outra troca enquanto for maior que zero
var swap_partner: Player = null
var still_time := 0.0     # parado há quanto tempo (Camuflagem)
var speed_orb_timer := 0.0   # orbe de Velocidade ligado por mais quanto tempo
var ambush_timer := 0.0   # Emboscada ligada por mais quanto tempo (todas as máquinas, para o brilho)
var ambush_shot := false  # Camuflagem: o primeiro disparo da Emboscada atravessa as paredes (máquina dona)
var ambush_cd := 0.0      # falta quanto para poder ganhar outra Emboscada (só a máquina dona)
var ambush_mat: ShaderMaterial
var slamming := false     # despencando com o Meteoro
var slam_height := 0.0    # altura do chão quando o Meteoro começou
var slam_cd := 0.0
var rj_charges := RJ_CHARGES   # Pulo-Foguete: lançamentos que ainda valem até tocar o chão
var slam_pressed := false # Meteoro: agachar apertado no ar neste passo (não vira dash)
var shot_bonus := 0.0     # bônus de dano do disparo atual (Última Bala), somado em shot_damage
var shot_count := 1       # balas do disparo atual (Escopeta com o pente quase vazio: menos)
var free_ammo_shown := 0    # Cartucheira: quantas balas do último tiro saíram de graça (HUD)
var free_ammo_flash := -100000   # quando (ms), para a piscada no arco do pente

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
var viewmodel_meshes: Array = []
var viewmodel_fade := 0.0
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
var mark_mat: ShaderMaterial   # Marca: contorno através das paredes na tela de quem marcou
var _mark_look := false
var heal_mat: StandardMaterial3D   # Sanguessuga: camada verde enquanto heal_glow > 0


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
	hand.scale = Vector3.ONE * 1.5   # acompanha o alcance de 3,6 m (era 1,3 com 3,2 m)
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
	# Mão do Mega Tapa: dentro do modelo (acompanha tamanho e achatamento), num nó que desfaz
	# o giro e a escala do modelo, para as posições serem em metros no espaço do jogador.
	var holder := Node3D.new()
	holder.rotation.y = PI
	holder.scale = Vector3.ONE / MODEL_SCALE
	model.add_child(holder)
	hand_3p = Node3D.new()
	hand_3p.visible = false
	holder.add_child(hand_3p)
	var big_hand := _make_hand()
	big_hand.scale = Vector3.ONE * 3.0
	_no_shadows(big_hand)
	hand_3p.add_child(big_hand)
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
	# Vingança: quem te matou na rodada que acabou (quem sobreviveu não tem alvo). Igual em
	# todas as máquinas: death_killer vem do _net_die.
	revenge_target = death_killer if not alive else ""
	skin_stacks = 0
	unstable_cards.clear()
	unstable_timer = 0.0
	overtime_cards.clear()
	_mech_clear()
	_clone_clear()
	_update_unstable_icons()
	_realm_clear()
	_grapple_clear()
	grapple_refund = 0.0
	stats = CardDB.compute_stats(BASE_STATS, cards)
	var masters := cards.filter(CardDB.is_master)
	master_id = masters[0] if not masters.is_empty() else ""
	master_cd = 0.0
	master_charges = master_max_charges()
	master_gap = 0.0
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
	ice_store = 0.0
	ice_from = null
	frost_layers = 0
	frost_timer = 0.0
	frost_freeze = 0.0
	frost_guard = 0.0
	frost_from = null
	thermal_from = null
	_frost_shown = false
	strike_timer = 0.0
	pressure_timer = 0.0
	_flat_next.clear()
	_ice_visual(false)
	slap_flight = 0.0
	slap_lock = false
	if slap_windup > 0.0:
		_cancel_slap(false)
	daze_timer = 0.0
	daze_fx = 0.0
	_net_dazed = false
	_update_daze_fx(0.0)
	_end_beam(false)
	plat_left = PLAT_MAX
	plat_chain = 0.0
	plat_cd = 0.0
	meteor_left = 0
	meteor_window = 0.0
	ride_timer = 0.0
	_ride_visual(false)
	_hook_clear()
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
	poison_tick = POISON_TICK
	contagion_guard = 0.0
	chain_guard = 0.0
	_chain_ended.clear()
	aff_from.clear()
	_contagion_sent.clear()
	marks.clear()
	marked.clear()
	acid_timer = 0.0
	heal_glow = 0.0
	silence_timer = 0.0
	silence_guard = 0.0
	bloodlust_timer = 0.0
	since_damage = 0.0
	since_attack = 0.0
	recent_hits.clear()
	last_attacker = null
	sky_active = false
	sky_credit = null
	zone_timer = ZONE_GRACE
	zone_out = false
	zone_credit = null
	revives_left = stats["revives"]
	blind_timer = 0.0
	blind_guard = 0.0
	echo_timer = 0.0
	echo_left = 0
	haste_timer = 0.0
	skin_timer = 0.0
	parkour_timer = 0.0
	tough_timer = 0.0
	dash_echo_left = 0
	dash_echo_wait = 0.0
	perfect_tried = false
	perfect_mag = false
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
	burn_heat = 0.0
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
	ambush_shot = false
	ambush_cd = 0.0
	_restore_overlay()
	slamming = false
	slam_cd = 0.0
	rj_charges = RJ_CHARGES
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
		model.scale = Vector3.ONE * _model_size()
		model.position.y = MECH_SEAT * body_scale / MECH_SCALE if mech_state > 0 else 0.0
	if ring:
		# O disco do chão acompanha só quando encolhe (Formiga, Nanico); maior, fica igual.
		ring.scale = Vector3.ONE * minf(body_scale, 1.0)
	_mech_update_fx()


## Tamanho do modelo: o do corpo; no Mecha, o piloto fica menor (MECH_PILOT) e sentado no
## alto da cabine (MECH_SEAT), e o mecha em volta ocupa o tamanho do corpo.
func _model_size() -> float:
	var s := MODEL_SCALE * float(stats["body_scale"])
	return s * MECH_PILOT / MECH_SCALE if mech_state > 0 else s


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
			slow_aim_input(motion.relative * sens)
			return
		look_yaw = wrapf(look_yaw - motion.relative.x * sens, -PI, PI)
		head.rotate_x(-motion.relative.y * sens)
		head.rotation.x = clampf(head.rotation.x, -1.5, 1.5)
		sway = (sway - motion.relative * 0.0004).limit_length(0.05)


## Mira lenta (Canhão Arcano e Foguete): o mouse move o alvo (beam_aim), que fica no
## máximo SLOW_AIM_LEAD à frente da mira: arrastando muito, ele passava de meia volta e a
## mira ia pelo lado mais curto, ao contrário do mouse (relato do usuário, 2026-10-06).
func slow_aim_input(rel: Vector2) -> void:
	var lead := clampf(angle_difference(look_yaw, beam_aim.x) - rel.x, -SLOW_AIM_LEAD, SLOW_AIM_LEAD)
	beam_aim.x = wrapf(look_yaw + lead, -PI, PI)
	var pitch_limit := 1.5 if beam_timer > 0.0 else RIDE_PITCH
	beam_aim.y = clampf(beam_aim.y - rel.y, -pitch_limit, pitch_limit)


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
		in_master_held = false
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
	in_master_held = Input.is_action_pressed("master")


# ---------------------------------------------------------------- visual

func _process(delta: float) -> void:
	if Prof.enabled:
		var t := Time.get_ticks_usec()
		_frame_step(delta)
		Prof.lap("jogador: quadro", t)
	else:
		_frame_step(delta)


func _frame_step(delta: float) -> void:
	if (beam_timer > 0.0 or ride_timer > 0.0) and is_human:
		var turn := (BEAM_TURN if beam_timer > 0.0 else RIDE_TURN) * delta
		look_yaw = rotate_toward(look_yaw, beam_aim.x, turn)
		var pitch_aim := beam_aim.y if beam_timer > 0.0 else clampf(beam_aim.y, -RIDE_PITCH, RIDE_PITCH)
		head.rotation.x = rotate_toward(head.rotation.x, pitch_aim, turn)
	if ride_fx:
		_update_ride_fx()
	if hook_fx:
		_update_hook_fx(delta)
	if rchain_fx:
		_update_rchain_fx(delta)
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
	if daze_fx > 0.0 or daze_stars:
		_update_daze_fx(delta)
	if realm_crown or realm_bonus_timer > 0.0 or (realm > 0 and realm_king):
		_update_crown()
	if grapple_state > 0 or (grapple_fx and grapple_fx.visible):
		_update_grapple_fx(delta)
	var guard_on := spawn_protect > 0.0 and alive and not is_human
	if guard_on != _protect_shown:
		_protect_shown = guard_on
		_restore_overlay()
	if not is_human:
		# Aliado: nome e vida sempre à vista, através das paredes, na cor do time.
		var ally := viewer != null and viewer.is_ally(self)
		if ally != _ally_look:
			_set_ally_look(ally)
		var mark_on := alive and viewer != null and viewer != self and viewer.is_marking(self)
		if mark_on != _mark_look:
			_set_mark_look(mark_on)
		tag.no_depth_test = ally or mark_on or (viewer != null and viewer != self and viewer.stats["radar"] > 0 \
				and global_position.distance_squared_to(viewer.global_position) <= pow(viewer.stats["radar"] * RADAR_RANGE, 2.0))
		if tag.visible and downed:
			tag.text = "%s\nCAÍDO" % player_name
		elif tag.visible:
			# Mecha: a blindagem entre colchetes.
			tag.text = "%s\n%d" % [player_name, ceili(health)] + (" +%d" % ceili(armor) if armor > 0.0 else "") \
				+ ("  [%d]" % ceili(mech_armor) if mech_state == 2 else "")
		_update_guard_icons()
		_update_realm_mark()
		if frost_layers > 0 or frost_mark:
			_update_frost_mark()
		if ally_arrow:
			# Parceiro caído: a seta pisca para chamar atenção.
			ally_arrow.modulate.a = (0.35 + 0.65 * absf(sin(Time.get_ticks_msec() * 0.008))) if downed else 1.0
	if model:
		_update_animation()
		_update_hit_flash(delta)
		if heal_glow > 0.0:
			_update_heal_glow(delta)
	elif heal_glow > 0.0:
		heal_glow = maxf(0.0, heal_glow - delta / HEAL_GLOW_TIME)   # sem modelo: só a HUD
	if is_human:
		_camera_feel(delta)
		_realm_scan()


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


## Liga ou desliga o contorno da Marca (o do aliado, em vermelho, através das paredes).
func _set_mark_look(on: bool) -> void:
	_mark_look = on
	if model == null:
		return
	if on and mark_mat == null:
		if _rim_shader == null:
			_rim_shader = Shader.new()
			_rim_shader.code = ALLY_RIM_SHADER
		mark_mat = ShaderMaterial.new()
		mark_mat.shader = _rim_shader
		mark_mat.set_shader_parameter("rim_color", Color(MARK_COLOR, 0.75))
	_restore_overlay()


## Sanguessuga curou: brilho verde no modelo (visto pelos outros) e borda verde na tela (HUD).
func heal_flash() -> void:
	var was := heal_glow > 0.0
	heal_glow = 1.0
	if model == null or was:
		return
	if heal_mat == null:
		heal_mat = StandardMaterial3D.new()
		heal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		heal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		heal_mat.albedo_color = Color(HEAL_GLOW_COLOR, 0.0)
	_restore_overlay()


func _update_heal_glow(delta: float) -> void:
	heal_glow = maxf(0.0, heal_glow - delta / HEAL_GLOW_TIME)
	if heal_mat:
		heal_mat.albedo_color.a = heal_glow * 0.6
	if heal_glow <= 0.0:
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
	model.scale = squash * _model_size()
	if hit_flash <= 0.0:
		_restore_overlay()


## Camuflagem: parado por CAMO_DELAY some da vista dos outros (o próprio jogador vê a
## tela escurecer nas bordas pelo HUD). Atirar ou levar dano revela (reveal).
func _update_camo(delta: float) -> void:
	if ambush_timer > 0.0:
		ambush_timer -= delta
		if ambush_timer <= 0.0:
			ambush_shot = false   # não atirou nos 3 s: perde o tiro que atravessa
			_restore_overlay()
	if stats["camo"] <= 0 or not alive:
		still_time = 0.0
		_fade_viewmodel(0.0, delta)
		return
	_fade_viewmodel(CAMO_VIEW_ALPHA if is_hidden() and not camo_blink() else 0.0, delta)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var still := velocity.length() < 0.6
	var sneaking := is_hidden() and hspeed <= float(stats["move_speed"]) * CAMO_SNEAK and absf(velocity.y) < 2.0
	if (still or sneaking) and not is_shielding():
		still_time += delta
	elif still_time > 0.0:
		reveal()
	if model and alive:
		var show := not is_hidden() or camo_blink() or (viewer != null and viewer.is_ally(self))
		model.visible = show
		ring.visible = show
		tag.visible = show


## Arma da própria tela translúcida enquanto invisível. No Compatibility a `transparency`
## do GeometryInstance3D não tem efeito (conferido em print), então cada material da arma
## ganha uma cópia com alfa, trocada só enquanto o valor não é 0 (opaca, nada muda).
## viewmodel_meshes: [malha, superfície (-1 = material_override), o que estava posto
## (volta ao ficar opaca), cópia, alfa original].
func _fade_viewmodel(target: float, delta: float) -> void:
	if viewmodel == null or is_equal_approx(viewmodel_fade, target):
		return
	var was := viewmodel_fade
	viewmodel_fade = move_toward(viewmodel_fade, target, CAMO_VIEW_FADE * delta)
	if viewmodel_meshes.is_empty():
		_collect_viewmodel_mats()
	for e in viewmodel_meshes:
		if not is_instance_valid(e[0]):
			continue   # rastro do Mega Tapa (Caos), que some sozinho
		var copy: BaseMaterial3D = e[3]
		copy.albedo_color.a = float(e[4]) * (1.0 - viewmodel_fade)
		if was == 0.0 or viewmodel_fade == 0.0:
			var mat: Material = copy if viewmodel_fade > 0.0 else e[2]
			var mi: MeshInstance3D = e[0]
			if e[1] < 0:
				mi.material_override = mat
			else:
				mi.set_surface_override_material(e[1], mat)


func _collect_viewmodel_mats() -> void:
	var copies := {}
	for mi in viewmodel.find_children("*", "MeshInstance3D", true, false):
		var slots: Array = [-1] if mi.material_override else range(mi.mesh.get_surface_count() if mi.mesh else 0)
		for s in slots:
			var old: Material = mi.material_override if s < 0 else mi.get_active_material(s)
			if not old is BaseMaterial3D:
				continue
			if not copies.has(old):
				var c: BaseMaterial3D = old.duplicate()
				c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				c.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				copies[old] = c
			viewmodel_meshes.append([mi, s, mi.material_override if s < 0 else mi.get_surface_override_material(s),
					copies[old], (old as BaseMaterial3D).albedo_color.a])


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


## Esperas mostradas na HUD (CardTimers): quanto falta para a Regeneração começar a curar e
## para o próximo colete da Segunda Pele; 0 sem a carta ou quando não há o que ganhar.
func regen_wait() -> float:
	if stats["regen"] <= 0.0 or not alive or health >= stats["max_health"]:
		return 0.0
	return maxf(0.0, REGEN_DELAY - minf(since_damage, since_attack))


func skin_wait() -> float:
	if stats["armor_regen"] <= 0.0 or not alive \
			or armor >= minf(ARMOR_MAX, SKIN_CAP * ceilf(float(stats["armor_regen"]) / 15.0)):
		return 0.0
	return maxf(0.0, SKIN_DELAY - skin_timer)


## Protegido do Flash / da Atordoante agora. Na máquina dona pelos timers; nas outras pelo
## estado em rede (bits 32 e 64), que é o que o ícone em cima do nome usa.
## Em cima do nome do inimigo, para quem tem Flash ou Atordoante: o ícone da carta apagado
## enquanto ele está protegido dela ("não adianta agora"). Um Sprite3D por carta, criado no
## 1o uso e só ligado/desligado depois.
func _update_guard_icons() -> void:
	var want := {}
	if viewer != null and viewer != self and viewer.is_enemy(self) and tag.visible:
		if viewer.stats["blind"] > 0.0 and flash_guarded():
			want["flash"] = true
		if viewer.stats["shield_break"] > 0 and stun_guarded():
			want["atordoante"] = true
		if viewer.stats["swap"] > 0 and swap_guarded():
			want["troca_troca"] = true
	if want.is_empty() and guard_icons.is_empty():
		return
	var shown := 0
	for id in ["flash", "atordoante", "troca_troca"]:
		var on: bool = want.has(id)
		if on and not guard_icons.has(id):
			var s := Sprite3D.new()
			s.texture = CardDB.icon(id)
			s.pixel_size = 0.0028
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.modulate = Color(0.75, 0.78, 0.85, 0.7)
			s.no_depth_test = true
			s.shaded = false
			tag.add_child(s)
			guard_icons[id] = s
		if guard_icons.has(id):
			var s: Sprite3D = guard_icons[id]
			s.visible = on
			if on:
				s.position = Vector3((shown - (want.size() - 1) * 0.5) * 0.55, 0.5, 0)
				shown += 1


func flash_guarded() -> bool:
	return blind_guard > 0.0 or (net_guards & 1) != 0


func stun_guarded() -> bool:
	return silence_guard > 0.0 or (net_guards & 2) != 0


func swap_guarded() -> bool:
	return swap_lock > 0.0 or (net_guards & 4) != 0


## Invisível há CAMO_TIRE ou mais: a camuflagem começa a falhar (is_camo_tired) e, dentro de
## cada CAMO_BLINK_EVERY, fica visível por CAMO_BLINK_TIME (camo_blink).
func is_camo_tired() -> bool:
	return still_time > CAMO_DELAY + CAMO_TIRE


func camo_blink() -> bool:
	return is_camo_tired() and fmod(still_time - CAMO_DELAY - CAMO_TIRE, CAMO_BLINK_EVERY) < CAMO_BLINK_TIME


func reveal() -> void:
	if is_local and alive and stats["camo"] > 0 and ambush_cd <= 0.0 \
			and still_time >= CAMO_DELAY + AMBUSH_MIN_HIDDEN:
		ambush_cd = AMBUSH_COOLDOWN
		if Net.online:
			_net_ambush.rpc()
		_start_ambush()
		ambush_shot = true
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
	# Aliado preso no Gancho inimigo perde o contorno e a seta: atirar nele machuca (escudo humano).
	var ally_on := _ally_look and hooked_by == null
	if ally_arrow:
		ally_arrow.visible = ally_on
	var mat: Material = ambush_mat if ambush_timer > 0.0 else (ally_mat if ally_on else null)
	if _mark_look and mark_mat:
		mat = mark_mat
	if heal_glow > 0.0 and heal_mat:
		mat = heal_mat
	if spawn_protect > 0.0 and alive:
		mat = _protect_material()
	for m in body_meshes:
		m.material_overlay = mat


## Começo da rodada (a partida chama em todas as máquinas quando a contagem acaba).
func start_spawn_protect() -> void:
	spawn_protect = SPAWN_PROTECT
	_net_protected = false


## Contorno dourado de quem está protegido (o mesmo do aliado, sem atravessar paredes).
func _protect_material() -> ShaderMaterial:
	if protect_mat == null:
		if _ambush_shader == null:
			_ambush_shader = Shader.new()
			_ambush_shader.code = ALLY_RIM_SHADER.replace("depth_test_disabled, ", "")
		protect_mat = ShaderMaterial.new()
		protect_mat.shader = _ambush_shader
		protect_mat.set_shader_parameter("rim_color", Color(PROTECT_COLOR, 0.9))
	return protect_mat


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


## Estrelinhas do tonto em volta da cabeça. Na própria tela não aparecem (a câmera está
## dentro da cabeça): lá o aviso é a mira (hud) e o balanço da câmera (_place_camera).
func _update_daze_fx(delta: float) -> void:
	daze_fx = maxf(0.0, daze_fx - delta)
	if not alive:
		daze_fx = 0.0
	var show := daze_fx > 0.0 and not is_human
	if show and daze_stars == null:
		daze_stars = DazeStars.new()
		add_child(daze_stars)
	if daze_stars == null:
		return
	daze_stars.visible = show
	if show:
		var size: float = stats["body_scale"]
		daze_stars.tick(delta, daze_fx, size, height * size)


## Domínio do Rei: coroa na cabeça de quem lançou enquanto tem o bônus; as pontas crescem
## com ele (RealmCrown). Criada no 1o uso.
func _update_crown() -> void:
	var show := alive and not is_human and ((realm > 0 and realm_king) or realm_bonus_timer > 0.0)
	if show and realm_crown == null:
		realm_crown = RealmCrown.new()
		add_child(realm_crown)
	if realm_crown == null:
		return
	realm_crown.visible = show
	if show:
		var size: float = stats["body_scale"]
		realm_crown.tick(realm_bonus() / REALM_BONUS_MAX, size, height * size)


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
	var roll := cam_roll
	if daze_fx > 0.0:
		# Tonto: a câmera balança de um lado para o outro e acalma no fim.
		roll += sin(Time.get_ticks_msec() * 0.009) * DAZE_ROLL * minf(1.0, daze_fx / 0.4)
	var euler := Vector3(head.rotation.x + recoil * RECOIL_KICK + jitter.y, yaw + jitter.x, roll)
	camera.global_transform = Transform3D(Basis.from_euler(euler), origin)


# ---------------------------------------------------------------- simulação

func _physics_process(delta: float) -> void:
	if Prof.enabled:
		var t := Time.get_ticks_usec()
		_physics_step(delta)
		Prof.lap("jogador: física", t)
	else:
		_physics_step(delta)


func _physics_step(delta: float) -> void:
	if unstable_timer > 0.0:
		# Cartas Instáveis: cada máquina conta o tempo desde que recebeu o sorteio e desfaz
		# sozinha (também nos jogadores das outras máquinas).
		unstable_timer -= delta
		if unstable_timer <= 0.0:
			_unstable_set([])
	if realm > 0:
		_realm_tick(delta)
	_mech_step(delta)
	_realm_pull_step(delta)
	realm_bonus_timer = maxf(0.0, realm_bonus_timer - delta)   # em todas: a coroa aparece para os outros
	spawn_protect = maxf(0.0, spawn_protect - delta)
	if not is_local:
		_follow_network(delta)
		if downed:
			_update_down(delta)
		return
	if brain:
		var t := Prof.now()
		brain.think(delta)
		Prof.lap("bot: pensar", t, true)
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
	if is_local:
		_sky_check(delta)
		if not frozen:
			_zone_check(delta)
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
	if realm_pull > 0.0:
		# Domínio do Rei: sendo puxado, sobe devagar sem agir.
		velocity = Vector3.UP * (REALM_LIFT / REALM_PULL)
		move_and_slide()
		_send_state()
		return
	if frost_freeze > 0.0 and ice_timer <= 0.0:
		_frost_move(delta)
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
	if hooked_by:
		_hooked_step(delta)
		_send_state()
		return
	if hook_state == 1:
		_hook_fly(delta)
	if rchain_state == 1:
		_rchain_fly(delta)
	if grapple_state > 0:
		_grapple_check()
	if grapple_state == 1:
		_grapple_fly(delta)
	if beam_charge > 0.0 or beam_timer > 0.0:
		_beam_step(delta)
		if beam_timer > 0.0:
			_send_state()
			return
		in_jump = false
		in_dash = false
	_update_crouch()
	if grapple_state < 2 or not _grapple_move(delta):
		_move(delta)
	_act(delta)
	var fall_speed := velocity.y
	var before_h := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if slap_flight > 0.0:
		_check_splat(before_h, delta)
	_check_wall()
	if is_local:   # todos pisam: qualquer jogador é lançado
		_check_sky_pad()
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
	# Congelamento: cada camada deixa a cadência e o recarregar mais lentos.
	var chill := 1.0 / (1.0 + FROST_STEP * frost_layers)
	_frost_tick(delta)
	fire_timer = maxf(0.0, fire_timer - delta * chill)
	shield_timer = maxf(0.0, shield_timer - delta)
	shield_cd = maxf(0.0, shield_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	master_cd = maxf(0.0, master_cd - delta)
	master_gap = maxf(0.0, master_gap - delta)
	_mech_tick(delta)
	if grapple_refund > 0.0:
		grapple_refund -= delta
		if grapple_refund <= 0.0:
			_master_refund()
	var max_charges := master_max_charges()
	if master_charges < max_charges and master_cd <= 0.0 and max_charges > 1:
		master_charges += 1
		if master_charges < max_charges:
			master_cd = float(CardDB.CARDS[master_id]["cooldown"])
	if chaos and is_local and alive:
		_chaos_tick(delta)
	speed_orb_timer = maxf(0.0, speed_orb_timer - delta)
	if daze_timer > 0.0:
		daze_timer = maxf(0.0, daze_timer - delta)
		if daze_timer <= 0.0:
			_chain_end("daze", 0.0, aff_from.get("daze"))
	if slap_windup > 0.0 and is_local:
		if not alive or ice_timer > 0.0 or frost_freeze > 0.0 or hooked_by or daze_timer > 0.0 or slap_lock \
				or ride_timer > 0.0:
			_cancel_slap()
		else:
			slap_windup -= delta
			if slap_windup <= 0.0:
				_slap()
	if plat_chain > 0.0:
		plat_chain -= delta
		if plat_chain <= 0.0:
			_plat_end()
	if plat_cd > 0.0:
		plat_cd -= delta
		if plat_cd <= 0.0:
			plat_left = PLAT_MAX
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
	haste_timer = maxf(0.0, haste_timer - delta)
	slam_cd = maxf(0.0, slam_cd - delta)
	protect_timer = maxf(0.0, protect_timer - delta)
	ambush_cd = maxf(0.0, ambush_cd - delta)
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
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
		if slow_timer <= 0.0:
			_chain_end("slow", slow_amount, aff_from.get("slow"))
	if silence_timer > 0.0:
		silence_timer = maxf(0.0, silence_timer - delta)
		if silence_timer <= 0.0:
			_chain_end("silence", 0.0, aff_from.get("silence"))
	silence_guard = maxf(0.0, silence_guard - delta)
	bloodlust_timer = maxf(0.0, bloodlust_timer - delta)
	if blind_timer > 0.0:
		blind_timer = maxf(0.0, blind_timer - delta)
		if blind_timer <= 0.0:
			_chain_end("blind", blind_time, aff_from.get("blind"))
	blind_guard = maxf(0.0, blind_guard - delta)
	acid_timer = maxf(0.0, acid_timer - delta)
	contagion_guard = maxf(0.0, contagion_guard - delta)
	chain_guard = maxf(0.0, chain_guard - delta)
	since_damage += delta
	since_attack += delta
	parkour_timer = maxf(0.0, parkour_timer - delta)
	strike_timer = maxf(0.0, strike_timer - delta)
	pressure_timer = maxf(0.0, pressure_timer - delta)
	tough_timer = maxf(0.0, tough_timer - delta)
	if dash_echo_wait > 0.0 and (ice_timer > 0.0 or hooked_by or slap_flight > 0.0 or ride_timer > 0.0):
		dash_echo_wait = 0.0   # preso, congelado ou arremessado: o dash extra se perde
		dash_echo_left = 0
	if stats["armor_regen"] > 0.0 and alive:
		skin_timer += delta
		var cap := minf(ARMOR_MAX, SKIN_CAP * ceilf(float(stats["armor_regen"]) / 15.0))
		if skin_timer >= SKIN_DELAY:
			skin_timer = 0.0
			if armor < cap:
				armor = minf(cap, armor + float(stats["armor_regen"]))
	if echo_timer > 0.0:
		echo_timer -= delta
		if echo_timer <= 0.0 and alive and silence_timer <= 0.0:
			shield_timer = stats["shield_duration"]
			_shield_effects()
			echo_left -= 1
			if echo_left > 0:
				echo_timer = stats["shield_duration"] + ECHO_DELAY
	if reload_timer > 0.0:
		var rate := 1.0
		if stats["air_reload"] > 0.0 and (not is_on_floor() or sliding):
			rate += minf(AIR_RELOAD_MAX, stats["air_reload"])
		reload_timer -= delta * rate * chill
		if reload_timer <= 0.0:
			ammo = stats["mag_size"]
	if not alive:
		return
	if not poisons.is_empty():
		_poison_step(delta)
	if burn_timer > 0.0:
		burn_timer -= delta
		burn_acc += burn_dps * (1.0 + burn_heat) * delta * _fuel_mult()
		if burn_acc >= BURN_CHUNK or burn_timer <= 0.0:
			var who := burn_from if is_instance_valid(burn_from) else null
			var amount := burn_acc
			burn_acc = 0.0
			if burn_timer <= 0.0:
				burn_heat = 0.0
				_chain_end("burn", burn_dps, who)
			take_damage(amount, who, true, false, true, true)
	if skin_stacks > 0:
		skin_stack_timer += delta
		if skin_stack_timer >= SKIN_STACK_RESET:
			skin_stacks = 0
	if stats["regen"] > 0.0 and since_damage > REGEN_DELAY and since_attack > REGEN_DELAY:
		heal(stats["regen"] * delta)
	if not _chain_ended.is_empty():
		_chain_step()


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
	if haste_timer > 0.0:
		speed *= 1.0 + stats["shield_haste"]
	if parkour_timer > 0.0:
		speed *= 1.0 + PARKOUR_SPEED * float(stats["parkour"])
	if pressure_timer > 0.0:
		speed *= 1.0 + PRESSURE_SPEED
	if beam_charge > 0.0:
		speed *= BEAM_CHARGE_SPEED
	if hook_state == 3:
		speed *= HOOK_CARRY_SPEED
	if scoping:
		speed *= SCOPE_SPEED
	if shrink_timer > 0.0:
		speed *= 1.0 + SHRINK_SPEED
	if mech_state > 0:
		speed *= MECH_BUILD_SPEED if mech_state == 1 else MECH_SPEED
	if stats["chase"] > 0.0 and _toward_enemy():
		speed *= 1.0 + stats["chase"]
	if is_surviving():
		speed *= 1.0 + stats["survival_speed"]
	return speed


## Instinto de Sobrevivência valendo agora (mesmo limite de vida da Fúria).
func is_surviving() -> bool:
	return stats["survival_speed"] > 0.0 and health < stats["max_health"] * RAGE_THRESHOLD


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
	slam_pressed = false
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if in_crouch and not crouching:
		crouching = true
		_set_height(CROUCH_HEIGHT)
		if stats["ground_slam"] > 0 and not is_on_floor():
			slam_pressed = true
			var h := _height_above_ground()
			if slam_cd <= 0.0 and h > SLAM_MIN_HEIGHT:
				slamming = true
				slam_height = h
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


## Meteoro: o impacto fere e empurra quem estiver perto, mais forte quanto mais alto
## começou; quem caiu quica para cima.
func _slam_impact() -> void:
	slamming = false
	slam_cd = SLAM_COOLDOWN
	var t := clampf((slam_height - SLAM_MIN_HEIGHT) / (SLAM_HIGH - SLAM_MIN_HEIGHT), 0.0, 1.0)
	var dmg := lerpf(SLAM_DAMAGE, SLAM_DAMAGE_MAX, t) + SLAM_DAMAGE_STEP * (int(stats["ground_slam"]) - 1)
	var daze := 0.0
	if slam_height >= SLAM_HIGH:
		daze = SLAM_DAZE_TOP
	elif slam_height >= SLAM_DAZE_HEIGHT:
		daze = SLAM_DAZE
	eye_dip = 0.25 + 0.15 * t
	shake = maxf(shake, 0.4 + 0.4 * t)
	Effects.burst(get_parent(), global_position + Vector3.UP * 0.3, SLAM_RANGE * (0.8 + 0.3 * t),
		Color(1.0, 0.55, 0.2))
	Sfx.at(self, "explosion", global_position)
	for enemy in enemies():
		var d := global_position.distance_to(enemy.global_position)
		if d < SLAM_INNER:
			enemy.remote_call("receive_slam", [global_position, dmg, String(name), daze])
		elif d < SLAM_RANGE:
			enemy.remote_call("receive_slam", [global_position, dmg * 0.5, String(name), 0.0])
	velocity.y = SLAM_BOUNCE
	jump_rising = false
	slammed.emit(slam_height, dmg)


## Levou o Meteoro: o empurrão da Onda de Choque, o dano e, no centro de uma queda alta,
## tontura.
func receive_slam(from_pos: Vector3, dmg: float, from_name: String, daze: float) -> void:
	receive_shockwave(from_pos, dmg, from_name)
	if daze > 0.0 and alive:
		_daze(daze, get_parent().get_node_or_null(from_name) as Player)


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
		if velocity.y <= 0.0:
			rj_charges = RJ_CHARGES   # ainda subindo do lançamento, o chão do quadro anterior não conta
		if not on_sky_floor and plat_chain > 0.0:
			_plat_end()   # o chão de verdade fecha a sequência (pousar numa plataforma não)
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
			if stats["parkour"] > 0:
				air_dashes_left = mini(air_dashes_left + 1, maxi(1, stats["air_dashes"]))
				parkour_timer = PARKOUR_TIME
		elif jumps_left > 0:
			jumps_left -= 1
			# O pulo no ar deixa trocar de direção sem perder velocidade.
			if wish != Vector3.ZERO:
				h = wish.normalized() * maxf(h.length(), target)
			jumped = true
		elif stats["platforms"] > 0 and plat_left > 0 and plat_cd <= 0.0:
			# Plataformas Suspensas: plataforma sob os pés, que já lança (sem o pulo comum).
			if wish != Vector3.ZERO:
				h = wish.normalized() * maxf(h.length(), target)
			_make_platform().use_by(self)
			_platform_launch()
			jump_buffer = 0.0
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

	if dash_echo_wait > 0.0:
		dash_echo_wait -= delta
		if dash_echo_wait <= 0.0 and dash_timer <= 0.0 and not slamming:
			# Dash Duplo: o extra não mexe na recarga nem gasta dash no ar.
			dash_echo_left -= 1
			var cd := dash_cd
			_start_dash(wish if wish != Vector3.ZERO else dash_dir, h, target, not on_floor)
			dash_cd = cd
	elif in_dash and not slamming and not slam_pressed and dash_cd <= 0.0 and dash_timer <= 0.0 and mech_state == 0:
		if on_floor and wish != Vector3.ZERO:
			_start_dash(wish, h, target, false)
			dash_echo_left = stats["dash_echo"]
		elif not on_floor and air_dashes_left > 0:
			air_dashes_left -= 1
			_start_dash(wish, h, target, true)
			dash_echo_left = stats["dash_echo"]

	var dashing := dash_timer > 0.0
	dash_timer = maxf(0.0, dash_timer - delta)
	if dashing and dash_timer <= 0.0:
		_end_dash()
		if dash_echo_left > 0:
			dash_echo_wait = DASH_ECHO_DELAY
		h = Vector3(velocity.x, 0.0, velocity.z)
	elif dashing:
		_dash_seek_step(delta)
		h = dash_dir * DASH_SPEED
		if dash_air:
			velocity.y = 0.0
		_dash_hits()
	elif slap_lock:
		pass   # voo do tapa: segurar para trás anulava o empurrão (medido: 17 m parado, 1 m voltando)
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
	if on_floor and velocity.y <= 0.0:
		slap_lock = false
	if not slap_lock:
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
	slap_lock = false   # dash no voo do tapa devolve o controle (a fuga de quem levou)
	dash_dir = wish.normalized() if wish != Vector3.ZERO else _flat_forward()
	dash_timer = DASH_TIME * float(stats["dash_power"])
	dash_cd = stats["dash_cooldown"]
	dash_air = air
	dash_exit = maxf(h.length(), target * DASH_EXIT)
	dash_hits.clear()
	dash_seek_target = _dash_seek_find() if stats["dash_seek"] > 0 else null
	dash_seek_left = DASH_SEEK_ANGLE
	if stats["dash_strike"] > 0 and _dash_seek_find(STRIKE_RANGE) != null:
		strike_timer = STRIKE_TIME   # Arrancada
	jump_rising = false
	if stats["dash_dodge"] > 0:
		dodge_timer = DODGE_TIME
	if stats["dash_ammo"] > 0 and reload_timer <= 0.0:
		ammo = mini(stats["mag_size"], ammo + int(stats["dash_ammo"]))
	if is_human:
		Sfx.ui(self, "dash")
	reveal()


## Fim do dash: sobra a velocidade de saída, e se o Ctrl ainda está seguro no chão, desliza.
## Bote: o inimigo à vista mais perto da direção do dash, dentro do alcance e do ângulo
## (a Arrancada usa com o alcance dela).
func _dash_seek_find(reach := DASH_SEEK_RANGE) -> Player:
	var best: Player = null
	var best_angle := DASH_SEEK_ANGLE
	var space := get_world_3d().direct_space_state
	for enemy: Player in enemies():
		var to := enemy.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.5 or d > reach:
			continue
		var angle := dash_dir.angle_to(to / d)
		if angle > best_angle:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(chest(), enemy.chest(), 1)).is_empty():
			continue
		best = enemy
		best_angle = angle
	return best


## Bote: vira a direção do dash para o alvo, sem passar do que sobrou da curva. Para quando
## já passou dele (atrás do jogador) ou ele saiu da partida.
func _dash_seek_step(delta: float) -> void:
	if dash_seek_target == null or dash_seek_left <= 0.0:
		return
	if not is_instance_valid(dash_seek_target) or not dash_seek_target.alive:
		dash_seek_target = null
		return
	var to := dash_seek_target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.3 or dash_dir.dot(to.normalized()) < 0.0:
		dash_seek_target = null
		return
	var turn := dash_dir.signed_angle_to(to.normalized(), Vector3.UP)
	var step := clampf(turn, -minf(DASH_SEEK_TURN * delta, dash_seek_left), minf(DASH_SEEK_TURN * delta, dash_seek_left))
	dash_dir = dash_dir.rotated(Vector3.UP, step)
	dash_seek_left -= absf(step)


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
## Alto demais: acima do teto das balas leva dano crescente (ver SKY_*). A máquina dona decide.
func _sky_check(delta: float) -> void:
	if chest().y > Bullet.CEILING_Y:
		if not sky_active:
			sky_active = true
			sky_ticks = 0
			sky_timer = SKY_GRACE + SKY_TICK
			sky_credit = last_attacker if since_damage < VOID_CREDIT and is_instance_valid(last_attacker) else null
		sky_low = 0.0
		sky_timer -= delta
		if sky_timer <= 0.0:
			sky_timer += SKY_TICK
			var part := SKY_FIRST + SKY_STEP * sky_ticks
			sky_ticks += 1
			take_damage(stats["max_health"] * part, sky_credit if is_instance_valid(sky_credit) else null, true, false, true)
	elif sky_active:
		sky_low += delta
		if sky_low >= SKY_RESET:
			sky_active = false


## Prorrogação: fora do círculo leva dano (ver ZONE_*). A máquina dona decide. Na sala do
## Domínio do Rei (longe do mapa) não conta.
func _zone_check(delta: float) -> void:
	zone_out = realm == 0 and is_outside_zone()
	if not zone_out:
		zone_timer = minf(ZONE_GRACE, zone_timer + delta)
		zone_credit = null
		return
	if zone_credit == null and since_damage < ASSIST_TIME and is_instance_valid(last_attacker):
		zone_credit = last_attacker
	zone_timer -= delta
	if zone_timer <= 0.0:
		zone_timer += ZONE_TICK
		take_damage(stats["max_health"] * ZONE_PART, zone_credit if is_instance_valid(zone_credit) else null, true, false, true)


func is_outside_zone() -> bool:
	return zone_radius < INF and Vector2(global_position.x, global_position.z).length() > zone_radius


## Lá em cima agora (para a HUD).
func is_too_high() -> bool:
	return sky_active and sky_low == 0.0


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
	# Pena (desde 2026-10-10): só na descida; na subida diminuía a gravidade e passava as Molas.
	return g * float(stats["gravity_mult"]) if velocity.y <= 0.0 else g


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


## Pulo-Foguete: a própria explosão em point (raio r) lança para longe dela. Soma ao
## embalo (o teto MAX_HSPEED segue valendo) e, para cima, fica com o maior entre o que já
## tinha e o lançamento. RJ_CHARGES por vez no ar, a 2a mais fraca; voltam no chão.
func rocket_jump(point: Vector3, r: float) -> void:
	if not is_local or not alive or rj_charges <= 0:
		return
	var v := rocket_jump_push(chest(), point, r)
	if v == Vector3.ZERO:
		return
	if rj_charges < RJ_CHARGES:
		v *= RJ_SECOND
	rj_charges -= 1
	velocity = Vector3(velocity.x + v.x, maxf(velocity.y, v.y), velocity.z + v.z)
	jump_rising = false
	coyote = 0.0
	sliding = false


## Empurrão do Pulo-Foguete em quem está em at (zero fora do alcance): mais forte perto.
static func rocket_jump_push(at: Vector3, point: Vector3, r: float) -> Vector3:
	var d := at.distance_to(point)
	if d >= r + 1.0:
		return Vector3.ZERO
	var away := (at - point).normalized()
	var k := 1.0 - 0.5 * d / (r + 1.0)
	return Vector3(away.x * RJ_SIDE, maxf(away.y * RJ_UP, RJ_MIN_UP), away.z * RJ_SIDE) * k


## Inimigo pego na explosão de quem tem Pulo-Foguete: RJ_ENEMY da força, sempre para longe
## pelo chão e um pouco para cima (pela direção 3D, quem está ao lado do ponto quase só subia).
static func rocket_jump_enemy_push(at: Vector3, point: Vector3, r: float) -> Vector3:
	var d := at.distance_to(point)
	if d >= r + 1.0:
		return Vector3.ZERO
	var flat := at - point
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var k := 1.0 - 0.5 * d / (r + 1.0)
	return (flat * RJ_SIDE + Vector3.UP * RJ_UP) * k * RJ_ENEMY


func knockback(v: Vector3) -> void:
	velocity += v * push_mult()
	jump_rising = false


## Peso Pesado: quanto dos empurrões chega (explosões, ondas, tapa, raio, buraco negro).
func push_mult() -> float:
	if mech_state == 2:
		return 0.0   # Mecha: imune a empurrões e puxões
	return 1.0 - float(stats["heavy"])


# ---------------------------------------------------------------- rede

## Manda o estado deste jogador para a outra máquina, a cada quadro de física.
func _send_state() -> void:
	if not Net.online or Net.match_peers.is_empty() or not Net.all_ready():
		return
	var flags := (1 if is_on_floor() else 0) | (2 if crouching else 0) | (4 if sliding else 0) \
		| (8 if boosting else 0) | (16 if daze_timer > 0.0 else 0) \
		| (32 if blind_guard > 0.0 else 0) | (64 if silence_guard > 0.0 else 0) | (128 if swap_lock > 0.0 else 0) \
		| (256 if spawn_protect > 0.0 else 0) | (512 if heal_glow > 0.0 else 0) \
		| (1024 if frost_freeze > 0.0 else 0) | (mini(frost_layers, 7) << 11)
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
	net_guards = (flags >> 5) & 7
	# Proteção do começo: só desliga depois de ver o bit ligado (pacotes da contagem, de
	# antes de a dona começar a luta, chegam sem ele).
	if (flags & 256) != 0:
		_net_protected = true
	elif _net_protected:
		_net_protected = false
		spawn_protect = 0.0
	var healing := (flags & 512) != 0   # Sanguessuga curou na máquina dele
	if healing and not _net_heal:
		heal_flash()
	_net_heal = healing
	var dazed := (flags & 16) != 0
	if dazed and not _net_dazed:
		daze_fx = DAZE_FX_TIME
	_net_dazed = dazed
	frost_layers = (flags >> 11) & 7   # Congelamento: para o visual nas outras máquinas
	_frost_visual_sync((flags & 1024) != 0 and alive)
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
	if grapple_state > 0:
		_grapple_clear()   # a ventosa ficou lá atrás: puxaria de volta pelo mapa
	global_position = pos
	net_pos = pos
	reset_physics_interpolation()
	if is_human:
		_place_camera()


## Quem causou dano recebe o crédito: roubo de vida, Sede de Sangue e o som de acerto.
## tick: dano contínuo (veneno, queimadura, nuvem, serra), que não recarrega o dash da Caçada.
func credit_damage(amount: float, lethal := false, tick := false) -> void:
	if not alive:
		return
	if stats["lifesteal"] > 0.0:
		var before := health
		heal(amount * stats["lifesteal"])
		if health > before:
			heal_flash()
	if stats["bloodlust"] > 0.0:
		bloodlust_timer = BLOODLUST_TIME
	if stats["hit_dash"] > 0 and not tick:
		dash_cd = 0.0
		air_dashes_left = mini(air_dashes_left + 1, stats["air_dashes"])
	if lethal and stats["kill_heal"] > 0.0:
		heal(stats["kill_heal"])   # Banquete
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
	if realm_pull > 0.0:
		return   # sendo puxado para o Domínio do Rei
	if mech_state > 0:
		# Mecha: Q de novo sai (e explode); o E vira o míssil, sem escudo.
		if in_master and mech_state == 2 and mech_timer < MECH_TIME - MECH_EXIT_LOCK:
			_mech_end()
		elif in_shield and mech_state == 2 and mech_missile_cd <= 0.0 and daze_timer <= 0.0:
			_fire_missile()
		in_master = false
		in_shield = false
	if in_master and is_instance_valid(clone):
		# Clone: Q de novo troca de lugar com ele.
		if clone.life < ShadowClone.LIFE - CLONE_SWAP_LOCK and realm == 0:   # do Domínio do Rei não sai
			_clone_swap()
		in_master = false
	if in_master and shrink_timer > 0.0:
		_end_shrink(true)   # Formiga: Q de novo volta ao tamanho antes do tempo
	elif in_master and master_ready() and hook_state == 0:
		_use_master()
	if in_shield and shield_cd <= 0.0 and silence_timer <= 0.0:
		_activate_shield()
	_shield_bash()
	shot_queued = maxf(0.0, shot_queued - delta)
	if hook_state == 3 and (in_click or (in_shoot and not shoot_was) or in_master):
		_hook_throw_now()
	if daze_timer > 0.0 or beam_charge > 0.0 or beam_timer > 0.0 or hook_state >= 1 or slap_windup > 0.0 or mech_state == 1:
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
	if in_reload and reload_timer > 0.0 and stats["perfect_reload"] > 0 and not perfect_tried:
		_try_perfect_reload()
	elif in_reload and reload_timer <= 0.0 and ammo < stats["mag_size"] and burst_left == 0:
		_start_reload()
	if burst_left > 0:
		burst_timer -= delta
		if burst_timer <= 0.0:
			burst_left -= 1
			burst_timer = BURST_GAP
			if ammo > 0:
				_shoot()
			else:
				burst_left = 0
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
			or beam_timer > 0.0 or beam_charge > 0.0 or meteor_left > 0 or ride_timer > 0.0 \
			or hook_state > 0 or slap_windup > 0.0 or unstable_timer > 0.0 or mech_state > 0 or is_instance_valid(clone):
		master_cd = CHAOS_WAIT
	elif master_cd <= 0.0:
		_chaos_draw()


# ---------------------------------------------------------------- Prorrogação

## Uma carta comum do baralho até o fim da rodada, sorteada como nas Cartas Instáveis (cópias
## pesam, limite por partida respeitado, sem Fênix). Só na máquina dona; as outras recebem
## pelo _net_overtime, com a rodada, para não somar uma carta atrasada na rodada seguinte.
func overtime_draw() -> void:
	var owned: Array = cards + overtime_cards + unstable_cards
	var ok := func(id): return not UNSTABLE_EXCLUDED.has(id) and CardDB.can_take(id, owned)
	var pool := deck.filter(ok)
	if pool.is_empty():
		pool = CardDB.all_ids().filter(ok)
	if pool.is_empty():
		return
	var id: String = pool.pick_random()
	_overtime_add(id)
	if Net.online and is_inside_tree():
		_net_overtime.rpc(id, net_round)


@rpc("authority", "call_remote", "reliable")
func _net_overtime(id: String, round_id: int) -> void:
	if round_id == net_round and CardDB.CARDS.has(id) and not CardDB.is_master(id):
		_overtime_add(id)


func _overtime_add(id: String) -> void:
	overtime_cards.append(id)
	_recompute_stats()
	overtime_card.emit(id)


# ---------------------------------------------------------------- Cartas Instáveis

## Sorteia UNSTABLE_COUNT cartas do baralho (cópias pesam, como na escolha; repetidas podem
## sair) respeitando o limite por partida, com as cartas que você já tem. Baralho vazio
## (bot sem baralho ainda) ou sem nenhuma carta possível: sorteia entre todas as comuns.
## Só na máquina dona; as outras recebem pelo _net_unstable.
func _unstable_draw() -> void:
	var ids := []
	for i in UNSTABLE_COUNT:
		var owned: Array = cards + overtime_cards + ids
		var ok := func(id): return not UNSTABLE_EXCLUDED.has(id) and CardDB.can_take(id, owned)
		var pool := deck.filter(ok)
		if pool.is_empty():
			pool = CardDB.all_ids().filter(ok)
		if pool.is_empty():
			break
		ids.append(pool.pick_random())
	_unstable_set(ids)
	unstable_drawn.emit(ids)
	if Net.online and is_inside_tree():
		_net_unstable.rpc(ids)


@rpc("authority", "call_remote", "reliable")
func _net_unstable(ids: Array) -> void:
	for id in ids:
		if not CardDB.CARDS.has(id) or CardDB.is_master(id):
			return
	_unstable_set(ids)
	unstable_drawn.emit(ids)


## Liga (ou, com [], desliga) as cartas temporárias e recalcula os atributos no meio da
## rodada. A vida acompanha a vida máxima em porcentagem (não cura nem mata ao acabar); o
## pente perde as balas que não cabem; o que a partida mexeu nos atributos (mestra do Caos,
## Formiga) é refeito por cima.
func _unstable_set(ids: Array) -> void:
	unstable_cards = ids.duplicate()
	unstable_timer = UNSTABLE_TIME if not ids.is_empty() else 0.0
	_recompute_stats()


## Atributos no meio da rodada com as cartas da partida, da prorrogação e as instáveis.
func _recompute_stats() -> void:
	var old_max: float = stats["max_health"]
	stats = CardDB.compute_stats(BASE_STATS, cards + overtime_cards + unstable_cards)
	if chaos and master_id != "":
		_chaos_set(master_id)
	if has_meta("shrunk") and get_meta("shrunk"):
		stats["body_scale"] = float(stats["body_scale"]) * SHRINK_SCALE
	if mech_state > 0:
		_mech_mods()
	if alive and old_max > 0.0:
		health = minf(health * float(stats["max_health"]) / old_max, stats["max_health"])
	ammo = mini(ammo, int(stats["mag_size"]))
	air_dashes_left = mini(air_dashes_left, int(stats["air_dashes"]))
	_apply_body_scale()
	_update_unstable_icons()


## Em cima do nome (para os outros): os ícones das cartas temporárias, apagados. Um
## Sprite3D por vaga, criado no 1o uso; só troca a textura e liga/desliga.
func _update_unstable_icons() -> void:
	if unstable_cards.is_empty() and unstable_icons.is_empty():
		return
	while unstable_icons.size() < unstable_cards.size():
		var s := Sprite3D.new()
		s.pixel_size = 0.0028
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.modulate = Color(0.85, 0.75, 1.0, 0.75)
		s.no_depth_test = true
		s.shaded = false
		tag.add_child(s)
		unstable_icons.append(s)
	var n := unstable_cards.size()
	for i in unstable_icons.size():
		var s: Sprite3D = unstable_icons[i]
		s.visible = i < n
		if i < n:
			s.texture = CardDB.icon(unstable_cards[i])
			s.position = Vector3((i - (n - 1) * 0.5) * 0.55, 0.95, 0)


# ---------------------------------------------------------------- Clone

## Q: o clone nasce onde você está e anda para onde você olha. Só a máquina dona decide;
## as outras recebem o mesmo ponto e direção pelo _net_clone.
func _start_clone() -> void:
	var look := -head.global_transform.basis.z
	_make_clone(global_position, look)
	if Net.online and is_inside_tree():
		_net_clone.rpc(global_position, look)


func _make_clone(pos: Vector3, look: Vector3) -> void:
	if is_instance_valid(clone):
		clone.vanish()
	clone = ShadowClone.spawn(self, pos, look)
	Sfx.at(self, "shield", pos + Vector3.UP)
	clone_changed.emit("criou")


@rpc("authority", "call_remote", "reliable")
func _net_clone(pos: Vector3, look: Vector3) -> void:
	_make_clone(pos, look)


## Nas outras máquinas, o clone vira e dispara junto (as balas chegam pela rede).
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_clone_aim(target: Vector3) -> void:
	if is_instance_valid(clone):
		clone.aim_at(target)


## Q de novo: você vai para onde o clone está (na sua máquina) e ele some.
func _clone_swap() -> void:
	var to := clone.global_position
	Effects.burst(get_parent(), chest(), 1.2, CLONE_COLOR, 0.2)
	teleport_to(to)
	velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
	sliding = false
	dash_timer = 0.0
	clone_changed.emit("trocou")
	_clone_end()


## Destruído pelas balas (máquina do dono).
func clone_destroyed() -> void:
	clone_changed.emit("destruído")
	_clone_end()


func _clone_end() -> void:
	if is_instance_valid(clone):
		clone.vanish()
	clone = null
	if Net.online and is_local and is_inside_tree():
		_net_clone_end.rpc()


@rpc("authority", "call_remote", "reliable")
func _net_clone_end() -> void:
	if is_instance_valid(clone):
		clone.vanish()
	clone = null


## Morte e fim de rodada: some sem avisar ninguém (todas as máquinas fazem o mesmo).
func _clone_clear() -> void:
	if is_instance_valid(clone):
		clone.vanish()
	clone = null


# ---------------------------------------------------------------- Mecha

## Q: começa a montar. Só a máquina dona decide; as outras recebem _net_mech.
func _start_mech() -> void:
	_mech_set(1)
	_mech_send()


## Máquina dona, a cada passo: a recarga só anda depois de sair; montou, entra; acabou o
## tempo, sai explodindo.
func _mech_tick(delta: float) -> void:
	if mech_state == 0:
		return
	if not chaos:
		master_cd = CardDB.CARDS["mecha"]["cooldown"]
	mech_missile_cd = maxf(0.0, mech_missile_cd - delta)
	if mech_timer > 0.0 or frozen:
		return   # parado entre rodadas: não sai nem explode (o reinício da rodada desmonta)
	if mech_state == 1:
		mech_armor_max = MECH_ARMOR_BASE + MECH_ARMOR_PART * float(stats["max_health"])
		mech_armor = mech_armor_max
		mech_missile_cd = 0.0
		_mech_set(2)
		_mech_send()
	else:
		_mech_end()


## Sai do mecha (tempo, Q de novo ou blindagem zerada) e ele explode: quanto menos
## blindagem sobrou, maior o dano.
func _mech_end() -> void:
	if mech_state != 2:
		return
	var lost := 1.0 - clampf(mech_armor / maxf(mech_armor_max, 1.0), 0.0, 1.0)
	var dmg := lerpf(MECH_BLAST_MIN, MECH_BLAST_MAX, lost)
	var pos := chest()
	_mech_set(0)
	_mech_send()
	if Net.online and is_inside_tree():
		_net_mech_blast.rpc(pos, dmg)
	else:
		_net_mech_blast(pos, dmg)


## Morte, fim de rodada, banco: some sem explodir.
func _mech_clear() -> void:
	if mech_state != 0:
		_mech_set(0)


func _mech_send() -> void:
	if Net.online and is_local and is_inside_tree():
		_net_mech.rpc(mech_state, mech_armor_max)


@rpc("authority", "call_remote", "reliable")
func _net_mech(state: int, armor_max: float) -> void:
	mech_armor_max = armor_max
	mech_armor = armor_max if state == 2 else 0.0
	_mech_set(state)


## Blindagem para os outros (barra em cima do nome); só quando muda.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_mech_armor(value: float) -> void:
	mech_armor = value


@rpc("authority", "call_local", "reliable")
func _net_mech_blast(pos: Vector3, dmg: float) -> void:
	mech_blast(get_parent(), pos, self, MECH_BLAST_RADIUS, dmg, false)
	mech_exploded.emit(dmg)


func _mech_set(state: int) -> void:
	mech_state = state
	mech_timer = MECH_BUILD if state == 1 else (MECH_TIME if state == 2 else 0.0)
	if state == 0:
		mech_armor = 0.0
	_mech_visual()
	_recompute_stats()   # depois do visual: _apply_body_scale põe o piloto e o mecha no tamanho
	mech_changed.emit(state)
	if state == 1:
		Sfx.at(self, "pickup", chest())
	elif state == 2:
		Effects.burst(get_parent(), chest(), 1.6, MECH_COLOR, 0.2)
		Sfx.at(self, "shield", chest())


## Os custos de dentro (e da montagem) por cima das cartas: corpo maior, pulo menor, sem
## pulos extras, de parede nem dash no ar (o dash no chão é cortado em _move).
func _mech_mods() -> void:
	stats["body_scale"] = float(stats["body_scale"]) * MECH_SCALE
	stats["jump_velocity"] = float(stats["jump_velocity"]) * MECH_JUMP
	stats["extra_jumps"] = 0
	stats["wall_jumps"] = 0
	stats["air_dashes"] = 0


## Blindagem leva o dano antes de tudo; devolve o que passou. Zerou: sai explodindo (só a
## máquina dona chama; quem chama decide o resto do dano).
func _mech_absorb(amount: float) -> float:
	var soak := minf(mech_armor, amount)
	mech_armor -= soak
	if Net.online and is_inside_tree():
		_net_mech_armor.rpc(mech_armor)
	return amount - soak


## E dentro do mecha: míssil na mira (20 + 40% do dano da bala, até 45).
func _fire_missile() -> void:
	mech_missile_cd = MISSILE_CD
	since_attack = 0.0
	spawn_protect = 0.0
	reveal()
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	var side := global_transform.basis.x * 0.9 * float(stats["body_scale"]) / MECH_SCALE
	var start := chest() + Vector3.UP * 0.5 + side
	var dmg := minf(MISSILE_MAX, MISSILE_BASE + MISSILE_SCALE * shot_damage())
	Bullet.fire(self, start, (target - start).normalized(), 0.0, false,
		{"speed": MISSILE_SPEED, "missile": true, "damage": dmg, "radius": 0.28, "gravity": 0.0, "bounces": 0,
		"ghost_walls": 0, "explosion": 0.0, "poison": 0.0, "burn": 0.0, "slow": 0.0, "push": 0.0, "shield_break": false,
		"execute": 0.0, "split": 0, "sticky": false, "boomerang": false, "guided": false, "seek": 0.0,
		"homing": 0.0, "target_bounce": 0.0, "lazy_top": 0.0, "grow": 0.0, "swap": false, "blind": 0.0,
		"toxic": 0, "hole": 0, "bounce_damage": 0.0})
	Sfx.at(self, "grapple_fire", start)


## Explosão do Mecha (saída) e do míssil, em cada máquina só nos jogadores dela; nunca no
## dono nem no aliado. Míssil: escudo de pé bloqueia o dano (não devolve).
static func mech_blast(parent: Node, pos: Vector3, owner_p: Player, radius: float, dmg: float, missile: bool) -> void:
	var color := MISSILE_COLOR if missile else MECH_COLOR.lightened(0.3)
	Effects.explosion(parent, pos, radius, color)
	Effects.sparks(parent, pos, color, 10 if missile else 16, 8.0)
	Sfx.at(parent, "explosion", pos)
	for node in parent.get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.is_local or not p.alive or p == owner_p:
			continue
		if is_instance_valid(owner_p) and owner_p.is_ally(p):
			continue
		var d := p.chest().distance_to(pos)
		if d > radius + p.hit_radius():
			continue
		if missile and p.is_shielding():
			p.reflect_flash = 1.0
			continue
		var away := p.chest() - pos
		away.y = 0.0
		p.knockback(away.normalized() * 7.0 + Vector3.UP * 4.0)
		p.take_area_damage(dmg * (1.0 - 0.5 * clampf(d / radius, 0.0, 1.0)), owner_p if is_instance_valid(owner_p) else null)


## Modelo montado em código, peças em comum entre todos (malha e material uma vez só).
## Para os outros: pernas, pés, quadril, costas e laterais abertas na frente (o personagem
## aparece na cabine), ombros com os lançadores. Na própria tela: a moldura da cabine nos
## cantos. As peças aparecem uma a uma na montagem (_mech_update_fx).
static var _mech_meshes: Array = []

func _mech_visual() -> void:
	if mech_state == 0:
		if mech_fx:
			mech_fx.queue_free()
			mech_fx = null
			_mech_parts.clear()
		return
	if mech_fx:
		return
	if _mech_meshes.is_empty():
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.55, 0.6, 0.66)
		steel.metallic = 0.4
		steel.roughness = 0.5
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.18, 0.2, 0.23)
		var hot := StandardMaterial3D.new()
		hot.albedo_color = MISSILE_COLOR
		hot.emission_enabled = true
		hot.emission = MISSILE_COLOR * 0.4
		var box := func(size: Vector3, mat: Material) -> BoxMesh:
			var m := BoxMesh.new()
			m.size = size
			m.material = mat
			return m
		# [malha, posição] em metros, para o corpo de tamanho 1 (o nó escala com o corpo).
		# Em volta de um corpo de 2,5 m (1,4x): o piloto (MECH_PILOT) senta a MECH_SEAT e
		# aparece da cintura para cima pela frente aberta da cabine.
		var third := [
			[box.call(Vector3(0.55, 0.2, 0.8), dark), Vector3(-0.42, 0.1, -0.05)],     # pés
			[box.call(Vector3(0.55, 0.2, 0.8), dark), Vector3(0.42, 0.1, -0.05)],
			[box.call(Vector3(0.42, 0.75, 0.5), steel), Vector3(-0.42, 0.55, 0.0)],    # pernas
			[box.call(Vector3(0.42, 0.75, 0.5), steel), Vector3(0.42, 0.55, 0.0)],
			[box.call(Vector3(1.3, 0.3, 0.85), dark), Vector3(0.0, 1.0, 0.0)],         # quadril
			[box.call(Vector3(1.2, 0.45, 0.12), steel), Vector3(0.0, 1.35, -0.42)],    # painel da frente (cobre as pernas do piloto)
			[box.call(Vector3(1.3, 1.25, 0.14), steel), Vector3(0.0, 1.75, 0.45)],     # costas
			[box.call(Vector3(0.14, 1.0, 0.85), steel), Vector3(-0.68, 1.65, 0.0)],    # laterais
			[box.call(Vector3(0.14, 1.0, 0.85), steel), Vector3(0.68, 1.65, 0.0)],
			[box.call(Vector3(0.45, 0.4, 0.8), dark), Vector3(-0.95, 2.25, 0.05)],     # ombros com os lançadores
			[box.call(Vector3(0.45, 0.4, 0.8), dark), Vector3(0.95, 2.25, 0.05)],
			[box.call(Vector3(0.32, 0.26, 0.08), hot), Vector3(-0.95, 2.25, -0.37)],   # bocas dos mísseis
			[box.call(Vector3(0.32, 0.26, 0.08), hot), Vector3(0.95, 2.25, -0.37)],
		]
		# Na tela (a 0,5 m da câmera a tela vai de ~±0,67 de lado e ±0,38 de altura): hastes
		# finas inclinadas nos cantos de baixo e uma faixa fina no pé da tela, com luzes.
		var first := [
			[box.call(Vector3(0.022, 0.3, 0.022), steel), Vector3(-0.6, -0.3, -0.5), Vector3(0, 0, -0.55)],
			[box.call(Vector3(0.022, 0.3, 0.022), steel), Vector3(0.6, -0.3, -0.5), Vector3(0, 0, 0.55)],
			[box.call(Vector3(1.5, 0.03, 0.04), dark), Vector3(0.0, -0.37, -0.5), Vector3.ZERO],
			[box.call(Vector3(0.06, 0.012, 0.01), hot), Vector3(-0.3, -0.353, -0.48), Vector3.ZERO],
			[box.call(Vector3(0.06, 0.012, 0.01), hot), Vector3(0.3, -0.353, -0.48), Vector3.ZERO],
		]
		_mech_meshes = [third, first]
	mech_fx = Node3D.new()
	var parts: Array = _mech_meshes[1 if is_human else 0]
	if is_human:
		camera.add_child(mech_fx)
	else:
		add_child(mech_fx)
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position = part[1]
		if part.size() > 2:
			mi.rotation = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mech_fx.add_child(mi)
		_mech_parts.append(mi)
	_mech_update_fx()


## Todas as máquinas, a cada passo: o tempo e as peças aparecendo na montagem.
func _mech_step(delta: float) -> void:
	if mech_state == 0:
		return
	mech_timer = maxf(0.0, mech_timer - delta)
	_mech_update_fx()


func _mech_update_fx() -> void:
	if mech_fx == null:
		return
	if not is_human:
		# O corpo do jogador já cresceu com o mecha (body_scale): o modelo acompanha.
		mech_fx.scale = Vector3.ONE * float(stats["body_scale"]) / MECH_SCALE
	var shown := _mech_parts.size()
	if mech_state == 1:
		shown = ceili((1.0 - mech_timer / MECH_BUILD) * _mech_parts.size())
	for i in _mech_parts.size():
		var mi: MeshInstance3D = _mech_parts[i]
		if mi.visible != (i < shown):
			mi.visible = i < shown
			if mi.visible and mech_state == 1:
				Effects.burst(get_parent(), mi.global_position, 0.4, MECH_COLOR, 0.1)


# ---------------------------------------------------------------- Arpéu Ventoso

func _grapple_fire() -> void:
	if grapple_state > 0:
		_grapple_release()   # a próxima ventosa solta a anterior: segue com o embalo até grudar
	grapple_state = 1
	grapple_dir = -head.global_transform.basis.z
	grapple_tip = head.global_position
	grapple_dist = 0.0
	reveal()
	Sfx.at(self, "grapple_fire", chest())
	grappled.emit(1)
	_grapple_send(1, grapple_tip, grapple_dir)


## A ventosa voa (máquina dona): o 1o pedaço de cenário na linha é onde gruda; jogadores e
## plataformas suspensas não contam (só a camada 1). Passou do alcance: errou.
func _grapple_fly(delta: float) -> void:
	var step := GRAPPLE_SPEED * delta
	var to := grapple_tip + grapple_dir * step
	# Inimigo na linha (antes do cenário): chute de ventosa.
	for enemy: Player in enemies():
		if enemy.ice_timer > 0.0 or enemy.hooked_by or enemy.realm_pull > 0.0:
			continue
		var c := enemy.chest()
		var t := clampf((c - grapple_tip).dot(grapple_dir), 0.0, step)
		if (grapple_tip + grapple_dir * t).distance_to(c) < 0.3 + enemy.hit_radius():
			grapple_state = 4
			grapple_target = enemy
			grapple_tip = c
			grapple_age = 0.0
			sliding = false
			dash_timer = 0.0
			Sfx.at(get_parent(), "grapple_stick", c)
			grappled.emit(4)
			_grapple_send(4, c, Vector3.ZERO)
			return
	var ray := PhysicsRayQueryParameters3D.create(grapple_tip, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		grapple_tip = hit["position"]
		grapple_normal = hit["normal"]
		grapple_state = 2
		grapple_len = chest().distance_to(grapple_tip)
		grapple_age = 0.0
		sliding = false
		dash_timer = 0.0
		Sfx.at(get_parent(), "grapple_stick", grapple_tip)
		grappled.emit(2)
		_grapple_send(2, grapple_tip, grapple_normal)
		return
	grapple_tip = to
	grapple_dist += step
	if grapple_dist >= GRAPPLE_RANGE:
		_grapple_clear()
		grapple_refund = GRAPPLE_REFUND
		grappled.emit(0)


## Errou: devolve a carga gasta (com o Caos, que tem uma só, não devolve).
func _master_refund() -> void:
	if chaos:
		return
	var max_charges := master_max_charges()
	if max_charges > 1:
		master_charges = mini(master_charges + 1, max_charges)
		if master_charges >= max_charges:
			master_cd = 0.0
	else:
		master_cd = 0.0


## Cortes: morrer, congelar, ser fisgado, levar tapa, montar.
func _grapple_check() -> void:
	if not alive or ice_timer > 0.0 or hooked_by or slap_lock or ride_timer > 0.0:
		_grapple_clear()


## Puxando ou pendurado: põe a velocidade no lugar do movimento normal. Devolve false
## quando soltou neste passo (o movimento normal segue, ex.: o dash que cortou).
func _grapple_move(delta: float) -> bool:
	if in_dash and dash_cd <= 0.0:
		_grapple_clear()   # dash corta e emenda: _move faz o dash com o embalo do puxão
		return false
	if grapple_state == 4:
		return _grapple_kick_step(delta)
	if grapple_state == 2 and in_jump:
		_grapple_release()   # pulo no balanço: solta com impulso para cima (pendurado, salta da parede)
		jump_buffer = 0.0
		return true
	grapple_age += delta
	if grapple_state == 2 and not in_master_held and grapple_age >= GRAPPLE_MIN_HOLD:
		_grapple_release(true)   # soltou o Q: sai com o embalo
		return true
	if grapple_state == 2:
		var to := grapple_tip - chest()
		var d := to.length()
		if d > GRAPPLE_ARRIVE and grapple_age < GRAPPLE_MAX_TIME:
			var dir := to / d
			# Balanço: puxa para o ponto sem apagar o embalo, gravidade pela metade, teclas guiam.
			velocity.y -= GRAVITY_FALL * GRAPPLE_GRAVITY * delta
			velocity += dir * GRAPPLE_ACCEL * delta
			var steer := _wish_dir()
			steer -= dir * steer.dot(dir)
			velocity += steer.limit_length(1.0) * GRAPPLE_AIR_STEER * delta
			# A corda não estica: corta o que afasta do ponto e puxa de volta o que passou.
			grapple_len = maxf(GRAPPLE_ARRIVE, minf(grapple_len, d) - GRAPPLE_REEL * delta)
			var away := velocity.dot(dir)
			if d > grapple_len and away < 0.0:
				velocity -= dir * away
			if d > grapple_len:
				velocity += dir * minf(d - grapple_len, 1.0) * 8.0
			velocity = velocity.limit_length(GRAPPLE_MAX_SPEED)
			sliding = false
			return true
		# Chegou (ou o tempo acabou) segurando: no topo de algo, pisa; na parede ou no teto, pendura.
		if grapple_age >= GRAPPLE_MAX_TIME:
			_grapple_release(true)
			return true
		if grapple_normal.y > 0.7:
			velocity = Vector3.UP * 2.0
			_grapple_clear()
			return true
		grapple_state = 3
		grapple_timer = GRAPPLE_HANG
		grappled.emit(3)
	# Pendurado: parado e sem gravidade; pular salta da parede.
	if in_jump:
		var n := Vector3(grapple_normal.x, 0.0, grapple_normal.z)
		velocity = Vector3.ZERO
		if grapple_normal.y > -0.7:
			velocity = n.normalized() * WALL_JUMP_PUSH + Vector3.UP * float(stats["jump_velocity"])
			jump_rising = true
		_grapple_clear()
		jump_buffer = 0.0
		return true
	grapple_timer -= delta
	if grapple_timer <= 0.0 or not in_master_held:
		_grapple_clear()   # o tempo acabou ou soltou o Q: cai
		return false
	velocity = Vector3.ZERO
	return true


## Soltar: soltando o Q (boost), no balanço sai com o embalo x GRAPPLE_RELEASE_BOOST e
## ganha um pulo no ar; pulo no balanço, ou a próxima ventosa, solta com +GRAPPLE_LIFT para
## cima; pendurado, só cai; com a ventosa ainda voando, ela some (a carga já foi).
func _grapple_release(boost := false) -> void:
	if grapple_state == 2:
		if boost:
			velocity = (velocity * GRAPPLE_RELEASE_BOOST).limit_length(GRAPPLE_MAX_SPEED * GRAPPLE_RELEASE_BOOST)
			jumps_left = maxi(jumps_left, 1)
		else:
			velocity += Vector3.UP * GRAPPLE_LIFT
		jump_rising = false
	elif grapple_state == 3:
		velocity = Vector3.ZERO
	_grapple_clear()
	grappled.emit(0)


## Chute de ventosa: puxado até o inimigo; chegando, a máquina dele decide (escudo bloqueia)
## e você quica para trás. Ele saiu de alcance, morreu ou passou do tempo: solta.
func _grapple_kick_step(delta: float) -> bool:
	grapple_age += delta
	var foe := grapple_target
	if not is_instance_valid(foe) or not foe.alive or foe.realm != realm or grapple_age > 1.5:
		_grapple_clear()
		return false
	grapple_tip = foe.chest()
	var to := grapple_tip - chest()
	var d := to.length()
	var dir := to / maxf(d, 0.01)
	if d > GRAPPLE_KICK_REACH:
		velocity = dir * GRAPPLE_KICK_SPEED
		sliding = false
		return true
	foe.remote_call("receive_grapple_kick", [String(name), dir])
	velocity = -Vector3(dir.x, 0.0, dir.z).normalized() * 6.0 + Vector3.UP * 7.0
	jump_rising = false
	jumps_left = maxi(jumps_left, 1)
	Effects.burst(get_parent(), foe.chest(), 1.2, GRAPPLE_COLOR, 0.15)
	grappled.emit(5)
	_grapple_clear()
	return true


## Na máquina de quem leva o chute: escudo de pé bloqueia (só o reflexo); senão dano e empurrão.
func receive_grapple_kick(from_name: String, dir: Vector3) -> void:
	if not alive:
		return
	if is_shielding():
		reflect_flash = 1.0
		Sfx.at(self, "reflect", chest())
		return
	knockback(Vector3(dir.x, 0.0, dir.z).normalized() * 12.0 + Vector3.UP * 5.0)
	take_damage(GRAPPLE_KICK_DAMAGE, get_parent().get_node_or_null(from_name) as Player)


func _grapple_clear() -> void:
	if grapple_state > 0 and is_local:
		_grapple_send(0, grapple_tip, Vector3.ZERO)
	grapple_state = 0
	grapple_timer = 0.0


## Rede: as outras máquinas só desenham (lançou, grudou, soltou); quem simula é a dona.
func _grapple_send(state: int, tip: Vector3, vec: Vector3) -> void:
	if Net.online and is_inside_tree():
		_net_grapple.rpc(state, tip, vec)


@rpc("authority", "call_remote", "reliable")
func _net_grapple(state: int, tip: Vector3, vec: Vector3) -> void:
	grapple_state = state
	grapple_tip = tip
	if state == 1:
		grapple_dir = vec
		Sfx.at(self, "grapple_fire", chest())
	elif state == 2:
		grapple_normal = vec
		Sfx.at(get_parent(), "grapple_stick", tip)
		grappled.emit(2)


## Desentupidor (ventosa vermelha de borracha e cabo de madeira) e a corda até a mão.
## Montados no 1o uso, só deste jogador; escondidos sem ventosa no ar.
func _grapple_visual() -> void:
	grapple_fx = Node3D.new()
	grapple_fx.top_level = true
	add_child(grapple_fx)
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.75, 0.1, 0.08)
	rubber.roughness = 0.5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.36, 0.18)
	wood.roughness = 0.8
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.2, 0.17, 0.14)
	rope.roughness = 0.9
	# Local: -Z é a frente (a boca da ventosa); o cabo sai para +Z, na direção de quem lançou.
	var cup := CylinderMesh.new()
	cup.top_radius = 0.05
	cup.bottom_radius = 0.13
	cup.height = 0.11
	cup.radial_segments = 12
	cup.material = rubber
	var stick := CylinderMesh.new()
	stick.top_radius = 0.022
	stick.bottom_radius = 0.022
	stick.height = 0.45
	stick.radial_segments = 6
	stick.material = wood
	grapple_plunger = Node3D.new()
	grapple_fx.add_child(grapple_plunger)
	for part in [[cup, 0.055], [stick, 0.11 + 0.225]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.rotation.x = PI / 2.0   # o eixo do cilindro (Y) vira +Z: a base larga fica na frente (-Z)
		mi.position.z = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grapple_plunger.add_child(mi)
	var cord := CylinderMesh.new()
	cord.top_radius = 0.018
	cord.bottom_radius = 0.018
	cord.height = 1.0
	cord.radial_segments = 5
	cord.rings = 1
	cord.material = rope
	grapple_cord = MeshInstance3D.new()
	grapple_cord.mesh = cord
	grapple_cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grapple_fx.add_child(grapple_cord)


func _update_grapple_fx(delta: float) -> void:
	if grapple_fx == null:
		_grapple_visual()
	grapple_fx.visible = grapple_state > 0 and alive
	if not grapple_fx.visible:
		return
	if grapple_state == 1 and not is_local:
		grapple_tip += grapple_dir * GRAPPLE_SPEED * delta   # nas outras máquinas ela voa sozinha
	var fwd := grapple_dir if grapple_state == 1 else -grapple_normal
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	var up := Vector3.UP if absf(fwd.normalized().y) < 0.99 else Vector3.RIGHT
	grapple_plunger.global_transform = Transform3D(Basis.looking_at(fwd, up), grapple_tip)
	var end := grapple_tip - fwd.normalized() * 0.56   # ponta do cabo
	var start := chest()
	if is_human:
		start = camera.global_position + Vector3.DOWN * 0.4 + camera.global_transform.basis.x * 0.25
	var axis := end - start
	var length := axis.length()
	grapple_cord.visible = length > 0.05
	if not grapple_cord.visible:
		return
	axis /= length
	var x := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(axis).normalized()
	grapple_cord.global_transform = Transform3D(Basis(x, axis * length, z), (start + end) / 2.0)


# ---------------------------------------------------------------- Domínio do Rei

## Q: lança a corrente sombria no alvo da mira (_realm_find, já conferido no _use_master).
## A máquina de quem lança move a ponta e decide parede e tempo; as outras desenham a ponta
## perseguindo o mesmo alvo.
func _rchain_fire(target: Player) -> void:
	_rchain_start(target)
	reveal()
	Sfx.at(self, "grapple_fire", chest())
	if Net.online and is_inside_tree():
		_net_rchain.rpc(1, String(target.name))


func _rchain_start(target: Player) -> void:
	rchain_state = 1
	rchain_target = target
	rchain_tip = chest()
	rchain_dir = (target.chest() - rchain_tip).normalized()
	rchain_time = 0.0
	rchain_serial += 1
	target.rchain_incoming = self
	if target == viewer:
		Sfx.ui(target, "count")   # aviso para o alvo: a corrente vem aí
	_rchain_visual(true)


@rpc("authority", "call_remote", "reliable")
func _net_rchain(state: int, target_name: String) -> void:
	var target := get_parent().get_node_or_null(target_name) as Player if target_name != "" else null
	if state == 1 and target:
		_rchain_start(target)
	else:
		_rchain_clear()


## A corrente persegue o alvo (máquina de quem lança). Não contorna: parede no caminho, alvo
## fora de alcance da regra (morto, congelado, fisgado, em outro Domínio) ou RCHAIN_LIFE sem
## chegar = errou. Chegou: a máquina do alvo decide (receive_realm; o escudo bloqueia lá).
func _rchain_fly(delta: float) -> void:
	rchain_time += delta
	var t_ok := is_instance_valid(rchain_target) and rchain_target.alive and rchain_target.realm == realm \
			and rchain_target.ice_timer <= 0.0 and not rchain_target.hooked_by and rchain_target.realm_pull <= 0.0
	if not t_ok or rchain_time > RCHAIN_LIFE:
		rchain_event.emit(false)
		realm_blocked()
		return
	var c := rchain_target.chest()
	var from := rchain_tip
	rchain_dir = (c - from).normalized()
	var step := RCHAIN_SPEED * delta
	var reach := minf(step, from.distance_to(c))
	var to := from + rchain_dir * reach
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if not wall.is_empty():
		rchain_tip = wall["position"]
		rchain_event.emit(false)
		realm_blocked()
		return
	rchain_tip = to
	if to.distance_to(c) < 0.4 + rchain_target.hit_radius():
		rchain_state = 2   # esperando a resposta da máquina do alvo
		rchain_event.emit(true)
		rchain_tip = c
		rchain_target.remote_call("receive_realm", [String(name)])


## No alvo: quem está com a corrente voando nele agora (null se ninguém).
func realm_threat() -> Player:
	if is_instance_valid(rchain_incoming) and rchain_incoming.rchain_state == 1 \
			and rchain_incoming.rchain_target == self:
		return rchain_incoming
	return null


func _rchain_clear() -> void:
	rchain_state = 0
	if is_instance_valid(rchain_target) and rchain_target.rchain_incoming == self:
		rchain_target.rchain_incoming = null
	_rchain_visual(false)


## O inimigo que o Q pega: à vista, a até RCHAIN_RANGE e a até REALM_AIM_ANGLE do centro da
## mira; o mais perto do centro. Preenche também realm_in_range (as coroas) quando pedido.
func _realm_find(fill := false) -> Player:
	if fill:
		realm_in_range.clear()
	if realm > 0 or not head or rchain_state != 0:
		return null
	var eye := head.global_position
	var aim := -head.global_transform.basis.z
	var best: Player = null
	var best_angle := REALM_AIM_ANGLE
	for e in enemies():
		if e.realm_pull > 0.0 or e.ice_timer > 0.0 or e.hooked_by \
				or (e.is_hidden() and not e.camo_blink()):
			continue
		var to: Vector3 = e.chest() - eye
		if to.length() > RCHAIN_RANGE:
			continue
		var ray := PhysicsRayQueryParameters3D.create(eye, e.chest(), 1, [get_rid(), e.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		if fill:
			realm_in_range.append(e)
		var angle := aim.angle_to(to)
		if angle <= best_angle:
			best = e
			best_angle = angle
	return best


## Jogador local com o Domínio do Rei pronto: quem ganha a coroa e qual fica acesa.
func _realm_scan() -> void:
	if stats["realm"] > 0 and alive and master_ready():
		realm_aim = _realm_find(true)
	elif not realm_in_range.is_empty() or realm_aim:
		realm_in_range.clear()
		realm_aim = null


## No inimigo, na tela de quem tem o Domínio pronto: coroa com "Q" em cima do nome, apagada
## se está ao alcance e acesa se é o alvo da vez. Um Sprite3D (uma chamada de desenho).
func _update_realm_mark() -> void:
	var on := viewer != null and viewer != self and tag.visible and viewer.realm_in_range.has(self)
	if not on:
		if realm_mark:
			realm_mark.visible = false
		return
	if realm_mark == null:
		realm_mark = Sprite3D.new()
		realm_mark.texture = _realm_mark_texture()
		realm_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		realm_mark.no_depth_test = true
		realm_mark.fixed_size = true   # mesmo tamanho na tela a 5 ou a 30 m
		realm_mark.shaded = false
		realm_mark.render_priority = 2
		tag.add_child(realm_mark)
	realm_mark.visible = true
	var aimed: bool = viewer.realm_aim == self
	realm_mark.pixel_size = 0.00052 if aimed else 0.00039   # ~48 e ~36 px a 1080p
	realm_mark.modulate = Color(0.86, 0.68, 1.0, 1.0) if aimed else Color(0.78, 0.66, 0.95, 0.6)
	# A base da coroa fica no topo do nome (offset de meia textura para cima, em pixels de tela
	# com o fixed_size), para não cobrir o nome de longe; acima dos outros ícones, se houver.
	realm_mark.offset = Vector2(0, 70)
	var y := 0.32
	for s in guard_icons.values():
		if (s as Sprite3D).visible:
			y = 0.75
	if not unstable_cards.is_empty():
		y = 1.2
	realm_mark.position = Vector3(0, y, 0)


static var _realm_tex: Texture2D

## Coroa branca com contorno escuro e a tecla "Q" embaixo, desenhada uma vez de um SVG feito
## aqui (a cor vem do modulate). O Q é desenhado como traço, sem fonte.
static func _realm_mark_texture() -> Texture2D:
	if _realm_tex:
		return _realm_tex
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<path d="M22 62 L16 22 L42 42 L64 10 L86 42 L112 22 L106 62 Z" fill="#fff" stroke="#140a22" stroke-width="6" stroke-linejoin="round"/>
<rect x="22" y="62" width="84" height="11" rx="3" fill="#fff" stroke="#140a22" stroke-width="5"/>
<rect x="44" y="81" width="40" height="40" rx="8" fill="#140a22" fill-opacity="0.75" stroke="#fff" stroke-width="4"/>
<circle cx="63" cy="100" r="10" fill="none" stroke="#fff" stroke-width="5"/>
<path d="M68 105 L76 113" stroke="#fff" stroke-width="5" stroke-linecap="round"/>
</svg>"""
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.generate_mipmaps()
	_realm_tex = ImageTexture.create_from_image(img)
	return _realm_tex


## A corrente: um cilindro fino roxo da mão de quem lança até a ponta (ou até o alvo, no puxão).
static var _rchain_mesh: CylinderMesh

func _rchain_visual(on: bool) -> void:
	if not on:
		if rchain_fx:
			rchain_fx.queue_free()
			rchain_fx = null
		return
	if rchain_fx:
		return
	if _rchain_mesh == null:
		_rchain_mesh = CylinderMesh.new()
		_rchain_mesh.top_radius = 0.06
		_rchain_mesh.bottom_radius = 0.06
		_rchain_mesh.height = 1.0
		_rchain_mesh.radial_segments = 6
		_rchain_mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = RCHAIN_COLOR
		_rchain_mesh.material = mat
	rchain_fx = MeshInstance3D.new()
	rchain_fx.mesh = _rchain_mesh
	rchain_fx.top_level = true
	rchain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rchain_fx)


func _update_rchain_fx(delta: float) -> void:
	if rchain_state == 1 and not is_local and is_instance_valid(rchain_target):
		# Nas outras máquinas a ponta persegue o mesmo alvo sozinha (quem decide é a de quem lança).
		rchain_dir = (rchain_target.chest() - rchain_tip).normalized()
		rchain_tip += rchain_dir * minf(RCHAIN_SPEED * delta, rchain_tip.distance_to(rchain_target.chest()))
	var start := chest()
	if is_human:
		start = camera.global_position + Vector3.DOWN * 0.4 + camera.global_transform.basis.x * 0.25
	var end := rchain_tip
	if rchain_state == 3 and is_instance_valid(realm_pull_partner):
		end = realm_pull_partner.chest()
	var axis := end - start
	var length := axis.length()
	rchain_fx.visible = length > 0.05
	if not rchain_fx.visible:
		return
	axis /= length
	var x := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(axis).normalized()
	rchain_fx.global_transform = Transform3D(Basis(x, axis * length, z), (start + end) / 2.0)


## Na máquina do alvo: escudo levantado (ou não dá mais) bloqueia; senão todos entram.
func receive_realm(from_name: String) -> void:
	var king := get_parent().get_node_or_null(from_name) as Player
	if king == null:
		return
	if not alive or is_shielding() or ice_timer > 0.0 or hooked_by or realm > 0 or king.realm > 0 or not king.alive:
		reflect_flash = 1.0
		Sfx.at(self, "reflect", chest())
		king.remote_call("realm_blocked", [])
		return
	if Net.online and is_inside_tree():
		_net_realm.rpc(from_name)
	else:
		_net_realm(from_name)


## Errou (parede ou alcance) ou o escudo bloqueou: a corrente some e a recarga cai.
func realm_blocked() -> void:
	master_cd = minf(master_cd, REALM_BLOCKED_CD)
	_rchain_clear()
	if Net.online and is_local and is_inside_tree():
		_net_rchain.rpc(0, "")


## Em todas as máquinas, no nó do alvo: começa o puxão dos dois (REALM_PULL); no fim dele,
## entram na sala de quem lançou (_realm_pull_step).
@rpc("any_peer", "call_local", "reliable")
func _net_realm(from_name: String) -> void:
	var king := get_parent().get_node_or_null(from_name) as Player
	if king == null:
		return
	king.rchain_state = 3   # a corrente fica esticada até o alvo durante o puxão
	if king.rchain_fx == null:
		king._rchain_visual(true)
	for p: Player in [king, self]:
		p._realm_pull_start(self if p == king else king, p == king)


func _realm_pull_start(partner: Player, king: bool) -> void:
	realm_pull = REALM_PULL
	realm_pull_partner = partner
	realm_pull_king = king
	realm_pull_from = global_position
	Sfx.at(self, "realm_pull", chest())
	if is_local:
		sliding = false
		dash_timer = 0.0
		velocity = Vector3.ZERO
		if grapple_state > 0:
			_grapple_clear()
		_hook_let_go()


## Todas as máquinas, todo passo: o puxão anda (redemoinho no chão) e, no fim, os dois
## entram. Um dos dois morreu ou sumiu no meio: cancela sem entrar.
func _realm_pull_step(delta: float) -> void:
	realm_fade = maxf(0.0, realm_fade - delta)
	if realm_pull <= 0.0:
		return
	var partner := realm_pull_partner
	if not is_instance_valid(partner) or not partner.alive or not alive:
		realm_pull = 0.0
		if realm_king or realm_pull_king:
			_rchain_clear()
		return
	var before := realm_pull
	realm_pull -= delta
	if int(before / 0.2) != int(maxf(realm_pull, 0.0) / 0.2):
		Effects.burst(get_parent(), global_position + Vector3.UP * 0.1, 1.2, RCHAIN_COLOR, 0.2)
	if realm_pull > 0.0:
		return
	if not realm_pull_king:
		realm_pull = 0.001   # o alvo espera: quem lançou leva os dois no mesmo passo
		return
	_rchain_clear()
	var room := KingRealm.room_for(get_parent(), side)
	for p: Player in [self, partner]:
		p.realm_pull = 0.0
		Effects.burst(get_parent(), p.chest(), 2.2, RCHAIN_COLOR, 0.25)
		p._realm_enter(room, side + 1, partner if p == self else self, p == self)
		p.realm_return = p.realm_pull_from
		p.realm_fade = REALM_FADE_IN
		if p.realm_marker:
			p.realm_marker.position = p.realm_pull_from


func _realm_enter(room: KingRealm, slot: int, partner: Player, king: bool) -> void:
	realm = slot
	realm_timer = REALM_TIME
	realm_partner = partner
	realm_king = king
	realm_return = global_position
	if realm_marker:
		realm_marker.queue_free()
	realm_marker = KingRealm.Marker.new(REALM_TIME)
	realm_marker.position = global_position
	get_parent().add_child(realm_marker)
	if is_local:
		var to := room.spawn_for(king)
		sliding = false
		dash_timer = 0.0
		slap_flight = 0.0
		slap_lock = false
		if slap_windup > 0.0:
			_cancel_slap(false)
		swap_partner = null
		swap_timer = 0.0
		velocity = Vector3.ZERO
		rotation.y = to.basis.get_euler().y
		look_yaw = rotation.y
		teleport_to(to.origin)
	realm_changed.emit(true, false)


## Todas as máquinas, todo passo: o tempo acaba ou um dos dois morreu (quem sobrou venceu)
## -> sai. Quem sai vivo volta para onde estava; quem morreu fica onde está.
func _realm_tick(delta: float) -> void:
	realm_timer -= delta
	var partner_out := not is_instance_valid(realm_partner) or not realm_partner.alive \
			or realm_partner.realm != realm
	if realm_timer <= 0.0 or partner_out or not alive:
		var won := alive and is_instance_valid(realm_partner) and not realm_partner.alive
		_realm_leave(won)


func _realm_leave(won: bool) -> void:
	if won and realm_king:
		realm_bonus_kept = realm_bonus()
		realm_bonus_timer = REALM_WIN_TIME
	realm = 0
	realm_timer = 0.0
	realm_partner = null
	if realm_marker:
		realm_marker.queue_free()
		realm_marker = null
	if is_local and alive:
		velocity = Vector3.ZERO
		teleport_to(realm_return)
	realm_changed.emit(false, won)


## Começo de rodada: ninguém continua lá dentro (o nascimento já põe cada um no lugar).
func _realm_clear() -> void:
	_rchain_clear()
	realm_pull = 0.0
	realm_fade = 0.0
	realm_bonus_timer = 0.0
	realm_bonus_kept = 0.0
	realm = 0
	realm_timer = 0.0
	realm_partner = null
	if realm_marker:
		realm_marker.queue_free()
		realm_marker = null


## Cargas da mestra (1 nas que não têm "charges"; o Caos usa uma vez e sorteia).
func master_max_charges() -> int:
	if master_id == "" or chaos:
		return 1
	return int(CardDB.CARDS[master_id].get("charges", 1))


## A mestra ativa pode ser usada agora (com cargas: sobrou alguma e passou a espera).
func master_ready() -> bool:
	if master_id == "" or not CardDB.CARDS[master_id].has("cooldown"):
		return false
	if master_max_charges() > 1:
		return master_charges > 0 and master_gap <= 0.0
	return master_cd <= 0.0


## Recarga total mostrada na HUD (com o Caos, a espera até a próxima).
func master_cd_total() -> float:
	if chaos:
		return CHAOS_WAIT
	return float(CardDB.CARDS[master_id].get("cooldown", 1.0)) if master_id != "" else 1.0


## Habilidade da carta mestra (tecla Q).
func _use_master() -> void:
	var realm_target: Player = null
	if stats["realm"] > 0:
		realm_target = _realm_find()
		if realm_target == null:
			return   # Domínio do Rei sem ninguém na mira: não gasta
	if master_max_charges() > 1:
		if master_charges >= master_max_charges():
			master_cd = CardDB.CARDS[master_id]["cooldown"]   # a recarga começa com a 1a gasta
		master_charges -= 1
		master_gap = MASTER_CHARGE_GAP
	else:
		master_cd = CardDB.CARDS[master_id]["cooldown"]
	if chaos:
		master_cd = CHAOS_WAIT
		chaos_used = true
	master_used.emit()
	reveal()
	spawn_protect = 0.0   # usar a mestra também encerra a proteção do começo da rodada
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
		_start_slap()
	if stats["beam"] > 0:
		_start_beam()
	if stats["rocket_ride"] > 0:
		_start_ride()
	if stats["hook"] > 0:
		_hook_fire()
	if stats["unstable"] > 0:
		_unstable_draw()
	if stats["mech"] > 0:
		_start_mech()
	if stats["clone"] > 0:
		_start_clone()
	if stats["realm"] > 0:
		_rchain_fire(realm_target)
	if stats["grapple"] > 0:
		_grapple_fire()
	if stats["meteor"] > 0:
		meteor_left = METEOR_SHOTS
		meteor_window = METEOR_WINDOW
		Effects.burst(get_parent(), muzzle.global_position, 0.6, MeteorStrike.COLOR, 0.2)
		Sfx.at(self, "pickup", chest())
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
	since_attack = 0.0
	spawn_protect = 0.0   # atacar encerra a proteção do começo da rodada
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
	since_attack = 0.0
	spawn_protect = 0.0   # atacar encerra a proteção do começo da rodada
	sniper_shots -= 1
	fire_timer = 0.5   # a arma fica na mão um instante depois do tiro
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	shot_bonus = 0.0
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
	shot_bonus = 0.0
	Bullet.fire(self, muzzle.global_position, (target - muzzle.global_position).normalized(), 0.0, true,
		{"speed": ICE_SPEED, "ice": true, "radius": ICE_SHARD_RADIUS, "gravity": 0.0, "bounces": 0, "ghost_walls": 0,
		"explosion": 0.0, "poison": 0.0, "burn": 0.0, "slow": 0.0, "push": 0.0, "shield_break": false, "execute": 0.0,
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
	ice_store = 0.0
	ice_from = null
	frost_freeze = 0.0   # a Prisão manda: o congelado das camadas acaba (o bloco é o dela)
	thermal_from = null
	_frost_shown = false
	_stop_actions()
	froze.emit()
	_ice_visual(true)
	if Net.online and is_inside_tree():
		_net_ice.rpc(true)


## Congelado (Prisão de Gelo ou camadas): para tudo o que estava fazendo.
func _stop_actions() -> void:
	_end_beam(true)
	_ride_crash()
	_hook_let_go()
	shield_timer = 0.0
	dash_timer = 0.0
	sliding = false
	slamming = false
	scoping = false


func _thaw() -> void:
	ice_timer = 0.0
	_ice_visual(false)
	if Net.online and is_inside_tree():
		_net_ice.rpc(false)
	if ice_store > 0.0:
		# Degelo: o que o bloco guardou sai de uma vez, com a quebra do gelo.
		var by := ice_from if is_instance_valid(ice_from) else null
		var stored := ice_store
		ice_store = 0.0
		ice_from = null
		_frost_fx(2)
		take_damage(stored + FROST_BREAK, by)
	if ice_debt > 0.0 and alive:
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


## Bloco de gelo levou dano de inimigo (máquina dona): guarda uma parte para o degelo.
func _ice_store(amount: float, from: Player) -> void:
	if from == null or from == self or is_ally(from):
		return
	ice_store = minf(ICE_STORE_MAX, ice_store + amount * ICE_STORE)
	ice_from = from


## Caco da Prisão de Gelo bateu no cenário (cada máquina, nos jogadores dela): camadas em
## quem está perto.
static func ice_shard_burst(shooter: Player, point: Vector3) -> void:
	Effects.burst(shooter.get_parent(), point, ICE_SHARD_RANGE, ICE_COLOR, 0.25)
	Effects.sparks(shooter.get_parent(), point, ICE_COLOR, 10, 8.0)
	for p: Player in shooter.enemies():
		if p.is_local and p.chest().distance_to(point) < ICE_SHARD_RANGE:
			p.add_frost(ICE_SHARD_LAYERS, shooter)


# ---------------------------------------------------------------- Congelamento

## Acerto de bala de from (máquina dona do alvo, depois do dano, para o tiro que congela não
## quebrar o gelo na hora): as camadas das cartas dele.
func frost_hit(from: Player) -> void:
	if not is_instance_valid(from) or from == self or is_ally(from):
		return
	var n := int(from.stats["frost"])
	if from.stats["hypothermia"] > 0 and slow_timer > 0.0:
		n += 1   # Hipotermia
	add_frost(n, from)


## n camadas de from (máquina dona). Na última, congela.
func add_frost(n: int, from: Player) -> void:
	if not alive or downed or n <= 0 or ice_timer > 0.0 or frost_freeze > 0.0:
		return
	frost_from = from if is_instance_valid(from) else null
	frost_timer = _control_time(FROST_HOLD)
	frost_layers = mini(frost_layers + n, FROST_MAX if frost_guard <= 0.0 else FROST_MAX - 1)
	if frost_layers >= FROST_MAX:
		_frost_freeze(frost_from)


func _frost_freeze(from: Player) -> void:
	frost_layers = 0
	var valid := is_instance_valid(from)
	thermal_from = from if valid and from.stats["thermal"] > 0 else null
	frost_freeze = _control_time(FROST_FREEZE_HYPO if valid and from.stats["hypothermia"] > 0 else FROST_FREEZE)
	frost_guard = frost_freeze + FROST_GUARD
	_stop_actions()
	_frost_fx(1)


## A cada passo (máquina dona): congelado, proteção e camadas que caem.
func _frost_tick(delta: float) -> void:
	frost_guard = maxf(0.0, frost_guard - delta)
	if frost_freeze > 0.0:
		frost_freeze = maxf(0.0, frost_freeze - delta)
		if frost_freeze <= 0.0 and alive and not downed and is_instance_valid(thermal_from):
			# Choque Térmico: derreteu sozinho.
			var by := thermal_from
			take_damage(_thermal_burn(), by)
	if frost_layers > 0:
		frost_timer -= delta
		if frost_timer <= 0.0:
			frost_layers -= 1
			frost_timer = _control_time(FROST_DECAY)
			if frost_layers == 0:
				_chain_end("frost", float(SHATTER_LAYERS), frost_from)
	_frost_visual_sync(frost_freeze > 0.0)


## Congelado pelas camadas: para no lugar (sem deslizar como o bloco da Prisão), cai e quica.
func _frost_move(delta: float) -> void:
	const STOP := 40.0
	velocity.y -= (GRAVITY_RISE if velocity.y > 0.0 else GRAVITY_FALL) * delta
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, STOP * delta)
	velocity.x = h.x
	velocity.z = h.y
	move_and_slide()
	if global_position.y < Arena.VOID_Y and velocity.y <= 0.0:
		_void_bounce()


## Golpe em quem está congelado pelas camadas (dentro de take_damage): quebra o gelo.
## Devolve o dano com a quebra.
func _frost_break(amount: float, from: Player) -> float:
	frost_freeze = 0.0
	_frost_visual_sync(false)
	_frost_fx(2)
	amount += FROST_BREAK
	if is_instance_valid(thermal_from):
		amount += _thermal_burn()   # Choque Térmico: soma à quebra
	if from.stats["shatter"] > 0:
		# Estilhaço: metade do golpe e camadas em quem está perto.
		for q: Player in get_tree().get_nodes_in_group("players"):
			if q == self or q == from or not q.alive or q.is_ally(from) \
					or q.global_position.distance_squared_to(global_position) > SHATTER_RANGE * SHATTER_RANGE:
				continue
			q.remote_call("receive_shatter", [String(from.name), amount * 0.5])
			Effects.beam(get_parent(), chest(), q.chest(), FROST_COLOR, 0.05, 0.3)
	return amount


## FLAT_GAP (máquina do alvo): este acerto de from pode aplicar efeitos de valor fixo?
func flat_ready(from: Player) -> bool:
	if from == null:
		return false
	var now := Time.get_ticks_msec()
	if now < int(_flat_next.get(from, 0)):
		return false
	_flat_next[from] = now + int(FLAT_GAP * 1000.0)
	return true


## Pressão: acertou de perto (máquina dona de quem atirou).
func pressure_hit() -> void:
	var now := Time.get_ticks_msec()
	if stats["pressure"] <= 0 or now < _pressure_next:
		return
	_pressure_next = now + int(FLAT_GAP * 1000.0)
	pressure_timer = PRESSURE_TIME
	dash_cd = maxf(0.0, dash_cd - PRESSURE_DASH)


## Choque Térmico no fim do congelado: põe a Queimadura de quem congelou e devolve o dano a mais.
func _thermal_burn() -> float:
	var by := thermal_from
	thermal_from = null
	apply_burn(THERMAL_DPS * by.burn_dps_mult(), THERMAL_TIME, by)
	Effects.burst(get_parent(), chest(), 1.2, BURN_COLOR, 0.2)
	return THERMAL_DAMAGE


## Pegou o Estilhaço de from_name (máquina dona).
func receive_shatter(from_name: String, dmg: float) -> void:
	var from := get_parent().get_node_or_null(from_name) as Player
	if not alive or from == null:
		return
	take_area_damage(dmg, from)
	if alive:
		add_frost(SHATTER_LAYERS, from)


## Camadas no inimigo, para quem olha (2026-10-15, pedido do usuário: minimalista, em cima do
## corpo e não acima da cabeça): floco de gelo e "n/5", tamanho fixo na tela, no peito,
## desenhado por cima do próprio modelo (sem teste de profundidade; no 1o print o braço e a
## arma cobriam). Para não entregar ninguém escondido, só aparece com linha de visão da câmera
## ao peito (um raio a cada FROST_MARK_LOS s) ou quando o nome atravessa paredes (Marca,
## Radar, aliado).
const FROST_MARK_ICON := 0.00026    # ~24 px a 1080p (textura de 128)
const FROST_MARK_TEXT := 0.0007     # ~16 px de altura (fonte 32)
const FROST_MARK_LOS := 0.1
var _frost_los_wait := 0.0
var _frost_los := false

func _update_frost_mark() -> void:
	var on := frost_layers > 0 and alive and tag.visible and viewer != null and viewer != self \
			and ice_timer <= 0.0 and not _frost_shown
	if not on:
		if frost_mark:
			frost_mark.visible = false
		return
	if frost_mark == null:
		frost_mark = Node3D.new()
		var s := Sprite3D.new()
		s.texture = load("res://assets/card_icons/marca_gelo.svg")
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.fixed_size = true
		s.pixel_size = FROST_MARK_ICON
		s.offset = Vector2(-40, 0)   # pixels da textura: o floco à esquerda, o número à direita
		s.shaded = false
		s.modulate = Color(FROST_COLOR, 0.9)
		s.no_depth_test = true
		s.render_priority = 2
		frost_mark.add_child(s)
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = FROST_MARK_TEXT
		l.font_size = 32
		l.outline_size = 8
		l.outline_modulate = Color(0, 0, 0, 0.6)
		l.modulate = Color(0.9, 0.97, 1.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.offset = Vector2(12, 0)
		l.no_depth_test = true
		l.render_priority = 2
		frost_mark.add_child(l)
		_frost_mark_label = l
		add_child(frost_mark)
		_frost_mark_n = -1
	var c := chest()
	var cam := get_viewport().get_camera_3d()
	_frost_los_wait -= get_process_delta_time()
	if _frost_los_wait <= 0.0 and cam:
		_frost_los_wait = FROST_MARK_LOS
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, c, 1)
		_frost_los = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	frost_mark.visible = _frost_los or tag.no_depth_test
	if not frost_mark.visible:
		return
	if frost_layers != _frost_mark_n:
		_frost_mark_n = frost_layers
		_frost_mark_label.text = "%d/%d" % [frost_layers, FROST_MAX]
	frost_mark.global_position = c


## Bloco do congelado das camadas: o mesmo da Prisão, menos na própria tela (a câmera está
## dentro da cabeça; lá o aviso é o HUD). A Prisão, se vier junto, cuida do bloco.
func _frost_visual_sync(on: bool) -> void:
	if on == _frost_shown or ice_timer > 0.0:
		return
	_frost_shown = on
	if not is_human:
		_ice_visual(on)


## Congelou (1) ou quebrou o gelo (2), em todas as máquinas.
func _frost_fx(kind: int) -> void:
	_show_frost_fx(kind)
	if Net.online and is_inside_tree():
		_net_frost_fx.rpc(kind)


@rpc("authority", "call_remote", "reliable")
func _net_frost_fx(kind: int) -> void:
	_show_frost_fx(kind)


func _show_frost_fx(kind: int) -> void:
	if kind == 1:
		Effects.burst(get_parent(), chest(), 1.4, FROST_COLOR, 0.25)
		Sfx.at(self, "pickup", chest())
	else:
		Effects.explosion(get_parent(), chest(), 1.6, ICE_COLOR, 0.3)
		Effects.sparks(get_parent(), chest(), ICE_COLOR, 12, 9.0)
		Sfx.at(self, "hit", chest())


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

## Q: ergue a mão; o tapa sai sozinho em SLAP_WINDUP (_tick).
func _start_slap() -> void:
	slap_windup = SLAP_WINDUP
	_show_windup(true)
	if Net.online:
		_net_windup.rpc(true)


## Preparação cortada (morreu, congelou, foi fisgado, levou tapa, ficou tonto, montou).
func _cancel_slap(send := true) -> void:
	slap_windup = 0.0
	_show_windup(false)
	if send and Net.online and is_inside_tree():
		_net_windup.rpc(false)


@rpc("authority", "call_remote", "reliable")
func _net_windup(on: bool) -> void:
	_show_windup(on)


## Mão erguida: na própria tela sobe do canto e fica puxada para trás, tremendo de leve;
## para os outros, a mão grande sobe acima do ombro direito.
func _show_windup(on: bool) -> void:
	if not on:
		if hand_pivot and hand_pivot.visible:
			_hand_tween = _retween(_hand_tween)
			_hand_tween.tween_property(hand_pivot, "position", Vector3(0.4, -0.6, -0.44), 0.12)
			_hand_tween.tween_callback(func(): hand_pivot.visible = false)
		if hand_3p:
			if _hand_3p_tween and _hand_3p_tween.is_valid():
				_hand_3p_tween.kill()
			hand_3p.visible = false
		return
	Sfx.at(self, "pickup", chest())
	if hand_pivot and is_human:
		hand_pivot.visible = true
		hand_pivot.position = Vector3(0.4, -0.6, -0.44)
		hand_pivot.rotation = Vector3(0.25, 0.1, -0.25)
		_hand_tween = _retween(_hand_tween)
		_hand_tween.tween_property(hand_pivot, "position", Vector3(0.33, 0.16, -0.44), 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Puxa para trás devagar (a "carga") até a hora do tapa.
		_hand_tween.tween_property(hand_pivot, "position", Vector3(0.42, 0.2, -0.38), SLAP_WINDUP - 0.15) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_hand_tween.parallel().tween_property(hand_pivot, "rotation", Vector3(0.4, 0.2, -0.35), SLAP_WINDUP - 0.15)
	if hand_3p and not is_human:
		hand_3p.visible = true
		hand_3p.position = Vector3(0.55, 1.2, 0.1)
		hand_3p.rotation = Vector3(0.0, 0.7, 0.3)
		_hand_3p_tween = _retween(_hand_3p_tween)
		_hand_3p_tween.tween_property(hand_3p, "position", Vector3(0.8, 2.0, 0.2), 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_hand_3p_tween.tween_property(hand_3p, "position", Vector3(0.9, 2.05, 0.35), SLAP_WINDUP - 0.15)


func _retween(t: Tween) -> Tween:
	if t and t.is_valid():
		t.kill()
	return create_tween()


## Tapa: quem está no leque curto à frente leva (a máquina do alvo decide o escudo).
func _slap() -> void:
	slap_windup = 0.0
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
	if mech_state == 2:
		take_damage(SLAP_DAMAGE, get_parent().get_node_or_null(from_name) as Player)   # Mecha: não voa
		return
	_end_beam(true)
	_ride_crash()
	_hook_let_go()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	velocity = (flat * SLAP_PUSH + Vector3.UP * SLAP_LIFT) * push_mult()
	jump_rising = false
	coyote = 0.0
	sliding = false
	dash_timer = 0.0
	if ice_timer > 0.0:
		return
	slap_flight = SLAP_FLIGHT
	slap_lock = true
	slap_from = from_name
	splat_damage = SPLAT_DAMAGE
	bowl = false
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
		var other := c.get_collider() as Player
		if other:
			# Gancho: arremessado em cima de alguém (que não seja quem jogou), os dois levam.
			# O parceiro de quem arremessou não leva (2x2); os dois inimigos levam e ficam tontos.
			var thrower := get_parent().get_node_or_null(slap_from) as Player
			if bowl and String(other.name) != slap_from and other.alive 					and not (thrower and thrower.is_ally(other)):
				slap_flight = 0.0
				bowl = false
				other.remote_call("receive_bowl", [slap_from])
				take_damage(HOOK_IMPACT, thrower)
				_daze(DAZE_TIME, thrower)
				_show_splat(c.get_position())
				if Net.online:
					_net_splat.rpc(c.get_position())
				return
			continue
		if absf(c.get_normal().y) > 0.6:
			continue
		if before_h.normalized().dot(-c.get_normal()) < 0.3:
			continue   # raspou de lado
		slap_flight = 0.0
		if bowl:
			bowl = false   # Gancho: na parede só o dano; a tontura vem de acertar outro jogador
		else:
			_daze(DAZE_TIME, get_parent().get_node_or_null(slap_from) as Player)
		shake = maxf(shake, 0.6)
		take_damage(splat_damage, get_parent().get_node_or_null(slap_from) as Player)
		_show_splat(c.get_position())
		slapped.emit(true)
		if Net.online:
			_net_splat.rpc(c.get_position())
		return


## Tonto (parede no Mega Tapa, boliche do Gancho): lento e sem atirar por DAZE_TIME.
func _daze(time := DAZE_TIME, from: Player = null) -> void:
	apply_slow(DAZE_SLOW, time, from)   # antes da conta: o apply_slow já desconta a Tenacidade
	aff_from["daze"] = from
	time = _control_time(time)
	daze_timer = maxf(daze_timer, time)
	daze_fx = maxf(daze_fx, DAZE_FX_TIME + time - DAZE_TIME)


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
	# Passada rápida da direita para a esquerda, deixando cópias da mão que somem (rastro).
	if hand_pivot and is_human:
		hand_pivot.visible = true
		_hand_tween = _retween(_hand_tween)
		_hand_tween.tween_property(hand_pivot, "position", Vector3(-0.9, 0.02, -0.47), SLAP_SWIPE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_tween.parallel().tween_property(hand_pivot, "rotation", Vector3(0.0, -0.4, 0.15), SLAP_SWIPE)
		for k in SLAP_GHOSTS:
			_hand_tween.parallel().tween_callback(_hand_ghost.bind(hand_pivot)).set_delay(SLAP_SWIPE * (k + 1) / (SLAP_GHOSTS + 1))
		_hand_tween.tween_interval(0.12)
		_hand_tween.tween_property(hand_pivot, "position", Vector3(-0.9, -0.6, -0.4), 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_hand_tween.tween_callback(func(): hand_pivot.visible = false)
	if hand_3p and not is_human:
		hand_3p.visible = true
		_hand_3p_tween = _retween(_hand_3p_tween)
		_hand_3p_tween.tween_property(hand_3p, "position", Vector3(-0.6, 1.3, -0.9), SLAP_SWIPE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_3p_tween.parallel().tween_property(hand_3p, "rotation", Vector3(0.0, -0.7, -0.2), SLAP_SWIPE)
		for k in SLAP_GHOSTS:
			_hand_3p_tween.parallel().tween_callback(_hand_ghost.bind(hand_3p)).set_delay(SLAP_SWIPE * (k + 1) / (SLAP_GHOSTS + 1))
		_hand_3p_tween.tween_interval(0.2)
		_hand_3p_tween.tween_callback(func(): hand_3p.visible = false)


## Rastro do tapa: cópia da mão no lugar atual, translúcida, que some em SLAP_GHOST_FADE.
## Só nasce no tapa (SLAP_GHOSTS por golpe), então o custo é desprezível.
func _hand_ghost(pivot: Node3D) -> void:
	if not is_instance_valid(pivot) or not pivot.visible:
		return
	var ghost := pivot.get_child(0).duplicate() as Node3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(SLAP_COLOR, 0.45)
	for mi in ghost.get_children():
		(mi as MeshInstance3D).material_override = mat
	var holder := Node3D.new()
	holder.transform = pivot.transform
	holder.add_child(ghost)
	pivot.get_parent().add_child(holder)
	var t := holder.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, SLAP_GHOST_FADE)
	t.tween_callback(holder.queue_free)


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


# ---------------------------------------------------------------- Gancho

signal hooked_someone   # registro do autoteste

func _hook_fire() -> void:
	hook_state = 1
	hook_dir = -head.global_transform.basis.z
	hook_tip = chest()
	hook_dist = 0.0
	hook_taken = 0.0
	reveal()
	Sfx.at(self, "dash", chest())
	_hook_visual(true)
	if Net.online and is_inside_tree():
		_net_hook_fire.rpc(hook_dir)


@rpc("authority", "call_remote", "reliable")
func _net_hook_fire(dir: Vector3) -> void:
	hook_state = 1
	hook_dir = dir
	hook_tip = chest()
	hook_dist = 0.0
	_hook_visual(true)


## A ponta voa (na máquina de quem lança): parede ou fim do alcance = errou; um inimigo
## perto da linha = manda o gancho para a máquina dele decidir.
func _hook_fly(delta: float) -> void:
	_hook_magnet(delta)
	var step := HOOK_SPEED * delta
	var from := hook_tip
	var to := hook_tip + hook_dir * step
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	for enemy: Player in enemies():
		if enemy.ice_timer > 0.0 or enemy.hooked_by:
			continue
		var c := enemy.chest()
		var t := clampf((c - from).dot(hook_dir), 0.0, step)
		if (from + hook_dir * t).distance_to(c) < 0.5 + enemy.hit_radius():
			hook_state = 4   # esperando a resposta da máquina do alvo
			hook_target = enemy
			hook_tip = c
			enemy.remote_call("receive_hook", [String(name)])
			return
	hook_tip = to
	hook_dist += step
	if not wall.is_empty() or hook_dist >= HOOK_RANGE:
		_hook_miss()


func _hook_magnet(delta: float) -> void:
	var best: Player = null
	var best_dist := HOOK_MAGNET_RANGE
	for enemy: Player in enemies():
		if enemy.ice_timer > 0.0 or enemy.hooked_by:
			continue
		var to := enemy.chest() - hook_tip
		var d := to.length()
		if d < best_dist and d > 0.01 and hook_dir.dot(to / d) > HOOK_MAGNET_CONE:
			best = enemy
			best_dist = d
	if best == null:
		return
	var space := get_world_3d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(hook_tip, best.chest(), 1)).is_empty():
		return
	var want := (best.chest() - hook_tip).normalized()
	var angle := hook_dir.angle_to(want)
	if angle > 0.001:
		hook_dir = hook_dir.slerp(want, minf(1.0, HOOK_MAGNET_TURN * delta / angle)).normalized()


func _hook_miss() -> void:
	_hook_clear()
	master_cd = minf(master_cd, HOOK_MISS_CD)
	if Net.online and is_inside_tree():
		_net_hook_end.rpc()


## Na máquina do alvo: escudo bloqueia; senão fica preso e avisa todas as máquinas.
func receive_hook(from_name: String) -> void:
	var grabber := get_parent().get_node_or_null(from_name) as Player
	if grabber == null:
		return
	if not alive or is_shielding() or ice_timer > 0.0 or hooked_by or mech_state == 2:
		reflect_flash = 1.0
		Sfx.at(self, "reflect", chest())
		grabber.remote_call("hook_blocked", [])
		return
	if Net.online and is_inside_tree():
		_net_hooked.rpc(from_name, 2)
	else:
		_net_hooked(from_name, 2)


func hook_blocked() -> void:
	_hook_miss()


## Estado do gancho (todas as máquinas; chamado pelo alvo): 2 puxando, 3 segurando, 0 solto.
@rpc("any_peer", "call_local", "reliable")
func _net_hooked(from_name: String, state: int) -> void:
	var grabber := get_parent().get_node_or_null(from_name) as Player
	if grabber == null:
		return
	if state == 0:
		if hooked_by:
			remove_collision_exception_with(hooked_by)
			hooked_by.remove_collision_exception_with(self)
		hooked_by = null
		grabber._hook_clear()
		_restore_overlay()
		return
	if state == 2:
		hooked_by = grabber
		add_collision_exception_with(grabber)
		grabber.add_collision_exception_with(self)
		grabber.hook_target = self
		grabber.hook_taken = 0.0
		grabber._hook_visual(true)
		grabber.hooked_someone.emit()
		_restore_overlay()
		sliding = false
		dash_timer = 0.0
		shield_timer = 0.0
		_end_beam(true)
		_ride_crash()
	grabber.hook_state = state


## Preso (na máquina do alvo): puxado até a frente de quem segura, depois fica lá.
func _hooked_step(delta: float) -> void:
	var g := hooked_by
	if not is_instance_valid(g) or not g.alive or not alive:
		_hook_free()
		return
	var forward := -g.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var spot := g.global_position + forward * HOOK_HOLD_DIST + right * HOOK_HOLD_SIDE + Vector3.UP * 0.2
	if g.hook_state == 2:
		# Puxando: parede entre os dois arrebenta a corrente.
		var los := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(chest(), g.chest(), 1))
		if not los.is_empty():
			_hook_free()
			return
		var to := spot - global_position
		if to.length() <= HOOK_PULL * delta + 0.2:
			hook_hold = HOOK_HOLD
			_net_hooked_all(String(g.name), 3)
		else:
			velocity = to.normalized() * HOOK_PULL
			move_and_slide()
			return
	hook_hold -= delta
	if hook_hold <= 0.0:
		_hook_free()   # cai aos pés de quem segurava
		return
	global_position = spot
	velocity = Vector3.ZERO


func _net_hooked_all(from_name: String, state: int) -> void:
	if Net.online and is_inside_tree():
		_net_hooked.rpc(from_name, state)
	else:
		_net_hooked(from_name, state)


## Solta (na máquina do alvo) e avisa todas.
func _hook_free() -> void:
	if hooked_by == null:
		return
	_net_hooked_all(String(hooked_by.name), 0)


## Quem segura arremessa: manda para a máquina do alvo.
func _hook_throw_now() -> void:
	if hook_target == null:
		return
	# Do preso até o ponto mirado (ele fica à direita; reto pela mira passaria ao lado).
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(head.global_position, head.global_position + aim * 60.0,
		1 | 2, [get_rid(), hook_target.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit["position"] if not hit.is_empty() else head.global_position + aim * 60.0
	var dir := (point - hook_target.chest()).normalized()
	hook_target.remote_call("hook_throw", [dir])
	hook_state = 0
	Sfx.at(self, "dash", chest())


func hook_throw(dir: Vector3) -> void:
	var g := hooked_by
	if g == null:
		return
	var from := String(g.name)
	_hook_free()
	velocity = dir.normalized() * HOOK_THROW + Vector3.UP * HOOK_THROW_LIFT
	jump_rising = false
	slap_flight = SLAP_FLIGHT
	slap_from = from
	splat_damage = HOOK_IMPACT
	bowl = true


## Quem segura solta (levou dano demais, congelou, levou tapa, morreu): avisa o alvo.
func _hook_let_go() -> void:
	if hook_state >= 2 and hook_target:
		hook_target.remote_call("hook_release", [])
	elif hook_state == 1 or hook_state == 4:
		_hook_miss()


func hook_release() -> void:
	_hook_free()


## Levou um jogador arremessado em cima (máquina dele).
func receive_bowl(from_name: String) -> void:
	if not alive:
		return
	knockback(Vector3.UP * 4.0)
	take_damage(HOOK_IMPACT, get_parent().get_node_or_null(from_name) as Player)
	_daze(DAZE_TIME, get_parent().get_node_or_null(from_name) as Player)


@rpc("authority", "call_remote", "reliable")
func _net_hook_end() -> void:
	_hook_clear()


func _hook_clear() -> void:
	hook_state = 0
	hook_target = null
	_hook_visual(false)
	if hooked_by and is_local:
		_hook_free()


## Corrente: cilindro fino de quem lança até a ponta (ou até quem está preso).
static var _chain_mesh: CylinderMesh

func _hook_visual(on: bool) -> void:
	if not on:
		if hook_fx:
			hook_fx.queue_free()
			hook_fx = null
		return
	if hook_fx:
		return
	if _chain_mesh == null:
		_chain_mesh = CylinderMesh.new()
		_chain_mesh.top_radius = 0.05
		_chain_mesh.bottom_radius = 0.05
		_chain_mesh.height = 1.0
		_chain_mesh.radial_segments = 6
		_chain_mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = HOOK_COLOR
		mat.metallic = 0.6
		_chain_mesh.material = mat
	hook_fx = MeshInstance3D.new()
	hook_fx.mesh = _chain_mesh
	hook_fx.top_level = true
	hook_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hook_fx)


func _update_hook_fx(delta: float) -> void:
	if hook_state == 1 and not is_local:
		hook_tip += hook_dir * HOOK_SPEED * delta   # nas outras máquinas a ponta voa sozinha
	var start := chest() + Vector3.DOWN * (0.35 if is_human else 0.0)
	if is_human:
		start = camera.global_position + Vector3.DOWN * 0.4 + camera.global_transform.basis.x * 0.25
	var end := hook_tip
	if hook_state >= 2 and is_instance_valid(hook_target):
		end = hook_target.chest()
	var axis := end - start
	var length := axis.length()
	if length < 0.05 or (is_human and hook_state == 3):
		hook_fx.visible = false   # segurando, na própria tela a corrente só atrapalha
		return
	hook_fx.visible = true
	axis /= length
	var x := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(axis).normalized()
	hook_fx.global_transform = Transform3D(Basis(x, axis * length, z), (start + end) / 2.0)


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
		"ghost_walls": 0, "explosion": 0.0, "poison": 0.0, "burn": 0.0, "slow": 0.0, "push": 0.0, "shield_break": false,
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
	Effects.explosion(parent, pos, ROCKET_BLAST_RADIUS, ROCKET_COLOR)
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
		p.take_area_damage(ROCKET_BLAST_DAMAGE * (1.0 - 0.5 * clampf(d / ROCKET_BLAST_RADIUS, 0.0, 1.0)),
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
## O dano do meteoro sai do dano da bala que marcou (MeteorStrike.damage_for).
func meteor_mark(point: Vector3, shot_damage: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 60.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var ground: Vector3 = hit["position"] if not hit.is_empty() else point
	var dmg := MeteorStrike.damage_for(shot_damage)
	if Net.online and is_inside_tree():
		_net_meteor.rpc(ground, dmg)
	else:
		_net_meteor(ground, dmg)


@rpc("authority", "call_local", "reliable")
func _net_meteor(pos: Vector3, dmg: float) -> void:
	MeteorStrike.spawn(get_parent(), pos, self, dmg)
	meteor_marked.emit()


# ---------------------------------------------------------------- Plataformas Suspensas

## Plataforma sob os pés, nesta e nas outras máquinas (para todo mundo poder pisar).
func _make_platform() -> SkyPlatform:
	plat_left -= 1
	if plat_left <= 0:
		_plat_end()
	else:
		plat_chain = PLAT_CHAIN
	var pos := global_position + Vector3.DOWN * (SkyPlatform.SIZE.y / 2.0 + 0.02)
	var plat := SkyPlatform.spawn(get_parent(), pos, color)
	platform_made.emit()
	if Net.online and is_inside_tree():
		_net_platform.rpc(pos)
	return plat


## Pisou numa plataforma que ainda não te lançou: propulsor para cima, sem perder o embalo.
## on_sky_floor: parado no chão, o Godot às vezes não registra colisão no passo; aí fica o
## valor anterior.
func _plat_end() -> void:
	plat_chain = 0.0
	plat_left = 0
	plat_cd = PLAT_COOLDOWN


func _check_sky_pad() -> void:
	if not is_on_floor():
		on_sky_floor = false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y <= 0.7:
			continue
		var plat := c.get_collider() as SkyPlatform
		on_sky_floor = plat != null
		if plat and plat.use_by(self):
			_platform_launch()
			return


func _platform_launch() -> void:
	velocity.y = maxf(velocity.y, PLAT_LAUNCH)
	jump_rising = false
	coyote = 0.0
	sliding = false
	slamming = false
	Sfx.at(self, "pad", global_position)


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
		velocity = push * BEAM_SHIELD_PUSH * push_mult()
		return
	velocity = push * push_mult()
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
	since_attack = 0.0
	spawn_protect = 0.0   # atacar encerra a proteção do começo da rodada
	rockets_left -= 1
	fire_timer = BAZOOKA_INTERVAL
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	shot_bonus = 0.0
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
	perfect_tried = false
	perfect_mag = false


## Quanto da recarga já passou (0 a 1).
func reload_progress() -> float:
	return clampf(1.0 - reload_timer / maxf(0.01, float(stats["reload_time"])), 0.0, 1.0)


## Recarga Perfeita: R de novo durante a recarga.
func _try_perfect_reload() -> void:
	perfect_tried = true
	var p := reload_progress()
	var ok := p >= PERFECT_START and p <= PERFECT_END
	if ok:
		ammo = stats["mag_size"]
		reload_timer = 0.0
		perfect_mag = true
		if is_human:
			Sfx.ui(self, "hitmarker")
	else:
		reload_timer += PERFECT_MISS
	perfect_reloaded.emit(ok)


## Coice da Pólvora Extra (ver RECOIL_BASE); o Peso Pesado segura como segura os empurrões.
func _recoil() -> void:
	var copies := int(stats["recoil"])
	if copies <= 0:
		return
	var back := head.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return   # mirando reto para cima ou para baixo: nada para trás
	var power := minf(RECOIL_MAX, RECOIL_BASE * pow(copies, RECOIL_EXP)) * push_mult()
	velocity += back.normalized() * power


## Clique: um tiro, ou a rajada inteira com a Rajada (os outros saem em _act a cada
## BURST_GAP). Cada tiro da rajada gasta uma bala (2026-10-11; antes a rajada saía de uma
## bala só e multiplicava com Cano Duplo e Escopeta).
func _fire() -> void:
	click_id += 1
	burst_left = stats["burst"] - 1
	burst_timer = BURST_GAP
	fire_timer = maxf(stats["fire_interval"], stats["burst"] * BURST_GAP)
	_shoot()


## Um tiro: gasta uma bala e dispara (_volley).
func _shoot() -> void:
	_recoil()
	since_attack = 0.0
	spawn_protect = 0.0   # atacar encerra a proteção do começo da rodada
	# Escopeta (2026-10-13): cada bala do leque gasta 1 do pente; sem o bastante, saem só as
	# que houver (as balas de graça, como a do Cano Duplo, saem sempre).
	var cost := mini(1 + int(stats["shot_ammo"]), ammo)
	shot_count = int(stats["bullet_count"]) - (1 + int(stats["shot_ammo"]) - cost)
	# Cartucheira: cada bala que sairia do pente sorteia se sai de graça (a HUD pisca o traço).
	var paid := cost
	if stats["free_ammo"] > 0.0:
		for k in cost:
			if randf() < float(stats["free_ammo"]):
				paid -= 1
		if paid < cost:
			free_ammo_shown = cost - paid
			free_ammo_flash = Time.get_ticks_msec()
	ammo -= paid
	fired.emit()
	pierce_shot = pierce_left > 0
	if pierce_shot:
		pierce_left -= 1
	meteor_shot = meteor_left > 0
	if meteor_shot:
		meteor_left -= 1
	shot_bonus = float(stats["last_shot"]) - 1.0 if ammo == 0 else 0.0
	_volley()
	strike_timer = 0.0   # Arrancada: só o próximo tiro (o leque inteiro)
	if ammo == 0:
		burst_left = 0   # a rajada acaba com o pente
		if stats["shield_on_empty"] > 0 and shield_cd <= 0.0 and silence_timer <= 0.0:
			_activate_shield()


## Um disparo: a mira é o centro da câmera. Um raio acha o ponto mirado e as balas
## saem do cano até ele, abertas em leque quando há mais de uma.
func _volley() -> void:
	var origin := head.global_position
	var aim := -head.global_transform.basis.z
	# Revela antes das balas (2026-10-14, pedido do usuário): o tiro que tira você da
	# Camuflagem já sai com a Emboscada (+40% e atravessando paredes).
	reveal()
	var ambush_pierce := ambush_shot
	ambush_shot = false
	# Bala que atravessa parede mira só nos jogadores: o ponto na parede a entortaria.
	var mask := 2 if pierce_shot or ambush_pierce or stats["ghost"] > 0 else 1 | 2
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 300.0, mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + aim * 300.0
	if pierce_shot:
		# O cano fica abaixo da mira: convergindo no 1o jogador, a bala subiria por cima de
		# quem está atrás dele. Convergindo mais longe, a fila inteira fica na linha.
		target = origin + aim * maxf(origin.distance_to(target), PIERCE_CONVERGE)
	var count := shot_count
	var echo_on := is_instance_valid(clone) and realm == 0
	var echo_from := Vector3.ZERO
	if echo_on:
		echo_from = clone.aim_at(target)   # o clone vira, ergue a arma e dispara junto
		if Net.online and is_inside_tree():
			_net_clone_aim.rpc(target)
	var spread := deg_to_rad(stats["spread"])
	for k in count:
		var dir := (target - muzzle.global_position).normalized()
		if count > 1:
			dir = dir.rotated(Vector3.UP, spread * (k - (count - 1) / 2.0))
		var mult := 1.0
		var crit := randf() < float(stats["crit_chance"])
		var extra := {"crit": crit, "click": click_id,
			"bonus": shot_bonus + (CRIT_BONUS if crit else 0.0)}
		if pierce_shot:
			# Perfurante: reta, bem mais rápida e atravessando paredes.
			extra.merge({"speed": float(stats["bullet_speed"]) * PIERCE_SPEED, "gravity": 0.0,
				"ghost": true, "pierce": true, "drill": true})
			mult *= PIERCE_DAMAGE
		elif ambush_pierce:
			# Emboscada: só atravessa o cenário; velocidade e queda da bala normais.
			extra.merge({"ghost": true, "ambush": true})
		var echo := extra.duplicate()
		if meteor_shot and k == 0:
			extra["meteor"] = true   # só a primeira bala do disparo marca (escopeta)
		Bullet.fire(self, muzzle.global_position, dir, mult, k == 0, extra)
		if echo_on:
			# Clone: o mesmo tiro sai dele, na direção do ponto mirado, com metade do dano
			# (sem marcar meteoro nem devolver bala da Reciclagem).
			var echo_dir := (target - echo_from).normalized()
			if count > 1:
				echo_dir = echo_dir.rotated(Vector3.UP, spread * (k - (count - 1) / 2.0))
			echo["click"] = 0
			Bullet.fire(self, echo_from, echo_dir, mult * CLONE_ECHO, false, echo)
	recoil = 1.0
	muzzle_light.light_energy = 3.0
	muzzle_light.visible = true


## Dano de um disparo. Soma única (2026-10-14, pedido do usuário: o dano escalava muito mais
## que a vida): os bônus de situação (Recarga Perfeita, Fúria, Emboscada, Botas, velocidade,
## Sangue Frio, Domínio do Rei, e os extra: Última Bala e crítico) somam no bônus de Dano das
## cartas em vez de multiplicar o total. extra: bônus a mais deste disparo.
func shot_damage(extra := 0.0) -> float:
	return damage_for(damage_sum() + extra)


## Dano com esta soma de bônus (1 + bônus), sobre o dano da arma sem os bônus das cartas.
func damage_for(sum: float) -> float:
	return float(stats["damage"]) / (1.0 + stats["damage_bonus"]) * sum * (1.0 - realm_weaken())


## 1 + todos os bônus de Dano que valem agora (cartas e situação). A bala guarda este número
## (Bullet.bonus) para somar os bônus do acerto (Executor, Vingança) e da Bola de Neve.
func damage_sum() -> float:
	var sum: float = 1.0 + stats["damage_bonus"]
	if perfect_mag:
		sum += PERFECT_DAMAGE
	if health < stats["max_health"] * RAGE_THRESHOLD:
		sum += stats["rage"]
	if ambush_timer > 0.0:
		sum += AMBUSH_DAMAGE
	if stats["rocket_boots"] > 0:
		sum += air_bonus()
	sum += speed_bonus()
	if is_still_aiming():
		sum += STILL_DAMAGE * stats["still_aim"]
	if strike_timer > 0.0:
		sum += STRIKE_DAMAGE   # Arrancada
	return sum + realm_bonus()


## Domínio do Rei: o alvo perde REALM_WEAKEN_RATE do dano por segundo lá dentro (até o MAX).
func realm_weaken() -> float:
	if realm > 0 and not realm_king:
		return minf(REALM_WEAKEN_MAX, REALM_WEAKEN_RATE * (REALM_TIME - realm_timer))
	return 0.0


## Domínio do Rei: o bônus de dano de quem lançou, lá dentro ou guardado depois de vencer.
func realm_bonus() -> float:
	if realm > 0 and realm_king:
		return minf(REALM_BONUS_MAX, REALM_BONUS_RATE * (REALM_TIME - realm_timer))
	return realm_bonus_kept if realm_bonus_timer > 0.0 else 0.0


## Sangue Frio valendo agora: parado ou agachado (sem deslizar), no chão.
func is_still_aiming() -> bool:
	if stats["still_aim"] <= 0 or not is_on_floor() or sliding:
		return false
	return crouching or Vector2(velocity.x, velocity.z).length() < STILL_MAX_SPEED


## Reciclagem: uma bala acertou alguém (chamado pela máquina do alvo). Cada bala que
## acerta devolve 1 por cópia (2026-10-13, pedido do usuário; antes era 1 vez por clique).
func bullet_refund(_click: int) -> void:
	if stats["recycle"] <= 0 or not alive:
		return
	ammo = mini(ammo + int(stats["recycle"]), stats["mag_size"])


## Velocidade Letal: bônus de dano pela velocidade de lado agora (0 sem a carta).
func speed_bonus() -> float:
	if stats["speed_damage"] <= 0.0:
		return 0.0
	# Cada cópia (0,3 de teto) soma 2% por m/s: o teto de 24 m/s de lado dá +30% / +60%.
	var over := Vector2(velocity.x, velocity.z).length() - SPEED_DAMAGE_FROM
	var rate: float = SPEED_DAMAGE_RATE * stats["speed_damage"] / 0.3
	return clampf(over * rate, 0.0, stats["speed_damage"])


## Vulto: multiplicador do dano de bala que você leva (1 sem a carta ou devagar). Roda na
## máquina de quem leva o tiro, que conhece a própria velocidade.
func bullet_taken_mult() -> float:
	var n := mini(int(stats["blur"]), BLUR_REDUCE.size() - 1)
	if n <= 0 or Vector2(velocity.x, velocity.z).length() < BLUR_SPEED:
		return 1.0
	return 1.0 - BLUR_REDUCE[n]


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
	adrenaline_used = false
	if stats["shield_echo"] > 0 and echo_timer <= 0.0:
		echo_timer = stats["shield_duration"] + ECHO_DELAY
		echo_left = stats["shield_echo"]
	_shield_effects()


## Efeitos das cartas de Escudo ao levantar. Também na levantada automática do Eco, que desde
## 2026-10-14 repete os efeitos (pedido do usuário: a build de escudo estava fraca; antes era
## só o bloqueio), Teleporte e Investida inclusive (pedido dele: mais movimento na build).
func _shield_effects() -> void:
	bash_hits.clear()
	# Desde 2026-10-07 os efeitos não têm recarga própria: o custo de cada carta está na
	# recarga do E, e a levantada extra do Escudo Duplo repete todos (pedido do usuário).
	# O colete da Couraça é o mesmo do item do mapa: um só, até ARMOR_MAX.
	if stats["shield_armor"] > 0.0:
		armor = minf(ARMOR_MAX, armor + stats["shield_armor"])
	if stats["shield_haste"] > 0.0:
		haste_timer = SHIELD_HASTE_TIME
	if stats["shield_reload"] > 0:
		ammo = stats["mag_size"]
		reload_timer = 0.0
	if stats["shield_heal"] > 0.0:
		heal(stats["shield_heal"])
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
				enemy.remote_call("receive_shockwave", [global_position, 8.0 * stats["shield_shockwave"], String(name)])
	if stats["shield_detonate"] > 0:
		for enemy in enemies():
			if chest().distance_to(enemy.chest()) < DETONATE_RANGE:
				enemy.remote_call("receive_detonation", [String(name)])
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
	if stats["shield_teleport"] > 0:
		_teleport_forward()
	var mask := _shield_area_mask()
	if mask != 0:
		AreaField.shield(self, mask, global_position)
		if Net.online:
			_net_shield_area.rpc(mask, global_position)


## Quais áreas do escudo saem: uma por carta de área que o jogador tem.
func _shield_area_mask() -> int:
	var mask := 0
	for pair in [[AreaField.SHIELD_SAW, "shield_saw"], [AreaField.SHIELD_FLAMES, "shield_flames"],
			[AreaField.SHIELD_FROST, "shield_frost"], [AreaField.SHIELD_MINE, "shield_mine"]]:
		if stats[pair[1]] > 0:
			mask |= pair[0]
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
	var center := Vector3.ZERO
	if realm > 0:
		# No Domínio do Rei, o muro de fora é o da sala.
		center = KingRealm.center_of(realm - 1)
		limit = KingRealm.HALF - RADIUS - 0.2
	var room := PhysicsShapeQueryParameters3D.new()
	room.shape = capsule
	room.collision_mask = 1
	room.exclude = [get_rid()]
	for dist in tries:
		var dest: Vector3 = global_position + aim * dist
		dest.y = maxf(dest.y, 0.05)   # olhando para baixo, para no chão
		if absf(dest.x - center.x) > limit or absf(dest.z - center.z) > limit:
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
	if not alive or not is_instance_valid(other) or not other.alive or other.realm != realm:
		return   # um dos dois foi para o Domínio do Rei no meio da espera
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
	return get_tree().get_nodes_in_group("players").filter(func(p): return p.alive and is_enemy(p) and p.realm == realm)


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
	if stats["reflect_refund"] > 0 and not adrenaline_used:
		# Corta metade do que falta depois de o escudo atual baixar, uma vez por levantada
		# (2026-10-07; antes zerava a recarga a cada reflexo e virava escudo eterno).
		adrenaline_used = true
		var rest := maxf(0.0, shield_cd - shield_timer)
		shield_cd = minf(shield_cd, shield_timer + maxf(ADRENALINE_GAP, rest * (1.0 - ADRENALINE_CUT)))


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
	if ice_timer > 0.0:
		return ICE_HIT_RADIUS * s
	return RADIUS * s


## Metabolismo aumenta toda cura que passa por aqui (itens, Restauração, Sanguessuga,
## Regeneração, Banquete).
func heal(amount: float) -> void:
	if acid_timer > 0.0:
		amount *= 1.0 - ACID_HEAL   # Ácido de quem está te machucando
	health = minf(stats["max_health"], health + amount * (1.0 + float(stats["heal_mult"])))


## Tenacidade: duração dos efeitos de controle em você (lentidão, tontura, cegueira, veneno,
## queimadura).
func _control_time(time: float) -> float:
	return time * (1.0 - float(stats["tenacity"]))


func apply_slow(amount: float, time := SLOW_TIME, from: Player = null) -> void:
	aff_from["slow"] = from
	slow_amount = clampf(maxf(slow_amount if slow_timer > 0.0 else 0.0, amount), 0.0, 0.7)
	slow_timer = maxf(slow_timer, _control_time(time))


## Queimadura (Chamas, Bala Incendiária): não empilha; renova o tempo e vale a mais forte
## (quem pôs a mais forte leva o crédito). Aflição: a Tenacidade encurta, o Blindado não
## reduz; a Persistência de quem pôs alonga. hit: acerto de bala (Brasa esquenta).
func apply_burn(dps: float, time: float, from: Player, hit := false) -> void:
	if is_instance_valid(from):
		# Combustão Lenta soma antes da Persistência; teto BURN_MAX_TIME.
		time = minf(BURN_MAX_TIME, (time + SLOW_BURN_TIME * float(from.stats["slow_burn"]))
			* (1.0 + float(from.stats["dot_time"])))
	if burn_timer > 0.0 and from == burn_from:
		# O mesmo dono: fica a mais forte das duas e a Brasa esquenta no acerto de bala.
		burn_dps = maxf(burn_dps, dps)
		if hit and from.stats["ember"] > 0:
			burn_heat = minf(BRASA_MAX, burn_heat + BRASA_STEP)
	elif burn_timer <= 0.0 or dps >= burn_dps * (1.0 + burn_heat):
		burn_dps = dps
		burn_from = from
		burn_heat = 0.0
	burn_timer = maxf(burn_timer, _control_time(time))
	if is_instance_valid(from) and from.stats["acid"] > 0:
		acid_timer = maxf(acid_timer, burn_timer)


## Combustão Lenta: quanto sobra do dano por segundo da Queimadura que este jogador põe.
func burn_dps_mult() -> float:
	return pow(SLOW_BURN_DPS, float(stats["slow_burn"]))


## Combustível de quem pôs o fogo: a queimadura tira FUEL_BONUS a mais se você tem outra
## aflição (veneno, lentidão, cegueira, escudo bloqueado, tontura).
func _fuel_mult() -> float:
	if not is_instance_valid(burn_from) or burn_from.stats["fuel"] <= 0:
		return 1.0
	if poisons.is_empty() and slow_timer <= 0.0 and blind_timer <= 0.0 and silence_timer <= 0.0 and daze_timer <= 0.0 \
			and frost_layers <= 0 and frost_freeze <= 0.0:
		return 1.0
	return 1.0 + FUEL_BONUS


## Veneno: o mesmo dano por segundo; com Tenacidade dura menos (e tira menos no total), com
## Persistência de quem atirou dura mais (e tira mais).
func apply_poison(total: float, from: Player) -> void:
	var valid := is_instance_valid(from)
	var time := _control_time(POISON_TIME * (1.0 + (float(from.stats["dot_time"]) if valid else 0.0)))
	poisons.append({"dps": total / POISON_TIME, "time": time, "from": from if valid else null, "acc": 0.0, "copy": false})
	if valid and from.stats["acid"] > 0:
		acid_timer = maxf(acid_timer, time)


## Estouro de from_name (máquina dona deste jogador): o veneno e a queimadura dele aqui
## saem de uma vez, multiplicados e com teto, e acabam.
func receive_detonation(from_name: String) -> void:
	var from := get_parent().get_node_or_null(from_name) as Player
	if not alive or from == null:
		return
	var poison := 0.0
	for p in poisons:
		if p["from"] == from:
			poison += p["acc"] + p["dps"] * maxf(0.0, p["time"])
	var burn := 0.0
	if burn_timer > 0.0 and burn_from == from:
		burn = burn_acc + burn_dps * (1.0 + burn_heat) * burn_timer * _fuel_mult()
		burn_timer = 0.0
		burn_acc = 0.0
		burn_from = null
		burn_heat = 0.0
	var frost := 0.0
	if frost_layers > 0 and frost_from == from:
		frost = DETONATE_FROST * frost_layers   # camadas: dano fixo, fora do multiplicador
		frost_layers = 0
	if poison + burn + frost <= 0.0:
		return
	if poison > 0.0:
		poisons = poisons.filter(func(p): return p["from"] != from)
	var mult := DETONATE_BOTH if poison > 0.0 and burn > 0.0 else DETONATE_MULT
	var kind := (1 if poison > 0.0 else 0) | (2 if burn > 0.0 else 0) | (4 if frost > 0.0 else 0)
	_show_detonation(kind)
	if Net.online:
		_net_detonation.rpc(kind)
	take_damage(minf(DETONATE_CAP, (poison + burn) * mult + frost), from, true)


@rpc("authority", "call_remote", "reliable")
func _net_detonation(kind: int) -> void:
	_show_detonation(kind)


## Estouro em cima de quem foi detonado: verde (veneno), laranja (queimadura) ou os dois.
func _show_detonation(kind: int) -> void:
	if kind & 1:
		Effects.explosion(get_parent(), chest(), 1.6, CONTAGION_COLOR, 0.3)
	if kind & 2:
		Effects.explosion(get_parent(), chest(), 1.3 if kind & 1 else 1.6, BURN_COLOR, 0.3)
	if kind & 4:
		Effects.explosion(get_parent(), chest(), 1.0 if kind & 3 else 1.6, FROST_COLOR, 0.3)


## Reação em Cadeia: uma aflição terminou aqui (máquina dona). power: a força dela, para
## repassar (veneno e queimadura: dano por segundo; lentidão: quanto; cegueira: tempo).
func _chain_end(kind: String, power: float, from) -> void:
	if alive and is_instance_valid(from) and from != self and from.stats["chain_blast"] > 0 \
			and not is_ally(from):
		_chain_ended.append({"kind": kind, "power": power, "from": from})


## As aflições que terminaram neste passo viram uma explosão só (do dono da primeira).
func _chain_step() -> void:
	var ended := _chain_ended
	_chain_ended = []
	var from = ended[0]["from"]
	if chain_guard > 0.0 or not alive or not is_instance_valid(from):
		return
	chain_guard = CHAIN_GUARD
	var kinds := []
	var effects := []
	for e in ended:
		if e["from"] == from and not e["kind"] in kinds:
			kinds.append(e["kind"])
			effects.append([e["kind"], e["power"]])
	var n := clampi(int(from.stats["chain_blast"]), 1, CHAIN_DAMAGE.size()) - 1
	var dmg: float = CHAIN_DAMAGE[n]
	var r: float = CHAIN_RANGE[n]
	_show_chain(kinds, r)
	if Net.online:
		_net_chain.rpc(kinds, r)
	for q: Player in get_tree().get_nodes_in_group("players"):
		if q == self or q == from or not q.alive or q.is_ally(from) \
				or q.global_position.distance_squared_to(global_position) > r * r:
			continue
		q.remote_call("receive_chain", [String(from.name), dmg, effects])
	take_area_damage(dmg, from)


## Pegou a explosão da Reação em Cadeia de from_name (máquina dona): o dano e as aflições
## que tinham terminado em quem explodiu, com a força que tinham lá.
func receive_chain(from_name: String, dmg: float, effects: Array) -> void:
	var from := get_parent().get_node_or_null(from_name) as Player
	if not alive or from == null:
		return
	take_area_damage(dmg, from)
	if not alive:
		return
	for e in effects:
		var power: float = e[1]
		match e[0]:
			"poison":
				apply_poison(power * POISON_TIME, from)
			"burn":
				apply_burn(power, BURN_HIT_TIME, from)
			"slow":
				apply_slow(power, SLOW_TIME, from)
			"blind":
				apply_blind(power, from)
			"silence":
				silence(from)
			"daze":
				_daze(DAZE_TIME, from)
			"frost":
				add_frost(int(power), from)


@rpc("authority", "call_remote", "reliable")
func _net_chain(kinds: Array, r: float) -> void:
	_show_chain(kinds, r)


## Explosão em cima de quem explodiu, uma camada por aflição, cada uma da sua cor.
func _show_chain(kinds: Array, r: float) -> void:
	var size := r
	for k in kinds:
		Effects.explosion(get_parent(), chest(), size, CHAIN_COLORS.get(k, Color.WHITE), 0.35)
		size *= 0.7
	Sfx.at(get_parent(), "explosion", chest())


## Contágio: cópia do veneno de from_name chegando de quem estava envenenado perto (máquina
## dona). Não pega se já tem veneno dele ou se pegou uma cópia há menos de CONTAGION_GUARD s.
func receive_contagion(dps: float, time: float, from_name: String) -> void:
	var from := get_parent().get_node_or_null(from_name) as Player
	if not alive or from == null or contagion_guard > 0.0:
		return
	for p in poisons:
		if p["from"] == from:
			return
	_add_poison_copy(dps, _control_time(time), from)


func _add_poison_copy(dps: float, time: float, from: Player) -> void:
	contagion_guard = CONTAGION_GUARD
	poisons.append({"dps": dps, "time": time, "from": from, "acc": 0.0, "copy": true})
	if from.stats["acid"] > 0:
		acid_timer = maxf(acid_timer, time)


## Contágio, a cada pedaço de veneno (máquina dona do envenenado): o veneno original de quem
## tem a carta manda uma cópia para os inimigos dele por perto; sem ninguém, volta para cá.
func _contagion_step() -> void:
	var now := Time.get_ticks_msec()
	for p in poisons:
		var from = p["from"]
		if p["copy"] or p["time"] <= 0.0 or not is_instance_valid(from) or from.stats["contagion"] <= 0:
			continue
		var dps: float = p["dps"] * CONTAGION_SHARE
		var near := false
		for q: Player in get_tree().get_nodes_in_group("players"):
			if q == self or q == from or not q.alive or q.is_ally(from) \
					or q.global_position.distance_squared_to(global_position) > CONTAGION_RANGE * CONTAGION_RANGE:
				continue
			near = true
			if now < int(_contagion_sent.get(q.name, 0)):
				continue
			_contagion_sent[q.name] = now + int(CONTAGION_GUARD * 1000.0)
			q.remote_call("receive_contagion", [dps, p["time"], String(from.name)])
			_contagion_fx(String(q.name))
		if not near and contagion_guard <= 0.0:
			_add_poison_copy(dps, p["time"], from)
			_contagion_fx(String(name))


## Fio verde de quem estava envenenado até quem pegou a cópia (ou um estouro, se voltou para
## ele mesmo), em todas as máquinas.
func _contagion_fx(target_name: String) -> void:
	_show_contagion(target_name)
	if Net.online:
		_net_contagion.rpc(target_name)


@rpc("authority", "call_remote", "reliable")
func _net_contagion(target_name: String) -> void:
	_show_contagion(target_name)


func _show_contagion(target_name: String) -> void:
	var q := get_parent().get_node_or_null(target_name) as Player
	if q == null or q == self:
		Effects.burst(get_parent(), chest(), 0.9, CONTAGION_COLOR, 0.25)
	else:
		Effects.beam(get_parent(), chest(), q.chest(), CONTAGION_COLOR, 0.05, 0.35)


## Junta o veneno de POISON_TICK em POISON_TICK s e tira de uma vez por atacante, como tick
## (crédito, Sanguessuga e Marca; o instante que já acabou entrega o resto no próximo pedaço).
func _poison_step(delta: float) -> void:
	for p in poisons:
		p["acc"] += p["dps"] * clampf(p["time"], 0.0, delta)
		p["time"] -= delta
	poison_tick -= delta
	if poison_tick > 0.0:
		return
	poison_tick = POISON_TICK
	_contagion_step()
	var sums := {}
	for p in poisons:
		var who: Player = p["from"] if is_instance_valid(p["from"]) else null
		sums[who] = float(sums.get(who, 0.0)) + p["acc"]
		p["acc"] = 0.0
	var last: Dictionary = poisons.back()
	poisons = poisons.filter(func(p): return p["time"] > 0.0)
	if poisons.is_empty():
		_chain_end("poison", last["dps"], last["from"])   # o último veneno acabou
	for who in sums:
		take_damage(sums[who], who, true, false, true, true)


## Marca: o dano de quem marcou leva MARK_BONUS a mais; qualquer dano dele marca de novo
## depois de MARK_WAIT. Decide a máquina do marcado e avisa a de quem marcou (contorno).
func _mark_hit(amount: float, from: Player) -> float:
	var now := Time.get_ticks_msec()
	var m: Array = marks.get(from, [0, 0])
	if now < int(m[0]):
		amount *= 1.0 + MARK_BONUS
	if now >= int(m[1]):
		marks[from] = [now + int(MARK_TIME * 1000.0), now + int(MARK_WAIT * 1000.0)]
		from.remote_call("mark_seen", [String(name)])
	return amount


## Marca, na máquina de quem marcou: o contorno de target_name aparece por MARK_TIME s.
func mark_seen(target_name: String) -> void:
	marked[target_name] = Time.get_ticks_msec() + int(MARK_TIME * 1000.0)


func is_marking(p: Player) -> bool:
	return not marked.is_empty() and Time.get_ticks_msec() < int(marked.get(String(p.name), 0))


## Flash: a tela de quem levou o tiro fica branca (o bot erra mais a mira).
func apply_blind(time: float, from: Player = null) -> void:
	if blind_guard > 0.0:
		return   # cego agora ou protegido logo depois: não renova (senão, com muitas balas, ficava cego direto)
	aff_from["blind"] = from
	blind_time = time
	time = _control_time(time)
	blind_timer = time
	blind_guard = time + BLIND_GUARD
	blind_guard_total = blind_guard


func silence(from: Player = null) -> void:
	if silence_guard > 0.0:
		return   # atordoado agora ou protegido logo depois: não renova
	aff_from["silence"] = from
	silence_timer = SILENCE_TIME
	silence_guard = SILENCE_TIME + SILENCE_GUARD
	shield_timer = 0.0


## Dano de explosão ou de área (Blindado tira uma parte). Só na máquina dona.
func take_area_damage(amount: float, from: Player, tick := false) -> void:
	take_damage(amount * (1.0 - float(stats["blast_resist"])), from, true, false, tick)


## Só é chamado na máquina dona deste jogador.
## ignore_armor: o Perfurante bate direto na vida. tick: dano contínuo (veneno, queimadura,
## serra, alto demais), que o Couro Grosso não conta e a Caçada ignora. affliction: tick de
## aflição (veneno, queimadura), o único que o Ácido e a Corrosão contam.
func take_damage(amount: float, from: Player, flash := true, ignore_armor := false, tick := false, affliction := false) -> void:
	if not alive or amount <= 0.0 or protect_timer > 0.0 or spawn_protect > 0.0:
		return
	if ice_timer > 0.0:
		_ice_store(amount, from)   # Prisão de Gelo: não tira vida agora; uma parte sai no degelo
		return
	if from and from != self and not is_ally(from):
		if frost_freeze > 0.0 and not tick:
			amount = _frost_break(amount, from)
		if from.stats["mark"] > 0:
			amount = _mark_hit(amount, from)
		if affliction:
			if from.stats["dot_pierce"] > 0:
				ignore_armor = true   # Corrosão
			if from.stats["acid"] > 0:
				acid_timer = maxf(acid_timer, ACID_WINDOW)
	if stats["thick_skin"] > 0 and flash and not tick:
		# Couro Grosso: este golpe perde o que acumulou (mínimo 1) e soma 1 para o próximo.
		if skin_stacks > 0:
			amount = maxf(minf(amount, 1.0), amount - skin_stacks)
		skin_stacks = mini(skin_stacks + 1, SKIN_STACK_MAX[mini(int(stats["thick_skin"]), SKIN_STACK_MAX.size() - 1)])
		skin_stack_timer = 0.0
	if from and from != self and not is_ally(from):   # tiro do parceiro (escudo humano) não conta
		last_attacker = from
		recent_hits[from] = Time.get_ticks_msec()
	skin_timer = 0.0
	if stats["tough"] > 0:
		var hit := amount
		if tough_timer > 0.0:
			amount *= 1.0 - TOUGH_REDUCE
		if hit >= TOUGH_TRIGGER:
			tough_timer = TOUGH_TIME
	if hook_state >= 2 and hook_target:
		hook_taken += amount
		if hook_taken >= HOOK_ESCAPE:
			_hook_let_go()
	var hit_total := amount
	var mech_broke := false
	if mech_state == 2 and not ignore_armor and is_local:
		# Mecha: a blindagem leva antes de tudo (a Perfurante, que ignora o colete, passa direto).
		amount = _mech_absorb(amount)
		mech_broke = mech_armor <= 0.0
	var absorbed := 0.0 if ignore_armor else minf(armor, amount)
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
	if immortal:
		health = maxf(health, 1.0)
	since_damage = 0.0
	reveal()
	if flash:
		shake = maxf(shake, clampf(amount / 40.0, 0.15, 0.6))
		flash_hit()
		damaged.emit(hit_total, from)
		if is_human:
			Sfx.ui(self, "hurt")
		if from and from != self:
			from.remote_call("credit_damage", [hit_total, health <= 0.0 and revives_left == 0, tick])
	if mech_broke:
		_mech_end()   # blindagem zerada: sai e explode com o máximo
	if health <= 0.0:
		_lethal()


## Vida zerada: a Fênix segura, senão morre.
func _lethal() -> void:
	last_stand_timer = 0.0
	if immortal:
		# Sala de teste: o Último Suspiro que acaba sem abate não mata (não há próxima rodada
		# para renascer) e fica pronto para testar de novo.
		health = maxf(health, 1.0)
		last_stand_used = false
		return
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
	var t := Prof.now()
	_apply_death_now(killer, assists)
	Prof.lap("morte do jogador", t, true)


func _apply_death_now(killer: String, assists: Array) -> void:
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
	_mech_clear()
	_clone_clear()
	frost_layers = 0
	frost_freeze = 0.0
	thermal_from = null
	if frost_mark:
		frost_mark.visible = false
	if _frost_shown:
		_frost_shown = false
		if ice_timer <= 0.0:
			_ice_visual(false)
	died.emit(self)


# ---------------------------------------------------------------- caído (2x2)

func _can_go_down() -> bool:
	if not downs_enabled or team < 0 or frozen or realm > 0:
		return false   # no Domínio do Rei o golpe fatal mata: vencer é o objetivo da sala
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
	_mech_clear()
	_clone_clear()
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
