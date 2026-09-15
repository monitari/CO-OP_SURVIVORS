extends SceneTree

## Diagnostic benchmark, not an absolute-time CI gate. No production code is
## instrumented. Normal samples call the real projectile and grid methods;
## a separate instrumented pass attributes query cost, including timer overhead.
## Fixed positions are restored OUTSIDE the timed call to maintain equal load.
## Piercing, zero-damage shots keep the crowd/count constant. Repeated fresh
## contacts stress hit processing but exclude main.gd's damage signal listeners.
##
## The same script runs against the code before and after the projectile
## optimisation: optional features (retarget budget, fine grid, batch renderer)
## are detected rather than assumed, so both builds measure identical load.
const Harness := preload("res://tests/test_harness.gd")
const ProjectileScript := preload("res://scripts/entities/projectile.gd")
const COUNTS := [100, 500, 1000, 2000]
## 300 samples per spread condition so p99 is the 3rd-worst sample rather than
## the worst; dense conditions are two orders of magnitude slower before the
## change and keep 60.
const FRAMES := 300
const WARMUP := 30
const DENSE_FRAMES := 60
const DENSE_WARMUP := 6
const ENEMIES := 620
const DT := 1.0 / 60.0

class MeasuredGrid extends EnemySpatialGrid:
	var radius_usec := 0
	var nearest_usec := 0
	var contact_usec := 0
	var radius_calls := 0
	var nearest_calls := 0
	var contact_calls := 0
	var returned := 0
	func query_radius(origin: Vector2, reach: float) -> Array[ChaserEnemy]:
		var started := Time.get_ticks_usec()
		var result := super.query_radius(origin, reach)
		radius_usec += Time.get_ticks_usec() - started
		radius_calls += 1
		returned += result.size()
		return result
	func nearest(origin: Vector2, reach: float, excluded: Array[ChaserEnemy] = []) -> ChaserEnemy:
		var started := Time.get_ticks_usec()
		var result := super.nearest(origin, reach, excluded)
		nearest_usec += Time.get_ticks_usec() - started
		nearest_calls += 1
		return result

## Separate subclass so the "before" build, which has no projectile_contacts,
## still loads this file.
static func _measured_grid() -> EnemySpatialGrid:
	var probe := EnemySpatialGrid.new()
	if not probe.has_method("projectile_contacts"):
		return MeasuredGrid.new()
	var script := GDScript.new()
	script.source_code = """extends "res://tests/projectile_performance_test.gd".MeasuredGrid
func projectile_contacts(from: Vector2, to: Vector2, shot_radius: float, limit: int, exclude: Dictionary, out: Array[ChaserEnemy]) -> int:
	var started := Time.get_ticks_usec()
	var found := super.projectile_contacts(from, to, shot_radius, limit, exclude, out)
	contact_usec += Time.get_ticks_usec() - started
	contact_calls += 1
	returned += found
	return found
"""
	script.reload()
	return script.new()


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
var records: Array[Dictionary] = []
var has_budget := false
## Untyped handle: the preloaded constant is treated as the class and refuses
## Script methods, and the old build lacks the static being called.
var projectile_script: GDScript = load("res://scripts/entities/projectile.gd")
var has_fine_grid := false


