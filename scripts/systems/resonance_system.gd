class_name ResonanceSystem
extends Node

## A run used to lock to one resonance forever after the first activation.
## With players able to carry up to three weapons each, the search space is
## up to nine weapon pairs — capping at one would waste almost all of it.
## Uncapped isn't safe either (every active resonance fires its own periodic
## AOE, so an unbounded stack becomes both a balance and a readability
## problem by the late game), so three is the deliberate middle ground.
const MAX_ACTIVE_RESONANCES := 3

var active_resonances: Array[Dictionary] = [] ## Each entry is a catalog dict plus its own "cooldown_remaining".

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
	{"id": "comet_shower", "name": "혜성우", "description": "투사체 마력과 냉기가 만나 사방으로 관통하는 얼음탄을 뿌립니다.", "requires": ["projectile", "frost"], "cooldown": 7.0},

	# Same-character duos: both requirement tags belong to a single character's own
	# tag set, so these only ever match when both survivors picked that character.
	{"id": "starbound_trajectory", "name": "성혼 궤적", "description": "두 사람의 유도탄이 궤적을 겹쳐 별빛 낙뢰로 착탄합니다.", "requires": ["tracking", "arcane"], "cooldown": 6.4},
	{"id": "storm_core", "name": "폭풍의 핵", "description": "두 사람 사이에 번개의 핵을 세워 사방으로 연쇄시킵니다.", "requires": ["lightning", "storm"], "cooldown": 6.3},
	{"id": "inferno_storm", "name": "겁화 폭풍", "description": "두 사람이 동시에 화염탄을 흩뿌리고 중심에서 폭발시킵니다.", "requires": ["fire", "burst"], "cooldown": 6.6},
	{"id": "absolute_zero", "name": "절대영도", "description": "두 사람 주변을 얼려 넓은 범위를 무력화합니다.", "requires": ["frost", "control"], "cooldown": 7.4},
	{"id": "bright_moon_flurry", "name": "명월난무", "description": "두 낫이 동시에 큰 호를 그리며 베어냅니다.", "requires": ["melee", "shadow"], "cooldown": 5.6},
	{"id": "bonded_mantra", "name": "결속의 진언", "description": "두 사람을 크게 회복시키고 사슬 전체에 성스러운 파동을 흘려보냅니다.", "requires": ["tether", "holy"], "cooldown": 7.8},

	# Cross-character pairs the original ten tag combinations left uncovered.
	{"id": "guided_bombardment", "name": "유도 폭격", "description": "유도탄이 불씨를 이끌어 넓은 범위에 함께 착탄합니다.", "requires": ["tracking", "burst"], "cooldown": 6.4},
	{"id": "twilight_pursuit", "name": "황혼 추적", "description": "유도 마력이 그림자 낫의 궤적을 밝혀 급소를 베어냅니다.", "requires": ["tracking", "shadow"], "cooldown": 6.2},
	{"id": "storm_cut_crescent", "name": "폭뢰 참월", "description": "번개를 두른 낫이 넓은 호를 그리며 감전시킵니다.", "requires": ["storm", "melee"], "cooldown": 6.5},
	{"id": "sacred_flame_vow", "name": "성화의 서약", "description": "두 사람을 회복시키는 성스러운 불길이 주변을 정화합니다.", "requires": ["fire", "holy"], "cooldown": 7.6},
	{"id": "frost_shade", "name": "서리 그림자", "description": "얼어붙은 그림자 낫이 넓은 범위를 베고 얼립니다.", "requires": ["frost", "shadow"], "cooldown": 6.8},

	# Added when resonance became fusion-only. The fused weapons carry tag sets
	# the base roster never produced, and these four close the last uncovered
	# pairs — verified pair by pair in resonance_coverage_test.
	{"id": "umbral_communion", "name": "명암의 계약", "description": "그림자 참격과 성흔이 겹쳐 적을 베고 두 사람을 되살립니다.", "requires": ["shadow", "holy"], "cooldown": 7.0},
	{"id": "arcing_tempest", "name": "참격 폭풍", "description": "중심에서 여섯 갈래 심판이 동시에 뻗어 나갑니다.", "requires": ["arc", "burst"], "cooldown": 6.6},
	{"id": "warding_garden", "name": "봉쇄 결계", "description": "두 사람을 둘러싼 결계밭이 깔리고 주변이 통째로 얼어붙습니다.", "requires": ["control", "aura"], "cooldown": 7.4},
	{"id": "singularity", "name": "특이점", "description": "사슬 한가운데가 무너져 모든 것을 끌어당긴 뒤 소멸시킵니다.", "requires": ["arcane", "storm"], "cooldown": 8.2}
]


## Checks every weapon pair across both players' loadouts (up to 3x3) rather
## than a single fixed pair, since either player may be carrying weapons
## picked up from other characters. requires[] is still matched against
## weapon["tags"] — tags now live on the weapon itself (a borrowed weapon
## keeps its source character's tags, not the player's own).
func get_candidates_for_loadouts(loadout_a: Array, loadout_b: Array) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if active_resonances.size() >= MAX_ACTIVE_RESONANCES:
		return candidates
	var active_ids: Dictionary = {}
	for active in active_resonances:
		active_ids[String(active["id"])] = true
	var seen_ids: Dictionary = {}
	# Resonance is the top of the tree, not a mid-run bonus: only fused weapons
	# reach it. A tier-3 base weapon used to qualify, which meant the pair hit
	# their supposed final mechanic before they had finished either build.
	for weapon_a in loadout_a:
		if not bool(weapon_a.get("evolved", false)):
			continue
		var tags_a: Array = weapon_a["tags"]
		for weapon_b in loadout_b:
			if not bool(weapon_b.get("evolved", false)):
				continue
			var tags_b: Array = weapon_b["tags"]
			for resonance in catalog:
				var resonance_id := String(resonance["id"])
				if active_ids.has(resonance_id) or seen_ids.has(resonance_id):
					continue
				var requirements: Array = resonance["requires"]
				var matches: bool = (requirements[0] in tags_a and requirements[1] in tags_b) or (requirements[1] in tags_a and requirements[0] in tags_b)
				if matches:
					seen_ids[resonance_id] = true
					var candidate := resonance.duplicate(true)
					candidate["weapon_a_name"] = String(weapon_a["weapon_name"])
					candidate["weapon_b_name"] = String(weapon_b["weapon_name"])
					candidates.append(candidate)
	return candidates


func activate(resonance: Dictionary) -> void:
	var entry := resonance.duplicate(true)
	entry["cooldown_remaining"] = 1.2
	active_resonances.append(entry)


## Returns the resonances that should fire this frame (each entry is the full
## catalog dict, ready to hand to WeaponController.perform_resonance). Every
## active resonance ticks its own independent cooldown.
func step(delta: float) -> Array[Dictionary]:
	var firing: Array[Dictionary] = []
	for entry in active_resonances:
		entry["cooldown_remaining"] = float(entry["cooldown_remaining"]) - delta
		if float(entry["cooldown_remaining"]) <= 0.0:
			entry["cooldown_remaining"] = float(entry["cooldown"])
			firing.append(entry)
	return firing
