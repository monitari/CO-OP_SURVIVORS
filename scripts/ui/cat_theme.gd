extends RefCounted
## Shared moonlit-cat UI tokens. Combat ownership and danger colours stay separate.
const INK := Color("edf3fa")
const PANEL := Color("101b30ed")
const CREAM := Color("fff9ea")
const NIGHT := Color("080f20")
const NIGHT_PANEL := Color("111f36")
const NIGHT_RAISED := Color("20334e")
const GOLD := Color("edc77e")
const MUTED := Color("a6b9cf")
const OUTLINE := Color("7596bd55")
const P1 := Color("63dce6")
## Cyan and violet sat too close perceptually on the blue rooftop. The partner
## now owns a warm amber-orange family throughout selection, HUD and cards.
const P2 := Color("ff9f43")
const CARD := Color("192a42f2")
# Combat can put hundreds of bright silhouettes behind these panels. At 60%
# opacity the crowd became part of the typography; 90% keeps the rooftop tone
# while giving health, builds and the shared timer a stable reading surface.
const HUD := Color("0c172ae6")

const RADIUS := 10
const BORDER := 1
const BORDER_ACTIVE := 2
## Full-bleed generated panel art. Its corner and edge caps are protected by
## StyleBoxTexture margins while the quiet centre stretches to every menu size.
const PANEL_ART := preload("res://assets/ui/character_panel_v3.png")
static var panel_texture: ImageTexture

static func image_surface(active := false) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	if panel_texture == null:
		var bitmap := PANEL_ART.get_image()
		panel_texture = ImageTexture.create_from_image(bitmap)
	style.texture = panel_texture
	style.set_texture_margin_all(16.0)
	style.set_expand_margin_all(0.0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 4.0)
	style.modulate_color = Color.WHITE.lerp(P1, 0.08) if active else Color.WHITE
	return style

const PADDING := 16

const TYPE_TITLE := 28
const TYPE_METRIC := 36
const TYPE_HEADING := 20
const TYPE_VALUE := 18
const TYPE_BODY := 15
const TYPE_CAPTION := 13


static func surface(tint: Color = PANEL, radius: int = RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = OUTLINE
	style.set_border_width_all(BORDER)
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	return style


static func player_surface(slot: int, active := false, confirmed := false, dark := false) -> StyleBoxTexture:
	var accent := P1 if slot == 0 else P2
	var style := image_surface(active or confirmed)
	var tint_strength := 0.14 if confirmed else (0.08 if active else 0.025)
	style.modulate_color = Color.WHITE.lerp(accent, tint_strength)
	if dark:
		style.modulate_color = style.modulate_color.darkened(0.06)
	style.set_content_margin_all(PADDING)
	return style


static func button_surface(state := "normal", accent: Color = P1, primary := false) -> StyleBoxFlat:
	var tint := CARD
	if primary:
		tint = NIGHT_RAISED.lerp(accent, 0.28)
	if state == "hover":
		tint = tint.lerp(accent, 0.18)
	elif state == "pressed":
		tint = tint.lerp(accent, 0.28)
	elif state == "disabled":
		tint = PANEL
	var style := surface(tint, RADIUS + 4)
	style.border_color = accent if primary or state == "hover" else OUTLINE
	style.set_border_width_all(BORDER_ACTIVE if primary or state == "hover" else BORDER)
	style.set_content_margin_all(8)
	return style
