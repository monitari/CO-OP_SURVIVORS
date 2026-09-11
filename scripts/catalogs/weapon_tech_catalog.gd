class_name WeaponTechCatalog
extends RefCounted

## A weapon chooses its delivery when it first joins a build. Routes leave
## all later upgrade axes open, change the treasure needed for the final form,
## and add a tag that determines which co-op resonance is created automatically.
const TECHS := {
	"homing": [
		{"id": "comet", "name": "혜성 추적", "description": "큰 한 발과 다중 유도를 키웁니다.", "treasure_id": "might", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "pursuit", "name": "무한 추적", "description": "빠른 유도탄과 추진 속도를 키웁니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"], "tag": "storm", "profile": "tempo"},
		{"id": "constellation", "name": "성좌 설계", "description": "위력과 속도를 고르게 완성합니다.", "treasure_id": "pierce", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "arcane", "profile": "balanced"},
	],
	"lightning": [
		{"id": "overload", "name": "과부하", "description": "강한 연쇄와 폭발적인 낙뢰를 만듭니다.", "treasure_id": "might", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "conductor", "name": "폭풍 도체", "description": "더 자주, 더 멀리 번개를 연결합니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"], "tag": "storm", "profile": "tempo"},
	],
	"flame": [
		{"id": "sun", "name": "작은 태양", "description": "한 발의 화염과 2차 폭발을 키웁니다.", "treasure_id": "might", "upgrades": ["weapon_power", "special_b"], "tag": "burst", "profile": "force"},
		{"id": "wildfire", "name": "들불", "description": "빠르게 더 많은 불씨를 흩뿌립니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_a"], "tag": "storm", "profile": "tempo"},
		{"id": "nebula", "name": "화염 성운", "description": "범위와 화력을 고르게 확장합니다.", "treasure_id": "area", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "aura", "profile": "control"},
	],
	"frost": [
		{"id": "shatter", "name": "빙정 파쇄", "description": "얼어붙은 적에게 큰 피해를 집중합니다.", "treasure_id": "crit", "upgrades": ["weapon_power", "special_b"], "tag": "burst", "profile": "force"},
		{"id": "permafrost", "name": "영구 동토", "description": "넓은 냉기 영역으로 진로를 봉쇄합니다.", "treasure_id": "armor", "upgrades": ["weapon_rate", "special_a", "special_b"], "tag": "aura", "profile": "control"},
	],
	"scythe": [
		{"id": "execution", "name": "처형", "description": "좁고 강한 참격으로 정예를 벱니다.", "treasure_id": "might", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "dance", "name": "월광 난무", "description": "빠른 회전 참격을 연달아 냅니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"], "tag": "storm", "profile": "tempo"},
		{"id": "eclipse", "name": "월식", "description": "사거리와 공격 각도를 함께 넓힙니다.", "treasure_id": "area", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "shadow", "profile": "control"},
	],
	"chain": [
		{"id": "vow", "name": "결속의 맹세", "description": "사슬을 넓히고 회복하는 수호 테크입니다.", "treasure_id": "recovery", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "holy", "profile": "balanced"},
	],
	"orbit": [
		{"id": "shards", "name": "유성 파편", "description": "파편 수와 충돌 피해를 키웁니다.", "treasure_id": "amount", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "ritual", "name": "천구 의식", "description": "넓고 오래 유지되는 이중 궤도를 만듭니다.", "treasure_id": "duration", "upgrades": ["weapon_rate", "special_b"], "tag": "aura", "profile": "control"},
	],
	"lance": [
		{"id": "judgement", "name": "심판", "description": "한 줄의 관통 피해를 극대화합니다.", "treasure_id": "crit", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "prism", "name": "분광", "description": "빠른 다중 광선으로 전선을 덮습니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"], "tag": "storm", "profile": "tempo"},
		{"id": "horizon", "name": "지평 광선", "description": "사거리와 광선 수를 고르게 키웁니다.", "treasure_id": "pierce", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "holy", "profile": "balanced"},
	],
	"mine": [
		{"id": "demolition", "name": "연쇄 폭파", "description": "다수의 강한 지뢰를 빠르게 매설합니다.", "treasure_id": "might", "upgrades": ["weapon_power", "weapon_rate", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "garden", "name": "봉쇄 정원", "description": "넓은 결계밭으로 접근로를 지웁니다.", "treasure_id": "thorns", "upgrades": ["weapon_rate", "special_b"], "tag": "aura", "profile": "control"},
	],
	"gravity": [
		{"id": "collapse", "name": "핵붕괴", "description": "중심 폭발의 피해를 극대화합니다.", "treasure_id": "might", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "maelstrom", "name": "중력 폭풍", "description": "더 자주 강한 인력을 발생시킵니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_b"], "tag": "storm", "profile": "tempo"},
		{"id": "horizon", "name": "사건의 지평선", "description": "범위와 인력을 함께 확장합니다.", "treasure_id": "vitality", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "control", "profile": "control"},
	],
	"boomerang": [
		{"id": "ricochet", "name": "연쇄 도약", "description": "여러 생선이 적 사이를 세게 튕깁니다.", "treasure_id": "amount", "upgrades": ["weapon_power", "special_a"], "tag": "burst", "profile": "force"},
		{"id": "tailwind", "name": "순풍 왕복", "description": "빠르고 먼 왕복으로 빈틈을 줄입니다.", "treasure_id": "projectile_speed", "upgrades": ["weapon_rate", "special_b"], "tag": "storm", "profile": "tempo"},
		{"id": "hunt", "name": "추적 놀이", "description": "수와 거리를 함께 키워 계속 추적합니다.", "treasure_id": "pierce", "upgrades": ["weapon_power", "weapon_rate", "special_a", "special_b"], "tag": "tracking", "profile": "balanced"},
	],
	"milk": [
		{"id": "downpour", "name": "우유 폭우", "description": "더 많은 웅덩이를 빠르게 뿌립니다.", "treasure_id": "haste", "upgrades": ["weapon_rate", "special_a"], "tag": "storm", "profile": "tempo"},
		{"id": "tide", "name": "크림 해일", "description": "큰 웅덩이로 넓은 지역을 통제합니다.", "treasure_id": "magnet", "upgrades": ["weapon_power", "special_b"], "tag": "holy", "profile": "control"},
	],
}


