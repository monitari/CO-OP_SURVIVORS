extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const EnemyProjectileScript := preload("res://scripts/entities/enemy_projectile.gd")

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
	_test_chain_ward(main)
	await _test_timed_windows(main)
	_test_purge(main)
	_test_chest(main)
	_test_drop_rates(main)
	_test_table_integrity(main)

	if failures.is_empty():
		print("FIELD_ITEM_PASS: pickups, stronger golden collar, mixed chest loot, elite guarantee, luck scaling")
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
	# The magnet used to bank everything on the frame it fired, which meant the
	# most dramatic item in the game produced no image at all — a number moved.
	# It now puts every gem into flight, so what this has to check is that they
	# are travelling and that they arrive.
	for gem: ExperienceGem in main.experience_system.active_gems:
		_check(gem.magnetized, "every gem on the field is pulled, however far away it is")
	_check(not main.experience_system.active_gems.is_empty(), "the pull is a journey, not an instant collection")

	# Flown in over roughly a second of run time, from four thousand pixels out.
	for tick in 180:
		main.experience_system.step(main.players, 1.0 / 60.0)
	_check(main.experience_system.active_gems.is_empty(),
		"pulled gems arrive (%d still travelling)" % main.experience_system.active_gems.size())
	_check(main.progression.experience > before, "and are banked as shared experience")

	# A gem that was never magnetised must still respect the pickup radius, or
	# the item has quietly become permanent.
	main.experience_system.spawn_gem(Vector2(4000.0, 4000.0), 7)
	for tick in 120:
		main.experience_system.step(main.players, 1.0 / 60.0)
	_check(main.experience_system.active_gems.size() == 1,
		"a gem spawned after the magnet is not swept up by it")
	main.experience_system.magnetize_all()
	for tick in 180:
		main.experience_system.step(main.players, 1.0 / 60.0)
	main.experience_system.magnet_radius = main.EXPERIENCE_MAGNET_BASE

	main.level_up_active = false
	main.resonance_vote_active = false
	main.level_overlay.visible = false
	main.resonance_overlay.visible = false
	paused = false


## 사슬 결계 replaced 사슬 정비. The old drop refunded integrity, which is a
## number going up; this one suspends the whole chain economy for a window and
## turns the chain into a weapon while it lasts. Each of those is checked
## separately, because "the timer is running" is not evidence that anything is
## actually different while it runs.
func _test_chain_ward(main: Node) -> void:
	main.chain_integrity = 10.0
	main.chain_overloaded = true
	main._on_field_item_collected("chain_ward")
	_check(main.chain_warded(), "the ward drop opens a ward window")
	_check(is_equal_approx(main.chain_integrity, main.CHAIN_INTEGRITY_MAX),
		"the ward pins integrity at full")
	_check(not main.chain_overloaded, "the ward clears an overloaded chain")

	# Held at a gap that would normally be burning integrity fast.
	main.players[0].position = Vector2(-main.chain_max_length * 0.5, 0.0)
	main.players[1].position = Vector2(main.chain_max_length * 0.5, 0.0)
	_check(main._tension_damage_multiplier() > 1.2,
		"a warded chain pays the overcharge bonus regardless of tension")
	_check(main._tension_damage_multiplier() >= 1.5 and main.CHAIN_WARD_WIDTH >= 100.0,
		"the golden collar is a major damage and burn-width power window")

	var victim := _spawn_enemy(main, Vector2.ZERO)
	var before := victim.health
	for tick in 30:
		main._update_chain_ward(1.0 / 60.0)
		main._update_chain_integrity(1.0 / 60.0)
	_check(victim.health < before, "the warded chain burns what stands on it")
	_check(is_equal_approx(main.chain_integrity, main.CHAIN_INTEGRITY_MAX),
		"and integrity does not drain while the ward holds (%.1f)" % main.chain_integrity)

	# It has to end, or it is not a window.
	for tick in int(main.CHAIN_WARD_DURATION * 61.0):
		main._update_chain_ward(1.0 / 60.0)
	_check(not main.chain_warded(), "the ward expires")
	for tick in 30:
		main._update_chain_integrity(1.0 / 60.0)
	_check(main.chain_integrity < main.CHAIN_INTEGRITY_MAX,
		"and the chain is strained again once it does (%.1f)" % main.chain_integrity)

	victim.take_damage(999999.0)
	main.chain_integrity = main.CHAIN_INTEGRITY_MAX
	main.chain_overloaded = false


