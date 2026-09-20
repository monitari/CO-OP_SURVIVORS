extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")

class RecordingSession extends NetworkSession:
	var controls: Array[Dictionary] = []

	func send_control(payload: Dictionary) -> void:
		controls.append(payload.duplicate(true))

var failures: Array[String] = []
var main: Node


func _initialize() -> void:
	Harness.arm_watchdog(self, "ONLINE_STATE_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "ONLINE_STATE_FAIL"):
		return
	main.selected_character_indices.assign([0, 1])
	main.character_confirmed.assign([true, true])
	main._start_selected_run()
	main.set_physics_process(false)
	var recording := RecordingSession.new()
	main.online.add_child(recording)
	recording.role = NetworkSession.Role.CLIENT
	main.online.session = recording

	main.character_select_active = true
	main.character_overlay.visible = true
	main.lobby_input_cooldown = 0.0
	main.character_confirmed.assign([false, false])
	main._refresh_character_select_ui()
	_check(main.character_overlay.get_node("CharacterConfirm0").disabled
		and not main.character_overlay.get_node("CharacterConfirm1").disabled,
		"online character controls expose only the local slot")
	main.character_overlay.get_node("CharacterConfirm1").pressed.emit()
	_check(not recording.controls.is_empty()
		and recording.controls.back().get("type") == "character_choice"
		and bool(recording.controls.back().get("confirmed")),
		"client character mouse confirmation is sent to the host")
	main.character_select_active = false
	main.character_overlay.visible = false

	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0.0
	main.selected_upgrade_indices.assign([0, -1])
	main._refresh_level_up_ui()
	_check(not main.level_overlay.has_node("ReturnToFirst"),
		"the immersive hand exposes no separate revision box")
	main.selected_upgrade_indices.assign([-1, -1])
	main._refresh_level_up_ui()
	main._confirm_growth_choice(1, main.upgrade_cursors[1])
	_check(recording.controls.back().get("type") == "growth_select",
		"client growth mouse confirmation is sent to the host")
	main.level_up_active = false
	main.level_overlay.visible = false
	paused = false

	main.pause_active = true
	main.pause_overlay.visible = true
	paused = true
	main.pause_overlay.get_node("PauseAction0").pressed.emit()
	_check(main.pause_active and recording.controls.back().get("type") == "pause_request"
		and not bool(recording.controls.back().get("enabled")),
		"client continue button waits for the host resume state")
	main.online._control(1, {"type": "pause_state", "enabled": false})

	var applied_sequences: Array[float] = []
	recording.snapshot_received.connect(func(payload: Dictionary) -> void:
		applied_sequences.append(float(payload["elapsed"])))
	recording._receive_snapshot_part(20, 0, 1, {"elapsed": 20.0}, [])
	recording._receive_snapshot_part(19, 0, 1, {"elapsed": 19.0}, [])
	_check(applied_sequences == [20.0], "client discards a snapshot older than the applied state")
	recording._receive_snapshot_part(21, 0, 2, {"elapsed": 21.0}, [])
	_check(applied_sequences == [20.0, 21.0],
		"split snapshots apply player and HUD state before all enemy chunks arrive")
	recording._receive_snapshot_part(21, 1, 2, {}, [])
	_check(applied_sequences == [20.0, 21.0, 21.0],
		"the completed split snapshot later supplies the assembled enemy state")
	recording._receive_snapshot_part(30, 0, 2, {'elapsed': 30.0}, [])
	recording._receive_snapshot_part(31, 0, 1, {'elapsed': 31.0}, [])
	_check(applied_sequences.slice(-2) == [30.0, 31.0]
		and not recording.incoming_snapshots.has(30),
		"a lost enemy chunk cannot block a newer complete snapshot")

	main.online._apply_snapshot({
		"chain_max_length": 445.0, "chain_overloaded": true,
		"chain_ward_remaining": 3.0, "guard_remaining": 2.0,
		"frenzy_remaining": 4.0, "time_stop_remaining": 1.5,
		"pending_cores": 1,
	})
	_check(is_equal_approx(main.chain_max_length, 445.0) and main.chain_overloaded
		and is_equal_approx(main.chain_ward_remaining, 3.0)
		and is_equal_approx(main.time_stop_remaining, 1.5)
		and main.resonance_system.pending_cores == 1,
		"client mirrors chain, timed-item and held-core combat state")

	var nearby := ChaserEnemy.new()
	nearby.setup(1.0, "runner")
	nearby.position = Vector2(120, 0)
	main.world_stage.add_child(nearby)
	var distant := ChaserEnemy.new()
	distant.setup(1.0, "runner")
	distant.position = Vector2(OnlineCoop.REPLICATION_RADIUS + 800.0, 0)
	main.world_stage.add_child(distant)
	main.enemies.assign([nearby, distant])
	var interest_snapshot: Dictionary = main.online._snapshot()
	var interest_ids: Array[int] = []
	for state: Array in interest_snapshot["enemies"]:
		interest_ids.append(int(state[OnlineCoop.EnemyField.ID]))
	_check(nearby.get_instance_id() in interest_ids and distant.get_instance_id() not in interest_ids,
		"enemy snapshots keep the local combat area and omit distant non-bosses")
	nearby.queue_free()
	distant.queue_free()
	main.enemies.clear()

	main.online.reconnect_in_progress = true
	main.online.reconnect_as_host = false
	main.online.reconnect_forced_pause = true
	main._set_pause(true, false)
	main.online._receive_run_resume({
		"indices": [0, 1],
		"weapon_loadouts": main.weapon_loadouts.duplicate(true),
		"treasure_loadouts": main.treasure_loadouts.duplicate(true),
		"chain_max_length": 510.0,
		"player_stats": main.online._player_build_states(),
		"active_resonances": [],
		"pending_cores": 2,
		"attack_timers": main.attack_timers.duplicate(true),
		"elapsed": 88.0, "kills": 42,
		"level": 5, "xp": 3, "required_xp": 20,
	})
	_check(not main.online.reconnect_in_progress and not main.pause_active
		and is_equal_approx(main.chain_max_length, 510.0)
		and main.elapsed == 88.0 and main.kills == 42
		and main.resonance_system.pending_cores == 2,
		"mid-run reconnect restores authoritative build and run progress")

	main.online._sync_enemies([[
		7001, Vector2(300, 40), 0.25, "brute", false, true, 2,
		480.0, 600.0, 0.0, true, 0.7, 0.0, 0.0, 0.6,
		Vector2.LEFT, Vector2(20, 30), true,
	]])
	_check(is_instance_valid(main.boss_enemy), "client creates the replicated boss")
	_check(main.boss_bar.visible and is_equal_approx(float(main.boss_bar.ratio), 480.0 / 600.0),
		"client shows the replicated boss health (%.2f of the bar)" % main.boss_bar.ratio)
	_check(String(main.boss_bar.health_text) == "480 / 600",
		"and the replicated numbers (%s)" % main.boss_bar.health_text)
	_check(main.boss_enemy.charge_windup > 0.0 and main.boss_enemy.boss_slam_windup > 0.0,
		"client receives attack telegraph timers")
	_check(main.boss_enemy.telegraph_direction == Vector2.LEFT,
		"client receives attack telegraph direction")

	main.online._event(1, {
		"type": "enemy_shot", "origin": Vector2(120, 80),
		"direction": Vector2.RIGHT, "speed": 310.0,
	})
	await process_frame
	var visual_projectile: EnemyProjectile
	for child in main.rooftop_view.world.get_children():
		if child is EnemyProjectile:
			visual_projectile = child
			break
	_check(is_instance_valid(visual_projectile), "client creates an enemy projectile visual")
	if is_instance_valid(visual_projectile):
		_check(visual_projectile.players.is_empty() and visual_projectile.damage == 0.0,
			"replicated projectile cannot damage client-side players")

	main.online._event(1, {
		"type": "player_attack", "player": 0, "weapon": "probe",
		"origin": Vector2(90, 40), "color": Color("43d9ff"), "radius": 88.0,
	})
	await process_frame
	var has_attack_visual := false
	for child in main.weapon_controller.get_children():
		if child is CombatFlare:
			has_attack_visual = true
			break
	_check(has_attack_visual, "client creates a harmless player attack visual")
	main.online._event(1, {
		"type": "player_attack", "player": 0, "weapon": "lance",
		"origin": Vector2(90, 40), "direction": Vector2.RIGHT,
		"color": Color("caffbf"), "radius": 88.0,
	})
	await process_frame
	var has_remote_trajectory := false
	for child in main.weapon_controller.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("lance_strike.gd"):
			has_remote_trajectory = true
			break
	_check(has_remote_trajectory,
		"remote weapon events preserve a directional beam instead of using one generic flare")

	main.online._sync_items([[
		8001, Vector2(240, 120), "frenzy", 18.0,
	]])
	_check(main.online.replica_items.size() == 1,
		"client creates a replicated field item")
	var replicated_item: FieldItem = main.online.replica_items.get(8001)
	_check(is_instance_valid(replicated_item) and replicated_item.item_id == "frenzy"
		and replicated_item.position == Vector2(240, 120),
		"replicated field item keeps its type and position")
	main.online._sync_items([[
		8001, Vector2(-180, 90), "guard", 22.0,
	]])
	_check(replicated_item.item_id == "guard"
		and replicated_item.position == Vector2(-180, 90),
		"a pooled host item id resets to the new drop type and spawn")
	main.online._sync_items([])
	_check(main.online.replica_items.is_empty(),
		"client removes a field item collected or expired on the host")

	main.online._control(1, {"type": "pause_state", "enabled": true})
	_check(main.pause_active and paused, "host pause state pauses the client")
	main.online._control(1, {"type": "pause_state", "enabled": false})
	_check(not main.pause_active and not paused, "host resume state resumes the client")

	var resonance_choices: Array = main.resonance_system.catalog.slice(0, 2)
	main.online._control(1, {
		"type": "resonance_open", "candidates": resonance_choices,
		"cursors": [0, 1], "votes": [-1, -1], "message": "",
	})
	_check(main.resonance_vote_active and main.resonance_overlay.visible and paused,
		"host resonance state opens and pauses the client vote")
	main._confirm_resonance_vote(1, 1)
	_check(recording.controls.back().get("type") == "resonance_action"
		and recording.controls.back().get("action") == "confirm"
		and int(recording.controls.back().get("index")) == 1,
		"client resonance confirmation is sent to the host")
	main.online._control(1, {
		"type": "resonance_close", "chosen": resonance_choices[1],
		"active": [resonance_choices[1]], "pending_cores": 0,
	})
	_check(not main.resonance_vote_active and not main.resonance_overlay.visible and not paused
		and main.resonance_system.active_resonances.size() == 1,
		"host resonance result closes the client vote and installs the chosen state")

	var remote_stats: Dictionary = main.run_stats.duplicate(true)
	remote_stats["bosses"] = WaveDirector.BOSS_COUNT
	remote_stats["revives"] = 2
	var points_before: int = int(main.meta_progression.points)
	main.online._control(1, {
		"type": "run_result", "victory": true, "elapsed": 321.5,
		"kills": 456, "run_stats": remote_stats, "reward_eligible": true,
		"debug_tainted": false,
	})
	_check(main.game_over and main.result_overlay.visible, "host result opens the client result screen")
	_check(main.kills == 456 and int(main.run_stats["revives"]) == 2,
		"client result uses the host's final run statistics")
	_check(main.run_reward == MetaProgression.CLEAR_REWARD
		and main.meta_progression.points == points_before + MetaProgression.CLEAR_REWARD,
		"an eligible host result awards the client's own profile exactly once")
	main._retry_same_pair()
	_check(recording.controls.back().get("type") == "result_action"
		and recording.controls.back().get("action") == "retry",
		"client result retry requests host authority instead of reloading alone")
	main._return_to_main_menu()
	_check(recording.controls.back().get("type") == "result_action"
		and recording.controls.back().get("action") == "menu",
		"client result menu action requests the host transition")

	_check(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep",
		"non-16:9 fullscreen keeps the authored aspect ratio")
	paused = false
	if failures.is_empty():
		print("ONLINE_STATE_PASS: snapshots, combat state, resonance, pause, reward, result actions and display aspect")
		quit(0)
	else:
		for failure in failures:
			push_error("ONLINE_STATE_FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
