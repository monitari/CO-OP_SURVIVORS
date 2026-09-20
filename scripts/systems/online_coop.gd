class_name OnlineCoop
extends Node

const SessionScript := preload("res://scripts/systems/network_session.gd")
const L := preload("res://scripts/systems/loc.gd")
const FieldItemScript := preload("res://scripts/entities/field_item.gd")
const WaveDirectorScript := preload("res://scripts/systems/wave_director.gd")
const RECONNECT_GRACE_SECONDS := 15.0
const RECONNECT_RETRY_SECONDS := 0.75
const REPLICATION_RADIUS := 1700.0

# Positional wire schema. Repeating eighteen Dictionary keys for every enemy was
# larger than the actual values and pushed tiny ENet chunks over the MTU.
enum EnemyField {
	ID, POSITION, ROTATION, ARCHETYPE, ELITE, BOSS, RANK, HEALTH, MAX_HEALTH,
	SLOW_TIMER, TELEGRAPHING, CHARGE_WINDUP, SHOOTER_WINDUP, CHAIN_WINDUP,
	BOSS_SLAM_WINDUP, TELEGRAPH_DIRECTION, BOSS_SLAM_POINT, BOSS_ENRAGED,
}

var game: Node
var session: NetworkSession
var snapshot_timer := 0.0
var last_remote_input_msec := 0
var replica_enemies: Dictionary = {}
var replica_items: Dictionary = {}
var reconnect_in_progress := false
var reconnect_as_host := false
var reconnect_remaining := 0.0
var reconnect_retry_timer := 0.0
var reconnect_forced_pause := false


func configure(main: Node) -> void:
	game = main
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = SessionScript.new() as NetworkSession
	session.name = "NetworkSession"
	add_child(session)
	session.status_changed.connect(_status)
	session.peer_joined.connect(_peer_joined)
	session.peer_left.connect(_peer_left)
	session.connected_to_host.connect(_connected)
	session.connection_failed.connect(_connection_failed)
	session.input_received.connect(_remote_input)
	session.control_received.connect(_control)
	session.event_received.connect(_event)
	session.snapshot_received.connect(_apply_snapshot)


func is_host() -> bool:
	return session != null and session.role == NetworkSession.Role.HOST


func is_client() -> bool:
	return session != null and session.role == NetworkSession.Role.CLIENT


func is_online() -> bool:
	return session != null and session.is_online()


func host_game() -> void:
	if not game.lobby_active or session.host_game() != OK:
		return
	game.ai_companion = false
	game.lobby_joined.assign([true, false])
	game.lobby_devices.assign([-1, -3])
	game.lobby_device_names.assign([L.t("이 PC    호스트"), L.t("온라인 동료 대기 중")])
	game._refresh_lobby_ui()


func join_game(address: String) -> void:
	if not game.lobby_active or session.join_game(address) != OK:
		return
	game.ai_companion = false
	game.lobby_joined.assign([false, true])
	game.lobby_devices.assign([-3, -1])
	game.lobby_device_names.assign([L.t("호스트 연결 중"), L.t("이 PC    나")])
	game._refresh_lobby_ui()


func stop() -> void:
	_cancel_reconnect()
	_clear_replicas()
	session.stop()


func _status(message: String) -> void:
	game.help_label.text = message
	var status := game.lobby_overlay.get_node_or_null("NetworkStatus") as Label
	if status != null:
		status.text = message


func _peer_joined(_peer_id: int) -> void:
	if not is_host():
		return
	if reconnect_in_progress and reconnect_as_host:
		_status("온라인 동료 재접속 완료    런 복구 중…")
		return
	if not game.lobby_active:
		return
	game.lobby_joined.assign([true, true])
	game.lobby_device_names.assign([L.t("이 PC    호스트"), L.t("온라인 동료")])
	game._refresh_lobby_ui()
	var retrying: bool = bool(game.online_retry_pending)
	game._finish_lobby()
	if retrying:
		game.online_retry_pending = false
		game.character_confirmed.assign([true, true])
		game._refresh_character_select_ui()
	send_character_state()
	if retrying:
		game._start_selected_run()


func _connected() -> void:
	if reconnect_in_progress and not reconnect_as_host:
		_status("호스트 재접속 완료    런 상태 복구 중…")
		session.send_control({"type": "resume_request"})
		return
	game.lobby_joined.assign([true, true])
	game.lobby_device_names.assign([L.t("온라인 호스트"), L.t("이 PC    나")])
	game._refresh_lobby_ui()


