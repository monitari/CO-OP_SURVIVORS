class_name OnlineCoop
extends Node

const SessionScript := preload("res://scripts/systems/network_session.gd")

var game: Node
var session: NetworkSession
var snapshot_timer := 0.0
var replica_enemies: Dictionary = {}


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
	session.input_received.connect(_remote_input)
	session.control_received.connect(_control)
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
	game.lobby_device_names.assign(["이 PC · 호스트", "온라인 동료 대기 중"])
	game._refresh_lobby_ui()


func join_game(address: String) -> void:
	if not game.lobby_active or session.join_game(address) != OK:
		return
	game.ai_companion = false
	game.lobby_joined.assign([false, true])
	game.lobby_devices.assign([-3, -1])
	game.lobby_device_names.assign(["호스트 연결 중", "이 PC · P2"])
	game._refresh_lobby_ui()


func stop() -> void:
	session.stop()


func _status(message: String) -> void:
	game.help_label.text = message
	var status := game.lobby_overlay.get_node_or_null("NetworkStatus") as Label
	if status != null:
		status.text = message


func _peer_joined(_peer_id: int) -> void:
	if not is_host() or not game.lobby_active:
		return
	game.lobby_joined.assign([true, true])
	game.lobby_device_names.assign(["이 PC · 호스트", "온라인 동료"])
	game._refresh_lobby_ui()
	game._finish_lobby()
	send_character_state()


func _connected() -> void:
	game.lobby_joined.assign([true, true])
	game.lobby_device_names.assign(["온라인 호스트", "이 PC · P2"])
	game._refresh_lobby_ui()


func _peer_left(_peer_id: int) -> void:
	if session.role == NetworkSession.Role.OFFLINE:
		game._begin_lobby()
		_status("연결 종료 · 다시 방을 만들거나 참가하세요")
	elif is_host():
		game._begin_lobby()
		_status("온라인 동료가 나갔습니다")


func _remote_input(_peer_id: int, movement: Vector2, dash: bool) -> void:
	if is_host() and not game.lobby_active:
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
		})


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
		})


func _control(_peer_id: int, payload: Dictionary) -> void:
	var kind := String(payload.get("type", ""))
	if is_host():
		match kind:
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
		return
	match kind:
		"character_state": _receive_character_state(payload)
		"run_start": _receive_run_start(payload)
		"growth_open", "growth_state": _receive_growth_state(payload)
		"growth_close":
			game.weapon_loadouts.assign(payload.get("weapon_loadouts", game.weapon_loadouts))
			game.treasure_loadouts.assign(payload.get("treasure_loadouts", game.treasure_loadouts))
			_sync_attack_timers()
			game.level_up_active = false
			game.level_overlay.visible = false
			game.get_tree().paused = false


func _receive_character_state(payload: Dictionary) -> void:
	game.selected_character_indices.assign(payload.get("indices", [0, 1]))
	game.character_confirmed.assign(payload.get("confirmed", [false, false]))
	game.lobby_active = false
	game.lobby_overlay.visible = false
	game.character_select_active = true
	game.character_overlay.visible = true
	game._refresh_character_select_ui()


func _receive_run_start(payload: Dictionary) -> void:
	game.selected_character_indices.assign(payload.get("indices", [0, 1]))
	game.character_confirmed.assign([true, true])
	game._start_selected_run()


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


func client_tick(delta: float) -> void:
	if game.character_select_active:
		_client_character_input()
		return
	if game.level_up_active:
		_client_growth_input()
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
	var changed := false
	if Input.is_action_just_pressed("p1_select_previous"):
		game.selected_character_indices[1] = wrapi(game.selected_character_indices[1] - 1, 0, game.character_catalog.size())
		game.character_confirmed[1] = false
		changed = true
	elif Input.is_action_just_pressed("p1_select_next"):
		game.selected_character_indices[1] = wrapi(game.selected_character_indices[1] + 1, 0, game.character_catalog.size())
		game.character_confirmed[1] = false
		changed = true
	elif Input.is_action_just_pressed("p1_select_confirm"):
		game.character_confirmed[1] = true
		changed = true
	elif Input.is_action_just_pressed("p1_select_cancel"):
		game.character_confirmed[1] = false
		changed = true
	if changed:
		game._refresh_character_select_ui()
		session.send_control({
			"type": "character_choice",
			"index": game.selected_character_indices[1],
			"confirmed": game.character_confirmed[1],
		})


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
		session.send_control({"type": "growth_select", "index": game.upgrade_cursors[1]})
	elif Input.is_action_just_pressed("p1_select_cancel"):
		session.send_control({"type": "growth_cancel"})
	elif Input.is_action_just_pressed("p1_reroll"):
		session.send_control({"type": "growth_reroll"})


func host_tick(delta: float) -> void:
	if not is_host() or game.lobby_active or game.character_select_active:
		return
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
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy_states.append({
				"id": enemy.get_instance_id(), "position": enemy.position,
				"rotation": enemy.rotation, "archetype": enemy.archetype,
				"elite": enemy.elite, "boss": enemy.boss, "rank": enemy.boss_rank,
				"health": enemy.health, "max_health": enemy.max_health,
				"slow_timer": enemy.slow_timer, "telegraphing": enemy.telegraphing,
			})
	return {
		"players": player_states, "enemies": enemy_states,
		"elapsed": game.elapsed, "kills": game.kills,
		"chain_integrity": game.chain_integrity,
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
	game.progression.level = int(payload.get("level", game.progression.level))
	game.progression.experience = int(payload.get("xp", game.progression.experience))
	game.progression.required_experience = int(payload.get("required_xp", game.progression.required_experience))
	_sync_attack_timers()
	_sync_enemies(payload.get("enemies", []))


func _sync_attack_timers() -> void:
	for slot in 2:
		while game.attack_timers[slot].size() < game.weapon_loadouts[slot].size():
			game.attack_timers[slot].append(0.1)
		while game.attack_timers[slot].size() > game.weapon_loadouts[slot].size():
			game.attack_timers[slot].pop_back()


func _sync_enemies(states: Array) -> void:
	var live: Dictionary = {}
	var synced: Array[ChaserEnemy] = []
	for state: Dictionary in states:
		var id := int(state["id"])
		live[id] = true
		var enemy: ChaserEnemy = replica_enemies.get(id)
		if not is_instance_valid(enemy):
			enemy = ChaserEnemy.new()
			enemy.setup(1.0, String(state["archetype"]), bool(state["elite"]), bool(state["boss"]), int(state["rank"]))
			game.wave_director.add_child(enemy)
			replica_enemies[id] = enemy
		enemy.position = enemy.position.lerp(Vector2(state["position"]), 0.65)
		enemy.rotation = float(state["rotation"])
		enemy.health = float(state["health"])
		enemy.max_health = float(state["max_health"])
		enemy.dead = false
		enemy.active = true
		enemy.visible = true
		enemy.slow_timer = float(state["slow_timer"])
		enemy.telegraphing = bool(state["telegraphing"])
		enemy.queue_redraw()
		synced.append(enemy)
	for id in replica_enemies.keys():
		if not live.has(id):
			var stale: ChaserEnemy = replica_enemies[id]
			if is_instance_valid(stale):
				stale.queue_free()
			replica_enemies.erase(id)
	game.enemies.assign(synced)
	game.spatial_grid.rebuild(game.enemies)
