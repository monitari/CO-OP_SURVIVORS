class_name EvolutionCatalog
extends RefCounted

## The middle rung of the tech tree: base weapon → fused weapon → resonance.
##
## A weapon fuses when it is maxed out AND its owner carries the right treasure
## deep enough. That is deliberately two commitments rather than one — the
## treasure requirement is what makes the four treasure slots a build decision
## instead of a stat shop, because picking 관통의 송곳 is also picking the fusion
## it unlocks. Character selection and every level-up expose both requirements.
##
## A fused weapon is not the base weapon with bigger numbers. Each one changes
## how the attack is delivered — a chain becomes a storm that hits everything at
## once, a cone becomes a full circle, a single mine becomes a ring of them —
## and only fused weapons can reach resonance.

## Six weapon upgrades and four treasure picks stand between a starting
## weapon and its fusion. At T5/T3 a fusion arrived while the pair was still
## learning the run and resonance followed almost immediately after, which
## left the whole top of the tree with nothing to be the climax of.
const WEAPON_MAX_TIER := 7
const REQUIRED_TREASURE_TIER := 4


static func all_evolutions() -> Array[Dictionary]:
	return [
		{
			"base_weapon_id": "homing",
			"treasure_id": "pierce",
			"weapon_id": "starpiercer",
			"weapon_name": "성좌 관통포",
			"tags": ["projectile", "tracking", "arcane", "burst"],
			"description": "유도탄이 관통 광선을 끌고 다니며 지나간 자리를 모두 꿰뚫습니다.",
			"weapon": {"damage": 33.0, "cooldown": 0.72, "count": 3, "speed": 500.0, "range": 445.0, "width": 23.0, "reach": 1.0},
		},
		{
			"base_weapon_id": "lightning",
			"treasure_id": "haste",
			"weapon_id": "thunder_god",
			"weapon_name": "뇌신의 격노",
			"tags": ["lightning", "storm", "chain", "burst"],
			"description": "연쇄를 버리고 사거리 안의 모든 적을 동시에 내리칩니다.",
			"weapon": {"damage": 27.0, "cooldown": 1.28, "range": 480.0, "reach": 2.05},
		},
		{
			"base_weapon_id": "flame",
			"treasure_id": "area",
			"weapon_id": "supernova",
			"weapon_name": "초신성",
			"tags": ["fire", "projectile", "burst", "aura"],
			"description": "불씨를 흩뿌린 뒤 그 자리에서 거대한 2차 폭발을 일으킵니다.",
			"weapon": {"damage": 25.0, "cooldown": 1.46, "count": 12, "speed": 325.0, "radius": 205.0, "reach": 2.4},
		},
		{
			"base_weapon_id": "frost",
			"treasure_id": "armor",
			"weapon_id": "absolute_zero",
			"weapon_name": "절대영도",
			"tags": ["frost", "control", "aura", "burst"],
			"description": "상시 냉기를 두르고, 오라 안에서 이미 얼어붙은 적을 계속 파쇄합니다.",
			"weapon": {"damage": 23.0, "cooldown": 1.78, "radius": 228.0, "slow": 0.14, "reach": 3.5},
		},
		{
			"base_weapon_id": "scythe",
			"treasure_id": "might",
			"weapon_id": "black_moon",
			"weapon_name": "흑월참",
			"tags": ["melee", "shadow", "arc", "burst"],
			"description": "부채꼴을 버리고 몸 주위를 두 번 완전히 베어냅니다.",
			"weapon": {"damage": 50.0, "cooldown": 1.15, "range": 238.0, "arc": 6.28, "reach": 1.05},
		},
		{
			"base_weapon_id": "chain",
			"treasure_id": "recovery",
			"weapon_id": "stigmata",
			"weapon_name": "성흔의 사슬",
			"tags": ["tether", "holy", "aura", "arcane"],
			"description": "사슬이 성흔으로 타오르며 적을 태우고 두 사람을 함께 회복시킵니다.",
			"weapon": {"damage": 38.0, "cooldown": 1.08, "width": 82.0, "heal": 2.2, "reach": 1.5},
		},
		{
			"base_weapon_id": "orbit",
			"treasure_id": "amount",
			"weapon_id": "celestial",
			"weapon_name": "천구 의식",
			"tags": ["arcane", "aura", "control", "holy"],
			"description": "안팎으로 반대로 도는 두 겹의 궤도가 주변을 통째로 갈아냅니다.",
			"weapon": {"damage": 17.0, "cooldown": 5.5, "count": 5, "radius": 104.0, "speed": 3.0, "reach": 3.0},
		},
		{
			"base_weapon_id": "lance",
			"treasure_id": "crit",
			"weapon_id": "judgement",
			"weapon_name": "심판의 창",
			"tags": ["projectile", "holy", "burst", "arc"],
			"description": "정면과 양 측면을 동시에 꿰뚫는 세 갈래 심판을 내립니다.",
			"weapon": {"damage": 45.0, "cooldown": 1.28, "range": 530.0, "width": 34.0, "reach": 1.15},
		},
		{
			"base_weapon_id": "mine",
			"treasure_id": "thorns",
			"weapon_id": "ruin_garden",
			"weapon_name": "파멸의 정원",
			"tags": ["control", "burst", "shadow", "aura"],
			"description": "한 발이 아니라 결계 한 무리를 원형으로 심어 둘 주위를 밭으로 만듭니다.",
			"weapon": {"damage": 34.0, "cooldown": 2.05, "count": 5, "radius": 84.0, "reach": 1.75},
		},
		{
			"base_weapon_id": "boomerang",
			"treasure_id": "projectile_speed",
			"weapon_id": "skipping_stone",
			"weapon_name": "물수제비 물고기",
			"tags": ["projectile", "tracking", "burst", "arc"],
			"description": "장난감이 한 번 왕복하는 대신 사방으로 튕기며 계속 지나갑니다.",
			"weapon": {"damage": 42.0, "cooldown": 1.95, "range": 320.0, "count": 3, "reach": 2.3},
		},
		{
			"base_weapon_id": "milk",
			"treasure_id": "magnet",
			"weapon_id": "cream_tide",
			"weapon_name": "크림 해일",
			"tags": ["aura", "control", "holy", "storm"],
			"description": "웅덩이가 아니라 밀려오는 해일이 되어 바닥을 통째로 덮습니다.",
			"weapon": {"damage": 19.0, "cooldown": 2.6, "range": 360.0, "count": 7, "radius": 92.0, "slow": 0.45, "reach": 7.4},
		},
		{
			"base_weapon_id": "gravity",
			"treasure_id": "vitality",
			"weapon_id": "event_horizon",
			"weapon_name": "사건의 지평선",
			"tags": ["arcane", "storm", "control", "burst"],
			"description": "끌어모은 자리를 한 번 더 무너뜨려 두 번 붕괴시킵니다.",
			"weapon": {"damage": 27.0, "cooldown": 1.92, "radius": 216.0, "pull": 200.0, "reach": 3.0},
		},
	]


static func for_base(base_weapon_id: String) -> Dictionary:
	for evolution in all_evolutions():
		if String(evolution["base_weapon_id"]) == base_weapon_id:
			return evolution
	return {}


static func by_weapon_id(weapon_id: String) -> Dictionary:
	for evolution in all_evolutions():
		if String(evolution["weapon_id"]) == weapon_id:
			return evolution
	return {}


static func is_evolved(weapon_id: String) -> bool:
	return not by_weapon_id(weapon_id).is_empty()


## The carried form. It keeps the slot the base weapon occupied and inherits the
## owning character's colour, so a fused weapon still reads as belonging to the
## survivor who built it.
static func build_state(evolution: Dictionary, base_state: Dictionary) -> Dictionary:
	var state: Dictionary = (evolution["weapon"] as Dictionary).duplicate(true)
	state["weapon_id"] = String(evolution["weapon_id"])
	state["weapon_name"] = String(evolution["weapon_name"])
	state["tags"] = (evolution["tags"] as Array).duplicate()
	state["color"] = base_state["color"]
	state["source_character"] = base_state.get("source_character", "")
	state["base_weapon_id"] = String(evolution["base_weapon_id"])
	state["evolved"] = true
	state["tier"] = WEAPON_MAX_TIER
	return state
