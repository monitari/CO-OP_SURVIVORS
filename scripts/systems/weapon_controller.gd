class_name WeaponController
extends Node2D

const ProjectileScript := preload("res://scripts/entities/projectile.gd")
const MilkPoolScript := preload("res://scripts/effects/milk_pool.gd")
const CombatFlareScript := preload("res://scripts/effects/combat_flare.gd")
const MineScript := preload("res://scripts/entities/proximity_mine.gd")
const WeaponFieldScript := preload("res://scripts/effects/weapon_field.gd")
const ChainStrikeScript := preload("res://scripts/effects/chain_strike.gd")
const LanceStrikeScript := preload("res://scripts/effects/lance_strike.gd")
const ReturningToyScript := preload("res://scripts/effects/returning_toy.gd")

signal cue_requested(cue_id: String)

var players: Array[ChainPlayer] = []
var weapon_loadouts: Array = []
var spatial_grid: EnemySpatialGrid
var elapsed := 0.0
## Kept current by main every physics tick. 결속 파동 is the one weapon whose
## output depends on how the pair is standing, so it needs the same two numbers
## the HUD reads rather than a second opinion about them.
var chain_length := 370.0
var chain_tension := 0.0
var active_projectiles: Array[HomingProjectile] = []
var projectile_pool: Array[HomingProjectile] = []
var sustained_fields: Dictionary = {}
## Main's own list of live hostile shots, shared rather than copied. Four
## weapons are allowed to knock them down — the crescent that sweeps a sector,
## the tether that is a line between the pair, the ring of shards, and the mine
## that goes off — and all four are things that already occupy space rather than
## fire past it, which is what makes shooting down a shot read as earned.
var enemy_shots: Array = []
const MINE_CAP_PER_PLAYER := 10


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
	var play_cast_cue := true
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
	scaled["pull"] = float(state.get("pull", 0.0)) * owner_player.area
	scaled["cast_range"] = float(state.get("cast_range", 0.0)) * owner_player.area
	scaled["duration"] = owner_player.duration
	match weapon_id:
		"boomerang": _throw_toy(player_index, scaled, damage, color, 0.35)
		"skipping_stone": _throw_toy(player_index, scaled, damage, color, TAU / maxf(1.0, float(scaled["count"])))
		"milk", "cream_tide": _spill_milk(player_index, scaled, damage, color)
		"homing": play_cast_cue = _fire_homing(player_index, scaled, damage, color)
		"lightning": play_cast_cue = _fire_lightning(owner_player.global_position, int(state["jumps"]), damage, float(scaled["range"]), color) > 0
		"flame": _fire_flame_nova(player_index, scaled, damage, color)
		"frost": play_cast_cue = _ensure_frost_aura(player_index, weapon_slot, scaled, damage, color)
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
		"absolute_zero": play_cast_cue = _ensure_absolute_aura(player_index, weapon_slot, scaled, damage, color)
		"black_moon": _swing_black_moon(player_index, scaled, damage, color)
		"stigmata": _burn_stigmata(scaled, damage)
		"celestial": _sweep_celestial(player_index, scaled, damage, color)
		"judgement": _fire_judgement(player_index, scaled, damage, color)
		"ruin_garden": _plant_ruin_garden(player_index, scaled, damage, color)
		"event_horizon": _collapse_event_horizon(player_index, scaled, damage, color)
		# Dual fusions consume two maxed weapons and retain both deliveries. Their
		# catalog numbers are deliberately one shared damage budget; each half gets
		# a fraction so combining weapons does not simply double endgame DPS.
		"comet_storm": _cast_comet_storm(player_index, scaled, damage, color)
		"cream_volcano": _cast_cream_volcano(player_index, scaled, damage, color)
		"glacial_satellite": _cast_glacial_satellite(player_index, weapon_slot, scaled, damage, color)
		"eclipse_lance": _cast_eclipse_lance(player_index, scaled, damage, color)
		"singularity_mine": _cast_singularity_mine(player_index, scaled, damage, color)
		"return_bell": _cast_return_bell(player_index, scaled, damage, color)
	if play_cast_cue:
		cue_requested.emit("weapon_" + weapon_id)


## 생선 부메랑, and the fused form that throws several at once. `fan` is the
## angle between consecutive toys: a small spread for the base weapon, a full
## circle for 물수제비 물고기, which is the whole difference between them.
func _throw_toy(player_index: int, state: Dictionary, damage: float, color: Color, fan: float) -> void:
	var owner_player := players[player_index]
	var count := maxi(1, int(state.get("count", 1)))
	var aim := _aim_direction(player_index, float(state["range"]))
	for index in count:
		var toy = ReturningToyScript.new()
		toy.anchor = owner_player
		toy.grid = spatial_grid
		toy.damage = damage
		toy.reach = float(state["range"])
		toy.tint = color
		toy.heading = aim.rotated((float(index) - float(count - 1) * 0.5) * fan)
		add_child(toy)
		toy.global_position = owner_player.global_position


