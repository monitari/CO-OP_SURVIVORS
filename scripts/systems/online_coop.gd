class_name OnlineCoop
extends Node

const SessionScript := preload("res://scripts/systems/network_session.gd")
const EnemyProjectileScript := preload("res://scripts/entities/enemy_projectile.gd")
const FieldItemScript := preload("res://scripts/entities/field_item.gd")

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
var replica_enemies: Dictionary = {}
var replica_items: Dictionary = {}


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
	game.lobby_device_names.assign(["이 PC · 호스트", "온라인 동료 대기 중"])
	game._refresh_lobby_ui()


func join_game(address: String) -> void:
	if not game.lobby_active or session.join_game(address) != OK:
		return
	game.ai_companion = false
	game.lobby_joined.assign([false, true])
	game.lobby_devices.assign([-3, -1])
	game.lobby_device_names.assign(["호스트 연결 중", "이 PC · 나"])
	game._refresh_lobby_ui()


func stop() -> void:
	_clear_replicas()
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
	game.lobby_device_names.assign(["온라인 호스트", "이 PC · 나"])
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


func send_result(victory: bool) -> void:
	if is_host():
		session.send_control({
			"type": "run_result", "victory": victory,
			"elapsed": game.elapsed, "kills": game.kills,
			"run_stats": game.run_stats.duplicate(true),
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
		session.send_event({
			"type": "player_attack", "player": player_index,
			"weapon": weapon_id, "origin": origin,
			"color": color, "radius": radius,
		})


func _event(_peer_id: int, payload: Dictionary) -> void:
	if not is_client():
		return
	match String(payload.get("type", "")):
		"enemy_shot": _receive_enemy_shot(payload)
		"player_attack":
			game.weapon_controller.play_remote_attack(
				Vector2(payload.get("origin", Vector2.ZERO)),
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
			"pause_request":
				var requested := bool(payload.get("enabled", false))
				if ((requested and not game.game_over and not game.level_up_active
						and not game.character_select_active and not game.cinematic_active)
						or (not requested and game.pause_active)):
					game._set_pause(requested)
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
		"pause_state": game._set_pause(bool(payload.get("enabled", false)), false)
		"run_result": _receive_result(payload)


func _receive_result(payload: Dictionary) -> void:
	game.elapsed = float(payload.get("elapsed", game.elapsed))
	game.kills = int(payload.get("kills", game.kills))
	game.run_stats = payload.get("run_stats", game.run_stats).duplicate(true)
	game._end_run(bool(payload.get("victory", false)), false)


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
	if game.game_over:
		return
	if game.pause_active:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
			request_pause(false)
		return
	if (not game.level_up_active and not game.character_select_active
			and Input.is_action_just_pressed("pause")):
		request_pause(true)
		return
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


func _receive_enemy_shot(payload: Dictionary) -> void:
	var projectile := EnemyProjectileScript.new() as EnemyProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	var no_targets: Array[ChainPlayer] = []
	projectile.setup(Vector2(payload.get("origin", Vector2.ZERO)),
		Vector2(payload.get("direction", Vector2.RIGHT)), 0.0, no_targets)
	projectile.speed = float(payload.get("speed", projectile.speed))
	game.add_child(projectile)


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
		"attack_timers": game.attack_timers.duplicate(true),
		"resonances": game.resonance_system.active_resonances.duplicate(true),
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
	if payload.has("attack_timers"):
		game.attack_timers = payload["attack_timers"].duplicate(true)
	if payload.has("resonances"):
		game.resonance_system.active_resonances.assign(payload["resonances"])
	_sync_enemies(payload.get("enemies", []))
	_sync_items(payload.get("items", []))


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
			game.wave_director.add_child(enemy)
			replica_enemies[id] = enemy
		enemy.position = enemy.position.lerp(Vector2(state[EnemyField.POSITION]), 0.65)
		enemy.rotation = float(state[EnemyField.ROTATION])
		enemy.health = float(state[EnemyField.HEALTH])
		enemy.max_health = float(state[EnemyField.MAX_HEALTH])
		enemy.dead = false
		enemy.active = true
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
		game.boss_bar.max_value = game.boss_enemy.max_health
		game.boss_bar.value = game.boss_enemy.health
		game.boss_bar.visible = true
		game.boss_label.text = "%s   %d/%d" % [
			game.boss_name(game.boss_enemy.boss_rank), game.boss_enemy.boss_rank,
			WaveDirector.BOSS_COUNT,
		]
		game.boss_label.visible = true
		game.boss_health_text_label.text = "%d / %d" % [
			int(ceil(game.boss_enemy.health)), int(ceil(game.boss_enemy.max_health))]
		game.boss_health_text_label.visible = true
	else:
		game.boss_enemy = null
		game._hide_boss_readout()
	game.spatial_grid.rebuild(game.enemies)
