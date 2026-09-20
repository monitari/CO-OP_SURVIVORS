extends SceneTree

const MetaScript := preload("res://scripts/systems/meta_progression.gd")
const SettingsScript := preload("res://scripts/systems/settings_system.gd")
const PlayerScript := preload("res://scripts/entities/player.gd")
const MainScene := preload("res://scenes/main.tscn")
const SAVE := "res://tests/tmp/meta_progression_test.cfg"
const SETTINGS_SAVE := "res://tests/tmp/settings_system_test.cfg"
const RECOVERY_SAVE := "res://tests/tmp/meta_recovery_test.cfg"
const SETTINGS_RECOVERY_SAVE := "res://tests/tmp/settings_recovery_test.cfg"
const SETTINGS_MIGRATION_SAVE := "res://tests/tmp/settings_migration_test.cfg"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in [SAVE, SETTINGS_SAVE, RECOVERY_SAVE, SETTINGS_RECOVERY_SAVE, SETTINGS_MIGRATION_SAVE]:
		for suffix in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_check(int(ProjectSettings.get_setting("display/window/size/window_width_override")) == 1280
		and int(ProjectSettings.get_setting("display/window/size/window_height_override")) == 720
		and int(ProjectSettings.get_setting("display/window/size/mode")) == DisplayServer.WINDOW_MODE_WINDOWED,
		"the project opens in a 1280x720 window by default")
	var meta := MetaScript.new() as MetaProgression
	meta.save_path = SAVE
	_check(meta.points == 0, "a fresh profile starts empty")
	_check(meta.award_clear() == MetaProgression.CLEAR_REWARD, "a clear grants the advertised reward")
	var first_cost := meta.cost("might")
	_check(meta.purchase("might"), "an affordable permanent upgrade can be bought")
	_check(meta.rank("might") == 1 and meta.points == MetaProgression.CLEAR_REWARD - first_cost, "purchase spends points and raises one rank")
	meta.mark_discovered("starpiercer")

	var loaded := MetaScript.new() as MetaProgression
	loaded.save_path = SAVE
	loaded.load_progress()
	_check(loaded.rank("might") == 1, "ranks persist")
	_check(loaded.is_discovered("starpiercer"), "enhancement discoveries persist")
	loaded.points = 10000
	var cap := int(MetaProgression.by_id("luck")["max_rank"])
	while loaded.purchase("luck"):
		pass
	_check(loaded.rank("luck") == cap and loaded.cost("luck") == 0, "every permanent upgrade has a hard cap")

	var player := PlayerScript.new() as ChainPlayer
	player.max_health = 100.0
	player.health = 100.0
	var might_before := player.might
	loaded.apply_to_player(player)
	_check(player.might > might_before, "bought power is applied to the next run")
	_check(loaded.team_luck_bonus() == cap, "team utility bonuses are exposed to the run")

	var settings := SettingsScript.new() as GameSettings
	settings.settings_path = SETTINGS_SAVE
	_check(not settings.fullscreen_enabled and settings.window_size_index == 0,
		"fresh settings prefer a practical window instead of a screen-sized window")
	settings.sound_enabled = false
	settings.sound_volume = 0.25
	settings.music_volume = 0.50
	settings.large_text_enabled = true
	settings.fullscreen_enabled = true
	settings.window_size_index = 2
	settings.frame_rate_limit = 144
	settings.vsync_enabled = false
	_check(settings.save_settings() == OK, "settings report a successful save")
	var loaded_settings := SettingsScript.new() as GameSettings
	loaded_settings.settings_path = SETTINGS_SAVE
	loaded_settings.load_settings()
	_check(not loaded_settings.sound_enabled and loaded_settings.fullscreen_enabled,
		"audio and fullscreen settings persist together")
	_check(is_equal_approx(loaded_settings.sound_volume, 0.25)
		and is_equal_approx(loaded_settings.music_volume, 0.50)
		and loaded_settings.large_text_enabled,
		"volume levels and the large-text preference persist")
	_check(loaded_settings.window_size_index == 2,
		"1920x1080 window preference persists with display settings")
	_check(loaded_settings.frame_rate_limit == 144 and not loaded_settings.vsync_enabled,
		"frame-rate limit and V-Sync preference persist")

	var old_config := ConfigFile.new()
	old_config.set_value("format", "version", 1)
	old_config.set_value("accessibility", "sound_volume", 0.25)
	old_config.set_value("accessibility", "fullscreen_enabled", true)
	old_config.set_value("accessibility", "window_size_index", 2)
	_check(old_config.save(SETTINGS_MIGRATION_SAVE) == OK,
		"the display migration fixture saves")
	var migrated_settings := SettingsScript.new() as GameSettings
	migrated_settings.settings_path = SETTINGS_MIGRATION_SAVE
	migrated_settings.load_settings()
	_check(not migrated_settings.fullscreen_enabled and migrated_settings.window_size_index == 0,
		"version 1 display settings migrate once to the new windowed default")
	_check(is_equal_approx(migrated_settings.sound_volume, 0.25),
		"display migration preserves unrelated preferences")

	var recovery := MetaScript.new() as MetaProgression
	recovery.save_path = RECOVERY_SAVE
	recovery.points = 5
	_check(recovery.save_progress() == OK, "the recovery fixture writes its first profile")
	recovery.points = 9
	_check(recovery.save_progress() == OK, "a later profile save rotates the previous backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECOVERY_SAVE))
	var recovered := MetaScript.new() as MetaProgression
	recovered.save_path = RECOVERY_SAVE
	recovered.load_progress()
	_check(recovered.recovered_from_backup and recovered.points == 5,
		"a missing or corrupt progression file loads the previous complete backup")

	var settings_recovery := SettingsScript.new() as GameSettings
	settings_recovery.settings_path = SETTINGS_RECOVERY_SAVE
	settings_recovery.sound_volume = 0.25
	_check(settings_recovery.save_settings() == OK, "the recovery fixture writes settings")
	settings_recovery.sound_volume = 0.75
	_check(settings_recovery.save_settings() == OK, "a later settings save rotates its backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_RECOVERY_SAVE))
	var recovered_settings := SettingsScript.new() as GameSettings
	recovered_settings.settings_path = SETTINGS_RECOVERY_SAVE
	recovered_settings.load_settings()
	_check(recovered_settings.recovered_from_backup
		and is_equal_approx(recovered_settings.sound_volume, 0.25),
		"missing or corrupt settings load the previous complete backup")

	var failing := MetaScript.new() as MetaProgression
	failing.save_path = SAVE + "/cannot_write.cfg"
	failing.points = 8
	_check(not failing.purchase("might"), "a purchase fails when its save cannot be written")
	_check(failing.points == 8 and failing.rank("might") == 0,
		"a failed purchase rolls currency and rank back")
	_check(failing.award(3) == 0 and failing.points == 8,
		"a failed reward save does not pretend currency was granted")
	failing.mark_discovered("starpiercer")
	_check(not failing.is_discovered("starpiercer"),
		"a failed discovery save does not leave an in-memory unlock")

	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.settings.settings_path = SETTINGS_SAVE
	main.title_mode = "settings"
	main.title_cursor = 0
	main.settings.fullscreen_enabled = false
	main.settings.window_size_index = 0
	main.settings.frame_rate_limit = 0
	main.settings.vsync_enabled = true
	main._refresh_title_ui()
	_check(main._title_rows().size() == 10,
		"the settings page exposes display, accessibility and audio controls")
	main._activate_title_item(0)
	_check(main.settings.fullscreen_enabled,
		"the settings page turns full screen on without rereading a stale OS mode")
	main._activate_title_item(0)
	_check(not main.settings.fullscreen_enabled,
		"the settings page returns to windowed mode")
	main._activate_title_item(1)
	_check(main.settings.window_size_index == 1,
		"the settings page changes the window resolution")
	main._activate_title_item(2)
	_check(main.settings.frame_rate_limit == 60,
		"the settings page advances the frame-rate limit")
	main._activate_title_item(3)
	_check(not main.settings.vsync_enabled,
		"the settings page changes V-Sync")
	main._change_setting(1, -1, false)
	_check(main.settings.window_size_index == 0,
		"left/right display adjustments apply immediately without wrapping")
	main.feedback.sound_volume = 0.50
	main._change_setting(7, -1, false)
	_check(is_equal_approx(main.feedback.sound_volume, 0.25),
		"left/right volume adjustments apply and preview the new level")
	main.pause_active = true
	main.pause_settings = true
	main.pause_cursor = 9
	main._update_pause_text()
	_check(main.pause_overlay.get_node("PauseAction9").visible
		and main.pause_overlay.get_node("PauseAction12").visible,
		"the pause settings page also exposes display mode and V-Sync")
	main.pause_active = false
	main.pause_settings = false
	var pause_action := main.pause_overlay.get_node("PauseAction1") as Button
	main.settings.large_text_enabled = false
	main._apply_accessibility_text_scale()
	var normal_text_size := pause_action.get_theme_font_size("font_size")
	main.settings.large_text_enabled = true
	main._apply_accessibility_text_scale()
	_check(pause_action.get_theme_font_size("font_size") > normal_text_size,
		"large-text mode increases menu text without compounding")
	main._apply_accessibility_text_scale()
	_check(pause_action.get_theme_font_size("font_size") > normal_text_size,
		"reapplying large-text mode keeps one stable scale")
	main.settings.large_text_enabled = false
	main._apply_accessibility_text_scale()
	main.meta_progression.save_path = SAVE
	main.meta_progression.ranks.clear()
	main.meta_progression.points = 8
	main.title_mode = "meta"
	main.title_cursor = 0
	main._refresh_title_ui()
	_check(main._title_rows().size() == 8 and MetaProgression.UPGRADES.size() == 12,
		"the title pages twelve upgrades with navigation and reset")
	var title_rank_before: int = main.meta_progression.rank("vitality")
	main._activate_title_item(0)
	_check(main.meta_progression.rank("vitality") == title_rank_before + 1,
		"the permanent-growth title page buys the selected upgrade")
	main._leave_title_subpage()
	_check(main.title_mode == "menu" and main.title_cursor == 1,
		"leaving permanent growth returns focus to its menu entry")
	main.meta_progression.points = 0
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	main.run_stats["bosses"] = WaveDirector.BOSS_COUNT - 1
	main._end_run(true)
	_check(main.run_reward == 0, "a synthetic or incomplete victory grants no clear currency")
	main.game_over = false
	main.run_stats["bosses"] = WaveDirector.BOSS_COUNT
	main._end_run(true)
	_check(main.run_reward == MetaProgression.CLEAR_REWARD, "the real five-boss clear pays the result-screen reward")
	paused = false
	main.free()
	player.free()
	for path in [SAVE, SETTINGS_SAVE, RECOVERY_SAVE, SETTINGS_RECOVERY_SAVE, SETTINGS_MIGRATION_SAVE]:
		for suffix in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

	if failures.is_empty():
		print("META_PROGRESSION_PASS: clear reward, capped purchases, atomic saves, backup recovery and next-run bonuses")
		quit(0)
	else:
		for failure in failures:
			push_error("META_PROGRESSION_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
