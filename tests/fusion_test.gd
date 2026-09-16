extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FUSION_FAIL", 90.0)
	call_deferred("_run")


## The tech tree is base weapon → fused weapon → resonance, and each rung is
## supposed to be a gate rather than a formality. These checks pin the gates:
## a fusion needs both a maxed weapon and the right treasure, it is offered the
## moment both are true and never before, it replaces the weapon in place, and
## the selected route exposes its material and final form before completion.
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
	WeaponTechs.apply_to_state(main.weapon_loadouts[0][0], WeaponTechs.by_id("homing", "constellation"))
	WeaponTechs.apply_to_state(main.weapon_loadouts[1][0], WeaponTechs.by_id("lightning", "conductor"))
	main.set_physics_process(false)
	await process_frame

	_test_catalog_is_complete()
	_test_route_choice_and_material(main)
	_test_both_requirements(main)
	_test_fusion_replaces_in_place(main)
	_test_tier_is_capped(main)
	_test_growth_selection_exposes_route(main)
	_test_completed_build_stops_growth(main)

	if failures.is_empty():
		print("FUSION_PASS: 1-3 routes per weapon, both gates enforced, maxed cards removed, route shown")
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
		var techs := WeaponTechs.for_weapon(weapon_id)
		_check(techs.size() >= 1 and techs.size() <= 3,
			"%s offers between one and three tech routes" % String(character["name"]))
		var tech_ids: Dictionary = {}
		for tech in techs:
			_check(not tech_ids.has(String(tech["id"])), "%s tech ids are unique" % weapon_id)
			tech_ids[String(tech["id"])] = true
			_check(treasure_ids.has(String(tech["treasure_id"])), "%s tech material exists" % String(tech["name"]))
			_check(not (tech["upgrades"] as Array).is_empty(), "%s tech has an upgrade path" % String(tech["name"]))

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


func _test_route_choice_and_material(main: Node) -> void:
	var character: Dictionary = CharacterCatalog.all_characters()[0]
	main.weapon_loadouts[0] = [main._build_weapon_state(character)]
	main.treasure_loadouts[0] = []
	# A new weapon grows untyped first: no route hand before the unlock tier.
	var opening: Array[Dictionary] = main._get_upgrade_choices(1)
	_check(not opening.is_empty() and opening.all(func(option: Dictionary) -> bool: return String(option["id"]) != "choose_tech"),
		"a new weapon is not asked for its tech before tier %d" % Growth.TECH_UNLOCK_TIER)
	while int(main.weapon_loadouts[0][0]["tier"]) < Growth.TECH_UNLOCK_TIER:
		main._apply_upgrade(0, {"id": "weapon_power", "weapon_slot": 0})
	_check(String(main.weapon_loadouts[0][0].get("tech_id", "")).is_empty(), "a three-route weapon is never assigned a route on its own")
	var tier_before := int(main.weapon_loadouts[0][0]["tier"])
	main._apply_upgrade(0, {"id": "weapon_power", "weapon_slot": 0})
	_check(int(main.weapon_loadouts[0][0]["tier"]) == tier_before, "a weapon waiting on its route takes no more tiers")
	var routes: Array[Dictionary] = main._get_upgrade_choices(1)
	_check(routes.size() == 3 and routes.all(func(option: Dictionary) -> bool: return String(option["id"]) == "choose_tech"),
		"a three-route weapon asks for its tech at the unlock tier, before numeric upgrades")
	main._apply_upgrade(0, routes[0])
	var chosen: Dictionary = main.weapon_loadouts[0][0]
	_check(String(chosen.get("tech_id", "")) == String((routes[0]["tech"] as Dictionary)["id"]),
		"the chosen route is stored on the weapon")
	var required_id := String(chosen["tech_treasure_id"])
	var after: Array[Dictionary] = main._get_upgrade_choices(1)
	_check(after.any(func(option: Dictionary) -> bool: return String(option["id"]) == "unlock_treasure" and String((option["treasure"] as Dictionary)["id"]) == required_id),
		"the chosen route's missing treasure is guaranteed in the next hand")
	for option in after:
		if int(option.get("weapon_slot", -1)) == 0 and String(option["id"]) in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
			_check(WeaponTechs.allows(chosen, String(option["id"])), "offered upgrades stay inside the chosen route")
	WeaponTechs.apply_to_state(main.weapon_loadouts[0][0], WeaponTechs.by_id("homing", "constellation"))


func _test_both_requirements(main: Node) -> void:
	var weapon: Dictionary = main.weapon_loadouts[0][0]
	var evolution: Dictionary = main._selected_evolution_for_state(weapon)
	_check(not evolution.is_empty(), "the starting weapon has a fusion to reach")
	var treasure_id := String(evolution["treasure_id"])

	# Neither requirement met.
	_check(_fusion_offers(main, 1).is_empty(), "no fusion is offered at tier 1 with no treasure")

	# Weapon at the enhancement gate, treasure missing.
	weapon["tier"] = EvolutionCatalog.EVOLUTION_TIER
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
	weapon["tier"] = EvolutionCatalog.EVOLUTION_TIER - 1
	_check(_fusion_offers(main, 1).is_empty(), "the weapon requirement is enforced independently")
	weapon["tier"] = EvolutionCatalog.EVOLUTION_TIER


func _test_fusion_replaces_in_place(main: Node) -> void:
	var slots_before: int = main.weapon_loadouts[0].size()
	var base_id := String(main.weapon_loadouts[0][0]["weapon_id"])
	var evolution: Dictionary = main._selected_evolution_for_state(main.weapon_loadouts[0][0])
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
	for option in main._get_upgrade_choices(2):
		_check(not (int(option.get("weapon_slot", -1)) == 0 and String(option["id"]) in ["weapon_power", "weapon_rate", "special_a", "special_b"]),
			"a max-tier weapon never appears as another ordinary upgrade")


