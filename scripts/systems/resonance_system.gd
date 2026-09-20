class_name ResonanceSystem
extends Node

const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const L := preload("res://scripts/systems/loc.gd")

## The top of the tree: what two *enhanced* weapons do together.
##
## Three things decide whether a resonance happens, and a player can check all
## three on the screen in front of them:
##
##   1. both survivors carry an enhanced weapon, and between them the two
##      weapons supply the resonance's two tags (§태그)
##   2. each survivor supplies at least one of those tags — this is the pair's
##      move, so one survivor can never qualify alone
##   3. the pair beat a boss and spent the 공명핵 it dropped
##
## The third one is new and it is what turned resonance from a thing that
## happened *to* a build into a thing a pair chooses. Matching tags used to
## activate a resonance outright at the next level-up, which meant the pair's
## climactic mechanic arrived as a notification: no moment, no decision, and no
## way to prefer one of two possible resonances over the other. Tags now only
## make a resonance *possible*; the core is the moment it becomes real.

## Two slots, and the run hands out exactly two cores (see MAIN: the first and
## second boss each drop one). Those two numbers are deliberately the same, so
## "how many resonances can we have?" is answered by something the pair watched
## happen rather than by a rule they had to be told. It used to be three, capped
## by a constant with no in-world referent.
const MAX_ACTIVE_RESONANCES := 2

## How hard the pair's move hits, against what the two weapons behind it do.
##
## For a while a resonance took those two weapons out of service — they kept
## their slots and their levels but stopped attacking, and the resonance attacked
## in their place. These numbers were priced as the payment for that. The
## silencing is gone (2026-09-16): the weapons fire, and the resonance fires as
## well, so these are simply how strong the pair's move is.
const TRADE_POWER := 1.65
## How much one weapon tier above the enhancement gate adds to the pair's move,
## per side. This plus TRADE_POWER is the whole growth formula — one common
## expression (base power × the two weapons' average growth) rather than a
## per-resonance scaling rule, which is what §16 asks for.
const TRADE_TIER_BONUS := 0.15

## Cores held but not yet spent. A core is a right to pick, not a material for a
## particular recipe: there is no 화염용 or 냉기용 core, because a reward that
## only some builds can use puts the run's payoff back behind a dice roll.
var pending_cores := 0
var active_resonances: Array[Dictionary] = [] ## Each entry is a catalog dict plus its own "cooldown_remaining".
## The whole catalogue, hand-made and generated together. Built once per system
## rather than per query, since generating it walks the evolution roster.
var catalog: Array[Dictionary] = all_resonances()

## The tags a resonance may be built from. They never overlap in meaning: a
## primary tag says what the attack is made of, a behaviour tag says what shape
## it takes, and no tag appears in both lists. 뇌전 is an element; 폭풍 is a way
## of covering ground with it.
const PRIMARY_TAGS := Evolutions.PRIMARY_TAGS
const BEHAVIOR_TAGS := Evolutions.BEHAVIOR_TAGS

const TAG_NAMES := {
	"fire": "화염", "frost": "냉기", "lightning": "뇌전", "arcane": "비전",
	"shadow": "그림자", "holy": "성흔",
	"projectile": "탄막", "melee": "참격", "chain": "사슬", "aura": "오라",
	"tracking": "유도", "control": "제어", "explosion": "폭발", "storm": "폭풍",
	"pierce": "관통",
}

## The adjective each element contributes to a generated resonance's name, and
## the noun each behaviour contributes. "서리 유도", "성광 탄막".
const ELEMENT_WORDS := {
	"fire": "업화", "frost": "서리", "lightning": "뇌전", "arcane": "비전",
	"shadow": "그믐", "holy": "성광",
}
const BEHAVIOR_WORDS := {
	"projectile": "탄막", "melee": "참격", "chain": "회로", "aura": "장판",
	"tracking": "추적", "control": "결계", "explosion": "폭발", "storm": "폭풍",
	"pierce": "관통",
}

## What each element does on top of the shape, in one clause. Used to build the
## generated descriptions, so the text and the effect cannot drift apart — the
## same clause names the rider that WeaponController actually applies.
const ELEMENT_RIDERS := {
	"fire": "적을 불태웁니다",
	"frost": "적을 얼려 둔화시킵니다",
	"lightning": "가까운 적에게 번개가 옮겨붙습니다",
	"arcane": "적을 중심으로 끌어당깁니다",
	"shadow": "체력이 낮은 적에게 추가 피해를 줍니다",
	"holy": "두 사람의 체력을 회복시킵니다",
}

