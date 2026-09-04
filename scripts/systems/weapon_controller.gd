class_name WeaponController
extends Node2D

const ProjectileScript := preload("res://scripts/projectile.gd")

var players: Array[ChainPlayer] = []
var weapon_loadouts: Array = []
var spatial_grid: EnemySpatialGrid
var elapsed := 0.0
var active_projectiles: Array[HomingProjectile] = []
var projectile_pool: Array[HomingProjectile] = []


func configure(
	player_nodes: Array[ChainPlayer],
	loadouts: Array,
	grid: EnemySpatialGrid
) -> void:
	players = player_nodes
	weapon_loadouts = loadouts
	spatial_grid = grid


## Each weapon-loadout entry is self-contained (weapon_id, color, and tags
## travel with it) rather than looked up from selected_characters[player_index],
## because a picked-up weapon belongs to whichever character it came from —
## a player's second or third weapon does not share their own character's color.
func perform_attack(player_index: int, weapon_slot: int, damage_multiplier: float) -> void:
	var owner_player := players[player_index]
	if owner_player.downed:
		return
	var state: Dictionary = weapon_loadouts[player_index][weapon_slot]
	var weapon_id := String(state["weapon_id"])
	var color := Color(state["color"])
	var damage := float(state["damage"]) * damage_multiplier * owner_player.might
	# The personal attributes scale the weapon's own numbers rather than
	# replacing them, so a scaled copy is handed to the effect functions and the
	# stored loadout entry keeps its unmodified base values.
	var scaled := state.duplicate()
	scaled["count"] = int(state.get("count", 1)) + owner_player.amount
	scaled["speed"] = float(state.get("speed", 0.0)) * owner_player.projectile_speed
	scaled["radius"] = float(state.get("radius", 0.0)) * owner_player.area
	scaled["range"] = float(state.get("range", 0.0)) * owner_player.area
	scaled["width"] = float(state.get("width", 0.0)) * owner_player.area
	scaled["arc"] = minf(TAU, float(state.get("arc", 0.0)) * owner_player.area)
	match weapon_id:
		"homing": _fire_homing(player_index, scaled, damage, color)
		"lightning": _fire_lightning(owner_player.global_position, int(state["jumps"]), damage, float(scaled["range"]), color)
		"flame": _fire_flame_nova(player_index, scaled, damage, color)
		"frost": _fire_frost_ring(player_index, scaled, damage, color)
		"scythe": _swing_scythe(player_index, scaled, damage, color)
		"chain": _fire_chain_pulse(scaled, damage)


