extends SceneTree

## Guards the 2026-09-19 performance pass (docs/performance-2026-09-19.md).
##
## Wall-clock numbers cannot be asserted here — they move with the machine and
## with whatever else the suite is running — so this checks the mechanisms the
## speed-up rests on instead, each of which fails loudly if it is undone:
##
##   1. an HUD refresh that changes nothing notifies no theme change, because a
##      theme change re-shapes a label's text and sixty of those a second were
##      the largest single cost in a late-run frame
##   2. a batched milk puddle does not draw itself; the renderer draws it
##   3. the fine-grid query_radius finds exactly the bodies a brute-force scan
##      over live positions finds

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RENDER_BUDGET_FAIL", 120.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	seed(20260919)
	await process_frame
	if not TestHarness.require_loaded(self, main, "RENDER_BUDGET_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_idle_hud_refresh_is_silent(main)
	await _test_puddles_are_batched(main)
	_test_query_radius_matches_brute_force(main)

	if failures.is_empty():
		print("RENDER_BUDGET_PASS: silent idle HUD refresh, batched puddles, exact fine-grid query")
		quit(0)
	else:
		for failure in failures:
			push_error("RENDER_BUDGET_FAIL: " + failure)
		quit(1)


func _test_idle_hud_refresh_is_silent(main: Node) -> void:
	# Settle once: the first refresh after a run starts legitimately sets colours.
	main._update_hud()
	await process_frame
	var notified := {"count": 0, "who": []}
	var labels: Array[Control] = []
	var stack: Array[Node] = [main.combat_hud]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Control:
			labels.append(node as Control)
	var counter := func(control: Control) -> void:
		notified["count"] = int(notified["count"]) + 1
		if (notified["who"] as Array).size() < 5:
			(notified["who"] as Array).append(String(control.get_path()).get_file())
	for control in labels:
		control.theme_changed.connect(counter.bind(control))
	for tick in 3:
		main._update_hud()
		for border in _borders(main):
			border.refresh()
	await process_frame
	_check(int(notified["count"]) == 0,
		"three HUD refreshes over an unchanged run notify no theme change (%d: %s)"
			% [int(notified["count"]), str(notified["who"])])
	for control in labels:
		control.theme_changed.disconnect(counter.bind(control))


func _borders(main: Node) -> Array:
	var found: Array = []
	var stack: Array[Node] = [main.combat_hud]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node.name == "CooldownBorder":
			found.append(node)
	return found


func _test_puddles_are_batched(main: Node) -> void:
	var milk: Dictionary = {}
	for character in main.character_catalog:
		if String(character["weapon_id"]) == "milk":
			milk = character
	main.weapon_loadouts[0] = [main._build_weapon_state(milk)]
	main.attack_timers[0] = [0.0]
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await process_frame
	var pools: Array[MilkPool] = []
	for child in main.weapon_controller.get_children():
		if child is MilkPool:
			pools.append(child)
	_check(not pools.is_empty(), "the milk weapon spills puddles to check")
	var batched := 0
	for pool in pools:
		batched += 1 if pool.batched else 0
	_check(batched == pools.size(), "every puddle the weapon spills is batched (%d of %d)" % [batched, pools.size()])
	var renderer: MilkPoolRenderer = main.weapon_controller.milk_renderer
	renderer.refresh()
	_check(renderer.drawn == pools.size(),
		"the batch renderer draws every live puddle (%d of %d)" % [renderer.drawn, pools.size()])


func _test_query_radius_matches_brute_force(main: Node) -> void:
	var grid: EnemySpatialGrid = main.spatial_grid
	var crowd: Array[ChaserEnemy] = []
	for index in 400:
		var enemy := main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false) as ChaserEnemy
		enemy.position = Vector2(randf_range(-900.0, 900.0), randf_range(-600.0, 600.0))
		main._register_enemy(enemy)
		crowd.append(enemy)
	grid.rebuild(main.enemies)
	var mismatches := 0
	for probe in 60:
		var origin := Vector2(randf_range(-1000.0, 1000.0), randf_range(-700.0, 700.0))
		var radius := randf_range(10.0, 520.0)
		var expected: Dictionary = {}
		for enemy in main.enemies:
			if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_squared_to(origin) <= radius * radius:
				expected[enemy] = true
		var found := grid.query_radius(origin, radius)
		var seen: Dictionary = {}
		for enemy in found:
			seen[enemy] = true
		if seen.size() != found.size() or seen.size() != expected.size():
			mismatches += 1
			continue
		for enemy in expected:
			if not seen.has(enemy):
				mismatches += 1
				break
	_check(mismatches == 0, "query_radius agrees with a brute-force scan on 60 random queries (%d disagreed)" % mismatches)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
