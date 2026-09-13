class_name RooftopPropField
extends Node
## Sparse, deterministic 2.5D furniture for the endless run roof.
##
## The floor used to paint every crate and vent into one canvas below the
## actors. Giving each solid its own node lets the shared y-sorted stage place
## a cat behind or in front of it while the gameplay plane stays unobstructed.

const PropScript := preload("res://scripts/entities/rooftop_prop.gd")
const CELL := 512
const RANGE := 2300.0
const RETIRE_RANGE := 2900.0
const HOME_LAYOUT := [
	["vent", Vector2(-525.0, 235.0)],
	["vent", Vector2(505.0, -235.0)],
	["duct", Vector2(440.0, 380.0)],
	["crate", Vector2(-455.0, -265.0)],
]

var stage: Node2D
var props: Dictionary = {} ## Vector2i -> RooftopProp
var last_cell := Vector2i(999999, 999999)


func configure(sorted_stage: Node2D) -> void:
	stage = sorted_stage


func follow(centre: Vector2) -> void:
	if not is_instance_valid(stage):
		return
	var centre_cell := Vector2i(int(floor(centre.x / CELL)), int(floor(centre.y / CELL)))
	if centre_cell == last_cell:
		return
	last_cell = centre_cell
	var radius := int(ceil(RANGE / CELL))
	var wanted: Dictionary = {}
	# Four authored landmarks frame the opening without occupying its central
	# movement lesson. Unlike supply planters these are scenery and drop nothing.
	for index in HOME_LAYOUT.size():
		var home: Array = HOME_LAYOUT[index]
		var key := "home:%d" % index
		var at := home[1] as Vector2
		if at.distance_squared_to(centre) > RANGE * RANGE:
			continue
		wanted[key] = true
		if not props.has(key) or not is_instance_valid(props[key]):
			_spawn(key, String(home[0]), at, 1000 + index)
	for cell_x in range(centre_cell.x - radius, centre_cell.x + radius + 1):
		for cell_y in range(centre_cell.y - radius, centre_cell.y + radius + 1):
			var cell := Vector2i(cell_x, cell_y)
			var entry := _entry(cell)
			if entry.is_empty():
				continue
			var at: Vector2 = entry["at"]
			if at.distance_squared_to(centre) > RANGE * RANGE:
				continue
			wanted[cell] = true
			if props.has(cell) and is_instance_valid(props[cell]):
				continue
			_spawn(cell, String(entry["kind"]), at, int(entry["variant"]))

	for cell in props.keys():
		var prop = props[cell]
		if not is_instance_valid(prop):
			props.erase(cell)
			continue
		if not wanted.has(cell) and (prop as RooftopProp).ground.distance_squared_to(centre) > RETIRE_RANGE * RETIRE_RANGE:
			(prop as RooftopProp).queue_free()
			props.erase(cell)


func living_props() -> Array[RooftopProp]:
	var living: Array[RooftopProp] = []
	for value in props.values():
		if is_instance_valid(value):
			living.append(value as RooftopProp)
	return living


func clear_all() -> void:
	for prop in props.values():
		if is_instance_valid(prop):
			(prop as RooftopProp).queue_free()
	props.clear()
	last_cell = Vector2i(999999, 999999)


func _spawn(key: Variant, kind: String, at: Vector2, variant: int) -> void:
	var prop := PropScript.new() as RooftopProp
	prop.setup(kind, at, variant)
	prop.scale = Vector2.ONE * 0.72
	prop.modulate = Color(0.70, 0.76, 0.80, 0.68)
	stage.add_child(prop)
	props[key] = prop


func _entry(cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi((cell.x * 73856093) ^ (cell.y * 19349663)) + 20260905
	if rng.randf() > 0.44:
		return {}
	var at := Vector2(
		cell.x * CELL + rng.randf_range(60.0, CELL - 140.0),
		cell.y * CELL + rng.randf_range(60.0, CELL - 140.0)
	)
	if absf(at.x) < 560.0 and absf(at.y) < 350.0:
		return {}
	var roll := rng.randi() % 5
	# Slot zero remains free for WaveDirector's breakable supply planter.
	if roll == 0:
		return {}
	var kinds := ["crate", "vent", "duct", "vent"]
	return {"kind": kinds[roll - 1], "at": at, "variant": int(rng.randi())}


## Fade before a prop hides a survivor or their immediate combat space. Use
## smooth distance weighting, not binary overlap, so crossing it never pops.
func update_visibility(players: Array[ChainPlayer], delta: float) -> void:
	for prop in living_props():
		var clearance := INF
		var centre := prop.screen_rect().get_center()
		for player in players:
			clearance = minf(clearance, centre.distance_to(player.global_position))
		if players.size() == 2:
			var closest := Geometry2D.get_closest_point_to_segment(
				centre, players[0].global_position, players[1].global_position)
			clearance = minf(clearance, centre.distance_to(closest))
		var weight := smoothstep(95.0, 230.0, clearance)
		var target := lerpf(0.10, 0.68, weight)
		prop.modulate.a = lerpf(prop.modulate.a, target, 1.0 - exp(-delta * 10.0))
