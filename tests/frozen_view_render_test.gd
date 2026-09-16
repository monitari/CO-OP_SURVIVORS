extends SceneTree

## Nothing on the roof may stop being drawn because the run is frozen.
##
## The crowd, and every hostile shot, are drawn in batches by CrowdRenderer and
## their own nodes are hidden. The batches are culled against the rectangle the
## renderer was last told was on screen, and that rectangle used to be refreshed
## only from a running physics tick. But the screens that interrupt a fight —
## growth, a chest, the pause menu — freeze the tree and then move the camera:
## they pull in on the pair and lift the view into the strip above the cards. The
## view therefore travelled while the cull rectangle stood still, and the bodies
## that the move brought on screen were hidden nodes nobody was batching.
##
## This drives that exact sequence and checks that everything inside the visible
## world is either drawing itself or in this frame's batch.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FROZEN_VIEW_FAIL", 90.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	# After the scene, not before: main._ready() calls randomize() over any
	# seed set earlier, so this is the line that actually makes the run repeat.
	seed(20260916)
	await process_frame
	if not TestHarness.require_loaded(self, main, "FROZEN_VIEW_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	var centre: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	# A field wide enough that a camera move brings new bodies in from every side.
	for enemy in main.enemies.duplicate():
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	for index in 300:
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy("chaser", 6.0, centre, false, false)
		enemy.position = centre + Vector2(randf_range(-1400.0, 1400.0), randf_range(-900.0, 900.0))
		main._register_enemy(enemy)
	# And a shot from each of thirty of them, so the threat layer is exercised too.
	for index in 30:
		main._on_enemy_ranged_attack(main.enemies[index].position, Vector2.from_angle(randf() * TAU), 4.0)
	for frame in 4:
		await physics_frame
		await process_frame
	_audit(main, "running")

	# The frozen camera push, at a zoom the pair's own spread would produce.
	main.world_camera.zoom = Vector2(0.62, 0.62)
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	_check(paused, "the growth screen freezes the run")
	var pushed := false
	for frame in 40:
		await process_frame
		await physics_frame
		if not main.world_camera.position.is_equal_approx(main.camera_written):
			pushed = true
		_audit(main, "frozen, camera pushing")
	_check(pushed or main.world_camera.zoom.x > 0.62,
		"the growth screen actually moved the camera, so the audit above meant something")

	# And a move no growth push would make, to prove the rule and not the numbers.
	main.world_camera.position += Vector2(900.0, -700.0)
	for frame in 3:
		await process_frame
		await physics_frame
	_audit(main, "frozen, camera teleported")

	if failures.is_empty():
		print("FROZEN_VIEW_PASS: the crowd and its shots stay drawn while the run is frozen and the camera moves")
		quit(0)
	else:
		for failure in failures:
			push_error("FROZEN_VIEW_FAIL: " + failure)
		quit(1)


## Everything inside the visible world must be drawn by somebody this frame:
## either by its own node, or as part of the batch the renderer just built.
func _audit(main: Node, context: String) -> void:
	var view: Rect2 = main._visible_world_rect()
	var missing := 0
	for enemy in main.enemies:
		if not is_instance_valid(enemy) or enemy.dead or not enemy.active:
			continue
		if not view.has_point(enemy.position):
			continue
		if not enemy.visible and not enemy.on_screen:
			missing += 1
	_check(missing == 0, "%s: %d visible enemies drawn by nobody" % [context, missing])
	var shots_missing := 0
	for candidate in main.enemy_shots:
		if not is_instance_valid(candidate):
			continue
		var shot := candidate as EnemyProjectile
		if shot == null or not shot.active or not view.has_point(shot.position):
			continue
		# A batched shot is a hidden node inside the renderer's cull rectangle.
		if not shot.visible and not main.crowd_renderer._built_cull.has_point(shot.position):
			shots_missing += 1
	_check(shots_missing == 0, "%s: %d visible enemy shots drawn by nobody" % [context, shots_missing])


func _check(ok: bool, context: String) -> void:
	if not ok and context not in failures:
		failures.append(context)