func _peer_left(_peer_id: int) -> void:
	if _run_can_reconnect():
		if session.role == NetworkSession.Role.HOST:
			_begin_host_reconnect()
		else:
			_begin_client_reconnect()
		return
	if session.role == NetworkSession.Role.OFFLINE:
		game._begin_lobby()
		_status("연결 종료    다시 방을 만들거나 참가하세요")
	elif is_host():
		game._begin_lobby()
		_status("온라인 동료가 나갔습니다")


func _connection_failed() -> void:
	if reconnect_in_progress and not reconnect_as_host:
		reconnect_retry_timer = RECONNECT_RETRY_SECONDS


func _run_can_reconnect() -> bool:
	return (not game.title_active and not game.lobby_active
		and not game.character_select_active and not game.game_over)


func _begin_host_reconnect() -> void:
	reconnect_in_progress = true
	reconnect_as_host = true
	reconnect_remaining = RECONNECT_GRACE_SECONDS
	reconnect_forced_pause = not game.get_tree().paused
	if reconnect_forced_pause:
		game._set_pause(true, false)
	_status(L.f("온라인 동료 연결 끊김    %d초 동안 재접속 대기", int(RECONNECT_GRACE_SECONDS)))


func _begin_client_reconnect() -> void:
	reconnect_in_progress = true
	reconnect_as_host = false
	reconnect_remaining = RECONNECT_GRACE_SECONDS
	reconnect_retry_timer = 0.0
	reconnect_forced_pause = not game.get_tree().paused
	if reconnect_forced_pause:
		game._set_pause(true, false)
	_status("호스트 연결 끊김    자동 재접속 중…")


func _cancel_reconnect() -> void:
	reconnect_in_progress = false
	reconnect_as_host = false
	reconnect_remaining = 0.0
	reconnect_retry_timer = 0.0
	reconnect_forced_pause = false


func connection_tick(delta: float) -> void:
	if not reconnect_in_progress:
		return
	reconnect_remaining -= delta
	if reconnect_remaining <= 0.0:
		var was_host := reconnect_as_host
		_cancel_reconnect()
		if game.pause_active:
			game._set_pause(false, false)
		game._begin_lobby()
		_status(L.f("재접속 시간이 만료되었습니다    %s",
			L.t("방을 다시 열어 주세요") if was_host else L.t("다시 참가해 주세요")))
		return
	if reconnect_as_host:
		_status(L.f("온라인 동료 재접속 대기    %d초", ceili(reconnect_remaining)))
		return
	if session.role == NetworkSession.Role.CLIENT and session.peer_is_connected():
		return
	reconnect_retry_timer -= delta
	if reconnect_retry_timer <= 0.0:
		reconnect_retry_timer = RECONNECT_RETRY_SECONDS
		session.join_game(session.address, session.port)


func _remote_input(_peer_id: int, movement: Vector2, dash: bool) -> void:
	if is_host() and not game.lobby_active:
		last_remote_input_msec = Time.get_ticks_msec()
		game.players[1].set_command(movement, dash)


func send_character_state() -> void:
	if is_host():
		session.send_control({
			"type": "character_state",
			"indices": game.selected_character_indices.duplicate(),
			"confirmed": game.character_confirmed.duplicate(),
		})


func send_run_start() -> void:
	if is_host():
		session.send_control({
			"type": "run_start",
			"indices": game.selected_character_indices.duplicate(),
			"chain_max_length": game.chain_max_length,
			"player_stats": _player_build_states(),
		})


func _send_run_resume() -> void:
	if not is_host():
		return
	session.send_control({
		"type": "run_resume",
		"indices": game.selected_character_indices.duplicate(),
		"weapon_loadouts": game.weapon_loadouts.duplicate(true),
		"treasure_loadouts": game.treasure_loadouts.duplicate(true),
		"chain_max_length": game.chain_max_length,
		"player_stats": _player_build_states(),
		"active_resonances": game.resonance_system.active_resonances.duplicate(true),
		"pending_cores": game.resonance_system.pending_cores,
		"attack_timers": game.attack_timers.duplicate(true),
		"elapsed": game.elapsed,
		"kills": game.kills,
		"level": game.progression.level,
		"xp": game.progression.experience,
		"required_xp": game.progression.required_experience,
	})
	# Resume the modal that was already open, or the ordinary running state.
	if game.level_up_active:
		send_growth_state("growth_open")
	elif game.resonance_vote_active:
		send_resonance_state("resonance_open")
	else:
		send_pause_state(game.pause_active and not reconnect_forced_pause)
	session.send_snapshot(_snapshot())
	if reconnect_forced_pause:
		game._set_pause(false, false)
	_cancel_reconnect()
	_status("온라인 동료 복구 완료")


