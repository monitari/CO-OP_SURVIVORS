extends RefCounted
## Shared "moonlit scrapbook" UI tokens: cream paper and dark ink laid over the
## night rooftop. Combat ownership and danger colours stay separate.

## Two typefaces, split by what the reader is doing with the words.
##
## Griun Hangul Gowoon is the game's voice: a thin, calm handwriting for titles,
## card names, dialogue and anything read at leisure on paper.
##
## Jua is the compact readout face for text drawn directly over the moving world:
## damage, survivor badges, edge distances, boss details and the bottom XP strip.
## The rebuilt top HUD has its own opaque paper surfaces, so its clock, names and
## meters use Gowoon like the rest of the interface without losing contrast.
##
## Memoment Kkukkukk is the fallback under both. It is the only bundled face
## with the full 11,172 Hangul syllables, and the only one with the punctuation
## the HUD actually types — the middle dot in "거리·안정", arrows, the em dash.
## Jua used to hold this job while missing every one of those glyphs, which left
## them to whatever the operating system happened to offer.
##
## `adopt()` puts FAMILY on ThemeDB as well as on the HUD host's theme, which is
## what non-Control draws (damage numbers, P1/P2 badges, the downed prompt) and
## any un-themed Label actually read.
const FAMILY := preload("res://assets/fonts/GriunXHangeul_Gowoon-Rg.ttf")
const READOUT := preload("res://assets/fonts/Jua-Regular.ttf")
const SYMBOL_FALLBACK := preload("res://assets/fonts/MemomentKkukkukk.ttf")


## Makes FAMILY the fallback for every font lookup in the process, themed or not,
## and hangs the symbol face under both bundled families.
## Idempotent; call it before the first Control or draw_string.
##
## Two separate resolutions have to be pointed at it, because a Control does not
## read the same one a bare draw_string does: `ThemeDB.fallback_font` is what an
## explicit engine-font draw ends up with, while an un-themed Control asks the
## default Theme. Setting only the first leaves every Label that is not under a
## themed host — the floating damage numbers, most of all — in the engine face.
##
## The two families never fall back to *each other*: a chain that loops would be
## one, and a word half-set in handwriting and half in the readout face reads as
## a rendering bug rather than as a hierarchy.
static func adopt() -> Font:
	for face: FontFile in [FAMILY, READOUT]:
		if face.fallbacks.is_empty():
			face.fallbacks = [SYMBOL_FALLBACK]
	if ThemeDB.fallback_font != FAMILY:
		ThemeDB.fallback_font = FAMILY
	var default_theme := ThemeDB.get_default_theme()
	if default_theme != null and default_theme.default_font != FAMILY:
		default_theme.default_font = FAMILY
	return FAMILY

# --- Paper: everything a player reads from a menu is written on it. ---------
## Text on paper. A warm plum-black rather than pure black, like fountain ink.
const INK := Color("2b2330")
## Secondary text on paper.
const MUTED := Color("786a73")
## The page itself: large sheets (pause, results, the build sheet).
const PAPER := Color("f2e6cb")
## Cards and rows laid on a sheet, a shade brighter than the sheet under them.
const PAPER_LIGHT := Color("fcf6e8")
## Recessed paper: stat chips, notes, inactive rows.
const PAPER_SHADE := Color("e6d6b4")
## A polaroid's border is whiter than the craft paper it is taped onto.
const PHOTO_BORDER := Color("fffcf3")
## The "photograph" inside a polaroid: the night sky every portrait is shot on.
const PHOTO_NIGHT := Color("1b2640")
## The cut edge every paper piece is outlined with.
const INK_LINE := Color("2b2330")
## Hard, un-blurred cast shadow of a paper piece lifted off the page.
const PAPER_SHADOW := Color(0.04, 0.03, 0.06, 0.38)
const PAPER_SHADOW_OFFSET := Vector2(4, 5)

# --- Night: text that sits directly on the rooftop art or the fight. --------
const CREAM := Color("fff9ea")
const NIGHT_MUTED := Color("c9d3e2")
const NIGHT := Color("080f20")
const NIGHT_PANEL := Color("111f36")
const NIGHT_RAISED := Color("20334e")
const GOLD := Color("edc77e")
const OUTLINE := Color("7596bd55")

# --- Ownership. The bright pair is for the fight; the *_INK pair is the same
# hue dark enough to be read on paper. ---------------------------------------
const P1 := Color("63dce6")
## Cyan and violet sat too close perceptually on the blue rooftop. The partner
## now owns a warm amber-orange family throughout selection, HUD and cards.
const P2 := Color("ff9f43")
const P1_INK := Color("137b87")
const P2_INK := Color("b8581a")
const GOLD_INK := Color("9a6a12")
const DANGER_INK := Color("b8392f")
## Masking tape, one roll per owner plus the neutral roll for everything else.
const TAPE := Color("e9d18f")