func perform_resonance(resonance: Dictionary, damage_multiplier: float) -> void:
	var resonance_id := String(resonance["id"])
	var midpoint := (players[0].global_position + players[1].global_position) * 0.5
	match resonance_id:
		"guided_thunder":
			_fire_lightning(midpoint, 8, 38.0 * damage_multiplier, 760.0, Color("fff275"))
		"storm_volley":
			_fire_flame_nova(0, {"count": 10, "speed": 480.0}, 22.0 * damage_multiplier, Color("b892ff"))
			_fire_flame_nova(1, {"count": 10, "speed": 480.0}, 22.0 * damage_multiplier, Color("b892ff"))
			_fire_lightning(midpoint, 5, 26.0 * damage_multiplier, 620.0, Color("b892ff"))
		"arcane_circuit":
			_damage_along_chain(68.0, 48.0 * damage_multiplier, 1.0)
			for player in players:
				player.heal(4.0)
		"thermal_fracture":
			_damage_area(midpoint, 300.0, 44.0 * damage_multiplier, 0.38)
			_draw_ring(midpoint, 300.0, Color("ffb4a2"), 12.0)
		"eclipse_tether":
			_fire_chain_pulse({"width": 92.0}, 42.0 * damage_multiplier)
			_swing_scythe(0, {"range": 280.0, "arc": 2.35}, 46.0 * damage_multiplier, Color("ef476f"))
			_swing_scythe(1, {"range": 280.0, "arc": 2.35}, 46.0 * damage_multiplier, Color("ef476f"))
		"storm_field":
			_fire_lightning(players[0].global_position, 6, 28.0 * damage_multiplier, 520.0, Color("b892ff"))
			_fire_lightning(players[1].global_position, 6, 28.0 * damage_multiplier, 520.0, Color("43d9ff"))
		"inferno_crescent":
			_swing_scythe(0, {"range": 270.0, "arc": 2.5}, 48.0 * damage_multiplier, Color("ff8c42"))
			_swing_scythe(1, {"range": 270.0, "arc": 2.5}, 48.0 * damage_multiplier, Color("ff8c42"))
		"astral_covenant":
			for player in players:
				player.heal(8.0)
				_damage_area(player.global_position, 190.0, 32.0 * damage_multiplier)
				_draw_ring(player.global_position, 190.0, Color("e4c1f9"), 8.0)
		"frozen_tether":
			_damage_along_chain(82.0, 36.0 * damage_multiplier, 0.32)
		"comet_shower":
			_fire_flame_nova(0, {"count": 14, "speed": 430.0}, 26.0 * damage_multiplier, Color("8ecae6"))
			_fire_flame_nova(1, {"count": 14, "speed": 430.0}, 26.0 * damage_multiplier, Color("8ecae6"))
		"starbound_trajectory":
			_fire_lightning(players[0].global_position, 6, 30.0 * damage_multiplier, 560.0, Color("43d9ff"))
			_fire_lightning(players[1].global_position, 6, 30.0 * damage_multiplier, 560.0, Color("43d9ff"))
		"storm_core":
			_fire_lightning(midpoint, 10, 34.0 * damage_multiplier, 820.0, Color("b892ff"))
		"inferno_storm":
			_fire_flame_nova(0, {"count": 16, "speed": 460.0}, 24.0 * damage_multiplier, Color("ff8c42"))
			_fire_flame_nova(1, {"count": 16, "speed": 460.0}, 24.0 * damage_multiplier, Color("ff8c42"))
			_damage_area(midpoint, 210.0, 34.0 * damage_multiplier)
		"absolute_zero":
			_damage_area(players[0].global_position, 220.0, 30.0 * damage_multiplier, 0.3)
			_damage_area(players[1].global_position, 220.0, 30.0 * damage_multiplier, 0.3)
			_draw_ring(midpoint, 260.0, Color("8ecae6"), 10.0)
		"bright_moon_flurry":
			_swing_scythe(0, {"range": 260.0, "arc": 2.6}, 44.0 * damage_multiplier, Color("ef476f"))
			_swing_scythe(1, {"range": 260.0, "arc": 2.6}, 44.0 * damage_multiplier, Color("ef476f"))
		"bonded_mantra":
			for player in players:
				player.heal(10.0)
			_damage_along_chain(78.0, 34.0 * damage_multiplier, 1.0)
		"guided_bombardment":
			_fire_flame_nova(0, {"count": 12, "speed": 470.0}, 24.0 * damage_multiplier, Color("ff8c42"))
			_fire_flame_nova(1, {"count": 12, "speed": 470.0}, 24.0 * damage_multiplier, Color("ff8c42"))
			_fire_lightning(midpoint, 4, 22.0 * damage_multiplier, 520.0, Color("fff275"))
		"twilight_pursuit":
			_fire_lightning(players[0].global_position, 5, 26.0 * damage_multiplier, 600.0, Color("43d9ff"))
			_swing_scythe(1, {"range": 250.0, "arc": 2.2}, 40.0 * damage_multiplier, Color("ef476f"))
		"storm_cut_crescent":
			_swing_scythe(0, {"range": 260.0, "arc": 2.3}, 42.0 * damage_multiplier, Color("b892ff"))
			_swing_scythe(1, {"range": 260.0, "arc": 2.3}, 42.0 * damage_multiplier, Color("b892ff"))
			_fire_lightning(midpoint, 4, 20.0 * damage_multiplier, 480.0, Color("b892ff"))
		"sacred_flame_vow":
			for player in players:
				player.heal(9.0)
			_damage_area(midpoint, 240.0, 32.0 * damage_multiplier)
			_draw_ring(midpoint, 240.0, Color("ff8c42"), 9.0)
		"frost_shade":
			_swing_scythe(0, {"range": 250.0, "arc": 2.4}, 38.0 * damage_multiplier, Color("8ecae6"))
			_swing_scythe(1, {"range": 250.0, "arc": 2.4}, 38.0 * damage_multiplier, Color("8ecae6"))
			_damage_area(midpoint, 200.0, 20.0 * damage_multiplier, 0.35)


func clear_transients() -> void:
	for projectile in active_projectiles.duplicate():
		projectile.release()


func _acquire_projectile() -> HomingProjectile:
	var projectile: HomingProjectile
	if projectile_pool.is_empty():
		projectile = ProjectileScript.new() as HomingProjectile
		projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
		projectile.released.connect(_on_projectile_released)
		add_child(projectile)
	else:
		projectile = projectile_pool.pop_back()
	active_projectiles.append(projectile)
	return projectile


func _on_projectile_released(projectile: HomingProjectile) -> void:
	active_projectiles.erase(projectile)
	if projectile not in projectile_pool:
		projectile_pool.append(projectile)


