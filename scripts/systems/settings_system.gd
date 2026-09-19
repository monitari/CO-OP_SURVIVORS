class_name GameSettings
extends RefCounted

const SETTINGS_PATH := "user://chainbound_settings.cfg"
const SECTION := "accessibility"
var settings_path := SETTINGS_PATH # Tests isolate saves from user preferences.

var sound_enabled := true
var music_enabled := true
var sound_volume := 0.75
var music_volume := 0.70
var damage_numbers_enabled := true
var screen_shake_enabled := true
var large_text_enabled := false
var fullscreen_enabled := false
var window_size_index := 2
var last_save_error: Error = OK


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
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


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, "sound_enabled", sound_enabled)
	config.set_value(SECTION, "music_enabled", music_enabled)
	config.set_value(SECTION, "sound_volume", sound_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "damage_numbers_enabled", damage_numbers_enabled)
	config.set_value(SECTION, "screen_shake_enabled", screen_shake_enabled)
	config.set_value(SECTION, "large_text_enabled", large_text_enabled)
	config.set_value(SECTION, "fullscreen_enabled", fullscreen_enabled)
	config.set_value(SECTION, "window_size_index", window_size_index)
	last_save_error = config.save(settings_path)
	return last_save_error