## Cards and rows: paper one shade brighter than the sheet.
const CARD := PAPER_LIGHT
## Sheets: dialogues and the build sheet. Nearly opaque, so the fight behind a
## pause still reads as "behind" without printing through the words.
const PANEL := Color(PAPER, 0.97)
# Combat can put hundreds of bright silhouettes behind these panels. At 60%
# opacity the crowd became part of the typography; 90% keeps the rooftop tone
# while giving health, builds and the shared timer a stable reading surface.
const HUD := Color("0c172ae6")

const RADIUS := 4
const BORDER := 2
const BORDER_ACTIVE := 3
## The panel surface every menu box shares: a sheet of paper. Slightly see-
## through (0.97) so a panel is still an overlay, not a new screen.
const OVERLAY := Color(PAPER, 0.97)
const OVERLAY_EDGE := INK_LINE

static func image_surface(active := false) -> StyleBoxFlat:
	var style := paper(PAPER.lerp(PAPER_LIGHT, 0.4) if active else PAPER)
	style.bg_color.a = OVERLAY.a
	style.set_content_margin_all(4.0)
	return style

const PADDING := 16

const TYPE_TITLE := 28
const TYPE_METRIC := 36
const TYPE_HEADING := 20
const TYPE_VALUE := 18
const TYPE_BODY := 16
const TYPE_CAPTION := 14


## A generic box. Light, unsaturated tints are paper and get the paper
## treatment — an ink cut edge and a hard shadow — so a caller asking for CARD or
## PANEL gets a scrapbook piece without knowing about it. Dark tints (HUD
## sockets, meter tracks) and saturated ones (bar fills) stay flat boxes.
static func surface(tint: Color = PANEL, radius: int = RADIUS) -> StyleBoxFlat:
	if tint.get_luminance() > 0.55 and tint.s < 0.35:
		var sheet := paper(tint)
		sheet.set_corner_radius_all(radius)
		sheet.corner_detail = corner_detail_for(radius)
		return sheet
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = OUTLINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.corner_detail = corner_detail_for(radius)
	return style


## A piece of paper cut out and laid on the page: an ink edge, nearly square
## corners, and a hard offset shadow instead of a glow.
static func paper(tint: Color = PAPER_LIGHT, lifted := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = INK_LINE
	style.set_border_width_all(BORDER)
	style.set_corner_radius_all(RADIUS)
	style.corner_detail = corner_detail_for(RADIUS)
	style.shadow_color = PAPER_SHADOW
	style.shadow_size = 1
	style.shadow_offset = PAPER_SHADOW_OFFSET * (1.5 if lifted else 1.0)
	return style


## The "photograph" window inside a polaroid or a portrait frame: night sky
## behind a thick white border.
static func photo(border := 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PHOTO_NIGHT
	style.border_color = PHOTO_BORDER
	style.set_border_width_all(border)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(PAPER_SHADOW, 0.25)
	style.shadow_size = 1
	style.shadow_offset = Vector2(2, 3)
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


## The paper-ink shade of an owner colour, for text and edges on paper.
static func owner_ink(slot: int) -> Color:
	return P1_INK if slot == 0 else P2_INK


static func player_surface(slot: int, active := false, confirmed := false, dark := false) -> StyleBoxFlat:
	var accent := P1 if slot == 0 else P2
	var tint_strength := 0.16 if confirmed else (0.07 if active else 0.02)
	var style := paper(PAPER.lerp(accent, tint_strength), active or confirmed)
	style.bg_color.a = OVERLAY.a
	style.border_color = owner_ink(slot) if active or confirmed else INK_LINE
	style.set_border_width_all(BORDER_ACTIVE if confirmed else BORDER)
	if dark:
		style.bg_color = style.bg_color.darkened(0.06)
	style.set_content_margin_all(PADDING)
	return style


## A paper button. Hover and a primary action are coloured like a marker pen
## over the paper; a pressed button loses its shadow, as if pushed flat.
static func button_surface(state := "normal", accent: Color = P1, primary := false) -> StyleBoxFlat:
	var tint := PAPER_LIGHT
	if primary:
		tint = PAPER_LIGHT.lerp(accent, 0.42)
	if state == "hover":
		tint = tint.lerp(accent, 0.30 if not primary else 0.2)
	elif state == "pressed":
		tint = tint.lerp(accent, 0.45)
	elif state == "disabled":
		tint = PAPER_SHADE
	var style := paper(tint)
	style.set_border_width_all(BORDER_ACTIVE if state == "hover" else BORDER)
	if state == "pressed":
		style.shadow_offset = Vector2(1, 1)
	elif state == "disabled":
		style.border_color = Color(INK_LINE, 0.45)
		style.shadow_color = Color(PAPER_SHADOW, 0.12)
	style.set_content_margin_all(8)
	return style
