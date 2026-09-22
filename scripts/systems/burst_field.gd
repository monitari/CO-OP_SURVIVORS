class_name BurstField
extends Node2D

## Killing three hundred enemies a run used to produce a sound and a gem and
## nothing else — the single largest gap between what the game does and what it
## feels like it does. Every burst lives in this one node and is drawn in one
## pass, so a screenful of simultaneous deaths costs one _draw() rather than a
## node, a tween and a redraw each.

const MAX_BURSTS := 48
const SHARDS := 6

var bursts: Array = []


## `weight` scales the burst: an ordinary chaser gets a small pop, an elite or
## the boss gets something you cannot miss.
func spawn(at: Vector2, color: Color, weight: float = 1.0) -> void:
	# Under a heavy wave the oldest burst is the one nobody is still looking at.
	if bursts.size() >= MAX_BURSTS:
		bursts.pop_front()
	bursts.append({
		"position": at,
		"color": color,
		"age": 0.0,
		"life": 0.26 + weight * 0.1,
		"radius": 14.0 * weight,
		"seed": randf() * TAU,
	})
	queue_redraw()


func step(delta: float) -> void:
	if bursts.is_empty():
		return
	var survivors: Array = []
	for burst in bursts:
		burst["age"] = float(burst["age"]) + delta
		if float(burst["age"]) < float(burst["life"]):
			survivors.append(burst)
	bursts = survivors
	queue_redraw()


func clear_all() -> void:
	if bursts.is_empty():
		return
	bursts.clear()
	queue_redraw()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:burst_field", probe_started)


func _probed_draw() -> void:
	for burst in bursts:
		var progress := clampf(float(burst["age"]) / float(burst["life"]), 0.0, 1.0)
		var fade := 1.0 - progress
		var color := Color(burst["color"] as Color, fade * 0.85)
		var origin := burst["position"] as Vector2
		var base_radius := float(burst["radius"])
		# The instant of the kill: a hot core for the first sliver of the burst,
		# gone before the ring has spread. It is what makes the pop read as a pop
		# rather than as a ring appearing.
		var core := 1.0 - clampf(progress / 0.28, 0.0, 1.0)
		if core > 0.0:
			draw_circle(origin, base_radius * (0.35 + 0.5 * core), Color(1.0, 0.98, 0.9, 0.7 * core))
		draw_arc(origin, base_radius * (0.6 + progress * 1.9), 0.0, TAU, 18, color, 3.0 * fade + 0.6, true)
		var start_angle := float(burst["seed"])
		for index in SHARDS:
			var angle := start_angle + TAU * float(index) / float(SHARDS)
			var direction := Vector2.from_angle(angle)
			var inner := origin + direction * base_radius * (0.5 + progress * 1.5)
			var outer := inner + direction * base_radius * 0.55 * fade
			draw_line(inner, outer, color, 2.5 * fade + 0.5, true)
