class_name SharedProgression
extends Node

var level := 1
var experience := 0
var required_experience := 30


func add_experience(amount: int) -> void:
	experience += amount


func can_level_up() -> bool:
	return experience >= required_experience


func consume_level_up() -> bool:
	if not can_level_up():
		return false
	experience -= required_experience
	level += 1
	# Every level-up pauses the run for both players to pick an upgrade, so the
	# curve has to be steep enough that the game is mostly combat rather than
	# mostly menus. At the roster's baseline kill rate this lands level-ups
	# roughly 20-25 seconds apart instead of the ~12 seconds the shallower
	# curve produced.
	required_experience = int(round(float(required_experience) * 1.38 + 8.0))
	return true

