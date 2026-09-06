class_name EnemyProjectile
extends Node2D

## Knocked out of the air by a friendly weapon rather than reaching anyone. Main
## listens so the hit gets sparks and a cue: a shot that simply vanished would
## read as the weapon having missed it.
signal broken(at: Vector2)

var direction := Vector2.RIGHT
var speed := 245.0
var damage := 10.0
var lifetime := 4.0
var players: Array[ChainPlayer] = []


func setup(origin: Vector2, travel_direction: Vector2, projectile_damage: float, targets: Array[ChainPlayer]) -> void:
	position = origin
	direction = travel_direction.normalized()
	damage = projectile_damage
	players = targets
	rotation = direction.angle()


## Set by main while 멈춘 회중시계 is running. A time stop that froze the
## enemies but let their shots keep travelling would be the worst of both.
var frozen := false


func _physics_process(delta: float) -> void:
	if frozen:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	position += direction * speed * delta
	for player in players:
		if global_position.distance_to(player.global_position) <= 10.0 + player.radius:
			player.hurt(damage)
			queue_free()
			return


## Takes this shot out of the air.
func shatter() -> void:
	broken.emit(global_position)
	queue_free()


## Knocks every shot in `shots` inside the circle down, and prunes entries whose
## projectile has already gone. Static and array-driven because two systems need
## exactly this loop — the controller for the weapons that strike once, and the
## field for the ones that sweep — and neither owns the list.
static func break_within(shots: Array, point: Vector2, radius: float) -> int:
	var broken_count := 0
	for index in range(shots.size() - 1, -1, -1):
		var candidate = shots[index]
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			shots.remove_at(index)
			continue
		var shot := candidate as EnemyProjectile
		if shot == null:
			shots.remove_at(index)
			continue
		if point.distance_squared_to(shot.global_position) > radius * radius:
			continue
		shots.remove_at(index)
		shot.shatter()
		broken_count += 1
	return broken_count


## The same thing along a segment, for the weapon that is a line between the two
## survivors rather than a circle around one of them.
static func break_along(shots: Array, from: Vector2, to: Vector2, width: float) -> int:
	var segment := to - from
	var length_squared := segment.length_squared()
	var broken_count := 0
	for index in range(shots.size() - 1, -1, -1):
		var candidate = shots[index]
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			shots.remove_at(index)
			continue
		var shot := candidate as EnemyProjectile
		if shot == null:
			shots.remove_at(index)
			continue
		var at := shot.global_position
		var nearest := from
		if length_squared > 0.001:
			nearest = from + segment * clampf((at - from).dot(segment) / length_squared, 0.0, 1.0)
		if nearest.distance_squared_to(at) > width * width:
			continue
		shots.remove_at(index)
		shot.shatter()
		broken_count += 1
	return broken_count


func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.25, 0.35, 0.2))
	draw_circle(Vector2.ZERO, 6.0, Color("ff5d8f"))
	# Crow's thrown pebble: bright hostile outline remains the damage cue.
	draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(1, -4), Vector2(-4, -2), Vector2(-3, 4), Vector2(2, 4)]), Color("f5c995"))
