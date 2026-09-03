class_name ResonanceSystem
extends Node

var active_resonance: Dictionary = {}
var cooldown_remaining := 0.0

var catalog: Array[Dictionary] = [
	{"id": "guided_thunder", "name": "추적 뇌광", "description": "유도 마력이 적을 추적하는 대형 연쇄 번개가 됩니다.", "requires": ["tracking", "lightning"], "cooldown": 6.0},
	{"id": "storm_volley", "name": "폭풍 유성군", "description": "투사체가 폭풍을 머금어 양쪽에서 탄막과 낙뢰를 함께 방출합니다.", "requires": ["projectile", "storm"], "cooldown": 6.6},
	{"id": "arcane_circuit", "name": "마력 회로", "description": "사슬을 비전 회로로 바꿔 접촉한 적을 태우고 두 사람을 회복합니다.", "requires": ["arcane", "chain"], "cooldown": 7.2},
	{"id": "thermal_fracture", "name": "열충격 붕괴", "description": "화염과 냉기가 충돌해 넓은 폭발과 강한 둔화를 일으킵니다.", "requires": ["fire", "frost"], "cooldown": 7.5},
	{"id": "eclipse_tether", "name": "월식의 사슬", "description": "사슬 전체와 양 끝에서 거대한 그림자 낫이 동시에 공격합니다.", "requires": ["shadow", "tether"], "cooldown": 6.8},
	{"id": "storm_field", "name": "폭풍 결계", "description": "두 사람 주변에 번개장을 만들고 가까운 적을 연속 타격합니다.", "requires": ["storm", "aura"], "cooldown": 6.5},
	{"id": "inferno_crescent", "name": "업화 초승달", "description": "불타는 부채꼴 참격을 양쪽에서 방출합니다.", "requires": ["fire", "melee"], "cooldown": 5.8},
	{"id": "astral_covenant", "name": "성간 서약", "description": "두 사람을 회복시키고 주변 적에게 별빛 피해를 줍니다.", "requires": ["arcane", "holy"], "cooldown": 8.0},
	{"id": "frozen_tether", "name": "빙결 족쇄", "description": "사슬 근처의 적을 얼리고 지속적인 결속 피해를 줍니다.", "requires": ["control", "tether"], "cooldown": 6.2},
	{"id": "comet_shower", "name": "혜성우", "description": "투사체 마력과 냉기가 만나 사방으로 관통하는 얼음탄을 뿌립니다.", "requires": ["projectile", "frost"], "cooldown": 7.0}
]


func get_candidates(character_a: Dictionary, character_b: Dictionary, weapon_a: Dictionary, weapon_b: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not active_resonance.is_empty() or int(weapon_a.get("tier", 1)) < 3 or int(weapon_b.get("tier", 1)) < 3:
		return candidates
	var tags_a: Array = character_a["tags"]
	var tags_b: Array = character_b["tags"]
	for resonance in catalog:
		var requirements: Array = resonance["requires"]
		var matches: bool = (requirements[0] in tags_a and requirements[1] in tags_b) or (requirements[1] in tags_a and requirements[0] in tags_b)
		if matches:
			candidates.append(resonance.duplicate(true))
	return candidates


func activate(resonance: Dictionary) -> void:
	active_resonance = resonance.duplicate(true)
	cooldown_remaining = 1.2


func step(delta: float) -> bool:
	if active_resonance.is_empty():
		return false
	cooldown_remaining -= delta
	if cooldown_remaining > 0.0:
		return false
	cooldown_remaining = float(active_resonance["cooldown"])
	return true
