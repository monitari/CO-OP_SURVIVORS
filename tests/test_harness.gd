extends RefCounted

## Shared guards for the headless test entry scripts.
##
## A SceneTree test only ends when it reaches quit(). If the coroutine driving
## it dies first — a parse error on main.gd, a runtime error mid-assertion —
## nothing calls quit() and the process spins until the CI runner kills it.
## That surfaces as a hang rather than a failure, which is how a completely
## unloadable build once passed for a full session.


## Force-fails the run if quit() is never reached. Ignores Engine.time_scale so
## the accelerated soak test gets the same wall-clock budget as everything else.
static func arm_watchdog(tree: SceneTree, prefix: String, seconds: float) -> void:
	var timer := tree.create_timer(seconds, true, false, true)
	timer.timeout.connect(func() -> void:
		push_error("%s: watchdog timeout after %.1fs — the test never reached quit()" % [prefix, seconds])
		tree.quit(1)
	)


## Fails fast when main.tscn instantiated but its script did not compile.
## Without this the first property access on the bare Node2D errors out and
## takes the coroutine with it.
static func require_loaded(tree: SceneTree, main: Node, prefix: String) -> bool:
	if main.get_script() != null:
		return true
	push_error("%s: res://scripts/main.gd failed to load — see the parse errors above" % prefix)
	tree.quit(1)
	return false
