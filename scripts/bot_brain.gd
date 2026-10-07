class_name BotBrain
extends Node
## IA simples para testar o 1x1 sozinho. Ela só preenche as variáveis in_* do
## Player, exatamente como o teclado faria. Mude as constantes para ajustar a dificuldade.
## Sem ver o inimigo, segue o caminho da malha de navegação da arena até ele.

const AIM_ERROR := 0.5       # erro de mira, em metros
const TURN_SPEED := 7.0      # velocidade de giro, rad/s
const LEAD := 0.7            # quanto antecipa o movimento do alvo (0 a 1)
const SHIELD_CHANCE := 0.5   # chance de levantar o escudo contra uma bala que vai acertar
const VOID_SAVE_CHANCE := 0.5  # chance de acertar o escudo ao bater no vazio
const CLICK_MIN := 0.12      # intervalo entre cliques do bot, em segundos (6 a 8 por segundo)
const CLICK_MAX := 0.17
const NEAR := 8.0
const FAR := 22.0
const REPATH_TIME := 0.5
const TARGET_TIME := 1.0
const REVIVE_SAFE := 12.0    # 2x2: vai reviver o parceiro se o inimigo visível está mais longe que isto

var player: Player
var strafe_dir := 1.0
var strafe_timer := 0.0
var aim_offset := Vector3.ZERO
var aim_timer := 0.0
var unseen_time := 0.0
var path := PackedVector3Array()
var path_index := 0
var repath_timer := 0.0
var stuck_time := 0.0
var crouch_time := 0.0
var target: Player
var target_timer := 0.0
var void_save := false
var click_cd := 0.0   # tempo até o próximo clique (a arma é semiautomática)
var judged := {}   # id da bala -> decidiu se defende ou não (decide uma vez por bala)


func think(delta: float) -> void:
	var p := player
	p.in_move = Vector2.ZERO
	p.in_jump = false
	p.in_jump_held = p.velocity.y > -0.5   # segura o pulo subindo, solta caindo
	p.in_crouch = false
	p.in_shoot = false
	p.in_shield = false
	p.in_dash = false
	p.in_reload = false
	p.in_master = false
	if p.stats["platforms"] > 0 and p.master_cd <= 0.0 and not p.is_on_floor() \
			and p.global_position.y < Arena.VOID_Y + 1.5 and p.velocity.y < 0.0:
		p.in_master = true   # Plataformas Suspensas: plataforma para não cair no vazio
	if p.downed and not p.frozen:
		_crawl_to_ally(delta)
		return
	var foe := _pick_target()
	if p.frozen or not p.alive or foe == null:
		return
	var sees := _can_see(foe)
	unseen_time = 0.0 if sees else unseen_time + delta
	var hurt := _downed_ally()
	if hurt and (not sees or p.global_position.distance_to(foe.global_position) > REVIVE_SAFE):
		# Parceiro caído e nenhum inimigo perto: vai até ele e fica ali (atirando, se vir alguém).
		var go := Vector3.ZERO
		if p.global_position.distance_to(hurt.global_position) > Player.REVIVE_RADIUS * 0.5:
			go = _follow_path(delta, hurt.global_position)
		_set_move(go)
		_aim_and_shoot(delta, foe, sees, go)
		_defend()
		return
	if p.sword_timer > 0.0:
		_sword_fight(delta, foe, sees)
		return
	var wish := _movement(delta, foe, sees)
	_aim_and_shoot(delta, foe, sees, wish)
	_defend()
	_master(foe, sees)


## 2x2: o parceiro caído (ou null).
func _downed_ally() -> Player:
	for node in player.get_tree().get_nodes_in_group("players"):
		var other := node as Player
		if other.downed and player.is_ally(other):
			return other
	return null


## Caído: se arrasta na direção do parceiro de pé, para encurtar o caminho dele.
func _crawl_to_ally(delta: float) -> void:
	for node in player.get_tree().get_nodes_in_group("players"):
		var other := node as Player
		if other.alive and player.is_ally(other):
			if player.global_position.distance_to(other.global_position) > 1.5:
				_set_move(_follow_path(delta, other.global_position))
			return


## Converte uma direção no mundo para in_move (relativo para onde o corpo olha).
func _set_move(wish: Vector3) -> void:
	var local := player.global_transform.basis.inverse() * wish
	player.in_move = Vector2(local.x, -local.z).limit_length(1.0)


## Com a Espada: corre até o alvo e golpeia quando ele está no alcance e na frente.
func _sword_fight(delta: float, foe: Player, sees: bool) -> void:
	var p := player
	var dist := p.global_position.distance_to(foe.global_position)
	var wish := Vector3.ZERO
	if dist > Player.SWORD_RANGE * 0.7:
		wish = _follow_path(delta, foe.global_position) if not sees else \
			Vector3(foe.global_position.x - p.global_position.x, 0.0, foe.global_position.z - p.global_position.z).normalized()
	_set_move(wish)
	p.look_at_point(foe.chest(), TURN_SPEED * delta)
	click_cd -= delta
	if dist < Player.SWORD_RANGE and click_cd <= 0.0:
		p.in_shoot = true
		click_cd = randf_range(CLICK_MIN, CLICK_MAX)
	_defend()


