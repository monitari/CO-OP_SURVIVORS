class_name SharedProgression
extends Node

var level := 1
var experience := 0
var required_experience := requirement_for_level(1)

## A quadratic curve has no recurrence cliff: level two is calculated from the
## level number, not from “last cost + a late-game-sized constant”. The opening
## therefore reads 20 → 42 → 78 → 130, while the squared term still makes a
## high-level run ask substantially more for each additional card.
const BASE_REQUIREMENT := 20.0
const LINEAR_REQUIREMENT := 14.0
const QUADRATIC_REQUIREMENT := 7.5


static func requirement_for_level(current_level: int) -> int:
	var depth := float(maxi(0, current_level - 1))
	return int(round(BASE_REQUIREMENT + LINEAR_REQUIREMENT * depth + QUADRATIC_REQUIREMENT * depth * depth))


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

