extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "CROWD_FAIL", 180.0)
	call_deferred("_run")


## Bodies are solid, and there are a great many more of them.
##
## Every enemy walked at the nearest survivor along its own straight line, so
## anything that spawned on a similar bearing converged into a single stack:
## twenty mice standing inside one mouse's silhouette, dealing twenty mice's
## contact damage from a shape the player reads as one enemy. The swarm
## archetype — whose entire point is arriving as a mass — was the worst case.
##
## Solid bodies are also what makes a bigger crowd mean anything: two hundred
## enemies that can occupy the same point are not a horde, they are a stack.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "CROWD_FAIL"):
		return

	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_a_stack_spreads_out(main)
	await _test_separation_runs_during_play(main)
	await _test_a_boss_is_not_shoved(main)
	await _test_enemies_are_pushed_out_of_survivors(main)
	_test_the_late_game_can_fill_the_screen(main)

	if failures.is_empty():
		print("CROWD_PASS: bodies are solid, bosses hold their ground, the late game fills the screen")
		quit(0)
	else:
		for failure in failures:
			push_error("CROWD_FAIL: " + failure)
		quit(1)


## Twenty enemies dropped on one point have to become twenty enemies.
func _test_a_stack_spreads_out(main: Node) -> void:
	await _clear(main)
	var stack: Array[ChaserEnemy] = []
	for index in 20:
		# Not exactly coincident: a perfect stack is resolved by a random
		# bearing, which is correct behaviour but would make this measure luck.
		stack.append(_spawn(main, Vector2(600.0, 0.0) + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))))
	main.spatial_grid.rebuild(main.enemies)
	_check(_worst_overlap(stack) > 0.8, "the fixture really is a stack")

	for tick in 90:
		main.spatial_grid.rebuild(main.enemies)
		main._separate_crowd()
	var overlap := _worst_overlap(stack)
	_check(overlap < 0.35, "a stack spreads into a crowd (deepest overlap %.2f of a body)" % overlap)

	# Spread out, not scattered across the rooftop: separation is a nudge, and a
	# pack that arrived together still has to read as a pack.
	var centre := Vector2.ZERO
	for enemy in stack:
		centre += enemy.global_position
	centre /= float(stack.size())
	var furthest := 0.0
	for enemy in stack:
		furthest = maxf(furthest, centre.distance_to(enemy.global_position))
	_check(furthest < 260.0, "and stays a pack rather than exploding apart (%.0fpx)" % furthest)
	print("CROWD_METRICS: 20 stacked bodies settle to %.2f overlap within %.0fpx" % [overlap, furthest])
	await _clear(main)


## The checks below drive _separate_crowd directly, which says nothing about
## whether the run ever calls it. This one plays real physics frames instead:
## the rule has to be wired into the loop, not merely implemented.
func _test_separation_runs_during_play(main: Node) -> void:
	await _clear(main)
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(120.0, 0.0)
	var stack: Array[ChaserEnemy] = []
	for index in 14:
		stack.append(_spawn(main, Vector2(700.0, 0.0) + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))))
	main.spatial_grid.rebuild(main.enemies)
	_check(_worst_overlap(stack) > 0.8, "the fixture really is a stack")

	main.set_physics_process(true)
	for frame in 40:
		await physics_frame
	main.set_physics_process(false)
	var alive: Array[ChaserEnemy] = []
	for enemy in stack:
		if is_instance_valid(enemy) and not enemy.dead:
			alive.append(enemy)
	_check(alive.size() >= 4, "enough of the fixture survived to measure (%d)" % alive.size())
	_check(_worst_overlap(alive) < 0.5,
		"a live run pulls a stack apart on its own (%.2f)" % _worst_overlap(alive))
	await _clear(main)


## The boss is the one thing on the field whose position is a promise: a wall of
## mice must not be able to walk it out of its own arena.
func _test_a_boss_is_not_shoved(main: Node) -> void:
	await _clear(main)
	var boss := EnemyScript.new() as ChaserEnemy
	boss.setup(3.0, "brute", false, true, 1)
	boss.position = Vector2(600.0, 0.0)
	main.add_child(boss)
	main.enemies.append(boss)
	var minions: Array[ChaserEnemy] = []
	for index in 12:
		minions.append(_spawn(main, boss.position + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))))

	var stood := boss.global_position
	for tick in 90:
		main.spatial_grid.rebuild(main.enemies)
		main._separate_crowd()
	_check(boss.global_position.distance_to(stood) < 0.5,
		"a boss does not move when a crowd piles onto it (%.1fpx)" % boss.global_position.distance_to(stood))
	var inside := 0
	for minion in minions:
		if minion.global_position.distance_to(boss.global_position) < boss.radius:
			inside += 1
	_check(inside == 0, "but the crowd is pushed off it (%d still inside)" % inside)
	await _clear(main)


