extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FIELD_ITEM_FAIL", 90.0)
	call_deferred("_run")


## Field drops are walk-over pickups that act on the pair. Each effect is
## checked against the thing it claims to change rather than against the
## pickup firing at all, since a drop that plays a message and does nothing
## would otherwise look identical to a working one.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "FIELD_ITEM_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_pickup_requires_contact(main)
	await _test_expiry_and_pooling(main)
	_test_heal(main)
	_test_magnet(main)
	_test_chain_repair(main)
	_test_purge(main)
	_test_drop_rates(main)
	_test_table_integrity(main)

	if failures.is_empty():
		print("FIELD_ITEM_PASS: contact pickup, expiry/pooling, all four effects, elite guarantee, luck scaling")
		quit(0)
	else:
		for failure in failures:
			push_error("FIELD_ITEM_FAIL: " + failure)
		quit(1)


func _test_pickup_requires_contact(main: Node) -> void:
	main.field_items.clear_all()
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(120.0, 0.0)

	# Well out of reach: gems get magnetised, field drops deliberately do not.
	main.field_items.spawn_item(Vector2(600.0, 0.0), "heal")
	_check(main.field_items.active_items.size() == 1, "a spawned drop is tracked as active")
	main.field_items.step(main.players, 0.1)
	_check(main.field_items.active_items.size() == 1, "a distant drop is not magnetised toward the players")

	main.players[0].position = Vector2(600.0, 0.0)
	main.field_items.step(main.players, 0.1)
	_check(main.field_items.active_items.is_empty(), "walking onto a drop collects it")
	main.players[0].position = Vector2.ZERO
	await process_frame


func _test_expiry_and_pooling(main: Node) -> void:
	main.field_items.clear_all()
	var item: FieldItem = main.field_items.spawn_item(Vector2(900.0, 900.0), "heal")
	var pooled_before: int = main.field_items.item_pool.size()
	main.field_items.step(main.players, item.ITEM_LIFETIME + 1.0)
	_check(main.field_items.active_items.is_empty(), "a drop nobody reaches eventually expires")
	_check(main.field_items.item_pool.size() > pooled_before, "an expired drop returns to the pool for reuse")

	main.field_items.spawn_item(Vector2(950.0, 950.0), "heal")
	_check(main.field_items.item_pool.size() == pooled_before, "the next spawn reuses the pooled instance")
	main.field_items.clear_all()
	await process_frame


func _test_heal(main: Node) -> void:
	for player in main.players:
		player.downed = false
		player.max_health = 200.0
		player.health = 60.0
	main._on_field_item_collected("heal")
	_check(main.players[0].health > 60.0 and main.players[1].health > 60.0, "the heal drop restores both survivors, not only whoever touched it")


func _test_magnet(main: Node) -> void:
	main.experience_system.magnet_radius = 1.0 # nothing is close enough to drift in on its own
	var before: int = main.progression.experience
	for index in 5:
		main.experience_system.spawn_gem(Vector2(4000.0 + index * 50.0, 4000.0), 7)
	_check(main.experience_system.active_gems.size() == 5, "gems are on the field before the magnet fires")

	main._on_field_item_collected("magnet")
	_check(main.experience_system.active_gems.is_empty(), "the magnet drop sweeps up gems anywhere on the field")
	_check(main.progression.experience > before, "swept gems are actually banked as shared experience")
	main.experience_system.magnet_radius = main.EXPERIENCE_MAGNET_BASE

	main.level_up_active = false
	main.resonance_vote_active = false
	main.level_overlay.visible = false
	main.resonance_overlay.visible = false
	paused = false


func _test_chain_repair(main: Node) -> void:
	main.chain_integrity = 10.0
	main.chain_overloaded = true
	main._on_field_item_collected("chain_repair")
	_check(main.chain_integrity > 10.0, "the repair drop restores chain integrity")
	_check(not main.chain_overloaded, "enough repair clears an overloaded chain")

	main.chain_integrity = main.CHAIN_INTEGRITY_MAX
	main._on_field_item_collected("chain_repair")
	_check(main.chain_integrity <= main.CHAIN_INTEGRITY_MAX, "repair never overfills past the maximum")
	main.chain_overloaded = false


func _test_purge(main: Node) -> void:
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(100.0, 0.0)
	var midpoint: Vector2 = (main.players[0].position + main.players[1].position) * 0.5

	var near := _spawn_enemy(main, midpoint + Vector2(200.0, 0.0))
	var far := _spawn_enemy(main, midpoint + Vector2(main.FIELD_ITEM_PURGE_RADIUS + 300.0, 0.0))
	var near_before := near.health
	var far_before := far.health

	main._on_field_item_collected("purge")
	_check(near.health < near_before, "the purge drop burns enemies near the pair")
	_check(is_equal_approx(far.health, far_before), "the purge has a limited radius and spares distant enemies")

	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()


func _spawn_enemy(main: Node, position: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.position = position
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	return enemy


func _test_drop_rates(main: Node) -> void:
	main.field_items.clear_all()
	for index in 20:
		main._try_drop_field_item(Vector2(index * 40.0, 3000.0), true)
	_check(main.field_items.active_items.size() == 20, "every elite kill leaves a drop (got %d of 20)" % main.field_items.active_items.size())

	main.field_items.clear_all()
	main.team_luck = 0
	for index in 400:
		main._try_drop_field_item(Vector2(index, 3000.0), false)
	var unlucky: int = main.field_items.active_items.size()

	main.field_items.clear_all()
	main.team_luck = 12
	for index in 400:
		main._try_drop_field_item(Vector2(index, 3000.0), false)
	var lucky: int = main.field_items.active_items.size()

	# The boss carries the elite flag, so an ordering slip would hand out a
	# guaranteed drop at the same instant the run ends.
	main.field_items.clear_all()
	var boss := main.wave_director._acquire_enemy("brute", 3.0, Vector2(0.0, -400.0), true, true) as ChaserEnemy
	main._register_enemy(boss)
	boss.take_damage(999999.0)
	_check(main.field_items.active_items.is_empty(), "defeating the boss does not strand a drop as the run ends")
	main.game_over = false
	main.run_won = false
	main.result_overlay.visible = false
	paused = false
	main.field_items.clear_all()

	_check(unlucky < 400, "ordinary kills do not always drop")
	_check(lucky > unlucky, "luck raises the field drop rate (%d -> %d over 400 kills)" % [unlucky, lucky])
	print("FIELD_ITEM_METRICS: drops per 400 kills luck0=%d luck12=%d" % [unlucky, lucky])
	main.team_luck = 0
	main.field_items.clear_all()


func _test_table_integrity(main: Node) -> void:
	# Every id the roll can produce must be handled by the pickup effects and
	# have a name and colour, or a drop would land as an unlabelled no-op.
	var handled := ["heal", "magnet", "chain_repair", "purge"]
	var table_ids: Array[String] = []
	for entry in main.field_items.ITEM_TABLE:
		table_ids.append(String(entry["id"]))
		_check(not String(entry["name"]).is_empty(), "drop %s has a display name" % String(entry["id"]))
	for id in table_ids:
		_check(id in handled, "drop table id %s has a matching pickup effect" % id)
	for id in handled:
		_check(id in table_ids, "pickup effect %s is reachable from the drop table" % id)

	var seen: Dictionary = {}
	for roll in 300:
		seen[main.field_items.roll_item_id()] = true
	_check(seen.size() == table_ids.size(), "every drop type is actually reachable by the weighted roll (%d of %d)" % [seen.size(), table_ids.size()])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
