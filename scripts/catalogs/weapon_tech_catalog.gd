class_name WeaponTechCatalog
extends RefCounted

## A weapon picks its direction once, at WeaponGrowth.TECH_UNLOCK_TIER, and every
## weapon offers exactly the same shape of choice:
##
##     A   화력형    강한 한 방을 키운다        weapon_power + 고유 하나
##     B   속도형    빠른 반복·수량을 키운다    weapon_rate  + 고유 하나
##
## That shape is the whole rule, and it is machine-checked (see
## `tests/weapon_data_test.gd`): tech A always names 화력, tech B always names
## 공격 속도, and each names exactly one of the weapon's two 고유 axes. A player
## who has learned one weapon's Lv.3 choice has learned all twelve.
##
## Every weapon used to offer between one and three routes, and five of them
## carried a third "고르게 완성합니다" route — a middle value that named all four
## axes, which meant it specialised in nothing and was picked because it read as
## safe rather than because it was a direction. Those five are gone; a route that
## does not commit is not a choice, it is a default with extra words.
##
## A route decides two things and nothing else:
##
##   - how the attack is delivered (see BEHAVIORS below)
##   - which growth axes are efficient (see WeaponGrowth.focus)
##
## A route deliberately does NOT decide whether the weapon can be enhanced,
## which treasure the pair has to find, or which resonance they can reach. Those
## used to hang off the route and made a Lv.3 card a decision about the rest of
## the run that nobody had the information to make.
const TECHS := {
	"homing": [
		{"id": "comet", "internal_id": "TECH_COMET_TRACKING", "name": "혜성 추적", "role": "a",
			"description": "적은 수의 큰 유도탄으로 적을 꿰뚫습니다.",
			"synergy_treasure_id": "might", "upgrades": ["weapon_power", "special_b"]},
		{"id": "pursuit", "internal_id": "TECH_ENDLESS_PURSUIT", "name": "무한 추적", "role": "b",
			"description": "약한 유도탄을 더 많이, 더 자주 날립니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_a"]},
	],
	"lightning": [
		{"id": "overload", "internal_id": "TECH_OVERLOAD", "name": "과부하", "role": "a",
			"description": "연쇄를 버리고 첫 적에게 폭발적인 낙뢰를 집중합니다.",
			"synergy_treasure_id": "might", "upgrades": ["weapon_power", "special_a"]},
		{"id": "conductor", "internal_id": "TECH_STORM_CONDUCTOR", "name": "폭풍 도체", "role": "b",
			"description": "더 자주, 더 멀리 번개를 연결합니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"]},
	],
	"flame": [
		{"id": "sun", "internal_id": "TECH_LITTLE_SUN", "name": "작은 태양", "role": "a",
			"description": "한 발의 화염과 2차 폭발을 키웁니다.",
			"synergy_treasure_id": "might", "upgrades": ["weapon_power", "special_b"]},
		{"id": "wildfire", "internal_id": "TECH_WILDFIRE", "name": "들불", "role": "b",
			"description": "빠르게 더 많은 불씨를 흩뿌립니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_a"]},
	],
	"frost": [
		{"id": "shatter", "internal_id": "TECH_CRYSTAL_SHATTER", "name": "빙정 파쇄", "role": "a",
			"description": "얼어붙은 적에게 큰 피해를 집중합니다.",
			"synergy_treasure_id": "crit", "upgrades": ["weapon_power", "special_b"]},
		{"id": "permafrost", "internal_id": "TECH_PERMAFROST", "name": "영구 동토", "role": "b",
			"description": "넓은 냉기 영역을 더 자주 갱신합니다.",
			"synergy_treasure_id": "armor", "upgrades": ["weapon_rate", "special_a"]},
	],
	"scythe": [
		{"id": "execution", "internal_id": "TECH_EXECUTION", "name": "처형", "role": "a",
			"description": "좁고 강한 참격으로 정예를 벱니다.",
			"synergy_treasure_id": "might", "upgrades": ["weapon_power", "special_a"]},
		{"id": "dance", "internal_id": "TECH_MOONLIGHT_DANCE", "name": "월광 난무", "role": "b",
			"description": "앞뒤를 동시에 베는 회전 참격을 연달아 냅니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"]},
	],
	"chain": [
		{"id": "vow", "internal_id": "TECH_BINDING_VOW", "name": "결속의 맹세", "role": "a",
			"description": "한 번의 파동을 넓고 무겁게 만듭니다.",
			"synergy_treasure_id": "recovery", "upgrades": ["weapon_power", "special_a"]},
		{"id": "tether", "internal_id": "TECH_TAUT_TETHER", "name": "팽팽한 사슬", "role": "b",
			"description": "약한 파동을 두 번 연달아 흘려보냅니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"]},
	],
	"orbit": [
		{"id": "shards", "internal_id": "TECH_METEOR_SHARDS", "name": "유성 파편", "role": "a",
			"description": "파편 수와 충돌 피해를 키웁니다.",
			"synergy_treasure_id": "amount", "upgrades": ["weapon_power", "special_a"]},
		{"id": "ritual", "internal_id": "TECH_CELESTIAL_RITUAL", "name": "천구 의식", "role": "b",
			"description": "반대로 도는 이중 궤도를 더 자주 돌립니다.",
			"synergy_treasure_id": "duration", "upgrades": ["weapon_rate", "special_b"]},
	],
	"lance": [
		{"id": "judgement", "internal_id": "TECH_JUDGEMENT", "name": "심판", "role": "a",
			"description": "한 줄의 관통 피해를 극대화합니다.",
			"synergy_treasure_id": "crit", "upgrades": ["weapon_power", "special_a"]},
		{"id": "prism", "internal_id": "TECH_PRISM", "name": "분광", "role": "b",
			"description": "빠른 다중 광선으로 전선을 덮습니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"]},
	],
	"mine": [
		{"id": "demolition", "internal_id": "TECH_DEMOLITION", "name": "연쇄 폭파", "role": "a",
			"description": "전방에 더 강한 지뢰를 무겁게 매설합니다.",
			"synergy_treasure_id": "might", "upgrades": ["weapon_power", "special_a"]},
		{"id": "garden", "internal_id": "TECH_WARDING_GARDEN", "name": "봉쇄 정원", "role": "b",
			"description": "넓은 결계밭을 빠르게 다시 깝니다.",
			"synergy_treasure_id": "thorns", "upgrades": ["weapon_rate", "special_b"]},
	],
	"gravity": [
		{"id": "collapse", "internal_id": "TECH_CORE_COLLAPSE", "name": "핵붕괴", "role": "a",
			"description": "중심 폭발의 피해를 극대화합니다.",
			"synergy_treasure_id": "might", "upgrades": ["weapon_power", "special_a"]},
		{"id": "maelstrom", "internal_id": "TECH_MAELSTROM", "name": "중력 폭풍", "role": "b",
			"description": "더 자주 강한 인력을 발생시킵니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"]},
	],
	"boomerang": [
		{"id": "ricochet", "internal_id": "TECH_RICOCHET", "name": "연쇄 도약", "role": "a",
			"description": "사방으로 펼쳐 던지는 무거운 왕복 공격입니다.",
			"synergy_treasure_id": "amount", "upgrades": ["weapon_power", "special_a"]},
		{"id": "tailwind", "internal_id": "TECH_TAILWIND", "name": "순풍 왕복", "role": "b",
			"description": "빠르고 먼 왕복으로 빈틈을 줄입니다.",
			"synergy_treasure_id": "projectile_speed", "upgrades": ["weapon_rate", "special_b"]},
	],
	"milk": [
		{"id": "tide", "internal_id": "TECH_CREAM_TIDE", "name": "크림 해일", "role": "a",
			"description": "큰 웅덩이로 넓은 지역을 무겁게 통제합니다.",
			"synergy_treasure_id": "magnet", "upgrades": ["weapon_power", "special_b"]},
		{"id": "downpour", "internal_id": "TECH_DOWNPOUR", "name": "우유 폭우", "role": "b",
			"description": "더 많은 웅덩이를 빠르게 뿌립니다.",
			"synergy_treasure_id": "haste", "upgrades": ["weapon_rate", "special_a"]},
	],
}


