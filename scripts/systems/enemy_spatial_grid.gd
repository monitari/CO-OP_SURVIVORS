class_name EnemySpatialGrid
extends RefCounted

var cell_size := 192.0
var cells: Dictionary = {}


func rebuild(enemies: Array[ChaserEnemy]) -> void:
	cells.clear()
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or not enemy.active:
			continue
		var key := _cell_key(enemy.global_position)
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(enemy)


func query_radius(origin: Vector2, radius: float) -> Array[ChaserEnemy]:
	var results: Array[ChaserEnemy] = []
	var minimum := _cell_key(origin - Vector2.ONE * radius)
	var maximum := _cell_key(origin + Vector2.ONE * radius)
	var radius_squared := radius * radius
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			var key := Vector2i(x, y)
			if not cells.has(key):
				continue
			for candidate in cells[key]:
				var enemy := candidate as ChaserEnemy
				if is_instance_valid(enemy) and not enemy.dead and enemy.global_position.distance_squared_to(origin) <= radius_squared:
					results.append(enemy)
	return results


func nearest(origin: Vector2, radius: float, excluded: Array[ChaserEnemy] = []) -> ChaserEnemy:
	var nearest_enemy: ChaserEnemy
	var nearest_distance := radius * radius
	for enemy in query_radius(origin, radius):
		if enemy in excluded:
			continue
		var distance := enemy.global_position.distance_squared_to(origin)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_enemy = enemy
	return nearest_enemy


func _cell_key(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))

