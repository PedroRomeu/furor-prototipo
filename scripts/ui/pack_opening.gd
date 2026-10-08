class_name PackOpening
extends Control
## Abertura de pacote (pedido do usuário, 2026-10-08, no estilo do Clash Royale e do Marvel
## Snap): o pacote aparece, um clique rasga a tira de cima, as cartas saem viradas em fila
## (da mais comum para a mais rara, Collection.open_pack já ordena) e cada clique revela a
## próxima. Épica brilha; lendária e mestra tremem e brilham na cor da raridade antes de
## virar, e a mestra ainda dá um clarão na tela. Embaixo de cada carta: NOVA, a cópia
## (2/3) ou a ficha ganha. Só tweens de posição, escala e cor (nada redesenhado por quadro).

signal finished
signal again

const CARD := Vector2(150, 214)
const GAP := 18.0
const PACK := Vector2(230, 330)
const STRIP := 70.0
const FLIP := 0.13

var pack_id := ""
var results: Array = []
var can_again := false

var _stage := 0          # 0 pacote fechado, 1 animando, 2 revelando, 3 fim
var _next := 0
var _holders: Array = []  # Control de cada carta (verso e frente dentro)
var _strip: Control
var _body: Control
var _hint: Label
var _buttons: HBoxContainer
var _again_button: Button
var _reveal_all: Button
var _flash: ColorRect