## Applied to a temporary cast state: previews and repeated selections never stack.
const BEHAVIORS := {
	"homing": {
		"comet": {"text": "적 둘을 관통하는 유도탄", "pierce": 2},
		"pursuit": {"text": "유도탄 한 발 추가    피해 20% 감소", "count": 1, "damage_scale": 0.8}},
	"lightning": {
		"overload": {"text": "첫 적에게 집중 낙뢰와 착탄 폭발    연쇄 1회", "jumps_set": 1, "damage_scale": 1.65, "splash": 64.0},
		"conductor": {"text": "연쇄 두 번 추가    피해 20% 감소", "jumps": 2, "damage_scale": 0.8}},
	"flame": {
		"sun": {"text": "적 둘을 관통하는 방사형 불꽃", "pierce": 2},
		"wildfire": {"text": "불꽃 세 발 추가    피해 25% 감소", "count": 3, "damage_scale": 0.75}},
	"frost": {
		"shatter": {"text": "둔화된 적에게 냉기 파쇄 추가 피해", "shatter": true, "damage_scale": 0.8},
		"permafrost": {"text": "동료에게도 작은 냉기 영역 생성", "ally_aura": true, "damage_scale": 0.75}},
	"scythe": {
		"execution": {"text": "좁은 부채꼴에 강한 집중 베기", "arc_scale": 0.6, "damage_scale": 1.6},
		"dance": {"text": "앞뒤 동시 베기    피해 35% 감소", "rear_sweep": true, "damage_scale": 0.65}},
	"chain": {
		"vow": {"text": "사슬 발동마다 두 고양이 체력 회복", "team_heal": true},
		"tether": {"text": "사슬 파동이 두 번 연달아 흐름    피해 30% 감소", "double_pulse": true, "damage_scale": 0.7}},
	"orbit": {
		"shards": {"text": "궤도 파편 두 개 추가    피해 25% 감소", "count": 2, "damage_scale": 0.75},
		"ritual": {"text": "반대 방향 이중 궤도    피해 35% 감소", "double_orbit": true, "damage_scale": 0.65}},
	"lance": {
		"judgement": {"text": "한 줄에 집중하는 장거리 관통창", "beams_set": 1, "range_scale": 1.35, "damage_scale": 1.25},
		"prism": {"text": "다른 적을 겨냥하는 광선 두 줄 추가", "beams": 2, "damage_scale": 0.65}},
	"mine": {
		"demolition": {"text": "전방에 지뢰 두 개 추가 매설", "count": 2, "damage_scale": 0.75},
		"garden": {"text": "주변을 감싸는 원형 지뢰밭", "mine_ring": true, "damage_scale": 0.75}},
	"gravity": {
		"collapse": {"text": "흡인 뒤 중심부 추가 폭발", "collapse": true, "damage_scale": 0.75},
		"maelstrom": {"text": "동료 위치에도 중력장 생성", "echo": true, "damage_scale": 0.65}},
	"boomerang": {
		"ricochet": {"text": "사방으로 펼쳐 던지는 왕복 공격", "radial_toys": true, "count": 2, "damage_scale": 0.7},
		"tailwind": {"text": "왕복 거리가 60% 길어짐", "range_scale": 1.6}},
	"milk": {
		"tide": {"text": "동료 발밑에도 둔화 웅덩이 생성", "echo": true, "damage_scale": 0.65},
		"downpour": {"text": "작은 웅덩이 두 개 추가로 흩뿌리기", "count": 2, "radius_scale": 0.8}},
}