## The shape each behaviour tag takes, as the generic template that runs it.
## Nine shapes cover every element × behaviour combination the roster can
## produce, which is what keeps a thirteenth weapon from needing twelve new
## hand-written resonances (§15).
const BEHAVIOR_TEMPLATES := {
	"projectile": {"template": "barrage", "cooldown": 5.4, "description": "두 사람이 동시에 %s 탄막을 흩뿌리고, %s."},
	"pierce": {"template": "lance", "cooldown": 5.6, "description": "두 사람 사이를 잇는 %s 관통 광선이 뻗어 나가고, %s."},
	"melee": {"template": "cleave", "cooldown": 5.0, "description": "두 사람 주위를 %s 참격이 크게 훑고, %s."},
	"chain": {"template": "conduit", "cooldown": 6.0, "description": "사슬이 %s 회로가 되어 닿은 적을 태우고, %s."},
	"aura": {"template": "field", "cooldown": 5.8, "description": "두 사람 주변에 %s 장판이 깔려 계속 타격하고, %s."},
	"tracking": {"template": "bombard", "cooldown": 5.5, "description": "%s 유도탄이 가장 몰린 자리를 골라 떨어지고, %s."},
	"control": {"template": "snare", "cooldown": 6.0, "description": "%s 결계가 넓게 퍼져 적을 묶어 두고, %s."},
	"explosion": {"template": "blast", "cooldown": 5.6, "description": "두 사람 사이에서 %s 폭발이 터지고, %s."},
	"storm": {"template": "tempest", "cooldown": 6.2, "description": "%s 폭풍이 넓은 범위를 거듭 때리고, %s."},
}

