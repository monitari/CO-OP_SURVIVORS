extends Node2D

## A chain attack should read as a flexible, charged tether rather than a
## rectangular beam. The two filled ribbons twist around one another while
## bright knots race from survivor to survivor.

var span := Vector2.RIGHT * 100.0
var curve := PackedVector2Array()
var half_width := 40.0
var tint := Color("80ed99")
var age := 0.0
var glow: GlowLayer
const LIFETIME := 0.42


func setup(from: Vector2, to: Vector2, width: float, color := Color("80ed99")) -> void:
	global_position = from
	span = to - from
	curve = PackedVector2Array([Vector2.ZERO, span])
	half_width = maxf(8.0, width)
	tint = color
	z_index = 3
	glow = GlowLayer.attach(self, _paint_glow)
	queue_redraw()


func setup_path(points: PackedVector2Array, width: float, color := Color("80ed99")) -> void:
	if points.size() < 2:
		return
	global_position = points[0]
	curve.clear()
	for point in points:
		curve.append(point - global_position)
	span = curve[curve.size() - 1]
	half_width = maxf(8.0, width)
	tint = color
	z_index = 3
	glow = GlowLayer.attach(self, _paint_glow)
	queue_redraw()


func _process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_process(delta)
	FrameProbe.add(&"render_strikes", probe_started)


func _probed_process(delta: float) -> void:
	age += delta
	queue_redraw()
	if glow != null:
		glow.queue_redraw()
	if age >= LIFETIME:
		queue_free()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:chain_strike", probe_started)


func _probed_draw() -> void:
	if curve.size() > 2:
		_draw_curved()
		return
	var length := span.length()
	if length <= 1.0:
		return
	var along := span / length
	var normal := along.orthogonal()
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var envelope := sin(progress * PI)
	var alpha := 1.0 - ease(progress, 2.0)

	# A broad, tapered energy body establishes the actual damage area.
	var body := _ribbon_points(along, normal, length, half_width * (0.78 + envelope * 0.22), age * 19.0)
	draw_colored_polygon(body, Color(tint, 0.22 * alpha))
	# Two thinner braids make it feel like linked energy instead of a flat bar.
	for phase in [-1.0, 1.0]:
		var braid := _ribbon_points(along, normal, length, half_width * 0.24, age * 24.0 + phase * PI * 0.5)
		draw_colored_polygon(braid, Color(tint.lightened(0.32), 0.64 * alpha))

	draw_circle(Vector2.ZERO, half_width * (0.45 + envelope * 0.15), Color(tint, 0.42 * alpha))
	draw_circle(span, half_width * (0.45 + envelope * 0.15), Color(tint, 0.42 * alpha))
	# Charged knots travel in opposite directions through the tether.
	for index in 5:
		var ratio := fmod(progress * 1.8 + float(index) / 5.0, 1.0)
		var at := span * ratio + normal * sin(ratio * TAU * 2.0 + age * 24.0) * half_width * 0.16
		_draw_diamond(at, 5.0 + envelope * 5.0, Color.WHITE, 0.9 * alpha)


func _draw_curved() -> void:
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var envelope := sin(progress * PI)
	var alpha := 1.0 - ease(progress, 2.0)
	# Polyline widths replace the old straight ribbon. Two counter-phase offset
	# paths retain the braided energy read while following every bend of the
	# physical leash.
	draw_polyline(curve, Color(tint, 0.22 * alpha), half_width * 1.55, true)
	for phase: float in [-1.0, 1.0]:
		var braid := PackedVector2Array()
		for index in curve.size():
			var ratio := float(index) / float(curve.size() - 1)
			var heading := _curve_heading(ratio)
			var wave := sin(ratio * TAU * 2.0 + age * 24.0 + phase * PI * 0.5)
			braid.append(curve[index] + heading.orthogonal() * wave * half_width * 0.18)
		draw_polyline(braid, Color(tint.lightened(0.32), 0.64 * alpha), half_width * 0.34, true)
	draw_circle(curve[0], half_width * (0.45 + envelope * 0.15), Color(tint, 0.42 * alpha))
	draw_circle(curve[curve.size() - 1], half_width * (0.45 + envelope * 0.15), Color(tint, 0.42 * alpha))
	for index in 5:
		var ratio := fmod(progress * 1.8 + float(index) / 5.0, 1.0)
		var at := _curve_point(ratio)
		var normal := _curve_heading(ratio).orthogonal()
		at += normal * sin(ratio * TAU * 2.0 + age * 24.0) * half_width * 0.16
		_draw_diamond(at, 5.0 + envelope * 5.0, Color.WHITE, 0.9 * alpha)


