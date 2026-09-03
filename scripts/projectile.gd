class_name HomingProjectile
extends Node2D

signal released(projectile: HomingProjectile)

var target: ChaserEnemy
var direction := Vector2.RIGHT
var speed := 470.0
var turn_speed := 7.0
var damage := 22.0
var lifetime := 3.2
var radius := 8.0
var projectile_color := Color("43d9ff")
var homing_enabled := true
var remaining_hits := 1
var hit_enemy_ids: Dictionary = {}
var spatial_grid: EnemySpatialGrid
var active := false


func setup(start_direction: Vector2, initial_target: ChaserEnemy) -> void:
	speed = 470.0
	turn_speed = 7.0
	damage = 22.0
	lifetime = 3.2
	radius = 8.0
	projectile_color = Color("43d9ff")
	homing_enabled = true
	remaining_hits = 1
	hit_enemy_ids.clear()
	direction = start_direction.normalized()
	target = initial_target
	active = true
	visible = true
	set_physics_process(true)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not active:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		release()
		return
	if homing_enabled and (not is_instance_valid(target) or target.dead):
		target = _find_nearest_enemy()
	if homing_enabled and is_instance_valid(target):
		var desired := global_position.direction_to(target.global_position)
		direction = direction.lerp(desired, minf(1.0, turn_speed * delta)).normalized()
	position += direction * speed * delta
	rotation = direction.angle()

	var candidates: Array = spatial_grid.query_radius(global_position, radius + 32.0) if spatial_grid != null else get_tree().get_nodes_in_group("enemies")
	for candidate in candidates:
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead or hit_enemy_ids.has(enemy.get_instance_id()):
			continue
		if global_position.distance_to(enemy.global_position) <= radius + enemy.radius:
			hit_enemy_ids[enemy.get_instance_id()] = true
			enemy.take_damage(damage)
			remaining_hits -= 1
			if remaining_hits <= 0:
				release()
				return


func release() -> void:
	if not active:
		return
	active = false
	visible = false
	set_physics_process(false)
	released.emit(self)


func _find_nearest_enemy() -> ChaserEnemy:
	if spatial_grid != null:
		return spatial_grid.nearest(global_position, 900.0)
	var nearest: ChaserEnemy
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _draw() -> void:
	draw_line(Vector2(-22.0, 0.0), Vector2(-7.0, 0.0), Color(projectile_color, 0.28), radius, true)
	draw_circle(Vector2.ZERO, radius + 5.0, Color(projectile_color, 0.18))
	draw_circle(Vector2.ZERO, radius, projectile_color)
