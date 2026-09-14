extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH",
		"res://.godot_runtime/ui-storefront-progress.cfg")
	Harness.arm_watchdog(self, "UI_STOREFRONT_CAPTURE_FAIL", 90.0)
	call_deferred("_run")


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("UI_STOREFRONT_CAPTURE_FAIL: no viewport texture for " + name)
		quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null:
		push_error("UI_STOREFRONT_CAPTURE_FAIL: no viewport image for " + name)
		quit(1)
		return
	var error := image.save_png(
		"res://.godot_runtime/ui-" + name + ".png")
	if error != OK:
		push_error("UI_STOREFRONT_CAPTURE_FAIL: " + name)
		quit(1)


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "UI_STOREFRONT_CAPTURE_FAIL"):
		return
	await _shot("title")
	for mode in ["modes", "settings", "meta", "credits"]:
		main.title_mode = mode
		main.title_cursor = 0
		main._refresh_title_ui()
		await _shot("title-" + mode)
	main._begin_title()
	main._begin_lobby()
	main.lobby_input_cooldown = 0.0
	main._join_lobby_slot(0, -1, "키보드 WASD")
	main._finish_lobby()
	await _shot("characters")
	main._set_character_exit_confirm(true)
	await _shot("characters-exit")
	main._set_character_exit_confirm(false)
	main.ReviewUI.toggle_character_details(main)
	await _shot("characters-detail")
	main.queue_free()
	await process_frame
	print("UI_STOREFRONT_CAPTURE_PASS")
	quit(0)
