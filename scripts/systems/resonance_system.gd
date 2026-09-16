class_name ResonanceSystem
extends Node

## A run used to lock to one resonance forever after the first activation.
## With players able to carry up to three weapons each, the search space is
## up to nine weapon pairs — capping at one would waste almost all of it.
## Uncapped isn't safe either (every active resonance fires its own periodic
## AOE, so an unbounded stack becomes both a balance and a readability
## problem by the late game), so three is the deliberate middle ground.
const MAX_ACTIVE_RESONANCES := 3

## How hard the pair's move hits, against what the two weapons behind it do.
##
## For a while a resonance took those two weapons out of service — they kept
## their slots and their levels but stopped attacking, and the resonance attacked
## in their place. These three numbers were priced as the payment for that: hit
## harder than the two weapons did, come round faster than the catalogue says,
## and keep rewarding levels spent on a weapon that had gone quiet.
##
## The silencing is gone (2026-09-16). The weapons fire, and the resonance fires
## as well, so these no longer pay for anything — they are simply how strong the
## pair's move is. They are left at the values the trade set, which means a
## resonance is now straight upside; whether that is the right size for it is a
## balance question, not a mechanical one.
const TRADE_POWER := 1.65
## How much one weapon tier above the enhancement gate adds to the pair's move,
## per side, so the resonance grows with the build that produced it rather than
## sitting at a flat value while the weapons around it climb.
const TRADE_TIER_BONUS := 0.15
const COOLDOWN_SCALE := 0.78

var active_resonances: Array[Dictionary] = [] ## Each entry is a catalog dict plus its own "cooldown_remaining".

