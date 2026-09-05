extends Node2D

## One clean filled stroke for the piercing lance. The old version stacked a
## polygon, halo line and core line, which became a bright slab when several
## beams fired together.

var span := Vector2.RIGHT * 500.0
var beam_width := 34.0
var tint := Color("caffbf")
var age := 0.0
const LIFETIME := 0.26


func setup(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	global_position = from
	span = to - from
	beam_width = maxf(6.0, width)
	tint = color
	z_index = 3
	queue_redraw()


func _process(delta: float) -> void:
	age += delta
	queue_redraw()
	if age >= LIFETIME:
		queue_free()


func _draw() -> void:
	if span.length_squared() <= 1.0:
		return
	var direction := span.normalized()
	var normal := direction.orthogonal()
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var alpha := 1.0 - ease(progress, 2.2)
	var pulse := 1.0 + sin(progress * PI) * 0.12
	var outer := PackedVector2Array([
		-normal * beam_width * 0.52 * pulse,
		normal * beam_width * 0.52 * pulse,
		span + normal * beam_width * 0.18,
		span + direction * beam_width * 0.62,
		span - normal * beam_width * 0.18,
	])
	draw_colored_polygon(outer, Color(tint, 0.42 * alpha))
	var core := PackedVector2Array([
		-normal * beam_width * 0.14,
		normal * beam_width * 0.14,
		span + normal * beam_width * 0.07,
		span + direction * beam_width * 0.35,
		span - normal * beam_width * 0.07,
	])
	draw_colored_polygon(core, Color(tint.lightened(0.55), 0.92 * alpha))
	draw_circle(Vector2.ZERO, beam_width * 0.22, Color(tint.lightened(0.4), 0.72 * alpha))
