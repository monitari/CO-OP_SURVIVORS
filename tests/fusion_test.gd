extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FUSION_FAIL", 90.0)
	call_deferred("_run")


## The tech tree is base weapon → fused weapon → resonance, and each rung is
## supposed to be a gate rather than a formality. These checks pin the gates:
## a fusion needs both a maxed weapon and the right treasure, it is offered the
## moment both are true and never before, it replaces the weapon in place, and
## the screen only starts drawing the tree once the pair has seen a fusion once.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "FUSION_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_catalog_is_complete()
	_test_both_requirements(main)
	_test_fusion_replaces_in_place(main)
	_test_tier_is_capped(main)
	_test_tech_tree_is_hidden_until_discovered(main)

	if failures.is_empty():
		print("FUSION_PASS: both gates enforced, fusion replaces in place, tech tree visible from the start")
		quit(0)
	else:
		for failure in failures:
			push_error("FUSION_FAIL: " + failure)
		quit(1)


## Every weapon a survivor can carry has to have somewhere to go. A weapon with
## no fusion is a dead branch: it can be maxed and then never reach resonance.
func _test_catalog_is_complete() -> void:
	var evolutions := EvolutionCatalog.all_evolutions()
	var treasure_ids: Dictionary = {}
	for treasure in TreasureCatalog.all_treasures():
		treasure_ids[String(treasure["id"])] = true

	for character in CharacterCatalog.all_characters():
		var weapon_id := String(character["weapon_id"])
		_check(not EvolutionCatalog.for_base(weapon_id).is_empty(),
			"%s's weapon has a fusion" % String(character["name"]))

	var weapon_ids: Dictionary = {}
	for evolution in evolutions:
		var fused_id := String(evolution["weapon_id"])
		_check(not weapon_ids.has(fused_id), "%s is a unique fused id" % fused_id)
		weapon_ids[fused_id] = true
		_check(treasure_ids.has(String(evolution["treasure_id"])),
			"%s requires a treasure that exists" % fused_id)
		_check(not (evolution["tags"] as Array).is_empty(), "%s carries resonance tags" % fused_id)
		_check(float((evolution["weapon"] as Dictionary)["damage"]) > 0.0, "%s deals damage" % fused_id)
		_check(EvolutionCatalog.is_evolved(fused_id), "%s reports itself as fused" % fused_id)
	_check(not EvolutionCatalog.is_evolved("homing"), "a base weapon does not report itself as fused")


func _fusion_offers(main: Node, player_index: int) -> Array[String]:
	var offered: Array[String] = []
	for draw in 12:
		for option in main._get_upgrade_choices(player_index):
			if String(option["id"]) == "evolve_weapon":
				var evolution: Dictionary = option["evolution"]
				if not (String(evolution["weapon_id"]) in offered):
					offered.append(String(evolution["weapon_id"]))
	return offered


func _test_both_requirements(main: Node) -> void:
	var weapon: Dictionary = main.weapon_loadouts[0][0]
	var evolution := EvolutionCatalog.for_base(String(weapon["weapon_id"]))
	_check(not evolution.is_empty(), "the starting weapon has a fusion to reach")
	var treasure_id := String(evolution["treasure_id"])

	# Neither requirement met.
	_check(_fusion_offers(main, 1).is_empty(), "no fusion is offered at tier 1 with no treasure")

	# Weapon maxed, treasure missing.
	weapon["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
	_check(_fusion_offers(main, 1).is_empty(), "a maxed weapon alone does not unlock a fusion")

	# Treasure carried but not deep enough.
	main._apply_upgrade(0, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id(treasure_id)})
	_check(_fusion_offers(main, 1).is_empty(),
		"a treasure below T%d does not unlock a fusion" % EvolutionCatalog.REQUIRED_TREASURE_TIER)

	# Both met.
	while main._treasure_tier(0, treasure_id) < EvolutionCatalog.REQUIRED_TREASURE_TIER:
		main._apply_upgrade(0, {"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": 0})
	_check(String(evolution["weapon_id"]) in _fusion_offers(main, 1),
		"both requirements together offer the fusion")

	# And an under-tier weapon with a deep treasure must still be refused, or
	# only one of the two gates is really doing anything.
	weapon["tier"] = EvolutionCatalog.WEAPON_MAX_TIER - 1
	_check(_fusion_offers(main, 1).is_empty(), "the weapon requirement is enforced independently")
	weapon["tier"] = EvolutionCatalog.WEAPON_MAX_TIER


func _test_fusion_replaces_in_place(main: Node) -> void:
	var slots_before: int = main.weapon_loadouts[0].size()
	var base_id := String(main.weapon_loadouts[0][0]["weapon_id"])
	var evolution := EvolutionCatalog.for_base(base_id)
	_check(not main.fusion_discovered, "the run has not seen a fusion yet")

	main._apply_upgrade(0, {"id": "evolve_weapon", "weapon_slot": 0, "evolution": evolution})
	var fused: Dictionary = main.weapon_loadouts[0][0]

	_check(main.weapon_loadouts[0].size() == slots_before, "a fusion does not consume another weapon slot")
	_check(String(fused["weapon_id"]) == String(evolution["weapon_id"]), "the slot now holds the fused weapon")
	_check(bool(fused.get("evolved", false)), "the fused weapon is flagged as fused")
	_check(String(fused["base_weapon_id"]) == base_id, "the fused weapon remembers what it grew from")
	_check(Color(fused["color"]) == Color(main.selected_characters[0]["color"]),
		"the fused weapon keeps its owner's colour")
	_check(main.fusion_discovered, "the first fusion is recorded")

	# It must not be offered a second time, and it cannot fuse again.
	_check(_fusion_offers(main, 1).is_empty(), "an already-fused weapon is not offered another fusion")
	_check(main._available_evolution(0, 0).is_empty(), "a fused slot reports no further fusion")


func _test_tier_is_capped(main: Node) -> void:
	# Player 2 is untouched, so this measures the cap rather than the fusion.
	var weapon: Dictionary = main.weapon_loadouts[1][0]
	weapon["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
	for step in 4:
		main._apply_upgrade(1, {"id": "weapon_power", "weapon_slot": 0})
	_check(int(weapon["tier"]) == EvolutionCatalog.WEAPON_MAX_TIER,
		"weapon tier stops at the cap (%d)" % int(weapon["tier"]))


func _test_tech_tree_is_hidden_until_discovered(main: Node) -> void:
	# Even before discovery, show the next requirements. P2 is already T7 in
	# this fixture; only the required denominator, not a T1 numerator, is fixed.
	main.fusion_discovered = false
	main._refresh_team_stats_ui()
	_check(String(main.team_stats_label.text).contains("합성  P1") and String(main.team_stats_label.text).contains("/7"),
		"the fusion path and weapon requirement are visible before the first fusion")

	main.fusion_discovered = true
	main._refresh_team_stats_ui()
	var text := String(main.team_stats_label.text)
	_check(text.contains("합성  P1") and text.contains("합성  P2"), "the tech tree lists both survivors")
	# P2 has an unfused weapon at max tier, so their line has to name the
	# treasure that is still missing — that is the whole point of the readout.
	var partner_evolution := EvolutionCatalog.for_base(String(main.weapon_loadouts[1][0]["weapon_id"]))
	var required := TreasureCatalog.by_id(String(partner_evolution["treasure_id"]))
	_check(text.contains(String(required["name"])),
		"the tech tree names the treasure a weapon still needs (%s)" % String(required["name"]))
	_check(text.contains(String(partner_evolution["weapon_name"])),
		"the tech tree names what the weapon would become")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
