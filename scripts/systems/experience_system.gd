class_name ExperienceSystem
extends Node2D

signal experience_collected(amount: int, collector_index: int)

const GemScript := preload("res://scripts/entities/experience_gem.gd")

var active_gems: Array[ExperienceGem] = []
var gem_pool: Array[ExperienceGem] = []
## A magnetised gem is given a travel time rather than a speed, so a gem four
## thousand pixels out arrives in about the same beat as one just off screen.
## Speed-based pulling made the far ones take ten seconds, by which point the
## item that caused it was long forgotten.
const MAGNET_ITEM_TRAVEL := 0.85
const MAGNET_ITEM_MIN_SPEED := 700.0
const MAGNET_ITEM_MAX_SPEED := 4200.0

var magnet_radius := 155.0
var pickup_radius := 34.0

## A crowded kill used to merge into an existing gem inside 46px. Its value was
## preserved, but the new drop never appeared, so two overlapping bodies looked
## as if only one of them paid experience. Below the field budget every kill now
## gets a visible gem and crowded drops fan out just enough to read separately.
## At the hard cap values still merge into the nearest gem, keeping the late-run
## node and draw budget bounded without losing any experience.
const DROP_SPACING := 18.0
const DROP_SCATTER_STEP := 16.0
const DROP_SCATTER_CANDIDATES := 24
const MAX_ACTIVE := 320


func spawn_gem(spawn_position: Vector2, value: int, grade := -1) -> void:
	if grade < 0:
		grade = 3 if value >= 100 else (2 if value >= 24 else (1 if value >= 7 else 0))
	# Merge only at the cap. Before it, every enemy gets a distinct, visible
	# payout even when several bodies die on the same pixel.
	var host := _merge_target(spawn_position) if active_gems.size() >= MAX_ACTIVE else null
	if host != null:
		host.absorb(value, grade)
		return
	var visible_position := _separated_drop_position(spawn_position)
	var gem: ExperienceGem
	if gem_pool.is_empty():
		gem = GemScript.new() as ExperienceGem
		add_child(gem)
	else:
		gem = gem_pool.pop_back()
	gem.activate(visible_position, value, grade)
	active_gems.append(gem)


## Finds a free nearby point for a crowded drop. The golden-angle walk avoids
## rows and keeps a whole pack's payout centred on where the pack died.
func _separated_drop_position(at: Vector2) -> Vector2:
	if _drop_position_is_clear(at):
		return at
	var phase := float(active_gems.size()) * 2.399963
	for index in range(1, DROP_SCATTER_CANDIDATES + 1):
		var ring := ceili(float(index) / 6.0)
		var candidate := at + Vector2.from_angle(phase + float(index) * 2.399963) \
			* DROP_SCATTER_STEP * float(ring)
		if _drop_position_is_clear(candidate):
			return candidate
	return at + Vector2.from_angle(phase) * DROP_SCATTER_STEP * 5.0


func _drop_position_is_clear(at: Vector2) -> bool:
	for candidate in active_gems:
		var gem := candidate as ExperienceGem
		if (is_instance_valid(gem) and gem.active
				and gem.global_position.distance_squared_to(at) < DROP_SPACING * DROP_SPACING):
			return false
	return true


## The gem a capped field should join. Magnetised gems are never merge targets:
## they are already on their way home, so a fresh drop must not teleport into
## the pickup stream.
func _merge_target(at: Vector2) -> ExperienceGem:
	var nearest: ExperienceGem = null
	var nearest_distance := INF
	for candidate in active_gems:
		var gem := candidate as ExperienceGem
		if not is_instance_valid(gem) or not gem.active or gem.magnetized:
			continue
		var distance := gem.global_position.distance_squared_to(at)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = gem
	if nearest == null:
		return null
	return nearest


func step(players: Array[ChainPlayer], delta: float) -> void:
	for index in range(active_gems.size() - 1, -1, -1):
		var gem := active_gems[index] as ExperienceGem
		if not is_instance_valid(gem) or not gem.active:
			continue
		var nearest: ChainPlayer = players[0]
		if gem.global_position.distance_squared_to(players[1].global_position) < gem.global_position.distance_squared_to(players[0].global_position):
			nearest = players[1]
		var distance: float = gem.global_position.distance_to(nearest.global_position)
		if gem.magnetized:
			# No radius at all: a magnetised gem is coming home from across the
			# map, accelerating as it closes so the stream arrives as a rush
			# rather than a uniform drift.
			var pull := clampf(distance / MAGNET_ITEM_TRAVEL, MAGNET_ITEM_MIN_SPEED, MAGNET_ITEM_MAX_SPEED)
			gem.position += gem.global_position.direction_to(nearest.global_position) * pull * delta
		elif distance <= magnet_radius:
			var speed := lerpf(170.0, 760.0, 1.0 - clampf(distance / magnet_radius, 0.0, 1.0))
			gem.position += gem.global_position.direction_to(nearest.global_position) * speed * delta
		if gem.global_position.distance_to(nearest.global_position) <= pickup_radius + nearest.radius:
			_collect_at(index, gem, nearest.player_index - 1)


## Puts every gem on the map into flight toward the nearest survivor. It used to
## bank them instantly, which meant the single most satisfying item in the game
## produced no image at all — a number moved and that was it. They now stream in
## over about a second, and the count returned is what is on its way.
func magnetize_all() -> int:
	var pulled := 0
	for candidate in active_gems.duplicate():
		var gem := candidate as ExperienceGem
		if not is_instance_valid(gem) or not gem.active or gem.magnetized:
			continue
		gem.magnetized = true
		gem.queue_redraw()
		pulled += 1
	return pulled


func _collect_at(index: int, gem: ExperienceGem, collector_index := -1) -> void:
	active_gems.remove_at(index)
	experience_collected.emit(gem.value, collector_index)
	gem.deactivate()
	gem_pool.append(gem)
