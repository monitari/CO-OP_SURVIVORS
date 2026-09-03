class_name ExperienceSystem
extends Node2D

signal experience_collected(amount: int)

const GemScript := preload("res://scripts/experience_gem.gd")

var active_gems: Array[ExperienceGem] = []
var gem_pool: Array[ExperienceGem] = []
var magnet_radius := 155.0
var pickup_radius := 34.0


func spawn_gem(spawn_position: Vector2, value: int) -> void:
	var gem: ExperienceGem
	if gem_pool.is_empty():
		gem = GemScript.new() as ExperienceGem
		add_child(gem)
	else:
		gem = gem_pool.pop_back()
	gem.activate(spawn_position, value)
	active_gems.append(gem)


func step(players: Array[ChainPlayer], delta: float) -> void:
	for candidate in active_gems.duplicate():
		var gem := candidate as ExperienceGem
		if not is_instance_valid(gem) or not gem.active:
			continue
		var nearest: ChainPlayer = players[0]
		if gem.global_position.distance_squared_to(players[1].global_position) < gem.global_position.distance_squared_to(players[0].global_position):
			nearest = players[1]
		var distance: float = gem.global_position.distance_to(nearest.global_position)
		if distance <= magnet_radius:
			var speed := lerpf(170.0, 760.0, 1.0 - clampf(distance / magnet_radius, 0.0, 1.0))
			gem.position += gem.global_position.direction_to(nearest.global_position) * speed * delta
		if gem.global_position.distance_to(nearest.global_position) <= pickup_radius + nearest.radius:
			_collect(gem)


func _collect(gem: ExperienceGem) -> void:
	active_gems.erase(gem)
	experience_collected.emit(gem.value)
	gem.deactivate()
	gem_pool.append(gem)
