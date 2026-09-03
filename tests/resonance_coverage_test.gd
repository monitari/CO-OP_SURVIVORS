extends SceneTree

const CharacterData := preload("res://scripts/character_catalog.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_COVERAGE_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	var characters := CharacterData.all_characters()
	var resonance := ResonanceScript.new() as ResonanceSystem
	var t3_weapon := {"tier": 3}

	# Duplicate picks are legal in character select (nothing in main.gd rejects
	# choosing the same survivor twice), so every ordered-with-repeats pair over
	# the six-character roster is a reachable lobby outcome and must resolve to
	# at least one resonance candidate once both weapons hit tier 3.
	var uncovered: Array[String] = []
	for i in characters.size():
		for j in range(i, characters.size()):
			var a: Dictionary = characters[i]
			var b: Dictionary = characters[j]
			var candidates := resonance.get_candidates(a, b, t3_weapon, t3_weapon)
			if candidates.is_empty():
				uncovered.append("%s + %s" % [String(a["name"]), String(b["name"])])

	_check(uncovered.is_empty(), "every character pair (incl. duplicates) has >=1 resonance candidate: " + ", ".join(uncovered))

	# The lockout guard (one resonance per run) must still hold: an active
	# resonance suppresses new candidates regardless of tag match.
	resonance.activate(resonance.catalog[0])
	var locked := resonance.get_candidates(characters[0], characters[1], t3_weapon, t3_weapon)
	_check(locked.is_empty(), "an active resonance blocks new candidates")

	# Below tier 3 nothing should ever surface, even for a covered pair.
	resonance.active_resonance = {}
	var undertiered := resonance.get_candidates(characters[0], characters[1], {"tier": 2}, t3_weapon)
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
