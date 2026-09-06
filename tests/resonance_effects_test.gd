extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const CombatFlareScript := preload("res://scripts/effects/combat_flare.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_EFFECTS_FAIL", 90.0)
	call_deferred("_run")


## Fires every catalog resonance once and confirms it actually damages something —
## a dispatch branch existing in weapon_controller.gd is not proof it works. A typo
## in a state dict key (e.g. "count" vs "counts") would compile fine and no-op
## silently at runtime, which get_candidates() coverage alone cannot catch.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "RESONANCE_EFFECTS_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	main.players[0].position = Vector2(-60.0, 0.0)
	main.players[1].position = Vector2(60.0, 0.0)
	main.players[0].last_input = Vector2.RIGHT
	main.players[1].last_input = Vector2.LEFT

	for resonance in main.resonance_system.catalog:
		await _test_resonance(main, resonance)

	if failures.is_empty():
		print("RESONANCE_EFFECTS_PASS: all %d resonances deal damage when triggered" % main.resonance_system.catalog.size())
		quit(0)
	else:
		for failure in failures:
			push_error("RESONANCE_EFFECTS_FAIL: " + failure)
		quit(1)


func _test_resonance(main: Node, resonance: Dictionary) -> void:
	await _clear_enemies(main)
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "brute")
	enemy.radius = 80.0
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.position = Vector2.ZERO
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)

	var health_before := enemy.health
	var child_count_before: int = main.weapon_controller.get_child_count()
	main.weapon_controller.perform_resonance(resonance, 1.0)
	var flare_created := false
	for child_index in range(child_count_before, main.weapon_controller.get_child_count()):
		if main.weapon_controller.get_child(child_index).get_script() == CombatFlareScript:
			flare_created = true
			break
	_check(flare_created, "%s creates a shared resonance flare" % String(resonance["id"]))
	await create_timer(0.75).timeout
	var dealt_damage := is_instance_valid(enemy) and enemy.health < health_before
	var resonance_id := String(resonance["id"])
	_check(dealt_damage, "%s (%s) deals damage when triggered" % [resonance_id, String(resonance["name"])])
	print("RESONANCE_EFFECT: %s damage=%s" % [resonance_id, str(health_before - (enemy.health if is_instance_valid(enemy) else health_before))])


func _clear_enemies(main: Node) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
