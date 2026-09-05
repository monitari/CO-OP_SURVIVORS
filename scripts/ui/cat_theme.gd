extends RefCounted
## Shared moonlit-cat UI tokens. Combat ownership and danger colours stay separate.
const INK := Color("202e38")
const PANEL := Color("f3efdf")
const CREAM := Color("fff9ea")
const GOLD := Color("bb633d")
const MUTED := Color("66706c")
const OUTLINE := Color("d4d5c7")
const P1 := Color("176c76")
const P2 := Color("715590")
const CARD := Color("fffdf4")


static func surface(tint: Color = PANEL, radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = OUTLINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	return style