var catalog: Array[Dictionary] = [
	{"id": "guided_thunder", "name": "추적 뇌광", "description": "가장 강한 적을 추적해 대형 연쇄 번개를 세 번 내리꽂습니다.", "requires": ["tracking", "lightning"], "cooldown": 6.0},
	{"id": "storm_volley", "name": "폭풍 유성군", "description": "두 사람이 동시에 관통 탄막을 쏘고, 각자의 자리에서 낙뢰를 부릅니다.", "requires": ["projectile", "storm"], "cooldown": 6.6},
	{"id": "arcane_circuit", "name": "마력 회로", "description": "사슬이 2.4초간 비전 회로가 되어 닿은 적을 계속 태우고 두 사람을 회복합니다.", "requires": ["arcane", "tether"], "cooldown": 7.2},
	{"id": "thermal_fracture", "name": "열충격 붕괴", "description": "냉기로 넓게 얼린 뒤 같은 자리를 폭발시켜, 얼어 있는 적에게 큰 피해를 줍니다.", "requires": ["fire", "frost"], "cooldown": 7.5},
	{"id": "eclipse_tether", "name": "월식의 사슬", "description": "사슬 전체와 양 끝에서 거대한 그림자 낫이 동시에 공격합니다.", "requires": ["shadow", "tether"], "cooldown": 6.8},
	{"id": "storm_field", "name": "폭풍 결계", "description": "두 사람 주변에 번개장을 만들어 약 2.5초간 가까운 적 셋을 연속 타격합니다.", "requires": ["storm", "aura"], "cooldown": 6.5},
	{"id": "inferno_crescent", "name": "업화 초승달", "description": "양쪽에서 부채꼴 참격을 날리고, 베인 적을 불태웁니다.", "requires": ["fire", "melee"], "cooldown": 5.8},
	{"id": "astral_covenant", "name": "성간 서약", "description": "두 사람을 회복시키고 주변 적에게 별빛 피해를 줍니다.", "requires": ["arcane", "holy"], "cooldown": 8.0},
	{"id": "frozen_tether", "name": "빙결 족쇄", "description": "사슬 근처의 적을 거의 멈추게 얼리고 약 2.7초간 결속 피해를 줍니다.", "requires": ["control", "tether"], "cooldown": 6.2},
	{"id": "comet_shower", "name": "혜성우", "description": "사방으로 관통하는 얼음탄을 뿌려 맞은 적을 크게 둔화시킵니다.", "requires": ["projectile", "frost"], "cooldown": 7.0},

	# Same-character duos: both requirement tags belong to a single character's own
	# tag set, so these only ever match when both survivors picked that character.
	{"id": "starbound_trajectory", "name": "성혼 궤적", "description": "두 사람의 유도 별탄이 적에게 착탄하는 순간 그 자리에 별빛 낙뢰가 떨어집니다.", "requires": ["tracking", "arcane"], "cooldown": 6.4},
	{"id": "storm_core", "name": "폭풍의 핵", "description": "두 사람 사이에 번개의 핵을 세워 네 방향으로 세 번 연쇄시킵니다.", "requires": ["lightning", "storm"], "cooldown": 6.3},
	{"id": "inferno_storm", "name": "겁화 폭풍", "description": "두 사람이 동시에 화염탄을 흩뿌리고, 잠시 뒤 중심에서 폭발시킵니다.", "requires": ["fire", "burst"], "cooldown": 6.6},
	{"id": "absolute_zero", "name": "절대영도", "description": "두 사람 주변을 거의 멈출 만큼 얼리고, 얼어붙은 적을 계속 파쇄합니다.", "requires": ["frost", "control"], "cooldown": 7.4},
	{"id": "bright_moon_flurry", "name": "명월난무", "description": "두 낫이 큰 호를 그린 뒤 반대 방향으로 한 번 더 베어냅니다.", "requires": ["melee", "shadow"], "cooldown": 5.6},
	{"id": "bonded_mantra", "name": "결속의 진언", "description": "두 사람을 크게 회복시키고 사슬을 따라 성스러운 파동을 세 번 흘려 적 탄을 지웁니다.", "requires": ["tether", "holy"], "cooldown": 7.8},

	# Cross-character pairs the original ten tag combinations left uncovered.
	{"id": "guided_bombardment", "name": "유도 폭격", "description": "유도 불씨가 적이 가장 몰린 자리를 골라 날아가 착탄 지점에서 폭발합니다.", "requires": ["tracking", "burst"], "cooldown": 6.4},
	{"id": "twilight_pursuit", "name": "황혼 추적", "description": "유도 마력이 가장 강한 적들을 표시하고, 그림자 낫이 따라가 급소를 벱니다.", "requires": ["tracking", "shadow"], "cooldown": 6.2},
	{"id": "storm_cut_crescent", "name": "폭뢰 참월", "description": "번개를 두른 낫이 넓은 호를 그리며 감전시켜 적을 잠시 둔화시킵니다.", "requires": ["storm", "melee"], "cooldown": 6.5},
	{"id": "sacred_flame_vow", "name": "성화의 서약", "description": "두 사람을 회복시키는 성스러운 불길이 주변을 태우고 적 탄을 정화합니다.", "requires": ["fire", "holy"], "cooldown": 7.6},
	{"id": "frost_shade", "name": "서리 그림자", "description": "얼어붙은 그림자 낫이 넓게 베고, 베인 자리의 적을 얼립니다.", "requires": ["frost", "shadow"], "cooldown": 6.8},

	# Added when resonance became fusion-only. The fused weapons carry tag sets
	# the base roster never produced, and these four close the last uncovered
	# pairs — verified pair by pair in resonance_coverage_test.
	{"id": "umbral_communion", "name": "명암의 계약", "description": "그림자 참격과 성흔이 겹쳐 적을 베고 두 사람을 되살립니다.", "requires": ["shadow", "holy"], "cooldown": 7.0},
	{"id": "arcing_tempest", "name": "참격 폭풍", "description": "중심에서 여섯 갈래 심판이 매번 다른 각도로 동시에 뻗어 나갑니다.", "requires": ["arc", "burst"], "cooldown": 6.6},
	{"id": "warding_garden", "name": "봉쇄 결계", "description": "두 사람을 둘러싼 결계밭이 깔리고 주변이 통째로 얼어붙습니다.", "requires": ["control", "aura"], "cooldown": 7.4},
	{"id": "singularity", "name": "특이점", "description": "두 사람 사이가 무너져 주변을 끌어당겨 짓누른 뒤 중심이 소멸합니다.", "requires": ["arcane", "storm"], "cooldown": 8.2}
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
	# A weapon already silenced by an active resonance cannot earn a second one:
	# it is spent, which is what keeps three resonances costing six weapon slots
	# rather than two.
	for slot_a in loadout_a.size():
		var weapon_a: Dictionary = loadout_a[slot_a]
		if not bool(weapon_a.get("evolved", false)) or is_bound(0, slot_a):
			continue
		var tags_a: Array = weapon_a["tags"]
		for slot_b in loadout_b.size():
			var weapon_b: Dictionary = loadout_b[slot_b]
			if not bool(weapon_b.get("evolved", false)) or is_bound(1, slot_b):
				continue
			var tags_b: Array = weapon_b["tags"]
			for resonance in catalog:
				var resonance_id := String(resonance["id"])
				if active_ids.has(resonance_id) or seen_ids.has(resonance_id):
					continue
				if not pair_satisfies(resonance["requires"], tags_a, tags_b):
					continue
				seen_ids[resonance_id] = true
				var candidate := resonance.duplicate(true)
				candidate["weapon_a_name"] = String(weapon_a["weapon_name"])
				candidate["weapon_b_name"] = String(weapon_b["weapon_name"])
				# The ids travel too, so the activation showcase can put the two
				# weapons that earned it on screen rather than only their names.
				candidate["weapon_a_id"] = String(weapon_a.get("weapon_id", ""))
				candidate["weapon_b_id"] = String(weapon_b.get("weapon_id", ""))
				# The slots travel with the candidate so activation knows which
				# two weapons it is taking out of service.
				candidate["weapon_a_slot"] = slot_a
				candidate["weapon_b_slot"] = slot_b
				var requirements: Array = candidate["requires"]
				candidate["tech_match_count"] = (1 if String(weapon_a.get("tech_tag", "")) in requirements else 0) \
					+ (1 if String(weapon_b.get("tech_tag", "")) in requirements else 0)
				candidates.append(candidate)
	return candidates


## Whether this pair of weapons satisfies a resonance.
##
## Every requirement has to be present across the two tag sets, and each survivor
## has to supply at least one of them — that second half is what keeps a
## resonance a pair's move rather than something one player qualifies for alone.
##
## Written against the sets rather than against `requires[0]` and `requires[1]`
## in both orders, which is what the old test did: correct for exactly two tags,
## silently wrong for any other number, and the reason nothing in the catalogue
## could ask for three.
static func pair_satisfies(requirements: Array, tags_a: Array, tags_b: Array) -> bool:
	if requirements.is_empty():
		return false
	var from_a := false
	var from_b := false
	for requirement in requirements:
		var in_a: bool = requirement in tags_a
		var in_b: bool = requirement in tags_b
		if not in_a and not in_b:
			return false
		from_a = from_a or in_a
		from_b = from_b or in_b
	# Both sides must be contributing. Two survivors carrying the same weapon do
	# satisfy this — the catalogue's same-character duos are deliberate — but one
	# survivor alone never can, because the other side supplies nothing.
	return from_a and from_b


## How many candidates the vote can show at once.
const VOTE_CHOICES := 3


## The candidates worth putting on the vote screen, best first.
##
## The vote used to take whichever three came out of the search first, which is
## catalogue order — so a pair who fused two specific weapons to reach one
## specific resonance could be shown three others instead and never get the one
## they built for. Candidates are now ranked by how *specific* they are to this
## build: a resonance only one weapon pair in the two loadouts can produce beats
## one that half the loadout satisfies incidentally. Ties keep catalogue order,
## so the list is stable between two level-ups that changed nothing.
func rank_candidates(candidates: Array[Dictionary], limit := VOTE_CHOICES) -> Array[Dictionary]:
	var produced_by: Dictionary = {}
	for candidate in candidates:
		var id := String(candidate["id"])
		produced_by[id] = int(produced_by.get(id, 0)) + 1
	var unique: Array[Dictionary] = []
	var seen: Dictionary = {}
	for candidate in candidates:
		var id := String(candidate["id"])
		if seen.has(id):
			continue
		seen[id] = true
		unique.append(candidate)
	var order: Dictionary = {}
	for index in unique.size():
		order[String(unique[index]["id"])] = index
	unique.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_id := String(first["id"])
		var second_id := String(second["id"])
		var first_pairs := int(produced_by[first_id])
		var second_pairs := int(produced_by[second_id])
		var first_tech := int(first.get("tech_match_count", 0))
		var second_tech := int(second.get("tech_match_count", 0))
		if first_tech != second_tech:
			return first_tech > second_tech
		if first_pairs != second_pairs:
			return first_pairs < second_pairs
		return int(order[first_id]) < int(order[second_id]))
	return unique.slice(0, limit)


