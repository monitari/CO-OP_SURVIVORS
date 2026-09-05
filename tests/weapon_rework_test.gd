extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const FieldScript := preload("res://scripts/effects/weapon_field.gd")
const MineScript := preload("res://scripts/proximity_mine.gd")
var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "WEAPON_REWORK_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "WEAPON_REWORK_FAIL"): return
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame
	await _test_orbit_is_a_timed_barrage(main)
	await _test_frost_is_a_sustained_aura(main)
	await _test_scythe_sweeps_over_time(main)
	await _test_gravity_moves_smoothly(main)
	await _test_mine_persists(main)
	if failures.is_empty(): print("WEAPON_REWORK_PASS: orbit, aura, sweep, pull and persistent mines")
	else:
		for failure in failures: push_error("WEAPON_REWORK_FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _equip(main: Node, character_index: int) -> void:
	await _clear(main)
	var character: Dictionary = main.character_catalog[character_index]
	main.weapon_loadouts[0] = [main._build_weapon_state(character)]
	main.players[0].apply_character(character)
	main.players[0].position = Vector2.ZERO
	main.players[0].last_input = Vector2.RIGHT


func _spawn(main: Node, at: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	enemy.position = at
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	return enemy


func _test_orbit_is_a_timed_barrage(main: Node) -> void:
	await _equip(main, 6)
	var enemy := _spawn(main, Vector2(96, 0))
	main.weapon_controller.perform_attack(0, 0, 1.0)
	check(_count_script(main.weapon_controller, FieldScript) == 1, "orbit creates a moving field")
	await create_timer(0.28).timeout
	var first: float = enemy.health
	await create_timer(0.55).timeout
	check(enemy.health < first, "orbit keeps striking during its active window")
	check(_count_script(main.weapon_controller, FieldScript) == 1, "orbit remains visible beyond one frame")


func _test_frost_is_a_sustained_aura(main: Node) -> void:
	await _equip(main, 3)
	var enemy := _spawn(main, Vector2(80, 0))
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.4).timeout
	var first: float = enemy.health
	await create_timer(0.45).timeout
	check(enemy.health < first, "frost aura deals recurring damage")
	check(_count_script(main.weapon_controller, FieldScript) == 1, "frost aura stays attached indefinitely")


func _test_scythe_sweeps_over_time(main: Node) -> void:
	await _equip(main, 4)
	var enemy := _spawn(main, Vector2(110, 0))
	main.weapon_controller.perform_attack(0, 0, 1.0)
	check(is_equal_approx(enemy.health, enemy.max_health), "scythe does not teleport damage before its blade arrives")
	await create_timer(0.4).timeout
	check(enemy.health < enemy.max_health, "animated scythe blade lands its hit")


func _test_gravity_moves_smoothly(main: Node) -> void:
	await _equip(main, 9)
	var enemy := _spawn(main, Vector2(330, 0))
	var farthest := _spawn(main, Vector2(430, 0))
	var start: Vector2 = enemy.position
	check(main.weapon_controller._gravity_centre(0, main.weapon_loadouts[0][0]).is_equal_approx(farthest.position), "gravity chooses the farthest enemy in cast range")
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.16).timeout
	check(enemy.position.distance_to(start) > 1.0, "gravity begins pulling before collapse")
	check(enemy.health == enemy.max_health, "gravity damage waits for the visible collapse")
	await create_timer(0.4).timeout
	check(enemy.health < enemy.max_health, "gravity damages at the end of the pull")


func _test_mine_persists(main: Node) -> void:
	await _equip(main, 8)
	main.players[0].last_input = Vector2.RIGHT
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.8).timeout
	check(_count_script(main.weapon_controller, MineScript) == 1, "mine remains armed without a lifetime timeout")
	check(is_inf(ProximityMine.LIFETIME), "mine catalog lifetime is infinite")


func _count_script(parent: Node, script: Script) -> int:
	var count := 0
	for child in parent.get_children():
		if child.get_script() == script: count += 1
	return count


func _clear(main: Node) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy): enemy.queue_free()
	main.enemies.clear()
	main.spatial_grid.rebuild(main.enemies)
	await process_frame


func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
