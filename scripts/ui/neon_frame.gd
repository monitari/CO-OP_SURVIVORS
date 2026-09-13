extends Control
## Resolution-independent neon trim; decorative children never intercept input.
var accent := Color("35dbff")
var active := false
var ears := false
var paws := true
var age := 0.0
var last_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	age += delta
	if active or size != last_size:
		last_size = size
		queue_redraw()

func _draw() -> void:
	var pulse := 0.88 + sin(age * 2.0) * 0.12 if active else 0.65
	for layer in range(4, 0, -1):
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color.TRANSPARENT
		glow.border_color = Color(accent, 0.035 * pulse)
		glow.set_border_width_all(layer * 3)
		glow.set_corner_radius_all(16 + layer)
		glow.corner_detail = 12
		draw_style_box(glow, Rect2(Vector2.ONE * -layer * 1.4, size + Vector2.ONE * layer * 2.8))
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color.TRANSPARENT
	edge.border_color = Color(accent.lightened(0.3), 0.95 if active else 0.7)
	edge.set_border_width_all(2 if active else 1)
	edge.set_corner_radius_all(14)
	edge.corner_detail = 12
	draw_style_box(edge, Rect2(Vector2.ZERO, size))
	draw_line(Vector2(20, 4), Vector2(size.x * 0.38, 4), Color(accent, pulse), 2, true)
	draw_line(Vector2(size.x * 0.62, size.y - 4), Vector2(size.x - 20, size.y - 4), Color(accent, pulse), 2, true)
	if paws and size.y > 90:
		_paw(Vector2(17, 20), 0.75)
		_paw(Vector2(size.x - 17, 20), 0.75)
	if ears:
		var x := size.x * 0.5
		var points := PackedVector2Array([Vector2(x - 37, 0), Vector2(x - 30, -20), Vector2(x - 15, -9), Vector2(x + 15, -9), Vector2(x + 30, -20), Vector2(x + 37, 0)])
		draw_polyline(points, Color(accent, pulse), 3, true)
		draw_circle(Vector2(x - 7, -3), 1.8, accent)
		draw_circle(Vector2(x + 7, -3), 1.8, accent)
	for corner in [Vector2(7, 10), Vector2(size.x - 7, size.y - 10)]:
		draw_line(corner - Vector2(4, 0), corner + Vector2(4, 0), Color.WHITE, 1, true)
		draw_line(corner - Vector2(0, 4), corner + Vector2(0, 4), accent, 1, true)

func _paw(at: Vector2, factor: float) -> void:
	draw_circle(at + Vector2(0, 3) * factor, 4 * factor, Color(accent, 0.75))
	for toe in [Vector2(-6, -2), Vector2(-2, -6), Vector2(3, -6), Vector2(7, -2)]:
		draw_circle(at + toe * factor, 2.4 * factor, Color(accent, 0.8))