## Carta mestra: Corrente de vez em quando na luta, Bazuca e Perfurante com o alvo à vista.
## (O Bastião sobe em _defend, contra uma bala que vem quando o escudo não está pronto.)
func _master(foe: Player, sees: bool) -> void:
	var p := player
	if p.ride_timer > 0.0:
		# Foguete: salta perto do alvo (o foguete solto segue até ele).
		if p.global_position.distance_to(foe.global_position) < 9.0 and p.ride_age > 0.3:
			p.in_master = true
		return
	if not sees or p.master_cd > 0.0 or p.global_position.distance_to(foe.global_position) > FAR:
		return
	if p.stats["updraft"] > 0 and randf() < 0.01:
		p.in_master = true
	elif p.stats["bazooka"] > 0:
		p.in_master = true
	elif p.stats["sniper"] > 0 and p.global_position.distance_to(foe.global_position) > NEAR:
		p.in_master = true
	elif p.stats["pierce"] > 0 and p.pierce_left == 0:
		p.in_master = true
	elif p.stats["ice"] > 0 and foe.ice_timer <= 0.0 \
			and p.global_position.distance_to(foe.global_position) < Player.ICE_RANGE * 0.6:
		p.in_master = true   # Prisão de Gelo: com o alvo à vista a menos de ~25 m
	elif p.stats["beam"] > 0 and p.global_position.distance_to(foe.global_position) > 8.0 \
			and p.global_position.distance_to(foe.global_position) < 30.0:
		p.in_master = true   # Canhão Arcano: alvo à vista entre 8 e 30 m
	elif p.stats["rocket_ride"] > 0 and p.global_position.distance_to(foe.global_position) > 12.0:
		p.in_master = true   # Foguete: monta e vai na direção do alvo
	elif p.stats["meteor"] > 0 and p.meteor_left == 0 and p.global_position.distance_to(foe.global_position) > 6.0:
		p.in_master = true   # Chuva de Meteoros: os próximos tiros marcam
	elif p.stats["slap"] > 0 and p.global_position.distance_to(foe.global_position) < Player.SLAP_RANGE + 0.5:
		p.in_master = true   # Mega Tapa: tira quem chegou perto
	elif p.stats["sword"] > 0 and p.global_position.distance_to(foe.global_position) < NEAR:
		p.in_master = true
	elif p.stats["shrink"] > 0 and p.shrink_timer <= 0.0 \
			and (p.health < p.stats["max_health"] * 0.4 or randf() < 0.01):
		p.in_master = true   # Formiga: para fugir com pouca vida ou, de vez em quando, para chegar perto


## Devolve a direção de movimento no mundo e já preenche in_move, pulo e deslize.
## Alvo: o inimigo visível mais perto; se nenhum está à vista, o mais perto de todos.
## Troca de alvo no máximo a cada TARGET_TIME para não ficar indeciso.
func _pick_target() -> Player:
	var p := player
	if target and target.alive and target_timer > 0.0:
		target_timer -= get_physics_process_delta_time()
		return target
	target_timer = TARGET_TIME
	var best: Player = null
	var best_score := INF
	for enemy in p.enemies():
		var d := p.global_position.distance_to(enemy.global_position)
		var score := d if _can_see(enemy) else d + 1000.0
		if score < best_score:
			best_score = score
			best = enemy
	target = best
	return target


func _movement(delta: float, foe: Player, sees: bool) -> Vector3:
	var p := player
	var dist := p.global_position.distance_to(foe.global_position)
	var wish := Vector3.ZERO
	if sees and dist < FAR:
		strafe_timer -= delta
		if strafe_timer <= 0.0:
			strafe_timer = randf_range(0.4, 1.4)
			if randf() < 0.6:
				strafe_dir = -strafe_dir
			p.in_jump = randf() < 0.2
			p.in_dash = randf() < 0.25
		var to := foe.global_position - p.global_position
		to.y = 0.0
		to = to.normalized()
		var forward := 0.0
		if dist > NEAR * 1.6:
			forward = 0.6
		elif dist < NEAR:
			forward = -1.0
		wish = (to.cross(Vector3.UP) * strafe_dir + to * forward).normalized()
	else:
		wish = _follow_path(delta, foe.global_position)
		# Correndo pelo caminho, às vezes desliza.
		if p.is_on_floor() and Vector2(p.velocity.x, p.velocity.z).length() > 7.0 and randf() < 0.01:
			crouch_time = 0.5
	crouch_time -= delta
	p.in_crouch = crouch_time > 0.0

	# Preso numa quina ou numa peça móvel: pula.
	var hspeed := Vector2(p.velocity.x, p.velocity.z).length()
	stuck_time = stuck_time + delta if wish != Vector3.ZERO and hspeed < 1.5 else 0.0
	if stuck_time > 0.35:
		p.in_jump = true
		stuck_time = 0.0

	var local := p.global_transform.basis.inverse() * wish
	p.in_move = Vector2(local.x, -local.z).limit_length(1.0)
	return wish


