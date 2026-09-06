extends SceneTree

const CharacterData := preload("res://scripts/catalogs/character_catalog.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_COVERAGE_FAIL", 30.0)
	call_deferred("_run")


## Resonance is fusion-only now, so coverage is a property of the fused roster
## rather than the starting one. A fused weapon is what this has to feed in.
func _fused_dict(evolution: Dictionary) -> Dictionary:
	return {
		"evolved": true,
		"tier": EvolutionCatalog.WEAPON_MAX_TIER,
		"tags": evolution["tags"],
		"weapon_name": evolution["weapon_name"],
	}


## A weapon that has NOT fused, for the checks that it cannot reach resonance.
func _base_dict(character: Dictionary, tier: int) -> Dictionary:
	return {"tier": tier, "tags": character["tags"], "weapon_name": character["weapon_name"]}


func _run() -> void:
	var characters := CharacterData.all_characters()
	var resonance := ResonanceScript.new() as ResonanceSystem

	# Duplicate picks are legal in character select, so every pair-with-repeats
	# over the fused roster is a reachable endgame and must resolve to at least
	# one candidate. A pair that fuses both weapons and is then told there is no
	# resonance for them has hit a dead end at the top of the tech tree.
	var evolutions := EvolutionCatalog.all_evolutions()
	var uncovered: Array[String] = []
	for i in evolutions.size():
		for j in range(i, evolutions.size()):
			var a: Dictionary = evolutions[i]
			var b: Dictionary = evolutions[j]
			resonance.active_resonances.clear()
			var candidates := resonance.get_candidates_for_loadouts([_fused_dict(a)], [_fused_dict(b)])
			if candidates.is_empty():
				uncovered.append("%s + %s" % [String(a["weapon_name"]), String(b["weapon_name"])])

	_check(uncovered.is_empty(), "every fused weapon pair (incl. duplicates) has >=1 resonance candidate: " + ", ".join(uncovered))
	resonance.active_resonances.clear()

	# And an unfused weapon must never reach it, however deeply upgraded.
	var maxed_base := _base_dict(characters[0], EvolutionCatalog.WEAPON_MAX_TIER)
	_check(resonance.get_candidates_for_loadouts([maxed_base], [_fused_dict(evolutions[1])]).is_empty(),
		"a maxed but unfused weapon produces no candidate")
	_check(resonance.get_candidates_for_loadouts([maxed_base], [_base_dict(characters[1], EvolutionCatalog.WEAPON_MAX_TIER)]).is_empty(),
		"two maxed unfused weapons produce no candidate")

	# A run no longer locks to one resonance forever — it caps at
	# MAX_ACTIVE_RESONANCES, and an id already active must not be re-offered.
	var loadout_a := [_fused_dict(evolutions[0])]
	var loadout_b := [_fused_dict(evolutions[1])]
	resonance.activate(resonance.catalog[0])
	var still_available := resonance.get_candidates_for_loadouts(loadout_a, loadout_b)
	var first_id := String(resonance.catalog[0]["id"])
	var reoffered := false
	for candidate in still_available:
		if String(candidate["id"]) == first_id:
			reoffered = true
	_check(not reoffered, "an already-active resonance id is not offered again")
	_check(not still_available.is_empty(), "activating one resonance does not block the rest while under the cap")

	# Fill the cap with resonances this pair could never match anyway (they need
	# fire/frost/melee tags lyra and volta do not have), so that an empty result
	# can only be the cap talking — not the already-active-id filter, which
	# would otherwise mask a broken cap entirely.
	resonance.active_resonances.clear()
	for unreachable_id in ["frost_shade", "sacred_flame_vow", "inferno_crescent"]:
		for entry in resonance.catalog:
			if String(entry["id"]) == unreachable_id:
				resonance.activate(entry)
	_check(resonance.active_resonances.size() == resonance.MAX_ACTIVE_RESONANCES, "the cap test actually reached MAX_ACTIVE_RESONANCES")
	var locked := resonance.get_candidates_for_loadouts(loadout_a, loadout_b)
	_check(locked.is_empty(), "reaching MAX_ACTIVE_RESONANCES blocks all new candidates")

	resonance.active_resonances.clear()
	var unfused := resonance.get_candidates_for_loadouts([_base_dict(characters[0], 3)], loadout_b)
	_check(unfused.is_empty(), "a tier-3 weapon no longer reaches resonance on its own")

	resonance.free()

	if failures.is_empty():
		print("RESONANCE_COVERAGE_PASS: all %d fused pairs resolve to a candidate" % (evolutions.size() * (evolutions.size() + 1) / 2))
		quit(0)
	else:
		for failure in failures:
			push_error("RESONANCE_COVERAGE_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
