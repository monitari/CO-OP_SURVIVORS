extends SceneTree
const MainScene := preload("res://scenes/main.tscn")
func _initialize() -> void:
	preload("res://tests/test_harness.gd").arm_watchdog(self, "COOP_CAPTURE", 20.0)
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/capture_progress.cfg")
	call_deferred("capture")
func capture() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main._begin_lobby()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/coop-lobby.png")
	main.lobby_input_cooldown = 0
	main._join_ai_companion()
	main._start_selected_run()
	main.set_physics_process(false)
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0
	main._handle_level_up_input()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/coop-growth.png")
	main.ai_companion = false
	main.selected_upgrade_indices.assign([0, -1])
	main._refresh_level_up_ui()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/coop-p2-growth.png")
	quit()
