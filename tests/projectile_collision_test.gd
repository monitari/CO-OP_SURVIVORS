extends SceneTree

## Correctness guard for the projectile fast paths. Every optimised lookup is
## compared against a brute-force answer on randomised crowds, and the gameplay
## rules the old code had — one hit per body per shot, single-hit shots stop at
## their first contact, nearest-target homing — are checked through the real
## projectile, not only through the grid.
const Harness := preload("res://tests/test_harness.gd")
const ProjectileScript := preload("res://scripts/entities/projectile.gd")

var failures: Array[String] = []
var stage: Node2D


func _initialize() -> void:
	Harness.arm_watchdog(self, "PROJECTILE_COLLISION_FAIL", 120.0)
	call_deferred("_run")


func _run() -> void:
	stage = Node2D.new()
	root.add_child(stage)
	_test_contacts_match_brute_force()
	_test_nearest_matches_brute_force()
	await _test_big_enemy_edge()
	await _test_fast_shot_does_not_tunnel()
	await _test_pierce_history()
	await _test_single_hit_in_pile()
	await _test_retarget_budget_delay()
	await _test_pool_integrity()
	await _test_renderer_order()
	ProjectileScript.reset_retarget_budget(-1)
	if failures.is_empty():
		print("PROJECTILE_COLLISION_PASS: contacts/nearest match brute force, no edge or tunnelling misses, pierce history, retarget delay, pool, batch order")
		quit(0)
	else:
		for failure in failures:
			push_error("PROJECTILE_COLLISION_FAIL: " + failure)
		quit(1)


func _enemy(at: Vector2, body_radius: float) -> ChaserEnemy:
	var enemy := ChaserEnemy.new()
	enemy.active = true
	enemy.health = 1e12
	enemy.max_health = 1e12
	enemy.radius = body_radius
	enemy.position = at
	stage.add_child(enemy)
	return enemy


func _clear_stage() -> void:
	for child in stage.get_children():
		child.queue_free()
	await process_frame


static func _segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * t)


func _test_contacts_match_brute_force() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for trial in 6:
		var crowd: Array[ChaserEnemy] = []
		for index in 300:
			var body_radius := rng.randf_range(6.0, 30.0) if rng.randf() < 0.9 else rng.randf_range(60.0, 120.0)
			crowd.append(_enemy(Vector2(rng.randf_range(-700, 700), rng.randf_range(-400, 400)), body_radius))
		var grid := EnemySpatialGrid.new()
		grid.projectile_cell_size = [48.0, 32.0, 96.0, 192.0, 64.0, 48.0][trial]
		grid.rebuild(crowd)
		# Bodies drift after the rebuild, the way separate() moves them: node and
		# flat array together, without rebucketing.
		for index in grid.bodies.size():
			var nudge := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, EnemySpatialGrid.DRIFT_MARGIN * 0.95)
			grid.positions[index] += nudge
			grid.bodies[index].position = grid.positions[index]
		crowd[3].dead = true
		var out: Array[ChaserEnemy] = []
		for sample in 400:
			var from := Vector2(rng.randf_range(-750, 750), rng.randf_range(-450, 450))
			var to := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 220.0)
			var shot_radius := 8.0 if sample % 2 == 0 else 9.0
			var exclude := {}
			var expected: Dictionary = {}
			for enemy in crowd:
				if enemy.dead:
					continue
				if rng.randf() < 0.1:
					exclude[enemy.get_instance_id()] = true
					continue
				if _segment_distance(enemy.position, from, to) <= shot_radius + enemy.radius:
					expected[enemy] = true
			grid.projectile_contacts(from, to, shot_radius, 1000000, exclude, out)
			var got: Dictionary = {}
			for enemy in out:
				got[enemy] = true
			if got.size() != out.size() or got.size() != expected.size():
				failures.append("contacts trial %d sample %d: %d found, %d expected" % [trial, sample, got.size(), expected.size()])
				return
			for enemy in expected:
				if not got.has(enemy):
					failures.append("contacts missed a touching body (trial %d)" % trial)
					return
			grid.projectile_contacts(from, to, shot_radius, 1, exclude, out)
			if out.size() != mini(1, expected.size()) or (out.size() == 1 and not expected.has(out[0])):
				failures.append("single-hit contact wrong (trial %d sample %d)" % [trial, sample])
				return
		for enemy in crowd:
			enemy.free()


