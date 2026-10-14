class_name DamageFeedback
extends Control
## Aviso de dano (2026-10-05, o vermelho na tela inteira não dizia de onde vinha o tiro).
## Do jeito de CoD, Valorant e Apex, sem exagero:
## - arco vermelho em volta da mira apontando para quem acertou; acompanha quando você
##   gira e some em ARC_TIME segundos; mais grosso com mais dano;
## - bordas da tela avermelhadas por um instante, mais fortes com mais dano;
## - vida baixa (abaixo de LOW_HEALTH): as bordas pulsam de leve até curar.
## Dano sem origem (vazio) só avermelha as bordas.
## Sanguessuga (2026-10-14, pedido do usuário): curar acende as bordas em verde (Player.heal_glow),
## na mesma camada, quando o verde é mais forte que o vermelho.
## Veneno e Queimadura (2026-10-14, pedido do usuário, como no The Bazaar): envenenado, a tela
## fica esverdeada; queimando, fogo tremulando nas bordas, avermelhando. Os dois crescem com o
## dano por segundo. Mesma camada (um passe só), ligada só enquanto há algo a mostrar.

const ARC_TIME := 1.2
const ARC_FADE := 0.5
const ARC_RADIUS := 120.0
const ARC_SPAN := 0.55          # radianos
const MAX_ARCS := 4
const LOW_HEALTH := 0.3         # fração da vida máxima
const HURT_TINT := Vector3(0.8, 0.04, 0.04)
const HEAL_TINT := Vector3(0.15, 0.9, 0.3)
const HEAL_STRENGTH := 0.45     # bordas verdes no começo do brilho
## Força do verde e do fogo: piso (assim que pega) + dano por segundo / escala, até 1.
const POISON_FLOOR := 0.25
const POISON_SCALE := 10.0      # 10 de veneno por segundo = cheio
const BURN_FLOOR := 0.25
const BURN_SCALE := 40.0        # ~30 de queimadura por segundo = cheio
const AFFLICTION_FADE := 3.0    # por segundo, subindo e descendo
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform float aspect = 1.78;
uniform vec3 tint = vec3(0.8, 0.04, 0.04);
uniform float poison = 0.0;
uniform float burn = 0.0;
vec4 over(vec4 top, vec4 base) {
	float a = top.a + base.a * (1.0 - top.a);
	return vec4((top.rgb * top.a + base.rgb * base.a * (1.0 - top.a)) / max(a, 0.0001), a);
}
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p) / length(vec2(aspect, 1.0) * 0.5);
	vec4 col = vec4(0.0);
	if (poison > 0.0) {
		float e = smoothstep(0.75 - 0.35 * poison, 1.1, d);
		col = over(vec4(0.25, 0.85, 0.15, poison * (0.06 + 0.5 * e)), col);
	}
	if (burn > 0.0) {
		float ang = atan(p.y, p.x);
		float flick = sin(ang * 11.0 + TIME * 7.0) * sin(ang * 5.0 - TIME * 4.3);
		float e = smoothstep(0.8 - 0.35 * burn + 0.07 * flick, 1.05, d);
		col = over(vec4(mix(vec3(1.0, 0.6, 0.15), vec3(0.85, 0.1, 0.03), e), burn * (0.05 + 0.6 * e)), col);
	}
	col = over(vec4(tint, smoothstep(0.55, 1.05, d) * intensity), col);
	COLOR = col;
}
"""

var me: Player
var arcs: Array = []      # {"pos": Vector3, "from": Player, "time": float, "size": float}
var pulse := 0.0          # vermelho nas bordas pelo último dano (cai sozinho)
var poison_level := 0.0   # verde na tela (Veneno), suavizado
var burn_level := 0.0     # fogo nas bordas (Queimadura), suavizado
var vignette: ColorRect
var _mat: ShaderMaterial
## Corrente sombria do Domínio do Rei vindo em você: onde está a ponta (INF = nada). Arco
## roxo pulsando do lado de onde ela vem, enquanto voa (a HUD põe a cada quadro).
var threat := Vector3.INF
var _threat_drawn := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	vignette.material = _mat
	add_child(vignette)


func hit(amount: float, from: Player) -> void:
	if me == null:
		return
	var share := amount / maxf(1.0, float(me.stats["max_health"]))
	pulse = maxf(pulse, clampf(0.3 + share * 1.2, 0.3, 0.7))
	if from == null or from == me or not is_instance_valid(from):
		return
	var size := clampf(share * 4.0, 0.0, 1.0)
	for a in arcs:
		if a["from"] == from:
			a["pos"] = from.global_position
			a["time"] = ARC_TIME
			a["size"] = maxf(a["size"], size)
			return
	arcs.append({"pos": from.global_position, "from": from, "time": ARC_TIME, "size": size})
	if arcs.size() > MAX_ARCS:
		arcs.pop_front()


func clear() -> void:
	arcs.clear()
	pulse = 0.0


func _process(delta: float) -> void:
	if me == null:
		return
	pulse = move_toward(pulse, 0.0, delta * 1.4)
	var low := 0.0
	if me.alive:
		var hp: float = me.health / maxf(1.0, float(me.stats["max_health"]))
		if hp < LOW_HEALTH:
			low = 0.22 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
		if me.last_stand_timer > 0.0:
			low = 0.4 + 0.15 * sin(Time.get_ticks_msec() * 0.012)
	# Só liga a vinheta quando há o que mostrar: é um shader na tela inteira, e na Intel HD
	# a 1080p cada camada de tela cheia custa alguns ms mesmo transparente.
	var intensity := maxf(pulse, low)
	var heal := me.heal_glow * HEAL_STRENGTH if me.alive else 0.0
	var green := heal > intensity
	if green:
		intensity = heal
	var poison_to := 0.0
	var burn_to := 0.0
	if me.alive:
		if not me.poisons.is_empty():
			var dps := 0.0
			for p in me.poisons:
				dps += p["dps"]
			poison_to = clampf(POISON_FLOOR + dps / POISON_SCALE, 0.0, 1.0)
		if me.burn_timer > 0.0:
			burn_to = clampf(BURN_FLOOR + me.burn_dps * (1.0 + me.burn_heat) / BURN_SCALE, 0.0, 1.0)
	poison_level = move_toward(poison_level, poison_to, delta * AFFLICTION_FADE)
	burn_level = move_toward(burn_level, burn_to, delta * AFFLICTION_FADE)
	vignette.visible = intensity > 0.005 or poison_level > 0.005 or burn_level > 0.005
	if vignette.visible:
		_mat.set_shader_parameter("tint", HEAL_TINT if green else HURT_TINT)
		_mat.set_shader_parameter("intensity", intensity)
		_mat.set_shader_parameter("poison", poison_level)
		_mat.set_shader_parameter("burn", burn_level)
		_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	var threat_on := threat != Vector3.INF and me.alive
	if threat_on or _threat_drawn:
		_threat_drawn = threat_on
		queue_redraw()
	if arcs.is_empty():
		return
	for a in arcs:
		a["time"] -= delta
	arcs = arcs.filter(func(a): return a["time"] > 0.0)
	if not me.alive:
		arcs.clear()
	queue_redraw()   # o último redesenho, com a lista vazia, apaga os arcos


func _draw() -> void:
	if (arcs.is_empty() and not _threat_drawn) or me.camera == null:
		return
	var center := size / 2.0
	var basis := me.camera.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	if _threat_drawn:
		var to := threat - me.global_position
		to.y = 0.0
		if to.length() > 0.3:
			var ta := atan2(to.dot(right), to.dot(forward)) - PI / 2.0
			var glow := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.012))
			var span := ARC_SPAN * 1.3
			draw_arc(center, ARC_RADIUS + 14.0, ta - span / 2.0, ta + span / 2.0, 24,
				Color(0, 0, 0, 0.45 * glow), 10.0, true)
			draw_arc(center, ARC_RADIUS + 14.0, ta - span / 2.0, ta + span / 2.0, 24,
				Color(KingRealm.MARK_COLOR, glow), 6.0, true)
	for a in arcs:
		var dir: Vector3 = a["pos"] - me.global_position
		dir.y = 0.0
		if dir.length() < 0.5:
			continue
		# Ângulo na tela: à frente = topo, à direita = direita (só o giro, sem olhar p/ cima).
		var angle := atan2(dir.dot(right), dir.dot(forward)) - PI / 2.0
		var alpha := clampf(a["time"] / ARC_FADE, 0.0, 1.0) * 0.9
		var width := 4.0 + 4.0 * float(a["size"])
		draw_arc(center, ARC_RADIUS, angle - ARC_SPAN / 2.0, angle + ARC_SPAN / 2.0, 24,
			Color(0, 0, 0, alpha * 0.4), width + 3.0, true)
		draw_arc(center, ARC_RADIUS, angle - ARC_SPAN / 2.0, angle + ARC_SPAN / 2.0, 24,
			Color(1.0, 0.18, 0.15, alpha), width, true)
