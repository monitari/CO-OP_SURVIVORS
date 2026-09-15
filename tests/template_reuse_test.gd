extends SceneTree

const InputBindings := preload("res://scripts/templates/input_bindings.gd")
const RunStatsTemplate := preload("res://scripts/templates/run_stats_template.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_run_stats_are_fresh()
	_test_input_install_is_complete_and_idempotent()
	if failures.is_empty():
		print("TEMPLATE_REUSE_TEST_PASS: fresh run data and reusable input bindings")
		quit(0)
	else:
		for failure in failures:
			push_error("TEMPLATE_REUSE_TEST_FAIL: " + failure)
		quit(1)


func _test_run_stats_are_fresh() -> void:
	var first := RunStatsTemplate.create()
	var second := RunStatsTemplate.create()
	first["xp_by_player"][0] = 99
	first["items_by_type"]["heal"] = 3
	first["weapon_damage"][0]["homing"] = 42.0
	_check(second["xp_by_player"] == [0, 0], "player XP does not leak between runs")
	_check(second["items_by_type"].is_empty(), "item counts do not leak between runs")
	_check(second["weapon_damage"][0].is_empty(), "nested damage data is deeply duplicated")


func _test_input_install_is_complete_and_idempotent() -> void:
	InputBindings.install()
	var event_count := InputMap.action_get_events("menu_previous").size()
	InputBindings.install()
	_check(InputMap.has_action("p1_dash") and InputMap.has_action("p2_dash"),
		"both player dash actions are installed")
	_check(event_count == InputMap.action_get_events("menu_previous").size(),
		"installing the template twice does not duplicate events")
	_check(_has_key("menu_previous", KEY_W), "menu bindings preserve alternate keyboard keys")
	_check(_has_button("pause", 1, JOY_BUTTON_START), "shared pad bindings reach player two")
	_check(_has_axis("p2_dash", 1, JOY_AXIS_TRIGGER_RIGHT, 1.0),
		"player-specific trigger bindings are preserved")


func _has_key(action: StringName, keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _has_button(action: StringName, device: int, button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.device == device and event.button_index == button:
			return true
	return false


func _has_axis(action: StringName, device: int, axis: int, value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.device == device \
			and event.axis == axis and is_equal_approx(event.axis_value, value):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
