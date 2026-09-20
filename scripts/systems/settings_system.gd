class_name GameSettings
extends RefCounted

const SETTINGS_PATH := "user://chainbound_settings.cfg"
const SECTION := "accessibility"
const FORMAT_SECTION := "format"
const SAVE_VERSION := 2
const FRAME_RATE_LIMITS := [0, 60, 90, 120, 144, 165, 240, -1]
var settings_path := SETTINGS_PATH # Tests isolate saves from user preferences.

var sound_enabled := true
var music_enabled := true
var sound_volume := 0.75
var music_volume := 0.70
var damage_numbers_enabled := true
var screen_shake_enabled := true
var large_text_enabled := false
var fullscreen_enabled := false
var window_size_index := 0
## 0 follows the monitor, -1 is uncapped, and positive values cap rendered FPS.
var frame_rate_limit := 0
var vsync_enabled := true
var last_save_error: Error = OK
var last_load_error: Error = OK
var recovered_from_backup := false


func load_settings() -> void:
	var config := ConfigFile.new()
	recovered_from_backup = false
	last_load_error = config.load(settings_path)
	if last_load_error != OK:
		last_load_error = config.load(settings_path + ".bak")
		if last_load_error != OK:
			return
		recovered_from_backup = true
	var version := maxi(0, int(config.get_value(FORMAT_SECTION, "version", 0)))
	if version > SAVE_VERSION:
		last_load_error = ERR_FILE_UNRECOGNIZED
		return
	sound_enabled = bool(config.get_value(SECTION, "sound_enabled", sound_enabled))
	music_enabled = bool(config.get_value(SECTION, "music_enabled", music_enabled))
	sound_volume = clampf(float(config.get_value(SECTION, "sound_volume", sound_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value(SECTION, "music_volume", music_volume)), 0.0, 1.0)
	# Old saves only had on/off switches. Preserve an off choice as 0% when
	# migrating them to the new volume steps.
	if not config.has_section_key(SECTION, "sound_volume") and not sound_enabled:
		sound_volume = 0.0
	if not config.has_section_key(SECTION, "music_volume") and not music_enabled:
		music_volume = 0.0
	if sound_volume <= 0.0:
		sound_enabled = false
	if music_volume <= 0.0:
		music_enabled = false
	damage_numbers_enabled = bool(config.get_value(SECTION, "damage_numbers_enabled", damage_numbers_enabled))
	screen_shake_enabled = bool(config.get_value(SECTION, "screen_shake_enabled", screen_shake_enabled))
	large_text_enabled = bool(config.get_value(SECTION, "large_text_enabled", large_text_enabled))
	fullscreen_enabled = bool(config.get_value(SECTION, "fullscreen_enabled", fullscreen_enabled))
	window_size_index = clampi(int(config.get_value(SECTION, "window_size_index", window_size_index)), 0, 2)
	# Version 2 makes a practical window the default. Reset the old display
	# choice once because version 1 could save a stale full-screen state while
	# Windows was still processing the mode switch.
	if version < 2:
		fullscreen_enabled = false
		window_size_index = 0
	frame_rate_limit = int(config.get_value(SECTION, "frame_rate_limit", frame_rate_limit))
	if frame_rate_limit not in FRAME_RATE_LIMITS:
		frame_rate_limit = 0
	vsync_enabled = bool(config.get_value(SECTION, "vsync_enabled", vsync_enabled))


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value(FORMAT_SECTION, "version", SAVE_VERSION)
	config.set_value(SECTION, "sound_enabled", sound_enabled)
	config.set_value(SECTION, "music_enabled", music_enabled)
	config.set_value(SECTION, "sound_volume", sound_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "damage_numbers_enabled", damage_numbers_enabled)
	config.set_value(SECTION, "screen_shake_enabled", screen_shake_enabled)
	config.set_value(SECTION, "large_text_enabled", large_text_enabled)
	config.set_value(SECTION, "fullscreen_enabled", fullscreen_enabled)
	config.set_value(SECTION, "window_size_index", window_size_index)
	config.set_value(SECTION, "frame_rate_limit", frame_rate_limit)
	config.set_value(SECTION, "vsync_enabled", vsync_enabled)
	last_save_error = MetaProgression._save_atomically(config, settings_path)
	return last_save_error