## The three timed drops. All of them are a *window*, so each is checked for
## the same three things: it starts, it actually changes the world while it
## runs, and it ends. A timer that ticks down without doing anything in between
## would pass a check that only looked at the flag.
func _test_timed_windows(main: Node) -> void:
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(120.0, 0.0)

	# 수호의 방울 — untouchable, and untouchable for its whole duration rather
	# than until the first hit resets the shared invulnerability timer.
	for player in main.players:
		player.downed = false
		player.health = player.max_health
		player.invulnerability = 0.0
	main._on_field_item_collected("guard")
	_check(main.guard_remaining > 0.0, "수호의 방울 opens a guard window")
	var before: float = main.players[0].health
	for tick in int(main.GUARD_DURATION * 30.0):
		main.players[0].hurt(50.0)
		main._update_timed_items(1.0 / 60.0)
	_check(is_equal_approx(main.players[0].health, before),
		"nothing gets through while it holds (%.0f of %.0f)" % [main.players[0].health, before])
	# The window has to be the authority over the shared invulnerability timer,
	# which a revive or an ordinary hit also writes to. Anything that clears it
	# mid-window must not end the guard early.
	main.players[0].invulnerability = 0.0
	main._update_timed_items(1.0 / 60.0)
	main.players[0].hurt(50.0)
	_check(is_equal_approx(main.players[0].health, before),
		"and a cleared invulnerability timer does not end it early (%.0f)" % main.players[0].health)
	for tick in int(main.GUARD_DURATION * 62.0):
		main._update_timed_items(1.0 / 60.0)
	_check(main.guard_remaining <= 0.0, "the guard window closes")
	# Earlier sub-tests hand out 행운의 앞발 and 아홉 목숨, either of which would
	# absorb this hit and make a mortal survivor look immortal.
	main.players[0].invulnerability = 0.0
	main.players[0].dodge_chance = 0.0
	main.players[0].second_chances = 0
	main.players[0].hurt(20.0)
	_check(main.players[0].health < before, "and the pair is mortal again")

	# 광란의 마타타비 — the same multiplier every weapon already reads, so the
	# whole loadout hits harder rather than one branch of it.
	main.players[0].health = main.players[0].max_health
	var calm: float = main._tension_damage_multiplier()
	var calm_interval: float = main._weapon_interval(0, 0)
	main._on_field_item_collected("frenzy")
	_check(main.frenzy_remaining > 0.0, "광란의 마타타비 opens a frenzy window")
	_check(main._tension_damage_multiplier() > calm * 1.5,
		"and the pair hits much harder (%.2f from %.2f)" % [main._tension_damage_multiplier(), calm])
	_check(main.players[0].field_move_multiplier > 1.0, "and both cats move faster")
	_check(main._weapon_interval(0, 0) < calm_interval, "and every weapon attacks faster")
	for tick in int(main.FRENZY_DURATION * 62.0):
		main._update_timed_items(1.0 / 60.0)
	_check(main.frenzy_remaining <= 0.0, "the frenzy window closes")
	_check(is_equal_approx(main._tension_damage_multiplier(), calm), "and damage returns to normal")
	_check(is_equal_approx(main.players[0].field_move_multiplier, 1.0), "and movement returns to normal")
	_check(is_equal_approx(main._weapon_interval(0, 0), calm_interval), "and attack speed returns to normal")

	# 멈춘 회중시계 — the world stops. Checked by moving something: a timer that
	# runs while enemies keep walking is not a time stop.
	var walker := _spawn_enemy(main, Vector2(400.0, 0.0))
	# Spawned through the run's own path rather than hand-built and parented.
	# Shots are now tracked in a list — four weapons shoot them down, and they
	# reach them from other nodes — so a projectile that never went through here
	# is one the run does not know exists, freeze included.
	main._on_enemy_ranged_attack(Vector2(0.0, 300.0), Vector2.UP, 5.0)
	var shot := main.enemy_shots[main.enemy_shots.size() - 1] as EnemyProjectile
	main._on_field_item_collected("time_stop")
	_check(main.world_stopped(), "멈춘 회중시계 stops the world")
	var stood: Vector2 = walker.global_position
	var shot_at: Vector2 = shot.global_position
	main.set_physics_process(true)
	for frame in 12:
		await physics_frame
	main.set_physics_process(false)
	_check(walker.global_position.distance_to(stood) < 1.0,
		"and nothing walks while it holds (%.1fpx)" % walker.global_position.distance_to(stood))
	_check(shot.global_position.distance_to(shot_at) < 1.0, "nor does anything already in the air")

	for tick in int(main.TIME_STOP_DURATION * 62.0):
		main._update_timed_items(1.0 / 60.0)
	_check(not main.world_stopped(), "the clock starts again")
	main.set_physics_process(true)
	for frame in 8:
		await physics_frame
	main.set_physics_process(false)
	_check(walker.global_position.distance_to(stood) > 1.0, "and the world moves again")

	walker.take_damage(999999.0)
	if is_instance_valid(shot):
		shot.queue_free()
	main.guard_remaining = 0.0
	main.frenzy_remaining = 0.0
	main.time_stop_remaining = 0.0
	await process_frame


