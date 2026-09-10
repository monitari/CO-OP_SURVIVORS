extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const ArenaFloorScript := preload("res://scripts/entities/arena_floor.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "PACING_FAIL", 90.0)
	call_deferred("_run")


## Three things that decide whether a run feels continuous: level-ups that queue
## instead of stacking, a rooftop with no edge to reach, and a character select
## that does not hand over the back half of the run before it starts.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "PACING_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_level_ups_queue(main)
	_test_opening_experience_curve()
	_test_floor_is_endless()
	_test_floor_is_stable()
	_test_select_exposes_the_tech_tree(main)

	if failures.is_empty():
		print("PACING_PASS: level-ups queue, the roof has no edge, select exposes tech routes")
		quit(0)
	else:
		for failure in failures:
			push_error("PACING_FAIL: " + failure)
		quit(1)


## Experience arrives in bursts — a swarm pack, a magnet item — so several levels
## can come due on one frame. They used to open back to back, which turned a good
## moment into a stutter: stop, one frame of play, stop again.
func _test_level_ups_queue(main: Node) -> void:
	# Enough experience for at least three levels at once. Worked out on a
	# throwaway progression rather than by adding the *current* requirement
	# three times: the requirement grows with each level, so the naive version
	# banked one level and two thirds of nothing, and silently stopped testing
	# the queue the moment the curve changed.
	var probe := SharedProgression.new()
	var banked := 0
	for step in 3:
		banked += probe.required_experience
		probe.add_experience(probe.required_experience)
		probe.consume_level_up()
	probe.free()
	main.progression.add_experience(banked)
	_check(main.progression.can_level_up(), "the fixture actually banked several levels")

	main._begin_level_up()
	_check(main.level_up_active, "the first level-up opens immediately")
	var level_after_first: int = main.progression.level

	# Resolve it the way both players confirming would.
	main.level_up_active = false
	main.level_overlay.visible = false
	main._finish_level_up()
	_check(not main.level_up_active, "the screen closes before the next one is considered")
	_check(main.level_up_gap_remaining > 0.0,
		"a pending level waits out a gap rather than opening on the same frame")

	# The gap has to be spent on run time, so the pair gets it back as play.
	main.set_physics_process(true)
	await physics_frame
	await physics_frame
	_check(not main.level_up_active, "the run resumes during the gap")
	var gap_mid: float = main.level_up_gap_remaining
	_check(gap_mid < main.LEVEL_UP_GAP, "the gap drains while the run plays (%.2f)" % gap_mid)

	for tick in int(main.LEVEL_UP_GAP * 70.0):
		if main.level_up_active:
			break
		await physics_frame
	main.set_physics_process(false)
	_check(main.level_up_active, "the queued level-up does open once the gap elapses")
	_check(main.progression.level > level_after_first, "and it is a real level, not a repeat")

	main.level_up_active = false
	main.level_overlay.visible = false
	main.level_up_gap_remaining = 0.0
	paused = false


func _test_opening_experience_curve() -> void:
	var probe := SharedProgression.new()
	var opening_costs: Array[int] = []
	for step in 5:
		opening_costs.append(probe.required_experience)
		probe.add_experience(probe.required_experience)
		probe.consume_level_up()
	_check(opening_costs == [20, 42, 78, 130, 196],
		"the quadratic opening has no recurrence cliff (%s)" % str(opening_costs))
	var previous_growth := 0
	var previous_cost := opening_costs[opening_costs.size() - 1]
	for current_level in range(6, 31):
		var cost := SharedProgression.requirement_for_level(current_level)
		var growth := cost - previous_cost
		_check(growth >= previous_growth, "experience cost rises smoothly at level %d" % current_level)
		previous_growth = growth
		previous_cost = cost
	_check(SharedProgression.requirement_for_level(10) < 800,
		"the first ten growth choices stay reachable (%d XP)" % SharedProgression.requirement_for_level(10))
	_check(SharedProgression.requirement_for_level(50) > 15000,
		"the same curve still stretches the late run (%d XP)" % SharedProgression.requirement_for_level(50))
	_check(SharedProgression.requirement_for_level(100) > 100000,
		"the post-40 curve absorbs the late kill surge (%d XP)" %
			SharedProgression.requirement_for_level(100))
	probe.free()


## The roof used to be a fixed slab about four screens across. A pair that kited
## in one direction ran off the world.
func _test_floor_is_endless() -> void:
	var floor_node := ArenaFloorScript.new() as ArenaFloor
	root.add_child(floor_node)
	floor_node.follow(Vector2.ZERO)
	var origin_draws := floor_node.draw_origin

	# Somewhere no fixed slab would ever have reached.
	floor_node.follow(Vector2(120000.0, -90000.0))
	_check(floor_node.draw_origin != origin_draws, "the floor follows the view out to any distance")
	_check(floor_node.draw_origin.distance_to(Vector2(120000.0, -90000.0)) < ArenaFloor.REDRAW_STEP * 2.0,
		"and stays centred on it (%s)" % str(floor_node.draw_origin))

	# It must not rebuild every frame, or an endless floor is an endless cost.
	var settled := floor_node.draw_origin
	floor_node.follow(Vector2(120000.0, -90000.0) + Vector2(ArenaFloor.REDRAW_STEP * 0.2, 0.0))
	_check(floor_node.draw_origin == settled, "small camera moves do not rebuild the floor")
	floor_node.follow(Vector2(120000.0, -90000.0) + Vector2(ArenaFloor.REDRAW_STEP * 2.5, 0.0))
	_check(floor_node.draw_origin != settled, "crossing a step does rebuild it")
	floor_node.free()


## An endless roof still has to be a place: the same patch has to look the same
## every time the pair crosses it, or the world is noise.
func _test_floor_is_stable() -> void:
	var floor_node := ArenaFloorScript.new() as ArenaFloor
	root.add_child(floor_node)
	var first := floor_node._cell_seed(7, -3)
	var again := floor_node._cell_seed(7, -3)
	_check(first == again, "a cell generates the same contents twice")
	_check(floor_node._cell_seed(7, -3) != floor_node._cell_seed(-3, 7),
		"mirrored cells are different places")
	_check(floor_node._cell_seed(1, 1) != floor_node._cell_seed(2, 2), "neighbouring cells differ")
	_check(floor_node._cell_seed(0, 0) >= 0, "seeds are usable by RandomNumberGenerator")
	floor_node.free()


## The route is now a plan, not a spoiler: character select must name every
## final form and tell a first-time player that resonance resolves automatically.
func _test_select_exposes_the_tech_tree(main: Node) -> void:
	main._refresh_character_select_ui()
	var shown := String(main.character_p1_label.text) + "\n" + String(main.character_p2_label.text) \
		+ "\n" + String(main.character_synergy_label.text)

	for player_index in 2:
		var character: Dictionary = main.character_catalog[main.selected_character_indices[player_index]]
		var evolution := EvolutionCatalog.for_base(String(character["weapon_id"]))
		_check(shown.contains(String(evolution["weapon_name"])),
			"select names the planned final form %s" % String(evolution["weapon_name"]))
	_check(shown.contains("자동 공명"), "select explains automatic resonance")

	# The starting weapon and route are both visible alongside the icon.
	for player_index in 2:
		var character: Dictionary = main.character_catalog[main.selected_character_indices[player_index]]
		var card := String(main.character_p1_label.text if player_index == 0 else main.character_p2_label.text)
		_check(card.contains(String(character["weapon_name"])), "the card still names the weapon")
		_check(card.contains("필요"), "and names route materials")
		_check(not card.contains("난이도"), "and does not classify the pick by difficulty")
		_check(main.character_overlay.get_node("CatWeapon%d" % player_index).texture != null, "and shows its weapon icon")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
