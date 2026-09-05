extends SceneTree
const MainScene := preload("res://scenes/main.tscn")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, reason: String) -> void:
	if not ok: failures.append(reason)
func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main._start_selected_run()
	main.set_physics_process(false)
	for index in [10, 11]:
		main.weapon_controller.clear_transients()
		main.weapon_loadouts[0] = [main._build_weapon_state(main.character_catalog[index])]
		main.players[0].position = Vector2.ZERO
		var enemy := ChaserEnemy.new()
		enemy.setup(0)
		enemy.health = 10000
		enemy.position = Vector2(120, 0)
		main.add_child(enemy)
		var targets: Array[ChaserEnemy] = [enemy]
		main.spatial_grid.rebuild(targets)
		main.weapon_controller.perform_attack(0, 0, 1.0)
		await create_timer(1.4).timeout
		check(enemy.health < 10000, "new weapon hits along its animated path")
		enemy.queue_free()
	for id in ["rat_runner", "wasp", "hedgehog", "mole", "owl"]:
		var enemy := ChaserEnemy.new()
		enemy.setup(3.0, id)
		main.add_child(enemy)
		enemy.position = Vector2(300, 0)
		for frame in 120: enemy.step(main.players, 1.0 / 60.0)
		check(enemy.position.distance_to(Vector2(300, 0)) > 1.0, id + " moves")
		check(enemy.body_sprite.texture != null, id + " has unique art")
		enemy.queue_free()
	var boss := ChaserEnemy.new()
	boss.setup(5.0, "owl", false, true, 2)
	main.add_child(boss)
	check(boss.max_health > 1000.0, "owl boss uses boss-scaled health")
	boss.set_meta("shots", 0)
	boss.ranged_attack.connect(func(_origin: Vector2, _direction: Vector2, _damage: float) -> void: boss.set_meta("shots", int(boss.get_meta("shots")) + 1))
	boss.shooter_windup = 0.01
	boss.step(main.players, 0.02)
	check(int(boss.get_meta("shots")) == 11, "owl boss releases a fan plus radial volley after warning")
	for index in 7: main._show_message("알림 %d" % index, Color.WHITE)
	check(main.notice_stack.size() == 4, "notifications are capped")
	check(main.notice_stack.back().position.y > main.notice_stack.front().position.y, "latest event is lowest")
	await create_timer(4.0).timeout
	main._show_message("마지막", Color.WHITE)
	check(main.notice_stack.size() == 1, "expired notices are removed safely")
	main._set_pause(true)
	check(main.pause_overlay.has_node("RunSnapshot/Metric3"), "snapshot uses four readable metrics")
	check(main.hud_label.position.x + main.hud_label.size.x / 2.0 == 640.0, "stopwatch is exactly centered")
	if failures.is_empty(): print("EXPANSION_PASS: new weapons, enemies, boss, notices, snapshot, centered HUD")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
