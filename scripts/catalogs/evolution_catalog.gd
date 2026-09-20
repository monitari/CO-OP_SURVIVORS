class_name EvolutionCatalog
extends RefCounted

const Growth := preload("res://scripts/systems/weapon_growth.gd")

## The middle rung of the tree: base weapon → enhanced weapon → resonance.
##
## A route names the treasure that completes it. Enhancement happens when both
## visible parts of that recipe are ready:
##
##     무기 레벨 >= 7 + 테크의 필수 보물 레벨 >= 4
##
## The route card, growth cards and full-stat sheet all print the same recipe,
## so the treasure is a build choice rather than a hidden failure state.
##
## The enhancement is also not a card any more. A weapon that reaches Lv.7
## enhances on the spot, because "you may now buy the thing you have already
## paid for" is not a decision — it was a card every player took every time,
## competing for a slot with cards they might actually have weighed.
##
## A fused weapon is not the base weapon with bigger numbers. Each one changes
## how the attack is delivered — a chain becomes a storm that hits everything at
## once, a cone becomes a full circle, a single mine becomes a ring of them —
## and only enhanced weapons can reach resonance.

## Six weapon upgrades stand between a starting weapon and its enhancement.
const EVOLUTION_TIER := 7
const REQUIRED_TREASURE_TIER := 4

## Where the numeric ladder actually stops, which is no longer where the
## enhancement happens. A weapon used to be finished the moment it enhanced: the
## enhancement stamped it at the ceiling and every card for that slot left the
## pool forever. Both survivors therefore ran dry around minute fifteen of a
## twenty-five minute run, sat on a maxed shared level, and spent the last third
## of the run with nothing to choose. An enhanced weapon now keeps climbing to
## EVOLUTION_TIER..WEAPON_MAX_TIER, so the enhancement is the middle of a
## weapon's life rather than the end of it.
const WEAPON_MAX_TIER := 12

## Every enhanced weapon carries exactly two tags and they never overlap in
## meaning: one says what it is made of, one says how it behaves. Four tags per
## weapon (the old shape) meant a pair could not look at two weapons and predict
## anything — almost every combination matched something, so resonance read as a
## slot machine rather than as a consequence of what they had built.
const PRIMARY_TAGS := ["fire", "frost", "lightning", "arcane", "shadow", "holy"]
const BEHAVIOR_TAGS := ["projectile", "melee", "chain", "aura", "tracking", "control", "explosion", "storm", "pierce"]


