class_name EnemyProjectile
extends Node2D

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


func _physics_process(delta: float) -> void:
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


func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.25, 0.35, 0.2))
	draw_circle(Vector2.ZERO, 6.0, Color("ff5d8f"))
	# Crow's thrown pebble: bright hostile outline remains the damage cue.
	draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(1, -4), Vector2(-4, -2), Vector2(-3, 4), Vector2(2, 4)]), Color("f5c995"))
