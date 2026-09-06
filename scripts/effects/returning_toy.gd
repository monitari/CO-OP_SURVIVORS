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
const TOY_TEXTURE := preload("res://assets/art/unified/weapons/boomerang.png")
const LIFETIME := 1.65
## Where the toy is along its path, as a multiple of `reach`. One and a half
## turns of a sine: out to +1, home through 0, and on to -1 where it is let go.
const SWEEP := PI * 1.5
const HIT_RADIUS := 22.0


func _physics_process(delta: float) -> void:
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
		enemy.take_damage(damage)
	queue_redraw()
	if progress >= 1.0:
		queue_free()


func _draw() -> void:
	var progress := age / LIFETIME
	var alpha := minf(1.0, (1.0 - progress) * 5.0)
	# A short trail behind whichever way it is currently travelling, so the
	# moment it turns around is visible rather than inferred.
	var travelling := signf(cos(progress * SWEEP))
	draw_line(Vector2.ZERO, -heading.rotated(-rotation) * travelling * 34.0, Color(tint, alpha * 0.28), 10.0, true)
	draw_set_transform(Vector2.ZERO, age * 9.0)
	draw_texture_rect(TOY_TEXTURE, Rect2(-24, -24, 48, 48), false, Color(1, 1, 1, alpha))
