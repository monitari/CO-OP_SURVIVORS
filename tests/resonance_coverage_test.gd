extends SceneTree

const CharacterData := preload("res://scripts/character_catalog.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_COVERAGE_FAIL", 30.0)
	call_deferred("_run")


## A single-weapon loadout matching what a character starts a run with —
## tags now live on the weapon itself, not the character, so this is how
## get_candidates_for_loadouts() must be fed even for the "one weapon each"
## baseline case this test covers.
func _weapon_dict(character: Dictionary, tier: int) -> Dictionary:
	return {"tier": tier, "tags": character["tags"], "weapon_name": character["weapon_name"]}


func _run() -> void:
	var characters := CharacterData.all_characters()
	var resonance := ResonanceScript.new() as ResonanceSystem

	# Duplicate picks are legal in character select (nothing in main.gd rejects
	# choosing the same survivor twice), so every ordered-with-repeats pair over
	# the six-character roster is a reachable lobby outcome and must resolve to
	# at least one resonance candidate once both weapons hit tier 3.
	var uncovered: Array[String] = []
	for i in characters.size():
		for j in range(i, characters.size()):
			var a: Dictionary = characters[i]
			var b: Dictionary = characters[j]
			var candidates := resonance.get_candidates_for_loadouts([_weapon_dict(a, 3)], [_weapon_dict(b, 3)])
			if candidates.is_empty():
				uncovered.append("%s + %s" % [String(a["name"]), String(b["name"])])

	_check(uncovered.is_empty(), "every character pair (incl. duplicates) has >=1 resonance candidate: " + ", ".join(uncovered))

	# A run no longer locks to one resonance forever — it caps at
	# MAX_ACTIVE_RESONANCES, and an id already active must not be re-offered.
	var loadout_a := [_weapon_dict(characters[0], 3)]
	var loadout_b := [_weapon_dict(characters[1], 3)]
	resonance.activate(resonance.catalog[0])
	var still_available := resonance.get_candidates_for_loadouts(loadout_a, loadout_b)
	var first_id := String(resonance.catalog[0]["id"])
	var reoffered := false
	for candidate in still_available:
		if String(candidate["id"]) == first_id:
			reoffered = true
	_check(not reoffered, "an already-active resonance id is not offered again")
	_check(not still_available.is_empty(), "activating one resonance does not block the rest while under the cap")

	while resonance.active_resonances.size() < resonance.MAX_ACTIVE_RESONANCES:
		resonance.activate(resonance.catalog[resonance.active_resonances.size()])
	var locked := resonance.get_candidates_for_loadouts(loadout_a, loadout_b)
	_check(locked.is_empty(), "reaching MAX_ACTIVE_RESONANCES blocks all new candidates")

	# Below tier 3 nothing should ever surface, even for a covered pair.
	resonance.active_resonances = []
	var undertiered := resonance.get_candidates_for_loadouts([_weapon_dict(characters[0], 2)], loadout_b)
	_check(undertiered.is_empty(), "sub-tier-3 weapons never produce a candidate")

	resonance.free()

	if failures.is_empty():
		print("RESONANCE_COVERAGE_PASS: all %d character pairs resolve to a candidate" % (characters.size() * (characters.size() + 1) / 2))
		quit(0)
	else:
		for failure in failures:
			push_error("RESONANCE_COVERAGE_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