func _test_purge(main: Node) -> void:
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(100.0, 0.0)
	main.world_camera.position = (main.players[0].position + main.players[1].position) * 0.5
	var visible: Rect2 = main._visible_world_rect()
	var near := _spawn_enemy(main, visible.get_center())
	var boss := _spawn_enemy(main, visible.get_center() + Vector2(120.0, 0.0), true)
	var far := _spawn_enemy(main, visible.position + Vector2(visible.size.x + 300.0, visible.size.y * 0.5))
	var far_before := far.health

	main._on_field_item_collected("purge")
	_check(near.dead, "the purge instantly defeats every ordinary enemy in view")
	_check(boss.dead, "the purge also instantly defeats a visible boss")
	_check(is_equal_approx(far.health, far_before), "the purge spares enemies outside the view")

	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()


func _spawn_enemy(main: Node, position: Vector2, boss := false) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "brute" if boss else "chaser", false, boss, 1 if boss else 0)
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

	# An early boss is a checkpoint and leaves a guaranteed drop; the final one
	# ends the run, so anything it left would be a pickup nobody can reach.
	main.field_items.clear_all()
	var early := main.wave_director._acquire_enemy("brute", 3.0, Vector2(0.0, -400.0), false, true, 1) as ChaserEnemy
	main._register_enemy(early)
	early.take_damage(999999.0)
	_check(main.field_items.active_items.size() == 1, "an early boss leaves a guaranteed drop behind")

	main.field_items.clear_all()
	var last := main.wave_director._acquire_enemy(
		"brute", 3.0, Vector2(0.0, -400.0), false, true, WaveDirector.BOSS_COUNT) as ChaserEnemy
	main._register_enemy(last)
	last.take_damage(999999.0)
	_check(main.field_items.active_items.is_empty(), "the final boss does not strand a drop as the run ends")
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


