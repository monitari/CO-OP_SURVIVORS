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
		"tags": EvolutionCatalog.tags_of(evolution),
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
	var evolutions := EvolutionCatalog.all_fusions()
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
	# fire/frost/melee tags the two fixtures do not have), so that an empty
	# result can only be the cap talking — not the already-active-id filter,
	# which would otherwise mask a broken cap entirely.
	resonance.active_resonances.clear()
	var unreachable: Array[String] = []
	var pair_tags: Array = EvolutionCatalog.tags_of(evolutions[0]) + EvolutionCatalog.tags_of(evolutions[1])
	for entry in resonance.catalog:
		if unreachable.size() >= resonance.MAX_ACTIVE_RESONANCES:
			break
		var reachable := false
		for tag in entry["requires"]:
			reachable = reachable or (tag in pair_tags)
		if not reachable:
			unreachable.append(String(entry["id"]))
			resonance.activate(entry)
	_check(resonance.active_resonances.size() == resonance.MAX_ACTIVE_RESONANCES, "the cap test actually reached MAX_ACTIVE_RESONANCES")
	var locked := resonance.get_candidates_for_loadouts(loadout_a, loadout_b)
	_check(locked.is_empty(), "reaching MAX_ACTIVE_RESONANCES blocks all new candidates")

	resonance.active_resonances.clear()
	var unfused := resonance.get_candidates_for_loadouts([_base_dict(characters[0], 3)], loadout_b)
	_check(unfused.is_empty(), "a tier-3 weapon no longer reaches resonance on its own")

	# §11. Tags alone never switch a resonance on: a core is what does that, and
	# a run hands out exactly as many cores as there are slots.
	resonance.active_resonances.clear()
	resonance.pending_cores = 0
	_check(not resonance.get_candidates_for_loadouts(loadout_a, loadout_b).is_empty(),
		"a matching pair produces candidates")
	_check(resonance.active_resonances.is_empty(),
		"but merely producing candidates activates nothing")
	resonance.grant_core()
	_check(resonance.pending_cores == 1, "a boss core is held until it is spent")
	resonance.activate(resonance.get_candidates_for_loadouts(loadout_a, loadout_b)[0])
	_check(resonance.active_resonances.size() == 1 and resonance.pending_cores == 0,
		"spending the core is what activates the resonance")

	# §16. The catalogue cooldown is the cooldown the game uses. A global scale
	# applied on activation made every number in the catalogue wrong.
	resonance.active_resonances.clear()
	var sample: Dictionary = resonance.catalog[0]
	resonance.activate(sample)
	_check(is_equal_approx(float(resonance.active_resonances[0]["cooldown"]), float(sample["cooldown"])),
		"an activated resonance keeps its catalogue cooldown (%.2f vs %.2f)" % [
			float(resonance.active_resonances[0]["cooldown"]), float(sample["cooldown"])])

	# §15. Most of the catalogue is generated from element x behaviour, and the
	# hand-written ones are the exception rather than the rule.
	var uniques := 0
	var templates := 0
	for entry in resonance.catalog:
		if String(entry["kind"]) == "unique":
			uniques += 1
		else:
			templates += 1
			_check(not String(entry.get("template", "")).is_empty(),
				"%s is generated but names no template" % entry["id"])
	_check(uniques > 0 and templates > 0, "the catalogue has both hand-made and generated resonances")

	resonance.free()

	if failures.is_empty():
		print("RESONANCE_COVERAGE_PASS: all %d enhanced pairs resolve to a candidate, cores gate activation, cooldowns are per-resonance" % (evolutions.size() * (evolutions.size() + 1) / 2))
		quit(0)
	else:
		for failure in failures:
			push_error("RESONANCE_COVERAGE_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