func _initialize() -> void:
	Harness.arm_watchdog(self, "PROJECTILE_PERF_FAIL", 1800.0)
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.canvas_transform = Transform2D(0.0, Vector2(640, 360))
	has_budget = ProjectileScript.new().has_method("reset_retarget_budget")
	has_fine_grid = "projectile_cell_size" in EnemySpatialGrid.new()
	print("PROJECTILE_ENV: engine=%s cpu=%s threads=%d display=%s gpu=%s resolution=%s budget=%s fine_grid=%s batched=%s" % [
		Engine.get_version_info().string, OS.get_processor_name(), OS.get_processor_count(),
		DisplayServer.get_name(), RenderingServer.get_video_adapter_name(), str(root.size),
		str(has_budget), str(has_fine_grid), str(WeaponController.new().has_method("set_batching"))])
	var quick := _quick_cases()
	if not quick.is_empty():
		# Development loop: `-- --quick=spread:1000,dense_singlehit:2000,cells`
		# runs just those cases with 60 samples; not used for the report.
		for entry: String in quick:
			if entry == "cells":
				await _cell_size_ab()
			elif entry.begins_with("recovery:"):
				await _recovery_case(int(entry.get_slice(":", 1)))
			elif entry.begins_with("pool:"):
				await _pool_case(int(entry.get_slice(":", 1)))
			else:
				await _case(entry.get_slice(":", 0), int(entry.get_slice(":", 1)), -1.0, 60)
	elif "--render-only" in OS.get_cmdline_user_args():
		for count in [0, 500, 1000, 2000]:
			await _render_case(count, true)
		await _render_case(2000, false)
		await _visual_parity()
		# The real screen: main scene, 620-body crowd, HUD, shots with their real
		# flight heights and floor shadows. Shots get an empty grid so no hit
		# feedback is spawned and only drawing differs between runs.
		var can_toggle := WeaponController.new().has_method("set_batching")
		for count in [0, 1000, 2000]:
			await _game_render_case(count, true)
		if can_toggle:
			await _game_render_case(2000, false)
	else:
		for mode in ["empty", "spread", "spread_singlehit", "dense", "spread_retarget", "dense_retarget", "dense_singlehit"]:
			for count in COUNTS:
				await _case(mode, count)
		for count in [500, 1000, 2000]:
			await _recovery_case(count)
		for count in COUNTS:
			await _pool_case(count)
		if has_fine_grid:
			await _cell_size_ab()
	if has_budget:
		projectile_script.call("reset_retarget_budget", -1)
	var output := "res://tests/tmp/projectile_render_results.json" if "--render-only" in OS.get_cmdline_user_args() else "res://tests/tmp/projectile_cpu_results.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		failures.append("cannot write benchmark results")
	else:
		file.store_string(JSON.stringify({"engine": Engine.get_version_info().string,
			"cpu": OS.get_processor_name(), "display": DisplayServer.get_name(),
			"gpu": RenderingServer.get_video_adapter_name(), "records": records}, "\t"))
	if failures.is_empty():
		print("PROJECTILE_PERF_PASS: completed diagnostics; timings are not FPS assertions")
		quit(0)
	else:
		for failure in failures:
			push_error("PROJECTILE_PERF_FAIL: " + failure)
		quit(1)

func _quick_cases() -> PackedStringArray:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--quick="):
			return argument.trim_prefix("--quick=").split(",")
	return PackedStringArray()

func _make_enemies(stage: Node2D, mode: String) -> Array[ChaserEnemy]:
	var result: Array[ChaserEnemy] = []
	if mode == "empty":
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	for index in ENEMIES:
		var enemy := ChaserEnemy.new()
		enemy.active = true
		enemy.health = 1e12
		enemy.max_health = 1e12
		if mode.begins_with("dense"):
			enemy.position = Vector2(96, 96) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 28.0
		else:
			enemy.position = Vector2(rng.randf_range(-560, 560), rng.randf_range(-280, 280))
		stage.add_child(enemy)
		result.append(enemy)
	return result

func _make_shots(controller: WeaponController, count: int, grid: EnemySpatialGrid, mode: String) -> Array[HomingProjectile]:
	var shots: Array[HomingProjectile] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for index in count:
		var shot := controller._acquire_projectile()
		shot.position = Vector2(96, 96) if mode.begins_with("dense") else Vector2(rng.randf_range(-550, 550), rng.randf_range(-270, 270))
		shot.setup(Vector2.from_angle(rng.randf() * TAU), null if grid.bodies.is_empty() else grid.bodies[index % grid.bodies.size()])
		shot.style = "star" if index % 2 == 0 else "ember"
		shot.homing_enabled = mode != "empty"
		shot.damage = 0.0
		shot.lifetime = 1e6
		shot.spawn_lifetime = 1e6
		shot.remaining_hits = 100000000
		shot.spatial_grid = grid
		if mode.ends_with("singlehit"):
			shot.set_meta("singlehit", true)
		shot.set_physics_process(false)
		shots.append(shot)
	return shots

func _begin_tick() -> void:
	if has_budget:
		projectile_script.call("reset_retarget_budget", -2)

func _reset(shots: Array[HomingProjectile], origins: PackedVector2Array, retarget: bool) -> void:
	for index in shots.size():
		if not shots[index].active:
			var controller := shots[index].get_parent() as WeaponController
			controller._acquire_projectile()
		shots[index].active = true
		shots[index].remaining_hits = 1 if shots[index].has_meta("singlehit") else 100000000
		shots[index].ground_position = origins[index]
		shots[index].hit_enemy_ids.clear()
		if retarget:
			shots[index].target = null
			if "retarget_wait" in shots[index]:
				shots[index].set("retarget_wait", 0)

