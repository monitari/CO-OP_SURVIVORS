extends SceneTree

## Real main scene and native callbacks, at normal time scale. Synthetic,
## long-lived penetrating shots hold the requested count without respawning.
## Hit history is retained, so each shot damages each enemy at most once.
## Tick intervals include pacing/catch-up; they are not GPU or CPU-only times.
const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

## Brackets one tick's callbacks: a node that runs first and one that runs last
## (by process priority) record the span between them. Unlike the Performance
## TIME_* monitors this is exactly the CPU spent in this tick's callbacks.
class TickProbe extends Node:
	var first := false
	var physics_start := 0
	var process_start := 0
	var physics_ms: Array[float] = []
	var process_ms: Array[float] = []
	var partner: TickProbe
	var recording := false
	func _physics_process(_delta: float) -> void:
		if first:
			physics_start = Time.get_ticks_usec()
		elif recording:
			physics_ms.append((Time.get_ticks_usec() - partner.physics_start) / 1000.0)
	func _process(_delta: float) -> void:
		if first:
			process_start = Time.get_ticks_usec()
		elif recording:
			process_ms.append((Time.get_ticks_usec() - partner.process_start) / 1000.0)


static func make_probes(parent: Node) -> TickProbe:
	var opener := TickProbe.new()
	opener.first = true
	opener.process_physics_priority = -1000000
	opener.process_priority = -1000000
	opener.process_mode = Node.PROCESS_MODE_ALWAYS
	var closer := TickProbe.new()
	closer.partner = opener
	closer.process_physics_priority = 1000000
	closer.process_priority = 1000000
	closer.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(opener)
	parent.add_child(closer)
	return closer

