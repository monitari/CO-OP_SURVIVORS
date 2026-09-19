extends Node2D

## 생선 부메랑. Thrown out, pulled back through the thrower, and then carried
## straight on out the far side — three passes from one cast.
##
## It used to stop dead the moment it got home, which made the second half of
## the arc a formality: the pair already knew the return path was the same path
## it had just cleared. Letting it keep going turns the throw into a line the
## survivor stands in the middle of, and makes which way you face at the moment
## of the cast the decision the weapon is actually about.

var anchor: ChainPlayer
var grid: EnemySpatialGrid
var heading := Vector2.RIGHT
var reach := 260.0
var damage := 30.0
var tint := Color("d59356")
var age := 0.0
var struck: Dictionary = {}
var source_player := -1
var source_weapon := ""
const LIFETIME := 1.65
## Where the toy is along its path, as a multiple of `reach`. One and a half
## turns of a sine: out to +1, home through 0, and on to -1 where it is let go.
const SWEEP := PI * 1.5
const HIT_RADIUS := 22.0


func _physics_process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_physics_process(delta)
	FrameProbe.add(&"toys", probe_started)


func _probed_physics_process(delta: float) -> void:
	if not is_instance_valid(anchor) or anchor.downed:
		queue_free()
		return
	age += delta
	var progress := minf(1.0, age / LIFETIME)
	var old_position := global_position
	global_position = anchor.global_position + heading * sin(progress * SWEEP) * reach
	# One hit per enemy per pass, so a body sitting on the line is hit three
	# times over the throw rather than once or continuously.
	var pass_index := mini(2, int(progress * 3.0))
	var travel := old_position.distance_to(global_position)
	for enemy in grid.query_radius(global_position, HIT_RADIUS + 48.0 + travel):
		if Geometry2D.get_closest_point_to_segment(enemy.global_position, old_position, global_position)\
				.distance_to(enemy.global_position) > enemy.radius + HIT_RADIUS:
			continue
		var key := "%d:%d" % [enemy.get_instance_id(), pass_index]
		if struck.has(key):
			continue
		struck[key] = true
		enemy.take_damage(damage, source_player, source_weapon)
	queue_redraw()
	if progress >= 1.0:
		queue_free()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:returning_toy", probe_started)


func _probed_draw() -> void:
	var progress := age / LIFETIME
	var alpha := minf(1.0, (1.0 - progress) * 5.0)
	# A short trail behind whichever way it is currently travelling, so the
	# moment it turns around is visible rather than inferred.
	var travelling := signf(cos(progress * SWEEP))
	draw_line(Vector2.ZERO, -heading.rotated(-rotation) * travelling * 34.0, Color(tint, alpha * 0.28), 10.0, true)
	draw_set_transform(Vector2.ZERO, age * 9.0)
	_draw_fish(alpha)


## The toy is drawn rather than blitted, for the same reason the star bolt and
## the ember are: it has to sit beside them on the same field without one of
## them looking like a sticker someone pasted on. Drawing it also lets it carry
## the thrower's colour — a picked-up 생선 부메랑 keeps the tint of whoever it
## came from — and costs the same as the one quad it replaces.
##
## Everything is in local coordinates around the toy's centre, nose along +X, so
## the spin above is the only transform involved.
const FISH_LENGTH := 19.0


func _draw_fish(alpha: float) -> void:
	var ink := Color(tint.darkened(0.62), alpha)
	var body_colour := Color(tint, alpha)
	var belly := Color(tint.lightened(0.62), alpha)
	draw_circle(Vector2.ZERO, FISH_LENGTH * 0.95, Color(tint, alpha * 0.14))
	var body := PackedVector2Array([
		Vector2(FISH_LENGTH, 0.0),
		Vector2(10.0, -7.6), Vector2(0.0, -8.6), Vector2(-8.0, -6.0),
		Vector2(-11.0, -3.4),
		# Forked tail: out to the top fluke, in to the notch, out to the bottom.
		Vector2(-FISH_LENGTH, -9.4), Vector2(-14.6, 0.0), Vector2(-FISH_LENGTH, 9.4),
		Vector2(-11.0, 3.4),
		Vector2(-8.0, 6.0), Vector2(0.0, 8.6), Vector2(10.0, 7.6),
	])
	# Fins first so the body outline closes over where they meet it.
	draw_colored_polygon(PackedVector2Array([
		Vector2(2.0, -7.4), Vector2(-3.5, -14.2), Vector2(-7.5, -6.4)]), Color(tint.darkened(0.18), alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(4.0, 3.2), Vector2(-1.5, 9.6), Vector2(-4.5, 3.2)]), Color(tint.darkened(0.18), alpha))
	draw_colored_polygon(body, body_colour)
	# A pale belly along the lower half, which is what makes it read as a fish
	# rather than as a leaf at the size this actually flies past at.
	draw_colored_polygon(PackedVector2Array([
		Vector2(13.0, 1.2), Vector2(0.0, 7.0), Vector2(-8.0, 4.6), Vector2(-9.5, 1.0)]), belly)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, ink, 2.2, true)
	draw_circle(Vector2(11.2, -2.4), 2.6, ink)
	draw_circle(Vector2(11.9, -3.1), 1.0, Color(Color.WHITE, alpha))
	# Gill line, one stroke, so the head end is distinguishable while it spins.
	draw_line(Vector2(6.4, -5.4), Vector2(5.2, 4.6), ink, 1.6, true)
