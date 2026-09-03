extends SceneTree

const MainScene := preload("res://scenes/main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	var wall_start := Time.get_ticks_msec()
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.players[0].max_health = 100000.0
	main.players[0].health = 100000.0
	main.players[1].max_health = 100000.0
	main.players[1].health = 100000.0
	main.experience_system.magnet_radius = 3000.0

	for frame in 720:
		var angle := float(frame) * 0.025
		var center := Vector2(cos(angle * 0.22), sin(angle * 0.22)) * 220.0
		main.players[0].position = center + Vector2.from_angle(angle) * 145.0
		main.players[1].position = center - Vector2.from_angle(angle) * 145.0
		if main.resonance_vote_active:
			main.resonance_votes[0] = 0
			main.resonance_votes[1] = 0
			main._handle_resonance_vote_input()
		elif main.level_up_active:
			if not main.p1_has_chosen:
				main._select_upgrade(1, 0)
			if main.level_up_active and not main.p2_has_chosen:
				main._select_upgrade(2, 0)
		await physics_frame

	Engine.time_scale = 1.0
	var wall_elapsed := Time.get_ticks_msec() - wall_start
	_check(main.elapsed >= 180.0 or main.run_won, "accelerated run reaches three minutes or completes with boss victory")
	_check(main.wave_director.boss_spawned, "120-second boss spawns")
	_check(main.enemies.size() <= main.wave_director.enemy_cap, "active enemy count respects cap")
	_check(main.kills > 0, "automated pair kills enemies")
	_check(main.progression.level > 1, "automated pair collects shared XP and levels")

	var archetypes: Dictionary = {}
	for enemy in main.enemies:
		if is_instance_valid(enemy) and enemy.active:
			archetypes[enemy.archetype] = true
	_check(archetypes.size() >= 3, "long run contains multiple enemy archetypes")

	print("SOAK_METRICS: simulated=%.1fs wall=%dms kills=%d level=%d active=%d pooled_enemies=%d pooled_gems=%d archetypes=%d" % [
		main.elapsed, wall_elapsed, main.kills, main.progression.level, main.enemies.size(),
		main.wave_director.enemy_pool.size(), main.experience_system.gem_pool.size(), archetypes.size()
	])
	if failures.is_empty():
		print("COOP_SOAK_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("COOP_SOAK_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
