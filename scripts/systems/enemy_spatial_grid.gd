class_name EnemySpatialGrid
extends RefCounted

var cell_size := 192.0
var cells: Dictionary = {}
var occupied_min := Vector2i.ZERO
var occupied_max := Vector2i.ZERO


func rebuild(enemies: Array[ChaserEnemy]) -> void:
	cells.clear()
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or not enemy.active:
			continue
		var key := _cell_key(enemy.global_position)
		if cells.is_empty():
			occupied_min = key
			occupied_max = key
		else:
			occupied_min = occupied_min.min(key)
			occupied_max = occupied_max.max(key)
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(enemy)


func query_radius(origin: Vector2, radius: float) -> Array[ChaserEnemy]:
	var results: Array[ChaserEnemy] = []
	if cells.is_empty(): return results
	var minimum := _cell_key(origin - Vector2.ONE * radius).max(occupied_min)
	var maximum := _cell_key(origin + Vector2.ONE * radius).min(occupied_max)
	var radius_squared := radius * radius
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			var key := Vector2i(x, y)
			if not cells.has(key):
				continue
			for candidate in cells[key]:
				if not is_instance_valid(candidate): continue
				var enemy := candidate as ChaserEnemy
				if is_instance_valid(enemy) and not enemy.dead and enemy.global_position.distance_squared_to(origin) <= radius_squared:
					results.append(enemy)
	return results


func nearest(origin: Vector2, radius: float, excluded: Array[ChaserEnemy] = []) -> ChaserEnemy:
	var nearest_enemy: ChaserEnemy
	var nearest_distance := radius * radius
	if cells.is_empty(): return null
	var minimum := _cell_key(origin - Vector2.ONE * radius).max(occupied_min)
	var maximum := _cell_key(origin + Vector2.ONE * radius).min(occupied_max)
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for candidate in cells.get(Vector2i(x, y), []):
				if not is_instance_valid(candidate): continue
				var enemy := candidate as ChaserEnemy
				if not is_instance_valid(enemy) or enemy.dead or enemy in excluded: continue
				var distance := enemy.global_position.distance_squared_to(origin)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_enemy = enemy
	return nearest_enemy


func _cell_key(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))