static func all_evolutions() -> Array[Dictionary]:
	return [
		{
			"base_weapon_id": "homing",
			"weapon_id": "starpiercer",
			"internal_id": "EVOLUTION_CONSTELLATION_CANNON",
			"weapon_name": "성좌 관통포",
			"primary_tag": "arcane",
			"behavior_tag": "pierce",
			"description": "유도탄이 관통 광선을 끌고 다니며 지나간 자리를 모두 꿰뚫습니다.",
			"weapon": {"damage": 29.0, "cooldown": 0.72, "count": 3, "speed": 500.0, "pierce": 1, "range": 480.0, "width": 32.0, "reach": 1.20},
		},
		{
			"base_weapon_id": "lightning",
			"weapon_id": "thunder_god",
			"internal_id": "EVOLUTION_THUNDER_GOD",
			"weapon_name": "뇌신의 격노",
			"primary_tag": "lightning",
			"behavior_tag": "storm",
			"description": "연쇄를 버리고 사거리 안의 모든 적을 동시에 내리칩니다.",
			"weapon": {"damage": 23.4, "cooldown": 1.28, "range": 520.0, "reach": 2.50},
		},
		{
			"base_weapon_id": "flame",
			"weapon_id": "supernova",
			"internal_id": "EVOLUTION_SUPERNOVA",
			"weapon_name": "초신성",
			"primary_tag": "fire",
			"behavior_tag": "explosion",
			"description": "불씨를 흩뿌린 뒤 그 자리에서 거대한 2차 폭발을 일으킵니다.",
			"weapon": {"damage": 21.2, "cooldown": 1.46, "count": 14, "speed": 325.0, "radius": 235.0, "reach": 2.75},
		},
		{
			"base_weapon_id": "frost",
			"weapon_id": "absolute_zero",
			"internal_id": "EVOLUTION_ABSOLUTE_ZERO",
			"weapon_name": "절대영도",
			"primary_tag": "frost",
			"behavior_tag": "aura",
			"description": "상시 냉기를 두르고, 오라 안에서 이미 얼어붙은 적을 계속 파쇄합니다.",
			"weapon": {"damage": 19.0, "cooldown": 1.78, "radius": 260.0, "slow": 0.14, "reach": 4.0},
		},
		{
			"base_weapon_id": "scythe",
			"weapon_id": "black_moon",
			"internal_id": "EVOLUTION_BLACK_MOON",
			"weapon_name": "흑월참",
			"primary_tag": "shadow",
			"behavior_tag": "melee",
			"description": "부채꼴을 버리고 몸 주위를 두 번 완전히 베어냅니다.",
			"weapon": {"damage": 46.0, "cooldown": 1.15, "range": 275.0, "arc": 6.28, "reach": 1.16},
		},
		{
			"base_weapon_id": "chain",
			"weapon_id": "stigmata",
			"internal_id": "EVOLUTION_STIGMATA",
			"weapon_name": "성흔의 사슬",
			"primary_tag": "holy",
			"behavior_tag": "chain",
			"description": "사슬이 성흔으로 타오르며 적을 태우고 두 사람을 함께 회복시킵니다.",
			"weapon": {"damage": 34.0, "cooldown": 1.08, "width": 105.0, "heal": 2.2, "reach": 1.65},
		},
		{
			"base_weapon_id": "orbit",
			"weapon_id": "celestial",
			"internal_id": "EVOLUTION_CELESTIAL_RITE",
			"weapon_name": "천구 의식",
			"primary_tag": "arcane",
			"behavior_tag": "aura",
			"description": "안팎으로 반대로 도는 두 겹의 궤도가 주변을 통째로 갈아냅니다.",
			"weapon": {"damage": 15.0, "cooldown": 5.5, "count": 5, "radius": 124.0, "speed": 3.0, "reach": 3.35},
		},
		{
			"base_weapon_id": "lance",
			"weapon_id": "judgement",
			"internal_id": "EVOLUTION_JUDGEMENT_LANCE",
			"weapon_name": "심판의 창",
			"primary_tag": "holy",
			"behavior_tag": "projectile",
			"description": "정면과 양 측면을 동시에 꿰뚫는 세 갈래 심판을 내립니다.",
			"weapon": {"damage": 41.0, "cooldown": 1.28, "range": 560.0, "width": 50.0, "reach": 1.25},
		},
		{
			"base_weapon_id": "mine",
			"weapon_id": "ruin_garden",
			"internal_id": "EVOLUTION_RUIN_GARDEN",
			"weapon_name": "파멸의 정원",
			"primary_tag": "shadow",
			"behavior_tag": "control",
			"description": "한 발이 아니라 결계 한 무리를 원형으로 심어 둘 주위를 밭으로 만듭니다.",
			"weapon": {"damage": 30.0, "cooldown": 2.05, "count": 5, "radius": 112.0, "reach": 2.10},
		},
		{
			"base_weapon_id": "boomerang",
			"weapon_id": "skipping_stone",
			"internal_id": "EVOLUTION_SKIPPING_STONE",
			"weapon_name": "물수제비 물고기",
			"primary_tag": "frost",
			"behavior_tag": "tracking",
			"description": "장난감이 한 번 왕복하는 대신 사방으로 튕기며 계속 지나갑니다.",
			"weapon": {"damage": 38.0, "cooldown": 1.95, "range": 385.0, "count": 3, "reach": 2.55},
		},
		{
			"base_weapon_id": "milk",
			"weapon_id": "cream_tide",
			"internal_id": "EVOLUTION_CREAM_TIDE",
			"weapon_name": "크림 해일",
			"primary_tag": "frost",
			"behavior_tag": "control",
			"description": "웅덩이가 아니라 밀려오는 해일이 되어 바닥을 통째로 덮습니다.",
			"weapon": {"damage": 16.0, "cooldown": 2.6, "range": 400.0, "count": 7, "radius": 120.0, "slow": 0.45, "reach": 8.7},
		},
		{
			"base_weapon_id": "gravity",
			"weapon_id": "event_horizon",
			"internal_id": "EVOLUTION_EVENT_HORIZON",
			"weapon_name": "사건의 지평선",
			"primary_tag": "arcane",
			"behavior_tag": "storm",
			"description": "끌어모은 자리를 한 번 더 무너뜨려 두 번 붕괴시킵니다.",
			"weapon": {"damage": 23.4, "cooldown": 1.92, "radius": 260.0, "pull": 240.0, "reach": 3.4},
		},
	]