func _case(mode: String, count: int, cell_size := -1.0, sample_override := -1) -> Dictionary:
	var stage := Node2D.new()
	root.add_child(stage)
	var crowd := _make_enemies(stage, mode)
	var grid := EnemySpatialGrid.new()
	if cell_size > 0.0:
		grid.set("projectile_cell_size", cell_size)
	grid.rebuild(crowd)
	var controller := WeaponController.new()
	stage.add_child(controller)
	var shots := _make_shots(controller, count, grid, mode)
	var origins := PackedVector2Array()
	for shot in shots:
		origins.append(shot.ground_position)
	var times: Array[float] = []
	var dense := mode.begins_with("dense")
	var sample_frames := DENSE_FRAMES if dense else FRAMES
	var warmup_frames := DENSE_WARMUP if dense else WARMUP
	if sample_override > 0:
		sample_frames = sample_override
		warmup_frames = maxi(2, sample_override / 10)
	for frame in warmup_frames + sample_frames:
		_reset(shots, origins, mode.ends_with("retarget"))
		_begin_tick()
		var started := Time.get_ticks_usec()
		for shot in shots:
			shot._physics_process(DT)
		var milliseconds := (Time.get_ticks_usec() - started) / 1000.0
		if frame >= warmup_frames:
			times.append(milliseconds)
		if frame % 10 == 0:
			await process_frame
	var measured := _measured_grid()
	if cell_size > 0.0:
		measured.set("projectile_cell_size", cell_size)
	measured.rebuild(crowd)
	for shot in shots:
		shot.spatial_grid = measured
	var diagnostic_total := 0
	for frame in 3:
		_reset(shots, origins, mode.ends_with("retarget"))
		_begin_tick()
		var started := Time.get_ticks_usec()
		for shot in shots:
			shot._physics_process(DT)
		diagnostic_total += Time.get_ticks_usec() - started
		await process_frame
	var lookups: int = measured.radius_calls + measured.contact_calls
	if lookups != count * 3 or controller.active_projectiles.size() + controller.projectile_pool.size() != count:
		failures.append("%s/%d lost active shots or collision queries" % [mode, count])
	var expected_searches := mini(count, int(projectile_script.get_script_constant_map().get("RETARGET_BUDGET", count))) if has_budget else count
	if mode.ends_with("retarget") and measured.nearest_calls != expected_searches * 3:
		failures.append("retarget case searched %d times, expected %d" % [measured.nearest_calls, expected_searches * 3])
	var stats := _stats(times)
	stats.merge({"kind": "cpu" if cell_size <= 0.0 else "cell_ab", "mode": mode, "shots": count, "enemies": crowd.size(),
		"cell_size": cell_size if cell_size > 0.0 else (float(grid.get("projectile_cell_size")) if has_fine_grid else 192.0),
		"diagnostic_total_ms": diagnostic_total / 3000.0,
		"radius_ms": measured.radius_usec / 3000.0, "contact_ms": measured.contact_usec / 3000.0,
		"nearest_ms": measured.nearest_usec / 3000.0, "searches_per_tick": measured.nearest_calls / 3.0,
		"candidates_per_shot": float(measured.returned) / maxf(1, lookups)})
	records.append(stats)
	print("PROJECTILE_CPU: " + JSON.stringify(stats))
	stage.queue_free()
	await process_frame
	return stats