func send_growth_state(kind := "growth_state") -> void:
	if is_host():
		session.send_control({
			"type": kind,
			"level": game.progression.level,
			"p1_choices": game.p1_choices.duplicate(true),
			"p2_choices": game.p2_choices.duplicate(true),
			"selected": game.selected_upgrade_indices.duplicate(),
			"cursors": game.upgrade_cursors.duplicate(),
			"rerolls": game.rerolls_remaining.duplicate(),
		})


func send_growth_close() -> void:
	if is_host():
		session.send_control({
			"type": "growth_close",
			"weapon_loadouts": game.weapon_loadouts.duplicate(true),
			"treasure_loadouts": game.treasure_loadouts.duplicate(true),
			"chain_max_length": game.chain_max_length,
			"player_stats": _player_build_states(),
		})


func send_resonance_state(kind := "resonance_state") -> void:
	if is_host():
		session.send_control({
			"type": kind,
			"candidates": game.resonance_candidates.duplicate(true),
			"cursors": game.resonance_cursors.duplicate(),
			"votes": game.resonance_votes.duplicate(),
			"message": game.resonance_vote_message,
		})


func send_resonance_close(chosen: Dictionary) -> void:
	if is_host():
		session.send_control({
			"type": "resonance_close",
			"chosen": chosen.duplicate(true),
			"active": game.resonance_system.active_resonances.duplicate(true),
			"pending_cores": game.resonance_system.pending_cores,
		})


func request_resonance_action(action: String, index: int) -> void:
	if is_client():
		session.send_control({"type": "resonance_action", "action": action, "index": index})


func request_result_action(action: String) -> void:
	if is_client():
		session.send_control({"type": "result_action", "action": action})


func send_retry_run() -> void:
	if is_host():
		session.send_control({"type": "retry_run"})


func send_return_to_menu() -> void:
	if is_host():
		session.send_control({"type": "return_to_menu"})


func send_pause_state(enabled: bool) -> void:
	if is_host():
		session.send_control({"type": "pause_state", "enabled": enabled})


func request_pause(enabled: bool) -> void:
	if is_client():
		session.send_control({"type": "pause_request", "enabled": enabled})


func request_character_choice(index: int, confirmed: bool) -> void:
	if is_client():
		session.send_control({
			"type": "character_choice", "index": index, "confirmed": confirmed,
		})


func request_growth_select(index: int) -> void:
	if is_client():
		session.send_control({"type": "growth_select", "index": index})


func request_growth_cancel() -> void:
	if is_client():
		session.send_control({"type": "growth_cancel"})


func request_growth_reroll() -> void:
	if is_client():
		session.send_control({"type": "growth_reroll"})


func send_result(victory: bool, reward_eligible := false) -> void:
	if is_host():
		session.send_control({
			"type": "run_result", "victory": victory,
			"elapsed": game.elapsed, "kills": game.kills,
			"run_stats": game.run_stats.duplicate(true),
			"reward_eligible": reward_eligible,
			"debug_tainted": game.debug_run_tainted,
		})


func send_enemy_shot(origin: Vector2, direction: Vector2, speed: float) -> void:
	if is_host():
		session.send_event({
			"type": "enemy_shot", "origin": origin,
			"direction": direction, "speed": speed,
		})


func send_player_attack(player_index: int, weapon_id: String, origin: Vector2,
		color: Color, radius: float) -> void:
	if is_host():
		var direction := Vector2.RIGHT
		if player_index >= 0 and player_index < game.players.size():
			direction = game.players[player_index].facing
		session.send_event({
			"type": "player_attack", "player": player_index,
			"weapon": weapon_id, "origin": origin,
			"direction": direction, "color": color, "radius": radius,
		})


func _event(_peer_id: int, payload: Dictionary) -> void:
	if not is_client():
		return
	match String(payload.get("type", "")):
		"enemy_shot": _receive_enemy_shot(payload)
		"player_attack":
			game.weapon_controller.play_remote_attack(
				String(payload.get("weapon", "")),
				Vector2(payload.get("origin", Vector2.ZERO)),
				Vector2(payload.get("direction", Vector2.RIGHT)),
				Color(payload.get("color", Color.WHITE)),
				clampf(float(payload.get("radius", 64.0)), 32.0, 220.0))


