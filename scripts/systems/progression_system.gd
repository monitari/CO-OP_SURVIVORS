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
	# The curve is written against total experience earned, not against how many
	# gems it arrives in, so it survived drops being banked and then unbanked
	# again. What moved it was raising what elites and bosses pay out, which
	# had the run landing at fifty-four level-ups rather than the high forties
	# the tech tree is sized for.
	# Raised alongside the grade payout in main. Weighting the rungs so a late
	# prism is worth five motes is what stops the back half of a run drifting into
	# a level-up drought, but on its own it also handed the front half far more
	# than it needed — the soak came out at seventy-one levels. This takes the
	# surplus back out and leaves the shape the payout was there to fix: the run
	# lands around fifty-seven levels with the late gap no longer wider than the
	# early one (28.4s early, 25.8s late, against 27.7 and 34.0 before). A few
	# more levels than the high forties is deliberate — weapons now open much
	# weaker and are meant to be carried by what a player spends on them.
	required_experience = int(round(float(required_experience) * 1.05 + 470.0))
	return true