## A route changes what a weapon does, and some of those changes leave one of the
## weapon's own specials with nothing to act on: 과부하 pins the chain to a single
## jump, so +1 연쇄 did nothing, and 심판 pins the lance to one beam, so +1 광선
## did nothing. Those routes replace the dead special with one that grows what the
## route is about. The fields named here are read by WeaponController and carried
## into the enhanced weapon by EvolutionCatalog.build_state.
const SPECIAL_OVERRIDES := {
	"homing": {"comet": {"b": {"title": "혜성 꼬리", "label": "추가 관통", "primitive": "Pierce", "field": "pierce_bonus", "delta": 1, "integer": true, "cap": 6.0}}},
	"flame": {"sun": {"b": {"title": "태양 흑점", "label": "추가 관통", "primitive": "Pierce", "field": "pierce_bonus", "delta": 1, "integer": true, "cap": 6.0}}},
	"lightning": {"overload": {"a": {"title": "낙뢰 폭심", "label": "착탄 폭발 반경", "primitive": "Radius", "field": "splash", "delta": 20.0}}},
	"lance": {"judgement": {"b": {"title": "심판의 창날", "label": "창 폭", "primitive": "Radius", "field": "width", "delta": 7.0}}},
}
## Fields a route's specials add that the enhanced weapon keeps using.
const CARRIED_FIELDS := ["pierce_bonus"]