## A recipe remains hidden until both ingredients are carried. At that point the
## involved card shows the *other* ingredient in its corner, while the result
## stays unknown until it has actually been discovered.
func _test_growth_selection_exposes_route(main: Node) -> void:
	main.fusion_discovered = false
	main._refresh_level_up_ui()
	# The whole screen rather than the one label the table used to live in: the
	# strip is gone entirely now, and an assertion pointed at an empty label
	# would pass no matter what the rest of the screen said.
	var shown := _growth_screen_text(main)
	for evolution in EvolutionCatalog.all_evolutions():
		_check(not shown.contains(String(evolution["weapon_name"])),
			"the growth screen does not name the fusion %s" % String(evolution["weapon_name"]))
	_check(not shown.contains(" T7 + "), "and does not lay enhancement requirements out as a table")
	_check(not shown.contains("미지의 합성") and not shown.contains("합성 재료"),
		"and does not label an offered card as a hidden fusion material")
	# The run's level, which is what stops the screen being a card rack with no
	# context. It is not inside the growth overlay: the growth screen deliberately
	# leaves the run showing underneath it, so the shared meter along the bottom of
	# the play field is still the thing that carries it, and scoping this to
	# level_overlay was looking at the wrong half of the screen.
	main._update_hud()
	_check(String(main.xp_text_label.text).contains("LV."),
		"the screen still says what level this is (%s)" % main.xp_text_label.text)

	var weapon: Dictionary = main.weapon_loadouts[1][0]
	var evolution: Dictionary = main._selected_evolution_for_state(weapon)
	var treasure := TreasureCatalog.by_id(String(evolution["treasure_id"]))
	# The same card, dealt twice: once while the treasure is not carried and once
	# after it is. Dealt for real both times — the seal is painted as a card is laid
	# out, so asserting over a hand that was never dealt was reading marks left on
	# the pooled Labels by whatever screen used them last.
	var route_choices: Array[Dictionary] = [{
		"id": "weapon_power", "weapon_slot": 0,
		"title": "마력 증폭\n%s" % String(weapon["weapon_name"]),
		"description": main._upgrade_preview(1, {"id": "weapon_power", "weapon_slot": 0}),
	}]
	main.p2_choices = route_choices
	main._refresh_level_up_ui()
	for slot in main.level_card_labels.size():
		for index in main.level_card_labels[slot].size():
			var card: Label = main.level_card_labels[slot][index]
			_check(card.has_node("FusionMark"), "every growth card has a conditional fusion seal")
			if not card.visible:
				continue
			_check(not card.get_node("FusionMark").visible,
				"the fusion seal stays hidden before both ingredients are owned (slot %d card %d)" % [slot, index])

	var visible_line: String = main._fusion_progress_line(1)
	_check(visible_line.contains(String(treasure["name"])) and visible_line.contains(String(evolution["weapon_name"])),
		"full stats names the selected tech's material and final form before pickup")

	main._apply_upgrade(1, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	main.p2_choices = route_choices
	main._refresh_level_up_ui()
	var mark := main.level_card_labels[1][0].get_node("FusionMark") as TextureRect
	_check(mark.visible and mark.texture != null,
		"owning both ingredients reveals the partner icon on its growth card")
	_check(mark.tooltip_text.contains(String(treasure["name"])) and mark.tooltip_text.contains("무기가 강화됩니다"),
		"the seal explains which owned item combines with this card")
	var revealed_line: String = main._fusion_progress_line(1)
	_check(revealed_line.contains(String(treasure["name"])),
		"full stats reveals the relationship once both ingredients are owned")


func _test_completed_build_stops_growth(main: Node) -> void:
	for slot in 2:
		main.weapon_loadouts[slot] = []
		for character in CharacterCatalog.all_characters().slice(0, main.WEAPON_LOADOUT_CAP):
			var state: Dictionary = main._build_weapon_state(character)
			if String(state.get("tech_id", "")).is_empty():
				WeaponTechs.apply_to_state(state, WeaponTechs.for_weapon(String(state["weapon_id"]))[0])
			var evolution: Dictionary = main._selected_evolution_for_state(state)
			var enhanced := EvolutionCatalog.build_state(evolution, state)
			# An enhancement is no longer the end of a weapon's life: it keeps
			# climbing to WEAPON_MAX_TIER, so a *finished* build is one that has
			# bought those rungs too.
			enhanced["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
			main.weapon_loadouts[slot].append(enhanced)
		main.treasure_loadouts[slot] = []
		for treasure in TreasureCatalog.all_treasures().slice(0, main.TREASURE_LOADOUT_CAP):
			var carried: Dictionary = TreasureCatalog.build_state(treasure)
			carried["tier"] = TreasureCatalog.MAX_TIER
			main.treasure_loadouts[slot].append(carried)
	main.level_up_active = false
	main.growth_finished = false
	main.overflow_levels = 0
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	_check(main.growth_finished and not main.level_up_active,
		"a fully maxed pair does not open another growth screen")
	# Experience has no ceiling: the level still lands, it just pays a flat
	# 초월 step to both survivors instead of opening a screen with nothing on it.
	_check(main.overflow_levels >= 1, "the level past a finished build is still taken")
	var might_before: float = float(main.players[0].might)
	var level_before := int(main.progression.level)
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	_check(int(main.progression.level) > level_before, "the shared level keeps climbing")
	_check(main.players[0].might > might_before, "and every level past the build still pays out")
	var banked := int(main.progression.experience)
	main._gain_shared_xp(100, 0)
	_check(int(main.progression.experience) > banked, "XP keeps accruing after the build is complete")


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
