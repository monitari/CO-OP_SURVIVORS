extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "HUD_REGRESSION_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	TranslationServer.set_locale("en")
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "HUD_REGRESSION_FAIL"):
		return
	main.settings.language = "en"
	main.settings.large_text_enabled = true
	main.wave_director.in_calm = false
	main.wave_director.wave_index = 24
	main.kills = 999
	main._apply_text_scale_to(main.combat_hud, 1.14)
	main._update_hud()
	await process_frame

	var failures: Array[String] = []
	var wave: Label = main.combat_hud.get_node("WaveReadout")
	var font := wave.get_theme_font("font")
	var font_size := wave.get_theme_font_size("font_size")
	var shown := wave.atr(wave.text)
	var text_width := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if text_width > wave.size.x + 1.0:
		failures.append("large English wave readout is clipped: %.0fpx in %.0fpx" % [text_width, wave.size.x])

	for slot in 2:
		var level: Label = main.combat_hud.get_node("PlayerLevel%d" % slot)
		if level.text != "Lv.%d" % int(main.run_stats["personal_levels"][slot]):
			failures.append("P%d does not use the compact Lv. badge" % (slot + 1))
	var left: ProgressBar = main.p1_health_bar
	var right: ProgressBar = main.p2_health_bar
	if left.size.x < 168.0 or right.size.x < 168.0:
		failures.append("health bars were not lengthened")
	if not is_equal_approx(left.position.x, 1280.0 - right.position.x - right.size.x):
		failures.append("lengthened health bars are not mirrored")

	main.queue_free()
	for failure in failures:
		push_error("HUD_REGRESSION_FAIL: " + failure)
	print("HUD_REGRESSION_PASS: English large text fits, Lv. badges fit, health bars mirror" if failures.is_empty() else "HUD_REGRESSION_FAIL")
	quit(0 if failures.is_empty() else 1)
