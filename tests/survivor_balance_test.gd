extends SceneTree

const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "SURVIVOR_BALANCE_FAIL", 30.0)
	call_deferred("_run")


## Two questions, and they pull against each other on purpose.
##
## "Is this survivor fair?" is answered by one budget over all six axes, so a
## cat may be extreme anywhere as long as it pays for it somewhere else.
##
## "Are these survivors actually different?" is the question the old test never
## asked, which is how the roster ended up varying by 25% in health, 18% in
## speed and nothing else at all. A budget alone is perfectly satisfied by ten
## identical cats, so the spread floors are asserted separately — and they are
## what fails if someone flattens the roster back out to make the budget easier
## to hit.
func _run() -> void:
	var roster := CharacterCatalog.all_characters()
	_check(roster.size() >= 2, "the roster has survivors in it")

	var ids: Dictionary = {}
	var weapon_ids: Dictionary = {}
	var budget_line: Array[String] = []
	var power_line: Array[String] = []
	var extended_signatures: Dictionary = {}

	for character in roster:
		var name := String(character["name"])
		var budget := CharacterCatalog.total_budget(character)
		budget_line.append("%s %.3f" % [name, budget])
		power_line.append("%s %.1f" % [name, CharacterCatalog.power_budget(character)])

		_check(budget >= CharacterCatalog.TOTAL_BUDGET_MIN and budget <= CharacterCatalog.TOTAL_BUDGET_MAX,
			"%s's total budget is inside the band (%.3f, band %.2f-%.2f)" % [
				name, budget, CharacterCatalog.TOTAL_BUDGET_MIN, CharacterCatalog.TOTAL_BUDGET_MAX])

		# A budget only means anything if every field it reads is actually there.
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

	print("SURVIVOR_BUDGET: " + "  ·  ".join(budget_line))
	print("SURVIVOR_POWER: " + "  ·  ".join(power_line))
	_test_axes_are_wide(roster)
	_test_leash_is_a_real_choice(roster)
	_test_the_normaliser_still_matches_the_roster(roster)

	# Difficulty labels no longer appear in character select. Distinct combat
	# signatures are the useful choice now, and no two cats may collapse to the
	# same four extended stats.
	_check(extended_signatures.size() == roster.size(),
		"every survivor has a distinct extended combat signature")

	# The band is only useful if it is tighter than the spread it was drawn
	# around; a band wide enough to admit anything asserts nothing.
	var band := CharacterCatalog.TOTAL_BUDGET_MAX - CharacterCatalog.TOTAL_BUDGET_MIN
	_check(band <= 0.15, "the budget band is tight enough to mean something (%.2f)" % band)

	if failures.is_empty():
		print("SURVIVOR_BALANCE_PASS: every survivor is inside the budget and the roster still spreads")
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


## The offense term divides by a constant that has to stay pinned to the
## roster's actual power level. Nothing enforces that on its own, and the
## failure is silent and total: rebalance every weapon downward and the divisor
## stays where it was, so all ten survivors read as under-budget and the band —
## the one thing keeping them fair to each other — starts rejecting a perfectly
## fair roster. The tolerance is loose because the constant sits a little under
## the mean by design (crit is priced on top of it); what it catches is the
## constant being left behind entirely.
func _test_the_normaliser_still_matches_the_roster(roster: Array[Dictionary]) -> void:
	var mean := 0.0
	for character in roster:
		mean += CharacterCatalog.raw_power(character)
	mean /= float(roster.size())
	var drift: float = absf(mean - CharacterCatalog.OFFENSE_REFERENCE) / CharacterCatalog.OFFENSE_REFERENCE
	_check(drift <= 0.15,
		"the offense normaliser is still the roster mean (%.1f vs %.1f, %.0f%% off)" % [
			CharacterCatalog.OFFENSE_REFERENCE, mean, drift * 100.0])
	print("SURVIVOR_NORMALISER: reference %.1f  mean %.1f" % [CharacterCatalog.OFFENSE_REFERENCE, mean])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
