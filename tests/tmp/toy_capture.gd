extends SceneTree
const MainScene := preload("res://scenes/main.tscn")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	# 에코 (boomerang) and 라이라, so the toy carries 에코's tint.
	main.selected_character_indices[0] = 10
	main.selected_character_indices[1] = 0
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	await process_frame
	main.set_physics_process(false)
	main.players[0].position = Vector2(-320.0, 0.0)
	main.players[1].position = Vector2(320.0, 0.0)
	# Four toys frozen at different ages, so the spin and the fade are both visible.
	for index in 4:
		var toy = preload("res://scripts/effects/returning_toy.gd").new()
		toy.anchor = main.players[0]
		toy.grid = main.spatial_grid
		toy.heading = Vector2.RIGHT
		toy.reach = 260.0
		toy.tint = Color(main.selected_characters[0]["color"])
		toy.age = float(index) * 0.34
		toy.z_index = 40
		main.add_child(toy)
		toy.global_position = Vector2(-330.0 + index * 220.0, -20.0)
		toy.scale = Vector2.ONE * 2.4
		toy.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://.godot_runtime/toy-draw.png")
	print("TOY_CAPTURE_PASS")
	quit(0)
