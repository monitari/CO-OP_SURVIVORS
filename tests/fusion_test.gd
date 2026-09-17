extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FUSION_FAIL", 90.0)
	call_deferred("_run")


## The tech tree is base weapon → enhanced weapon → resonance, and the middle
## rung is now a single visible number: Lv.7, reached, done. These checks pin
## that shape — the route is chosen at Lv.3, the enhancement happens on its own
## at Lv.7 with no card and no treasure, everything the weapon was grown by
## survives it, and the weapon keeps climbing afterwards.
##
## The gate this test used to guard (a maxed weapon *and* a route-specific
## treasure at Lv.4) is deliberately gone, so the checks that it was enforced
## are gone with it. What replaced them is the opposite assertion: a treasure
## must not be able to hold an enhancement back.
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
	WeaponTechs.apply_to_state(main.weapon_loadouts[0][0], WeaponTechs.by_id("homing", "comet"))
	WeaponTechs.apply_to_state(main.weapon_loadouts[1][0], WeaponTechs.by_id("lightning", "conductor"))
	main.set_physics_process(false)
	await process_frame

	_test_catalog_is_complete()
	_test_route_choice(main)
	_test_level_seven_is_the_only_condition(main)
	_test_enhancement_replaces_in_place(main)
	_test_growth_carries_in_full(main)
	_test_tier_is_capped(main)
	_test_growth_selection_exposes_synergy(main)
	_test_completed_build_stops_growth(main)

	if failures.is_empty():
		print("FUSION_PASS: two routes per weapon, Lv.7 auto-enhances with growth intact, no treasure gate, maxed cards removed")
		quit(0)
	else:
		for failure in failures:
			push_error("FUSION_FAIL: " + failure)
		quit(1)


## Every weapon a survivor can carry has to have somewhere to go. A weapon with
## no enhancement is a dead branch: it can be maxed and then never reach
## resonance.
func _test_catalog_is_complete() -> void:
	var treasure_ids: Dictionary = {}
	for treasure in TreasureCatalog.all_treasures():
		treasure_ids[String(treasure["id"])] = true

	for character in CharacterCatalog.all_characters():
		var weapon_id := String(character["weapon_id"])
		_check(not EvolutionCatalog.for_base(weapon_id).is_empty(),
			"%s's weapon has an enhancement" % String(character["name"]))
		var techs := WeaponTechs.for_weapon(weapon_id)
		_check(techs.size() == 2, "%s offers exactly two routes" % String(character["name"]))
		var tech_ids: Dictionary = {}
		for tech in techs:
			_check(not tech_ids.has(String(tech["id"])), "%s tech ids are unique" % weapon_id)
			tech_ids[String(tech["id"])] = true
			_check(treasure_ids.has(String(tech["synergy_treasure_id"])),
				"%s names a synergy treasure that exists" % String(tech["name"]))
			_check((tech["upgrades"] as Array).size() == 2, "%s names two growth axes" % String(tech["name"]))

	var weapon_ids: Dictionary = {}
	for evolution in EvolutionCatalog.all_evolutions():
		var fused_id := String(evolution["weapon_id"])
		_check(not weapon_ids.has(fused_id), "%s is a unique enhanced id" % fused_id)
		weapon_ids[fused_id] = true
		_check(EvolutionCatalog.tags_of(evolution).size() == 2, "%s carries exactly two tags" % fused_id)
		_check(float((evolution["weapon"] as Dictionary)["damage"]) > 0.0, "%s deals damage" % fused_id)
		_check(EvolutionCatalog.is_evolved(fused_id), "%s reports itself as enhanced" % fused_id)
	_check(not EvolutionCatalog.is_evolved("homing"), "a base weapon does not report itself as enhanced")


