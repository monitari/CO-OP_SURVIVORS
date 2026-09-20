extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const ProjectileScript := preload("res://scripts/entities/projectile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "SMOKE_TEST_FAIL", 90.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "SMOKE_TEST_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame
	_check(not main.character_select_active, "character selection completes")
	_check(main.selected_characters.size() == 2, "two characters are assigned")

	for character_index in main.character_catalog.size():
		await _test_weapon(main, character_index)
	_check(main.weapon_controller.projectile_pool.size() > 0, "friendly projectiles return to reuse pool")

	var level_before: int = main.progression.level
	main._gain_shared_xp(main.progression.required_experience)
	_check(main.level_up_active, "shared XP opens level-up")
	_check(main.progression.level == level_before + 1, "shared level increments once")
	main._select_upgrade(1, 0)
	main._select_upgrade(2, 0)
	_check(not main.level_up_active, "both choices close level-up")
	_check(not paused, "combat resumes after both choices")

	if failures.is_empty():
		print("SMOKE_TEST_PASS: selection, every roster weapon deals damage, shared level-up")
		quit(0)
	else:
		for failure in failures:
			push_error("SMOKE_TEST_FAIL: " + failure)
		quit(1)


func _test_weapon(main: Node, character_index: int) -> void:
	await _clear_combat_nodes(main)
	var character: Dictionary = main.character_catalog[character_index].duplicate(true)
	main.selected_characters[0] = character
	main.weapon_loadouts[0] = [main._build_weapon_state(character)]
	main.attack_timers[0] = [0.0]
	main.players[0].apply_character(character)
	main.players[0].last_input = Vector2.RIGHT

	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 1000.0
	enemy.max_health = 1000.0
	var weapon_id := String(character["weapon_id"])
	if weapon_id == "chain":
		enemy.position = (main.players[0].position + main.players[1].position) * 0.5
	elif weapon_id in ["mine", "milk"]:
		# Mines are planted underfoot and wait to be walked into, and milk is
		# scattered rather than aimed, so the standard "enemy standing 105px
		# away" fixture would never set one off or land a pool on it.
		enemy.position = main.players[0].position + Vector2(24.0, 0.0)
	else:
		enemy.position = main.players[0].position + Vector2(105.0, 0.0)
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)

	var health_before := enemy.health
	main._perform_character_attack(0)
	if weapon_id == "milk":
		# Milk intentionally lands at a random visible point. Move the fixture onto
		# the real spawned puddle so this remains a damage smoke test instead of a
		# probability test whose result depends on the random landing coordinate.
		await process_frame
		var puddle: MilkPool
		for child in main.weapon_controller.get_children():
			if child is MilkPool:
				puddle = child
				break
		_check(puddle != null, "milk weapon creates a visible puddle")
		if puddle != null:
			enemy.position = puddle.global_position
			main.spatial_grid.rebuild(main.enemies)
	await create_timer(0.75).timeout
	var dealt_damage := is_instance_valid(enemy) and enemy.health < health_before
	_check(dealt_damage, "%s weapon deals damage" % weapon_id)
	print("SMOKE_WEAPON: %s damage=%s" % [weapon_id, str(health_before - enemy.health)])


func _clear_combat_nodes(main: Node) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	for child in main.get_children():
		if child.get_script() == ProjectileScript:
			child.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
