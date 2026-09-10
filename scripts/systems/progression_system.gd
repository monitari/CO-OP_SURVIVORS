class_name SharedProgression
extends Node

var level := 1
var experience := 0
var required_experience := requirement_for_level(1)

## A quadratic curve has no recurrence cliff: level two is calculated from the
## level number, not from “last cost + a late-game-sized constant”. The opening
## therefore reads 20 → 42 → 78 → 130. A second curve starts only after
## level 40, where enemy count and gem grades surge; without it a 25-minute
## soak reached level 119 and stopped for a menu every 9.8 seconds late-game.
const BASE_REQUIREMENT := 20.0
const LINEAR_REQUIREMENT := 14.0
const QUADRATIC_REQUIREMENT := 7.5
const LATE_CURVE_START := 40.0
const LATE_QUADRATIC_REQUIREMENT := 12.0


static func requirement_for_level(current_level: int) -> int:
	var depth := float(maxi(0, current_level - 1))
	var late_depth := maxf(0.0, depth - LATE_CURVE_START)
	return int(round(BASE_REQUIREMENT + LINEAR_REQUIREMENT * depth
		+ QUADRATIC_REQUIREMENT * depth * depth
		+ LATE_QUADRATIC_REQUIREMENT * late_depth * late_depth))


func add_experience(amount: int) -> void:
	experience += amount


func can_level_up() -> bool:
	return experience >= required_experience


func consume_level_up() -> bool:
	if not can_level_up():
		return false
	experience -= required_experience
	level += 1
	required_experience = requirement_for_level(level)
	return true