func _test_route_choice(main: Node) -> void:
	var character: Dictionary = CharacterCatalog.all_characters()[0]
	main.weapon_loadouts[0] = [main._build_weapon_state(character)]
	main.treasure_loadouts[0] = []
	# A new weapon grows untyped first: no route hand before the unlock tier.
	var opening: Array[Dictionary] = main._get_upgrade_choices(1)
	_check(not opening.is_empty() and opening.all(func(option: Dictionary) -> bool: return String(option["id"]) != "choose_tech"),
		"a new weapon is not asked for its route before tier %d" % Growth.TECH_UNLOCK_TIER)
	while int(main.weapon_loadouts[0][0]["tier"]) < Growth.TECH_UNLOCK_TIER:
		main._apply_upgrade(0, {"id": "weapon_power", "weapon_slot": 0})
	_check(String(main.weapon_loadouts[0][0].get("tech_id", "")).is_empty(),
		"a two-route weapon is never assigned a route on its own")
	var tier_before := int(main.weapon_loadouts[0][0]["tier"])
	main._apply_upgrade(0, {"id": "weapon_power", "weapon_slot": 0})
	_check(int(main.weapon_loadouts[0][0]["tier"]) == tier_before, "a weapon waiting on its route takes no more tiers")
	var routes: Array[Dictionary] = main._get_upgrade_choices(1)
	_check(routes.size() == 2 and routes.all(func(option: Dictionary) -> bool: return String(option["id"]) == "choose_tech"),
		"a weapon asks for its route at the unlock tier, before numeric upgrades")
	# Both routes reach the same enhanced weapon, which is what makes the Lv.3
	# card a decision about delivery rather than a commitment to a final form.
	var destinations: Dictionary = {}
	for option in routes:
		var probe: Dictionary = main.weapon_loadouts[0][0].duplicate(true)
		WeaponTechs.apply_to_state(probe, option["tech"] as Dictionary)
		destinations[String(main._selected_evolution_for_state(probe)["weapon_id"])] = true
	_check(destinations.size() == 1, "both routes lead to the same enhanced weapon")
	main._apply_upgrade(0, routes[0])
	var chosen: Dictionary = main.weapon_loadouts[0][0]
	_check(String(chosen.get("tech_id", "")) == String((routes[0]["tech"] as Dictionary)["id"]),
		"the chosen route is stored on the weapon")
	_check(not String(chosen.get("tech_synergy_treasure_id", "")).is_empty(),
		"the chosen route records the treasure it pairs well with")


## The one that matters: Lv.7 and nothing else, and no card in between.
func _test_level_seven_is_the_only_condition(main: Node) -> void:
	var weapon: Dictionary = main.weapon_loadouts[0][0]
	main.treasure_loadouts[0] = []
	weapon["tier"] = EvolutionCatalog.EVOLUTION_TIER - 1
	_check(main._available_evolution(0, 0).is_empty(), "a weapon below Lv.7 is not enhanced")
	_check(main._apply_pending_evolutions(0).is_empty(), "and nothing enhances it early")

	# Carrying no treasures at all must not stand in the way.
	weapon["tier"] = EvolutionCatalog.EVOLUTION_TIER
	_check(not main._available_evolution(0, 0).is_empty(),
		"Lv.7 with an empty treasure loadout is enough to enhance")

	# The enhancement is never a card the pair has to pick.
	for draw in 12:
		for option in main._get_upgrade_choices(1):
			_check(String(option["id"]) != "evolve_weapon", "the enhancement is never offered as a growth card")


func _test_enhancement_replaces_in_place(main: Node) -> void:
	var slots_before: int = main.weapon_loadouts[0].size()
	var base_id := String(main.weapon_loadouts[0][0]["weapon_id"])
	var evolution: Dictionary = main._selected_evolution_for_state(main.weapon_loadouts[0][0])
	var route_before := String(main.weapon_loadouts[0][0].get("tech_id", ""))
	main.fusion_discovered = false

	var enhanced_now: Array = main._apply_pending_evolutions(0)
	_check(enhanced_now.size() == 1, "reaching Lv.7 enhances the weapon on the spot")
	var fused: Dictionary = main.weapon_loadouts[0][0]

	_check(main.weapon_loadouts[0].size() == slots_before, "an enhancement does not consume another weapon slot")
	_check(String(fused["weapon_id"]) == String(evolution["weapon_id"]), "the slot now holds the enhanced weapon")
	_check(bool(fused.get("evolved", false)), "the enhanced weapon is flagged as enhanced")
	_check(String(fused["base_weapon_id"]) == base_id, "the enhanced weapon remembers what it grew from")
	_check(String(fused.get("tech_id", "")) == route_before,
		"the route survives the enhancement, which is what keeps the two routes different afterwards")
	_check(Color(fused["color"]) == Color(main.selected_characters[0]["color"]),
		"the enhanced weapon keeps its owner's colour")
	_check(main.fusion_discovered, "the first enhancement is recorded")
	_check(main._available_evolution(0, 0).is_empty(), "an enhanced slot reports no further enhancement")
	_check(main._apply_pending_evolutions(0).is_empty(), "and does not enhance a second time")


## §8. Everything bought before Lv.7 is still there after it. This used to carry
## at 35%, so two thirds of every 화력 card evaporated at the moment the pair
## reached what they had been playing for.
func _test_growth_carries_in_full(main: Node) -> void:
	var character: Dictionary = CharacterCatalog.all_characters()[0]
	var base: Dictionary = character["weapon"]
	var grown: Dictionary = main._build_weapon_state(character)
	WeaponTechs.apply_to_state(grown, WeaponTechs.for_weapon(String(character["weapon_id"]))[0])
	var opening := float(grown["damage"])
	for step in 5:
		main.apply_special_to_state(grown, "a")
		grown["damage"] = float(grown["damage"]) * Growth.power_step(grown)
	var ratio := float(grown["damage"]) / maxf(0.001, opening)
	_check(ratio > 1.5, "the fixture actually grew the weapon (x%.2f)" % ratio)

	var evolution := EvolutionCatalog.for_base(String(character["weapon_id"]))
	var catalogue_damage := float((evolution["weapon"] as Dictionary)["damage"])
	var enhanced := EvolutionCatalog.build_state(evolution, grown)
	_check(is_equal_approx(float(enhanced["damage"]), catalogue_damage * ratio),
		"the enhanced weapon opens at the same multiple its base weapon had reached (%.1f vs %.1f)" % [
			float(enhanced["damage"]), catalogue_damage * ratio])
	_check(float(base["cooldown"]) > 0.0 and float(enhanced["cooldown"]) > 0.0, "the enhanced weapon has a cooldown")