func _control(peer_id: int, payload: Dictionary) -> void:
	var kind := String(payload.get("type", ""))
	if is_host():
		if peer_id not in session.multiplayer.get_peers():
			return
		if kind == "character_choice" and not game.character_select_active:
			return
		if kind.begins_with("growth_") and not game.level_up_active:
			return
		if kind == "resonance_action" and not game.resonance_vote_active:
			return
		if kind == "result_action" and not game.game_over:
			return
		match kind:
			"resume_request":
				if reconnect_in_progress and reconnect_as_host:
					_send_run_resume()
			"dash":
				if not game.game_over and not game.pause_active and not game.level_up_active \
						and not game.resonance_vote_active and not game.cinematic_active:
					game.players[1].commanded_dash = true
			"character_choice":
				game.selected_character_indices[1] = clampi(int(payload.get("index", 0)), 0, game.character_catalog.size() - 1)
				game.character_confirmed[1] = bool(payload.get("confirmed", false))
				game._refresh_character_select_ui()
				send_character_state()
				if game.character_confirmed[0] and game.character_confirmed[1]:
					game._start_selected_run()
			"growth_select":
				game._select_upgrade(2, int(payload.get("index", 0)))
			"growth_cancel":
				if game.selected_upgrade_indices[1] >= 0 and game.selected_upgrade_indices[0] < 0:
					game.selected_upgrade_indices[1] = -1
					send_growth_state()
			"growth_reroll":
				if game.selected_upgrade_indices[1] < 0 and game.rerolls_remaining[1] > 0:
					game._reroll_choices(2)
					send_growth_state("growth_open")
			"pause_request":
				var requested := bool(payload.get("enabled", false))
				if ((requested and not game.game_over and not game.level_up_active
						and not game.character_select_active and not game.cinematic_active)
						or (not requested and game.pause_active)):
					game._set_pause(requested)
			"resonance_action":
				var action := String(payload.get("action", ""))
				var index := clampi(int(payload.get("index", 0)), 0,
					maxi(0, game.resonance_candidates.size() - 1))
				match action:
					"cursor":
						if game.resonance_votes[1] < 0:
							game.resonance_cursors[1] = index
							game._refresh_resonance_vote_ui()
							send_resonance_state()
					"confirm":
						if game.resonance_votes[1] < 0:
							game.resonance_cursors[1] = index
							game.resonance_votes[1] = index
							game.feedback.play_cue("select")
							game._resolve_resonance_votes()
					"cancel":
						if game.resonance_votes[1] >= 0:
							game.resonance_votes[1] = -1
							game._refresh_resonance_vote_ui()
							send_resonance_state()
			"result_action":
				match String(payload.get("action", "")):
					"retry": game._retry_same_pair()
					"menu": game._return_to_main_menu()
		return
	match kind:
		"character_state": _receive_character_state(payload)
		"run_start": _receive_run_start(payload)
		"run_resume": _receive_run_resume(payload)
		"growth_open", "growth_state": _receive_growth_state(payload)
		"growth_close":
			game.weapon_loadouts.assign(payload.get("weapon_loadouts", game.weapon_loadouts))
			game.treasure_loadouts.assign(payload.get("treasure_loadouts", game.treasure_loadouts))
			game.chain_max_length = float(payload.get("chain_max_length", game.chain_max_length))
			_apply_player_build_states(payload.get("player_stats", []))
			_sync_attack_timers()
			game.level_up_active = false
			game.level_overlay.visible = false
			game.get_tree().paused = false
		"resonance_open", "resonance_state": _receive_resonance_state(payload)
		"resonance_close": _receive_resonance_close(payload)
		"pause_state": game._set_pause(bool(payload.get("enabled", false)), false)
		"run_result": _receive_result(payload)
		"retry_run": game._accept_online_retry()
		"return_to_menu": game._accept_online_return_to_menu()


func _receive_result(payload: Dictionary) -> void:
	game.elapsed = float(payload.get("elapsed", game.elapsed))
	game.kills = int(payload.get("kills", game.kills))
	game.run_stats = payload.get("run_stats", game.run_stats).duplicate(true)
	game.debug_run_tainted = bool(payload.get("debug_tainted", false))
	game._end_run(bool(payload.get("victory", false)),
		bool(payload.get("reward_eligible", false)))


func _receive_character_state(payload: Dictionary) -> void:
	game.selected_character_indices.assign(payload.get("indices", [0, 1]))
	game.character_confirmed.assign(payload.get("confirmed", [false, false]))
	game.lobby_active = false
	game.lobby_overlay.visible = false
	game.character_select_active = true
	game.character_overlay.visible = true
	game._refresh_character_select_ui()


func _receive_run_start(payload: Dictionary) -> void:
	if not game.game_over and not game.character_select_active and not game.lobby_active:
		return
	game.selected_character_indices.assign(payload.get("indices", [0, 1]))
	game.character_confirmed.assign([true, true])
	game._start_selected_run()
	game.chain_max_length = float(payload.get("chain_max_length", game.chain_max_length))
	_apply_player_build_states(payload.get("player_stats", []))


