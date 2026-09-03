extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "VISUAL_CAPTURE_FAIL", 120.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "VISUAL_CAPTURE_FAIL"):
		return
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/character-select.png")

	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.players[0].position = Vector2(-120.0, 0.0)
	main.players[1].position = Vector2(120.0, 0.0)
	var archetypes := ["chaser", "charger", "shooter", "chain_hunter", "brute"]
	for index in archetypes.size():
		var enemy := main.wave_director._acquire_enemy(archetypes[index], 1.0, Vector2.ZERO, index == 4, false) as ChaserEnemy
		enemy.position = Vector2.from_angle(TAU * float(index) / float(archetypes.size())) * 265.0
		main._register_enemy(enemy)
	main.experience_system.spawn_gem(Vector2(0.0, 115.0), 5)
	main.spatial_grid.rebuild(main.enemies)
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/gameplay.png")

	main.players[0].health = 1.0
	main.players[0].invulnerability = 0.0
	main.players[0].hurt(999.0)
	main.players[1].position = main.players[0].position + Vector2(75.0, 0.0)
	main._update_revives(1.0)
	main._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/downed-revive.png")
	main.players[0].revive()

	main.progression.add_experience(main.progression.required_experience)
	main._begin_level_up()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/level-up.png")
	main.level_up_active = false
	main.level_overlay.visible = false
	paused = false

	main.selected_characters[0] = main.character_catalog[0].duplicate(true)
	main.selected_characters[1] = main.character_catalog[1].duplicate(true)
	main.weapon_states[0] = (main.selected_characters[0]["weapon"] as Dictionary).duplicate(true)
	main.weapon_states[1] = (main.selected_characters[1]["weapon"] as Dictionary).duplicate(true)
	main.weapon_states[0]["tier"] = 3
	main.weapon_states[1]["tier"] = 3
	main.resonance_system.active_resonance = {}
	main.p1_has_chosen = true
	main.p2_has_chosen = true
	main.level_up_active = true
	paused = true
	main._after_personal_upgrade_choices()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/resonance-vote.png")

	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	main.level_up_active = false
	paused = false
	var boss := main.wave_director._acquire_enemy("brute", 3.0, Vector2.ZERO, true, true) as ChaserEnemy
	boss.position = Vector2(0.0, -170.0)
	main._register_enemy(boss)
	main._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/boss-arrival.png")
	boss.take_damage(999999.0)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/victory-result.png")
	print("VISUAL_CAPTURE_PASS")
	quit(0)


func _save_viewport(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Failed to save visual capture: " + path)
