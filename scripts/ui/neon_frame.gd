extends Control
## Scrapbook trim laid over a paper card: two strips of masking tape holding it
## to the page, a marker outline when it is the one in focus, and an ink paw
## stamp. Still called NeonTrim by the nodes that own one — the name predates
## the paper look — and it keeps the old API (accent / active / ears / paws), so
## every card, panel and button that was trimmed is re-dressed from here.
## Decorative only: it never takes input, and it redraws only when it changes.
const Palette := preload("res://scripts/ui/cat_theme.gd")
var accent := Color("35dbff"):
	set(value):
		if accent != value:
			accent = value
			queue_redraw()
var active := false:
	set(value):
		if active != value:
			active = value
			queue_redraw()
var ears := false
var paws := true
var last_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:neon_frame", probe_started)


func _probed_draw() -> void:
	var tape := _tape_colour()
	if active:
		# A marker line traced just outside the cut edge, a little off-register
		# the way a hand-drawn circle around a photo is.
		var marker := StyleBoxFlat.new()
		marker.bg_color = Color.TRANSPARENT
		marker.border_color = Color(accent.darkened(0.08), 0.95)
		marker.set_border_width_all(3)
		marker.set_corner_radius_all(Palette.RADIUS + 3)
		marker.corner_detail = Palette.corner_detail_for(Palette.RADIUS + 3)
		draw_style_box(marker, Rect2(Vector2(-9, -9), size + Vector2(18, 18)))
	# A transparent accent means "nothing holds this down": no tape at all.
	if accent.a > 0.05 and size.x >= 60.0 and size.y >= 40.0:
		var strip := Vector2(clampf(size.x * 0.2, 26.0, 46.0), 14.0)
		_tape(Vector2(4.0, 2.0), strip, -0.62, tape)
		if size.x > 120.0:
			_tape(Vector2(size.x - 4.0, 2.0), strip, 0.62, tape)
	if ears:
		_tape(Vector2(size.x * 0.5, -1.0), Vector2(clampf(size.x * 0.16, 44.0, 84.0), 16.0), -0.03, tape)
	if paws and size.y > 90.0:
		_paw(Vector2(size.x - 20.0, size.y - 18.0), 0.7, Color(Palette.INK_LINE, 0.16))


## Owner-coloured tape for a card that belongs to someone, the plain roll for
## everything else. Tape is translucent, so what it holds shows through.
func _tape_colour() -> Color:
	var base: Color = Palette.TAPE.lerp(accent, 0.5) if accent.s > 0.2 else Palette.TAPE
	# Mostly opaque: over the night sky a see-through strip read as a grey bar.
	return Color(base.lightened(0.28), 0.9)


## A strip of tape centred on `at`, rotated `angle`, with the torn ends drawn as
## a shallow zigzag.
func _tape(at: Vector2, extent: Vector2, angle: float, colour: Color) -> void:
	var half := extent * 0.5
	var points := PackedVector2Array()
	points.append(Vector2(-half.x, -half.y))
	points.append(Vector2(half.x, -half.y))
	for step in 4:
		var y := -half.y + extent.y * float(step + 1) / 4.0
		points.append(Vector2(half.x + (2.0 if step % 2 == 0 else 0.0), y))
	points.append(Vector2(-half.x, half.y))
	for step in 4:
		var y := half.y - extent.y * float(step + 1) / 4.0
		points.append(Vector2(-half.x - (2.0 if step % 2 == 0 else 0.0), y))
	var transform := Transform2D(angle, at)
	draw_colored_polygon(transform * points, colour)


func _paw(at: Vector2, factor: float, colour: Color) -> void:
	draw_circle(at + Vector2(0, 3) * factor, 5 * factor, colour, true, -1.0, true)
	for toe in [Vector2(-7, -3), Vector2(-2.5, -8), Vector2(3, -8), Vector2(8, -3)]:
		draw_circle(at + toe * factor, 2.8 * factor, colour, true, -1.0, true)