func _fire_homing(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var target := spatial_grid.nearest(players[player_index].global_position, 700.0)
	if target == null:
		return
	var count := int(state["count"])
	for shot in count:
		var projectile := _acquire_projectile()
		projectile.global_position = players[player_index].global_position
		var spread := (float(shot) - float(count - 1) * 0.5) * 0.16
		projectile.setup(players[player_index].last_input.rotated(spread), target)
		projectile.spatial_grid = spatial_grid
		projectile.damage = damage
		projectile.speed = float(state["speed"])
		projectile.projectile_color = color


func _fire_lightning(origin: Vector2, jumps: int, damage: float, first_range: float, color: Color) -> void:
	var hit: Array[ChaserEnemy] = []
	var current_position := origin
	var search_range := first_range
	for jump in jumps:
		var target := spatial_grid.nearest(current_position, search_range, hit)
		if target == null:
			break
		_draw_lightning(current_position, target.global_position, color, 4.0)
		target.take_damage(damage * pow(0.82, jump))
		hit.append(target)
		current_position = target.global_position
		search_range = 210.0


func _fire_flame_nova(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var count := int(state["count"])
	var phase := elapsed * 0.7
	for shot in count:
		var direction := Vector2.from_angle(phase + TAU * float(shot) / float(count))
		var projectile := _acquire_projectile()
		projectile.global_position = players[player_index].global_position + direction * 22.0
		projectile.setup(direction, null)
		projectile.spatial_grid = spatial_grid
		projectile.homing_enabled = false
		projectile.damage = damage
		projectile.speed = float(state["speed"])
		# A narrow ember could pass cleanly through the gaps in the opening
		# ring, making Ignis survival depend heavily on random spawn angles.
		# The modestly wider hit disc preserves the radial gaps but makes close
		# interceptions reliable.
		projectile.radius = 9.0
		projectile.projectile_color = color
	_draw_ring(players[player_index].global_position, 40.0, color, 4.0)


func _fire_frost_ring(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var origin := players[player_index].global_position
	var radius := float(state["radius"])
	for enemy in spatial_grid.query_radius(origin, radius + 40.0):
		if origin.distance_to(enemy.global_position) <= radius + enemy.radius:
			enemy.take_damage(damage)
			if is_instance_valid(enemy) and not enemy.dead:
				enemy.apply_slow(1.25, float(state["slow"]))
	_draw_ring(origin, radius, color, 7.0)


func _swing_scythe(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var origin := players[player_index].global_position
	var direction := players[player_index].last_input.normalized()
	var attack_range := float(state["range"])
	var arc := float(state["arc"])
	for enemy in spatial_grid.query_radius(origin, attack_range + 40.0):
		var to_enemy := enemy.global_position - origin
		if to_enemy.length() <= attack_range + enemy.radius and absf(direction.angle_to(to_enemy.normalized())) <= arc * 0.5:
			enemy.take_damage(damage)
	_draw_scythe_arc(origin, direction.angle(), attack_range, arc, color)


func _fire_chain_pulse(state: Dictionary, damage: float) -> void:
	_damage_along_chain(float(state["width"]), damage, 1.0)


func _damage_area(center: Vector2, radius: float, damage: float, slow_multiplier: float = 1.0) -> void:
	for enemy in spatial_grid.query_radius(center, radius + 45.0):
		if center.distance_to(enemy.global_position) > radius + enemy.radius:
			continue
		enemy.take_damage(damage)
		if slow_multiplier < 1.0 and is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(1.8, slow_multiplier)


func _damage_along_chain(width: float, damage: float, slow_multiplier: float) -> void:
	var from := players[0].global_position
	var to := players[1].global_position
	var midpoint := (from + to) * 0.5
	var search_radius := from.distance_to(to) * 0.5 + width + 45.0
	for enemy in spatial_grid.query_radius(midpoint, search_radius):
		if _distance_to_segment(enemy.global_position, from, to) <= width + enemy.radius:
			enemy.take_damage(damage)
			if slow_multiplier < 1.0 and is_instance_valid(enemy) and not enemy.dead:
				enemy.apply_slow(1.8, slow_multiplier)
	_draw_chain_pulse(from, to, width)


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * ratio)


func _draw_lightning(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var bolt := Line2D.new()
	bolt.width = width
	bolt.default_color = color
	bolt.z_index = 3
	for index in 8:
		var ratio := float(index) / 7.0
		var point := from.lerp(to, ratio)
		if index > 0 and index < 7:
			point += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		bolt.add_point(point)
	add_child(bolt)
	_fade_and_free(bolt, 0.17)


func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var ring := Line2D.new()
	ring.position = center
	# Friendly area attacks were reading like persistent arena boundaries.
	# Keep their footprint visible, but subordinate them to enemy telegraphs.
	ring.width = clampf(width * 0.45, 2.0, 4.0)
	ring.default_color = Color(color, minf(color.a, 0.34))
	ring.z_index = 2
	ring.antialiased = true
	for index in 33:
		ring.add_point(Vector2.from_angle(TAU * float(index) / 32.0) * radius)
	add_child(ring)
	_fade_and_free(ring, 0.12)


func _draw_scythe_arc(center: Vector2, angle: float, radius: float, arc: float, color: Color) -> void:
	var slash := Line2D.new()
	slash.position = center
	slash.width = 12.0
	slash.default_color = color
	slash.z_index = 3
	for index in 19:
		slash.add_point(Vector2.from_angle(angle - arc * 0.5 + arc * float(index) / 18.0) * radius)
	add_child(slash)
	_fade_and_free(slash, 0.2)


func _draw_chain_pulse(from: Vector2, to: Vector2, width: float) -> void:
	var pulse := Line2D.new()
	pulse.width = width * 2.0
	pulse.default_color = Color(0.5, 0.93, 0.6, 0.32)
	pulse.z_index = 2
	pulse.add_point(from)
	pulse.add_point(to)
	add_child(pulse)
	_fade_and_free(pulse, 0.22)


func _fade_and_free(node: CanvasItem, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 0.0, duration)
	tween.tween_callback(node.queue_free)