## After every target dies at once: the cost of each following tick and how many
## ticks pass before every shot is homing again. Before the retarget budget this
## is always one expensive tick; with it, several bounded ones.
func _recovery_case(count: int) -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var crowd := _make_enemies(stage, "spread")
	var grid := EnemySpatialGrid.new()
	grid.rebuild(crowd)
	var controller := WeaponController.new()
	stage.add_child(controller)
	var shots := _make_shots(controller, count, grid, "spread")
	var origins := PackedVector2Array()
	for shot in shots:
		origins.append(shot.ground_position)
	var tick_times: Array[float] = []
	var recovery_ticks: Array[float] = []
	for trial in 40:
		_reset(shots, origins, true)
		var ticks := 0
		var waiting := count
		while waiting > 0 and ticks < 30:
			for index in shots.size():
				shots[index].ground_position = origins[index]
				shots[index].hit_enemy_ids.clear()
			_begin_tick()
			var started := Time.get_ticks_usec()
			for shot in shots:
				shot._physics_process(DT)
			tick_times.append((Time.get_ticks_usec() - started) / 1000.0)
			ticks += 1
			waiting = 0
			for shot in shots:
				if not is_instance_valid(shot.target):
					waiting += 1
		recovery_ticks.append(float(ticks))
		if waiting > 0:
			failures.append("recovery/%d: %d shots never reacquired" % [count, waiting])
		await process_frame
	var row := _stats(tick_times)
	var ticks_stats := _stats(recovery_ticks)
	row.merge({"kind": "retarget_recovery", "shots": count, "enemies": crowd.size(), "trials": 40,
		"ticks_to_recover_max": ticks_stats["max_ms"], "ticks_to_recover_mean": ticks_stats["mean_ms"],
		"worst_reaction_delay_ms": (float(ticks_stats["max_ms"]) - 1.0) * DT * 1000.0})
	records.append(row)
	print("PROJECTILE_RECOVERY: " + JSON.stringify(row))
	stage.queue_free()
	await process_frame

func _pool_case(count: int) -> void:
	var colds: Array[float] = []
	var releases: Array[float] = []
	var reuses: Array[float] = []
	var clears: Array[float] = []
	for trial in 20:
		var controller := WeaponController.new()
		root.add_child(controller)
		var grid := EnemySpatialGrid.new()
		var started := Time.get_ticks_usec()
		var shots := _make_shots(controller, count, grid, "empty")
		colds.append((Time.get_ticks_usec() - started) / 1000.0)
		await process_frame
		# Released in a shuffled order: a landing volley does not land in the
		# order it was fired, and the front-to-back order was the old best case.
		var order := shots.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.seed = trial
		for index in range(order.size() - 1, 0, -1):
			var swap := rng.randi() % (index + 1)
			var held = order[index]
			order[index] = order[swap]
			order[swap] = held
		started = Time.get_ticks_usec()
		for shot in order:
			shot.release()
		releases.append((Time.get_ticks_usec() - started) / 1000.0)
		# A duplicate release must be a no-op.
		shots[0].release()
		started = Time.get_ticks_usec()
		shots = _make_shots(controller, count, grid, "empty")
		reuses.append((Time.get_ticks_usec() - started) / 1000.0)
		var projectile_children := 0
		for child in controller.get_children():
			if child is HomingProjectile:
				projectile_children += 1
		if projectile_children != count or not controller.projectile_pool.is_empty():
			failures.append("pool reuse allocated extra nodes")
		started = Time.get_ticks_usec()
		controller.clear_transients()
		clears.append((Time.get_ticks_usec() - started) / 1000.0)
		if controller.projectile_pool.size() != count or not controller.active_projectiles.is_empty():
			failures.append("clear_transients lost or duplicated shots")
		controller.queue_free()
		await process_frame
	var row := {"kind": "pool", "shots": count, "trials": 20,
		"cold": _stats(colds), "release": _stats(releases), "reuse": _stats(reuses), "clear_transients": _stats(clears),
		"cold_ms": _mean(colds), "release_ms": _mean(releases), "reuse_ms": _mean(reuses)}
	records.append(row)
	print("PROJECTILE_POOL: " + JSON.stringify(row))

## Projectile cell size A/B on the fine grid. Rebuild cost is part of the price:
## a smaller cell is only worth it if the lookups save more than it adds.
func _cell_size_ab() -> void:
	for cell_size in [192.0, 96.0, 64.0, 48.0, 32.0]:
		for mode in ["spread", "spread_singlehit", "spread_retarget", "dense_singlehit"]:
			for count in [1000, 2000]:
				await _case(mode, count, cell_size, 120 if not mode.begins_with("dense") else 40)
		for crowd_mode in ["spread", "dense"]:
			var stage := Node2D.new()
			root.add_child(stage)
			var crowd := _make_enemies(stage, crowd_mode)
			var grid := EnemySpatialGrid.new()
			grid.set("projectile_cell_size", cell_size)
			var rebuilds: Array[float] = []
			for sample in 240:
				var started := Time.get_ticks_usec()
				grid.rebuild(crowd)
				if sample >= 20:
					rebuilds.append((Time.get_ticks_usec() - started) / 1000.0)
			var row := _stats(rebuilds)
			row.merge({"kind": "cell_ab_rebuild", "cell_size": cell_size, "crowd": crowd_mode, "enemies": crowd.size()})
			records.append(row)
			print("PROJECTILE_CELL_REBUILD: " + JSON.stringify(row))
			stage.queue_free()
			await process_frame

