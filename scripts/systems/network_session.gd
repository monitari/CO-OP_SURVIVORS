class_name NetworkSession
extends Node
const L := preload("res://scripts/systems/loc.gd")

signal status_changed(message: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_host
signal connection_failed
signal input_received(peer_id: int, movement: Vector2, dash: bool)
signal control_received(peer_id: int, payload: Dictionary)
signal event_received(peer_id: int, payload: Dictionary)
signal snapshot_received(payload: Dictionary)

enum Role { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 24872
const MAX_CLIENTS := 1
const ENEMIES_PER_SNAPSHOT_PART := 2

var role := Role.OFFLINE
var address := "127.0.0.1"
var port := DEFAULT_PORT
var snapshot_sequence := 0
var incoming_snapshots: Dictionary = {}
var last_applied_snapshot_sequence := -1
var last_applied_base_sequence := -1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(listen_port := DEFAULT_PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(listen_port, MAX_CLIENTS)
	if error != OK:
		status_changed.emit(L.f("방을 열 수 없습니다    포트 %d", listen_port))
		return error
	role = Role.HOST
	port = listen_port
	multiplayer.multiplayer_peer = peer
	status_changed.emit(L.f("LAN 방 열림    포트 %d    친구를 기다리는 중", port))
	return OK


func join_game(host_address: String, host_port := DEFAULT_PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var clean_address := host_address.strip_edges()
	if clean_address.is_empty():
		clean_address = "127.0.0.1"
	var error := peer.create_client(clean_address, host_port)
	if error != OK:
		status_changed.emit(L.f("접속을 시작할 수 없습니다    %s:%d", [clean_address, host_port]))
		return error
	role = Role.CLIENT
	address = clean_address
	port = host_port
	multiplayer.multiplayer_peer = peer
	status_changed.emit(L.f("%s:%d 접속 중…", [address, port]))
	return OK


func stop() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	incoming_snapshots.clear()
	last_applied_snapshot_sequence = -1
	last_applied_base_sequence = -1


func is_online() -> bool:
	return role != Role.OFFLINE


func peer_is_connected() -> bool:
	return (multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer.get_connection_status()
			== MultiplayerPeer.CONNECTION_CONNECTED)


func submit_input(movement: Vector2, dash: bool) -> void:
	if role == Role.CLIENT and peer_is_connected():
		_receive_input.rpc_id(1, movement.limit_length(1.0), false)
		# Movement is disposable, but a dash is a single button edge. Send that
		# edge reliably so one lost input packet cannot eat the action entirely.
		if dash:
			_receive_control.rpc_id(1, {"type": "dash"})


func send_control(payload: Dictionary) -> void:
	if role == Role.CLIENT and peer_is_connected():
		_receive_control.rpc_id(1, payload)
	elif role == Role.HOST:
		_receive_control.rpc(payload)


func send_event(payload: Dictionary) -> void:
	if role == Role.HOST and not multiplayer.get_peers().is_empty():
		_receive_event.rpc(payload)


func send_snapshot(payload: Dictionary) -> void:
	if role != Role.HOST or multiplayer.get_peers().is_empty():
		return
	snapshot_sequence += 1
	var base := payload.duplicate(true)
	var enemies: Array = base.get("enemies", [])
	base.erase("enemies")
	# Keep the shared state below the unreliable packet MTU even as new HUD or
	# audio fields are added. Enemy chunks travel in their own small packets.
	var part_count := 1 + ceili(float(enemies.size()) / float(ENEMIES_PER_SNAPSHOT_PART))
	for part in part_count:
		var chunk: Array = []
		if part > 0:
			var first := (part - 1) * ENEMIES_PER_SNAPSHOT_PART
			chunk = enemies.slice(first, mini(first + ENEMIES_PER_SNAPSHOT_PART, enemies.size()))
		_receive_snapshot_part.rpc(snapshot_sequence, part, part_count, base if part == 0 else {}, chunk)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(movement: Vector2, dash: bool) -> void:
	if role != Role.HOST:
		return
	input_received.emit(multiplayer.get_remote_sender_id(), movement.limit_length(1.0), dash)


@rpc("any_peer", "call_remote", "reliable", 0)
func _receive_control(payload: Dictionary) -> void:
	control_received.emit(multiplayer.get_remote_sender_id(), payload)


@rpc("authority", "call_remote", "unreliable", 3)
func _receive_event(payload: Dictionary) -> void:
	if role == Role.CLIENT:
		event_received.emit(multiplayer.get_remote_sender_id(), payload)


@rpc("authority", "call_remote", "unreliable", 2)
func _receive_snapshot_part(sequence: int, part: int, part_count: int,
		base: Dictionary, enemies: Array) -> void:
	if role != Role.CLIENT:
		return
	if sequence <= last_applied_snapshot_sequence:
		return
	if not incoming_snapshots.has(sequence):
		incoming_snapshots[sequence] = {"base": {}, "parts": {}, "count": part_count}
	var assembly: Dictionary = incoming_snapshots[sequence]
	if not base.is_empty():
		assembly["base"] = base
		# Player, timer and boss-independent state must not wait for every enemy
		# chunk. With a full late-game crowd that could otherwise turn one dropped
		# unreliable packet into a visible 100 ms freeze of the whole HUD.
		if part_count > 1 and sequence > last_applied_base_sequence:
			last_applied_base_sequence = sequence
			snapshot_received.emit(base.duplicate(true))
	(assembly["parts"] as Dictionary)[part] = enemies
	for old_sequence in incoming_snapshots.keys():
		if int(old_sequence) < sequence - 2:
			incoming_snapshots.erase(old_sequence)
	if (assembly["parts"] as Dictionary).size() < part_count or (assembly["base"] as Dictionary).is_empty():
		return
	# If a newer base already updated the player/HUD, an older enemy assembly may
	# still improve the crowd picture but must not rewind those newer values.
	var payload: Dictionary = {} if sequence < last_applied_base_sequence else assembly["base"]
	var combined: Array = []
	for index in part_count:
		combined.append_array((assembly["parts"] as Dictionary)[index])
	payload["enemies"] = combined
	incoming_snapshots.erase(sequence)
	last_applied_snapshot_sequence = sequence
	for old_sequence in incoming_snapshots.keys():
		if int(old_sequence) <= sequence:
			incoming_snapshots.erase(old_sequence)
	snapshot_received.emit(payload)


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)
	status_changed.emit("온라인 동료 접속 완료")


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
	status_changed.emit("온라인 동료 연결 종료")


func _on_connected_to_server() -> void:
	connected_to_host.emit()
	status_changed.emit("호스트 접속 완료")


func _on_connection_failed() -> void:
	role = Role.OFFLINE
	connection_failed.emit()
	status_changed.emit("호스트에 접속하지 못했습니다")


func _on_server_disconnected() -> void:
	role = Role.OFFLINE
	peer_left.emit(1)
	status_changed.emit("호스트와 연결이 끊겼습니다")
