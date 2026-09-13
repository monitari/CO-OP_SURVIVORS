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

## Moon-fish turned out to be far easier to come by than this price list was
## written for: a clear pays eight, every chest the pair cannot use pays more,
## and a couple of runs therefore bought the entire board — after which the shop
## was a screen with nothing on it. Every rank now costs `base_cost + rank *
## cost_step` rather than `base_cost + rank`, and both numbers are several times
## what they were, so the whole board is a long-term project instead of a
## weekend's shopping. The first rank of the cheap lines is still inside one
## clear, which is what keeps a first visit worth making.
const UPGRADES := [
	{"id": "vitality", "name": "튼튼한 심장", "max_rank": 8, "base_cost": 3, "cost_step": 3, "summary": "최대 체력 +3%"},
	{"id": "might", "name": "날카로운 발톱", "max_rank": 8, "base_cost": 4, "cost_step": 4, "summary": "피해량 +2%"},
	{"id": "haste", "name": "빠른 수염", "max_rank": 8, "base_cost": 4, "cost_step": 4, "summary": "발동 간격 -1.5%"},
	{"id": "move", "name": "가벼운 발걸음", "max_rank": 8, "base_cost": 3, "cost_step": 3, "summary": "이동 속도 +1.5%"},
	{"id": "magnet", "name": "별빛 주머니", "max_rank": 6, "base_cost": 6, "cost_step": 4, "summary": "자력 +4%"},
	{"id": "luck", "name": "행운의 꼬리", "max_rank": 4, "base_cost": 10, "cost_step": 8, "summary": "행운 +1"},
	{"id": "armor", "name": "단단한 털", "max_rank": 6, "base_cost": 5, "cost_step": 4, "summary": "방어 +0.3"},
	{"id": "recovery", "name": "느긋한 숨", "max_rank": 6, "base_cost": 6, "cost_step": 5, "summary": "초당 재생 +0.05"},
	{"id": "crit", "name": "사냥꾼의 눈", "max_rank": 6, "base_cost": 5, "cost_step": 4, "summary": "치명타 확률 +1%"},
	{"id": "area", "name": "커다란 발자국", "max_rank": 6, "base_cost": 4, "cost_step": 4, "summary": "공격 범위 +2%"},
	{"id": "duration", "name": "오래가는 마법", "max_rank": 6, "base_cost": 4, "cost_step": 4, "summary": "지속 시간 +2%"},
	{"id": "resolve", "name": "든든한 동료", "max_rank": 6, "base_cost": 4, "cost_step": 3, "summary": "구조 능력 +0.5"},
]

var save_path := SAVE_PATH
var points := 0
var ranks: Dictionary = {}
var discoveries: Dictionary = {}
var last_save_error: Error = OK


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
	last_save_error = config.save(save_path)
	return last_save_error


func award_clear() -> int:
	return award(CLEAR_REWARD)


## Moon-fish from anywhere else. A chest opened by a pair who already own
## everything it could have contained pays out here instead of finding something
## to inflate, so the box is never a disappointment and the run still banks
## something the next one keeps.
func award(amount: int) -> int:
	var granted := maxi(0, amount)
	if granted <= 0:
		return 0
	points += granted
	if save_progress() != OK:
		points -= granted
		return 0
	return granted


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func cost(id: String) -> int:
	var entry := by_id(id)
	if entry.is_empty() or rank(id) >= int(entry["max_rank"]):
		return 0
	return int(entry["base_cost"]) + rank(id) * int(entry.get("cost_step", 1))


func purchase(id: String) -> bool:
	var price := cost(id)
	if price <= 0 or points < price:
		last_save_error = OK
		return false
	points -= price
	ranks[id] = rank(id) + 1
	if save_progress() != OK:
		points += price
		ranks[id] = rank(id) - 1
		return false
	return true


func refund_value() -> int:
	var total := 0
	for entry in UPGRADES:
		var count := rank(String(entry["id"]))
		total += count * int(entry["base_cost"]) + count * (count - 1) / 2 * int(entry.get("cost_step", 1))
	return total


func reset_upgrades() -> bool:
	var previous := ranks.duplicate()
	var refund := refund_value()
	for id in ranks:
		ranks[id] = 0
	points += refund
	if save_progress() != OK:
		ranks = previous
		points -= refund
		return false
	return true


func mark_discovered(fusion_id: String) -> void:
	if fusion_id.is_empty() or discoveries.has(fusion_id):
		return
	discoveries[fusion_id] = true
	if save_progress() != OK:
		discoveries.erase(fusion_id)


func is_discovered(fusion_id: String) -> bool:
	return discoveries.has(fusion_id)


func apply_to_player(player: ChainPlayer) -> void:
	var health_scale := 1.0 + float(rank("vitality")) * 0.03
	player.max_health *= health_scale
	player.health = player.max_health
	player.might *= 1.0 + float(rank("might")) * 0.02
	player.haste *= 1.0 - float(rank("haste")) * 0.015
	player.move_speed *= 1.0 + float(rank("move")) * 0.015
	player.armor += rank("armor") * 0.3
	player.recovery += rank("recovery") * 0.05
	player.crit_chance += rank("crit") * 0.01
	player.area *= 1.0 + rank("area") * 0.02
	player.duration *= 1.0 + rank("duration") * 0.02
	player.resolve += rank("resolve") * 0.5


func team_magnet_bonus() -> float:
	return float(rank("magnet")) * 0.04


func team_luck_bonus() -> int:
	return rank("luck")


static func by_id(id: String) -> Dictionary:
	for entry in UPGRADES:
		if String(entry["id"]) == id:
			return entry
	return {}
