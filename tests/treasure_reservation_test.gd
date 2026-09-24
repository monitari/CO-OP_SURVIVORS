extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const Reservation := preload("res://scripts/systems/treasure_reservation.gd")
const Treasures := preload("res://scripts/catalogs/treasure_catalog.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "TREASURE_RESERVATION_FAIL", 90.0)
	call_deferred("_run")


func _run() -> void:
	var untyped: Array = [{"weapon_id": "homing"}]
	var three: Array = [{"id": "armor"}, {"id": "recovery"}, {"id": "area"}]
	var full: Array = [{"id": "armor"}, {"id": "recovery"}, {"id": "area"}, {"id": "might"}]
	_check(Reservation.missing_slots(untyped, three) == 1,
		"untyped weapon reserves one route material")
	_check(Reservation.viable(untyped, three, 4, "", -1, "", "might"),
		"one valid route material may take the last slot")
	_check(not Reservation.viable(untyped, three, 4, "", -1, "", "crit"),
		"unrelated treasure cannot take the last slot")
	_check(not Reservation.viable(untyped, full, 4, "", 0, "crit"),
		"route choice is rejected when its material cannot fit")
	_check(Reservation.viable(untyped, full, 4, "", 0, "might"),
		"route choice is accepted when its material can fit")

	var shared: Array = [
		{"weapon_id": "homing", "tech_synergy_treasure_id": "might"},
		{"weapon_id": "lightning", "tech_synergy_treasure_id": "might"},
	]
	_check(Reservation.missing_slots(shared, []) == 1,
		"two weapons can share one material slot")
	_check(not Reservation.viable(shared, three, 4, "orbit"),
		"new weapon is withheld when all remaining route materials are blocked")

	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "TREASURE_RESERVATION_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	var weapon: Dictionary = main.weapon_loadouts[0][0]
	main.WeaponTechs.apply_to_state(weapon, main.WeaponTechs.by_id("homing", "comet"))
	for treasure_id in ["armor", "recovery", "area"]:
		main._apply_upgrade(0, {"id": "unlock_treasure", "treasure": Treasures.by_id(treasure_id)})
	_check(main.treasure_loadouts[0].size() == 3, "three ordinary treasures fit before the reserved slot")
	for draw in 8:
		var choices: Array[Dictionary] = main._get_upgrade_choices(1)
		_check(choices.any(func(option: Dictionary) -> bool:
			return String(option["id"]) == "unlock_treasure" and String((option["treasure"] as Dictionary)["id"]) == "might"),
			"required treasure appears in every last-slot growth hand")
	var chest: Array[Dictionary] = main._chest_unlock_candidates()
	_check(chest.any(func(candidate: Dictionary) -> bool:
		return int(candidate["slot"]) == 0 and String(candidate["option"]["id"]) == "unlock_treasure" and String(candidate["option"]["treasure"]["id"]) == "might"),
		"chest can offer the required material")
	_check(not chest.any(func(candidate: Dictionary) -> bool:
		return int(candidate["slot"]) == 0 and String(candidate["option"]["id"]) == "unlock_treasure" and String(candidate["option"]["treasure"]["id"]) == "crit"),
		"chest excludes a material that would close the only route")
	main._apply_upgrade(0, {"id": "unlock_treasure", "treasure": Treasures.by_id("crit")})
	_check(main.treasure_loadouts[0].size() == 3, "stale unrelated treasure card cannot consume reserved slot")
	main._apply_upgrade(0, {"id": "unlock_treasure", "treasure": Treasures.by_id("might")})
	_check(main.treasure_loadouts[0].size() == 4, "required treasure consumes reserved slot")
	var might_slot := 3
	for tier in 3:
		main._apply_upgrade(0, {"id": "treasure_upgrade", "treasure_slot": might_slot})
	weapon["tier"] = Evolutions.EVOLUTION_TIER
	main._apply_pending_evolutions(0)
	_check(bool(main.weapon_loadouts[0][0].get("evolved", false)), "reachable material completes the real evolution recipe")

	if failures.is_empty():
		print("TREASURE_RESERVATION_PASS: route slots, hand, chest, and stale card stay viable")
		quit(0)
	else:
		for failure in failures:
			push_error("TREASURE_RESERVATION_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)