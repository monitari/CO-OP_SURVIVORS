extends SceneTree

## Where a physics frame actually goes when the screen is full.
##
## crowd_performance_test times the separation pass on its own, which answers
## "is that algorithm fast" and nothing else. The complaint this exists for is
## "the game drops frames when there are a lot of enemies", and that is a claim
## about a whole tick: AI, grid, separation, effects, pickups, weapons, HUD.
## Timing one phase in isolation cannot tell you which phase to fix, and it was
## the reason contact resolution looked like the obvious culprit.
##
## The numbers printed here are a CPU measurement of the simulation only. There
## is no renderer in a headless run, so the node census at the end stands in for
## the draw side: what the GPU is asked to do scales with those counts.
##
## Read FRAME_SPREAD by hand when changing anything in the tick. The average is
## not what a player feels — a pass that runs on alternate frames costs nothing
## on one tick and double on the next, and only the double misses the deadline —
## so the percentiles are the useful output. They are printed rather than
## asserted on because wall-clock numbers inflate by half again when the suite
## runs them alongside forty other Godot processes, and an assertion that fails
## for that reason teaches nobody anything. The assertion below is on the shape
## of the curve instead, which contention does not move.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

## One physics tick at the project's 60Hz. The frame budget everything below is
## measured against.
const FRAME_BUDGET_MS := 16.67
const MEASURED_FRAMES := 240
const WARMUP_FRAMES := 30

## The crowd sizes worth knowing about: a busy mid-run screen, and the spawn cap
## the late game actually reaches.
const CROWD_SIZES := [200, 400, 620]

