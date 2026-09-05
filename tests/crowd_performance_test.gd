extends SceneTree
const MainScene := preload("res://scenes/main.tscn")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	var crowd: Array[ChaserEnemy] = []
	for index in 620:
		var enemy := ChaserEnemy.new()
		enemy.active = true
		enemy.position = Vector2(index % 25, index / 25) * 2.0
		main.add_child(enemy)
		crowd.append(enemy)
	main.spatial_grid.rebuild(crowd)
	if main.spatial_grid.query_radius(Vector2.ZERO, 250000.0).size() != 620:
		push_error("CROWD_FAIL: huge queries must preserve every target")
		quit(1)
		return
	var baseline_start := Time.get_ticks_usec()
	for first in crowd.size():
		for second in range(first + 1, crowd.size()): main._resolve_overlap(crowd[first], crowd[second])
	var baseline_ms := (Time.get_ticks_usec() - baseline_start) / 1000.0
	var start := Time.get_ticks_usec()
	for iteration in 10: main._separate_crowd()
	var milliseconds := (Time.get_ticks_usec() - start) / 10000.0
	print("CROWD_METRICS: 620 enemies concentrated in one cell, original_pairs_ms=%.2f bounded_ms=%.2f" % [baseline_ms, milliseconds])
	if milliseconds > 40.0:
		push_error("CROWD_FAIL: dense crowd exceeds 40ms budget")
		quit(1)
	else:
		print("CROWD_PASS")
		quit(0)