func _render_case(count: int, glow: bool) -> void:
	Moonlight.enabled = glow
	var controller := WeaponController.new()
	root.add_child(controller)
	var shots := _make_shots(controller, count, EnemySpatialGrid.new(), "empty")
	var intervals: Array[float] = []
	var draw_calls: Array[float] = []
	var probe := make_probes(root)
	probe.recording = true
	var previous := Time.get_ticks_usec()
	# No redraw or spatial query work: isolates cached projectile drawing with
	# real moving transforms. Wall intervals include script + engine + rendering,
	# not GPU-only time, and are intentionally uncapped with VSync disabled.
	# 600 measured frames so p99 is not the single worst frame.
	for frame in 600 + 60:
		for index in shots.size():
			var shot := shots[index]
			shot.position.x = -550 + fposmod(float(index * 31) + float(frame) * 2.0, 1100)
			shot.rotation += 0.01
		await process_frame
		var now := Time.get_ticks_usec()
		if frame >= 60:
			intervals.append((now - previous) / 1000.0)
			draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		previous = now
	probe.recording = false
	var row := _stats(intervals)
	var draw_stats := _stats(draw_calls)
	row.merge({"kind": "render", "shots": count, "glow": glow, "draw_calls_mean": _mean(draw_calls),
		"draw_calls_max": draw_stats["max_ms"], "process_cpu": _stats(probe.process_ms)})
	probe.partner.queue_free()
	probe.queue_free()
	records.append(row)
	print("PROJECTILE_RENDER: " + JSON.stringify(row))
	controller.queue_free()
	await process_frame

