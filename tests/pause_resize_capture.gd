extends SceneTree

## Resizing the window while the fight is frozen must not blank the battlefield.
##
## The world is drawn into an off-screen buffer whose updates are switched off
## while the tree is paused. A resize recreates that buffer empty, so the roof
## behind a pause menu or growth screen used to go black on the first resize.
## Needs a real window (the buffer is never drawn headless), so it runs outside
## the headless suite:
##
##   godot --path . --script res://tests/pause_resize_capture.gd

const MainScene := preload("res://scenes/main.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	for frame in 30:
		await process_frame
	paused = true
	for frame in 5:
		await process_frame
	var before := _brightness(main)
	var failures: Array[String] = []
	for size in [Vector2i(1600, 900), Vector2i(1024, 576), Vector2i(1280, 720)]:
		root.size = size
		for frame in 6:
			await process_frame
		var after := _brightness(main)
		print("paused resize %s: world brightness %.4f (before %.4f)" % [size, after, before])
		if after < before * 0.5:
			failures.append("world went dark after resizing to %s while paused" % size)
	paused = false
	if failures.is_empty():
		print("PAUSE_RESIZE_PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("PAUSE_RESIZE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _brightness(main: Node) -> float:
	var image: Image = main.rooftop_view.surface.get_texture().get_image()
	if image == null or image.is_empty():
		return 0.0
	image.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y).get_luminance()
	return total / float(image.get_width() * image.get_height())