func open(p_pack_id: String, p_results: Array, p_can_again: bool) -> void:
	pack_id = p_pack_id
	results = p_results
	can_again = p_can_again
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for c in get_children():
		c.queue_free()
	_holders.clear()
	_next = 0
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.03, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_pack()
	_hint = Ui.label("Clique para abrir", 18, Ui.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -110
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_buttons = Ui.hbox(12)
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.offset_top = -86
	_buttons.offset_bottom = -40
	_buttons.offset_left = -260
	_buttons.offset_right = 260
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.visible = false
	add_child(_buttons)
	_reveal_all = Ui.button("Revelar todas", _reveal_rest, 200)
	_buttons.add_child(_reveal_all)
	_again_button = Ui.button("Abrir outro  ·  %d" % Collection.PACKS[pack_id]["price"], func(): again.emit(), 220)
	_buttons.add_child(_again_button)
	var done := Ui.accent(Ui.button("Continuar", func(): finished.emit(), 180))
	done.name = "Done"
	_buttons.add_child(done)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_stage = 0
	visible = true
	# O pacote chega crescendo.
	for part in [_strip, _body]:
		part.modulate.a = 0.0
		create_tween().tween_property(part, "modulate:a", 1.0, 0.25)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if _stage == 0:
		_tear()
	elif _stage == 2:
		_reveal_next()


# ---------------------------------------------------------------- pacote

func _build_pack() -> void:
	var color: Color = Collection.PACKS[pack_id]["color"]
	var center := size / 2.0 if size != Vector2.ZERO else get_viewport_rect().size / 2.0
	var origin := center - PACK / 2.0 - Vector2(0, 30)
	_strip = PanelContainer.new()
	var strip_style := Ui.box(color.darkened(0.45), 16, color, 3)
	strip_style.corner_radius_bottom_left = 0
	strip_style.corner_radius_bottom_right = 0
	_strip.add_theme_stylebox_override("panel", strip_style)
	_strip.position = origin
	_strip.size = Vector2(PACK.x, STRIP)
	_strip.pivot_offset = Vector2(PACK.x, STRIP)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tear := Ui.label("-  -  -  -  -  -  -  -  -  -", 14, Color(1, 1, 1, 0.5), true)
	tear.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(tear)
	add_child(_strip)
	_body = PanelContainer.new()
	var body_style := Ui.box(color.darkened(0.55), 16, color, 3)
	body_style.corner_radius_top_left = 0
	body_style.corner_radius_top_right = 0
	_body.add_theme_stylebox_override("panel", body_style)
	_body.position = origin + Vector2(0, STRIP)
	_body.size = Vector2(PACK.x, PACK.y - STRIP)
	_body.pivot_offset = _body.size / 2.0
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Ui.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(col)
	for t in [["FUROR", 40, Color.WHITE], [Collection.PACKS[pack_id]["name"], 18, color.lightened(0.3)],
			["%d carta%s" % [results.size(), "" if results.size() == 1 else "s"], 14, Ui.MUTED]]:
		var l := Ui.label(t[0], t[1], t[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	add_child(_body)


## Rasga: a tira voa girando, o corpo treme e cai sumindo, e as cartas saem em fila.
func _tear() -> void:
	_stage = 1
	_hint.text = ""
	Sfx.ui(self, "shield")
	var t := create_tween().set_parallel()
	t.tween_property(_strip, "position", _strip.position + Vector2(160, -140), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_strip, "rotation", 0.6, 0.45)
	t.tween_property(_strip, "modulate:a", 0.0, 0.45)
	var shake := create_tween()
	for k in 4:
		shake.tween_property(_body, "rotation", 0.05 * (1 if k % 2 == 0 else -1), 0.04)
	shake.tween_property(_body, "rotation", 0.0, 0.04)
	shake.tween_property(_body, "position", _body.position + Vector2(0, 260), 0.4).set_ease(Tween.EASE_IN)
	shake.parallel().tween_property(_body, "modulate:a", 0.0, 0.4)
	_flash_screen(Color(1, 1, 1), 0.25)
	await get_tree().create_timer(0.3).timeout
	_deal()


func _deal() -> void:
	var n := results.size()
	var total := n * CARD.x + (n - 1) * GAP
	var area := size if size != Vector2.ZERO else get_viewport_rect().size
	var scale_fit := minf(1.0, (area.x - 80.0) / total)
	var start := Vector2(area.x / 2.0 - total * scale_fit / 2.0, area.y / 2.0 - CARD.y * scale_fit / 2.0 - 30)
	var from := area / 2.0 - CARD / 2.0
	for i in n:
		var holder := Control.new()
		holder.size = CARD
		holder.pivot_offset = CARD / 2.0
		holder.position = from
		holder.scale = Vector2.ONE * 0.3 * scale_fit
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glow := PanelContainer.new()
		glow.name = "Glow"
		var gs := Ui.box(Color(0, 0, 0, 0), 14)
		gs.shadow_color = Color(Collection.PACKS[pack_id]["color"], 0.0)
		gs.shadow_size = 0
		glow.add_theme_stylebox_override("panel", gs)
		glow.size = CARD
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(glow)
		var back := CardFace.back(CARD.x, CARD.y)
		back.name = "Back"
		back.size = CARD
		holder.add_child(back)
		add_child(holder)
		move_child(holder, _flash.get_index())   # o clarão fica por cima de tudo
		_holders.append(holder)
		var target := start + Vector2(i * (CARD.x + GAP) * scale_fit, 0) - CARD * (1.0 - scale_fit) / 2.0
		var t := create_tween().set_parallel()
		t.tween_property(holder, "position", target, 0.35).set_delay(i * 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(holder, "scale", Vector2.ONE * scale_fit, 0.35).set_delay(i * 0.06)
	await get_tree().create_timer(0.35 + n * 0.06).timeout
	_stage = 2
	_hint.text = "Clique para revelar"
	_buttons.visible = true
	_again_button.visible = false
	_buttons.get_node("Done").visible = false
	_reveal_all.visible = n > 1


# ---------------------------------------------------------------- revelação

func _reveal_next() -> void:
	if _next >= results.size():
		return
	var i := _next
	_next += 1
	var r: Dictionary = results[i]
	var holder: Control = _holders[i]
	var rare: bool = r["rarity"] in ["lendario", "mitico"]
	_stage = 1
	if rare:
		await _suspense(holder, r)
	await _flip(holder, r)
	_stage = 2
	if _next >= results.size():
		_finish()


func _reveal_rest() -> void:
	if _stage != 2:
		return
	while _next < results.size():
		await _reveal_next()


## Antes de lendária e mestra: a carta treme e acende na cor da raridade.
func _suspense(holder: Control, r: Dictionary) -> void:
	var color: Color = CardDB.RARITIES[r["rarity"]]["color"]
	_glow(holder, color, 0.9, 0.5)
	var t := create_tween()
	for k in 6:
		t.tween_property(holder, "rotation", 0.04 * (1 if k % 2 == 0 else -1), 0.05)
	t.tween_property(holder, "rotation", 0.0, 0.05)
	await t.finished


func _flip(holder: Control, r: Dictionary) -> void:
	var base := holder.scale
	var t := create_tween()
	t.tween_property(holder, "scale", Vector2(0.0, base.y), FLIP)
	await t.finished
	holder.get_node("Back").visible = false
	var face := CardFace.make(r["id"], CARD.x)
	face.custom_minimum_size.y = CARD.y
	face.size = CARD
	holder.add_child(face)
	holder.add_child(_badge(r))
	var color: Color = CardDB.RARITIES[r["rarity"]]["color"]
	match r["rarity"]:
		"comum", "raro":
			Sfx.ui(self, "hit")
		"epico":
			Sfx.ui(self, "pickup")
			_glow(holder, color, 0.7, 0.3)
		"lendario":
			Sfx.ui(self, "kill")
			_glow(holder, color, 1.0, 0.3)
			_flash_screen(color, 0.18)
		"mitico":
			Sfx.ui(self, "kill")
			_glow(holder, color, 1.0, 0.3)
			_flash_screen(color, 0.35)
	t = create_tween()
	t.tween_property(holder, "scale", base, FLIP)
	if r["rarity"] in ["lendario", "mitico"]:
		t.tween_property(holder, "scale", base * 1.12, 0.12)
		t.tween_property(holder, "scale", base, 0.18)
	await t.finished


## Embaixo da carta: NOVA, a cópia (2/3) ou a ficha que ela virou.
func _badge(r: Dictionary) -> Label:
	var text := ""
	var color := Ui.MUTED
	if r["token"]:
		text = "+1 ficha %s" % Collection.RARITY_FEM[r["rarity"]]
		color = CardDB.RARITIES[r["rarity"]]["color"]
	elif r["new"]:
		text = "NOVA"
		color = Ui.OK
	else:
		text = "%d/%d" % [r["copy"], Collection.max_copies(r["id"])]
	var l := Ui.label(text, 15, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, CARD.y + 8)
	l.size = Vector2(CARD.x, 24)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _glow(holder: Control, color: Color, strength: float, time: float) -> void:
	var glow: PanelContainer = holder.get_node("Glow")
	var s: StyleBoxFlat = glow.get_theme_stylebox("panel")
	var t := create_tween()
	t.tween_method(func(v: float):
		s.shadow_color = Color(color, v * 0.8)
		s.shadow_size = int(v * 28.0), 0.0, strength, time)


func _flash_screen(color: Color, alpha: float) -> void:
	_flash.color = Color(color, alpha)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.4)


func _finish() -> void:
	_stage = 3
	_hint.text = ""
	_reveal_all.visible = false
	_buttons.get_node("Done").visible = true
	_again_button.visible = can_again and Collection.coins >= Collection.PACKS[pack_id]["price"]