## One-way: an enemy is pushed out of a survivor, never the other way round.
## Shoving the player would take the controls away exactly when they matter.
func _test_enemies_are_pushed_out_of_survivors(main: Node) -> void:
	await _clear(main)
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(200.0, 0.0)
	var walker := _spawn(main, Vector2(4.0, 0.0))
	var player_stood: Vector2 = main.players[0].position

	for tick in 30:
		main.spatial_grid.rebuild(main.enemies)
		main._separate_crowd()
	_check(main.players[0].position == player_stood, "the survivor is never pushed")
	var gap := walker.global_position.distance_to(main.players[0].global_position)
	_check(gap >= main.players[0].radius + walker.radius - 1.0,
		"and the enemy ends up outside them (%.0fpx of %.0f)" % [gap, main.players[0].radius + walker.radius])
	await _clear(main)


## The back half of a run is supposed to be able to bury the screen. Checked on
## the schedule rather than by playing it out — coop_soak_test measures what
## actually turns up, this pins that the schedule can produce it at all.
func _test_the_late_game_can_fill_the_screen(main: Node) -> void:
	var director: WaveDirector = main.wave_director
	_check(director.enemy_cap >= 600, "the field is allowed to hold a real horde (%d)" % director.enemy_cap)
	_check("deluge" in WaveDirector.ENCOUNTER_ORDER, "the rota contains the screen-filling encounter")

	# Held back: the deluge is a climax, not an opening.
	director.encounters_run = WaveDirector.ENCOUNTER_ORDER.find("deluge")
	director.encounter_timer = 0.0
	var early: Array[String] = []
	director.encounter_started.connect(func(id: String) -> void: early.append(id))
	director.step(1.0 / 60.0, 120.0, Vector2.ZERO, 0)
	_check(early.size() == 1 and early[0] != "deluge",
		"no deluge in the opening minutes (%s)" % str(early))

	var late: Array[ChaserEnemy] = []
	director._run_encounter("deluge", 1200.0 / WaveDirector.DIFFICULTY_SECONDS, Vector2.ZERO, 0, late)
	_check(late.size() >= 60, "a late deluge is a screenful (%d bodies)" % late.size())
	var radii: Dictionary = {}
	for enemy in late:
		radii[roundi(enemy.global_position.length() / 50.0)] = true
	_check(radii.size() >= 3, "arriving in ranks rather than as one wall (%d rings)" % radii.size())
	var mid: Array[ChaserEnemy] = []
	director._run_encounter("deluge", 480.0 / WaveDirector.DIFFICULTY_SECONDS, Vector2.ZERO, 0, mid)
	_check(late.size() > mid.size(), "and it grows with the run (%d then %d)" % [mid.size(), late.size()])
	print("CROWD_METRICS: deluge %d at 8:00, %d at 20:00, cap %d" % [mid.size(), late.size(), director.enemy_cap])
	for pool: Array[ChaserEnemy] in [late, mid]:
		for enemy in pool:
			director.release_enemy(enemy)


## Deepest overlap in the group, as a fraction of a body's width. 0 means no two
## bodies touch; 1 means two are standing in exactly the same place.
func _worst_overlap(group: Array[ChaserEnemy]) -> float:
	var worst := 0.0
	for index in group.size():
		for other in range(index + 1, group.size()):
			var first := group[index]
			var second := group[other]
			var reach := first.radius + second.radius
			var gap := first.global_position.distance_to(second.global_position)
			worst = maxf(worst, clampf((reach - gap) / reach, 0.0, 1.0))
	return worst


func _spawn(main: Node, at: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.position = at
	main.add_child(enemy)
	main.enemies.append(enemy)
	return enemy


func _clear(main: Node) -> void:
	for candidate in main.enemies.duplicate():
		var enemy := candidate as ChaserEnemy
		if is_instance_valid(enemy):
			enemy.dead = true
			enemy.queue_free()
	main.enemies.clear()
	main.spatial_grid.rebuild(main.enemies)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
