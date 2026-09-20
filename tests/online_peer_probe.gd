extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

var mode := ""
var main: Node


func _initialize() -> void:
	Harness.arm_watchdog(self, "ONLINE_%s" % mode.to_upper(), 55.0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--peer-mode="):
			mode = argument.trim_prefix("--peer-mode=")
	call_deferred("_run")


func _run() -> void:
	if mode not in ["host", "client"]:
		push_error("ONLINE_PROBE_FAIL: pass --peer-mode=host or client")
		quit(2)
		return
	change_scene_to_packed(MainScene)
	await scene_changed
	main = current_scene
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
		_fail("host never reached character selection · status=%s peers=%s" % [
			main.online.session.multiplayer.multiplayer_peer.get_connection_status(),
			str(main.online.session.multiplayer.get_peers())])
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
	if not await _wait_until(func() -> bool: return main.online.reconnect_in_progress, 5.0):
		_fail("host did not preserve the run after the client transport dropped")
		return
	if not await _wait_until(func() -> bool: return not main.online.reconnect_in_progress, 12.0):
		_fail("host did not complete the client run restore")
		return
	var boss := main.wave_director._acquire_enemy("brute", 3.0, Vector2(420, 0), false, true, 1) as ChaserEnemy
	boss.charge_windup = 0.75
	boss.telegraph_direction = Vector2.LEFT
	boss.active = false
	main._register_enemy(boss)
	main._on_enemy_ranged_attack(Vector2(240, 0), Vector2.LEFT, 14.0)
	main._on_player_attack_visual(0, "probe", Vector2(120, 40), Color("43d9ff"), 92.0)
	main.field_items.spawn_item(Vector2(520, 260), "frenzy")
	if not await _wait_until(func() -> bool: return main.pause_active, 5.0):
		_fail("host never received the client's pause request")
		return
	if not await _wait_until(func() -> bool: return not main.pause_active, 5.0):
		_fail("host never received the client's resume request")
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
	main.resonance_candidates.assign(main.resonance_system.catalog.slice(0, 2))
	main.resonance_cursors.assign([0, 0])
	main.resonance_votes.assign([0, -1])
	main.resonance_vote_message = ""
	main.resonance_vote_active = true
	main.resonance_overlay.visible = true
	paused = true
	main.online.send_resonance_state("resonance_open")
	if not await _wait_until(_has_active_resonance, 5.0):
		_fail("host never received the client's resonance vote")
		return
	if not await _wait_until(func() -> bool: return not main.cinematic_active, 5.0):
		_fail("host resonance showcase never completed")
		return
	main._end_run(false)
	var first_run := main
	await scene_changed
	main = current_scene
	if main == first_run or not await _wait_until(_run_is_active, 12.0):
		_fail("host did not reopen the room and start the retry run · %s" % _state_text())
		return
	print("ONLINE_HOST_PASS: movement, combat visuals, field items, pause, growth, resonance, result and retry synchronized")
	main.online.stop()
	quit(0)


func _run_client() -> void:
	main.online.join_game("127.0.0.1")
	if not await _wait_until(func() -> bool: return main.character_select_active, 8.0):
		_fail("client never received character selection · status=%s peers=%s" % [
			main.online.session.multiplayer.multiplayer_peer.get_connection_status(),
			str(main.online.session.multiplayer.get_peers())])
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
	# Drop the transport without changing scenes. The host must keep the live
	# run paused, and this client must reconnect to the same address and receive
	# the authoritative build/run state before the probe continues.
	main.online.session.multiplayer.multiplayer_peer.close()
	if not await _wait_until(func() -> bool: return main.online.reconnect_in_progress, 3.0):
		_fail("client did not enter mid-run reconnect after transport loss")
		return
	if not await _wait_until(func() -> bool:
			return main.online.is_client() and not main.online.reconnect_in_progress, 12.0):
		_fail("client did not restore the interrupted run · %s" % _state_text())
		return
	if not await _wait_until(_client_has_boss_telegraph, 5.0):
		_fail("client never received the boss and its telegraph")
		return
	if not await _wait_until(_client_has_enemy_projectile, 5.0):
		_fail("client never received the enemy projectile visual")
		return
	if not await _wait_until(_client_has_player_attack_visual, 2.0):
		_fail("client never received the player attack visual")
		return
	if not await _wait_until(func() -> bool: return main.online.replica_items.size() == 1, 5.0):
		_fail("client never received the field item snapshot")
		return
	var item: FieldItem = main.online.replica_items.values()[0]
	if item.item_id != "frenzy" or item.position.distance_to(Vector2(520, 260)) > 1.0:
		_fail("client field item snapshot had the wrong type or position")
		return
	main.online.request_pause(true)
	if not await _wait_until(func() -> bool: return main.pause_active, 5.0):
		_fail("client never received host pause state")
		return
	main.online.request_pause(false)
	if not await _wait_until(func() -> bool: return not main.pause_active, 5.0):
		_fail("client never received host resume state")
		return
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
	if not await _wait_until(func() -> bool: return main.resonance_vote_active, 5.0):
		_fail("client never received the resonance vote")
		return
	main.online.request_resonance_action("confirm", 0)
	if not await _wait_until(_client_has_chosen_resonance, 5.0):
		_fail("client never received the chosen resonance")
		return
	if not await _wait_until(func() -> bool: return main.game_over and main.result_overlay.visible, 5.0):
		_fail("client never received the result screen")
		return
	var first_run := main
	main._retry_same_pair()
	await scene_changed
	main = current_scene
	if main == first_run or not await _wait_until(_run_is_active, 12.0):
		_fail("client did not reconnect and enter the retry run · %s" % _state_text())
		return
	print("ONLINE_CLIENT_PASS: movement, mid-run reconnect, combat visuals, field items, pause, growth, resonance, result and retry synchronized")
	quit(0)


func _client_has_boss_telegraph() -> bool:
	return (is_instance_valid(main.boss_enemy) and main.boss_bar.visible
		and main.boss_enemy.charge_windup > 0.0)


func _client_has_enemy_projectile() -> bool:
	# World nodes are adopted into the off-screen rooftop viewport after setup;
	# looking only under main made a visible replicated shot appear missing.
	for child in main.rooftop_view.world.get_children():
		if child is EnemyProjectile:
			return true
	return false


func _client_has_player_attack_visual() -> bool:
	for child in main.weapon_controller.get_children():
		if child is CombatFlare:
			return true
	return false


func _has_active_resonance() -> bool:
	return main.resonance_system.active_resonances.size() == 1


func _client_has_chosen_resonance() -> bool:
	return not main.resonance_vote_active and _has_active_resonance()


func _run_is_active() -> bool:
	return (is_instance_valid(main) and not main.title_active and not main.lobby_active
		and not main.character_select_active and not main.game_over)


func _state_text() -> String:
	if not is_instance_valid(main):
		return "main invalid"
	return "role=%s title=%s lobby=%s character=%s over=%s status=%s peers=%s" % [
		main.online.session.role, main.title_active, main.lobby_active,
		main.character_select_active, main.game_over, main.help_label.text,
		str(main.online.session.multiplayer.get_peers()),
	]


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
