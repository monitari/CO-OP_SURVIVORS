class_name MetaProgression
extends RefCounted

## Small, capped bonuses bought with moon-fish earned at the end of a clear.
## The save owns discoveries too: a fusion is a silhouette until the player has
## actually made it once, then its real icon/name may be used in future runs.

const SAVE_PATH := "user://moonroof_progression.cfg"
## The headless tests drive whole runs, and a run that completes a fusion records
## the discovery — into the player's own save, because that is the only path this
## knew about. A suite run therefore marked fusions as found that nobody had
## made. It cuts the other way too: once a player has bought ranks, every balance
## instrument in tests/ would be measuring a stronger pair than it thinks it is.
## Pointing this at a scratch file keeps the two apart. Named like the other test
## switches the suite already uses.
const PATH_OVERRIDE_ENV := "CHAINBOUND_PROGRESSION_PATH"
const SECTION := "progression"
const DISCOVERY_SECTION := "fusion_discoveries"
const CLEAR_REWARD := 8

const UPGRADES := [
	{"id": "vitality", "name": "튼튼한 심장", "max_rank": 8, "base_cost": 1, "summary": "최대 체력 +3%"},
	{"id": "might", "name": "날카로운 발톱", "max_rank": 8, "base_cost": 1, "summary": "피해량 +2%"},
	{"id": "haste", "name": "빠른 수염", "max_rank": 8, "base_cost": 1, "summary": "발동 간격 -1.5%"},
	{"id": "move", "name": "가벼운 발걸음", "max_rank": 8, "base_cost": 1, "summary": "이동 속도 +1.5%"},
	{"id": "magnet", "name": "별빛 주머니", "max_rank": 6, "base_cost": 2, "summary": "자력 +4%"},
	{"id": "luck", "name": "행운의 꼬리", "max_rank": 4, "base_cost": 3, "summary": "행운 +1"},
]

var save_path := SAVE_PATH
var points := 0
var ranks: Dictionary = {}
var discoveries: Dictionary = {}


func _init() -> void:
	var override := OS.get_environment(PATH_OVERRIDE_ENV).strip_edges()
	if not override.is_empty():
		save_path = override
	for entry in UPGRADES:
		ranks[String(entry["id"])] = 0


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	points = maxi(0, int(config.get_value(SECTION, "points", 0)))
	for entry in UPGRADES:
		var id := String(entry["id"])
		ranks[id] = clampi(int(config.get_value(SECTION, id, 0)), 0, int(entry["max_rank"]))
	for key in config.get_section_keys(DISCOVERY_SECTION):
		if bool(config.get_value(DISCOVERY_SECTION, key, false)):
			discoveries[String(key)] = true


func save_progress() -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, "points", points)
	for entry in UPGRADES:
		var id := String(entry["id"])
		config.set_value(SECTION, id, rank(id))
	for fusion_id in discoveries:
		config.set_value(DISCOVERY_SECTION, String(fusion_id), true)
	return config.save(save_path)


func award_clear() -> int:
	points += CLEAR_REWARD
	save_progress()
	return CLEAR_REWARD


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func cost(id: String) -> int:
	var entry := by_id(id)
	if entry.is_empty() or rank(id) >= int(entry["max_rank"]):
		return 0
	return int(entry["base_cost"]) + rank(id)


func purchase(id: String) -> bool:
	var price := cost(id)
	if price <= 0 or points < price:
		return false
	points -= price
	ranks[id] = rank(id) + 1
	save_progress()
	return true


func mark_discovered(fusion_id: String) -> void:
	if fusion_id.is_empty() or discoveries.has(fusion_id):
		return
	discoveries[fusion_id] = true
	save_progress()


func is_discovered(fusion_id: String) -> bool:
	return discoveries.has(fusion_id)


func apply_to_player(player: ChainPlayer) -> void:
	var health_scale := 1.0 + float(rank("vitality")) * 0.03
	player.max_health *= health_scale
	player.health = player.max_health
	player.might *= 1.0 + float(rank("might")) * 0.02
	player.haste *= 1.0 - float(rank("haste")) * 0.015
	player.move_speed *= 1.0 + float(rank("move")) * 0.015


func team_magnet_bonus() -> float:
	return float(rank("magnet")) * 0.04


func team_luck_bonus() -> int:
	return rank("luck")


static func by_id(id: String) -> Dictionary:
	for entry in UPGRADES:
		if String(entry["id"]) == id:
			return entry
	return {}