func _test_chest(main: Node) -> void:
	var weapon_count_before: int = main.weapon_loadouts[0].size() + main.weapon_loadouts[1].size()
	var treasure_count_before: int = main.treasure_loadouts[0].size() + main.treasure_loadouts[1].size()
	var depth_before: int = main._build_depth(0) + main._build_depth(1)
	seed(19273)
	var rewards: Array[Dictionary] = main._open_chest()
	var depth_after: int = main._build_depth(0) + main._build_depth(1)
	_check(rewards.size() >= 1 and rewards.size() <= main.CHEST_MAX_REWARDS,
		"a chest grants between one and the configured maximum (%d)" % rewards.size())
	_check(depth_after == depth_before + rewards.size(),
		"every ordinary chest reward adds one tier or one new tier-one item (%d -> %d)" % [depth_before, depth_after])
	for reward in rewards:
		_check(not String(reward.get("detail", "")).is_empty(), "a chest records the exact upgrade it applied")
		_check(String(reward.get("advice", "")) in ["recommended", "discouraged", "neutral"],
			"a chest reward carries a recommendation verdict")

	# New equipment competes with upgrades even before the existing build is
	# finished, and luck makes that branch measurably more likely.
	main.team_luck = 0
	var base_new_chance: float = main._chest_new_gear_chance()
	main.team_luck = 12
	var lucky_new_chance: float = main._chest_new_gear_chance()
	_check(lucky_new_chance > base_new_chance,
		"luck raises the chance that a chest contains unowned gear (%.1f%% -> %.1f%%)" % [base_new_chance * 100.0, lucky_new_chance * 100.0])
	var saw_new_gear: bool = (
		main.weapon_loadouts[0].size() + main.weapon_loadouts[1].size() > weapon_count_before
		or main.treasure_loadouts[0].size() + main.treasure_loadouts[1].size() > treasure_count_before)
	for attempt in 12:
		if saw_new_gear:
			break
		main._open_chest()
		saw_new_gear = (
			main.weapon_loadouts[0].size() + main.weapon_loadouts[1].size() > weapon_count_before
			or main.treasure_loadouts[0].size() + main.treasure_loadouts[1].size() > treasure_count_before)
	_check(saw_new_gear, "a chest can award a weapon or treasure that was not carried")
	main.team_luck = 0

	# Sampled over a hundred thousand rolls rather than a thousand. The top of
	# the ladder is under a tenth of a percent on purpose — it is a thing to be
	# told about, not a thing to plan around — so a thousand rolls would find it
	# once if it were lucky and the check would fail on the runs where it was not.
	seed(74291)
	var singles := 0
	var jackpots := 0
	var counts: Dictionary = {}
	for roll in 100000:
		var count: int = main._roll_chest_reward_count()
		counts[count] = int(counts.get(count, 0)) + 1
		if count == 1: singles += 1
		if count == main.CHEST_MAX_REWARDS: jackpots += 1
	_check(singles > 65000, "single-item chests stay the common result (%d/100000)" % singles)
	_check(jackpots > 0 and jackpots < 400, "maximum chests are possible but vanishingly rare (%d/100000)" % jackpots)
	# Every rung has to be reachable, or the ladder is shorter than it claims.
	for rung in range(1, main.CHEST_MAX_REWARDS + 1):
		_check(int(counts.get(rung, 0)) > 0, "a chest can hand out exactly %d" % rung)
	# ...and each one rarer than the one below it, which is what makes a big
	# chest read as a big chest rather than as noise.
	for rung in range(2, main.CHEST_MAX_REWARDS + 1):
		_check(int(counts.get(rung, 0)) < int(counts.get(rung - 1, 0)),
			"%d rewards is rarer than %d (%d vs %d)" % [rung, rung - 1, int(counts.get(rung, 0)), int(counts.get(rung - 1, 0))])


func _test_table_integrity(main: Node) -> void:
	# Every id the roll can produce must be handled by the pickup effects and
	# have a name and colour, or a drop would land as an unlabelled no-op.
	var handled := ["heal", "magnet", "chain_ward", "guard", "frenzy", "time_stop", "purge"]
	var table_ids: Array[String] = []
	for entry in main.field_items.ITEM_TABLE:
		table_ids.append(String(entry["id"]))
		_check(not String(entry["name"]).is_empty(), "drop %s has a display name" % String(entry["id"]))
	_check(main.field_items.ITEM_TABLE.reduce(func(total: int, entry: Dictionary) -> int: return total + int(entry["weight"]), 0) == 100,
		"field-item weights are explicit percentages")
	for id in table_ids:
		_check(id in handled, "drop table id %s has a matching pickup effect" % id)
	for id in handled:
		_check(id in table_ids, "pickup effect %s is reachable from the drop table" % id)
	_check(main.field_items.item_display_name("chest") != "chest", "the separately rolled chest has a display name")
	_check(main.field_items.item_color("chest") != Color.WHITE, "the separately rolled chest has its own colour")

	var seen: Dictionary = {}
	for roll in 300:
		seen[main.field_items.roll_item_id()] = true
	_check(seen.size() == table_ids.size(), "every drop type is actually reachable by the weighted roll (%d of %d)" % [seen.size(), table_ids.size()])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
