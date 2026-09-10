class_name WeaponTechCatalog
extends RefCounted

## A weapon chooses its route once, when it first joins a build. Routes keep
## later card hands coherent, change the treasure needed for the final form,
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


static func for_weapon(weapon_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tech: Dictionary in TECHS.get(weapon_id, []):
		result.append(tech.duplicate(true))
	return result


static func by_id(weapon_id: String, tech_id: String) -> Dictionary:
	for tech in for_weapon(weapon_id):
		if String(tech["id"]) == tech_id:
			return tech
	return {}


static func allows(state: Dictionary, upgrade_id: String) -> bool:
	var tech := by_id(String(state.get("base_weapon_id", state.get("weapon_id", ""))), String(state.get("tech_id", "")))
	return tech.is_empty() or upgrade_id in (tech["upgrades"] as Array)


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
