class_name WeaponController
extends Node2D

const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const ProjectileScript := preload("res://scripts/entities/projectile.gd")
const MilkPoolScript := preload("res://scripts/effects/milk_pool.gd")
const CombatFlareScript := preload("res://scripts/effects/combat_flare.gd")
const MineScript := preload("res://scripts/entities/proximity_mine.gd")
const WeaponFieldScript := preload("res://scripts/effects/weapon_field.gd")
const ChainStrikeScript := preload("res://scripts/effects/chain_strike.gd")
const LanceStrikeScript := preload("res://scripts/effects/lance_strike.gd")
const ReturningToyScript := preload("res://scripts/effects/returning_toy.gd")
const LightFieldScript := preload("res://scripts/effects/light_field.gd")
const TickerScript := preload("res://scripts/effects/resonance_ticker.gd")
const ProjectileRendererScript := preload("res://scripts/effects/projectile_renderer.gd")

signal cue_requested(cue_id: String)
signal attack_visual(player_index: int, weapon_id: String, origin: Vector2, color: Color, radius: float)
## A blast big enough to be felt across the roof: shockwaves and boss flares.
signal impact(centre: Vector2, radius: float)
## Shared cosmetic marks: impact flares, embers, debris. Optional — every call is
## guarded, so a controller built without one (a test, the showcase) still works.
var particles: ParticleField

var players: Array[ChainPlayer] = []
var weapon_loadouts: Array = []
var spatial_grid: EnemySpatialGrid
var elapsed := 0.0
## Kept current by main every physics tick. 결속 파동 is the one weapon whose
## output depends on how the pair is standing, so it needs the same two numbers
## the HUD reads rather than a second opinion about them.
var chain_length := 370.0
var chain_tension := 0.0
## Sampled from the same ChainArc the run draws. The ground path owns damage;
## the raised path owns the flash laid over it.
var chain_path := PackedVector2Array()
var chain_visual_path := PackedVector2Array()
var flight_field: FlightField
var active_projectiles: Array[HomingProjectile] = []
var projectile_pool: Array[HomingProjectile] = []
## Draws every milk puddle in one batch; the puddle nodes only simulate.
var milk_renderer: MilkPoolRenderer
## Every projectile this controller ever made, in creation order — which is also
## their child order, and so the order they used to draw in. The batch renderer
## walks this rather than the active list, because the active list is kept
## compact by swap-removal and its order changes as shots land.
var all_projectiles: Array[HomingProjectile] = []
## Draws every friendly shot in two batches instead of several calls each.
## Static so a comparison can switch every controller back to per-node drawing.
static var batch_projectiles := true
var projectile_renderer: Node2D


## For comparisons: controllers created after this draw shots per node (false)
## or in batches (true).
static func set_batching(enabled: bool) -> void:
	batch_projectiles = enabled
var sustained_fields: Dictionary = {}
## Real light cast back onto the roof by whatever is being fired at it. Pooled
## and capped; see LightField.
var light_field: LightField
## Main's own list of live hostile shots, shared rather than copied. Four
## weapons are allowed to knock them down — the crescent that sweeps a sector,
## the tether that is a line between the pair, the ring of shards, and the mine
## that goes off — and all four are things that already occupy space rather than
## fire past it, which is what makes shooting down a shot read as earned.
var enemy_shots: Array = []
const MINE_CAP_PER_PLAYER := 10
var current_source_player := -1
var current_source_weapon := ""


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
	var state: Dictionary = WeaponTechs.cast_state(weapon_loadouts[player_index][weapon_slot])
	var weapon_id := String(state["weapon_id"])
	current_source_player = player_index
	current_source_weapon = weapon_id
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
	scaled["count"] = int(state.get("count", 1)) + floori(owner_player.amount)
	scaled["speed"] = float(state.get("speed", 0.0)) * owner_player.projectile_speed
	scaled["radius"] = float(state.get("radius", 0.0)) * owner_player.area
	scaled["range"] = float(state.get("range", 0.0)) * owner_player.area
	scaled["width"] = float(state.get("width", 0.0)) * owner_player.area
	scaled["arc"] = minf(TAU, float(state.get("arc", 0.0)) * owner_player.area)
	scaled["pull"] = float(state.get("pull", 0.0)) * owner_player.area
	scaled["cast_range"] = float(state.get("cast_range", 0.0)) * owner_player.area
	scaled["duration"] = owner_player.duration
	if state.has("splash"):
		scaled["splash"] = float(state["splash"]) * owner_player.area
	var behavior := WeaponTechs.behavior(state)
	play_cast_cue = _deliver_attack(player_index, weapon_slot, scaled, damage, color, behavior)
	if bool(behavior.get("echo", false)) and not players[1 - player_index].downed:
		_deliver_attack(1 - player_index, weapon_slot, scaled, damage, color, {})
	if bool(behavior.get("team_heal", false)):
		for player in players:
			player.heal(0.45)
	if play_cast_cue:
		cue_requested.emit("weapon_" + weapon_id)
		var visual_radius := maxf(float(scaled.get("radius", 0.0)), float(scaled.get("width", 0.0)) * 2.0)
		visual_radius = maxf(visual_radius, float(scaled.get("range", 0.0)) * 0.22)
		visual_radius = clampf(visual_radius, 52.0, 170.0)
		attack_visual.emit(player_index, weapon_id, owner_player.global_position, color, visual_radius)
		_light_the_cast(weapon_id, owner_player.global_position, color, visual_radius)


func _deliver_attack(player_index: int, weapon_slot: int, scaled: Dictionary,
		damage: float, color: Color, behavior: Dictionary) -> bool:
	var owner_player := players[player_index]
	var weapon_id := String(scaled["weapon_id"])
	var play_cast_cue := true
	if weapon_id == "frost":
		if bool(behavior.get("shatter", false)):
			return _ensure_absolute_aura(player_index, weapon_slot, scaled, damage, color)
		if bool(behavior.get("ally_aura", false)):
			var key := "tech_frost:%d:%d" % [current_source_player, weapon_slot]
			var existing = sustained_fields.get(key)
			if is_instance_valid(existing):
				existing.refresh_frost(damage, float(scaled["radius"]) * 0.7, float(scaled["slow"]), color)
			else:
				var field = WeaponFieldScript.new()
				field.configure_frost(players[1 - player_index], spatial_grid, damage,
					float(scaled["radius"]) * 0.7, float(scaled["slow"]), color, false, current_source_player, current_source_weapon)
				add_child(field)
				sustained_fields[key] = field
	if weapon_id == "scythe" and bool(behavior.get("rear_sweep", false)):
		var rear := scaled.duplicate()
		rear["rear"] = true
		_swing_scythe(player_index, rear, damage, color)
	if weapon_id == "orbit" and bool(behavior.get("double_orbit", false)):
		_sweep_celestial(player_index, scaled, damage, color)
		return true
	if weapon_id == "mine" and bool(behavior.get("mine_ring", false)):
		var ring := scaled.duplicate()
		# Three more than the survivor would plant anyway, so 다중 매설 keeps
		# growing the ring from the first card instead of doing nothing until
		# the count caught up with a fixed floor of four.
		ring["count"] = int(scaled["count"]) + 3
		_plant_ruin_garden(player_index, ring, damage, color)
		return true
	# There used to be a second branch here, `self_gravity`, which opened the well
	# on the caster's own body. No route has set it for a long time; it is deleted
	# rather than left dormant because it is exactly the behaviour a pull weapon
	# must never have (see GRAVITY_MIN_STAND_OFF), and a dormant switch for it is
	# an invitation to turn it back on.
	if weapon_id == "gravity" and bool(behavior.get("collapse", false)):
		_collapse_event_horizon(player_index, scaled, damage, color)
		return true
	if weapon_id == "boomerang" and bool(behavior.get("radial_toys", false)):
		_throw_toy(player_index, scaled, damage, color, TAU / maxf(1.0, float(scaled["count"])))
		return true
	match weapon_id:
		"boomerang": _throw_toy(player_index, scaled, damage, color, 0.35)
		"skipping_stone": _throw_toy(player_index, scaled, damage, color, TAU / maxf(1.0, float(scaled["count"])))
		"milk", "cream_tide": _spill_milk(player_index, scaled, damage, color)
		"homing": play_cast_cue = _fire_homing(player_index, scaled, damage, color)
		"lightning": play_cast_cue = _strike_lightning(owner_player.global_position, scaled, damage, color)
		"flame": _fire_flame_nova(player_index, scaled, damage, color)
		"frost": play_cast_cue = _ensure_frost_aura(player_index, weapon_slot, scaled, damage, color)
		"scythe": _swing_scythe(player_index, scaled, damage, color)
		"chain": _fire_chain_pulse(scaled, damage, 2 if bool(behavior.get("double_pulse", false)) else 1)
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
	return play_cast_cue