func activate(resonance: Dictionary) -> void:
	var entry := resonance.duplicate(true)
	entry["cooldown"] = float(resonance["cooldown"]) * COOLDOWN_SCALE
	entry["cooldown_remaining"] = 1.2
	active_resonances.append(entry)


## Whether this weapon slot already feeds an active resonance.
##
## Only the candidate search asks. A bound weapon used to stop attacking, and
## this was the question the attack loop and the HUD asked about every carried
## weapon; weapons keep firing through a resonance now. What is left is the rule
## that one weapon cannot back two resonances at once — three may be active and a
## survivor may carry three weapons, so without this a pair could run three
## resonances off fewer weapons than earned them.
func is_bound(player_index: int, weapon_slot: int) -> bool:
	var key := "weapon_a_slot" if player_index == 0 else "weapon_b_slot"
	for entry in active_resonances:
		if int(entry.get(key, -1)) == weapon_slot:
			return true
	return false


## How much slower a resonance charges while the pair is not really a pair.
const DOWNED_CHARGE := 0.3
## Charge multiplier at a fully stretched chain, and at a slack one. A resonance
## is the thing two survivors do together, so the chain between them is what
## feeds it: holding the leash out — the same risk that burns integrity and pays
## the overcharge bonus — brings the pair's move round faster, and standing on
## top of each other slows it down.
const TAUT_CHARGE := 1.6
const SLACK_CHARGE := 0.65


## What one second of play is worth to the resonance clocks, given how the pair
## is standing and whether both of them are still up.
static func charge_rate(tension: float, both_up: bool) -> float:
	if not both_up:
		return DOWNED_CHARGE
	return lerpf(SLACK_CHARGE, TAUT_CHARGE, clampf(tension, 0.0, 1.0))


## Returns the resonances that should fire this frame (each entry is the full
## catalog dict, ready to hand to WeaponController.perform_resonance). Every
## active resonance ticks its own independent cooldown, and they all charge at
## the rate the pair is currently earning.
func step(delta: float, rate := 1.0) -> Array[Dictionary]:
	var firing: Array[Dictionary] = []
	var charged := delta * maxf(0.0, rate)
	for entry in active_resonances:
		entry["cooldown_remaining"] = float(entry["cooldown_remaining"]) - charged
		if float(entry["cooldown_remaining"]) <= 0.0:
			entry["cooldown_remaining"] = float(entry["cooldown"])
			firing.append(entry)
	return firing