func _test_tier_is_capped(main: Node) -> void:
	# Player 2 is untouched, so this measures the cap rather than the enhancement.
	var weapon: Dictionary = main.weapon_loadouts[1][0]
	weapon["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
	for step in 4:
		main._apply_upgrade(1, {"id": "weapon_power", "weapon_slot": 0})
	_check(int(weapon["tier"]) == EvolutionCatalog.WEAPON_MAX_TIER,
		"weapon tier stops at the cap (%d)" % int(weapon["tier"]))
	for option in main._get_upgrade_choices(2):
		_check(not (int(option.get("weapon_slot", -1)) == 0 and String(option["id"]) in ["weapon_power", "weapon_rate", "special_a", "special_b"]),
			"a max-tier weapon never appears as another ordinary upgrade")


## The growth screen never names an enhanced weapon the pair has not reached,
## and the corner seal marks a *synergy* rather than a requirement.
func _test_growth_selection_exposes_synergy(main: Node) -> void:
	main.fusion_discovered = false
	main._refresh_level_up_ui()
	var shown := _growth_screen_text(main)
	for evolution in EvolutionCatalog.all_evolutions():
		_check(not shown.contains(String(evolution["weapon_name"])),
			"the growth screen does not name the enhancement %s" % String(evolution["weapon_name"]))
	_check(not shown.contains(" T7 + "), "and does not lay enhancement requirements out as a table")
	main._update_hud()
	_check(String(main.xp_text_label.text).contains("LV."),
		"the screen still says what level this is (%s)" % main.xp_text_label.text)

	var weapon: Dictionary = main.weapon_loadouts[1][0]
	var synergy_id := String(weapon.get("tech_synergy_treasure_id", ""))
	_check(not synergy_id.is_empty(), "the routed weapon names a synergy treasure")
	var treasure := TreasureCatalog.by_id(synergy_id)
	main.treasure_loadouts[1] = []
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
			_check(card.has_node("FusionMark"), "every growth card has a conditional synergy seal")
			if not card.visible:
				continue
			_check(not card.get_node("FusionMark").visible,
				"the synergy seal stays hidden before the treasure is owned (slot %d card %d)" % [slot, index])

	# The progress line is one clock now, not two: no treasure appears in it.
	var progress_line: String = main._fusion_progress_line(1)
	_check(progress_line.contains("/%d" % EvolutionCatalog.EVOLUTION_TIER),
		"full stats counts the weapon toward Lv.%d (%s)" % [EvolutionCatalog.EVOLUTION_TIER, progress_line])
	_check(not progress_line.contains(String(treasure["name"])),
		"and no longer presents a treasure as part of the requirement")

	main._apply_upgrade(1, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	main.p2_choices = route_choices
	main._refresh_level_up_ui()
	var mark := main.level_card_labels[1][0].get_node("FusionMark") as TextureRect
	_check(mark.visible and mark.texture != null,
		"owning the route's synergy treasure reveals the seal on its growth card")
	_check(mark.tooltip_text.contains(String(treasure["name"])) and mark.tooltip_text.contains("시너지"),
		"the seal explains the synergy rather than demanding a combination")


func _test_completed_build_stops_growth(main: Node) -> void:
	for slot in 2:
		main.weapon_loadouts[slot] = []
		for character in CharacterCatalog.all_characters().slice(0, main.WEAPON_LOADOUT_CAP):
			var state: Dictionary = main._build_weapon_state(character)
			if String(state.get("tech_id", "")).is_empty():
				WeaponTechs.apply_to_state(state, WeaponTechs.for_weapon(String(state["weapon_id"]))[0])
			var evolution: Dictionary = main._selected_evolution_for_state(state)
			var enhanced := EvolutionCatalog.build_state(evolution, state)
			# An enhancement is not the end of a weapon's life: it keeps climbing
			# to WEAPON_MAX_TIER, so a *finished* build has bought those rungs too.
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


func _growth_screen_text(main: Node) -> String:
	var parts: Array[String] = []
	for node in _walk(main.level_overlay):
		if node is Label:
			parts.append(String((node as Label).text))
		elif node is RichTextLabel:
			parts.append(String((node as RichTextLabel).text))
	return "\n".join(parts)


func _walk(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_walk(child))
	return found


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