func _curve_point(ratio: float) -> Vector2:
	if curve.size() < 2:
		return span * ratio
	var step := clampf(ratio, 0.0, 1.0) * float(curve.size() - 1)
	var index := clampi(int(step), 0, curve.size() - 2)
	return curve[index].lerp(curve[index + 1], step - float(index))


func _curve_heading(ratio: float) -> Vector2:
	var run := _curve_point(minf(1.0, ratio + 0.04)) - _curve_point(maxf(0.0, ratio - 0.04))
	return run.normalized() if run.length_squared() > 0.001 else Vector2.RIGHT


func _ribbon_points(along: Vector2, normal: Vector2, length: float, width: float, phase: float) -> PackedVector2Array:
	var top := PackedVector2Array()
	const SEGMENTS := 14
	for index in SEGMENTS + 1:
		var ratio := float(index) / float(SEGMENTS)
		var taper := 0.55 + sin(ratio * PI) * 0.45
		var wave := sin(ratio * TAU * 2.0 + phase) * width * 0.22
		var centre := along * length * ratio + normal * wave
		top.append(centre + normal * width * taper)
	for index in range(SEGMENTS, -1, -1):
		var ratio := float(index) / float(SEGMENTS)
		var taper := 0.55 + sin(ratio * PI) * 0.45
		var wave := sin(ratio * TAU * 2.0 + phase) * width * 0.22
		var centre := along * length * ratio + normal * wave
		top.append(centre - normal * width * taper)
	return top


func _draw_diamond(at: Vector2, radius: float, color: Color, alpha: float) -> void:
	var points := PackedVector2Array([
		at + Vector2(0.0, -radius), at + Vector2(radius, 0.0),
		at + Vector2(0.0, radius), at + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, Color(color, alpha))


## The tether keeps its body and its braids; what emits is the charge running
## through it — the knots, and the two points it is anchored to. Same division
## the leash itself uses in ChainFlow, so the weapon and the chain that names
## this game read as the same material.
func _paint_glow(layer: GlowLayer) -> void:
	if curve.size() > 2:
		_paint_curved_glow(layer)
		return
	var length := span.length()
	if length <= 1.0:
		return
	var normal := (span / length).orthogonal()
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var envelope := sin(progress * PI)
	var alpha := 1.0 - ease(progress, 2.0)
	layer.draw_circle(Vector2.ZERO, half_width * (0.4 + envelope * 0.2), Moonlight.glow(tint, 0.24 * alpha))
	layer.draw_circle(span, half_width * (0.4 + envelope * 0.2), Moonlight.glow(tint, 0.24 * alpha))
	for index in 5:
		var ratio := fmod(progress * 1.8 + float(index) / 5.0, 1.0)
		var at := span * ratio + normal * sin(ratio * TAU * 2.0 + age * 24.0) * half_width * 0.16
		layer.draw_circle(at, 4.0 + envelope * 6.0, Moonlight.glow(tint.lightened(0.5), 0.30 * alpha))


func _paint_curved_glow(layer: GlowLayer) -> void:
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var envelope := sin(progress * PI)
	var alpha := 1.0 - ease(progress, 2.0)
	layer.draw_circle(curve[0], half_width * (0.4 + envelope * 0.2), Moonlight.glow(tint, 0.24 * alpha))
	layer.draw_circle(curve[curve.size() - 1], half_width * (0.4 + envelope * 0.2), Moonlight.glow(tint, 0.24 * alpha))
	for index in 5:
		var ratio := fmod(progress * 1.8 + float(index) / 5.0, 1.0)
		var at := _curve_point(ratio)
		var normal := _curve_heading(ratio).orthogonal()
		at += normal * sin(ratio * TAU * 2.0 + age * 24.0) * half_width * 0.16
		layer.draw_circle(at, 4.0 + envelope * 6.0, Moonlight.glow(tint.lightened(0.5), 0.30 * alpha))