## Same shots drawn by their own nodes and by the batch, captured and compared.
func _visual_parity() -> void:
	if DisplayServer.get_name() == "headless" or not WeaponController.new().has_method("set_batching"):
		return
	Moonlight.enabled = true
	var captures := {}
	for batched in [false, true]:
		WeaponController.new().call("set_batching", batched)
		var field: FlightField = load("res://scripts/effects/flight_field.gd").new()
		field.set("batched", batched)
		root.add_child(field)
		var controller := WeaponController.new()
		root.add_child(controller)
		controller.flight_field = field
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var colors := [Color("43d9ff"), Color("ff8c42"), Color("b892ff"), Color("8ecae6"), Color("fff275"), Color("ef476f")]
		for index in 30:
			var shot := controller._acquire_projectile()
			shot.position = Vector2(-500 + (index % 10) * 110, -200 + floori(index / 10.0) * 150)
			shot.setup(Vector2.from_angle(rng.randf() * TAU), null)
			shot.style = ["star", "ember", "bolt"][index % 3]
			shot.projectile_color = colors[index % colors.size()]
			shot.radius = 9.0 if index % 4 == 0 else 8.0
			shot.rotation = rng.randf() * TAU
			shot.scale = Vector2.ONE * rng.randf_range(0.8, 1.6)
			shot.modulate.a = rng.randf_range(0.5, 1.0)
			# setup() draws its seed from the global generator; pin it so both
			# captures compare the same shapes.
			shot.shape_seed = rng.randf() * TAU
			if index % 3 != 2:
				controller._give_projectile_height(shot, "homing" if index % 3 == 0 else "flame")
			shot.set_physics_process(false)
			shot.queue_redraw()
		for frame in 8:
			field.step(0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		captures[batched] = image
		image.save_png("res://tests/tmp/projectile_parity_%s.png" % ("batched" if batched else "nodes"))
		controller.queue_free()
		field.queue_free()
		await process_frame
	WeaponController.new().call("set_batching", true)
	var nodes: Image = captures[false]
	var batch: Image = captures[true]
	var total := 0.0
	var worst := 0.0
	var differing := 0
	var covered := 0
	for y in range(0, nodes.get_height(), 2):
		for x in range(0, nodes.get_width(), 2):
			var a := nodes.get_pixel(x, y)
			var b := batch.get_pixel(x, y)
			var delta := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			if a.v > 0.02 or b.v > 0.02:
				covered += 1
				total += delta
				worst = maxf(worst, delta)
				if delta > 0.1:
					differing += 1
	var row := {"kind": "visual_parity", "covered_pixels": covered, "mean_abs_diff": total / maxf(1, covered),
		"max_abs_diff": worst, "pixels_over_10pct": differing, "share_over_10pct": float(differing) / maxf(1, covered)}
	records.append(row)
	print("PROJECTILE_PARITY: " + JSON.stringify(row))

func _game_render_case(count: int, batched: bool) -> void:
	var can_toggle := WeaponController.new().has_method("set_batching")
	if can_toggle:
		WeaponController.new().call("set_batching", batched)
	Moonlight.enabled = true
	root.canvas_transform = Transform2D.IDENTITY
	seed(20260915)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	for player in main.players:
		player.max_health = 1e12
		player.health = 1e12
	main.elapsed = 900.0
	main.progression.required_experience = 1 << 30
	main.wave_director.enemy_cap = 620
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	for enemy in main.enemies:
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	for index in 620:
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy("chaser", 14.0, center, false, false)
		enemy.position = center + Vector2(randf_range(-900, 900), randf_range(-500, 500))
		enemy.max_health = 1e12
		enemy.health = 1e12
		main._register_enemy(enemy)
	var empty := EnemySpatialGrid.new()
	var shots: Array[HomingProjectile] = []
	for index in count:
		var shot: HomingProjectile = main.weapon_controller._acquire_projectile()
		shot.global_position = center + Vector2(randf_range(-520, 520), randf_range(-280, 280))
		shot.setup(Vector2.from_angle(randf() * TAU), null)
		shot.style = "star" if index % 2 == 0 else "ember"
		shot.projectile_color = Color("43d9ff") if index % 2 == 0 else Color("ff8c42")
		shot.homing_enabled = false
		shot.speed = 90.0
		shot.lifetime = 1e6
		shot.spawn_lifetime = 1e6
		shot.remaining_hits = 100000000
		shot.spatial_grid = empty
		main.weapon_controller._give_projectile_height(shot, "homing" if index % 2 == 0 else "flame")
		shots.append(shot)
	var intervals: Array[float] = []
	var draw_calls: Array[float] = []
	var probe := make_probes(root)
	var paused_frames := 0
	var previous := Time.get_ticks_usec()
	for frame in 600 + 60:
		for shot in shots:
			if shot.ground_position.distance_squared_to(center) > 560.0 * 560.0:
				shot.ground_position = center + Vector2(randf_range(-400, 400), randf_range(-220, 220))
		await process_frame
		var now := Time.get_ticks_usec()
		probe.recording = frame >= 59
		if frame >= 60 and get_root().get_tree().paused:
			paused_frames += 1
		if frame >= 60:
			intervals.append((now - previous) / 1000.0)
			draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		previous = now
	probe.recording = false
	if count > 0:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/tmp/projectile_game_%d_%s.png" % [count, "batched" if (batched and can_toggle) else ("nodes" if can_toggle else "before")])
	var row := _stats(intervals)
	if paused_frames > 0:
		failures.append("game render %d paused for %d frames" % [count, paused_frames])
	row.merge({"kind": "game_render", "shots": count, "batched": batched and can_toggle, "enemies": main.enemies.size(),
		"paused_frames": paused_frames, "resolution": str(root.size),
		"draw_calls_mean": _mean(draw_calls), "draw_calls_max": _stats(draw_calls)["max_ms"],
		"process_cpu": _stats(probe.process_ms), "physics_cpu": _stats(probe.physics_ms)})
	probe.partner.queue_free()
	probe.queue_free()
	records.append(row)
	print("PROJECTILE_GAME_RENDER: " + JSON.stringify(row))
	main.queue_free()
	await process_frame
	await process_frame
	if can_toggle:
		WeaponController.new().call("set_batching", true)


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(1, values.size())

func _stats(values: Array[float]) -> Dictionary:
	var average := _mean(values)
	values.sort()
	return {"mean_ms": average, "p50_ms": values[int((values.size() - 1) * 0.5)],
		"p99_ms": values[int((values.size() - 1) * 0.99)], "max_ms": values.back(), "frames": values.size()}