func _receive_run_resume(payload: Dictionary) -> void:
	game.selected_character_indices.assign(payload.get("indices", game.selected_character_indices))
	game.weapon_loadouts.assign(payload.get("weapon_loadouts", game.weapon_loadouts))
	game.treasure_loadouts.assign(payload.get("treasure_loadouts", game.treasure_loadouts))
	game.chain_max_length = float(payload.get("chain_max_length", game.chain_max_length))
	game.resonance_system.active_resonances.assign(
		payload.get("active_resonances", game.resonance_system.active_resonances))
	game.resonance_system.pending_cores = int(
		payload.get("pending_cores", game.resonance_system.pending_cores))
	game.attack_timers = payload.get("attack_timers", game.attack_timers).duplicate(true)
	game.elapsed = float(payload.get("elapsed", game.elapsed))
	game.kills = int(payload.get("kills", game.kills))
	game.progression.level = int(payload.get("level", game.progression.level))
	game.progression.experience = int(payload.get("xp", game.progression.experience))
	game.progression.required_experience = int(
		payload.get("required_xp", game.progression.required_experience))
	_apply_player_build_states(payload.get("player_stats", []))
	_sync_attack_timers()
	if reconnect_forced_pause:
		game._set_pause(false, false)
	_cancel_reconnect()
	_status("온라인 런 복구 완료")


func _receive_growth_state(payload: Dictionary) -> void:
	game.p1_choices.assign(payload.get("p1_choices", []))
	game.p2_choices.assign(payload.get("p2_choices", []))
	game.selected_upgrade_indices.assign(payload.get("selected", [-1, -1]))
	game.upgrade_cursors.assign(payload.get("cursors", [0, 0]))
	game.rerolls_remaining.assign(payload.get("rerolls", [0, 0]))
	game.progression.level = int(payload.get("level", game.progression.level))
	game.level_up_active = true
	game.level_overlay.visible = true
	game.level_up_input_delay = 0.0
	game.get_tree().paused = true
	game._refresh_level_up_ui()


func _receive_resonance_state(payload: Dictionary) -> void:
	game.resonance_candidates.assign(payload.get("candidates", []))
	game.resonance_cursors.assign(payload.get("cursors", [0, 0]))
	game.resonance_votes.assign(payload.get("votes", [-1, -1]))
	game.resonance_vote_message = String(payload.get("message", ""))
	game.resonance_vote_active = true
	game.resonance_overlay.visible = true
	game.modal_dim.visible = true
	game.modal_dim.veil_only = true
	game.get_tree().paused = true
	game._refresh_resonance_vote_ui()


func _receive_resonance_close(payload: Dictionary) -> void:
	game.resonance_system.active_resonances.assign(payload.get("active", []))
	game.resonance_system.pending_cores = int(payload.get("pending_cores", 0))
	game.resonance_vote_active = false
	game.resonance_overlay.visible = false
	game.get_tree().paused = false
	var chosen: Dictionary = payload.get("chosen", {})
	if not chosen.is_empty():
		game._show_message(L.f("공명 발현 — %s", ResonanceSystem.display_name(chosen)), Color("fff275"))


func _player_build_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for player in game.players:
		states.append({
			"health": player.health, "max_health": player.max_health,
			"move_speed": player.move_speed,
			"might": player.might, "haste": player.haste, "area": player.area,
			"projectile_speed": player.projectile_speed, "duration": player.duration,
			"amount": player.amount, "armor": player.armor, "recovery": player.recovery,
			"crit_chance": player.crit_chance, "pierce": player.pierce,
			"thorns": player.thorns, "resolve": player.resolve,
			"dodge_chance": player.dodge_chance,
			"second_chances": player.second_chances,
		})
	return states


func _apply_player_build_states(states: Array) -> void:
	for slot in mini(states.size(), game.players.size()):
		var state: Dictionary = states[slot]
		var player: ChainPlayer = game.players[slot]
		for key in state:
			player.set(key, state[key])


func client_tick(delta: float) -> void:
	if reconnect_in_progress:
		return
	if game.game_over:
		game._handle_result_input()
		return
	if game.pause_active:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
			request_pause(false)
		return
	if (not game.level_up_active and not game.character_select_active
			and not game.resonance_vote_active
			and Input.is_action_just_pressed("pause")):
		request_pause(true)
		return
	if game.character_select_active:
		_client_character_input()
		return
	if game.level_up_active:
		_client_growth_input()
		return
	if game.resonance_vote_active:
		_client_resonance_input()
		return
	if game.lobby_active or game.title_active or game.game_over:
		return
	var movement := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
	var dash := Input.is_action_just_pressed("p1_dash")
	session.submit_input(movement, dash)
	game.players[1].set_command(movement, dash)
	game.players[1].step_movement(delta)
	# Attacks stay host-authoritative. Running them here would mutate replica
	# enemy health and could temporarily kill an enemy that is alive on the host.
	game._update_chain_visual()
	game._update_camera(delta)
	game._update_hud()