## 과부하: the chain is pinned to one jump, and what it loses in reach it spends
## on the first body — the bolt bursts where it lands.
func _strike_lightning(origin: Vector2, state: Dictionary, damage: float, color: Color) -> bool:
	var first := spatial_grid.nearest(origin, float(state["range"]))
	if first == null:
		return false
	var impact := first.global_position
	_chain_lightning(origin, first, int(state["jumps"]), damage, color)
	var splash := float(state.get("splash", 0.0))
	if splash > 0.0:
		_damage_area(impact, splash, damage * 0.55)
		_draw_ring(impact, splash, color.lightened(0.3), 7.0)
	return true



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
		toy.source_player = current_source_player
		toy.source_weapon = current_source_weapon
		toy.heading = aim.rotated((float(index) - float(count - 1) * 0.5) * fan)
		add_child(toy)
		toy.global_position = owner_player.global_position


## 우유 흩뿌리기. Scattered around the caster rather than aimed: where the milk
## lands is not a decision the weapon makes, which is why the survivor's own
## position is the only thing that decides whether a cast was worth anything.
## How many milk puddles may be on the ground at once, across both survivors.
##
## A puddle lasts 4.6s times the owner's 지속 multiplier, and nothing ever retired
## one early — so the number alive was cast rate times volume times lifetime, and
## every one of those three grew without limit. A late 크림 해일 had well over a
## hundred overlapping pools down: the weapon stopped being a patch of ground the
## pair owns and became a filter over the whole screen, through which neither
## survivor could read an enemy telegraph. The oldest puddle now makes way for
## the newest, which is what the weapon was always doing in spirit — milk that
## fell eight seconds ago is not where the fight is.
const MILK_POOL_BUDGET := 30
const MILK_VIEW_MARGIN := 54.0
const MILK_PLAYER_CLEARANCE := 110.0


