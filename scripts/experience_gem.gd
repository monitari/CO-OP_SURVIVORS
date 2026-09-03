class_name ExperienceGem
extends Node2D

var value := 5
var active := false
var velocity := Vector2.ZERO


func activate(spawn_position: Vector2, experience_value: int) -> void:
	position = spawn_position
	value = experience_value
	velocity = Vector2.ZERO
	active = true
	visible = true
	scale = Vector2.ONE
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false
	velocity = Vector2.ZERO


func _draw() -> void:
	var points := PackedVector2Array([Vector2(0, -8), Vector2(6, 0), Vector2(0, 8), Vector2(-6, 0)])
	draw_colored_polygon(points, Color("80ed99"))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color.WHITE, 1.5, true)