func _client_character_input() -> void:
	if Input.is_action_just_pressed("p1_select_previous"):
		game._set_character_choice(1,
			wrapi(game.selected_character_indices[1] - 1, 0, game.character_catalog.size()), false)
	elif Input.is_action_just_pressed("p1_select_next"):
		game._set_character_choice(1,
			wrapi(game.selected_character_indices[1] + 1, 0, game.character_catalog.size()), false)
	elif Input.is_action_just_pressed("p1_select_confirm"):
		game._set_character_choice(1, game.selected_character_indices[1], true)
	elif Input.is_action_just_pressed("p1_select_cancel"):
		game._set_character_choice(1, game.selected_character_indices[1], false)


func _client_growth_input() -> void:
	if game.p2_choices.is_empty():
		return
	if Input.is_action_just_pressed("p1_select_previous"):
		game.upgrade_cursors[1] = wrapi(game.upgrade_cursors[1] - 1, 0, game.p2_choices.size())
		game._refresh_level_up_ui()
	elif Input.is_action_just_pressed("p1_select_next"):
		game.upgrade_cursors[1] = wrapi(game.upgrade_cursors[1] + 1, 0, game.p2_choices.size())
		game._refresh_level_up_ui()
	elif Input.is_action_just_pressed("p1_select_confirm"):
		game._confirm_growth_choice(1, game.upgrade_cursors[1])
	elif Input.is_action_just_pressed("p1_select_cancel"):
		game._cancel_growth_choice(1)
	elif Input.is_action_just_pressed("p1_reroll"):
		game._reroll_growth_choice(1)


func _client_resonance_input() -> void:
	if game.resonance_candidates.is_empty():
		return
	if game.resonance_votes[1] >= 0:
		if Input.is_action_just_pressed("p1_select_cancel"):
			game._cancel_resonance_vote(1)
		return
	if Input.is_action_just_pressed("p1_select_previous"):
		game._set_resonance_cursor(1, game.resonance_cursors[1] - 1)
	elif Input.is_action_just_pressed("p1_select_next"):
		game._set_resonance_cursor(1, game.resonance_cursors[1] + 1)
	elif Input.is_action_just_pressed("p1_select_confirm"):
		game._confirm_resonance_vote(1, game.resonance_cursors[1])


func _receive_enemy_shot(payload: Dictionary) -> void:
	# Through the host's own pool and the host's own signal wiring, so a received
	# shot is recycled and pruned by exactly the code a locally fired one is.
	var projectile: EnemyProjectile = game._acquire_enemy_shot()
	var no_targets: Array[ChainPlayer] = []
	projectile.setup(Vector2(payload.get("origin", Vector2.ZERO)),
		Vector2(payload.get("direction", Vector2.RIGHT)), 0.0, no_targets)
	projectile.speed = float(payload.get("speed", projectile.speed))
	# Registered like a host shot: the crowd renderer draws every enemy shot from
	# this list, and the friendly weapons that knock shots down read it too.
	game.enemy_shots.append(projectile)


func host_tick(delta: float) -> void:
	if not is_host() or game.lobby_active or game.character_select_active:
		return
	if last_remote_input_msec > 0 and Time.get_ticks_msec() - last_remote_input_msec > 500:
		game.players[1].set_command(Vector2.ZERO)
		last_remote_input_msec = 0
	snapshot_timer -= delta
	if snapshot_timer <= 0.0:
		snapshot_timer = 0.10
		session.send_snapshot(_snapshot())


func _snapshot() -> Dictionary:
	var player_states: Array = []
	for player in game.players:
		player_states.append({
			"position": player.position, "health": player.health,
			"max_health": player.max_health, "downed": player.downed,
			"bleedout": player.bleedout_remaining, "revive": player.revive_progress,
		})
	var enemy_states: Array = []
	var replication_center: Vector2 = (
		game.players[0].position + game.players[1].position) * 0.5
	for enemy in game.enemies:
		if (is_instance_valid(enemy) and not enemy.dead
				and (enemy.boss or enemy.position.distance_to(replication_center) <= REPLICATION_RADIUS)):
			enemy_states.append([
				enemy.get_instance_id(), enemy.position, enemy.rotation, enemy.archetype,
				enemy.elite, enemy.boss, enemy.boss_rank, enemy.health, enemy.max_health,
				enemy.slow_timer, enemy.telegraphing, enemy.charge_windup,
				enemy.shooter_windup, enemy.chain_windup, enemy.boss_slam_windup,
				enemy.telegraph_direction, enemy.boss_slam_point, enemy.boss_enraged,
			])
	var item_states: Array = []
	for item in game.field_items.active_items:
		if is_instance_valid(item) and item.active:
			item_states.append([
				item.get_instance_id(), item.position, item.item_id, item.lifetime,
			])
	return {
		"players": player_states, "enemies": enemy_states, "items": item_states,
		"elapsed": game.elapsed, "kills": game.kills,
		"chain_integrity": game.chain_integrity,
		"chain_max_length": game.chain_max_length,
		"chain_overloaded": game.chain_overloaded,
		"chain_ward_remaining": game.chain_ward_remaining,
		"guard_remaining": game.guard_remaining,
		"frenzy_remaining": game.frenzy_remaining,
		"time_stop_remaining": game.time_stop_remaining,
		"attack_timers": game.attack_timers.duplicate(true),
		"resonance_clocks": _resonance_clocks(),
		"pending_cores": game.resonance_system.pending_cores,
		"level": game.progression.level, "xp": game.progression.experience,
		"required_xp": game.progression.required_experience,
	}


