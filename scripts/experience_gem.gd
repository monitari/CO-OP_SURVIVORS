class_name ExperienceGem
extends Node2D

var value := 5
var active := false
var velocity := Vector2.ZERO
## Set by the magnet field item. A magnetised gem ignores the pickup radius
## entirely and flies home from wherever it is on the map.
var magnetized := false


func activate(spawn_position: Vector2, experience_value: int) -> void:
	position = spawn_position
	value = experience_value
	velocity = Vector2.ZERO
	magnetized = false
	active = true
	visible = true
	scale = Vector2.ONE
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false
	velocity = Vector2.ZERO
	magnetized = false


func _draw() -> void:
	var points := PackedVector2Array([Vector2(0, -8), Vector2(6, 0), Vector2(0, 8), Vector2(-6, 0)])
	if magnetized:
		# A pulled gem is visibly in transit, so a map-wide magnet reads as a
		# stream of experience arriving rather than a number changing.
		draw_circle(Vector2.ZERO, 15.0, Color(0.55, 0.95, 0.65, 0.28))
	draw_colored_polygon(points, Color("80ed99"))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color.WHITE, 1.5, true)

