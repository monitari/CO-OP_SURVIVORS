class_name ExperienceSystem
extends Node2D

signal experience_collected(amount: int)

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

## Every kill drops its own gem, which on its own is unbounded: an automated
## fifteen-minute run left 1,987 of them lying on the roof and still climbing,
## each one a node redrawing itself every frame. So a drop that lands on top of
## a gem already on the floor merges into it, and once the field is carrying
## MAX_ACTIVE the next drop merges into the nearest gem however far that is.
##
## Nothing is ever thrown away — the gem simply gets heavier and, if the new
## drop outranks it, brighter. The pair still sees a drop for every kill; what
## they stop seeing is a thousand separate specks none of which was worth
## walking to.
const MERGE_RADIUS := 46.0
const MAX_ACTIVE := 320


func spawn_gem(spawn_position: Vector2, value: int, grade := -1) -> void:
	var gem: ExperienceGem
	if gem_pool.is_empty():
		gem = GemScript.new() as ExperienceGem
		add_child(gem)
	else:
		gem = gem_pool.pop_back()
	if grade < 0:
		grade = 3 if value >= 100 else (2 if value >= 24 else (1 if value >= 7 else 0))
	var host := _merge_target(spawn_position)
	if host != null:
		host.absorb(value, grade)
		return
	gem.activate(spawn_position, value, grade)
	active_gems.append(gem)


## The gem a new drop should join, or null when it deserves its own node.
## Magnetised gems are never merge targets: they are already on their way home,
## so pouring a fresh drop into one would teleport it to the players.
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
	if nearest_distance <= MERGE_RADIUS * MERGE_RADIUS:
		return nearest
	return nearest if active_gems.size() >= MAX_ACTIVE else null


func step(players: Array[ChainPlayer], delta: float) -> void:
	for candidate in active_gems.duplicate():
		var gem := candidate as ExperienceGem
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
			_collect(gem)


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


func _collect(gem: ExperienceGem) -> void:
	active_gems.erase(gem)
	experience_collected.emit(gem.value)
	gem.deactivate()
	gem_pool.append(gem)
