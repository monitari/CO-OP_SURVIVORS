extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "MOUSE_ALIGNMENT_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "MOUSE_ALIGNMENT_FAIL"):
		return
	var hit := main.title_overlay.get_node("TitleHit0") as Button
	var logical_center := hit.get_global_rect().get_center()
	# Convert the authored 1280x720 canvas point to the actual window point in
	# exactly the same way rendering does. Feeding that visible centre through
	# Input must land on the same control at the default 1920x1080 scale.
	var screen_center := root.get_final_transform() * logical_center
	var press := InputEventMouseButton.new()
	press.position = screen_center
	press.global_position = screen_center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	_check(main.title_mode == "modes", "visual button centre activates the title button")
	var release := InputEventMouseButton.new()
	release.position = screen_center
	release.global_position = screen_center
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	_check(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep",
		"window and pointer use the same aspect-preserving transform")
	if failures.is_empty():
		print("MOUSE_ALIGNMENT_PASS: rendered centre and input target agree")
		quit(0)
	else:
		for failure in failures:
			push_error("MOUSE_ALIGNMENT_FAIL: " + failure)
		quit(1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