## 우유 흩뿌리기. Scattered around the caster rather than aimed: where the milk
## lands is not a decision the weapon makes, which is why the survivor's own
## position is the only thing that decides whether a cast was worth anything.
func _spill_milk(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var origin := players[player_index].global_position
	var spread := float(state["range"])
	var count := maxi(1, int(state.get("count", 1)))
	for index in count:
		# The first one lands underfoot, so a cast is never entirely wasted by
		# an unlucky scatter and the survivor always has one patch of ground
		# they know is theirs. The rest divide the circle and are then jittered,
		# so a cast covers the area around the pair rather than clumping on one
		# bearing — and never lands in the same pattern twice.
		var at := origin
		if index > 0:
			var angle := TAU * (float(index) + randf() * 0.7) / float(count)
			at = origin + Vector2.from_angle(angle) * spread * sqrt(randf_range(0.16, 1.0))
		var pool := MilkPoolScript.new() as MilkPool
		pool.configure(at, spatial_grid, damage, float(state["radius"]),
			float(state.get("slow", 0.55)), color, 4.6 * float(state.get("duration", 1.0)))
		add_child(pool)
	cue_requested.emit("weapon_milk")


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


## Treasure-driven dash attack, resolved through the same grid and feedback
## stack as the regular weapons.
func perform_pounce(center: Vector2, damage: float, color: Color) -> void:
	_damage_area(center, 112.0, damage)
	_draw_ring(center, 112.0, color, 9.0)
	_spawn_combat_flare(center, color, Color.WHITE, 54.0, 0.24)


func _spawn_combat_flare(center: Vector2, primary: Color, secondary: Color, radius: float, lifetime: float) -> void:
	var flare := CombatFlareScript.new()
	flare.setup(center, primary, secondary, radius, lifetime)
	add_child(flare)


## The chain itself as a weapon, for 사슬 결계. Public because it is a field
## item doing it, not a weapon cast — nothing about it belongs in the loadout.
func burn_chain(width: float, damage: float) -> void:
	_damage_along_chain(width, damage, 1.0)


func clear_transients() -> void:
	for projectile in active_projectiles.duplicate():
		projectile.release()
	# Planted mines outlive the cast that placed them, so a restart or a test
	# teardown has to sweep them or they detonate into the next run.
	for child in get_children():
		if child.get_script() == ReturningToyScript:
			child.set_physics_process(false)
			child.queue_free()
		var mine := child as ProximityMine
		if mine != null:
			mine.queue_free()
		var field = child if child.get_script() == WeaponFieldScript else null
		if field != null:
			field.queue_free()
	sustained_fields.clear()


func clear_sustained_for_player(player_index: int) -> void:
	# Fusion may replace a frost aura or remove a lower weapon slot, invalidating
	# every slot-key that follows it. Rebuild only this survivor's persistent
	# fields on their next cast instead of leaving a retired aura alive.
	for key: String in sustained_fields.keys():
		var parts := key.split(":")
		if parts.size() < 3 or int(parts[1]) != player_index:
			continue
		var field = sustained_fields[key]
		if is_instance_valid(field):
			field.queue_free()
		sustained_fields.erase(key)


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
	# The smoothed heading rather than the raw input: with nothing to shoot at,
	# a weapon that snapped between eight compass directions as the stick moved
	# looked like a bug even though nothing was being hit either way.
	var fallback := players[player_index].facing
	return fallback.normalized() if fallback.length_squared() > 0.001 else Vector2.RIGHT


func _fire_homing(player_index: int, state: Dictionary, damage: float, color: Color) -> bool:
	var target := spatial_grid.nearest(players[player_index].global_position, 700.0)
	if target == null:
		return false
	var count := int(state["count"])
	for shot in count:
		var projectile := _acquire_projectile()
		projectile.global_position = players[player_index].global_position
		var spread := (float(shot) - float(count - 1) * 0.5) * 0.16
		projectile.setup(_aim_direction(player_index, 700.0).rotated(spread), target)
		projectile.style = "star"
		projectile.spatial_grid = spatial_grid
		projectile.damage = damage
		projectile.speed = float(state["speed"])
		projectile.lifetime *= float(state.get("duration", 1.0))
		projectile.spawn_lifetime = projectile.lifetime
		projectile.projectile_color = color
		projectile.remaining_hits = 1 + players[player_index].pierce
	return true


func _fire_lightning(origin: Vector2, jumps: int, damage: float, first_range: float, color: Color) -> int:
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
	return hit.size()


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
		projectile.lifetime *= float(state.get("duration", 1.0))
		projectile.spawn_lifetime = projectile.lifetime
		# A narrow ember could pass cleanly through the gaps in the opening
		# ring, making Ignis survival depend heavily on random spawn angles.
		# The modestly wider hit disc preserves the radial gaps but makes close
		# interceptions reliable.
		projectile.radius = 9.0
		projectile.style = "ember"
		projectile.projectile_color = color
	_draw_ring(players[player_index].global_position, 40.0, color, 4.0)


func _ensure_frost_aura(player_index: int, weapon_slot: int, state: Dictionary, damage: float, color: Color) -> bool:
	var key := "frost:%d:%d" % [player_index, weapon_slot]
	var existing = sustained_fields.get(key)
	if is_instance_valid(existing):
		existing.refresh_frost(damage, float(state["radius"]), float(state["slow"]), color)
		return false
	var field = WeaponFieldScript.new()
	field.configure_frost(players[player_index], spatial_grid, damage, float(state["radius"]), float(state["slow"]), color)
	add_child(field)
	sustained_fields[key] = field
	return true


func _ensure_absolute_aura(player_index: int, weapon_slot: int, state: Dictionary, damage: float, color: Color) -> bool:
	var key := "absolute:%d:%d" % [player_index, weapon_slot]
	var existing = sustained_fields.get(key)
	if is_instance_valid(existing):
		existing.refresh_frost(damage, float(state["radius"]), float(state["slow"]), color, true)
		return false
	var field = WeaponFieldScript.new()
	field.configure_frost(players[player_index], spatial_grid, damage, float(state["radius"]), float(state["slow"]), color, true)
	add_child(field)
	sustained_fields[key] = field
	return true


func _swing_scythe(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var origin := players[player_index].global_position
	var attack_range := float(state["range"])
	var direction := _aim_direction(player_index, attack_range)
	var field = WeaponFieldScript.new()
	field.configure_scythe(origin, direction, spatial_grid, damage, attack_range, float(state["arc"]), color)
	field.enemy_shots = enemy_shots
	add_child(field)


## The tether weapon is the only one that cares how the pair is standing, and
## it now says so: a slack chain is a short, weak line and a stretched one is a
## long, hot one. That makes 느슨한 족쇄 — the upgrade that lengthens the leash —
## a damage upgrade as well as a freedom one, and it puts the weapon on the same
## side as the overcharge mechanic instead of ignoring it.
const CHAIN_TENSION_BONUS := 0.6


func _fire_chain_pulse(state: Dictionary, damage: float) -> void:
	var width := float(state["width"])
	_damage_along_chain(width, damage * (1.0 + chain_tension * CHAIN_TENSION_BONUS), 1.0)
	EnemyProjectile.break_along(enemy_shots, players[0].global_position, players[1].global_position, width)
	cue_requested.emit("chain_snap")


## Shards riding a circle around their owner. The angle comes from run time
## rather than from a stored rotation, so the ring keeps turning between casts
## and two consecutive sweeps never hit the same arc — which is what makes it
## read as an orbit rather than as a pulsing ring.
func _sweep_orbit(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var field = WeaponFieldScript.new()
	field.configure_orbit(players[player_index], spatial_grid, damage, float(state["radius"]), maxi(1, int(state["count"])), float(state.get("speed", 2.4)), color, float(state.get("duration", 1.0)))
	field.enemy_shots = enemy_shots
	add_child(field)


## A straight line that reaches much further than anything else in the roster
## and does not care how many bodies are between the two ends of it.
## A straight line that reaches much further than anything else in the roster
## and does not care how many bodies are between the two ends of it. 분광 splits
## it into parallel beams rather than widening one, so the upgrade covers a
## front instead of just thickening a stripe.
func _fire_lance(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var origin := players[player_index].global_position
	var reach := float(state["range"])
	var width := float(state["width"])
	var beams := maxi(1, int(state.get("beams", 1)))
	for heading in _lance_headings(player_index, reach, beams):
		_lance_from(origin, heading, reach, width, damage, color)


## Each beam rolls a different target from the current field. Extra beams only
## use a small fallback fan if there are fewer enemies than beams, so the
## multi-beam upgrade can never collapse back into parallel copies.
func _lance_headings(player_index: int, reach: float, beam_count: int) -> Array[Vector2]:
	var origin := players[player_index].global_position
	var candidates: Array[ChaserEnemy] = []
	for enemy in spatial_grid.query_radius(origin, reach + 45.0):
		if is_instance_valid(enemy) and not enemy.dead and origin.distance_to(enemy.global_position) <= reach + enemy.radius:
			candidates.append(enemy)
	candidates.shuffle()
	var headings: Array[Vector2] = []
	for index in mini(beam_count, candidates.size()):
		headings.append(origin.direction_to(candidates[index].global_position))
	var fallback := _aim_direction(player_index, reach)
	while headings.size() < beam_count:
		var index := headings.size()
		var ratio := 0.5 if beam_count <= 1 else float(index) / float(beam_count - 1)
		headings.append(fallback.rotated(lerpf(-0.34, 0.34, ratio)))
	return headings


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
		_spawn_mine(player_index, players[player_index].global_position + offset, damage * 1.45, radius * 1.15, color)


func _spawn_mine(player_index: int, at: Vector2, damage: float, radius: float, color: Color) -> void:
	var owned: Array[ProximityMine] = []
	for child in get_children():
		var carried := child as ProximityMine
		if carried != null and carried.owner_index == player_index and not carried.spent:
			owned.append(carried)
	if owned.size() >= MINE_CAP_PER_PLAYER:
		owned[0].force_detonate()
	var mine := MineScript.new() as ProximityMine
	mine.configure(damage, radius, color, player_index)
	mine.detonated.connect(_on_mine_detonated)
	mine.spatial_grid = spatial_grid
	mine.global_position = at
	add_child(mine)


func _on_mine_detonated(centre: Vector2, damage: float, radius: float, color: Color) -> void:
	cue_requested.emit("mine_blast")
	_damage_area(centre, radius, damage)
	EnemyProjectile.break_within(enemy_shots, centre, radius)
	_draw_ring(centre, radius, color, 6.0)
	_spawn_combat_flare(centre, color, color.lightened(0.4), radius * 0.5, 0.22)


## Drags everything in range toward one point before hitting it, which turns a
## spread-out ring of enemies into a single cluster the rest of the pair's
## weapons can then clear.
func _collapse_gravity(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_collapse_gravity_at(_gravity_centre(player_index, state), player_index, state, damage, color)


func _collapse_gravity_at(centre: Vector2, _player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var radius := float(state["radius"])
	var pull := float(state.get("pull", 160.0))
	var field = WeaponFieldScript.new()
	field.configure_gravity(centre, spatial_grid, damage, radius, pull, color, func() -> void: cue_requested.emit("gravity_collapse"))
	add_child(field)
	cue_requested.emit("gravity_pull")


## Preferred stand-off for the collapse, as a fraction of the cast range.
const GRAVITY_STAND_OFF := 0.55
## At most this many bodies are tried as the centre of the well. Every candidate
## is scored against every body in range, so an uncapped search would be
## quadratic in a crowd; a stride across the list samples the shape of it for a
## fixed cost instead.
const GRAVITY_SAMPLES := 20


## Where the collapse actually lands.
##
## Centring it on the caster made a control weapon into a panic button: it only
## helped once things had reached you, and dragging every nearby enemy into a
## tight ball on top of your own body was the last thing you wanted at that
## moment. Picking the farthest body in range fixed that and overshot — the well
## opened behind the crowd that was already on its way in, so the weapon spent
## its cooldown tidying up the back of the field.
##
## It now looks for the best place rather than the extreme one: how much a well
## there would actually catch, tempered by how well placed it is. A slightly
## smaller cluster out in front of the pair beats a bigger one underfoot or one
## sitting at the very edge of the cast. With nothing in range it falls back to a
## point along the aim direction rather than snapping home, so the weapon never
## behaves like the old version by accident.
func _gravity_centre(player_index: int, state: Dictionary) -> Vector2:
	var origin := players[player_index].global_position
	var cast_range := float(state.get("cast_range", 520.0))
	var radius := float(state["radius"])
	var preferred := cast_range * GRAVITY_STAND_OFF
	var candidates := spatial_grid.query_radius(origin, cast_range + 45.0)
	var stride := maxi(1, candidates.size() / GRAVITY_SAMPLES)
	var radius_squared := radius * radius
	var best := Vector2.ZERO
	var best_score := 0.0
	for index in range(0, candidates.size(), stride):
		var enemy := candidates[index] as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var at := enemy.global_position
		var distance := origin.distance_to(at)
		if distance > cast_range:
			continue
		var caught := 0
		for other in candidates:
			var body := other as ChaserEnemy
			if is_instance_valid(body) and not body.dead and at.distance_squared_to(body.global_position) <= radius_squared:
				caught += 1
		# Placement runs 1.0 at the preferred stand-off down toward 0.0 at either
		# extreme. The 0.4 floor keeps a genuinely enormous cluster worth taking
		# even when it is badly placed — the weapon should still answer a wall.
		var placement := 1.0 - clampf(absf(distance - preferred) / maxf(1.0, cast_range), 0.0, 1.0)
		var score := float(caught) * (0.4 + placement)
		if score > best_score:
			best_score = score
			best = at
	if best_score > 0.0:
		return best
	return origin + _aim_direction(player_index, cast_range) * preferred


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
		if struck < 24:
			_draw_lightning(origin, enemy.global_position, color, 3.0)
		enemy.take_damage(damage)
		struck += 1
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
	for offset in [0.0, 0.34, -0.34]:
		_lance_from(origin, heading.rotated(offset), float(state["range"]), float(state["width"]), damage, color)


## A whole minefield in one cast, laid in a ring around the planter.
func _plant_ruin_garden(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var count := maxi(1, int(state["count"]))
	var centre := players[player_index].global_position
	for index in count:
		var angle := TAU * float(index) / float(count) + randf() * 0.3
		_spawn_mine(player_index, centre + Vector2.from_angle(angle) * 105.0, damage * 1.25, float(state["radius"]), color)


## Pull, collapse, and then collapse again on the cluster the first one made.
func _collapse_event_horizon(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	# Resolved before the first collapse so both stages land on the same point:
	# the pull picks its target from the field, and the second detonation has to
	# follow the cluster it just made rather than firing back at the caster.
	var centre := _gravity_centre(player_index, state)
	_collapse_gravity_at(centre, player_index, state, damage, color)
	var radius := float(state["radius"])
	var implode := func() -> void:
		if not is_inside_tree():
			return
		_damage_area(centre, radius * 0.7, damage * 2.0)
		_draw_ring(centre, radius * 0.7, color.lightened(0.35), 11.0)
		_spawn_combat_flare(centre, color, Color.WHITE, radius * 0.4, 0.26)
	get_tree().create_timer(0.55).timeout.connect(implode)


## --- dual fusions --------------------------------------------------------
## Each of these keeps the readable verbs of both consumed weapons. The
## fractions are part of the balance: two deliveries, one endgame damage budget.
func _cast_comet_storm(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_fire_starpiercer(player_index, state, damage * 0.72, color)
	_fire_lightning(players[player_index].global_position, int(state.get("jumps", 5)),
		damage * 0.62, float(state["range"]), Color("b892ff"))


func _cast_cream_volcano(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_fire_supernova(player_index, state, damage * 0.68, color)
	var pools := state.duplicate()
	pools["count"] = mini(4, maxi(2, int(state["count"]) / 2))
	_spill_milk(player_index, pools, damage * 0.34, Color("f2e2c4"))


func _cast_glacial_satellite(player_index: int, weapon_slot: int, state: Dictionary, damage: float, color: Color) -> void:
	_sweep_celestial(player_index, state, damage * 0.64, color)
	_ensure_absolute_aura(player_index, weapon_slot, state, damage * 0.42, Color("8ecae6"))


func _cast_eclipse_lance(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_swing_black_moon(player_index, state, damage * 0.66, color)
	_fire_judgement(player_index, state, damage * 0.72, Color("caffbf"))


func _cast_singularity_mine(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_collapse_event_horizon(player_index, state, damage * 0.66, color)
	_plant_ruin_garden(player_index, state, damage * 0.58, Color("bdb2ff"))


func _cast_return_bell(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_throw_toy(player_index, state, damage * 0.70, color, TAU / maxf(1.0, float(state["count"])))
	_fire_chain_pulse(state, damage * 0.78)


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
	var beam = LanceStrikeScript.new()
	beam.setup(from, to, width, color)
	add_child(beam)


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
	var fill := Polygon2D.new()
	fill.position = center
	var fill_points := PackedVector2Array()
	for index in 48:
		fill_points.append(Vector2.from_angle(TAU * float(index) / 48.0) * radius)
	fill.polygon = fill_points
	fill.color = Color(color, minf(0.12, maxf(0.045, color.a * 0.16)))
	fill.z_index = 1
	add_child(fill)
	_flash_and_free(fill, RING_HOLD, RING_FADE)
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


func _draw_chain_pulse(from: Vector2, to: Vector2, width: float) -> void:
	var strike = ChainStrikeScript.new()
	strike.setup(from, to, width, Color("80ed99"))
	add_child(strike)


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

