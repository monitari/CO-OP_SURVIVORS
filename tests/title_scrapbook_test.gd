extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "TITLE_SCRAPBOOK_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "TITLE_SCRAPBOOK_FAIL"):
		return
	var ambience: Node = main.title_overlay.get_node("TitleAmbience")
	_check(ambience.has_node("SceneBackdrop"), "scrapbook rooftop background is a separate layer")
	_check((ambience.get_node("SceneBackdrop") as TextureRect).texture.get_width() == 1920,
		"background is authored at the default window width")
	var brand := main.title_overlay.get_node("BrandLockup") as TextureRect
	_check(brand != null and String(brand.texture.resource_path).ends_with("moonroof_title_scrapbook_v4.png"),
		"title uses the new image-authored scrapbook logo")
	var collage: Control = main.title_overlay.get_node("SnapshotCollage") as Control
	_check(collage.get_child_count() == 4, "the title carries four independent snapshots")
	for photo in collage.get_children():
		var subject: TextureRect = photo.get_node("Subject")
		_check(subject.texture.get_width() == subject.texture.get_height(),
			"%s uses square photo art" % photo.name)
		_check(is_equal_approx(photo.size.x, photo.size.y), "%s has a square print" % photo.name)
		_check(photo.get_node("Caption").text == "" and not photo.get_node("Caption").visible,
			"%s has no caption" % photo.name)
	_check(not is_equal_approx((collage.get_child(0) as Control).size.x,
		(collage.get_child(1) as Control).size.x), "snapshots vary in size")
	_check((collage.get_child(0) as Control).get_rect().intersects(
		(collage.get_child(1) as Control).get_rect()), "top snapshots overlap naturally")
	_check((collage.get_child(2) as Control).get_rect().intersects(
		(collage.get_child(3) as Control).get_rect()), "bottom snapshots overlap naturally")
	_check(not main.title_note.visible, "no description line under the menu")
	_check(main.title_rows[0].position.x < 100.0 and main.title_rows[4].position.y > 480.0,
		"menu is a left-hand vertical paper stack")
	var gaps: Array[float] = []
	for index in 4:
		gaps.append(main.title_rows[index + 1].position.y
			- (main.title_rows[index].position.y + main.title_rows[index].size.y))
	_check(gaps.all(func(gap: float) -> bool: return is_equal_approx(gap, gaps[0])),
		"menu cards share one gap")
	_check(absf(main.title_rows[1].rotation) > 0.01, "menu cards are visibly laid at an angle")
	main.title_mode = "modes"
	main._refresh_title_ui()
	_check(is_zero_approx(main.title_rows[0].rotation),
		"utility pages reset the scrapbook card tilt")
	main.title_mode = "menu"
	main._refresh_title_ui()
	var hit := main.title_overlay.get_node("TitleHit0") as Button
	var stable_before := hit.position
	main.title_cursor = 1
	main._refresh_title_ui()
	var stable_after := hit.position
	_check(stable_before == stable_after,
		"hover selection never moves the mouse hit area")
	_check(hit.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS,
		"menu buttons activate on the first mouse press")
	await process_frame
	await process_frame
	# The dummy headless renderer intentionally has no backing texture. A normal
	# display run also leaves a review image without making logic CI depend on it.
	if DisplayServer.get_name() != "headless":
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			failures.append("viewport capture is available")
		elif image.save_png("res://.godot_runtime/title-scrapbook.png") != OK:
			failures.append("title screenshot saves")
	if failures.is_empty():
		print("TITLE_SCRAPBOOK_PASS: scrapbook backdrop, image logo, four loose square photos, stable mouse targets")
		quit(0)
	else:
		for failure in failures:
			push_error("TITLE_SCRAPBOOK_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
