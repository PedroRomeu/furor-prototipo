class_name CardFace
## Cartão de uma carta da loja (abertura de pacote e ofertas): moldura do grupo, símbolo
## do grupo, ícone, nome e raridade; com desc_height > 0, a descrição numa área que rola.
## E o verso (back), igual para todas, para as cartas viradas do pacote.

const BACK_COLOR := Color(0.09, 0.11, 0.19)
const BACK_LINE := Color(0.45, 0.65, 1.0)


static func make(id: String, width: float, desc_height := 0.0) -> PanelContainer:
	var card: Dictionary = CardDB.CARDS[id]
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := CardFrame.style(card["cat"], "lit", CardDB.is_master(id), width * 0.07)
	panel.add_theme_stylebox_override("panel", style)
	var col := Ui.vbox(int(width * 0.04))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var top := Ui.hbox(4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(CardFrame.symbol_rect(card["cat"], maxf(14.0, width * 0.1)))
	top.add_child(Ui.spacer())
	var icon := CardIcon.make(id, width * 0.42, 1, false)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	var name_label := Ui.label(card["name"], int(maxf(13.0, width * 0.1)), Ui.TEXT, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var sub := CardDB.rarity_name(id) + ("  ·  mestra" if CardDB.is_master(id) else "")
	var rarity := Ui.label(sub, int(maxf(11.0, width * 0.075)), CardDB.rarity_color(id), true)
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rarity)
	if desc_height > 0.0:
		col.add_child(HSeparator.new())
		col.add_child(Ui.scroll_text(card["desc"], desc_height, 13, Ui.TEXT.darkened(0.15)))
	return panel


## Verso: azul-escuro com "FUROR" no meio.
static func back(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, height)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Ui.box(BACK_COLOR, int(width * 0.08), BACK_LINE.darkened(0.2), 2)
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var inner := PanelContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := Ui.box(Color.TRANSPARENT, int(width * 0.06), Color(BACK_LINE, 0.35), 1)
	inner_style.content_margin_left = width * 0.12
	inner_style.content_margin_right = width * 0.12
	inner_style.content_margin_top = height * 0.3
	inner_style.content_margin_bottom = height * 0.3
	inner.add_theme_stylebox_override("panel", inner_style)
	center.add_child(inner)
	var logo := Ui.label("FUROR", int(width * 0.14), Color(BACK_LINE, 0.85), true)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(logo)
	return panel