## Applied to a temporary cast state: previews and repeated selections never stack.
const BEHAVIORS := {
	"homing": {
		"comet": {"text": "적 둘을 관통하는 유도탄", "pierce": 2},
		"pursuit": {"text": "유도탄 한 발 추가 · 피해 20% 감소", "count": 1, "damage_scale": 0.8},
		"constellation": {"text": "동료 위치에서도 유도탄 발사 · 피해 35% 감소", "echo": true, "damage_scale": 0.65}},
	"lightning": {
		"overload": {"text": "첫 적에게 집중 낙뢰 · 연쇄 1회", "jumps_set": 1, "damage_scale": 1.65},
		"conductor": {"text": "연쇄 두 번 추가 · 피해 20% 감소", "jumps": 2, "damage_scale": 0.8}},
	"flame": {
		"sun": {"text": "적 둘을 관통하는 방사형 불꽃", "pierce": 2},
		"wildfire": {"text": "불꽃 세 발 추가 · 피해 25% 감소", "count": 3, "damage_scale": 0.75},
		"nebula": {"text": "퍼진 불꽃이 적을 향해 휘어짐", "homing": true}},
	"frost": {
		"shatter": {"text": "둔화된 적에게 냉기 파쇄 추가 피해", "shatter": true, "damage_scale": 0.8},
		"permafrost": {"text": "동료에게도 작은 냉기 영역 생성", "ally_aura": true, "damage_scale": 0.75}},
	"scythe": {
		"execution": {"text": "좁은 부채꼴에 강한 집중 베기", "arc_scale": 0.6, "damage_scale": 1.6},
		"dance": {"text": "앞뒤 동시 베기 · 피해 35% 감소", "rear_sweep": true, "damage_scale": 0.65},
		"eclipse": {"text": "한 바퀴 원형 베기 · 피해 25% 감소", "full_circle": true, "damage_scale": 0.75}},
	"chain": {"vow": {"text": "사슬 발동마다 두 고양이 체력 회복", "team_heal": true}},
	"orbit": {
		"shards": {"text": "궤도 파편 두 개 추가 · 피해 25% 감소", "count": 2, "damage_scale": 0.75},
		"ritual": {"text": "반대 방향 이중 궤도 · 피해 35% 감소", "double_orbit": true, "damage_scale": 0.65}},
	"lance": {
		"judgement": {"text": "한 줄에 집중하는 장거리 관통창", "beams_set": 1, "range_scale": 1.35, "damage_scale": 1.25},
		"prism": {"text": "다른 적을 겨냥하는 광선 두 줄 추가", "beams": 2, "damage_scale": 0.65},
		"horizon": {"text": "동료 위치에서도 관통창 발사", "echo": true, "damage_scale": 0.65}},
	"mine": {
		"demolition": {"text": "전방에 지뢰 두 개 추가 매설", "count": 2, "damage_scale": 0.75},
		"garden": {"text": "주변을 감싸는 원형 지뢰밭", "mine_ring": true, "damage_scale": 0.75}},
	"gravity": {
		"collapse": {"text": "흡인 뒤 중심부 추가 폭발", "collapse": true, "damage_scale": 0.75},
		"maelstrom": {"text": "동료 위치에도 중력장 생성", "echo": true, "damage_scale": 0.65},
		"horizon": {"text": "발밑을 지키는 중력장", "self_gravity": true}},
	"boomerang": {
		"ricochet": {"text": "사방으로 펼쳐 던지는 왕복 공격", "radial_toys": true, "count": 2, "damage_scale": 0.7},
		"tailwind": {"text": "왕복 거리가 60% 길어짐", "range_scale": 1.6},
		"hunt": {"text": "동료 위치에서도 장난감 투척", "echo": true, "damage_scale": 0.65}},
	"milk": {
		"downpour": {"text": "작은 웅덩이 두 개 추가로 흩뿌리기", "count": 2, "radius_scale": 0.8},
		"tide": {"text": "동료 발밑에도 둔화 웅덩이 생성", "echo": true, "damage_scale": 0.65}}
}