func _spill_milk(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var count := maxi(1, int(state.get("count", 1)))
	_retire_oldest_pools(count)
	for _index in count:
		var at := _random_visible_world_point(
			maxf(MILK_VIEW_MARGIN, float(state["radius"]) + 18.0),
			maxf(MILK_PLAYER_CLEARANCE, float(state["radius"]) * 0.9))
		var pool := MilkPoolScript.new() as MilkPool
		pool.batched = milk_renderer != null
		pool.configure(at, spatial_grid, damage, float(state["radius"]),
			float(state.get("slow", 0.55)), color, 4.6 * float(state.get("duration", 1.0)),
			current_source_player, current_source_weapon)
		add_child(pool)
	cue_requested.emit("weapon_milk")


## Picks a point inside the camera's current canvas, leaving room for the pool
## rim and rejecting the space directly under either survivor. Canvas inversion
## keeps this correct while the camera follows the pair or a SubViewport scales.
func _random_visible_world_point(margin: float, player_clearance: float) -> Vector2:
	var viewport := get_viewport()
	var visible := viewport.get_visible_rect()
	var inset_x := minf(margin, visible.size.x * 0.4)
	var inset_y := minf(margin, visible.size.y * 0.4)
	var canvas_inverse := viewport.get_canvas_transform().affine_inverse()
	var best := canvas_inverse * visible.get_center()
	var best_distance := -1.0
	for _attempt in 18:
		var screen_point := Vector2(
			randf_range(visible.position.x + inset_x, visible.end.x - inset_x),
			randf_range(visible.position.y + inset_y, visible.end.y - inset_y))
		var world_point := canvas_inverse * screen_point
		var nearest_player := INF
		for player in players:
			nearest_player = minf(nearest_player,
				world_point.distance_squared_to(player.global_position))
		if nearest_player >= player_clearance * player_clearance:
			return world_point
		if nearest_player > best_distance:
			best_distance = nearest_player
			best = world_point
	return best


## Retires the oldest puddles until `incoming` more of them will fit under
## MILK_POOL_BUDGET. Oldest rather than furthest, so the ground the pair is
## standing on right now is never the ground that gets taken away.
##
## Retired by bringing the puddle's own end forward rather than freeing it, so it
## drains through the fade it would have ended with anyway. Freeing it outright
## makes a patch of lit floor vanish between two frames, which reads as a glitch
## at exactly the moment the screen is busiest. The same shape 결계 지뢰 already
## used for its own cap (MINE_CAP_PER_PLAYER), which detonates its oldest rather
## than deleting it.
func _retire_oldest_pools(incoming: int) -> void:
	var live: Array[MilkPool] = []
	for child in get_children():
		var pool := child as MilkPool
		if pool != null and not pool.is_queued_for_deletion() and pool.duration - pool.age > MilkPool.FADE_TIME:
			live.append(pool)
	var over := live.size() + incoming - MILK_POOL_BUDGET
	if over <= 0:
		return
	live.sort_custom(func(first: MilkPool, second: MilkPool) -> bool: return first.age > second.age)
	for index in mini(over, live.size()):
		live[index].duration = live[index].age + MilkPool.FADE_TIME


## Resonance now sits behind two fused weapons rather than two tier-3 base
## ones, so it fires far later in a run and against far tougher enemies. The
## per-effect numbers below were written for the old gate; this scales all of
## them at once rather than rewriting twenty-five of them by hand.
##
## Every resonance does what its description says. Several used to be one
## instant hit standing in for something that lasts or aims — a lightning field
## that "keeps striking" struck once, a guided bombardment was an unguided ring
## of embers — and are now built from the ticks, seekers and impacts below.
const ENDGAME_SCALE := 2.2

## What separates a friendly area ring from an enemy telegraph is how long it
## stays, not how dim it is. Named so the hierarchy is asserted against these
## rather than against a colour someone might reasonably want to change.
const RING_HOLD := 0.07
const RING_FADE := 0.24


func perform_resonance(resonance: Dictionary, damage_multiplier: float) -> void:
	var resonance_id := String(resonance["id"])
	current_source_player = -1
	current_source_weapon = "resonance:" + resonance_id
	var source := current_source_weapon
	var m := damage_multiplier * ENDGAME_SCALE
	var midpoint := _pair_midpoint()
	_play_resonance_flare(midpoint, resonance)
	# 고유 공명이 있으면 그것을, 없으면 템플릿을 (§15). Everything with a case
	# below is hand-written because its two tags mean something together that the
	# generic shape cannot say; everything else — every element × behaviour
	# combination the roster can produce — runs through one of nine templates, so
	# a new weapon never arrives owing twelve new hand-written effects.
	if String(resonance.get("kind", "unique")) == "template":
		_perform_template_resonance(resonance, source, midpoint, m)
		return
	match resonance_id:
		"guided_thunder":
			# Hunts the toughest body in reach and keeps striking it: one great
			# chain and two follow-ups that re-acquire if the first mark died.
			_repeat(source, 0.24, 3, func(tick: int) -> void:
				var centre := _pair_midpoint()
				var marks := _priority_targets(centre, 760.0, 1)
				if not marks.is_empty():
					_chain_lightning(centre, marks[0], 8 if tick == 0 else 3,
						(38.0 if tick == 0 else 14.0) * m, Color("fff275"), 260.0))
		"storm_volley":
			# Both survivors loose a piercing volley and call lightning from where
			# they stand, so the storm comes from two sides at once.
			for index in 2:
				_fire_flame_nova(index, {"count": 10, "speed": 480.0, "tech_pierce": 1, "style": "star"},
					18.0 * m, Color("b892ff"))
				_fire_lightning(players[index].global_position, 5, 26.0 * m, 620.0, Color("b892ff"))
		"arcane_circuit":
			# The chain stays live as a circuit: it burns what touches it and feeds
			# both survivors on every pulse.
			_repeat(source, 0.4, 6, func(_tick: int) -> void:
				_damage_along_chain(68.0, 11.0 * m, 1.0)
				for player in players:
					player.heal(1.2))
		"thermal_fracture":
			# Frost first, then heat on the same ground: the blast hits harder on
			# everything the frost is still holding.
			_damage_area(midpoint, 300.0, 14.0 * m)
			_slow_area(midpoint, 300.0, 2.6, 0.3)
			_draw_ring(midpoint, 300.0, Color("8ecae6"), 10.0)
			_repeat(source, 0.0, 1, func(_tick: int) -> void:
				for enemy in _enemies_within(midpoint, 300.0):
					enemy.take_damage(30.0 * m * (THERMAL_SHOCK if enemy.slow_timer > 0.0 else 1.0),
						current_source_player, current_source_weapon)
				_draw_ring(midpoint, 300.0, Color("ffb4a2"), 12.0)
				_spawn_combat_flare(midpoint, Color("ff8c42"), Color("ffb4a2"), 150.0, 0.3), 0.45)
		"eclipse_tether":
			_fire_chain_pulse({"width": 92.0}, 42.0 * m)
			for index in 2:
				_swing_scythe(index, {"range": 320.0, "arc": 3.0}, 46.0 * m, Color("ef476f"))
		"storm_field":
			# A field around each survivor that keeps striking the three nearest
			# bodies inside it for almost three seconds.
			var tints := [Color("b892ff"), Color("43d9ff")]
			for index in 2:
				_draw_ring(players[index].global_position, STORM_FIELD_RADIUS, tints[index], 6.0)
			_repeat(source, 0.35, 7, func(tick: int) -> void:
				for index in 2:
					var player := players[index]
					if player.downed:
						continue
					for enemy in _nearest_enemies(player.global_position, STORM_FIELD_RADIUS, 3):
						_draw_lightning(player.global_position, enemy.global_position, tints[index], 3.0)
						enemy.take_damage(7.0 * m, current_source_player, current_source_weapon)
					if tick % 4 == 3:
						_draw_ring(player.global_position, STORM_FIELD_RADIUS, Color(tints[index], 0.6), 5.0))
		"inferno_crescent":
			# The crescents set what they cut alight.
			var burning: Array[ChaserEnemy] = []
			for index in 2:
				var origin := players[index].global_position
				var heading := _aim_direction(index, 270.0)
				_swing_scythe(index, {"range": 270.0, "arc": 2.5}, 48.0 * m, Color("ff8c42"))
				for enemy in _enemies_in_sector(origin, heading, 270.0, 2.5):
					if enemy not in burning:
						burning.append(enemy)
			_burn(source, burning, 6.0 * m, 3, Color("ff8c42"))
		"astral_covenant":
			for player in players:
				player.heal(8.0)
				_damage_area(player.global_position, 190.0, 32.0 * m)
				_draw_ring(player.global_position, 190.0, Color("e4c1f9"), 8.0)
		"frozen_tether":
			# Everything near the chain is held nearly still and keeps taking the
			# binding damage while it is.
			_repeat(source, 0.45, 6, func(tick: int) -> void:
				_damage_along_chain(82.0, (16.0 if tick == 0 else 6.0) * m, 0.2))
		"comet_shower":
			for index in 2:
				_fire_flame_nova(index, {"count": 14, "speed": 430.0, "tech_pierce": 1, "slow_on_hit": 0.4, "style": "star"},
					20.0 * m, Color("8ecae6"))
		"starbound_trajectory":
			# Guided stars from both survivors; where each one lands, lightning
			# comes down from above it.
			for index in 2:
				var origin := players[index].global_position
				for target in _nearest_enemies(origin, 700.0, 4):
					_launch_seeker(origin, target, 16.0 * m, 560.0, Color("43d9ff"), "star",
						func(at: Vector2) -> void:
							_in_scope(source, func() -> void:
								_chain_lightning(at + Vector2(0.0, -150.0), spatial_grid.nearest(at, 160.0), 3,
									14.0 * m, Color("b892ff"), 220.0)
								_spawn_combat_flare(at, Color("43d9ff"), Color("fff275"), 60.0, 0.22)))
		"storm_core":
			# A core between the two survivors that chains out into all four
			# quarters of the field, four times.
			_repeat(source, 0.45, 3, func(_tick: int) -> void:
				var core := _pair_midpoint()
				_draw_ring(core, 46.0, Color("b892ff"), 8.0)
				for first in _nearest_per_quadrant(core, 560.0):
					if first != null:
						_chain_lightning(core, first, 3, 11.0 * m, Color("b892ff"), 230.0))
		"inferno_storm":
			for index in 2:
				_fire_flame_nova(index, {"count": 16, "speed": 460.0}, 24.0 * m, Color("ff8c42"))
			_draw_ring(midpoint, 230.0, Color("ff8c42", 0.5), 4.0)
			_repeat(source, 0.0, 1, func(_tick: int) -> void:
				var centre := _pair_midpoint()
				_damage_area(centre, 230.0, 36.0 * m)
				_draw_ring(centre, 230.0, Color("ffd166"), 12.0)
				_spawn_combat_flare(centre, Color("ff8c42"), Color("fff275"), 140.0, 0.32), 0.5)
		"glacial_prison":
			# Near-total freeze around both survivors, then the frozen shatter.
			for index in 2:
				var at := players[index].global_position
				_damage_area(at, 240.0, 30.0 * m)
				_slow_area(at, 240.0, 2.8, 0.12)
				_draw_ring(at, 240.0, Color("8ecae6"), 10.0)
			_repeat(source, 0.6, 3, func(_tick: int) -> void:
				for index in 2:
					for enemy in _enemies_within(players[index].global_position, 240.0):
						if enemy.slow_timer > 0.0:
							enemy.take_damage(5.0 * m, current_source_player, current_source_weapon)
							if is_instance_valid(enemy) and not enemy.dead:
								enemy.apply_slow(0.7, 0.12), 0.6)
		"bright_moon_flurry":
			for index in 2:
				_swing_scythe(index, {"range": 260.0, "arc": 2.6}, 44.0 * m, Color("ef476f"))
			# The flurry: both blades come back the other way.
			_repeat(source, 0.0, 1, func(_tick: int) -> void:
				for index in 2:
					_swing_scythe(index, {"range": 240.0, "arc": 2.6, "rear": true}, 24.0 * m, Color("ff8fab")), 0.22)
		"bonded_mantra":
			for player in players:
				player.heal(16.0)
			# A wave that runs the chain three times and clears shots off it.
			_repeat(source, 0.22, 3, func(_tick: int) -> void:
				_damage_along_chain(78.0, 16.0 * m, 1.0)
				EnemyProjectile.break_along(enemy_shots, players[0].global_position, players[1].global_position, 78.0))
		"guided_bombardment":
			# Guided embers pick the thickest parts of the crowd and burst there.
			var targets := _cluster_targets(midpoint, 620.0, BOMBARDMENT_SHELLS)
			# Every shell flies even when the crowd is thin: a lone boss takes them all.
			for shell in (BOMBARDMENT_SHELLS if not targets.is_empty() else 0):
				var origin := players[shell % 2].global_position
				_launch_seeker(origin, targets[shell % targets.size()], 8.0 * m, 520.0, Color("ff8c42"), "ember",
					func(at: Vector2) -> void:
						_in_scope(source, func() -> void:
							_damage_area(at, 110.0, 16.0 * m)
							_draw_ring(at, 110.0, Color("ff8c42"), 8.0)
							_spawn_combat_flare(at, Color("ff8c42"), Color("fff275"), 70.0, 0.24)))
		"twilight_pursuit":
			# The guiding light marks the toughest bodies; a shadow blade follows
			# it to each mark and cuts where it is weakest.
			var marks := _priority_targets(midpoint, 650.0, 5)
			for mark_index in marks.size():
				var target := marks[mark_index]
				var caster := players[0] if players[0].global_position.distance_squared_to(target.global_position) \
					<= players[1].global_position.distance_squared_to(target.global_position) else players[1]
				_draw_lightning(caster.global_position, target.global_position, Color("43d9ff"), 3.0)
				_repeat(source, 0.0, 1, func(_tick: int) -> void:
					if not is_instance_valid(target) or target.dead:
						return
					var at := target.global_position
					target.take_damage(48.0 * m * (VITAL_STRIKE if target.elite or target.boss else 1.0),
						current_source_player, current_source_weapon)
					var blade = WeaponFieldScript.new()
					blade.configure_scythe(at, Vector2.from_angle(randf() * TAU), spatial_grid, 24.0 * m, 130.0, TAU,
						Color("ef476f"), current_source_player, current_source_weapon)
					add_child(blade), 0.12 + 0.07 * mark_index)
		"storm_cut_crescent":
			for index in 2:
				_swing_scythe(index, {"range": 260.0, "arc": 2.3}, 42.0 * m, Color("b892ff"))
				_fire_lightning(players[index].global_position, 3, 18.0 * m, 300.0, Color("b892ff"))
				# 감전: what the charged blade passes stutters.
				_slow_area(players[index].global_position, 260.0, 0.8, 0.45)
		"sacred_flame_vow":
			for player in players:
				player.heal(9.0)
			_damage_area(midpoint, 240.0, 32.0 * m)
			EnemyProjectile.break_within(enemy_shots, midpoint, 240.0)
			_draw_ring(midpoint, 240.0, Color("ff8c42"), 9.0)
			# The flame stays and keeps purifying the ground around the pair.
			_repeat(source, 0.5, 3, func(_tick: int) -> void:
				var centre := _pair_midpoint()
				_damage_area(centre, 240.0, 5.0 * m)
				EnemyProjectile.break_within(enemy_shots, centre, 240.0)
				_draw_ring(centre, 240.0, Color("ffd166", 0.45), 4.0), 0.5)
		"frost_shade":
			var cuts: Array = []
			for index in 2:
				cuts.append([players[index].global_position, _aim_direction(index, 250.0)])
				_swing_scythe(index, {"range": 250.0, "arc": 2.4}, 38.0 * m, Color("8ecae6"))
			_damage_area(midpoint, 200.0, 20.0 * m, 0.35)
			# What the frozen blades cut stays frozen behind them.
			_repeat(source, 0.0, 1, func(_tick: int) -> void:
				for cut: Array in cuts:
					for enemy in _enemies_in_sector(cut[0], cut[1], 250.0, 2.4):
						enemy.apply_slow(2.2, 0.3), 0.3)
		"umbral_communion":
			for index in 2:
				_swing_scythe(index, {"range": 300.0, "arc": TAU}, 52.0 * m, Color("c77dff"))
				players[index].heal(12.0)
			_damage_along_chain(88.0, 40.0 * m, 1.0)
		"arcing_tempest":
			# Six lances from the midpoint, so there is no safe bearing at all. The
			# fan turns with run time so two casts never leave the same gaps.
			var phase := elapsed * 0.9
			for step in 6:
				var heading := Vector2.from_angle(phase + TAU * float(step) / 6.0)
				_lance_from(midpoint, heading, 620.0, 40.0, 46.0 * m, Color("caffbf"))
		"warding_garden":
			for index in 2:
				var centre := players[index].global_position
				for step in 5:
					var mine := MineScript.new() as ProximityMine
					mine.configure(38.0 * m, 110.0, Color("bdb2ff"), -1, current_source_weapon)
					mine.spatial_grid = spatial_grid
					mine.detonated.connect(_on_mine_detonated)
					mine.global_position = centre + Vector2.from_angle(TAU * float(step) / 5.0) * 120.0
					add_child(mine)
				_damage_area(centre, 230.0, 26.0 * m, 0.2)
			_draw_ring(midpoint, 300.0, Color("bdb2ff"), 8.0)
		"singularity":
			# Pulls everything in over half a second, crushes it, and then the
			# centre goes out.
			var well = WeaponFieldScript.new()
			well.configure_gravity(midpoint, spatial_grid, 30.0 * m, 420.0, 320.0, Color("ff7bd5"),
				func() -> void:
					_in_scope(source, func() -> void:
						_damage_area(midpoint, 190.0, 58.0 * m)
						_draw_ring(midpoint, 190.0, Color("ff7bd5"), 12.0)
						_spawn_combat_flare(midpoint, Color("ff7bd5"), Color.WHITE, 160.0, 0.34)),
				-1, source)
			add_child(well)
			_draw_ring(midpoint, 420.0, Color("ff7bd5"), 4.0)


## The generic resonance layer: nine shapes, six elements, one effect each time
## they are combined.
##
## Every resonance that is not hand-written is an element and a behaviour, and
## this is where that becomes something on the roof. The behaviour decides the
## shape — where it lands and how it is delivered — and the element decides the
## colour and the rider that goes on top of it. Neither half knows about the
## other, which is the whole point: a thirteenth weapon tagged `holy` + `storm`
## already has a resonance with all twelve of the others, and nobody had to write
## one.
##
## The numbers are shared across all of them on purpose. A generic resonance is
## deliberately a little weaker than a hand-made one at the same cooldown — the
## hand-made ones are the combinations somebody thought were worth building
## toward, and they should stay worth it.
const TEMPLATE_DAMAGE := 26.0
const TEMPLATE_RADIUS := 250.0
const TEMPLATE_TICKS := 5
const TEMPLATE_TICK_RATE := 0.3

const ELEMENT_COLORS := {
	"fire": Color("ff8c42"), "frost": Color("8ecae6"), "lightning": Color("b892ff"),
	"arcane": Color("bdb2ff"), "shadow": Color("ef476f"), "holy": Color("fff275"),
}


func _perform_template_resonance(resonance: Dictionary, source: String, midpoint: Vector2, m: float) -> void:
	var element := String(resonance.get("element", "arcane"))
	var color: Color = ELEMENT_COLORS.get(element, Color("bdb2ff"))
	var damage := TEMPLATE_DAMAGE * m
	match String(resonance.get("template", "blast")):
		"barrage":
			# Both survivors scatter a spread of shots, so the volley comes from
			# wherever the pair happen to be standing rather than from a point.
			for index in 2:
				_fire_flame_nova(index, {"count": 9, "speed": 470.0, "tech_pierce": 0, "style": "star"},
					damage * 0.42, color)
		"lance":
			# The two survivors are the ends of the beam: it runs through the
			# gap between them and out the far side, which is the one shape that
			# is only available to a pair.
			var span := players[1].global_position - players[0].global_position
			var heading := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
			for direction in [heading, -heading]:
				_lance_from(midpoint, direction, 620.0, 46.0, damage * 0.9, color)
			_element_rider(source, element, midpoint, 300.0, damage, color)
		"cleave":
			for index in 2:
				_swing_scythe(index, {"range": 280.0, "arc": TAU}, damage * 0.85, color)
			_element_rider(source, element, midpoint, 300.0, damage, color)
		"conduit":
			# Runs along the leash rather than around a point, so it is the chain
			# itself that does the damage for a moment.
			_repeat(source, 0.36, TEMPLATE_TICKS, func(_tick: int) -> void:
				_damage_along_chain(76.0, damage * 0.3, 1.0)
				_draw_chain_pulse(players[0].global_position, players[1].global_position, 76.0))
			_element_rider(source, element, midpoint, 280.0, damage, color)
		"field":
			_draw_ring(midpoint, TEMPLATE_RADIUS, color, 7.0)
			_repeat(source, TEMPLATE_TICK_RATE, TEMPLATE_TICKS, func(_tick: int) -> void:
				_damage_area(midpoint, TEMPLATE_RADIUS, damage * 0.34))
			_element_rider(source, element, midpoint, TEMPLATE_RADIUS, damage, color)
		"bombard":
			# Aims at where the bodies actually are rather than at the pair, so
			# it clears a pack the survivors are running away from.
			for target in _cluster_targets(midpoint, 700.0, BOMBARDMENT_SHELLS):
				var landing: Vector2 = target.global_position
				_launch_seeker(midpoint, target, damage * 0.5, 520.0, color, "star",
					func() -> void:
						_in_scope(source, func() -> void:
							_damage_area(landing, 150.0, damage * 0.6)
							_spawn_combat_flare(landing, color, Color.WHITE, 120.0, 0.28)))
			_element_rider(source, element, midpoint, 320.0, damage, color)
		"snare":
			_draw_ring(midpoint, TEMPLATE_RADIUS * 1.2, color, 6.0)
			_slow_area(midpoint, TEMPLATE_RADIUS * 1.2, 2.8, 0.25)
			_repeat(source, 0.4, 4, func(_tick: int) -> void:
				_damage_area(midpoint, TEMPLATE_RADIUS * 1.2, damage * 0.3, 0.35))
			_element_rider(source, element, midpoint, TEMPLATE_RADIUS * 1.2, damage, color)
		"tempest":
			# Four strikes that each pick their own ground, so it covers a field
			# instead of hammering one crater.
			_repeat(source, 0.34, 4, func(_tick: int) -> void:
				var centre := _pair_midpoint()
				for target in _nearest_per_quadrant(centre, 520.0):
					if target == null:
						continue
					var at: Vector2 = (target as ChaserEnemy).global_position
					_damage_area(at, 170.0, damage * 0.4)
					_draw_ring(at, 170.0, color, 5.0))
			_element_rider(source, element, midpoint, 360.0, damage, color)
		_:
			_damage_area(midpoint, TEMPLATE_RADIUS, damage)
			_draw_ring(midpoint, TEMPLATE_RADIUS, color, 10.0)
			_spawn_combat_flare(midpoint, color, Color.WHITE, 160.0, 0.34)
			_element_rider(source, element, midpoint, TEMPLATE_RADIUS, damage, color)


## What the element adds on top of the shape. One clause each, and the same
## clause the generated description promises (ResonanceSystem.ELEMENT_RIDERS),
## so the card and the effect cannot drift apart.
func _element_rider(source: String, element: String, centre: Vector2, radius: float, damage: float, color: Color) -> void:
	match element:
		"fire":
			_burn(source, _enemies_within(centre, radius), damage * 0.22, 4, color)
		"frost":
			_slow_area(centre, radius, 2.6, 0.35)
			_draw_ring(centre, radius, color, 5.0)
		"lightning":
			for target in _nearest_enemies(centre, radius, 3):
				_chain_lightning(centre, target, 3, damage * 0.3, color, 220.0)
		"arcane":
			var well = WeaponFieldScript.new()
			well.configure_gravity(centre, spatial_grid, damage * 0.2, radius * 1.3, 240.0, color,
				Callable(), -1, source)
			add_child(well)
		"shadow":
			# Finishes what the shape started rather than adding a flat hit, so
			# it reads as an execution and not as "a bit more damage".
			for enemy in _enemies_within(centre, radius):
				if enemy.health < enemy.max_health * 0.4:
					enemy.take_damage(damage * 0.55, current_source_player, current_source_weapon)
		"holy":
			for player in players:
				player.heal(6.0)
			EnemyProjectile.break_within(enemy_shots, centre, radius)


## Damage bonus 열충격 붕괴 deals to bodies the frost is still holding.
const THERMAL_SHOCK := 1.6
## Damage bonus 황혼 추적 deals to elites and bosses.
const VITAL_STRIKE := 1.6
const STORM_FIELD_RADIUS := 230.0
const BOMBARDMENT_SHELLS := 4


func _pair_midpoint() -> Vector2:
	return (players[0].global_position + players[1].global_position) * 0.5


## Runs `body` with this resonance as the damage source, then puts back whatever
## the controller was attributing before. Ticks and impacts land on later frames,
## after other weapons have cast and moved the attribution on.
func _in_scope(source: String, body: Callable) -> void:
	var previous_player := current_source_player
	var previous_weapon := current_source_weapon
	current_source_player = -1
	current_source_weapon = source
	body.call()
	current_source_player = previous_player
	current_source_weapon = previous_weapon


## `body(tick)` for `ticks` ticks, `interval` apart. With no delay the first tick
## lands on this frame; the rest run on a resonance ticker so they pause with the
## run and are swept by clear_transients.
func _repeat(source: String, interval: float, ticks: int, body: Callable, first_delay := 0.0) -> void:
	var first_index := 0
	var delay := first_delay
	if first_delay <= 0.0:
		body.call(0)
		first_index = 1
		delay = interval
	if ticks - first_index <= 0:
		return
	var ticker = TickerScript.new()
	ticker.setup(delay, interval, ticks - first_index, func(tick: int) -> void:
		_in_scope(source, func() -> void: body.call(tick)), first_index)
	add_child(ticker)


## A burn on these bodies: `ticks` hits of `damage`, half a second apart.
func _burn(source: String, bodies: Array[ChaserEnemy], damage: float, ticks: int, color: Color) -> void:
	if bodies.is_empty():
		return
	_repeat(source, 0.5, ticks, func(_tick: int) -> void:
		var drawn := 0
		for enemy in bodies:
			if not is_instance_valid(enemy) or enemy.dead:
				continue
			var at := enemy.global_position
			enemy.take_damage(damage, current_source_player, current_source_weapon)
			if drawn < 8:
				_draw_ring(at, 24.0, Color(color, 0.7), 4.0)
				drawn += 1, 0.5)


func _enemies_within(centre: Vector2, radius: float) -> Array[ChaserEnemy]:
	var found: Array[ChaserEnemy] = []
	for enemy in spatial_grid.query_radius(centre, radius + 45.0):
		if is_instance_valid(enemy) and not enemy.dead and centre.distance_to(enemy.global_position) <= radius + enemy.radius:
			found.append(enemy)
	return found


func _enemies_in_sector(origin: Vector2, heading: Vector2, reach: float, sweep: float) -> Array[ChaserEnemy]:
	var found: Array[ChaserEnemy] = []
	for enemy in _enemies_within(origin, reach):
		var offset := enemy.global_position - origin
		if sweep >= TAU - 0.01 or offset.length() <= enemy.radius \
				or absf(heading.angle_to(offset)) <= sweep * 0.5 + enemy.radius / maxf(1.0, offset.length()):
			found.append(enemy)
	return found


## Up to `count` living bodies, nearest first.
func _nearest_enemies(origin: Vector2, radius: float, count: int) -> Array[ChaserEnemy]:
	var found: Array[ChaserEnemy] = []
	for index in count:
		var enemy := spatial_grid.nearest(origin, radius, found)
		if enemy == null:
			break
		found.append(enemy)
	return found


## The bodies worth a guided strike: bosses, then elites, then whatever has the
## most health left. Planters are scenery and never chosen.
func _priority_targets(origin: Vector2, radius: float, count: int) -> Array[ChaserEnemy]:
	var pool: Array[ChaserEnemy] = []
	for enemy in _enemies_within(origin, radius):
		if not enemy.scenery:
			pool.append(enemy)
	pool.sort_custom(func(first: ChaserEnemy, second: ChaserEnemy) -> bool:
		return _threat(first) > _threat(second))
	return pool.slice(0, count)


func _threat(enemy: ChaserEnemy) -> float:
	return enemy.health + (1000000.0 if enemy.boss else 0.0) + (10000.0 if enemy.elite else 0.0)


## The nearest body in each quarter of the field around `centre` (entries may be
## null), so a core can chain out in four directions instead of four times at
## the same crowd.
func _nearest_per_quadrant(centre: Vector2, radius: float) -> Array:
	var best: Array = [null, null, null, null]
	var best_distance: Array[float] = [INF, INF, INF, INF]
	for enemy in _enemies_within(centre, radius):
		var offset := enemy.global_position - centre
		var quadrant := clampi(int(fposmod(offset.angle(), TAU) / (PI * 0.5)), 0, 3)
		var distance := offset.length_squared()
		if distance < best_distance[quadrant]:
			best_distance[quadrant] = distance
			best[quadrant] = enemy
	return best


## Where a bombardment should land: the bodies with the most company, kept apart
## from each other so six shells do not fall on one mouse. Samples a stride of
## the crowd for the same reason the gravity well does.
func _cluster_targets(centre: Vector2, radius: float, count: int) -> Array[ChaserEnemy]:
	var candidates := _enemies_within(centre, radius)
	var stride := maxi(1, ceili(float(candidates.size()) / 24.0))
	var scored: Array = []
	for index in range(0, candidates.size(), stride):
		var enemy := candidates[index]
		if enemy.scenery:
			continue
		var company := 0
		for other in candidates:
			if enemy.global_position.distance_squared_to(other.global_position) <= 110.0 * 110.0:
				company += 1
		scored.append([company, enemy])
	scored.sort_custom(func(first: Array, second: Array) -> bool: return int(first[0]) > int(second[0]))
	var chosen: Array[ChaserEnemy] = []
	for entry: Array in scored:
		var enemy: ChaserEnemy = entry[1]
		var crowded := false
		for picked in chosen:
			if picked.global_position.distance_squared_to(enemy.global_position) < 90.0 * 90.0:
				crowded = true
				break
		if not crowded:
			chosen.append(enemy)
		if chosen.size() >= count:
			break
	return chosen


func _slow_area(centre: Vector2, radius: float, duration: float, multiplier: float) -> void:
	for enemy in _enemies_within(centre, radius):
		enemy.apply_slow(duration, multiplier)


## One guided shot from anywhere, at a chosen body, that calls `impact` where it
## finally lands.
func _launch_seeker(origin: Vector2, target: ChaserEnemy, damage: float, speed: float, color: Color, style: String, impact: Callable) -> void:
	var projectile := _acquire_projectile()
	projectile.global_position = origin
	projectile.setup(origin.direction_to(target.global_position), target)
	projectile.source_player = current_source_player
	projectile.source_weapon = current_source_weapon
	projectile.style = style
	projectile.spatial_grid = spatial_grid
	projectile.damage = damage
	projectile.speed = speed
	projectile.turn_speed = 12.0
	projectile.projectile_color = color
	projectile.on_impact = impact
	_give_projectile_height(projectile, "homing")


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
	impact.emit(center, 520.0)
	_spawn_combat_flare(center, Color("ff334f") if enraged else Color("c1121f"), Color("fff275"), 235.0 if enraged else 205.0, 0.72)


func play_remote_attack(weapon_id: String, origin: Vector2, direction: Vector2,
		color: Color, radius: float) -> void:
	var heading := direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT
	# Presentation remains harmless, but preserves the weapon's spatial
	# language instead of collapsing every remote cast into one round flash.
	if weapon_id in ["lance", "starpiercer", "chain", "lightning"]:
		var tip := origin + heading * maxf(150.0, radius * 2.2)
		if weapon_id in ["chain", "lightning"]:
			_draw_lightning(origin, tip, color, 6.0)
		else:
			_draw_beam(origin, tip, color, 12.0)
	elif weapon_id in ["frost", "milk", "mine", "orbit", "nova", "supernova"]:
		_draw_ring(origin, radius, color, 8.0)
	elif weapon_id in ["scythe", "boomerang", "returning_toy"]:
		var sweep_from := origin + heading.rotated(-0.65) * radius
		var sweep_to := origin + heading.rotated(0.65) * radius
		_draw_lightning(sweep_from, sweep_to, color, 5.0)
	else:
		_spawn_combat_flare(origin, color, color.lightened(0.38), radius, 0.24)


## Treasure-driven dash attack, resolved through the same grid and feedback
## stack as the regular weapons.
func perform_pounce(center: Vector2, damage: float, color: Color) -> void:
	current_source_player = -1
	current_source_weapon = "team:dash"
	_damage_area(center, 112.0, damage)
	_draw_ring(center, 112.0, color, 9.0)
	_spawn_combat_flare(center, color, Color.WHITE, 54.0, 0.24)


func _spawn_combat_flare(center: Vector2, primary: Color, secondary: Color, radius: float, lifetime: float) -> void:
	var flare := CombatFlareScript.new()
	flare.setup(center, primary, secondary, radius, lifetime)
	add_child(flare)
	_spawn_reactive_light(center, primary.lerp(secondary, 0.25), minf(radius * 0.9, 190.0), minf(lifetime * 0.7, 0.24), 0.34)


func _spawn_reactive_light(at: Vector2, color: Color, radius: float, lifetime: float, light_energy: float, falloff := 2.4) -> void:
	if is_instance_valid(light_field):
		light_field.flash(at, color, radius, lifetime, light_energy, falloff)


## How much light each weapon throws onto the roof when it fires.
##
## `energy` is the peak the light reaches, `life` how long it burns, `reach` a
## multiplier on the attack's own visual radius, and `where` says whether the
## light belongs at the survivor or out where the attack actually lands: a lance
## is a beam that leaves, a frost aura is a cold ring the cat is standing in the
## middle of.
##
## The energies are spread deliberately wide. A homing bolt fires several times
## a second and gets a pulse barely above nothing; a fused weapon on a long
## cooldown gets four or five times that. Giving them the same light would raise
## the roof to an even brightness and none of it would read as anything
## happening — which is the failure mode the art direction names for halos, and
## it is worse for real light because real light does not stop at the effect.
##
## The colours come from the weapon, so the rule the whole look rests on holds:
## the roof is cold and the only warm things on it are the cats and their magic.
const CAST_LIGHT := {
	# Repeaters. Barely there on any one shot; what the player sees is the roof
	# breathing under a stream of them.
	"homing": {"energy": 0.07, "life": 0.13, "reach": 0.7, "where": "self"},
	"boomerang": {"energy": 0.06, "life": 0.14, "reach": 0.7, "where": "self"},
	"skipping_stone": {"energy": 0.07, "life": 0.14, "reach": 0.7, "where": "self"},
	"orbit": {"energy": 0.08, "life": 0.20, "reach": 1.1, "where": "self"},
	"chain": {"energy": 0.10, "life": 0.16, "reach": 1.3, "where": "chain"},
	# Swings and sprays: a wider, softer wash, still short.
	"scythe": {"energy": 0.13, "life": 0.17, "reach": 1.2, "where": "aim"},
	"flame": {"energy": 0.16, "life": 0.22, "reach": 1.1, "where": "self", "falloff": 1.6},
	"milk": {"energy": 0.09, "life": 0.24, "reach": 1.0, "where": "aim"},
	"mine": {"energy": 0.10, "life": 0.18, "reach": 0.9, "where": "self"},
	# Slow, heavy, aimed: these are events and are lit like events.
	"lance": {"energy": 0.20, "life": 0.16, "reach": 1.4, "where": "aim"},
	"lightning": {"energy": 0.22, "life": 0.14, "reach": 1.2, "where": "aim", "falloff": 3.2},
	"gravity": {"energy": 0.12, "life": 0.30, "reach": 1.3, "where": "aim"},
	"frost": {"energy": 0.08, "life": 0.26, "reach": 1.2, "where": "self", "falloff": 1.4},
	# Fused weapons. The brightest thing a loadout can do on its own.
	"starpiercer": {"energy": 0.23, "life": 0.18, "reach": 1.5, "where": "aim"},
	"thunder_god": {"energy": 0.25, "life": 0.17, "reach": 1.5, "where": "aim", "falloff": 3.2},
	"supernova": {"energy": 0.26, "life": 0.26, "reach": 1.6, "where": "self", "falloff": 1.6},
	"absolute_zero": {"energy": 0.14, "life": 0.30, "reach": 1.4, "where": "self", "falloff": 1.4},
	"black_moon": {"energy": 0.21, "life": 0.20, "reach": 1.4, "where": "aim"},
	"stigmata": {"energy": 0.20, "life": 0.22, "reach": 1.2, "where": "chain"},
	"celestial": {"energy": 0.18, "life": 0.24, "reach": 1.3, "where": "self"},
	"judgement": {"energy": 0.24, "life": 0.20, "reach": 1.5, "where": "aim"},
	"ruin_garden": {"energy": 0.16, "life": 0.22, "reach": 1.1, "where": "self"},
	"event_horizon": {"energy": 0.18, "life": 0.34, "reach": 1.5, "where": "aim"},
	"cream_tide": {"energy": 0.12, "life": 0.26, "reach": 1.1, "where": "aim"},
}
## No cast may light more roof than this, however wide the attack itself is.
const CAST_LIGHT_MAX_REACH := 300.0
## What a weapon with no entry gets. Every weapon in the roster has one; this is
## for a resonance-spawned cast or anything added later, and it is deliberately
## the quietest setting in the table rather than a bright default.
const CAST_LIGHT_FALLBACK := {"energy": 0.08, "life": 0.16, "reach": 1.0, "where": "self"}


## One light per cast, from the table above.
func _light_the_cast(weapon_id: String, origin: Vector2, color: Color, visual_radius: float) -> void:
	if not is_instance_valid(light_field):
		return
	var entry: Dictionary = CAST_LIGHT.get(weapon_id, CAST_LIGHT_FALLBACK)
	var at := origin
	match String(entry.get("where", "self")):
		"aim":
			# Out where the attack lands rather than at the paw that threw it.
			# Falls back to the survivor when the field is empty, which is also
			# where the attack itself goes in that case.
			var target := spatial_grid.nearest(origin, 620.0) if spatial_grid != null else null
			if target != null:
				at = origin.lerp(target.global_position, 0.62)
		"chain":
			at = _pair_midpoint()
	# Capped as well as scaled. An attack's visual radius runs up to 170 and the
	# table reaches 1.6 on top of that, which without a ceiling puts a pool of
	# light most of a screen wide under a single cast — and a light that large
	# stops being an event on the roof and becomes the roof's brightness. The
	# on/off capture of a packed late screen is what this number is set from.
	var reach := minf(visual_radius * float(entry["reach"]) * 1.5, CAST_LIGHT_MAX_REACH)
	light_field.flash(at, color, reach,
		float(entry["life"]), float(entry["energy"]), float(entry.get("falloff", 2.4)))


## The chain itself as a weapon, for 사슬 결계. Public because it is a field
## item doing it, not a weapon cast — nothing about it belongs in the loadout.
func burn_chain(width: float, damage: float) -> void:
	current_source_player = -1
	current_source_weapon = "team:chain_ward"
	_damage_along_chain(width, damage, 1.0)


func clear_transients() -> void:
	for projectile in active_projectiles.duplicate():
		projectile.release()
	if is_instance_valid(light_field):
		light_field.clear_all()
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
		if child.get_script() == TickerScript:
			child.queue_free()
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


func _ready() -> void:
	if light_field == null:
		light_field = LightFieldScript.new() as LightField
		light_field.name = "LightField"
		add_child(light_field)
	if milk_renderer == null:
		milk_renderer = MilkPoolRenderer.new()
		milk_renderer.name = "MilkBatch"
		milk_renderer.controller = self
		add_child(milk_renderer)
	if batch_projectiles and projectile_renderer == null:
		projectile_renderer = ProjectileRendererScript.new()
		projectile_renderer.name = "ProjectileBatch"
		projectile_renderer.controller = self
		add_child(projectile_renderer)
		# First child: pooled shots are created early and keep their slots, so
		# every transient effect appended later already drew over them.
		move_child(projectile_renderer, 0)


## Every live shot's tick, in one callback.
##
## Each projectile used to carry its own `_physics_process`, so a screen holding
## two thousand of them asked the engine to dispatch two thousand script calls a
## tick before any of them had moved a pixel. Walking the creation-order list
## here costs one array read per pooled shot and nothing per engine crossing.
##
## `all_projectiles` rather than the active list, and its size sampled up front,
## for two reasons: releases swap-remove out of the active list and would move
## an unvisited shot over a visited one mid-walk, and a shot spawned by another
## shot's impact this tick must wait for the next one, exactly as it did when
## the engine built the callback list before the tick began.
func _physics_process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_physics_process(delta)
	FrameProbe.add(&"projectiles", probe_started)


func _probed_physics_process(delta: float) -> void:
	if not HomingProjectile.driven_by_loop:
		return
	var count := all_projectiles.size()
	for index in count:
		var shot := all_projectiles[index]
		if shot.active:
			shot.step(delta)


func _acquire_projectile() -> HomingProjectile:
	var projectile: HomingProjectile
	if projectile_pool.is_empty():
		projectile = ProjectileScript.new() as HomingProjectile
		projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
		projectile.released.connect(_on_projectile_released)
		all_projectiles.append(projectile)
		add_child(projectile)
	else:
		projectile = projectile_pool.pop_back()
		projectile.in_pool = false
	projectile.batched = projectile_renderer != null
	projectile.active_index = active_projectiles.size()
	active_projectiles.append(projectile)
	return projectile


## O(1): the last active shot takes the released one's place. Releasing a
## thousand shots used to erase each from the middle of the list and search the
## whole pool to avoid a duplicate, which grew with the square of the count.
func _on_projectile_released(projectile: HomingProjectile) -> void:
	if is_instance_valid(flight_field) and projectile.flight_height > 0.0:
		flight_field.flash(projectile.ground_position, projectile.projectile_color,
			maxf(18.0, projectile.radius * 2.6))
	var index := projectile.active_index
	if index >= 0 and index < active_projectiles.size() and active_projectiles[index] == projectile:
		var last: HomingProjectile = active_projectiles.pop_back()
		if last != projectile:
			active_projectiles[index] = last
			last.active_index = index
	elif projectile in active_projectiles:
		# Someone edited the list by hand; fall back rather than corrupt it.
		active_projectiles.erase(projectile)
		for position_index in active_projectiles.size():
			active_projectiles[position_index].active_index = position_index
	projectile.active_index = -1
	if not projectile.in_pool:
		projectile.in_pool = true
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
		projectile.source_player = current_source_player
		projectile.source_weapon = current_source_weapon
		projectile.style = "star"
		projectile.spatial_grid = spatial_grid
		projectile.damage = damage
		projectile.speed = float(state["speed"])
		projectile.lifetime *= float(state.get("duration", 1.0))
		projectile.spawn_lifetime = projectile.lifetime
		projectile.projectile_color = color
		projectile.remaining_hits = (1 + int(state.get("pierce", 0))
			+ _caster_pierce() + int(state.get("tech_pierce", 0)))
		_give_projectile_height(projectile, "homing")
	return true


func _fire_lightning(origin: Vector2, jumps: int, damage: float, first_range: float, color: Color) -> int:
	return _chain_lightning(origin, spatial_grid.nearest(origin, first_range), jumps, damage, color).size()


## A chain that starts on a chosen body rather than on whatever is nearest, so a
## resonance can aim its first bolt at the thing worth hitting. Each jump loses
## 18% and looks for the next body within `jump_range` of the last one.
func _chain_lightning(origin: Vector2, first: ChaserEnemy, jumps: int, damage: float, color: Color, jump_range := 210.0) -> Array[ChaserEnemy]:
	var hit: Array[ChaserEnemy] = []
	var target := first
	var current_position := origin
	for jump in jumps:
		if target == null or not is_instance_valid(target) or target.dead:
			break
		var at := target.global_position
		_draw_lightning(current_position, at, color, 4.0)
		target.take_damage(damage * pow(0.82, jump), current_source_player, current_source_weapon)
		hit.append(target)
		current_position = at
		target = spatial_grid.nearest(current_position, jump_range, hit)
	return hit


## Resonances cast with no owner (-1). Indexing the survivors with that reads the
## last one, which quietly handed P2's 관통 to every resonance volley.
func _caster_pierce() -> int:
	return players[current_source_player].pierce if current_source_player >= 0 and current_source_player < players.size() else 0


func _fire_flame_nova(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var count := int(state["count"])
	var phase := elapsed * 0.7
	for shot in count:
		var direction := Vector2.from_angle(phase + TAU * float(shot) / float(count))
		var projectile := _acquire_projectile()
		projectile.global_position = players[player_index].global_position + direction * 22.0
		projectile.setup(direction, null)
		projectile.source_player = current_source_player
		projectile.source_weapon = current_source_weapon
		projectile.spatial_grid = spatial_grid
		projectile.homing_enabled = bool(state.get("tech_homing", false))
		projectile.remaining_hits = 1 + _caster_pierce() + int(state.get("tech_pierce", 0))
		projectile.slow_on_hit = float(state.get("slow_on_hit", 1.0))
		projectile.damage = damage
		projectile.speed = float(state["speed"])
		projectile.lifetime *= float(state.get("duration", 1.0))
		projectile.spawn_lifetime = projectile.lifetime
		# A narrow ember could pass cleanly through the gaps in the opening
		# ring, making Ignis survival depend heavily on random spawn angles.
		# The modestly wider hit disc preserves the radial gaps but makes close
		# interceptions reliable.
		projectile.radius = 9.0
		projectile.style = String(state.get("style", "ember"))
		projectile.projectile_color = color
		_give_projectile_height(projectile, "flame")
	_draw_ring(players[player_index].global_position, 40.0, color, 4.0)
	# Embers thrown out ahead of the ring, so the nova reads as something that
	# burst rather than as a ring that appeared.
	if is_instance_valid(particles):
		particles.emit_burst(players[player_index].global_position, color.lightened(0.3), 8, 300.0)


func _give_projectile_height(projectile: HomingProjectile, weapon_id: String) -> void:
	projectile.flight_height = RooftopSpace.weapon_height(weapon_id)
	projectile.ground_position = projectile.global_position
	projectile.global_position = RooftopSpace.raised(projectile.ground_position, projectile.flight_height)
	if is_instance_valid(flight_field):
		flight_field.track(projectile)


func _ensure_frost_aura(player_index: int, weapon_slot: int, state: Dictionary, damage: float, color: Color) -> bool:
	var key := "frost:%d:%d" % [player_index, weapon_slot]
	var existing = sustained_fields.get(key)
	if is_instance_valid(existing):
		existing.refresh_frost(damage, float(state["radius"]), float(state["slow"]), color)
		return false
	var field = WeaponFieldScript.new()
	field.configure_frost(players[player_index], spatial_grid, damage, float(state["radius"]), float(state["slow"]), color, false, player_index, current_source_weapon)
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
	field.configure_frost(players[player_index], spatial_grid, damage, float(state["radius"]), float(state["slow"]), color, true, player_index, current_source_weapon)
	add_child(field)
	sustained_fields[key] = field
	return true


func _swing_scythe(player_index: int, state: Dictionary, damage: float, color: Color, source_player := -2, source_weapon := "") -> void:
	var origin := players[player_index].global_position
	var attack_range := float(state["range"])
	var direction := _aim_direction(player_index, attack_range)
	if bool(state.get("rear", false)):
		direction = -direction
	var field = WeaponFieldScript.new()
	var attack_owner := current_source_player if source_player == -2 else source_player
	var weapon_id := current_source_weapon if source_weapon.is_empty() else source_weapon
	field.configure_scythe(origin, direction, spatial_grid, damage, attack_range, float(state["arc"]), color, attack_owner, weapon_id)
	field.enemy_shots = enemy_shots
	add_child(field)


## The tether weapon is the only one that cares how the pair is standing, and
## it now says so: a slack chain is a short, weak line and a stretched one is a
## long, hot one. That makes 느슨한 족쇄 — the upgrade that lengthens the leash —
## a damage upgrade as well as a freedom one, and it puts the weapon on the same
## side as the overcharge mechanic instead of ignoring it.
const CHAIN_TENSION_BONUS := 0.6


## 팽팽한 사슬 sends a weaker pulse twice instead of one heavy one, which is what
## makes it the 속도 route rather than a second copy of 결속의 맹세.
func _fire_chain_pulse(state: Dictionary, damage: float, pulses := 1) -> void:
	var width := float(state["width"])
	_repeat(current_source_weapon, 0.18, maxi(1, pulses), func(_tick: int) -> void:
		_damage_along_chain(width, damage * (1.0 + chain_tension * CHAIN_TENSION_BONUS), 1.0)
		EnemyProjectile.break_along(enemy_shots, players[0].global_position, players[1].global_position, width)
		cue_requested.emit("chain_snap"))


## Shards riding a circle around their owner. The angle comes from run time
## rather than from a stored rotation, so the ring keeps turning between casts
## and two consecutive sweeps never hit the same arc — which is what makes it
## read as an orbit rather than as a pulsing ring.
func _sweep_orbit(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var field = WeaponFieldScript.new()
	field.configure_orbit(players[player_index], spatial_grid, damage, float(state["radius"]), maxi(1, int(state["count"])), float(state.get("speed", 2.4)), color, float(state.get("duration", 1.0)), player_index, current_source_weapon)
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
	mine.configure(damage, radius, color, player_index, current_source_weapon)
	mine.detonated.connect(_on_mine_detonated)
	mine.spatial_grid = spatial_grid
	mine.global_position = at
	add_child(mine)


func _on_mine_detonated(centre: Vector2, damage: float, radius: float, color: Color, owner_index: int, source_weapon: String) -> void:
	cue_requested.emit("mine_blast")
	_damage_area(centre, radius, damage, 1.0, owner_index, source_weapon)
	EnemyProjectile.break_within(enemy_shots, centre, radius)
	_draw_ring(centre, radius, color, 6.0)
	_spawn_combat_flare(centre, color, color.lightened(0.4), radius * 0.5, 0.22)
	# A mine is the one weapon that is literally an explosion: a flash, sparks,
	# and roof thrown up where it stood.
	if is_instance_valid(particles):
		particles.emit_flare(centre, color.lightened(0.4), radius * 0.45, 0.24)
		particles.emit_burst(centre, color.lightened(0.3), 8, 320.0)
		particles.emit_chips(centre, Color("59605e"), 5, 200.0)


## Drags everything in range toward one point before hitting it, which turns a
## spread-out ring of enemies into a single cluster the rest of the pair's
## weapons can then clear.
func _collapse_gravity(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_collapse_gravity_at(_gravity_centre(player_index, state), player_index, state, damage, color)


func _collapse_gravity_at(centre: Vector2, _player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var radius := float(state["radius"])
	var pull := float(state.get("pull", 160.0))
	if is_instance_valid(particles):
		particles.emit_implode(centre, radius, color.lightened(0.35), 12)
	var field = WeaponFieldScript.new()
	field.configure_gravity(centre, spatial_grid, damage, radius, pull, color, func() -> void: cue_requested.emit("gravity_collapse"), current_source_player, current_source_weapon)
	add_child(field)
	cue_requested.emit("gravity_pull")


## Preferred stand-off for the collapse, as a fraction of the cast range.
const GRAVITY_STAND_OFF := 0.55
## And the distance from either survivor inside which a well may never open,
## whatever is standing there.
##
## This is the whole fix for the weapon's worst behaviour. The placement below
## scores a candidate on how many bodies a well there would catch, and in a
## survivors game the densest cluster on the field is almost always the one
## already on top of the pair — so the well opened underfoot and *dragged the
## rest of the crowd in after it*. A weapon whose entire job is to pull things
## together was reliably pulling them onto the two people it belonged to. No
## amount of scoring fixes that, because the score was not wrong about where the
## bodies were.
##
## A candidate this close is pushed straight out to the ring rather than thrown
## away. The distinction matters: the crowd standing on the pair is still the
## right thing for the weapon to answer, and the well's radius comfortably
## reaches back over them from here — so they are caught and dragged *off* the
## survivors instead of onto them. Discarding those candidates instead would have
## made the weapon quietly refuse to fire at the one moment a player most wants
## it to.
const GRAVITY_MIN_STAND_OFF := 160.0
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
## smaller cluster out in front of the pair beats one sitting at the very edge of
## the cast. With nothing in range it falls back to a point along the aim
## direction rather than snapping home, so the weapon never behaves like the old
## version by accident.
##
## Nothing inside GRAVITY_MIN_STAND_OFF of *either* survivor is eligible, and
## that rule is absolute rather than a term in the score — see the constant.
func _gravity_centre(player_index: int, state: Dictionary) -> Vector2:
	var origin := players[player_index].global_position
	var cast_range := float(state.get("cast_range", 520.0))
	var radius := float(state["radius"])
	var preferred := maxf(GRAVITY_MIN_STAND_OFF, cast_range * GRAVITY_STAND_OFF)
	var candidates := spatial_grid.query_radius(origin, cast_range + 45.0)
	var stride := maxi(1, ceili(float(candidates.size()) / float(GRAVITY_SAMPLES)))
	var radius_squared := radius * radius
	var best := Vector2.ZERO
	var best_score := 0.0
	for index in range(0, candidates.size(), stride):
		var enemy := candidates[index] as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var at := _push_clear_of_survivors(enemy.global_position, origin)
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


## `at`, moved out to the nearest point that is GRAVITY_MIN_STAND_OFF clear of
## both survivors. Run once per survivor, nearest first, so a point wedged
## between the two ends up outside both rings rather than pushed off one and
## straight into the other. `away_from` breaks the tie when a candidate sits
## exactly on a survivor and there is no direction to push along.
func _push_clear_of_survivors(at: Vector2, away_from: Vector2) -> Vector2:
	var moved := at
	for pass_index in 2:
		for player in players:
			var centre := player.global_position
			var offset := moved - centre
			if offset.length_squared() >= GRAVITY_MIN_STAND_OFF * GRAVITY_MIN_STAND_OFF:
				continue
			var heading := offset.normalized()
			if heading == Vector2.ZERO:
				heading = (centre - away_from).normalized()
			if heading == Vector2.ZERO:
				heading = Vector2.RIGHT
			moved = centre + heading * GRAVITY_MIN_STAND_OFF
	return moved


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
		enemy.take_damage(damage, current_source_player, current_source_weapon)
		struck += 1
	_draw_ring(origin, reach, Color(color, 0.35), 3.0)


## Scatter, then collapse: the embers go out and the ground they left goes up.
func _fire_supernova(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	_fire_flame_nova(player_index, state, damage, color)
	var centre := players[player_index].global_position
	var radius := float(state["radius"])
	var source_player := current_source_player
	var source_weapon := current_source_weapon
	var blast := func() -> void:
		if not is_inside_tree():
			return
		_damage_area(centre, radius, damage * 1.6, 1.0, source_player, source_weapon)
		_draw_ring(centre, radius, color.lightened(0.2), 10.0)
		_spawn_combat_flare(centre, color, color.lightened(0.5), radius * 0.6, 0.3)
	get_tree().create_timer(0.45, false).timeout.connect(blast)


## No facing requirement any more: two full circles around the swinger.
func _swing_black_moon(player_index: int, state: Dictionary, damage: float, color: Color) -> void:
	var full := state.duplicate()
	full["arc"] = TAU
	_swing_scythe(player_index, full, damage, color)
	var source_player := current_source_player
	var source_weapon := current_source_weapon
	var second := func() -> void:
		if is_inside_tree():
			_swing_scythe(player_index, full, damage, color.darkened(0.2), source_player, source_weapon)
	get_tree().create_timer(0.18, false).timeout.connect(second)


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
	var source_player := current_source_player
	var source_weapon := current_source_weapon
	var implode := func() -> void:
		if not is_inside_tree():
			return
		_damage_area(centre, radius * 0.7, damage * 2.0, 1.0, source_player, source_weapon)
		_draw_ring(centre, radius * 0.7, color.lightened(0.35), 11.0)
		_spawn_combat_flare(centre, color, Color.WHITE, radius * 0.4, 0.26)
	get_tree().create_timer(0.55, false).timeout.connect(implode)


## The lance shape decoupled from a survivor, so resonances can fire one from
## anywhere in any direction.
func _lance_from(origin: Vector2, heading: Vector2, reach: float, width: float, damage: float, color: Color) -> void:
	var tip := origin + heading.normalized() * reach
	var midpoint := (origin + tip) * 0.5
	var half_width := width * 0.5
	for enemy in spatial_grid.query_radius(midpoint, reach * 0.5 + half_width + 45.0):
		if _distance_to_segment(enemy.global_position, origin, tip) <= half_width + enemy.radius:
			enemy.take_damage(damage, current_source_player, current_source_weapon)
	_draw_beam(origin, tip, color, width)


## A ring that grows from nothing to `radius` and fades as it goes. Field items
## use it as their signature: they are rare, they change the board, and they
## should look like it. `inward` reverses the motion, which is what the magnet
## needs — its ring collapses toward the pair rather than expanding from them.
func play_shockwave(centre: Vector2, radius: float, color: Color, duration: float, inward := false) -> void:
	impact.emit(centre, radius)
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
	# The beam leaves with a flash at the muzzle and ends in one where it stops.
	if is_instance_valid(particles):
		particles.emit_flare(from, color.lightened(0.4), 18.0 + width * 0.4, 0.16)
		particles.emit_flare(to, color.lightened(0.4), 14.0 + width * 0.5, 0.2)
	_spawn_reactive_light(to, color, 72.0 + width * 0.8, 0.16, 0.30)


func _damage_area(center: Vector2, radius: float, damage: float, slow_multiplier: float = 1.0, source_player := -2, source_weapon := "") -> void:
	var attack_owner := current_source_player if source_player == -2 else source_player
	var weapon_id := current_source_weapon if source_weapon.is_empty() else source_weapon
	for enemy in spatial_grid.query_radius(center, radius + 45.0):
		if center.distance_to(enemy.global_position) > radius + enemy.radius:
			continue
		enemy.take_damage(damage, attack_owner, weapon_id)
		if slow_multiplier < 1.0 and is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(1.8, slow_multiplier)


func _damage_along_chain(width: float, damage: float, slow_multiplier: float) -> void:
	var from := players[0].global_position
	var to := players[1].global_position
	var midpoint := (from + to) * 0.5
	var search_radius := from.distance_to(to) * 0.5 + width + 45.0
	for enemy in spatial_grid.query_radius(midpoint, search_radius):
		var distance := _distance_to_polyline(enemy.global_position, chain_path) \
			if chain_path.size() >= 2 else _distance_to_segment(enemy.global_position, from, to)
		if distance <= width + enemy.radius:
			enemy.take_damage(damage, current_source_player, current_source_weapon)
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


func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.size() < 2:
		return INF
	var nearest := INF
	for index in points.size() - 1:
		nearest = minf(nearest, _distance_to_segment(point, points[index], points[index + 1]))
	return nearest


## Lightning is a hard white line with light spilling off it, and those are two
## different things drawn two different ways. The bolt itself stays narrow and
## opaque so a chain of six jumps is still six readable lines; the spill is a
## separate additive pass on the same jagged path, sitting behind the core so
## it spreads out from it rather than washing over it.
func _draw_lightning(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var path := PackedVector2Array()
	for index in 8:
		var ratio := float(index) / 7.0
		var point := from.lerp(to, ratio)
		if index > 0 and index < 7:
			point += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		path.append(point)
	var bolt := Line2D.new()
	bolt.width = width * 1.5
	bolt.default_color = color.lightened(0.2)
	bolt.z_index = 3
	bolt.antialiased = true
	bolt.points = path
	add_child(bolt)
	# A fork off the middle of the bolt. Real lightning branches, and one short
	# branch is enough to stop the bolt reading as a drawn line.
	var fork_at := path[randi_range(2, 4)]
	var heading := (to - from).normalized()
	var fork_dir := heading.rotated(randf_range(0.45, 0.8) * (1.0 if randf() < 0.5 else -1.0))
	var fork_len := from.distance_to(to) * randf_range(0.18, 0.3)
	var fork := Line2D.new()
	fork.width = width * 0.8
	fork.default_color = color.lightened(0.35)
	fork.antialiased = true
	fork.points = PackedVector2Array([fork_at,
		fork_at + fork_dir * fork_len * 0.55 + fork_dir.orthogonal() * randf_range(-6.0, 6.0),
		fork_at + fork_dir * fork_len])
	bolt.add_child(fork)
	if is_instance_valid(particles):
		particles.emit_flare(to, color.lightened(0.45), 12.0 + width * 1.6, 0.16)
	if Moonlight.enabled:
		var spill := Line2D.new()
		spill.width = width * 4.6
		spill.default_color = Moonlight.glow(color, 0.20)
		spill.material = Moonlight.additive()
		spill.antialiased = true
		spill.z_as_relative = true
		spill.z_index = -1
		spill.points = path
		bolt.add_child(spill)
		_spawn_reactive_light(to, color, 58.0 + width * 3.0, 0.14, 0.26)
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
	if chain_visual_path.size() >= 2:
		strike.setup_path(chain_visual_path, width, Color("80ed99"))
	else:
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
