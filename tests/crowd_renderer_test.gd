extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "CROWD_RENDERER_FAIL", 90.0)
	call_deferred("_run")


func _run() -> void:
	seed(20260915)
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "CROWD_RENDERER_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await process_frame
	main.set_physics_process(false)

	for enemy in main.enemies:
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	var rest_positions: Array[Vector2] = []
	for index in 180:
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy(
			main.wave_director._pick_archetype(900.0), 14.0, center, index % 12 == 0, false)
		var angle := TAU * float(index) / 180.0
		enemy.position = center + Vector2.from_angle(angle) * randf_range(70.0, 290.0)
		rest_positions.append(enemy.position)
		main._register_enemy(enemy)

	main.crowd_renderer.view_rect = Rect2(center - Vector2(640, 360), Vector2(1280, 720))
	main.crowd_renderer.refresh()
	_check(main.crowd_renderer.drawn_bodies == 180, "every visible enemy is batched once")
	_check(not main.crowd_renderer._atlas.get_image().has_mipmaps(),
		"runtime atlas has no mip levels that can pop while moving")
	var capacity := 0
	for layer in main.crowd_renderer._bands:
		capacity += layer.multimesh.instance_count
		_check(layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"every depth band uses a stable non-mip texture filter")
	_check(capacity <= 180 * 3, "sparse band buffers stay close to their actual use (%d slots)" % capacity)

	# Move every body back and forth across depth-band boundaries. Rebuilding the
	# bands must never produce the one-frame zero count that appears as flicker.
	for frame in 20:
		var offset := CrowdRenderer.BAND * (0.55 if frame % 2 == 0 else -0.55)
		for index in main.enemies.size():
			main.enemies[index].position.y = rest_positions[index].y + offset
		main.crowd_renderer.refresh()
		_check(main.crowd_renderer.drawn_bodies == 180,
			"crossing depth bands keeps every enemy visible on frame %d" % frame)

	if failures.is_empty():
		print("CROWD_RENDERER_PASS: stable atlas, bounded buffers, no band-crossing gaps")
		quit(0)
	else:
		for failure in failures:
			push_error("CROWD_RENDERER_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