func _test_nearest_matches_brute_force() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for trial in 4:
		var crowd: Array[ChaserEnemy] = []
		var spread: float = [1100.0, 300.0, 60.0, 2400.0][trial]
		for index in 620:
			crowd.append(_enemy(Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.5, spread * 0.5)), rng.randf_range(8.0, 40.0)))
		var grid := EnemySpatialGrid.new()
		grid.rebuild(crowd)
		for index in grid.bodies.size():
			grid.positions[index] += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, EnemySpatialGrid.DRIFT_MARGIN * 0.95)
			grid.bodies[index].position = grid.positions[index]
		for sample in 500:
			var origin := Vector2(rng.randf_range(-spread * 1.6, spread * 1.6), rng.randf_range(-spread, spread))
			var reach: float = [900.0, 210.0, 700.0][sample % 3]
			var excluded: Array[ChaserEnemy] = []
			if sample % 5 == 0:
				for pick in 3:
					excluded.append(crowd[rng.randi() % crowd.size()])
			var best_distance := reach * reach
			var best: ChaserEnemy = null
			for enemy in crowd:
				if enemy in excluded:
					continue
				var distance := enemy.position.distance_squared_to(origin)
				if distance < best_distance:
					best_distance = distance
					best = enemy
			var found := grid.nearest(origin, reach, excluded)
			if (found == null) != (best == null) or (found != null and not is_equal_approx(found.position.distance_squared_to(origin), best_distance)):
				failures.append("nearest differs from brute force (trial %d sample %d)" % [trial, sample])
				return
		for enemy in crowd:
			enemy.free()


func _shot(controller: WeaponController, at: Vector2, heading: Vector2, grid: EnemySpatialGrid) -> HomingProjectile:
	var shot := controller._acquire_projectile()
	shot.position = at
	shot.setup(heading, null)
	shot.homing_enabled = false
	shot.spatial_grid = grid
	shot.set_physics_process(false)
	return shot


func _test_big_enemy_edge() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	var boss := _enemy(Vector2(95.0, 0.0), 90.0)
	var grid := EnemySpatialGrid.new()
	grid.rebuild([boss] as Array[ChaserEnemy])
	# 95px from the centre of a 90px body: inside it, but 55px beyond the old
	# fixed radius + 32 lookup, which is where large bodies used to be missed.
	var shot := _shot(controller, Vector2.ZERO, Vector2.UP, grid)
	shot.speed = 0.0
	shot._physics_process(1.0 / 60.0)
	_check(boss.health < boss.max_health, "a shot inside a large body's radius hits it")


func _test_fast_shot_does_not_tunnel() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	var small := _enemy(Vector2(40.0, 0.0), 10.0)
	var grid := EnemySpatialGrid.new()
	grid.rebuild([small] as Array[ChaserEnemy])
	var shot := _shot(controller, Vector2.ZERO, Vector2.RIGHT, grid)
	shot.speed = 5000.0 # 83px in one 60Hz tick: straight through an 18px-wide target
	shot._physics_process(1.0 / 60.0)
	_check(small.health < small.max_health, "a shot faster than a body is wide still hits it")
	_check(not shot.active, "and a single-hit shot is spent on it")


func _test_pierce_history() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	var line: Array[ChaserEnemy] = []
	for index in 5:
		line.append(_enemy(Vector2(30.0 + index * 22.0, 0.0), 12.0))
	var grid := EnemySpatialGrid.new()
	grid.rebuild(line)
	var shot := _shot(controller, Vector2.ZERO, Vector2.RIGHT, grid)
	shot.remaining_hits = 3
	shot.damage = 1.0
	shot.speed = 60.0
	for tick in 240:
		if not shot.active:
			break
		shot._physics_process(1.0 / 60.0)
	var damaged := 0
	for enemy in line:
		var lost := enemy.max_health - enemy.health
		_check(lost == 0.0 or is_equal_approx(lost, 1.0), "a piercing shot hits each body at most once")
		if lost > 0.0:
			damaged += 1
	_check(damaged == 3 and not shot.active, "a shot with three pierces hits exactly three bodies (%d)" % damaged)

	var slow := _shot(controller, Vector2.ZERO, Vector2.RIGHT, grid)
	slow.remaining_hits = 100
	slow.damage = 1.0
	slow.speed = 0.5
	slow.ground_position = Vector2(41.0, 0.0)
	for tick in 60:
		slow._physics_process(1.0 / 60.0)
	_check(slow.hit_enemy_ids.size() == 2, "a shot parked on two bodies keeps hitting neither again (%d)" % slow.hit_enemy_ids.size())


func _test_single_hit_in_pile() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	var pile: Array[ChaserEnemy] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for index in 620:
		pile.append(_enemy(Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 28.0, 14.0))
	var grid := EnemySpatialGrid.new()
	grid.rebuild(pile)
	var impacts := [0]
	var shot := _shot(controller, Vector2.ZERO, Vector2.RIGHT, grid)
	shot.damage = 1.0
	shot.on_impact = func(_at: Vector2) -> void: impacts[0] += 1
	shot._physics_process(1.0 / 60.0)
	var damaged := 0
	for enemy in pile:
		if enemy.health < enemy.max_health:
			damaged += 1
	_check(damaged == 1 and impacts[0] == 1 and not shot.active, "a single-hit shot in a 620-body pile hits one body and lands once (%d)" % damaged)


