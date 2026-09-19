class_name EnemyProjectile
extends Node2D

## Knocked out of the air by a friendly weapon rather than reaching anyone. Main
## listens so the hit gets sparks and a cue: a shot that simply vanished would
## read as the weapon having missed it.
signal broken(at: Vector2)
## Emitted once when this shot leaves play, however it left — timed out, hit
## somebody, or was knocked down. main listens and parks the node in its pool.
signal released(shot: EnemyProjectile)

var direction := Vector2.RIGHT
var speed := 245.0
var damage := 10.0
var lifetime := 4.0
var players: Array[ChainPlayer] = []
## Live rather than freed. A shooter-heavy late wave fires a few hundred of
## these a minute, and every one used to be a node allocation and a queue_free;
## the list they were kept in was only ever swept while a time stop was running,
## so in an ordinary run it grew for twenty-five minutes and everything that
## walks it — the batch renderer every frame, the AI companion every tick —
## walked thousands of dead references.
var active := false
## Set by main while the node sits in its pool, so a double release is a flag
## test rather than a search.
var pooled := false


func setup(origin: Vector2, travel_direction: Vector2, projectile_damage: float, targets: Array[ChainPlayer]) -> void:
	position = origin
	direction = travel_direction.normalized()
	damage = projectile_damage
	players = targets
	rotation = direction.angle()
	lifetime = 4.0
	frozen = false
	active = true
	visible = true


## Set by main while 멈춘 회중시계 is running. A time stop that froze the
## enemies but let their shots keep travelling would be the worst of both.
var frozen := false


## One tick of travel. Returns true once the shot has left play.
##
## Driven by main's own loop rather than by a per-node physics callback: the
## callback is a separate trip from the engine into the script for every shot in
## the air, and the body of it is four lines.
func step(delta: float) -> bool:
	if not active:
		return true
	if frozen:
		return false
	lifetime -= delta
	if lifetime <= 0.0:
		release()
		return true
	position += direction * speed * delta
	for player in players:
		if global_position.distance_to(player.global_position) <= 10.0 + player.radius:
			player.hurt(damage)
			release()
			return true
	return false


## Takes this shot out of the air.
func shatter() -> void:
	if not active:
		return
	broken.emit(global_position)
	release()


## Leaves play without a break effect. Idempotent.
func release() -> void:
	if not active:
		return
	active = false
	visible = false
	released.emit(self)


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
		if shot == null or not shot.active:
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
		if shot == null or not shot.active:
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
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:enemy_projectile", probe_started)


func _probed_draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.25, 0.35, 0.2))
	draw_circle(Vector2.ZERO, 6.0, Color("ff5d8f"))
	# Crow's thrown pebble: bright hostile outline remains the damage cue.
	draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(1, -4), Vector2(-4, -2), Vector2(-3, 4), Vector2(2, 4)]), Color("f5c995"))