func _apply_snapshot(payload: Dictionary) -> void:
	if not is_client() or game.character_select_active or game.lobby_active:
		return
	var states: Array = payload.get("players", [])
	for slot in mini(2, states.size()):
		var state: Dictionary = states[slot]
		game.players[slot].position = game.players[slot].position.lerp(Vector2(state["position"]), 0.55)
		game.players[slot].health = float(state["health"])
		game.players[slot].max_health = float(state["max_health"])
		game.players[slot].downed = bool(state["downed"])
		game.players[slot].bleedout_remaining = float(state["bleedout"])
		game.players[slot].revive_progress = float(state["revive"])
		game.players[slot].queue_redraw()
	game.elapsed = float(payload.get("elapsed", game.elapsed))
	game.kills = int(payload.get("kills", game.kills))
	game.chain_integrity = float(payload.get("chain_integrity", game.chain_integrity))
	game.chain_max_length = float(payload.get("chain_max_length", game.chain_max_length))
	game.chain_overloaded = bool(payload.get("chain_overloaded", game.chain_overloaded))
	game.chain_ward_remaining = float(payload.get("chain_ward_remaining", game.chain_ward_remaining))
	game.guard_remaining = float(payload.get("guard_remaining", game.guard_remaining))
	game.frenzy_remaining = float(payload.get("frenzy_remaining", game.frenzy_remaining))
	game.time_stop_remaining = float(payload.get("time_stop_remaining", game.time_stop_remaining))
	game.progression.level = int(payload.get("level", game.progression.level))
	game.progression.experience = int(payload.get("xp", game.progression.experience))
	game.progression.required_experience = int(payload.get("required_xp", game.progression.required_experience))
	_sync_attack_timers()
	if payload.has("attack_timers"):
		game.attack_timers = payload["attack_timers"].duplicate(true)
	if payload.has("resonance_clocks"):
		_apply_resonance_clocks(payload["resonance_clocks"])
	if payload.has("pending_cores"):
		game.resonance_system.pending_cores = int(payload["pending_cores"])
	if payload.has("enemies"):
		_sync_enemies(payload["enemies"])
	if payload.has("items"):
		_sync_items(payload["items"])


func _resonance_clocks() -> Array:
	var clocks: Array = []
	for resonance: Dictionary in game.resonance_system.active_resonances:
		clocks.append([String(resonance.get("id", "")),
			float(resonance.get("cooldown_remaining", 0.0))])
	return clocks


func _apply_resonance_clocks(clocks: Array) -> void:
	for clock: Array in clocks:
		if clock.size() < 2:
			continue
		for resonance: Dictionary in game.resonance_system.active_resonances:
			if String(resonance.get("id", "")) == String(clock[0]):
				resonance["cooldown_remaining"] = float(clock[1])
				break


func _sync_attack_timers() -> void:
	for slot in 2:
		while game.attack_timers[slot].size() < game.weapon_loadouts[slot].size():
			game.attack_timers[slot].append(0.1)
		while game.attack_timers[slot].size() > game.weapon_loadouts[slot].size():
			game.attack_timers[slot].pop_back()


func _sync_items(states: Array) -> void:
	var live: Dictionary = {}
	for state: Array in states:
		if state.size() < 4:
			continue
		var id := int(state[0])
		live[id] = true
		var item: FieldItem = replica_items.get(id)
		var item_kind := String(state[2])
		var remote_lifetime := float(state[3])
		if not is_instance_valid(item):
			item = FieldItemScript.new() as FieldItem
			game.field_items.add_child(item)
			item.activate(Vector2(state[1]), item_kind,
				game.field_items.item_color(item_kind))
			replica_items[id] = item
		elif item.item_id != item_kind or remote_lifetime > item.lifetime + 0.25:
			# The host pools item nodes, so a collected node can reappear with the
			# same instance id before the next snapshot. A reset lifetime marks it
			# as a new drop and must snap it to the new spawn instead of drifting.
			item.activate(Vector2(state[1]), item_kind,
				game.field_items.item_color(item_kind))
		else:
			item.position = item.position.lerp(Vector2(state[1]), 0.7)
		item.lifetime = remote_lifetime
		item.queue_redraw()
	for id in replica_items.keys():
		if not live.has(id):
			var stale: FieldItem = replica_items[id]
			if is_instance_valid(stale):
				stale.queue_free()
			replica_items.erase(id)


