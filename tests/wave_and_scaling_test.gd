extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const WaveDirectorScript := preload("res://scripts/systems/wave_director.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WAVE_SCALING_FAIL", 60.0)
	call_deferred("_run")


## The playthrough soaks are far too noisy to verify any of this — spawn
## angles, archetype rolls and whether an enemy happens to intercept the bot
## swing survival time by 20+ seconds between runs. These checks read the
## numbers directly instead.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WAVE_SCALING_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_late_ramp()
	_test_wave_clock()
	_test_surge_and_calm()
	await _test_culling(main)

	if failures.is_empty():
		print("WAVE_SCALING_PASS: late ramp is back-loaded, waves surge and lull, far enemies recycle")
		quit(0)
	else:
		for failure in failures:
			push_error("WAVE_SCALING_FAIL: " + failure)
		quit(1)


## "charger" rather than "chaser": a chaser rolls a random radius, and radius
## feeds the health formula, so two chasers at the same difficulty do not have
## the same health and nothing can be compared exactly.
func _stats_at(difficulty: float) -> Dictionary:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(difficulty, "charger")
	var stats := {"health": enemy.max_health, "damage": enemy.contact_damage}
	enemy.free()
	return stats


func _test_late_ramp() -> void:
	var early := _stats_at(0.0)
	var mid := _stats_at(ChaserEnemy.LATE_GAME_DIFFICULTY)
	var late := _stats_at(ChaserEnemy.LATE_GAME_DIFFICULTY * 2.0)

	# Below the threshold the ramp must contribute exactly nothing: the early
	# game measured as the lethal part already, and this change is not meant
	# to touch it.
	var linear_at_threshold: float = float(early["health"]) + ChaserEnemy.LATE_GAME_DIFFICULTY * 5.0
	_check(absf(float(mid["health"]) - linear_at_threshold) < 0.01,
		"at the threshold the health ramp has not started (%.1f vs linear %.1f)" % [mid["health"], linear_at_threshold])
	_check(is_equal_approx(float(mid["damage"]), float(early["damage"])),
		"contact damage is untouched up to the threshold")

	# Past it, both climb.
	# The multiplier applies to the linear value at the late difficulty, not to
	# the value back at the threshold.
	var late_difficulty := ChaserEnemy.LATE_GAME_DIFFICULTY * 2.0
	var linear_at_late: float = float(early["health"]) + late_difficulty * 5.0
	var expected_health := linear_at_late * (1.0 + ChaserEnemy.LATE_GAME_DIFFICULTY * ChaserEnemy.LATE_HEALTH_PER_STEP)
	_check(float(late["health"]) > float(mid["health"]) * 1.5,
		"late enemies are substantially tougher (%.0f -> %.0f)" % [mid["health"], late["health"]])
	_check(absf(float(late["health"]) - expected_health) < expected_health * 0.05,
		"the late health ramp follows its stated rate (%.0f, expected near %.0f)" % [late["health"], expected_health])
	_check(float(late["damage"]) > float(mid["damage"]),
		"late enemies also hit harder (%.1f -> %.1f)" % [mid["damage"], late["damage"]])
	print("SCALING_METRICS: chaser health d0=%.0f d%.0f=%.0f d%.0f=%.0f" % [
		early["health"], ChaserEnemy.LATE_GAME_DIFFICULTY, mid["health"],
		ChaserEnemy.LATE_GAME_DIFFICULTY * 2.0, late["health"]
	])


func _test_wave_clock() -> void:
	var director := WaveDirectorScript.new() as WaveDirector
	root.add_child(director)
	_check(director.wave_index == 0, "a run opens on wave zero")

	var started: Array[int] = []
	director.wave_started.connect(func(index: int, _surge: bool) -> void: started.append(index))

	# Step past two full wave durations without ever reaching the boss timer.
	var delta := 1.0 / 60.0
	var elapsed := 0.0
	for tick in int(WaveDirector.WAVE_DURATION * 2.0 / delta):
		elapsed += delta
		director.step(delta, elapsed, Vector2.ZERO, 0)
	_check(director.wave_index == 2, "two wave durations advance the counter twice (got %d)" % director.wave_index)
	_check(started == [1, 2], "each wave start is announced exactly once (%s)" % str(started))

	director.free()


