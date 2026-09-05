class_name WeaponController
extends Node2D

const ProjectileScript := preload("res://scripts/projectile.gd")
const CombatFlareScript := preload("res://scripts/effects/combat_flare.gd")
const MineScript := preload("res://scripts/proximity_mine.gd")

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
	# One roll per cast also covers delayed mines and secondary explosions.
	if owner_player.crit_chance > 0.0 and randf() < owner_player.crit_chance:
		damage *= ChainPlayer.CRIT_MULTIPLIER
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
		"orbit": _sweep_orbit(player_index, scaled, damage, color)
		"lance": _fire_lance(player_index, scaled, damage, color)
		"mine": _plant_mines(player_index, scaled, damage, color)
		"gravity": _collapse_gravity(player_index, scaled, damage, color)
		# Fused weapons. Each one changes the delivery, not just the numbers.
		"starpiercer": _fire_starpiercer(player_index, scaled, damage, color)
		"thunder_god": _call_thunder_god(player_index, scaled, damage, color)
		"supernova": _fire_supernova(player_index, scaled, damage, color)
		"absolute_zero": _freeze_absolute(player_index, scaled, damage, color)
		"black_moon": _swing_black_moon(player_index, scaled, damage, color)
		"stigmata": _burn_stigmata(scaled, damage)
		"celestial": _sweep_celestial(player_index, scaled, damage, color)
		"judgement": _fire_judgement(player_index, scaled, damage, color)
		"ruin_garden": _plant_ruin_garden(player_index, scaled, damage, color)
		"event_horizon": _collapse_event_horizon(player_index, scaled, damage, color)


## Resonance now sits behind two fused weapons rather than two tier-3 base
## ones, so it fires far later in a run and against far tougher enemies. The
## per-effect numbers below were written for the old gate; this scales all of
## them at once rather than rewriting twenty-five of them by hand.
const ENDGAME_SCALE := 2.2

## What separates a friendly area ring from an enemy telegraph is how long it
## stays, not how dim it is. Named so the hierarchy is asserted against these
## rather than against a colour someone might reasonably want to change.
const RING_HOLD := 0.07
const RING_FADE := 0.24


func perform_resonance(resonance: Dictionary, damage_multiplier: float) -> void:
	var resonance_id := String(resonance["id"])
	damage_multiplier *= ENDGAME_SCALE
	var midpoint := (players[0].global_position + players[1].global_position) * 0.5
	_play_resonance_flare(midpoint, resonance)
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
		"umbral_communion":
			for index in 2:
				_swing_scythe(index, {"range": 300.0, "arc": TAU}, 52.0 * damage_multiplier, Color("c77dff"))
				players[index].heal(12.0)
			_damage_along_chain(88.0, 40.0 * damage_multiplier, 1.0)
		"arcing_tempest":
			# Six lances from the midpoint, so there is no safe bearing at all.
			for step in 6:
				var heading := Vector2.from_angle(TAU * float(step) / 6.0)
				_lance_from(midpoint, heading, 620.0, 40.0, 46.0 * damage_multiplier, Color("caffbf"))
		"warding_garden":
			for index in 2:
				var centre := players[index].global_position
				for step in 5:
					var mine := MineScript.new() as ProximityMine
					mine.configure(38.0 * damage_multiplier, 110.0, Color("bdb2ff"))
					mine.spatial_grid = spatial_grid
					mine.detonated.connect(_on_mine_detonated)
					mine.global_position = centre + Vector2.from_angle(TAU * float(step) / 5.0) * 120.0
					add_child(mine)
				_damage_area(centre, 230.0, 26.0 * damage_multiplier, 0.2)
			_draw_ring(midpoint, 300.0, Color("bdb2ff"), 8.0)
		"singularity":
			for enemy in spatial_grid.query_radius(midpoint, 420.0):
				var offset := midpoint - enemy.global_position
				if offset.length() > 420.0 + enemy.radius:
					continue
				if not enemy.boss:
					enemy.position += offset.normalized() * minf(320.0, offset.length())
				enemy.take_damage(30.0 * damage_multiplier)
			_damage_area(midpoint, 190.0, 58.0 * damage_multiplier)
			_draw_ring(midpoint, 420.0, Color("ff7bd5"), 4.0)
			_draw_ring(midpoint, 190.0, Color("ff7bd5"), 12.0)
		"frost_shade":
			_swing_scythe(0, {"range": 250.0, "arc": 2.4}, 38.0 * damage_multiplier, Color("8ecae6"))
			_swing_scythe(1, {"range": 250.0, "arc": 2.4}, 38.0 * damage_multiplier, Color("8ecae6"))
			_damage_area(midpoint, 200.0, 20.0 * damage_multiplier, 0.35)


