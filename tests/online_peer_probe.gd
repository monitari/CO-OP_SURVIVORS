extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

var mode := ""
var main: Node


func _initialize() -> void:
	Harness.arm_watchdog(self, "ONLINE_%s" % mode.to_upper(), 25.0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--peer-mode="):
			mode = argument.trim_prefix("--peer-mode=")
	call_deferred("_run")


func _run() -> void:
	if mode not in ["host", "client"]:
		push_error("ONLINE_PROBE_FAIL: pass --peer-mode=host or client")
		quit(2)
		return
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "ONLINE_%s" % mode.to_upper()):
		return
	main._begin_lobby()
	main.lobby_input_cooldown = 0.0
	if mode == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	main.online.host_game()
	if not await _wait_until(func() -> bool: return main.character_select_active, 8.0):
		_fail("host never reached character selection")
		return
	main.character_confirmed[0] = true
	main._refresh_character_select_ui()
	if not await _wait_until(func() -> bool: return not main.character_select_active and not main.lobby_active, 8.0):
		_fail("host never started the run")
		return
	if main.players[1].input_source != ChainPlayer.InputSource.REMOTE:
		_fail("host did not assign P2 to remote input")
		return
	var start_x: float = main.players[1].position.x
	if not await _wait_until(func() -> bool: return main.players[1].position.x > start_x + 20.0, 5.0):
		_fail("host did not apply the remote P2 movement command")
		return
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	if not main.level_up_active:
		_fail("host could not open the growth choice")
		return
	main._select_upgrade(1, 0)
	if not await _wait_until(func() -> bool: return not main.level_up_active, 6.0):
		_fail("host never completed the shared growth choice")
		return
	print("ONLINE_HOST_PASS: peer joined, character state agreed, run started, remote input moved P2, growth closed")
	main.online.stop()
	quit(0)


func _run_client() -> void:
	main.online.join_game("127.0.0.1")
	if not await _wait_until(func() -> bool: return main.character_select_active, 8.0):
		_fail("client never received character selection")
		return
	main.online.session.send_control({
		"type": "character_choice",
		"index": main.selected_character_indices[1],
		"confirmed": true,
	})
	if not await _wait_until(func() -> bool: return not main.character_select_active and not main.lobby_active, 8.0):
		_fail("client never received run start")
		return
	Input.action_press("p1_right")
	var end_at := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < end_at:
		await physics_frame
	Input.action_release("p1_right")
	if not await _wait_until(func() -> bool: return main.level_up_active, 5.0):
		_fail("client never received the growth choice")
		return
	main.online.session.send_control({"type": "growth_select", "index": 0})
	if not await _wait_until(func() -> bool: return not main.level_up_active, 5.0):
		_fail("client never received growth close")
		return
	await create_timer(0.4).timeout
	if main.level_up_active:
		_fail("client growth screen reopened after close")
		return
	print("ONLINE_CLIENT_PASS: connected, selected P2, received run, streamed input, growth closed")
	quit(0)


func _wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _fail(message: String) -> void:
	push_error("ONLINE_%s_FAIL: %s" % [mode.to_upper(), message])
	quit(1)