func _test_surge_and_calm() -> void:
	var director := WaveDirectorScript.new() as WaveDirector
	root.add_child(director)
	_check(director.is_surge_wave(WaveDirector.SURGE_EVERY), "every SURGE_EVERY-th wave is a surge")
	_check(not director.is_surge_wave(1), "the first wave is an ordinary one")
	_check(not director.is_surge_wave(0), "wave zero is not treated as a surge")

	# A wave boundary spawns a burst, and a surge boundary spawns a bigger one.
	director.wave_elapsed = WaveDirector.WAVE_DURATION
	var ordinary := director.step(1.0 / 60.0, 10.0, Vector2.ZERO, 0)
	director.wave_index = WaveDirector.SURGE_EVERY - 1
	director.wave_elapsed = WaveDirector.WAVE_DURATION
	var surge := director.step(1.0 / 60.0, 10.0, Vector2.ZERO, 0)
	_check(surge.size() > ordinary.size(), "a surge wave opens with more enemies (%d vs %d)" % [surge.size(), ordinary.size()])

	# The lull stops the regular trickle but must not stop elites, or a calm
	# stretch would be a guaranteed safe window rather than a breather.
	director.wave_elapsed = WaveDirector.WAVE_DURATION - WaveDirector.WAVE_CALM
	director.in_calm = true
	director.spawn_timer = -1.0
	director.elite_timer = 999.0
	var during_calm := director.step(1.0 / 60.0, 60.0, Vector2.ZERO, 0)
	_check(during_calm.is_empty(), "the lull stops ordinary spawns (%d spawned)" % during_calm.size())

	director.elite_timer = -1.0
	var elite_in_calm := director.step(1.0 / 60.0, 60.0, Vector2.ZERO, 0)
	var found_elite := false
	for enemy in elite_in_calm:
		if enemy.elite:
			found_elite = true
	_check(found_elite, "an elite still arrives during the lull")

	director.free()


func _test_culling(main: Node) -> void:
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(100.0, 0.0)
	var origin: Vector2 = (main.players[0].position + main.players[1].position) * 0.5

	var near := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	near.position = origin + Vector2(300.0, 0.0)
	main._register_enemy(near)
	var far := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	far.position = origin + Vector2(main.ENEMY_CULL_RADIUS + 400.0, 0.0)
	main._register_enemy(far)

	var kills_before: int = main.kills
	var gems_before: int = main.experience_system.active_gems.size()
	var tracked_before: int = main.enemies.size()

	# The cull runs earlier in the same physics tick than the spawn step, so
	# without fully suppressing spawning the director immediately pops the
	# just-recycled enemy back out of the pool and the cull looks like it
	# never happened. A cap of zero stops the surge burst too.
	var real_cap: int = main.wave_director.enemy_cap
	main.wave_director.enemy_cap = 0

	main.set_physics_process(true)
	await physics_frame
	await physics_frame
	main.set_physics_process(false)

	_check(main.enemies.size() < tracked_before, "a distant enemy is removed from the active list")
	_check(near in main.enemies, "an enemy inside the cull radius is left alone")
	_check(not (far in main.enemies), "the distant enemy specifically is the one removed")
	# Culling is not a kill: no score, no experience, no field drop.
	_check(main.kills == kills_before, "recycling a wandering enemy does not count as a kill")
	_check(main.experience_system.active_gems.size() == gems_before, "recycling a wandering enemy drops no experience")

	# The far enemy should be back in the pool, ready for reuse.
	_check(far in main.wave_director.enemy_pool, "the recycled enemy returns to the spawn pool")
	main.wave_director.enemy_cap = real_cap


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
