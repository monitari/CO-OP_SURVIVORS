extends RefCounted
## Shared moonlit-cat UI tokens. Combat ownership and danger colours stay separate.

## The one typeface in the game.
##
## Jua is bundled with its OFL licence rather than relying on an OS fallback, so
## every machine renders the same rounded storybook voice. It used to be applied
## only to the theme main.gd hands its HUD host, which meant everything drawn
## outside that Control subtree — floating damage numbers, the P1/P2 badges over
## the cats, the downed prompt — fell back to the engine's own Open Sans and the
## screen carried two typefaces at once. `adopt()` puts it on ThemeDB as well,
## which is what those non-Control draws and any un-themed Label actually read.
const FAMILY := preload("res://assets/fonts/Jua-Regular.ttf")


## Makes FAMILY the fallback for every font lookup in the process, themed or not.
## Idempotent; call it before the first Control or draw_string.
##
## Two separate resolutions have to be pointed at it, because a Control does not
## read the same one a bare draw_string does: `ThemeDB.fallback_font` is what an
## explicit engine-font draw ends up with, while an un-themed Control asks the
## default Theme. Setting only the first leaves every Label that is not under a
## themed host — the floating damage numbers, most of all — in the engine face.
static func adopt() -> Font:
	if ThemeDB.fallback_font != FAMILY:
		ThemeDB.fallback_font = FAMILY
	var default_theme := ThemeDB.get_default_theme()
	if default_theme != null and default_theme.default_font != FAMILY:
		default_theme.default_font = FAMILY
	return FAMILY

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
## The panel surface every menu box shares. It used to be the generated v3
## panel art stretched as a nine-slice; it is a see-through overlay now, the
## same size, so whatever is behind a panel — the rooftop backdrop, or the
## paused run — still shows through it.
const OVERLAY := Color(0.025, 0.045, 0.095, 0.64)
const OVERLAY_EDGE := Color("7596bd40")

static func image_surface(active := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = OVERLAY.lerp(Color(P1, OVERLAY.a), 0.08) if active else OVERLAY
	style.border_color = OVERLAY_EDGE
	style.set_border_width_all(BORDER)
	style.set_corner_radius_all(RADIUS + 4)
	style.corner_detail = corner_detail_for(RADIUS + 4)
	style.set_content_margin_all(4.0)
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
	style.corner_detail = corner_detail_for(radius)
	return style


## Segments per rounded corner, in proportion to its radius.
##
## Every surface used twelve regardless of size. A 7px HUD socket corner split
## twelve ways is segments a fraction of a pixel long, and each segment is
## triangles for the fill, the border and the antialiasing feather — the twenty
## HUD panels came to fifteen thousand primitives a frame (tests/
## perf_bench_capture.gd, BENCH_LAYERS=1). At 0.6 segments per pixel of radius
## the corner never strays from a true arc by more than a tenth of a pixel.
static func corner_detail_for(radius: float) -> int:
	return clampi(ceili(radius * 0.6), 3, 12)


static func player_surface(slot: int, active := false, confirmed := false, dark := false) -> StyleBoxFlat:
	var accent := P1 if slot == 0 else P2
	var style := image_surface(active or confirmed)
	var tint_strength := 0.14 if confirmed else (0.08 if active else 0.025)
	style.bg_color = OVERLAY.lerp(Color(accent, OVERLAY.a), tint_strength)
	if dark:
		style.bg_color = style.bg_color.darkened(0.06)
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