var failures: Array[String] = []
## Cost per enemy at each crowd size, so the assertions can talk about how the
## tick scales rather than about a wall-clock number.
var per_enemy_usec: Dictionary = {}


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FRAME_BUDGET_FAIL", 300.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	# After the scene, not before: main._ready() calls randomize() over any
	# seed set earlier, so this is the line that actually makes the run repeat.
	seed(20260906)
	await process_frame
	if not TestHarness.require_loaded(self, main, "FRAME_BUDGET_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await process_frame
	# The tick is driven by hand below so each crowd size gets exactly the same
	# number of frames regardless of how fast the host runs them.
	main.set_physics_process(false)
	# The measurement must not end early because the pair died to the crowd it
	# is standing in, and it must not be distorted by a level-up screen opening.
	for player in main.players:
		player.max_health = 1000000.0
		player.health = 1000000.0

	for size in CROWD_SIZES:
		await _measure(main, size)

	_census(main)
	_assert_scaling()

	if failures.is_empty():
		print("FRAME_BUDGET_PASS: the tick stays linear in the crowd")
		quit(0)
	else:
		for failure in failures:
			push_error("FRAME_BUDGET_FAIL: " + failure)
		quit(1)


## Fills the field to `size` live enemies, runs the real tick, and reports the
## per-phase split. Spawning goes through the director's own pool so archetypes,
## difficulty scaling and combat state match a real run rather than a field of
## identical default chasers.
func _measure(main: Node, size: int) -> void:
	for enemy in main.enemies:
		if is_instance_valid(enemy):
			main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	main.boss_enemy = null

	# A late-run field: difficulty decides which archetypes exist and how much
	# health they carry, and measuring the opening minute's mice would answer a
	# question nobody is asking.
	main.elapsed = 900.0
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	var difficulty: float = main.elapsed / main.wave_director.DIFFICULTY_SECONDS
	for index in size:
		var archetype: String = main.wave_director._pick_archetype(main.elapsed)
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy(archetype, difficulty, center, index % 12 == 0, false)
		# Spread across the ring the fight actually happens in. Dropping them all
		# on one point would measure a pile-up, which is a different question.
		var angle := TAU * float(index) / float(size)
		enemy.position = center + Vector2.from_angle(angle) * randf_range(120.0, 780.0)
		main._register_enemy(enemy)
	# Crowd size is the independent variable, so the director is capped at it
	# rather than left free to top the field up mid-measurement.
	main.wave_director.enemy_cap = size

	main.profiling = false
	for frame in WARMUP_FRAMES:
		main._physics_process(1.0 / 60.0)
		await process_frame

	main.profile_totals.clear()
	main.profile_frames = 0
	main.profile_frame_usec.clear()
	main.profiling = true
	# Accumulated per call rather than across the loop: the awaits between ticks
	# are the engine's own frame, and counting them would measure the harness.
	var wall_usec := 0
	for frame in MEASURED_FRAMES:
		var call_start := Time.get_ticks_usec()
		main._physics_process(1.0 / 60.0)
		wall_usec += Time.get_ticks_usec() - call_start
		await process_frame
	var wall_ms := float(wall_usec) / 1000.0 / float(MEASURED_FRAMES)
	main.profiling = false

	var live := 0
	for enemy in main.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			live += 1

	var sections: Array = main.profile_totals.keys()
	sections.sort_custom(func(a, b): return float(main.profile_totals[a]) > float(main.profile_totals[b]))
	var frames := maxf(1.0, float(main.profile_frames))
	var parts: PackedStringArray = []
	var simulated_ms := 0.0
	for section in sections:
		var section_ms := float(main.profile_totals[section]) / frames / 1000.0
		simulated_ms += section_ms
		parts.append("%s=%.3f" % [section, section_ms])
	var spread: Array[int] = []
	for value in main.profile_frame_usec:
		spread.append(value)
	spread.sort()
	print("FRAME_BUDGET: crowd=%d live=%d tick_ms=%.3f measured_ms=%.3f (%.0f%% of %.2fms budget)" % [
		size, live, wall_ms, simulated_ms, simulated_ms / FRAME_BUDGET_MS * 100.0, FRAME_BUDGET_MS,
	])
	print("FRAME_SPREAD: crowd=%d p50=%.2f p90=%.2f p99=%.2f max=%.2f" % [
		size, _percentile(spread, 0.50), _percentile(spread, 0.90),
		_percentile(spread, 0.99), _percentile(spread, 1.0),
	])
	print("FRAME_SPLIT: crowd=%d %s" % [size, " ".join(parts)])

	per_enemy_usec[size] = simulated_ms * 1000.0 / maxf(1.0, float(live))


## The absolute millisecond figures above are the useful output of this test and
## the reason to run it by hand, but they cannot be asserted on: run inside the
## full suite they come out half again as large as they do alone, because the
## host is busy and every section inflates together. What survives that noise is
## the shape of the curve. Separation and steering are meant to be linear in the
## crowd — that is what the spatial grid and the bounded sampling are for — so
## the cost of one enemy should not climb as the crowd grows. A pass that
## quietly became quadratic is the regression worth catching here, and it shows
## up in this ratio no matter how loaded the machine is.
func _assert_scaling() -> void:
	var smallest: int = CROWD_SIZES[0]
	var largest: int = CROWD_SIZES[CROWD_SIZES.size() - 1]
	if not per_enemy_usec.has(smallest) or not per_enemy_usec.has(largest):
		failures.append("both crowd sizes must be measured")
		return
	var small: float = per_enemy_usec[smallest]
	var large: float = per_enemy_usec[largest]
	var growth := large / maxf(0.001, small)
	print("FRAME_SCALING: per_enemy_usec %d=%.2f %d=%.2f growth=%.2fx" % [
		smallest, small, largest, large, growth,
	])
	_check(growth < 2.0,
		"tripling the crowd does not raise the cost of one enemy (%.2fx)" % growth)
	# A loose ceiling that only a catastrophe trips. It exists so a change that
	# makes the tick several times slower still fails the suite rather than
	# merely printing a worse number nobody reads.
	_check(per_enemy_usec[largest] * float(largest) / 1000.0 < FRAME_BUDGET_MS * 2.0,
		"a full crowd stays within twice the frame budget even on a loaded host")


## What the draw side is handed. Every CanvasItem is at minimum one item the
## renderer has to walk, cull and submit, so this is the number that decides
## whether the GPU work is one batch or several hundred.
func _census(main: Node) -> void:
	var nodes := 0
	var canvas_items := 0
	var visible_items := 0
	var pending: Array[Node] = [main]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		nodes += 1
		var item := node as CanvasItem
		if item != null:
			canvas_items += 1
			if item.is_visible_in_tree():
				visible_items += 1
		for child in node.get_children():
			pending.append(child)
	print("FRAME_CENSUS: nodes=%d canvas_items=%d visible=%d enemies=%d" % [
		nodes, canvas_items, visible_items, main.enemies.size(),
	])


## Milliseconds at a rank in the sorted spread of tick times.
func _percentile(sorted_usec: Array[int], fraction: float) -> float:
	if sorted_usec.is_empty():
		return 0.0
	var index := clampi(int(floor(fraction * float(sorted_usec.size() - 1))), 0, sorted_usec.size() - 1)
	return float(sorted_usec[index]) / 1000.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
