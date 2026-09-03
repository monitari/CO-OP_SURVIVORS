class_name SharedProgression
extends Node

var level := 1
var experience := 0
var required_experience := 25


func add_experience(amount: int) -> void:
	experience += amount


func can_level_up() -> bool:
	return experience >= required_experience


func consume_level_up() -> bool:
	if not can_level_up():
		return false
	experience -= required_experience
	level += 1
	required_experience = int(round(float(required_experience) * 1.22 + 5.0))
	return true