func _follow_path(delta: float, target: Vector3) -> Vector3:
	var p := player
	repath_timer -= delta
	if repath_timer <= 0.0:
		repath_timer = REPATH_TIME
		var map := p.get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			path = NavigationServer3D.map_get_path(map, p.global_position, target, true)
			path_index = 0
	while path_index < path.size():
		var flat := path[path_index] - p.global_position
		flat.y = 0.0
		if flat.length() > 1.0:
			return flat.normalized()
		path_index += 1
	var direct := target - p.global_position
	direct.y = 0.0
	return direct.normalized()


func _aim_and_shoot(delta: float, foe: Player, sees: bool, wish: Vector3) -> void:
	var p := player
	var eye := p.head.global_position
	if not sees:
		# Sem ver o inimigo, olha para onde está indo.
		if wish != Vector3.ZERO:
			p.look_at_point(eye + wish * 5.0, TURN_SPEED * delta)
		if p.ammo < p.stats["mag_size"]:
			p.in_reload = true
		return
	aim_timer -= delta
	if aim_timer <= 0.0:
		aim_timer = 0.4
		var error := AIM_ERROR * (6.0 if p.blind_timer > 0.0 else 1.0)
		aim_offset = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * error
	var rocket := p.bazooka_timer > 0.0
	var sniping := p.sniper_timer > 0.0
	var straight: bool = rocket or sniping or p.pierce_left > 0 or p.stats["guided"] > 0
	var speed: float = Player.ROCKET_SPEED if rocket else (Player.SNIPER_SPEED if sniping else p.stats["bullet_speed"])
	if not rocket and p.pierce_left > 0:
		speed *= Player.PIERCE_SPEED
	var travel := eye.distance_to(foe.global_position) / speed
	var target := foe.chest() + foe.velocity * travel * LEAD + aim_offset
	# Compensa a queda da bala mirando acima (foguete, perfurante e bala guiada vão retos).
	if not straight:
		target.y += 0.5 * float(p.stats["bullet_gravity"]) * travel * travel
	p.look_at_point(target, TURN_SPEED * delta)
	var forward := -p.head.global_transform.basis.z
	click_cd -= delta
	if forward.angle_to(target - eye) < 0.06:
		# Semiautomática: o bot clica num ritmo de gente (6 a 8 por segundo); segurar só
		# repete o tiro com a Metralhadora. think() solta o botão a cada quadro.
		if p.stats["auto_fire"] > 0:
			p.in_shoot = true
		elif click_cd <= 0.0:
			p.in_shoot = true
			click_cd = randf_range(CLICK_MIN, CLICK_MAX)


func _can_see(foe: Player) -> bool:
	if foe.is_hidden():
		return false
	# O parceiro no meio do caminho não tapa a visão (a bala o atravessa).
	var skip: Array[RID] = [player.get_rid()]
	for p in get_tree().get_nodes_in_group("players"):
		if player.is_ally(p):
			skip.append(p.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		player.head.global_position, foe.chest(), 1 | 2, skip)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == foe


func _defend() -> void:
	# Caindo no vazio: levanta o escudo pouco antes de bater (às vezes erra o tempo).
	var p := player
	if p.global_position.y > Arena.VOID_Y + 3.0:
		void_save = randf() < VOID_SAVE_CHANCE   # sorteia uma vez por queda
	elif void_save and p.velocity.y < 0.0 and p.global_position.y + p.velocity.y * 0.15 < Arena.VOID_Y:
		p.in_shield = true
	var center := player.chest()
	for node in get_tree().get_nodes_in_group("bullets"):
		var b := node as Bullet
		if b.shooter == player or player.is_ally(b.shooter):
			continue
		var speed := b.velocity.length()
		if speed < 0.01:
			continue
		var dir := b.velocity / speed
		var rel := center - b.global_position
		var along := rel.dot(dir)
		if along <= 0.0 or (rel - dir * along).length() > 1.4:
			continue   # já passou ou vai errar
		if along / speed > float(player.stats["shield_duration"]) * 0.8:
			continue   # ainda longe demais para levantar o escudo
		var id := b.get_instance_id()
		if not judged.has(id):
			judged[id] = randf() < SHIELD_CHANCE
		if judged[id]:
			player.in_shield = true
			if player.shield_cd > 0.0 and player.stats["barrier"] > 0:
				player.in_master = true
	if judged.size() > 256:
		judged.clear()
