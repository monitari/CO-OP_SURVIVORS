class_name FieldItemSystem
extends Node2D

## Spawns and recycles walk-over pickups, mirroring how ExperienceSystem pools
## gems. Deliberately has no magnet: a drop is only worth taking if the pair is
## willing to move the chain to it.

signal item_collected(item_id: String)

const FieldItemScript := preload("res://scripts/field_item.gd")

## Weights are relative, not percentages. Healing is the common one because it
## is the safety valve; the screen-clearing purge is the rare payoff.
const ITEM_TABLE := [
	{"id": "heal", "weight": 4, "color": "80ed99", "name": "결속의 양식"},
	{"id": "magnet", "weight": 3, "color": "43d9ff", "name": "자력 파동"},
	{"id": "chain_repair", "weight": 2, "color": "fff275", "name": "사슬 정비"},
	{"id": "purge", "weight": 1, "color": "ff5d8f", "name": "정화의 불꽃"},
]

var active_items: Array[FieldItem] = []
var item_pool: Array[FieldItem] = []
var pickup_radius := 30.0


## Picks a drop type by weight. Kept separate from spawning so tests can check
## the table without needing a live scene.
func roll_item_id() -> String:
	var total := 0
	for entry in ITEM_TABLE:
		total += int(entry["weight"])
	var roll := randi() % total
	for entry in ITEM_TABLE:
		roll -= int(entry["weight"])
		if roll < 0:
			return String(entry["id"])
	return String(ITEM_TABLE[0]["id"])


func item_display_name(item_id: String) -> String:
	for entry in ITEM_TABLE:
		if String(entry["id"]) == item_id:
			return String(entry["name"])
	return item_id


func item_color(item_id: String) -> Color:
	for entry in ITEM_TABLE:
		if String(entry["id"]) == item_id:
			return Color(String(entry["color"]))
	return Color.WHITE


func spawn_item(spawn_position: Vector2, item_id: String) -> FieldItem:
	var item: FieldItem
	if item_pool.is_empty():
		item = FieldItemScript.new() as FieldItem
		add_child(item)
	else:
		item = item_pool.pop_back()
	item.activate(spawn_position, item_id, item_color(item_id))
	active_items.append(item)
	return item


func step(players: Array[ChainPlayer], delta: float) -> void:
	for candidate in active_items.duplicate():
		var item := candidate as FieldItem
		if not is_instance_valid(item) or not item.active:
			continue
		if item.step(delta):
			_recycle(item)
			continue
		for player in players:
			if player.downed:
				continue
			if item.global_position.distance_to(player.global_position) <= pickup_radius + player.radius:
				item_collected.emit(item.item_id)
				_recycle(item)
				break


func clear_all() -> void:
	for candidate in active_items.duplicate():
		var item := candidate as FieldItem
		if is_instance_valid(item):
			_recycle(item)


func _recycle(item: FieldItem) -> void:
	active_items.erase(item)
	item.deactivate()
	if item not in item_pool:
		item_pool.append(item)