## The hand-made ones. A combination earns an entry here when the two tags
## together mean something the generic shape cannot say — 화염 + 냉기 is not a
## fire field with a frost rider, it is thermal shock — and WeaponController has
## a written effect for each. Everything else falls through to the template
## above, which is the priority §15 asks for: 고유 공명이 있으면 그것을, 없으면
## 템플릿을.
##
## Cooldowns are per-resonance and are the real numbers. There used to be a
## global `× 0.78` applied to every entry on activation, so the catalogue said
## one thing and the game did another; these are the former values with that
## factor already folded in. The long ones at the bottom are the utility
## resonances — the ones that heal both survivors or clear enemy shots — which
## are deliberately not priced like the damage ones (§16).
const UNIQUE_RESONANCES := [
	{"id": "guided_thunder", "name": "추적 뇌광", "requires": ["lightning", "tracking"], "cooldown": 4.7,
		"description": "가장 강한 적을 추적해 대형 연쇄 번개를 세 번 내리꽂습니다."},
	{"id": "storm_volley", "name": "폭풍 유성군", "requires": ["projectile", "storm"], "cooldown": 5.1,
		"description": "두 사람이 동시에 관통 탄막을 쏘고, 각자의 자리에서 낙뢰를 부릅니다."},
	{"id": "arcane_circuit", "name": "마력 회로", "requires": ["arcane", "chain"], "cooldown": 5.6,
		"description": "사슬이 2.4초간 비전 회로가 되어 닿은 적을 계속 태우고 두 사람을 회복합니다."},
	{"id": "thermal_fracture", "name": "열충격 붕괴", "requires": ["fire", "frost"], "cooldown": 5.9,
		"description": "냉기로 넓게 얼린 뒤 같은 자리를 폭발시켜, 얼어 있는 적에게 큰 피해를 줍니다."},
	{"id": "eclipse_tether", "name": "월식의 사슬", "requires": ["shadow", "chain"], "cooldown": 5.3,
		"description": "사슬 전체와 양 끝에서 거대한 그림자 낫이 동시에 공격합니다."},
	{"id": "storm_field", "name": "폭풍 결계", "requires": ["aura", "storm"], "cooldown": 5.1,
		"description": "두 사람 주변에 번개장을 만들어 약 2.5초간 가까운 적 셋을 연속 타격합니다."},
	{"id": "inferno_crescent", "name": "업화 초승달", "requires": ["fire", "melee"], "cooldown": 4.5,
		"description": "양쪽에서 부채꼴 참격을 날리고, 베인 적을 불태웁니다."},
	{"id": "astral_covenant", "name": "성간 서약", "requires": ["arcane", "holy"], "cooldown": 6.2,
		"description": "두 사람을 회복시키고 주변 적에게 별빛 피해를 줍니다."},
	{"id": "frozen_tether", "name": "빙결 족쇄", "requires": ["chain", "control"], "cooldown": 4.8,
		"description": "사슬 근처의 적을 거의 멈추게 얼리고 약 2.7초간 결속 피해를 줍니다."},
	{"id": "comet_shower", "name": "혜성우", "requires": ["frost", "projectile"], "cooldown": 5.5,
		"description": "사방으로 관통하는 얼음탄을 뿌려 맞은 적을 크게 둔화시킵니다."},
	{"id": "starbound_trajectory", "name": "성혼 궤적", "requires": ["arcane", "tracking"], "cooldown": 5.0,
		"description": "두 사람의 유도 별탄이 적에게 착탄하는 순간 그 자리에 별빛 낙뢰가 떨어집니다."},
	{"id": "storm_core", "name": "폭풍의 핵", "requires": ["lightning", "storm"], "cooldown": 4.9,
		"description": "두 사람 사이에 번개의 핵을 세워 네 방향으로 세 번 연쇄시킵니다."},
	{"id": "inferno_storm", "name": "겁화 폭풍", "requires": ["fire", "storm"], "cooldown": 5.1,
		"description": "두 사람이 동시에 화염탄을 흩뿌리고, 잠시 뒤 중심에서 폭발시킵니다."},
	{"id": "glacial_prison", "name": "빙하 감옥", "requires": ["control", "frost"], "cooldown": 5.8,
		"description": "두 사람 주변을 거의 멈출 만큼 얼리고, 얼어붙은 적을 계속 파쇄합니다."},
	{"id": "bright_moon_flurry", "name": "명월난무", "requires": ["melee", "shadow"], "cooldown": 4.4,
		"description": "두 낫이 큰 호를 그린 뒤 반대 방향으로 한 번 더 베어냅니다."},
	{"id": "bonded_mantra", "name": "결속의 진언", "requires": ["chain", "holy"], "cooldown": 6.1,
		"description": "두 사람을 크게 회복시키고 사슬을 따라 성스러운 파동을 세 번 흘려 적 탄을 지웁니다."},
	{"id": "guided_bombardment", "name": "유도 폭격", "requires": ["explosion", "tracking"], "cooldown": 5.0,
		"description": "유도 불씨가 적이 가장 몰린 자리를 골라 날아가 착탄 지점에서 폭발합니다."},
	{"id": "twilight_pursuit", "name": "황혼 추적", "requires": ["shadow", "tracking"], "cooldown": 4.8,
		"description": "유도 마력이 가장 강한 적들을 표시하고, 그림자 낫이 따라가 급소를 벱니다."},
	{"id": "storm_cut_crescent", "name": "폭뢰 참월", "requires": ["melee", "storm"], "cooldown": 5.1,
		"description": "번개를 두른 낫이 넓은 호를 그리며 감전시켜 적을 잠시 둔화시킵니다."},
	{"id": "sacred_flame_vow", "name": "성화의 서약", "requires": ["fire", "holy"], "cooldown": 5.9,
		"description": "두 사람을 회복시키는 성스러운 불길이 주변을 태우고 적 탄을 정화합니다."},
	{"id": "frost_shade", "name": "서리 그림자", "requires": ["frost", "shadow"], "cooldown": 5.3,
		"description": "얼어붙은 그림자 낫이 넓게 베고, 베인 자리의 적을 얼립니다."},
	{"id": "umbral_communion", "name": "명암의 계약", "requires": ["holy", "shadow"], "cooldown": 5.5,
		"description": "그림자 참격과 성흔이 겹쳐 적을 베고 두 사람을 되살립니다."},
	{"id": "warding_garden", "name": "봉쇄 결계", "requires": ["aura", "control"], "cooldown": 5.8,
		"description": "두 사람을 둘러싼 결계밭이 깔리고 주변이 통째로 얼어붙습니다."},
	{"id": "singularity", "name": "특이점", "requires": ["arcane", "storm"], "cooldown": 6.4,
		"description": "두 사람 사이가 무너져 주변을 끌어당겨 짓누른 뒤 중심이 소멸합니다."},
]