static func behavior(state: Dictionary) -> Dictionary:
	var base_id := String(state.get("base_weapon_id", state.get("weapon_id", "")))
	return BEHAVIORS.get(base_id, {}).get(String(state.get("tech_id", "")), {})


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
	if effect.get("full_circle", false):
		result["arc"] = TAU
	result["tech_pierce"] = int(effect.get("pierce", 0))
	result["tech_homing"] = bool(effect.get("homing", false))
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
	state["tech_treasure_id"] = String(tech["treasure_id"])
	state["tech_tag"] = String(tech["tag"])


static func evolution_for(base: Dictionary, state: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var tech := by_id(String(state.get("base_weapon_id", state.get("weapon_id", ""))), String(state.get("tech_id", "")))
	if tech.is_empty():
		return result
	result["treasure_id"] = String(tech["treasure_id"])
	result["tech_id"] = String(tech["id"])
	result["tech_name"] = String(tech["name"])
	result["tech_treasure_id"] = String(tech["treasure_id"])
	result["tech_tag"] = String(tech["tag"])
	var tags: Array = (result["tags"] as Array).duplicate()
	if String(tech["tag"]) not in tags:
		tags.append(String(tech["tag"]))
	result["tags"] = tags
	var weapon: Dictionary = (result["weapon"] as Dictionary).duplicate(true)
	match String(tech["profile"]):
		"force":
			weapon["damage"] = float(weapon["damage"]) * 1.18
			weapon["cooldown"] = float(weapon["cooldown"]) * 1.05
		"tempo":
			weapon["damage"] = float(weapon["damage"]) * 0.94
			weapon["cooldown"] = float(weapon["cooldown"]) * 0.78
		"control":
			for field in ["radius", "range", "width"]:
				if weapon.has(field):
					weapon[field] = float(weapon[field]) * 1.18
	result["weapon"] = weapon
	result["description"] = "%s %s" % [String(tech["description"]), String(result["description"])]
	return result
