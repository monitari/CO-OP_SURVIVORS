extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "LOBBY_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "LOBBY_FAIL"):
		return
	if main.get_script() == null:
		push_error("LOBBY_FAIL: main.gd failed to load")
		quit(1)
		return

	_check(main.lobby_active, "starts in lobby")
	_check(main.lobby_overlay.visible, "lobby overlay is visible")
	_check(not main.character_overlay.visible, "character select is hidden behind the lobby")
	_check(main.lobby_p1_label.text.contains("참가 대기"), "empty P1 slot prompts to join")

	main.lobby_input_cooldown = 0.0
	main._join_lobby_slot(0, -1, "키보드 WASD")
	_check(main.lobby_joined[0] and not main.lobby_joined[1], "one keyboard join fills only P1")
	_check(main.lobby_active, "lobby waits for the second survivor")
	_check(main.lobby_p1_label.text.contains("참가 완료"), "joined slot confirms in the UI")

	main._join_lobby_slot(0, -1, "again")
	_check(main.lobby_device_names[0] == "키보드 WASD", "an occupied slot rejects a second join")

	main._join_lobby_with_gamepad(1)
	_check(main.lobby_joined[1] and main.lobby_devices[1] == 1, "gamepad 1 fills P2")
	_check(main.last_input_gamepad[1] and not main.last_input_gamepad[0], "per-slot device hint is recorded")
	_check(not main.lobby_active and not main.lobby_overlay.visible, "both joins close the lobby")
	_check(main.character_select_active and main.character_overlay.visible, "lobby hands off to character select")
	_check(main.lobby_input_cooldown > 0.0, "handoff debounces the shared confirm keys")

	main._begin_lobby()
	_check(main.lobby_active and not main.lobby_joined[0] and not main.lobby_joined[1], "ESC reset clears both slots")
	_check(main.lobby_devices == [-1, -1] and not main.character_overlay.visible, "reset releases devices")

	main.lobby_input_cooldown = 0.0
	main._join_lobby_with_gamepad(0)
	main._join_lobby_with_gamepad(0)
	_check(main.lobby_joined[0] and not main.lobby_joined[1], "the same pad cannot claim both slots")
	main._join_lobby_with_gamepad(5)
	_check(not main.lobby_joined[1], "unmapped pad devices are ignored")
	main._join_lobby_slot(1, -1, "키보드 방향키")

	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await process_frame
	_check(not main.lobby_active and not main.character_select_active, "run starts from a completed lobby")
	_check(not paused, "combat is unpaused after the full front-end flow")

	if failures.is_empty():
		print("LOBBY_FLOW_PASS: join, reset, device claim, handoff to character select")
		quit(0)
	else:
		for failure in failures:
			push_error("LOBBY_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
