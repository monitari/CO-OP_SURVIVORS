extends SceneTree
## Shoots every screen in one language, for looking at rather than asserting on.
## `--locale en` (the default is ko) picks the language; the files land in
## .godot_runtime/loc-<locale>-<screen>.png.
const Scene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

var main: Node
var locale := "en"

func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/loc-capture.cfg")
	var args := OS.get_cmdline_user_args()
	var at := args.find("--locale")
	if at >= 0 and at + 1 < args.size():
		locale = args[at + 1]
	OS.set_environment("CHAINBOUND_LOCALE", locale)
	Harness.arm_watchdog(self, "LOC_CAPTURE", 180.0)
	call_deferred("run")


func run() -> void:
	main = Scene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "LOC_CAPTURE"): return

	main.title_active = true
	main._begin_title()
	main._refresh_title_ui()
	await shot("title")
	main.title_mode = "settings"
	main._refresh_title_ui()
	await shot("settings")
	main.title_mode = "menu"

	main._begin_lobby()
	main._refresh_lobby_ui()
	await shot("lobby")

	main.lobby_joined.assign([true, true])
	main.lobby_devices.assign([0, 1])
	main._begin_character_select()
	main._refresh_character_select_ui()
	await shot("character")

	main.ai_companion = true
	main.selected_character_indices[0] = 1
	main.selected_character_indices[1] = 4
	main._start_selected_run()
	main.title_active = false
	main.character_select_active = false
	main.title_overlay.hide()
	main.character_overlay.hide()
	main.combat_hud.show()
	main.set_physics_process(false)
	main.elapsed = 142.0
	main.kills = 213
	main._update_hud()
	await shot("hud")

	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0.0
	main.selected_upgrade_indices.assign([-1, 0])
	main.upgrade_cursors.assign([1, 0])
	main._refresh_level_up_ui()
	await shot("growth")

	main.ReviewUI.toggle_details(main)
	await shot("details")
	main.ReviewUI.toggle_details(main)

	main.resonance_candidates.assign(main.resonance_system.catalog.slice(0, 3))
	main.resonance_votes.assign([-1, 0])
	main.resonance_cursors.assign([1, 0])
	main.resonance_vote_active = true
	main.resonance_overlay.show()
	main._refresh_resonance_vote_ui()
	await shot("resonance")
	main.resonance_vote_active = false
	main.resonance_overlay.hide()

	main._set_pause(true)
	main._update_pause_text()
	await shot("pause")
	main._set_pause(false)

	main._end_run(true)
	main.set_physics_process(true)
	for frame in 6: await physics_frame
	main.set_physics_process(false)
	await shot("result")
	print("LOC_CAPTURE done: %s" % locale)
	quit(0)


func shot(label: String) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://.godot_runtime/loc-%s-%s.png" % [locale, label])
