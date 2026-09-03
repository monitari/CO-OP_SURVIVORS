class_name GameSettings
extends RefCounted

const SETTINGS_PATH := "user://chainbound_settings.cfg"
const SECTION := "accessibility"

var sound_enabled := true
var damage_numbers_enabled := true
var screen_shake_enabled := true


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	sound_enabled = bool(config.get_value(SECTION, "sound_enabled", sound_enabled))
	damage_numbers_enabled = bool(config.get_value(SECTION, "damage_numbers_enabled", damage_numbers_enabled))
	screen_shake_enabled = bool(config.get_value(SECTION, "screen_shake_enabled", screen_shake_enabled))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "sound_enabled", sound_enabled)
	config.set_value(SECTION, "damage_numbers_enabled", damage_numbers_enabled)
	config.set_value(SECTION, "screen_shake_enabled", screen_shake_enabled)
	config.save(SETTINGS_PATH)
