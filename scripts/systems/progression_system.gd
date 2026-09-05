class_name SharedProgression
extends Node

var level := 1
var experience := 0
var required_experience := 32


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
	# mostly menus, and shallow enough that a run actually reaches the top of
	# its own tech tree.
	#
	# The 1.32 curve was drawn for a five-minute run and put level 20 at 8,400
	# experience — unreachable, which is why the whole back half of the tree
	# was theoretical. A twenty-five-minute run has to deliver roughly forty
	# level-ups, so the curve is gentler and enemies now also carry more
	# experience as the run goes on (see ChaserEnemy.XP_PER_DIFFICULTY); the
	# two together are what keeps the cadence flat instead of collapsing into
	# a drought after ten minutes.
	# Retuned when the crowd grew: a run that kills twenty-four thousand things
	# instead of six thousand earns four times the experience for the same
	# twenty-five minutes, and the old curve turned that into seventy-two
	# level-ups — a build finished and maxed out long before the last boss.
	required_experience = int(round(float(required_experience) * 1.045 + 270.0))
	return true

