extends Control

## The off-screen marks: where the elite is, where the chest is.
##
## Both used to be a `Label` with a flat dark rectangle behind it, parked at the
## screen edge with the bearing baked into its position and nowhere else. That
## left the two most time-critical readings on the HUD — *which way* and *how
## far* — carried entirely by a word and a number the player had to stop and
## read. A pointer that does not point is a caption.
##
## This draws, in one node:
##
##   - **an arrowhead on the bearing**, outside the pill, so direction is read
##     from a shape rather than parsed from the mark's position on the edge
##   - **a pill** whose length follows its text, instead of one fixed box wide
##     enough for the longest string either pointer can ever produce
##   - **a proximity cue**: the arrow grows and the pill brightens as the thing
##     closes, so "it is nearly on us" arrives before the number does
##   - **an urgency pulse** for a drop that is about to expire, which is the one
##     case where the mark is asking the pair to change what they are doing
##
## The two pointers share this class and differ only by accent colour and label,
## which is what keeps them reading as one family of marks — a boss and a box
## should look like the same kind of HUD object, not like two unrelated widgets.

const PILL_HEIGHT := 30.0
const PILL_PADDING := 11.0
const ARROW_LENGTH := 13.0
const ARROW_HALF := 8.0
const ARROW_GAP := 7.0
const CORNER := 15.0
const BACKDROP := Color("060b18e0")

var accent := Color("ff5d8f")
var text := ""
## Unit vector from the screen centre toward the thing being pointed at.
var bearing := Vector2.RIGHT
## 0 far away, 1 just off the edge. Drives the arrow's size and the pill's glow.
var closeness := 0.0
## Set while a drop is running out; drives the pulse.
var urgent := false
var pulse := 0.0
var _text_width := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Everything the pointer shows, set in one call so a half-updated mark is not a
## state this can be left in.
func report(mark: String, direction: Vector2, nearness: float, tint: Color, is_urgent: bool) -> void:
	text = mark
	bearing = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	closeness = clampf(nearness, 0.0, 1.0)
	accent = tint
	urgent = is_urgent
	_text_width = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	size = Vector2(_text_width + PILL_PADDING * 2.0, PILL_HEIGHT)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if urgent:
		pulse = fposmod(pulse + delta * 4.0, TAU)
		queue_redraw()
	elif pulse != 0.0:
		pulse = 0.0
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var pill := Rect2(Vector2.ZERO, size)
	var glow := 0.25 + 0.45 * closeness
	if urgent:
		glow = clampf(glow + 0.25 * (0.5 + 0.5 * sin(pulse)), 0.0, 1.0)

	# The arrow sits outside the pill on the bearing, so the mark points away
	# from the pair and toward the thing — the same way round as looking at it.
	var scale := 0.82 + 0.5 * closeness
	var centre := pill.get_center() + bearing * (_pill_reach() + ARROW_GAP)
	var tip := centre + bearing * ARROW_LENGTH * scale
	var side := bearing.orthogonal() * ARROW_HALF * scale
	var head := PackedVector2Array([tip, centre + side, centre - side])
	draw_colored_polygon(head, Color(accent, 0.55 + 0.45 * glow))
	draw_polyline(PackedVector2Array([tip, centre + side, centre - side, tip]),
		Color(accent.lightened(0.4), 0.9), 1.5, true)

	draw_style_box(_pill_style(glow), pill)
	draw_string(font, Vector2(PILL_PADDING, PILL_HEIGHT * 0.5 + 6.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff9ea"))


## How far the pill's own edge is from its centre along the bearing, so the
## arrow clears a wide pill and a narrow one by the same visual gap.
func _pill_reach() -> float:
	var half := size * 0.5
	var horizontal := half.x / maxf(0.001, absf(bearing.x))
	var vertical := half.y / maxf(0.001, absf(bearing.y))
	return minf(horizontal, vertical)


func _pill_style(glow: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BACKDROP.lerp(Color(accent, 0.92), 0.10 + 0.14 * glow)
	box.set_corner_radius_all(int(CORNER))
	box.set_border_width_all(1)
	box.border_color = Color(accent, 0.45 + 0.5 * glow)
	# A soft halo rather than a hard drop shadow: the roof under the HUD is dark
	# and busy, and a hard edge there reads as a second, nearer object.
	box.shadow_color = Color(accent, 0.16 + 0.2 * glow)
	box.shadow_size = int(3.0 + 5.0 * glow)
	return box