func _play_resonance_flare(center: Vector2, resonance: Dictionary) -> void:
	var tag_colors := {
		"tracking": Color("43d9ff"), "lightning": Color("b892ff"),
		"projectile": Color("43d9ff"), "storm": Color("b892ff"),
		"arcane": Color("8ecae6"), "chain": Color("80ed99"),
		"fire": Color("ff8c42"), "frost": Color("8ecae6"),
		"shadow": Color("ef476f"), "tether": Color("80ed99"),
		"aura": Color("e4c1f9"), "melee": Color("ef476f"),
		"holy": Color("fff275"), "control": Color("8ecae6"),
		"burst": Color("ff8c42"), "arc": Color("fff275"),
	}
	var requirements: Array = resonance["requires"]
	_spawn_combat_flare(center, tag_colors.get(String(requirements[0]), Color("43d9ff")), tag_colors.get(String(requirements[1]), Color("fff275")), 165.0, 0.5)


func play_boss_flare(center: Vector2, enraged := false) -> void:
	_spawn_combat_flare(center, Color("ff334f") if enraged else Color("c1121f"), Color("fff275"), 235.0 if enraged else 205.0, 0.72)


func _spawn_combat_flare(center: Vector2, primary: Color, secondary: Color, radius: float, lifetime: float) -> void:
	var flare := CombatFlareScript.new()
	flare.setup(center, primary, secondary, radius, lifetime)
	add_child(flare)


func clear_transients() -> void:
	for projectile in active_projectiles.duplicate():
		projectile.release()
	# Planted mines outlive the cast that placed them, so a restart or a test
	# teardown has to sweep them or they detonate into the next run.
	for child in get_children():
		var mine := child as ProximityMine
		if mine != null:
			mine.queue_free()


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


## Where a directional weapon should point.
##
## These used to fire along the survivor's movement direction, which asked the
## pair to steer, keep the chain in range and aim, all at once, with no separate
## aiming control to do it with. Running away from something meant shooting away
## from it. They now aim themselves at the nearest thing in range and only fall
## back to the movement direction when the field is empty, so the weapon's shape
## is still the thing that defines it — a cone is still a cone, a lance is still
## a line — but pointing it is no longer a second job.
func _aim_direction(player_index: int, reach: float) -> Vector2:
	var origin := players[player_index].global_position
	var target := spatial_grid.nearest(origin, reach)
	if target != null:
		return origin.direction_to(target.global_position)
	var fallback := players[player_index].last_input
	return fallback.normalized() if fallback.length_squared() > 0.001 else Vector2.RIGHT


