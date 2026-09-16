extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/ui-review-progress.cfg")
	Harness.arm_watchdog(self, "UI_REDESIGN_CAPTURE_FAIL", 45.0)
	call_deferred("_run")

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://.godot_runtime/ui-" + name + ".png")
	if error != OK:
		push_error("UI_REDESIGN_CAPTURE_FAIL: " + name)
		quit(1)

func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	# After the scene, not before: main._ready() calls randomize() over any
	# seed set earlier, so this is the line that actually makes the run repeat.
	seed(90213)
	await process_frame
	if not Harness.require_loaded(self, main, "UI_REDESIGN_CAPTURE_FAIL"):
		return
	await _shot("title")
	main._begin_lobby()
	await _shot("lobby")
	main._set_lobby_exit_confirm(true)
	await _shot("lobby-exit")
	main._set_lobby_exit_confirm(false)
	main._finish_lobby()
	await _shot("characters")
	main.ReviewUI.toggle_character_details(main)
	await _shot("characters-detail")
	main.ReviewUI.toggle_character_details(main)
	main.character_confirmed.assign([true, true])
	main._start_selected_run()
	main.set_physics_process(false)
	main._physics_process(1.0 / 60.0)
	main._update_hud()
	await _shot("hud")
	main.players[0].health = 10.0
	main._update_hud()
	await _shot("hud-danger")
	main.players[0].health = main.players[0].max_health
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0.0
	main._refresh_level_up_ui()
	for frame in 35:
		main._physics_process(1.0 / 60.0)
		await process_frame
	await _shot("growth-three")
	# A real treasure option alongside the tech choices exercises the fourth
	# slot, the long before/after description and the recommendation badge.
	var treasure: Dictionary = main.Treasures.all_treasures()[0]
	var option := {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure,
		"title": "새 보물: " + String(treasure["name"]), "recommended": true,
		"recommendation_reason": "동료와 함께 강화"}
	option["description"] = main._upgrade_preview(0, option)
	while main.p1_choices.size() < 4:
		main.p1_choices.append(option.duplicate(true))
	main._refresh_level_up_ui()
	await _shot("growth-four")
	root.size = Vector2i(1920, 1080)
	await process_frame
	await _shot("growth-four-1080")
	root.size = Vector2i(1280, 720)
	await process_frame
	main.selected_upgrade_indices.assign([0, -1])
	main._refresh_level_up_ui()
	await _shot("growth-p2")
	main.level_up_active = false
	main.level_overlay.hide()
	paused = false
	main._set_pause(true)
	await _shot("pause")
	main._set_pause(false)
	main._end_run(true)
	await _shot("result")
	paused = false
	main.queue_free()
	await process_frame
	print("UI_REDESIGN_CAPTURE_PASS")
	quit(0)
