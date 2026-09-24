extends SceneTree

const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "SURVIVOR_BALANCE_FAIL", 30.0)
	call_deferred("_run")


## Non-weapon identity and roster data stay covered here. Live weapon fairness
## is measured separately by weapon_balance_test.gd against crowds and a
## single large target; reach-based catalogue budgets concealed the real gap.
func _run() -> void:
	var roster := CharacterCatalog.all_characters()
	_check(roster.size() >= 2, "the roster has survivors in it")

	var ids: Dictionary = {}
	var weapon_ids: Dictionary = {}
	var extended_signatures: Dictionary = {}

	for character in roster:
		var name := String(character["name"])
		# Every roster entry needs the fields used by combat and character select.
		for field: String in ["health", "speed", "armor", "crit", "pickup", "chain", "might", "area", "haste", "recovery"]:
			_check(character.has(field), "%s declares %s" % [name, field])
		var weapon: Dictionary = character["weapon"]
		_check(weapon.has("reach"), "%s's weapon declares a reach factor" % name)
		_check(float(weapon.get("reach", 0.0)) > 0.0, "%s's reach factor is positive" % name)
		_check(float(weapon["cooldown"]) > 0.0, "%s's cooldown is positive" % name)
		_check(int(weapon.get("tier", 0)) == 1, "%s starts at tier 1" % name)
		_check(float(character["health"]) > 0.0, "%s has health" % name)
		_check(float(character["speed"]) > 0.0, "%s can move" % name)
		_check(float(character["armor"]) >= 0.0, "%s's armor is not negative" % name)

		# Identity fields the rest of the game indexes by. A duplicate here would
		# silently make one survivor unreachable in the roster or the icon atlas.
		var character_id := String(character["id"])
		var weapon_id := String(character["weapon_id"])
		_check(not ids.has(character_id), "%s's id is unique" % name)
		_check(not weapon_ids.has(weapon_id), "%s's weapon id is unique" % name)
		ids[character_id] = true
		weapon_ids[weapon_id] = true
		_check(GameIconCatalog.survivor(character_id) != null, "%s has a portrait icon" % name)
		_check(GameIconCatalog.weapon(weapon_id) != null, "%s's weapon has an icon" % name)
		_check(not (character["tags"] as Array).is_empty(), "%s has resonance tags" % name)

		extended_signatures["%.2f:%.2f:%.2f:%.2f" % [character["might"], character["area"], character["haste"], character["recovery"]]] = true

	_test_axes_are_wide(roster)
	_test_leash_is_a_real_choice(roster)

	# Difficulty labels no longer appear in character select. Distinct combat
	# signatures are the useful choice now, and no two cats may collapse to the
	# same four extended stats.
	_check(extended_signatures.size() == roster.size(),
		"every survivor has a distinct extended combat signature")

	if failures.is_empty():
		print("SURVIVOR_BALANCE_PASS: roster data and non-weapon axes still spread")
		quit(0)
	else:
		for failure in failures:
			push_error("SURVIVOR_BALANCE_FAIL: " + failure)
		quit(1)


## The roster has to actually use each axis. Ratio axes are checked as max/min
## and additive ones as max-min, matching how CharacterCatalog.SPREAD_FLOORS is
## written, and every floor is reported with the measured value so a failure
## says how far short it fell rather than only that it did.
func _test_axes_are_wide(roster: Array[Dictionary]) -> void:
	var report: Array[String] = []
	for field: String in CharacterCatalog.SPREAD_FLOORS:
		var low := INF
		var high := -INF
		for character in roster:
			var value := float(character[field])
			low = minf(low, value)
			high = maxf(high, value)
		var floor_value := float(CharacterCatalog.SPREAD_FLOORS[field])
		var ratio_axis := field in ["health", "speed", "pickup"]
		var measured := (high / maxf(0.0001, low)) if ratio_axis else (high - low)
		report.append("%s %.2f..%.2f (%s %.2f)" % [
			field, low, high, "x" if ratio_axis else "d", measured])
		_check(measured >= floor_value,
			"the roster spreads across %s (%.2f, floor %.2f)" % [field, measured, floor_value])
	print("SURVIVOR_SPREAD: " + "  ·  ".join(report))


## The leash is the one stat that is decided by the pair rather than by either
## survivor, so it is checked as a pair: the shortest possible chain and the
## longest have to be different enough that picking for it is a real decision.
func _test_leash_is_a_real_choice(roster: Array[Dictionary]) -> void:
	var shortest := INF
	var longest := -INF
	for first in roster:
		for second in roster:
			var length := CharacterCatalog.chain_length_for(first, second)
			shortest = minf(shortest, length)
			longest = maxf(longest, length)
	_check(shortest > 200.0, "even the shortest pairing leaves room to fight (%.0f)" % shortest)
	_check(longest / shortest >= 1.5,
		"the leash a pair ends up with is a real choice (%.0f to %.0f)" % [shortest, longest])
	print("SURVIVOR_LEASH: %.0f - %.0f" % [shortest, longest])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
