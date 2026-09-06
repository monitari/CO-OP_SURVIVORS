class_name ExperienceGem
extends Node2D

var value := 5
var grade := 0 ## 0 mote, 1 shard, 2 prism, 3 core
var active := false
var velocity := Vector2.ZERO
## Set by the magnet field item. A magnetised gem ignores the pickup radius
## entirely and flies home from wherever it is on the map.
var magnetized := false


func _ready() -> void:
	# Pooled/inactive gems do no frame work. activate() turns processing back on.
	visible = false
	set_process(false)


func activate(spawn_position: Vector2, experience_value: int, experience_grade := 0) -> void:
	position = spawn_position
	value = experience_value
	grade = clampi(experience_grade, 0, 3)
	velocity = Vector2.ZERO
	magnetized = false
	active = true
	visible = true
	scale = Vector2.ONE
	z_index = 1
	set_process(true)
	queue_redraw()


## Takes another drop into this one. Used when a kill lands on top of a gem
## that is already lying there: the experience is added rather than given its
## own node, and the silhouette rises to the better of the two so the pile
## still reads as the best thing in it.
func absorb(extra_value: int, extra_grade: int) -> void:
	value += extra_value
	grade = clampi(maxi(grade, extra_grade), 0, 3)
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false
	velocity = Vector2.ZERO
	magnetized = false
	set_process(false)


func _process(_delta: float) -> void:
	# Valuable drops breathe and rotate gently; the silhouette still carries
	# the grade when colour is hard to distinguish.
	rotation += (0.55 + grade * 0.22) * _delta
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006 + grade) * (0.025 + grade * 0.012)
	scale = Vector2.ONE * pulse
	if grade >= 2 or magnetized:
		queue_redraw()


func _draw() -> void:
	var colors := [Color("80ed99"), Color("43d9ff"), Color("ffd166"), Color("ff8fab")]
	var names := [4, 6, 8, 10]
	var radius := 6.0 + grade * 2.4
	var points := PackedVector2Array()
	var sides: int = names[grade]
	for index in sides:
		var r := radius if index % 2 == 0 or grade < 2 else radius * 0.58
		points.append(Vector2.from_angle(-PI * 0.5 + TAU * float(index) / sides) * r)
	if magnetized:
		# A pulled gem is visibly in transit, so a map-wide magnet reads as a
		# stream of experience arriving rather than a number changing.
		draw_circle(Vector2.ZERO, radius + 7.0, Color(colors[grade], 0.24))
	if grade >= 2:
		draw_circle(Vector2.ZERO, radius + 5.0, Color(colors[grade], 0.12 + sin(Time.get_ticks_msec() * 0.008) * 0.04))
	draw_colored_polygon(points, colors[grade])
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color.WHITE, 1.5 + grade * 0.25, true)
	if grade == 3:
		draw_circle(Vector2.ZERO, 3.2, Color.WHITE)
