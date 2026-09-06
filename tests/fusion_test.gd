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
## the ordinary growth cards do not reveal material paths before completion.
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
	_test_growth_selection_hides_material_hints(main)

	if failures.is_empty():
		print("FUSION_PASS: both gates enforced, fusion replaces in place, growth cards hide material paths")
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


## A recipe remains hidden until both ingredients are carried. At that point the
## involved card shows the *other* ingredient in its corner, while the result
## stays unknown until it has actually been discovered.
func _test_growth_selection_hides_material_hints(main: Node) -> void:
	main.fusion_discovered = false
	main._refresh_level_up_ui()
	# The whole screen rather than the one label the table used to live in: the
	# strip is gone entirely now, and an assertion pointed at an empty label
	# would pass no matter what the rest of the screen said.
	var shown := _growth_screen_text(main)
	for evolution in EvolutionCatalog.all_evolutions():
		_check(not shown.contains(String(evolution["weapon_name"])),
			"the growth screen does not name the fusion %s" % String(evolution["weapon_name"]))
	_check(not shown.contains("→ "), "and does not lay the requirements out as a table")
	_check(not shown.contains("미지의 합성") and not shown.contains("합성 재료"),
		"and does not label an offered card as a hidden fusion material")
	# It still has to say where the run is, or the screen is a card rack with no
	# context: the title carries the shared level.
	_check(shown.contains("LV."), "the screen still says what level this is")

	for side: Array in main.level_card_labels:
		for card: Label in side:
			_check(card.has_node("FusionMark"), "every growth card has a conditional fusion seal")
			_check(not card.get_node("FusionMark").visible,
				"the fusion seal stays hidden before both ingredients are owned")

	var weapon: Dictionary = main.weapon_loadouts[1][0]
	var evolution := EvolutionCatalog.for_base(String(weapon["weapon_id"]))
	var treasure := TreasureCatalog.by_id(String(evolution["treasure_id"]))
	var hidden_line: String = main._fusion_progress_line(1)
	_check(hidden_line.contains("???") and not hidden_line.contains(String(treasure["name"])),
		"full stats hides the absent fusion ingredient")

	main._apply_upgrade(1, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	var revealed_choices: Array[Dictionary] = [{
		"id": "weapon_power", "weapon_slot": 0,
		"title": "마력 증폭\n%s" % String(weapon["weapon_name"]),
		"description": main._upgrade_preview(1, {"id": "weapon_power", "weapon_slot": 0}),
	}]
	main.p2_choices = revealed_choices
	main._refresh_level_up_ui()
	var mark := main.level_card_labels[1][0].get_node("FusionMark") as TextureRect
	_check(mark.visible and mark.texture != null,
		"owning both ingredients reveals the partner icon on its growth card")
	_check(mark.tooltip_text.contains(String(treasure["name"])) and mark.tooltip_text.contains("합치면 합성됩니다"),
		"the seal explains which owned item combines with this card")
	var revealed_line: String = main._fusion_progress_line(1)
	_check(revealed_line.contains(String(treasure["name"])),
		"full stats reveals the relationship once both ingredients are owned")


## Every piece of text on the growth screen, joined.
func _growth_screen_text(main: Node) -> String:
	var parts: Array[String] = []
	_collect_text(main.level_overlay, parts)
	return "\n".join(parts)


func _collect_text(node: Node, parts: Array[String]) -> void:
	for child in node.get_children():
		var item := child as Label
		if item != null:
			parts.append(String(item.text))
		_collect_text(child, parts)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