func _test_retarget_budget_delay() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	var crowd: Array[ChaserEnemy] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for index in 620:
		crowd.append(_enemy(Vector2(rng.randf_range(-560, 560), rng.randf_range(-280, 280)), 14.0))
	var grid := EnemySpatialGrid.new()
	grid.rebuild(crowd)
	var shots: Array[HomingProjectile] = []
	for index in 2000:
		var shot := _shot(controller, Vector2(rng.randf_range(-550, 550), rng.randf_range(-270, 270)), Vector2.RIGHT, grid)
		shot.homing_enabled = true
		shot.lifetime = 1e6
		shot.remaining_hits = 100000000
		shot.damage = 0.0
		shots.append(shot)
	var ticks := 0
	var waiting := shots.size()
	while waiting > 0 and ticks < 20:
		ProjectileScript.reset_retarget_budget(-2)
		for shot in shots:
			shot._physics_process(1.0 / 60.0)
		ticks += 1
		waiting = 0
		for shot in shots:
			if not is_instance_valid(shot.target):
				waiting += 1
	var bound := ceili(float(shots.size()) / float(ProjectileScript.RETARGET_BUDGET))
	_check(waiting == 0 and ticks <= bound, "2,000 orphaned shots all reacquire within %d ticks (took %d)" % [bound, ticks])
	# The rule is unchanged: each reacquired target is the nearest body.
	var wrong := 0
	for shot in shots.slice(0, 200):
		var best := INF
		for enemy in crowd:
			best = minf(best, enemy.position.distance_squared_to(shot.ground_position))
		# Positions moved one tick after acquiring; allow that step.
		if shot.target.position.distance_to(shot.ground_position) > sqrt(best) + shot.speed / 60.0 * float(ticks) * 2.0 + 0.5:
			wrong += 1
	_check(wrong == 0, "reacquired targets are the nearest bodies (%d wrong)" % wrong)
	ProjectileScript.reset_retarget_budget(-1)


func _test_pool_integrity() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	var grid := EnemySpatialGrid.new()
	var shots: Array[HomingProjectile] = []
	for index in 500:
		shots.append(_shot(controller, Vector2.ZERO, Vector2.RIGHT, grid))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for round_index in 6:
		shots.shuffle()
		# Release half, some twice, while walking a copy of the active list.
		for shot in controller.active_projectiles.duplicate():
			if rng.randf() < 0.5:
				shot.release()
				if rng.randf() < 0.3:
					shot.release()
		for index in rng.randi_range(50, 300):
			var shot := controller._acquire_projectile()
			shot.setup(Vector2.RIGHT, null)
			shot.set_physics_process(false)
	var pooled: Dictionary = {}
	for shot in controller.projectile_pool:
		_check(not pooled.has(shot), "the pool holds no duplicates")
		pooled[shot] = true
		_check(not shot.active and shot.in_pool, "pooled shots are inactive and flagged")
	for index in controller.active_projectiles.size():
		var shot := controller.active_projectiles[index]
		_check(shot.active_index == index and not pooled.has(shot), "active index is exact and never overlaps the pool")
	_check(controller.active_projectiles.size() + controller.projectile_pool.size() == controller.all_projectiles.size(),
		"every shot is either active or pooled")
	controller.clear_transients()
	_check(controller.active_projectiles.is_empty() and controller.projectile_pool.size() == controller.all_projectiles.size(),
		"clear_transients returns every shot exactly once")


func _test_renderer_order() -> void:
	await _clear_stage()
	var controller := WeaponController.new()
	stage.add_child(controller)
	await process_frame
	var renderer = controller.projectile_renderer
	_check(renderer != null, "the controller batches its shots")
	if renderer == null:
		return
	var grid := EnemySpatialGrid.new()
	var shots: Array[HomingProjectile] = []
	for index in 40:
		var shot := _shot(controller, Vector2(index * 10.0, 0.0), Vector2.RIGHT, grid)
		shot.style = ["star", "ember", "bolt"][index % 3]
		shots.append(shot)
	for index in [3, 17, 25]:
		shots[index].release()
	# Reacquiring puts pooled shots back at the end of the active list; the batch
	# must still draw them in creation order.
	for index in 3:
		var shot := controller._acquire_projectile()
		shot.setup(Vector2.RIGHT, null)
		shot.set_physics_process(false)
	renderer.refresh()
	_check(renderer.drawn_shots == controller.active_projectiles.size(), "one body instance per live shot")
	var buffer: PackedFloat32Array = RenderingServer.multimesh_get_buffer(renderer._body.multimesh.get_rid())
	var expected_x: Array[float] = []
	for shot in controller.all_projectiles:
		if shot.active and shot.visible:
			expected_x.append(shot.position.x)
	var drawn: int = renderer.drawn_shots
	var in_order := true
	var centre_x: float = (renderer.LEFT + renderer.RIGHT) * 0.5
	var width: float = renderer.cell_width()
	if buffer.size() >= drawn * 16:
		for index in drawn:
			var origin_x: float = buffer[index * 16 + 3] - buffer[index * 16] / width * centre_x
			if absf(origin_x - expected_x[index]) > 0.01:
				in_order = false
	else:
		print("PROJECTILE_COLLISION: multimesh buffer not readable on this display; order checked by instance count only")
	_check(in_order, "batched shots keep creation (child) order")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
