class_name DamageFeedback
extends Control
## Aviso de dano (2026-10-05, o vermelho na tela inteira não dizia de onde vinha o tiro).
## Do jeito de CoD, Valorant e Apex, sem exagero:
## - arco vermelho em volta da mira apontando para quem acertou; acompanha quando você
##   gira e some em ARC_TIME segundos; mais grosso com mais dano;
## - bordas da tela avermelhadas por um instante, mais fortes com mais dano;
## - vida baixa (abaixo de LOW_HEALTH): as bordas pulsam de leve até curar.
## Dano sem origem (veneno, vazio) só avermelha as bordas.

const ARC_TIME := 1.2
const ARC_FADE := 0.5
const ARC_RADIUS := 120.0
const ARC_SPAN := 0.55          # radianos
const MAX_ARCS := 4
const LOW_HEALTH := 0.3         # fração da vida máxima
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform float aspect = 1.78;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p) / length(vec2(aspect, 1.0) * 0.5);
	float edge = smoothstep(0.55, 1.05, d);
	COLOR = vec4(0.8, 0.04, 0.04, edge * intensity);
}
"""

var me: Player
var arcs: Array = []      # {"pos": Vector3, "from": Player, "time": float, "size": float}
var pulse := 0.0          # vermelho nas bordas pelo último dano (cai sozinho)
var vignette: ColorRect
var _mat: ShaderMaterial


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
	vignette.visible = intensity > 0.005
	if vignette.visible:
		_mat.set_shader_parameter("intensity", intensity)
		_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	if arcs.is_empty():
		return
	for a in arcs:
		a["time"] -= delta
	arcs = arcs.filter(func(a): return a["time"] > 0.0)
	if not me.alive:
		arcs.clear()
	queue_redraw()   # o último redesenho, com a lista vazia, apaga os arcos


func _draw() -> void:
	if arcs.is_empty() or me.camera == null:
		return
	var center := size / 2.0
	var basis := me.camera.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
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