func _clear_replicas() -> void:
	for enemy in replica_enemies.values():
		if is_instance_valid(enemy):
			enemy.queue_free()
	for item in replica_items.values():
		if is_instance_valid(item):
			item.queue_free()
	replica_enemies.clear()
	replica_items.clear()


func _sync_enemies(states: Array) -> void:
	var live: Dictionary = {}
	var synced: Array[ChaserEnemy] = []
	for state: Array in states:
		if state.size() < EnemyField.size():
			continue
		var id := int(state[EnemyField.ID])
		live[id] = true
		var enemy: ChaserEnemy = replica_enemies.get(id)
		if not is_instance_valid(enemy):
			enemy = ChaserEnemy.new()
			enemy.setup(1.0, String(state[EnemyField.ARCHETYPE]),
				bool(state[EnemyField.ELITE]), bool(state[EnemyField.BOSS]),
				int(state[EnemyField.RANK]))
			game.world_stage.add_child(enemy)
			enemy.z_index = 0
			replica_enemies[id] = enemy
		enemy.position = enemy.position.lerp(Vector2(state[EnemyField.POSITION]), 0.65)
		enemy.rotation = float(state[EnemyField.ROTATION])
		enemy.health = float(state[EnemyField.HEALTH])
		enemy.max_health = float(state[EnemyField.MAX_HEALTH])
		enemy.dead = false
		enemy.active = true
		# Visibility belongs to the crowd renderer, which hides the bodies it draws
		# in batches; forcing it on every snapshot drew those bodies twice.
		if not game.crowd_renderer.enabled or enemy.boss:
			enemy.visible = true
		enemy.slow_timer = float(state[EnemyField.SLOW_TIMER])
		enemy.telegraphing = bool(state[EnemyField.TELEGRAPHING])
		enemy.charge_windup = float(state[EnemyField.CHARGE_WINDUP])
		enemy.shooter_windup = float(state[EnemyField.SHOOTER_WINDUP])
		enemy.chain_windup = float(state[EnemyField.CHAIN_WINDUP])
		enemy.boss_slam_windup = float(state[EnemyField.BOSS_SLAM_WINDUP])
		enemy.telegraph_direction = Vector2(state[EnemyField.TELEGRAPH_DIRECTION])
		enemy.boss_slam_point = Vector2(state[EnemyField.BOSS_SLAM_POINT])
		enemy.boss_enraged = bool(state[EnemyField.BOSS_ENRAGED])
		enemy.queue_redraw()
		if enemy.boss:
			game.boss_enemy = enemy
		synced.append(enemy)
	for id in replica_enemies.keys():
		if not live.has(id):
			var stale: ChaserEnemy = replica_enemies[id]
			if is_instance_valid(stale):
				stale.queue_free()
			replica_enemies.erase(id)
	game.enemies.assign(synced)
	if is_instance_valid(game.boss_enemy) and game.boss_enemy in synced:
		# The bar is drawn rather than themed now, so the client feeds it the same
		# way the host does: name and rank once when the boss changes, health on
		# every snapshot. Re-resetting on every snapshot would restart the
		# lagging ghost each tick and the client would never see a damage burst.
		if String(game.boss_bar.boss_name) != game.boss_name(game.boss_enemy.boss_rank):
			game.boss_bar.reset(game.boss_name(game.boss_enemy.boss_rank),
				game.boss_enemy.boss_rank, WaveDirectorScript.BOSS_COUNT, game.boss_enemy.max_health)
		game.boss_bar.report(game.boss_enemy.health, game.boss_enemy.max_health,
			bool(game.boss_enemy.boss_enraged))
		game.boss_bar.visible = true
		game.boss_label.text = "%s   %d/%d" % [
			game.boss_name(game.boss_enemy.boss_rank), game.boss_enemy.boss_rank,
			WaveDirector.BOSS_COUNT,
		]
		game.boss_label.visible = false
		game.boss_health_text_label.text = "%d / %d" % [
			int(ceil(game.boss_enemy.health)), int(ceil(game.boss_enemy.max_health))]
		game.boss_health_text_label.visible = false
	else:
		game.boss_enemy = null
		game._hide_boss_readout()
	game.spatial_grid.rebuild(game.enemies)
