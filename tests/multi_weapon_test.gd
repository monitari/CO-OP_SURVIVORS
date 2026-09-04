extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "MULTI_WEAPON_FAIL", 60.0)
	call_deferred("_run")


## Weapons used to be one-per-character; a player can now carry up to
## WEAPON_LOADOUT_CAP, picked up via level-up choices. Verifies the cap is
## actually enforced, that each owned weapon fires on its own independent
## cooldown instead of sharing the single old attack_timers[i] float, and
## that resonance can be reached through a picked-up weapon even when the
## player's own starting weapon shares no tags with the partner at all.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "MULTI_WEAPON_FAIL"):
		return

	main.selected_character_indices[0] = 4 # moro
	main.selected_character_indices[1] = 0 # lyra
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_weapon_cap(main)
	await _test_independent_cooldowns(main)
	_test_loadout_resonance(main)

	if failures.is_empty():
		print("MULTI_WEAPON_PASS: cap enforced, independent cooldowns, resonance reaches through a picked-up weapon")
		quit(0)
	else:
		for failure in failures:
			push_error("MULTI_WEAPON_FAIL: " + failure)
		quit(1)


func _test_weapon_cap(main: Node) -> void:
	_check(main.weapon_loadouts[0].size() == 1, "a run starts with exactly one weapon")

	for i in 2:
		var candidates: Array = main._pick_unowned_characters(0, 1)
		_check(not candidates.is_empty(), "an unowned character is available to unlock (iteration %d)" % i)
		main._apply_upgrade(0, {"id": "unlock_weapon", "weapon_slot": -1, "character": candidates[0]})

	_check(main.weapon_loadouts[0].size() == main.WEAPON_LOADOUT_CAP, "two unlock picks bring a player to the weapon cap")
	_check(main.attack_timers[0].size() == main.weapon_loadouts[0].size(), "attack_timers stays 1:1 with weapon_loadouts")

	var pool_at_cap: Array[Dictionary] = main._get_upgrade_choices(1)
	var has_unlock_at_cap := false
	for option in pool_at_cap:
		if String(option["id"]) == "unlock_weapon":
			has_unlock_at_cap = true
	_check(not has_unlock_at_cap, "no more unlock candidates are offered once the cap is reached")
	await process_frame


func _test_independent_cooldowns(main: Node) -> void:
	# player 0 now has 3 weapons from the cap test above. Give the first a
	# very short cooldown and the rest very long ones, then step the same
	# decrement-then-fire shape the physics loop uses and confirm only the
	# fast weapon's timer (and the damage it deals) moves.
	for weapon_slot in main.weapon_loadouts[0].size():
		main.weapon_loadouts[0][weapon_slot]["cooldown"] = 0.05 if weapon_slot == 0 else 30.0
	main.attack_timers[0] = [0.0, 30.0, 30.0]

	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.position = main.players[0].position + Vector2(105.0, 0.0)
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)

	var delta := 1.0 / 60.0
	var health_before := enemy.health
	for tick in 10:
		for weapon_slot in main.weapon_loadouts[0].size():
			main.attack_timers[0][weapon_slot] -= delta
			if main.attack_timers[0][weapon_slot] <= 0.0:
				main.weapon_controller.perform_attack(0, weapon_slot, 1.0)
				main.attack_timers[0][weapon_slot] = float(main.weapon_loadouts[0][weapon_slot]["cooldown"])
	await create_timer(0.3).timeout # let any spawned projectiles travel and land

	_check(is_instance_valid(enemy) and enemy.health < health_before, "the fast weapon fired repeatedly on its own short cooldown")
	_check(main.attack_timers[0][1] > 25.0, "a slow weapon's independent timer is untouched by the fast weapon firing")
	_check(main.attack_timers[0][2] > 25.0, "the third weapon's timer is likewise untouched")


func _test_loadout_resonance(main: Node) -> void:
	main.resonance_system.active_resonances = []
	var moro: Dictionary = main.character_catalog[4]
	var lyra: Dictionary = main.character_catalog[0]
	var volta: Dictionary = main.character_catalog[1]

	var moro_weapon: Dictionary = main._build_weapon_state(moro)
	moro_weapon["tier"] = 3
	var lyra_weapon: Dictionary = main._build_weapon_state(lyra)
	lyra_weapon["tier"] = 3
	var volta_weapon: Dictionary = main._build_weapon_state(volta)
	volta_weapon["tier"] = 3

	var solo_check: Array = main.resonance_system.get_candidates_for_loadouts([moro_weapon], [lyra_weapon])
	_check(solo_check.is_empty(), "moro alone and lyra alone do not resonate (sanity check on this test's premise)")

	var loadout_check: Array = main.resonance_system.get_candidates_for_loadouts([moro_weapon, volta_weapon], [lyra_weapon])
	var ids: Array[String] = []
	for candidate in loadout_check:
		ids.append(String(candidate["id"]))
	_check("guided_thunder" in ids, "a second picked-up weapon (volta's lightning) reaches a resonance the player's own weapon alone could not")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
