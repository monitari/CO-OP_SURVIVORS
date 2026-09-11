class_name CombatFlare
extends Node2D

var primary := Color.WHITE
var secondary := Color("fff275")
var radius := 150.0
var lifetime := 0.48
var elapsed := 0.0
var spokes := 8
var glow: GlowLayer


func setup(effect_position: Vector2, first: Color, second: Color, effect_radius := 150.0, effect_lifetime := 0.48) -> void:
	position = effect_position
	primary = first
	secondary = second
	radius = effect_radius
	lifetime = effect_lifetime
	z_index = 4 # Below enemies and their danger telegraphs, above friendly rings.
	glow = GlowLayer.attach(self, _paint_glow)
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	scale = Vector2.ONE * lerpf(0.42, 1.16, ease(progress, -1.8))
	rotation = progress * 0.55
	modulate.a = 1.0 - ease(progress, 2.2)
	queue_redraw()
	if glow != null:
		glow.queue_redraw()
	if elapsed >= lifetime:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 0.14, Color(primary, 0.2))
	for ring_index in 3:
		var ring_radius := radius * (0.42 + ring_index * 0.25)
		var offset := ring_index * 0.42
		for quarter in 4:
			var start := offset + quarter * TAU / 4.0
			draw_arc(Vector2.ZERO, ring_radius, start, start + 0.58, 12, Color(primary if ring_index != 1 else secondary, 0.86 - ring_index * 0.16), 5.0 - ring_index, true)
	for index in spokes:
		var direction := Vector2.from_angle(TAU * float(index) / float(spokes))
		var tangent := direction.orthogonal()
		var inner := direction * radius * 0.18
		var outer := direction * radius * (0.55 if index % 2 == 0 else 0.4)
		draw_line(inner, outer, Color(secondary, 0.72), 3.0, true)
		draw_colored_polygon(PackedVector2Array([
			outer + direction * 11.0,
			outer + tangent * 5.0,
			outer - direction * 7.0,
			outer - tangent * 5.0,
		]), Color(secondary, 0.82))


## An explosion is the one thing on the roof that briefly out-lights the moon,
## so the hot centre and the spark tips emit and the rings do not. Pushing the
## rings into the glow as well was the version that turned a mine field into a
## white sheet: eight flares at once added to far past white and took the
## enemies standing in them with it.
func _paint_glow(layer: GlowLayer) -> void:
	layer.draw_circle(Vector2.ZERO, radius * 0.60, Moonlight.glow(primary, 0.11))
	layer.draw_circle(Vector2.ZERO, radius * 0.26, Moonlight.glow(secondary, 0.32))
	for index in spokes:
		var direction := Vector2.from_angle(TAU * float(index) / float(spokes))
		var outer := direction * radius * (0.55 if index % 2 == 0 else 0.4)
		layer.draw_circle(outer + direction * 6.0, radius * 0.085, Moonlight.glow(secondary, 0.26))