static func behavior(state: Dictionary) -> Dictionary:
	var base_id := String(state.get("base_weapon_id", state.get("weapon_id", "")))
	return BEHAVIORS.get(base_id, {}).get(String(state.get("tech_id", "")), {})


static func special_override(state: Dictionary, key: String) -> Dictionary:
	var base_id := String(state.get("base_weapon_id", state.get("weapon_id", "")))
	return SPECIAL_OVERRIDES.get(base_id, {}).get(String(state.get("tech_id", "")), {}).get(key, {})


static func cast_state(state: Dictionary) -> Dictionary:
	var result := state.duplicate()
	var effect := behavior(state)
	for field in ["count", "jumps", "beams"]:
		if effect.has(field):
			result[field] = int(result.get(field, 1)) + int(effect[field])
		if effect.has(field + "_set"):
			result[field] = int(effect[field + "_set"])
	for field in ["range", "radius", "arc", "damage"]:
		if result.has(field):
			result[field] = float(result[field]) * float(effect.get(field + "_scale", 1.0))
	result["tech_pierce"] = int(effect.get("pierce", 0)) + int(state.get("pierce_bonus", 0))
	result["tech_homing"] = bool(effect.get("homing", false))
	var splash := float(state.get("splash", 0.0)) + float(effect.get("splash", 0.0))
	if splash > 0.0:
		result["splash"] = splash
	return result


static func for_weapon(weapon_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tech: Dictionary in TECHS.get(weapon_id, []):
		var entry := tech.duplicate(true)
		entry["behavior_description"] = String(BEHAVIORS.get(weapon_id, {}).get(String(tech["id"]), {}).get("text", tech["description"]))
		entry["description"] = entry["behavior_description"]
		result.append(entry)
	return result


static func by_id(weapon_id: String, tech_id: String) -> Dictionary:
	for tech in for_weapon(weapon_id):
		if String(tech["id"]) == tech_id:
			return tech
	return {}


static func allows(_state: Dictionary, _upgrade_id: String) -> bool:
	# Routes choose delivery, never remove an axis from later growth.
	return true


static func apply_to_state(state: Dictionary, tech: Dictionary) -> void:
	state["tech_id"] = String(tech["id"])
	state["tech_name"] = String(tech["name"])
	state["tech_internal_id"] = String(tech["internal_id"])
	state["tech_synergy_treasure_id"] = String(tech["synergy_treasure_id"])
