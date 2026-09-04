extends SceneTree

const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "SURVIVOR_BALANCE_FAIL", 30.0)
	call_deferred("_run")


## The roster is meant to grow, and "is the new one fair?" is not answerable by
## reading six dictionaries. CharacterCatalog states two budgets; this asserts
## every survivor sits inside them, so adding a seventh either lands in the band
## or fails here with the number it missed by.
func _run() -> void:
	var roster := CharacterCatalog.all_characters()
	_check(roster.size() >= 2, "the roster has survivors in it")

	var ids: Dictionary = {}
	var weapon_ids: Dictionary = {}
	var survival_line: Array[String] = []
	var power_line: Array[String] = []

	for character in roster:
		var name := String(character["name"])
		var survival := CharacterCatalog.survival_budget(character)
		var power := CharacterCatalog.power_budget(character)
		survival_line.append("%s %.3f" % [name, survival])
		power_line.append("%s %.1f" % [name, power])

		_check(survival >= CharacterCatalog.SURVIVAL_BUDGET_MIN and survival <= CharacterCatalog.SURVIVAL_BUDGET_MAX,
			"%s's survival budget is inside the band (%.3f, band %.2f-%.2f)" % [
				name, survival, CharacterCatalog.SURVIVAL_BUDGET_MIN, CharacterCatalog.SURVIVAL_BUDGET_MAX])
		_check(power >= CharacterCatalog.POWER_BUDGET_MIN and power <= CharacterCatalog.POWER_BUDGET_MAX,
			"%s's power budget is inside the band (%.1f, band %.0f-%.0f)" % [
				name, power, CharacterCatalog.POWER_BUDGET_MIN, CharacterCatalog.POWER_BUDGET_MAX])

		# A budget only means anything if every field it reads is actually there.
		var weapon: Dictionary = character["weapon"]
		_check(weapon.has("reach"), "%s's weapon declares a reach factor" % name)
		_check(float(weapon.get("reach", 0.0)) > 0.0, "%s's reach factor is positive" % name)
		_check(float(weapon["cooldown"]) > 0.0, "%s's cooldown is positive" % name)
		_check(int(weapon.get("tier", 0)) == 1, "%s starts at tier 1" % name)

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

	print("SURVIVOR_SURVIVAL: " + "  ·  ".join(survival_line))
	print("SURVIVOR_POWER: " + "  ·  ".join(power_line))

	# The bands are only useful if they are tighter than the spread they were
	# drawn around; a band wide enough to admit anything asserts nothing.
	var survival_spread := CharacterCatalog.SURVIVAL_BUDGET_MAX - CharacterCatalog.SURVIVAL_BUDGET_MIN
	_check(survival_spread <= 0.25, "the survival band is tight enough to mean something (%.2f)" % survival_spread)
	var power_spread := CharacterCatalog.POWER_BUDGET_MAX - CharacterCatalog.POWER_BUDGET_MIN
	_check(power_spread <= 10.0, "the power band is tight enough to mean something (%.1f)" % power_spread)

	if failures.is_empty():
		print("SURVIVOR_BALANCE_PASS: every survivor is inside both budgets")
		quit(0)
	else:
		for failure in failures:
			push_error("SURVIVOR_BALANCE_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
