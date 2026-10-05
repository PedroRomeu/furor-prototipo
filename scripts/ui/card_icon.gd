class_name CardIcon
extends PanelContainer
## Ícone quadrado de uma carta: desenho (assets/card_icons, game-icons.net) na cor do grupo,
## com o número de cópias no canto. Passando o mouse, mostra nome, grupo, raridade e efeito.

var card_id := ""
var copies := 1


## size: lado em pixels. tooltip: false quando quem usa já mostra o texto (editor, escolha).
static func make(id: String, size := 36.0, count := 1, tooltip := true) -> CardIcon:
	var icon := CardIcon.new()
	icon.card_id = id
	icon.copies = count
	icon.custom_minimum_size = Vector2(size, size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var color: Color = CardDB.CATEGORY_COLORS[CardDB.CARDS[id]["cat"]]
	var master := CardDB.is_master(id)
	var style := Ui.box(color.darkened(0.78), int(size * 0.2),
		CardDB.rarity_color(id) if master else color.darkened(0.35), 2 if master else 1)
	style.set_content_margin_all(size * 0.14)
	icon.add_theme_stylebox_override("panel", style)
	var tex := TextureRect.new()
	tex.texture = CardDB.icon(id)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 128 px reduzido sem serrilhar
	tex.modulate = color.lerp(Color.WHITE, 0.25)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(tex)
	if count > 1:
		var badge := Label.new()
		badge.text = "%d" % count
		badge.add_theme_font_size_override("font_size", maxi(10, int(size * 0.32)))
		badge.add_theme_font_override("font", Ui.bold())
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_constant_override("outline_size", 4)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.offset_left = -size
		badge.offset_top = -size
		badge.offset_right = 1
		badge.offset_bottom = 3
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(badge)
	if tooltip:
		icon.tooltip_text = CardDB.card_name(id)   # precisa de texto para a dica aparecer
		icon.mouse_default_cursor_shape = Control.CURSOR_HELP
	else:
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_custom_tooltip(_for_text: String) -> Object:
	var card: Dictionary = CardDB.CARDS[card_id]
	var col := Ui.vbox(4)
	var top := Ui.hbox(8)
	col.add_child(top)
	top.add_child(Ui.label(card["name"], 17, Ui.TEXT, true))
	top.add_child(Ui.spacer())
	if copies > 1:
		top.add_child(Ui.label("x%d" % copies, 15, Ui.WARN, true))
	var info := "%s  ·  %s" % [card["cat"], CardDB.rarity_name(card_id)]
	if CardDB.is_master(card_id):
		info += "  ·  mestra" + ("  ·  %s" % GameState.key_text("master") if card.has("cooldown") else "  ·  passiva")
	col.add_child(Ui.label(info, 13, CardDB.rarity_color(card_id)))
	# Quebra feita aqui: Label com autowrap dentro de dica fica com a altura errada.
	col.add_child(Ui.label(_wrap(card["desc"], 40), 14, Ui.MUTED))
	return col


static func _wrap(text: String, width: int) -> String:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		if line != "" and line.length() + 1 + word.length() > width:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	lines.append(line)
	return String.chr(10).join(lines)