var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, "PROJECTILE_INTEGRATION_FAIL", 1800.0)
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# PROJECTILE_LOOP=off hands every shot back its own physics callback, so the
	# same scene can be measured with and without the controller's single loop.
	HomingProjectile.driven_by_loop = OS.get_environment("PROJECTILE_LOOP") != "off"
	print("INTEGRATION_ENV: cpu=%s display=%s gpu=%s loop=%s" % [OS.get_processor_name(), DisplayServer.get_name(), RenderingServer.get_video_adapter_name(), HomingProjectile.driven_by_loop])
	for count in [0, 500, 1000, 2000]:
		await _case(count)
	# Mass release and re-acquire of every shot once a second, inside the real
	# scene: the pool path under a live crowd.
	await _case(2000, 60)
	var file := FileAccess.open("res://tests/tmp/projectile_integration_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(rows, "\t"))
	else:
		failures.append("cannot write results")
	if failures.is_empty():
		print("PROJECTILE_INTEGRATION_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("PROJECTILE_INTEGRATION_FAIL: " + failure)
		quit(1)

const TICKS := 600


static func _summary(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"mean_ms": total / maxf(1, sorted.size()), "p50_ms": sorted[int((sorted.size() - 1) * 0.5)],
		"p99_ms": sorted[int((sorted.size() - 1) * 0.99)], "max_ms": sorted.back()}


func _case(count: int, burst_every := 0) -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	# After the scene, not before: main._ready() calls randomize() over any
	# seed set earlier, so this is the line that actually makes the run repeat.
	seed(20260915)
	await process_frame
	if not Harness.require_loaded(self, main, "PROJECTILE_INTEGRATION_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	for player in main.players:
		player.max_health = 1e12
		player.health = 1e12
	main.elapsed = 900.0
	# No growth screen or chest may pause the tree mid-measurement.
	main.progression.required_experience = 1 << 30
	main.wave_director.enemy_cap = 620
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	for enemy in main.enemies:
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	for index in 620:
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy("chaser", 14.0, center, false, false)
		enemy.position = center + Vector2(randf_range(-550, 550), randf_range(-270, 270))
		enemy.max_health = 1e12
		enemy.health = 1e12
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	var shots: Array[HomingProjectile] = []
	for index in count:
		var shot: HomingProjectile = main.weapon_controller._acquire_projectile()
		shot.global_position = center + Vector2(randf_range(-550, 550), randf_range(-270, 270))
		shot.setup(Vector2.from_angle(randf() * TAU), main.enemies[index % 620])
		shot.spatial_grid = main.spatial_grid
		shot.style = "star" if index % 2 == 0 else "ember"
		shot.damage = 0.1
		shot.remaining_hits = 100000000
		shot.lifetime = 1e6
		shot.spawn_lifetime = 1e6
		shot.source_player = 0
		shot.source_weapon = "homing"
		shots.append(shot)
	for frame in 30:
		await physics_frame
	main.profiling = true
	main.profile_totals.clear()
	main.profile_frames = 0
	main.profile_frame_usec.clear()
	var intervals: Array[float] = []
	var probe := make_probes(root)
	probe.recording = true
	var burst_ms: Array[float] = []
	var active_samples: Array[int] = []
	var paused_ticks := 0
	var previous := Time.get_ticks_usec()
	for frame in TICKS:
		for shot in shots:
			if shot.ground_position.distance_squared_to(center) > 650.0 * 650.0:
				shot.ground_position = center + Vector2(randf_range(-500, 500), randf_range(-250, 250))
		if burst_every > 0 and frame % burst_every == burst_every - 1:
			var started := Time.get_ticks_usec()
			for shot in shots:
				shot.release()
			for index in shots.size():
				var shot: HomingProjectile = main.weapon_controller._acquire_projectile()
				shot.global_position = center + Vector2(randf_range(-550, 550), randf_range(-270, 270))
				shot.setup(Vector2.from_angle(randf() * TAU), main.enemies[index % main.enemies.size()])
				shot.spatial_grid = main.spatial_grid
				shot.style = "star" if index % 2 == 0 else "ember"
				shot.damage = 0.1
				shot.remaining_hits = 100000000
				shot.lifetime = 1e6
				shot.spawn_lifetime = 1e6
				shot.source_player = 0
				shot.source_weapon = "homing"
				shots[index] = shot
			burst_ms.append((Time.get_ticks_usec() - started) / 1000.0)
		await physics_frame
		var now := Time.get_ticks_usec()
		intervals.append((now - previous) / 1000.0)
		previous = now
		active_samples.append(main.weapon_controller.active_projectiles.size())
		if main.get_tree().paused:
			paused_ticks += 1
	main.profiling = false
	intervals.sort()
	var sum := 0.0
	for value in intervals:
		sum += value
	var phases := {}
	for key in main.profile_totals:
		phases[key] = float(main.profile_totals[key]) / maxf(1, main.profile_frames) / 1000.0
	active_samples.sort()
	var row := {"synthetic_shots": count, "burst_every": burst_every, "enemies": main.enemies.size(), "ticks": TICKS,
		"tick_interval_mean_ms": sum / intervals.size(), "tick_interval_p99_ms": intervals[int((intervals.size() - 1) * 0.99)],
		"tick_interval_max_ms": intervals.back(),
		"physics_process_cpu": _summary(probe.physics_ms), "process_cpu": _summary(probe.process_ms),
		"cpu_samples": [probe.physics_ms.size(), probe.process_ms.size()],
		"burst_release_reacquire": _summary(burst_ms) if not burst_ms.is_empty() else {},
		"paused_ticks": paused_ticks, "active_min": active_samples.front(),
		"active_max": active_samples.back(), "main_phase_ms": phases,
		"display": DisplayServer.get_name(), "game_over": main.game_over}
	rows.append(row)
	print("PROJECTILE_INTEGRATION: " + JSON.stringify(row))
	if main.game_over or paused_ticks > 0 or active_samples.front() < count or main.enemies.size() != 620:
		failures.append("integration failed to sustain crowd/projectile load")
	probe.recording = false
	probe.partner.queue_free()
	probe.queue_free()
	main.queue_free()
	await process_frame