static var _catalog_cache: Array[Dictionary] = []


## Every resonance in the game: the hand-made ones, plus one generated entry for
## each element × behaviour combination the enhanced roster can actually produce
## and that no hand-made one already claims.
##
## Generating them is what makes the roster extensible. Adding a thirteenth
## weapon means giving it two tags; it does not mean sitting down and writing its
## resonance with each of the twelve weapons that already exist. It also makes
## coverage structural rather than something a test has to keep watch over: any
## two enhanced weapons A and B supply A's element with B's behaviour, the two
## tags always differ because the two tag lists are disjoint, and both sides
## contribute by construction — so a pair can never end a run holding two
## finished weapons and no resonance to show for them.
static func all_resonances() -> Array[Dictionary]:
	if not _catalog_cache.is_empty():
		return _catalog_cache
	var result: Array[Dictionary] = []
	var claimed: Dictionary = {}
	for entry in UNIQUE_RESONANCES:
		var unique := (entry as Dictionary).duplicate(true)
		var requires: Array = unique["requires"]
		requires.sort()
		unique["requires"] = requires
		unique["kind"] = "unique"
		unique["internal_id"] = "RESONANCE_" + String(unique["id"]).to_upper()
		result.append(unique)
		claimed[_pair_key(requires)] = true
	for element in _roster_tags(PRIMARY_TAGS):
		for behavior in _roster_tags(BEHAVIOR_TAGS):
			var requires := [element, behavior]
			requires.sort()
			if claimed.has(_pair_key(requires)):
				continue
			claimed[_pair_key(requires)] = true
			result.append(_generated(element, behavior, requires))
	_catalog_cache = result
	return result


## Only the tags the enhanced roster actually carries. Generating combinations
## for tags no weapon has would fill the codex with resonances nobody can ever
## reach, which is the catalogue equivalent of dead code.
static func _roster_tags(allowed: Array) -> Array:
	var present: Dictionary = {}
	for evolution in Evolutions.all_evolutions():
		for tag in Evolutions.tags_of(evolution):
			if tag in allowed:
				present[tag] = true
	var tags: Array = present.keys()
	tags.sort()
	return tags


static func _pair_key(requires: Array) -> String:
	return "%s+%s" % [requires[0], requires[1]]


## The name a player reads. A hand-written resonance has one written name; a
## generated one is an element word and a behaviour word, translated separately
## so the roster does not need 54 hand-written English names to say the same
## nine shapes in six elements.
static func display_name(entry: Dictionary) -> String:
	if entry.has("name_parts"):
		var parts: Array = entry["name_parts"]
		return "%s %s" % [L.t(String(parts[0])), L.t(String(parts[1]))]
	return L.t(String(entry.get("name", "")))


## The sentence a player reads, built the same way: one translated shape with
## the element's noun and the element's rider clause dropped into it.
static func display_description(entry: Dictionary) -> String:
	if entry.has("description_parts"):
		var parts: Array = entry["description_parts"]
		return L.f(String(parts[0]), [L.t(String(parts[1])), L.t(String(parts[2]))])
	return L.t(String(entry.get("description", "")))


## One generic resonance, built from the element's rider and the behaviour's
## shape. Name, description and numbers all come from the same two tags, so
## there is no text to keep in step with the effect by hand (§20).
## A generated entry keeps the two words and the rider it was built from as well
## as the Korean sentence, so `display_name` and `display_description` can build
## the line again in whatever locale is current. Composing once and caching the
## result would freeze the catalogue in the language it was first read in, and
## the language can be changed from the pause menu mid-run.
static func _generated(element: String, behavior: String, requires: Array) -> Dictionary:
	var shape: Dictionary = BEHAVIOR_TEMPLATES[behavior]
	return {
		"id": "%s_%s" % [element, behavior],
		"internal_id": "RESONANCE_%s_%s" % [element.to_upper(), behavior.to_upper()],
		"name": "%s %s" % [ELEMENT_WORDS[element], BEHAVIOR_WORDS[behavior]],
		"description": String(shape["description"]) % [TAG_NAMES[element], ELEMENT_RIDERS[element]],
		"name_parts": [ELEMENT_WORDS[element], BEHAVIOR_WORDS[behavior]],
		"description_parts": [String(shape["description"]), TAG_NAMES[element], ELEMENT_RIDERS[element]],
		"requires": requires,
		"kind": "template",
		"template": String(shape["template"]),
		"element": element,
		"behavior": behavior,
		"cooldown": float(shape["cooldown"]),
	}


