extends RefCounted

const Frame := preload("res://scripts/ui/neon_frame.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")

const CYAN := Color("35dbff")
const PARTNER := Color("ff9f43")
const CHEST := Color("ffd166")
const INK := Color("f1f7ff")
## The largest card the growth hand deals. A chest reward is the same card at the
## same size, scaled down as a whole when the box holds more than fits a row.
const CARD_SIZE := Vector2(224, 348)


static func surface(tint: Color, selected := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("09182f")
	style.border_color = tint
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(tint, 0.3 if selected else 0.12)
	style.shadow_size = 12 if selected else 6
	return style


static func decorate(card: Control, tint: Color, selected := false, ears := false, paws := true, apply_surface := true) -> void:
	var style_key := "normal" if card is Label else "panel"
	if apply_surface:
		card.add_theme_stylebox_override(style_key, surface(tint, selected))
	card.set_meta("growth_card_visual", true)
	var frame := card.get_node_or_null("NeonTrim")
	if frame == null:
		frame = Frame.new()
		frame.name = "NeonTrim"
		card.add_child(frame)
	frame.accent = tint
	frame.active = selected
	frame.ears = ears
	frame.paws = paws
	frame.queue_redraw()


## An empty card carrying every child `paint` fills in. The level-up hand builds
## its cards in main.gd with the same node names; the chest showcase builds them
## here. Both are painted by `paint`, so a chest reward and a growth choice are
## one card rather than two cards kept in step by hand.
static func create_card() -> Label:
	var card := Label.new()
	card.size = CARD_SIZE
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_theme_color_override("font_color", Palette.INK)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["Icon", "FusionMark"]:
		var art := TextureRect.new()
		art.name = key
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
	for key in ["Scope", "Category", "CardTitle", "Recommendation"]:
		var text := Label.new()
		text.name = key
		text.clip_text = true
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_color_override("font_color", Palette.INK)
		if key == "CardTitle":
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(text)
	return card


## Lays out and fills one card. `model` is what the card says, independent of
## where it came from: category, title, body, icon, fusion (texture or null),
## tech (compact layout), advice ("recommended" / "discouraged" / "neutral") and
## reason.
static func paint(card: Label, model: Dictionary, tint: Color, selected: bool, width: float, height: float) -> void:
	var tech := bool(model.get("tech", false))
	var style := surface(tint, selected)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 178 if tech else (214 if height > 330 else 190)
	style.content_margin_bottom = 56
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_font_size_override("font_size", 13 if tech else (16 if width > 190 else 14))
	card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# Not clip_text: a clipping Label clips its whole canvas item to the
	# screen-space bounds of its rectangle, which cut the selection glow and the
	# drop shadow off every card — straight across, at the height of the highest
	# corner of a tilted one. Trimming the overflowing lines keeps the body inside
	# the card without clipping anything drawn around it.
	card.clip_text = false
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.text = String(model.get("body", ""))
	var category: Label = card.get_node("Category")
	category.text = String(model.get("category", ""))
	category.position = Vector2(30, 12)
	category.size = Vector2(width - 60, 25)
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category.add_theme_font_size_override("font_size", 17 if width > 190 else 14)
	category.add_theme_color_override("font_color", tint.lightened(0.35))
	var icon: TextureRect = card.get_node("Icon")
	icon.texture = model.get("icon") as Texture2D
	var art := 80.0 if tech else (106.0 if height > 330 else 86.0)
	icon.position = Vector2((width - art) * 0.5, 45)
	icon.size = Vector2.ONE * art
	var title: Label = card.get_node("CardTitle")
	title.text = String(model.get("title", ""))
	title.position = Vector2(13, 123 if tech else (155 if height > 330 else 132))
	title.size = Vector2(width - 26, 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21 if width > 190 else 17)
	card.get_node("Scope").visible = false
	var fusion: TextureRect = card.get_node("FusionMark")
	fusion.texture = model.get("fusion") as Texture2D
	fusion.visible = fusion.texture != null
	fusion.position = Vector2(width - 45, 52)
	fusion.size = Vector2(32, 32)
	var badge: Label = card.get_node("Recommendation")
	var advice := String(model.get("advice", "neutral"))
	badge.text = recommendation_text(advice, String(model.get("reason", "무난한 성장")))
	badge.visible = true
	badge.position = Vector2(10, height - 47)
	badge.size = Vector2(width - 20, 36)
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_stylebox_override("normal", surface(tint.darkened(0.3)))
	badge.add_theme_color_override("font_color", recommendation_color(advice))
	decorate(card, tint, selected, false, true, false)


static func recommendation_text(advice: String, reason: String) -> String:
	match advice:
		"recommended":
			return "👍 " + reason
		"discouraged":
			return "👎 " + reason
		_:
			return "— " + reason


static func recommendation_color(advice: String) -> Color:
	return Color("ffafbd") if advice == "discouraged" else Color("71ffcd")