## The two tags as a list, which is what resonance matching reads.
static func tags_of(evolution: Dictionary) -> Array:
	return [String(evolution["primary_tag"]), String(evolution["behavior_tag"])]


static func all_hybrid_evolutions() -> Array[Dictionary]:
	# Weapon + weapon recipes were retired. Kept as an empty compatibility API
	# for old tools and saves that may still ask for the former catalogue.
	return []


static func all_fusions() -> Array[Dictionary]:
	return all_evolutions()


static func for_base(base_weapon_id: String) -> Dictionary:
	for evolution in all_evolutions():
		if String(evolution["base_weapon_id"]) == base_weapon_id:
			return evolution
	return {}


static func by_weapon_id(weapon_id: String) -> Dictionary:
	for evolution in all_fusions():
		if String(evolution["weapon_id"]) == weapon_id:
			return evolution
	return {}


static func is_evolved(weapon_id: String) -> bool:
	return not by_weapon_id(weapon_id).is_empty()


## The carried form. It keeps the slot the base weapon occupied and inherits the
## owning character's colour, so an enhanced weapon still reads as belonging to the
## survivor who built it.
##
## There is one enhanced form per weapon, not one per route. The route is not
## thrown away by that — it still decides delivery (WeaponTechCatalog.BEHAVIORS
## rides on `tech_id`, which is carried below) and which growth axes are
## efficient — so a 혜성 추적 성좌 관통포 and a 무한 추적 성좌 관통포 remain
## different weapons without the catalogue having to hold twice as many entries.
static func build_state(evolution: Dictionary, base_state: Dictionary) -> Dictionary:
	var state: Dictionary = (evolution["weapon"] as Dictionary).duplicate(true)
	state["weapon_id"] = String(evolution["weapon_id"])
	state["internal_id"] = String(evolution["internal_id"])
	state["weapon_name"] = String(evolution["weapon_name"])
	state["primary_tag"] = String(evolution["primary_tag"])
	state["behavior_tag"] = String(evolution["behavior_tag"])
	state["tags"] = tags_of(evolution)
	state["color"] = base_state["color"]
	state["source_character"] = base_state.get("source_character", "")
	state["base_weapon_id"] = String(evolution["base_weapon_id"])
	# The enhanced form's own catalogue interval, which every speed floor is a
	# share of. Read from the enhanced entry and not carried from the base
	# weapon: an enhancement is allowed to change how often the weapon fires,
	# and the floor has to follow what it became.
	state["base_cooldown"] = float((evolution["weapon"] as Dictionary).get("cooldown", 1.0))
	for key in ["tech_id", "tech_name", "tech_internal_id", "tech_synergy_treasure_id"]:
		if base_state.has(key):
			state[key] = base_state[key]
	state["evolved"] = true
	# The enhancement does not stamp the weapon at the ceiling any more; it keeps
	# the tier it climbed to, and the five rungs above EVOLUTION_TIER are what an
	# enhanced weapon spends the last third of a run buying.
	state["tier"] = maxi(EVOLUTION_TIER, int(base_state.get("tier", EVOLUTION_TIER)))
	# Everything the base weapon was grown by survives the enhancement in full.
	if not bool(base_state.get("evolved", false)):
		var catalogue := _base_catalogue_weapon(String(state["base_weapon_id"]))
		if not catalogue.is_empty():
			Growth.carry_into_evolution(state, base_state,
				float(catalogue.get("damage", 0.0)), float(catalogue.get("cooldown", 0.0)))
	for field in WeaponTechCatalog.CARRIED_FIELDS:
		if base_state.has(field):
			state[field] = base_state[field]
	return state


static func _base_catalogue_weapon(base_weapon_id: String) -> Dictionary:
	for character in CharacterCatalog.all_characters():
		if String(character["weapon_id"]) == base_weapon_id:
			return character["weapon"]
	return {}
