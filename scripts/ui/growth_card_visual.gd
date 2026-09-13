extends RefCounted

const Frame := preload("res://scripts/ui/neon_frame.gd")

const CYAN := Color("35dbff")
const PARTNER := Color("ff9f43")
const CHEST := Color("ffd166")
const INK := Color("f1f7ff")


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


static func recommendation_text(advice: String, reason: String) -> String:
	match advice:
		"recommended":
			return "👍  " + reason
		"discouraged":
			return "👎  " + reason
		_:
			return "●  " + reason


static func recommendation_color(advice: String) -> Color:
	match advice:
		"recommended":
			return Color("71ffcd")
		"discouraged":
			return Color("ffafbd")
		_:
			return Color("c6d7ec")