func _fire_homing(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var target := spatial_grid.nearest(players[player_index].global_position, 700.0)
	if target == null:
		return
	var count := int(state["count"])
	for shot in count:
		var projectile := _acquire_projectile()
		projectile.global_position = players[player_index].global_position
		var spread := (float(shot) - float(count - 1) * 0.5) * 0.16
		projectile.setup(_aim_direction(player_index, 700.0).rotated(spread), target)
		projectile.spatial_grid = spatial_grid
		projectile.damage = damage
		projectile.speed = float(state["speed"])
		projectile.projectile_color = color
		projectile.remaining_hits = 1 + players[player_index].pierce


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
		projectile.remaining_hits = 1 + players[player_index].pierce
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
	var attack_range := float(state["range"])
	var direction := _aim_direction(player_index, attack_range)
	var arc := float(state["arc"])
	for enemy in spatial_grid.query_radius(origin, attack_range + 40.0):
		var to_enemy := enemy.global_position - origin
		if to_enemy.length() <= attack_range + enemy.radius and absf(direction.angle_to(to_enemy.normalized())) <= arc * 0.5:
			enemy.take_damage(damage)
	_draw_scythe_arc(origin, direction.angle(), attack_range, arc, color)


func _fire_chain_pulse(state: Dictionary, damage: float) -> void:
	_damage_along_chain(float(state["width"]), damage, 1.0)


## Shards riding a circle around their owner. The angle comes from run time
## rather than from a stored rotation, so the ring keeps turning between casts
## and two consecutive sweeps never hit the same arc — which is what makes it
## read as an orbit rather than as a pulsing ring.
func _sweep_orbit(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var centre := players[player_index].global_position
	var radius := float(state["radius"])
	var shards := maxi(1, int(state["count"]))
	var phase := elapsed * float(state.get("speed", 2.4))
	for index in shards:
		var angle := phase + TAU * float(index) / float(shards)
		var point := centre + Vector2.from_angle(angle) * radius
		_damage_area(point, 26.0, damage)
		_draw_ring(point, 15.0, color, 5.0)
	_draw_ring(centre, radius, Color(color, 0.5), 2.0)


## A straight line that reaches much further than anything else in the roster
## and does not care how many bodies are between the two ends of it.
func _fire_lance(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_lance_from(
		players[player_index].global_position,
		_aim_direction(player_index, float(state["range"])),
		float(state["range"]), float(state["width"]), damage, color
	)


## Ordnance left behind rather than fired forward: the pair's own path becomes
## the trap. Mines arm on a delay so they cannot be used as an instant nova.
func _plant_mines(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var count := maxi(1, int(state["count"]))
	var radius := float(state["radius"])
	# Laid toward whatever is closing in rather than exactly underfoot: a trap
	# you have to walk backwards over is a trap you rarely get to use.
	var lead := _aim_direction(player_index, 460.0) * 70.0
	for index in count:
		var offset := lead if index == 0 else lead + Vector2.from_angle(randf() * TAU) * randf_range(30.0, 90.0)
		var mine := MineScript.new() as ProximityMine
		mine.configure(damage, radius, color)
		mine.detonated.connect(_on_mine_detonated)
		mine.spatial_grid = spatial_grid
		mine.global_position = players[player_index].global_position + offset
		add_child(mine)


func _on_mine_detonated(centre: Vector2, damage: float, radius: float, color: Color) -> void:
	_damage_area(centre, radius, damage)
	_draw_ring(centre, radius, color, 6.0)
	_spawn_combat_flare(centre, color, color.lightened(0.4), radius * 0.5, 0.22)


## Drags everything in range toward one point before hitting it, which turns a
## spread-out ring of enemies into a single cluster the rest of the pair's
## weapons can then clear.
func _collapse_gravity(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var centre := players[player_index].global_position
	var radius := float(state["radius"])
	var pull := float(state.get("pull", 160.0))
	for enemy in spatial_grid.query_radius(centre, radius + 45.0):
		var offset := centre - enemy.global_position
		var distance := offset.length()
		if distance > radius + enemy.radius:
			continue
		if enemy.boss:
			# A boss that can be vacuumed across the arena would trivialise the
			# one fight the whole run builds toward.
			enemy.take_damage(damage)
			continue
		enemy.position += offset.normalized() * minf(pull, distance)
		enemy.take_damage(damage)
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(1.2, 0.55)
	_draw_ring(centre, radius, color, 3.0)
	_draw_ring(centre, radius * 0.35, Color(color, 0.85), 5.0)


## --- fused weapons -------------------------------------------------------
##
## The base forms all answer "how do I hit the thing in front of me". The fused
## forms answer "how do I stop being surrounded", which is the problem the late
## game actually poses.


## Homing volley plus the lance it grew out of: the bolts still seek, and the
## line they are fired along is itself lethal.
func _fire_starpiercer(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_fire_homing(player_index, state, damage, color)
	_fire_lance(player_index, state, damage * 0.75, color.lightened(0.3))


## The chain is gone. Everything inside the radius is struck in the same
## instant, which is what a chain lightning weapon has always wanted to be.
func _call_thunder_god(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var origin := players[player_index].global_position
	var reach := float(state["range"])
	var struck := 0
	for enemy in spatial_grid.query_radius(origin, reach):
		if origin.distance_to(enemy.global_position) > reach:
			continue
		_draw_lightning(origin, enemy.global_position, color, 3.0)
		enemy.take_damage(damage)
		struck += 1
		if struck >= 24:
			# A cap on the drawn bolts only; a screenful of lines stops reading
			# as lightning and starts reading as static.
			break
	_draw_ring(origin, reach, Color(color, 0.35), 3.0)


## Scatter, then collapse: the embers go out and the ground they left goes up.
func _fire_supernova(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_fire_flame_nova(player_index, state, damage, color)
	var centre := players[player_index].global_position
	var radius := float(state["radius"])
	var blast := func() -> void:
		if not is_inside_tree():
			return
		_damage_area(centre, radius, damage * 1.6)
		_draw_ring(centre, radius, color.lightened(0.2), 10.0)
		_spawn_combat_flare(centre, color, color.lightened(0.5), radius * 0.6, 0.3)
	get_tree().create_timer(0.45).timeout.connect(blast)


## Freezes rather than slows, and anything already frozen is shattered instead
## of merely hit again.
func _freeze_absolute(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var centre := players[player_index].global_position
	var radius := float(state["radius"])
	for enemy in spatial_grid.query_radius(centre, radius + 45.0):
		if centre.distance_to(enemy.global_position) > radius + enemy.radius:
			continue
		var already_frozen := enemy.slow_timer > 0.0
		enemy.take_damage(damage * (2.4 if already_frozen else 1.0))
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(2.4, float(state["slow"]))
	_draw_ring(centre, radius, color, 9.0)
	_draw_ring(centre, radius * 0.55, Color(color, 0.7), 4.0)


## No facing requirement any more: two full circles around the swinger.
func _swing_black_moon(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var full := state.duplicate()
	full["arc"] = TAU
	_swing_scythe(player_index, full, damage, color)
	var second := func() -> void:
		if is_inside_tree():
			_swing_scythe(player_index, full, damage, color.darkened(0.2))
	get_tree().create_timer(0.18).timeout.connect(second)


## The chain itself burns, and what it burns feeds both survivors.
func _burn_stigmata(state: Dictionary, damage: float) -> void:
	_damage_along_chain(float(state["width"]), damage, 1.0)
	for player in players:
		player.heal(float(state.get("heal", 3.0)))


## Two rings turning opposite ways, so there is no gap to walk through.
func _sweep_celestial(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_sweep_orbit(player_index, state, damage, color)
	var inner := state.duplicate()
	inner["radius"] = float(state["radius"]) * 0.55
	inner["speed"] = -float(state.get("speed", 2.9)) * 1.4
	_sweep_orbit(player_index, inner, damage, color.lightened(0.25))


## Forward and both flanks at once, so being flanked stops being a problem.
func _fire_judgement(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	# Aimed once and then fanned, rather than three separate lookups: the three
	# beams have to form one fan around the same target or it reads as noise.
	var heading := _aim_direction(player_index, float(state["range"]))
	var origin := players[player_index].global_position
	for offset in [0.0, TAU * 0.33, -TAU * 0.33]:
		_lance_from(origin, heading.rotated(offset), float(state["range"]), float(state["width"]), damage, color)


## A whole minefield in one cast, laid in a ring around the planter.
func _plant_ruin_garden(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var count := maxi(1, int(state["count"]))
	var centre := players[player_index].global_position
	for index in count:
		var angle := TAU * float(index) / float(count) + randf() * 0.3
		var mine := MineScript.new() as ProximityMine
		mine.configure(damage, float(state["radius"]), color)
		mine.spatial_grid = spatial_grid
		mine.detonated.connect(_on_mine_detonated)
		mine.global_position = centre + Vector2.from_angle(angle) * 105.0
		add_child(mine)


## Pull, collapse, and then collapse again on the cluster the first one made.
func _collapse_event_horizon(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_collapse_gravity(player_index, state, damage, color)
	var centre := players[player_index].global_position
	var radius := float(state["radius"])
	var implode := func() -> void:
		if not is_inside_tree():
			return
		_damage_area(centre, radius * 0.7, damage * 2.0)
		_draw_ring(centre, radius * 0.7, color.lightened(0.35), 11.0)
		_spawn_combat_flare(centre, color, Color.WHITE, radius * 0.4, 0.26)
	get_tree().create_timer(0.35).timeout.connect(implode)


## The lance shape decoupled from a survivor, so resonances can fire one from
## anywhere in any direction.
func _lance_from(origin: Vector2, heading: Vector2, reach: float, width: float, damage: float, color: Color) -> void:
	var tip := origin + heading.normalized() * reach
	var midpoint := (origin + tip) * 0.5
	var half_width := width * 0.5
	for enemy in spatial_grid.query_radius(midpoint, reach * 0.5 + half_width + 45.0):
		if _distance_to_segment(enemy.global_position, origin, tip) <= half_width + enemy.radius:
			enemy.take_damage(damage)
	_draw_beam(origin, tip, color, width)


## A ring that grows from nothing to `radius` and fades as it goes. Field items
## use it as their signature: they are rare, they change the board, and they
## should look like it. `inward` reverses the motion, which is what the magnet
## needs — its ring collapses toward the pair rather than expanding from them.
func play_shockwave(centre: Vector2, radius: float, color: Color, duration: float, inward := false) -> void:
	var wave := Line2D.new()
	wave.position = centre
	wave.width = 14.0
	wave.default_color = Color(color, 0.9)
	wave.z_index = 4
	wave.antialiased = true
	for index in 65:
		wave.add_point(Vector2.from_angle(TAU * float(index) / 64.0) * radius)
	wave.scale = Vector2.ONE * (1.0 if inward else 0.04)
	add_child(wave)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector2.ONE * (0.04 if inward else 1.0), duration) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave, "width", 3.0, duration)
	tween.tween_property(wave, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(wave.queue_free)


## Spokes thrown outward from a point. Only the purge uses this, and only
## because a screen-clear that looks the same as a nova is a wasted moment.
func play_purge_rays(centre: Vector2, radius: float, color: Color) -> void:
	for index in 16:
		var angle := TAU * float(index) / 16.0 + randf() * 0.12
		var ray := Line2D.new()
		ray.position = centre
		ray.width = 9.0
		ray.default_color = Color(color.lightened(0.4), 0.85)
		ray.z_index = 4
		ray.antialiased = true
		ray.add_point(Vector2.from_angle(angle) * radius * 0.18)
		ray.add_point(Vector2.from_angle(angle) * radius * 1.15)
		ray.scale = Vector2(0.15, 0.15)
		add_child(ray)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(ray, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(ray, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(ray.queue_free)


func _draw_beam(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	# A soft outer pass under a bright core: the halo says where the beam is,
	# the core says it landed. One flat line at 70% did neither well.
	var halo := Line2D.new()
	halo.width = width * 2.1
	halo.default_color = Color(color, 0.26)
	halo.z_index = 2
	halo.antialiased = true
	halo.add_point(from)
	halo.add_point(to)
	add_child(halo)
	_flash_and_free(halo, 0.08, 0.26)

	var beam := Line2D.new()
	beam.width = width
	beam.default_color = Color(color.lightened(0.35), 0.95)
	beam.z_index = 3
	beam.antialiased = true
	beam.add_point(from)
	beam.add_point(to)
	add_child(beam)
	_flash_and_free(beam, 0.09, 0.2)


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
	bolt.width = width * 1.5
	bolt.default_color = color.lightened(0.2)
	bolt.z_index = 3
	bolt.antialiased = true
	for index in 8:
		var ratio := float(index) / 7.0
		var point := from.lerp(to, ratio)
		if index > 0 and index < 7:
			point += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		bolt.add_point(point)
	add_child(bolt)
	_flash_and_free(bolt, 0.06, 0.22)


func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var ring := Line2D.new()
	ring.position = center
	# Friendly area attacks were reading like persistent arena boundaries.
	# Keep their footprint visible, but subordinate them to enemy telegraphs.
	# Friendly rings were dimmed to 34% and 4px to stop them reading as arena
	# boundaries. That worked and then some — they became invisible. They are
	# legible again; what keeps them distinct from an enemy telegraph is that
	# they flash once and expand away, while a telegraph pulses and fills.
	ring.width = clampf(width * 0.8, 3.0, 9.0)
	ring.default_color = Color(color, minf(color.a, 0.85))
	ring.z_index = 2
	ring.antialiased = true
	for index in 41:
		ring.add_point(Vector2.from_angle(TAU * float(index) / 40.0) * radius)
	add_child(ring)
	_flash_and_free(ring, RING_HOLD, RING_FADE)
	var grow := create_tween()
	grow.tween_property(ring, "scale", Vector2.ONE * 1.12, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _draw_scythe_arc(center: Vector2, angle: float, radius: float, arc: float, color: Color) -> void:
	var slash := Line2D.new()
	slash.position = center
	slash.width = 16.0
	slash.default_color = color.lightened(0.25)
	slash.z_index = 3
	slash.antialiased = true
	for index in 19:
		slash.add_point(Vector2.from_angle(angle - arc * 0.5 + arc * float(index) / 18.0) * radius)
	add_child(slash)
	_flash_and_free(slash, 0.1, 0.26)


func _draw_chain_pulse(from: Vector2, to: Vector2, width: float) -> void:
	var pulse := Line2D.new()
	pulse.width = width * 2.0
	pulse.default_color = Color(0.55, 0.98, 0.66, 0.72)
	pulse.z_index = 2
	pulse.add_point(from)
	pulse.add_point(to)
	add_child(pulse)
	_flash_and_free(pulse, 0.1, 0.3)


## Attack visuals were dying on a straight fade that began the instant they
## appeared, over 0.12-0.22s. Half of that is spent under 50% opacity, so a
## weapon firing every second read as a faint smear rather than as a hit.
##
## They now hold at full strength for a beat and only then fall off, on an eased
## curve. Same budget of screen time, but the part the eye registers is at full
## opacity instead of averaged away.
func _flash_and_free(node: CanvasItem, hold: float, fade: float) -> void:
	var tween := create_tween()
	tween.tween_interval(hold)
	tween.tween_property(node, "modulate:a", 0.0, fade).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(node.queue_free)


func _fade_and_free(node: CanvasItem, duration: float) -> void:
	_flash_and_free(node, duration * 0.55, duration)
