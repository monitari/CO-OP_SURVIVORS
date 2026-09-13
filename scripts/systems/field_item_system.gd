class_name FieldItemSystem
extends Node2D

## Spawns and recycles walk-over pickups, mirroring how ExperienceSystem pools
## gems. Deliberately has no magnet: a drop is only worth taking if the pair is
## willing to move the chain to it.

signal item_collected(item_id: String, collector_index: int)

const FieldItemScript := preload("res://scripts/entities/field_item.gd")

## These sum to 100, so the weights are also readable as percentages. Healing
## and collection help stay common; rule-breaking windows are rarer, and the
## view-clearing purge is held to 3% because it can erase a boss.
## Four drops meant a run of twenty-odd pickups was the same four things over
## and over. Seven is enough that finding one is a question ("what did we get?")
## rather than a formality, and the three additions are deliberately the two
## fantasies a survivors game owes a player — being untouchable for a moment,
## and stopping the world — plus a short window where the pair simply hits much
## harder. All three are timed rather than instant: an item you have to *spend*
## well is worth walking to.
const ITEM_TABLE := [
	{"id": "heal", "weight": 28, "color": "80ed99", "name": "참치캔 간식"},
	{"id": "magnet", "weight": 22, "color": "43d9ff", "name": "수염 자석"},
	{"id": "chain_ward", "weight": 15, "color": "fff275", "name": "황금 목줄"},
	{"id": "guard", "weight": 10, "color": "9bf6ff", "name": "아홉 목숨 방울"},
	{"id": "frenzy", "weight": 14, "color": "ff9770", "name": "광란의 마타타비"},
	{"id": "time_stop", "weight": 8, "color": "c77dff", "name": "멈춘 털실시계"},
	{"id": "purge", "weight": 3, "color": "ff5d8f", "name": "냥냥 대청소"},
]

const CHEST_ENTRY := {"id": "chest", "color": "ffd166", "name": "수염 상자"}

var active_items: Array[FieldItem] = []
var item_pool: Array[FieldItem] = []
var pickup_radius := 30.0


## Picks a drop type by weight. Kept separate from spawning so tests can check
## the table without needing a live scene.
func roll_item_id(luck: float = 0.0) -> String:
	var total := 0.0
	var weights: Array[float] = []
	for entry in ITEM_TABLE:
		var weight := float(entry["weight"])
		if String(entry["id"]) in ["guard", "frenzy", "time_stop", "purge"]:
			weight *= 1.0 + minf(2.0, maxf(0.0, luck) * 0.06)
		weights.append(weight)
		total += weight
	var roll := randf() * total
	for index in ITEM_TABLE.size():
		var entry: Dictionary = ITEM_TABLE[index]
		roll -= weights[index]
		if roll < 0:
			return String(entry["id"])
	return String(ITEM_TABLE[0]["id"])


func item_display_name(item_id: String) -> String:
	if item_id == "chest":
		return String(CHEST_ENTRY["name"])
	for entry in ITEM_TABLE:
		if String(entry["id"]) == item_id:
			return String(entry["name"])
	return item_id


func item_color(item_id: String) -> Color:
	if item_id == "chest":
		return Color(String(CHEST_ENTRY["color"]))
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
				item_collected.emit(item.item_id, player.player_index - 1)
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