## Checks every weapon pair across both players' loadouts (up to 3x3) rather
## than a single fixed pair, since either player may be carrying weapons
## picked up from other characters. requires[] is matched against weapon
## ["tags"] — tags live on the weapon itself (a borrowed weapon keeps its
## source character's tags, not the player's own).
func get_candidates_for_loadouts(loadout_a: Array, loadout_b: Array) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if active_resonances.size() >= MAX_ACTIVE_RESONANCES:
		return candidates
	var active_ids: Dictionary = {}
	for active in active_resonances:
		active_ids[String(active["id"])] = true
	var seen_ids: Dictionary = {}
	# Resonance is the top of the tree, not a mid-run bonus: only enhanced
	# weapons reach it. A weapon already backing an active resonance cannot earn
	# a second one — it is spent, which is what keeps two resonances costing four
	# weapon slots rather than two.
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
			for resonance in all_resonances():
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
				# two weapons it is spending.
				candidate["weapon_a_slot"] = slot_a
				candidate["weapon_b_slot"] = slot_b
				candidates.append(candidate)
	return candidates


## Whether this pair of weapons satisfies a resonance.
##
## Every requirement has to be present across the two tag sets, and each survivor
## has to supply at least one of them — that second half is what keeps a
## resonance a pair's move rather than something one player qualifies for alone.
## The rule is stated on the candidate card rather than left to be discovered
## (§14), because a condition a player can fail without seeing why is the thing
## this whole system was rebuilt to remove.
##
## Written against the sets rather than against `requires[0]` and `requires[1]`
## in both orders, which is what the old test did: correct for exactly two tags,
## silently wrong for any other number.
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
	# satisfy this — deliberately — but one survivor alone never can, because the
	# other side supplies nothing.
	return from_a and from_b


## How many candidates the selection screen can show at once.
const VOTE_CHOICES := 3


## The candidates worth putting on the selection screen, best first.
##
## Ranked by how *specific* a resonance is to this build: one that only a single
## weapon pair in the two loadouts can produce beats one that half the loadout
## satisfies incidentally, and a hand-made resonance beats a generated one,
## because a combination somebody wrote an effect for is a combination the pair
## was more likely aiming at. Ties keep catalogue order, so the list is stable
## between two openings that changed nothing.
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
		var first_unique := String(first.get("kind", "")) == "unique"
		var second_unique := String(second.get("kind", "")) == "unique"
		if first_unique != second_unique:
			return first_unique
		var first_pairs := int(produced_by[first_id])
		var second_pairs := int(produced_by[second_id])
		if first_pairs != second_pairs:
			return first_pairs < second_pairs
		return int(order[first_id]) < int(order[second_id]))
	return unique.slice(0, limit)


## A boss died and left a core. Held until the pair spends it on a candidate.
func grant_core() -> void:
	pending_cores += 1


## Whether a held core can still buy anything. A core with no free slot and a
## core with no matching candidate are both dead weight, and the caller checks
## both before it opens a screen about one.
func has_free_slot() -> bool:
	return active_resonances.size() < MAX_ACTIVE_RESONANCES


func activate(resonance: Dictionary) -> void:
	var entry := resonance.duplicate(true)
	# The catalogue cooldown is the real cooldown. Nothing is applied on top of
	# it here, so a number in the catalogue is a number a player can be shown.
	entry["cooldown"] = float(resonance["cooldown"])
	entry["cooldown_remaining"] = 1.2
	active_resonances.append(entry)
	pending_cores = maxi(0, pending_cores - 1)


## Whether this weapon slot already feeds an active resonance.
##
## One weapon cannot back two resonances at once — two may be active and a
## survivor may carry three weapons, so without this a pair could run two
## resonances off fewer weapons than earned them. The HUD marks a bound slot in
## gold, and the candidate card says so too (§17).
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
