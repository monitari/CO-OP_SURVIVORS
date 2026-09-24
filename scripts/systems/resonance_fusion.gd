extends RefCounted

## The generated resonances: one weapon's delivery, blown up to resonance size,
## carrying the other weapon's element to everything it touches.
##
##     carrier  the weapon that supplied the behaviour tag — *how* it lands
##     payload  the element the other weapon supplied — *what* happens where
##
## 초신성(화염) + 물수제비 물고기(유도) is therefore a giant fish skipping from
## enemy to enemy and exploding each time it lands, and 크림 해일(냉기·제어) +
## 뇌신의 격노(뇌전) is a wave of milk that washes the crowd back while lightning
## comes down on whatever it has soaked. Both weapons are still recognisably on
## the roof — which is the thing the nine generic templates this replaced could
## not do: they were the same nine attacks in six colours, and a pair could not
## find either of their own weapons in them.
##
## The absolute numbers here only shape an attack against itself — how much of
## it is the carrier and how much is the payload. How hard the whole cast hits is
## decided outside, by ResonanceSystem.RESONANCE_PREMIUM against the two weapons
## the resonance absorbed (see main._resonance_power), so these can be tuned for
## how an attack reads without moving the trade.

const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const WeaponFieldScript := preload("res://scripts/effects/weapon_field.gd")
const MineScript := preload("res://scripts/entities/proximity_mine.gd")
const MilkPoolScript := preload("res://scripts/effects/milk_pool.gd")
const ReturningToyScript := preload("res://scripts/effects/returning_toy.gd")

## One cast's base damage unit, before the resonance multiplier.
const UNIT := 24.0
## A payload is worth this share of the unit. The carriers pay it out many times,
## so it is a fraction rather than the whole.
const PAYLOAD_SHARE := 0.62
## No cast sets off more payloads than this, however many bodies its carrier
## touches. Each payload is a small explosion, bolt or well, and a carrier that
## touches the whole screen would otherwise spend a frame on two hundred of them.
const PAYLOAD_BUDGET := 26
## How many of those payloads may also heal (성광), so a holy fusion on a crowded
## screen does not refill two health bars in one cast.
const HEAL_BUDGET := 6
const HOLY_HEAL := 1.4
## 서리 payloads deal this much more to a body something was already holding.
const FROST_SHATTER := 1.8
## 그믐 payloads cut this much deeper into a body under half health.
const SHADOW_EXECUTE := 1.6

const ELEMENT_COLORS := {
	"fire": Color("ff8c42"), "frost": Color("8ecae6"), "lightning": Color("b892ff"),
	"arcane": Color("bdb2ff"), "shadow": Color("ef476f"), "holy": Color("fff275"),
}


static func perform(c: WeaponController, resonance: Dictionary, source: String, midpoint: Vector2, m: float) -> void:
	var element := String(resonance.get("element", "arcane"))
	var carrier := String(resonance.get("carrier", ""))
	if carrier.is_empty():
		carrier = String(ResonanceSystem.BEHAVIOR_TEMPLATES.get(String(resonance.get("behavior", "")), {}).get("carrier", "supernova"))
	var payload_color: Color = ELEMENT_COLORS.get(element, Color("bdb2ff"))
	var carrier_color: Color = ELEMENT_COLORS.get(
		String(Evolutions.by_weapon_id(carrier).get("primary_tag", element)), payload_color)
	var unit := UNIT * m
	var payload := _payload(c, element, payload_color, source, unit * PAYLOAD_SHARE)
	match carrier:
		"starpiercer": _comet_cannon(c, source, unit, carrier_color, payload)
		"thunder_god": _thunderhead(c, source, midpoint, unit, carrier_color, payload)
		"event_horizon": _black_hole(c, source, midpoint, unit, carrier_color, payload)
		"supernova": _supernova(c, source, midpoint, unit, carrier_color, payload)
		"absolute_zero": _frost_waves(c, source, unit, carrier_color, payload)
		"celestial": _orrery(c, source, unit, carrier_color, payload)
		"black_moon": _crescents(c, source, unit, carrier_color, payload)
		"stigmata": _burning_leash(c, source, unit, carrier_color, payload)
		"judgement": _lance_rain(c, source, midpoint, unit, carrier_color, payload)
		"ruin_garden": _blooming_garden(c, source, midpoint, unit, carrier_color, payload)
		"cream_tide": _cream_wave(c, source, midpoint, unit, carrier_color, payload)
		"skipping_stone": _skipping_fish(c, source, unit, carrier_color, payload)
		_: _supernova(c, source, midpoint, unit, carrier_color, payload)


## --- payloads -------------------------------------------------------------


## What the element does wherever the carrier lands, as `func(at, scale)`. The
## scale lets a carrier's single big moment (a black hole's collapse) set off a
## bigger payload than one of its many small ones.
static func _payload(c: WeaponController, element: String, color: Color, source: String, damage: float) -> Callable:
	var budget := {"left": PAYLOAD_BUDGET, "heals": HEAL_BUDGET}
	return func(at: Vector2, scale: float) -> void:
		if int(budget["left"]) <= 0 or not c.is_inside_tree():
			return
		budget["left"] = int(budget["left"]) - 1
		c._in_scope(source, func() -> void: _land(c, element, color, source, at, damage, scale, budget))


static func _land(c: WeaponController, element: String, color: Color, source: String, at: Vector2,
		damage: float, scale: float, budget: Dictionary) -> void:
	var hit := damage * scale
	var reach := sqrt(scale)
	match element:
		"frost": _shatter(c, at, hit, 115.0 * reach, color)
		"lightning": _thunderbolt(c, at, hit, color)
		"arcane": _singularity(c, source, at, hit, 150.0 * reach, color)
		"shadow": _execute(c, source, at, hit, 125.0 * reach, color)
		"holy": _pillar(c, at, hit, 100.0 * reach, color, budget)
		_: _explode(c, at, hit, 105.0 * reach, color)


static func _explode(c: WeaponController, at: Vector2, damage: float, radius: float, color: Color) -> void:
	c._damage_area(at, radius, damage)
	c._draw_ring(at, radius, color, 8.0)
	c._spawn_combat_flare(at, color, Color("fff275"), radius * 0.8, 0.26)
	if is_instance_valid(c.particles):
		c.particles.emit_burst(at, color.lightened(0.3), 10, 360.0)
		c.particles.emit_chips(at, Color("59605e"), 4, 220.0)


static func _shatter(c: WeaponController, at: Vector2, damage: float, radius: float, color: Color) -> void:
	for enemy in c._enemies_within(at, radius):
		var held := enemy.slow_timer > 0.0
		enemy.take_damage(damage * (FROST_SHATTER if held else 1.0), c.current_source_player, c.current_source_weapon)
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(2.4, 0.15)
	c._draw_ring(at, radius, color, 7.0)
	c._spawn_combat_flare(at, color, Color.WHITE, radius * 0.6, 0.22)
	if is_instance_valid(c.particles):
		c.particles.emit_chips(at, Color("dff6ff"), 7, 260.0)


static func _thunderbolt(c: WeaponController, at: Vector2, damage: float, color: Color) -> void:
	# Straight down out of the sky onto the spot, then sideways to its neighbours.
	c._draw_lightning(at + Vector2(randf_range(-40.0, 40.0), -280.0), at, color, 5.0)
	c._damage_area(at, 64.0, damage * 0.55)
	var first := c.spatial_grid.nearest(at, 170.0)
	if first != null:
		c._chain_lightning(at, first, 4, damage * 0.6, color, 230.0)


static func _singularity(c: WeaponController, source: String, at: Vector2, damage: float, radius: float, color: Color) -> void:
	# Everything nearby is yanked most of the way in at once — a snap, not a
	# drift — and the knot it makes goes off a beat later.
	for enemy in c._enemies_within(at, radius):
		if enemy.scenery:
			continue
		var travel := at.distance_to(enemy.global_position) * (0.2 if enemy.boss else 0.6)
		enemy.global_position = enemy.global_position.move_toward(at, travel)
	if is_instance_valid(c.particles):
		c.particles.emit_implode(at, radius, color.lightened(0.35), 10)
	c._draw_ring(at, radius, Color(color, 0.6), 4.0)
	c._repeat(source, 0.0, 1, func(_tick: int) -> void:
		c._damage_area(at, radius * 0.6, damage * 1.3)
		c._draw_ring(at, radius * 0.6, color.lightened(0.3), 10.0)
		c._spawn_combat_flare(at, color, Color.WHITE, radius * 0.5, 0.24), 0.26)


static func _execute(c: WeaponController, source: String, at: Vector2, damage: float, radius: float, color: Color) -> void:
	var blade = WeaponFieldScript.new()
	blade.configure_scythe(at, Vector2.from_angle(randf() * TAU), c.spatial_grid, damage * 0.7, radius, TAU,
		color, -1, source)
	blade.presence = WeaponController.RESONANCE_PRESENCE
	c.add_child(blade)
	for enemy in c._enemies_within(at, radius):
		if enemy.health < enemy.max_health * 0.5:
			enemy.take_damage(damage * SHADOW_EXECUTE, c.current_source_player, c.current_source_weapon)


static func _pillar(c: WeaponController, at: Vector2, damage: float, radius: float, color: Color, budget: Dictionary) -> void:
	c._draw_beam(at + Vector2(0.0, -320.0), at, color, 44.0)
	c._damage_area(at, radius, damage)
	c._draw_ring(at, radius, color, 6.0)
	EnemyProjectile.break_within(c.enemy_shots, at, radius * 1.5)
	if int(budget["heals"]) > 0:
		budget["heals"] = int(budget["heals"]) - 1
		for player in c.players:
			player.heal(HOLY_HEAL)


## --- carriers -------------------------------------------------------------


## `targets`, repeated round until there are `count` of them.
##
## A carrier with eight spears for eight knots of the crowd must still throw all
## eight when the only thing on the roof is a boss. Picking eight *different*
## bodies left a lone boss taking one spear, one comet, one fish-skip — a
## resonance that was sixty times better against a crowd than against the thing
## a pair most needs it for.
static func _fill(targets: Array[ChaserEnemy], count: int) -> Array[ChaserEnemy]:
	var result: Array[ChaserEnemy] = []
	if targets.is_empty():
		return result
	for index in count:
		result.append(targets[index % targets.size()])
	return result


## 성좌 관통포: a beam from each survivor as wide as a doorway, and three comets
## each that pierce four bodies before they land. The payload goes off along the
## beam and wherever a comet finally stops.
static func _comet_cannon(c: WeaponController, _source: String, unit: float, color: Color, payload: Callable) -> void:
	for index in c.players.size():
		var player := c.players[index]
		if player.downed:
			continue
		var origin := player.global_position
		var marks := c._priority_targets(origin, 760.0, 3)
		if marks.is_empty():
			marks = c._nearest_enemies(origin, 760.0, 3)
		var heading := c._aim_direction(index, 760.0)
		if not marks.is_empty():
			heading = origin.direction_to(marks[0].global_position)
		c._lance_from(origin, heading, 760.0, 96.0, unit * 0.9, color)
		for step in 3:
			payload.call(origin + heading * (170.0 + 220.0 * float(step)), 0.7)
		for mark in _fill(marks, 3):
			var comet := c._launch_seeker(origin, mark, unit * 0.5, 660.0, color, "star",
				func(at: Vector2) -> void: payload.call(at, 1.2))
			comet.radius = 24.0
			comet.remaining_hits = 4
	c.impact.emit(c._pair_midpoint(), 420.0)


## 뇌신의 격노: the sky opens over the pair three times. Every body in reach is
## struck on each wave; the payload lands on the thickest knots of them.
static func _thunderhead(c: WeaponController, source: String, _midpoint: Vector2, unit: float, color: Color, payload: Callable) -> void:
	c._repeat(source, 0.34, 3, func(tick: int) -> void:
		var centre := c._pair_midpoint()
		var drawn := 0
		for enemy in c._enemies_within(centre, 600.0):
			if drawn < 20:
				c._draw_lightning(enemy.global_position + Vector2(randf_range(-30.0, 30.0), -300.0),
					enemy.global_position, color, 3.0)
				drawn += 1
			enemy.take_damage(unit * 0.32, c.current_source_player, c.current_source_weapon)
		for target in _fill(c._cluster_targets(centre, 600.0, 4), 4):
			payload.call(target.global_position + Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0)), 1.0)
		c._draw_ring(centre, 600.0, Color(color, 0.35), 4.0)
		if tick == 0:
			c.impact.emit(centre, 600.0))


## 사건의 지평선: a hole opens on the biggest knot of the crowd and swallows it.
## The collapse sets off the payload at the core, big, and then twice more in a
## ring as what is left of the knot is flung back out.
static func _black_hole(c: WeaponController, source: String, midpoint: Vector2, unit: float, color: Color, payload: Callable) -> void:
	var clusters := c._cluster_targets(midpoint, 640.0, 1)
	var centre := midpoint if clusters.is_empty() else clusters[0].global_position
	var well = WeaponFieldScript.new()
	well.configure_gravity(centre, c.spatial_grid, unit * 1.2, 380.0, 320.0, color,
		func() -> void:
			c._in_scope(source, func() -> void:
				c._damage_area(centre, 200.0, unit * 1.4)
				c._draw_ring(centre, 200.0, Color.WHITE, 12.0)
				c._spawn_combat_flare(centre, color, Color.WHITE, 190.0, 0.4)
				payload.call(centre, 2.5)
				c.impact.emit(centre, 400.0))
			c._repeat(source, 0.2, 2, func(ring: int) -> void:
				for spoke in 4:
					var angle := TAU * float(spoke) / 4.0 + float(ring) * PI * 0.25
					payload.call(centre + Vector2.from_angle(angle) * (110.0 + 70.0 * float(ring)), 0.9), 0.2),
		-1, source)
	c.add_child(well)
	c._draw_ring(centre, 380.0, color, 4.0)
	if is_instance_valid(c.particles):
		c.particles.emit_implode(centre, 380.0, color.lightened(0.35), 18)


## 초신성: each survivor bursts a ring of embers three times their usual size,
## and every one of them sets off the payload where it lands. Then the ground
## between the two goes up.
static func _supernova(c: WeaponController, source: String, _midpoint: Vector2, unit: float, color: Color, payload: Callable) -> void:
	for index in c.players.size():
		if c.players[index].downed:
			continue
		c._fire_flame_nova(index, {"count": 10, "speed": 440.0, "tech_pierce": 2, "style": "ember",
			"shot_radius": 26.0, "impact": func(at: Vector2) -> void: payload.call(at, 1.0)},
			unit * 0.45, color)
	c._damage_area(c._pair_midpoint(), 150.0, unit * 0.8)
	c._repeat(source, 0.0, 1, func(_tick: int) -> void:
		var centre := c._pair_midpoint()
		c._damage_area(centre, 300.0, unit * 1.3)
		c._draw_ring(centre, 300.0, color.lightened(0.2), 14.0)
		c._spawn_combat_flare(centre, color, Color("fff275"), 240.0, 0.42)
		payload.call(centre, 2.0)
		c.impact.emit(centre, 460.0), 0.55)


## 절대영도: three waves of cold roll out from both survivors. Everything a wave
## reaches is chilled and bitten; the payload goes off on the nearest few.
static func _frost_waves(c: WeaponController, source: String, unit: float, color: Color, payload: Callable) -> void:
	c._repeat(source, 0.38, 3, func(wave: int) -> void:
		var reach := 220.0 + 70.0 * float(wave)
		for index in c.players.size():
			var player := c.players[index]
			if player.downed:
				continue
			var at := player.global_position
			c.play_shockwave(at, reach, color, 0.34)
			c._damage_area(at, reach, unit * 0.34, 0.4)
			for target in _fill(c._nearest_enemies(at, reach, 3), 3):
				payload.call(target.global_position, 0.9))


## 천구 의식: two great rings of orbiting stones, one round each survivor, wide
## enough to meet over the chain. A stone that passes a body sets the payload off
## on it — once per body per turn, so the ring reads as stones striking rather
## than as a zone. When the rings wind down, every stone leaves its orbit and
## falls on the strongest thing in reach: without that the orrery was a ring a
## boss could stand beside untouched, ninety times better against a crowd.
static func _orrery(c: WeaponController, source: String, unit: float, color: Color, payload: Callable) -> void:
	var struck := {}
	for index in c.players.size():
		if c.players[index].downed:
			continue
		c._sweep_orbit(index, {"radius": 190.0, "count": 6, "speed": 3.6, "duration": 0.7}, unit * 0.5, color)
		c._damage_area(c.players[index].global_position, 150.0, unit * 0.4)
	c._repeat(source, 0.3, 8, func(tick: int) -> void:
		for index in c.players.size():
			var player := c.players[index]
			if player.downed:
				continue
			var fired := 0
			for enemy in c._enemies_within(player.global_position, 230.0):
				var key := "%d:%d" % [enemy.get_instance_id(), floori(float(tick) / 3.0)]
				if struck.has(key) or player.global_position.distance_to(enemy.global_position) < 120.0:
					continue
				struck[key] = true
				payload.call(enemy.global_position, 0.7)
				fired += 1
				if fired >= 2:
					break)
	c._repeat(source, 0.0, 1, func(_tick: int) -> void:
		for index in c.players.size():
			var player := c.players[index]
			if player.downed:
				continue
			var marks := c._priority_targets(player.global_position, 560.0, 1)
			if marks.is_empty():
				continue
			for stone in 6:
				var origin := player.global_position + Vector2.from_angle(TAU * float(stone) / 6.0) * 190.0
				var shot := c._launch_seeker(origin, marks[0], unit * 0.4, 720.0, color, "star",
					func(at: Vector2) -> void: payload.call(at, 0.6))
				shot.radius = 18.0, 2.5)


## 흑월참: both survivors swing a blade the size of the chain, twice round. The
## payload follows the blade into the six bodies nearest each of them.
static func _crescents(c: WeaponController, source: String, unit: float, color: Color, payload: Callable) -> void:
	for index in c.players.size():
		if c.players[index].downed:
			continue
		c._swing_scythe(index, {"range": 340.0, "arc": TAU}, unit * 1.1, color)
	c._repeat(source, 0.0, 1, func(_tick: int) -> void:
		for index in c.players.size():
			if c.players[index].downed:
				continue
			c._swing_scythe(index, {"range": 300.0, "arc": TAU, "rear": true}, unit * 0.8, color.lightened(0.2))
			for target in _fill(c._nearest_enemies(c.players[index].global_position, 340.0, 6), 6):
				payload.call(target.global_position, 0.8), 0.2)


## 성흔의 사슬: the leash between them burns four times, sets the payload off at
## two points along itself, and cracks out from both ends like a whip at the
## nearest thing to each survivor — the chain itself becomes the fuse.
##
## The lash is what makes this a resonance rather than a trap. Burning only
## along the leash, it measured nothing at all against a boss that was not
## standing on the chain, and a pair who fused into it would have traded two
## weapons for a line on the floor.
static func _burning_leash(c: WeaponController, source: String, unit: float, color: Color, payload: Callable) -> void:
	c._repeat(source, 0.26, 4, func(_tick: int) -> void:
		c._damage_along_chain(120.0, unit * 0.5, 0.6)
		var from := c.players[0].global_position
		var to := c.players[1].global_position
		for step in 2:
			payload.call(from.lerp(to, (1.0 + float(step)) / 3.0), 0.8)
		for player in c.players:
			if player.downed:
				continue
			var mark := c.spatial_grid.nearest(player.global_position, 440.0)
			if mark == null:
				continue
			var at := mark.global_position
			c._draw_beam(player.global_position, at, Color("80ed99").lerp(color, 0.4), 30.0)
			mark.take_damage(unit * 0.6, c.current_source_player, c.current_source_weapon)
			payload.call(at, 0.8))


## 심판의 창: spears fall out of the sky onto every knot of the crowd, one after
## another, and the payload goes off where each one sticks.
static func _lance_rain(c: WeaponController, source: String, midpoint: Vector2, unit: float, color: Color, payload: Callable) -> void:
	var marks := c._cluster_targets(midpoint, 680.0, 8)
	for extra in c._nearest_enemies(midpoint, 680.0, 8):
		if marks.size() >= 8:
			break
		if extra not in marks:
			marks.append(extra)
	var spots: Array[Vector2] = []
	for mark in _fill(marks, 8):
		spots.append(mark.global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0)))
	if spots.is_empty():
		spots.append(midpoint)
	for index in spots.size():
		var at := spots[index]
		c._repeat(source, 0.0, 1, func(_tick: int) -> void:
			c._draw_beam(at + Vector2(randf_range(-60.0, 60.0), -360.0), at, color, 64.0)
			c._damage_area(at, 80.0, unit * 0.7)
			payload.call(at, 1.0)
			if index == 0:
				c.impact.emit(at, 300.0), 0.02 + 0.07 * float(index))


## 파멸의 정원: a ring of wards blooms round the pair, arms, and — whatever has
## or has not walked onto them — goes off all together a moment later. Each ward
## sets off the payload where it stood.
static func _blooming_garden(c: WeaponController, source: String, midpoint: Vector2, unit: float, color: Color, payload: Callable) -> void:
	var mines: Array = []
	for ring in 2:
		var count := 6 + 4 * ring
		var radius := 110.0 + 110.0 * float(ring)
		for step in count:
			var mine := MineScript.new() as ProximityMine
			mine.configure(unit * 0.6, 120.0, color, -1, source)
			mine.spatial_grid = c.spatial_grid
			mine.detonated.connect(func(centre: Vector2, damage: float, blast: float, tint: Color, _owner: int, weapon: String) -> void:
				c._on_mine_detonated(centre, damage, blast, tint, -1, weapon)
				payload.call(centre, 0.8))
			mine.global_position = midpoint + Vector2.from_angle(TAU * float(step) / float(count) + float(ring) * 0.3) * radius
			c.add_child(mine)
			mines.append(mine)
	c._damage_area(midpoint, 240.0, unit * 0.5)
	c._draw_ring(midpoint, 240.0, color, 8.0)
	# The bloom. A trap that only pays when something wanders onto it is a trap
	# that pays nothing to the pair who chose it on an empty stretch of roof.
	c._repeat(source, 0.06, mines.size(), func(tick: int) -> void:
		var mine = mines[tick]
		if is_instance_valid(mine) and not mine.spent:
			mine.force_detonate(), 1.1)


## 크림 해일: a wave of cream rolls across the pair toward the thickest part of
## the crowd, carrying what it catches along with it, and the payload goes off
## on whatever it has soaked. It leaves puddles behind where it broke.
static func _cream_wave(c: WeaponController, source: String, midpoint: Vector2, unit: float, color: Color, payload: Callable) -> void:
	var clusters := c._cluster_targets(midpoint, 640.0, 1)
	var heading := Vector2.RIGHT
	if not clusters.is_empty() and clusters[0].global_position.distance_to(midpoint) > 1.0:
		heading = midpoint.direction_to(clusters[0].global_position)
	var across := heading.orthogonal()
	var start := midpoint - heading * 260.0
	var soaked := {}
	c._repeat(source, 0.09, 12, func(tick: int) -> void:
		var front := start + heading * (70.0 * float(tick))
		c._draw_beam(front - across * 300.0, front + across * 300.0, Color("fff8e7"), 70.0)
		var fired := 0
		for enemy in c._enemies_within(front, 320.0):
			var offset := enemy.global_position - front
			if absf(offset.dot(heading)) > 60.0 + enemy.radius or absf(offset.dot(across)) > 300.0:
				continue
			enemy.take_damage(unit * 0.14, c.current_source_player, c.current_source_weapon)
			if is_instance_valid(enemy) and not enemy.dead:
				enemy.apply_slow(1.6, 0.45)
				if not enemy.scenery:
					enemy.global_position += heading * (18.0 if enemy.boss else 46.0)
				if not soaked.has(enemy.get_instance_id()) and fired < 2:
					soaked[enemy.get_instance_id()] = true
					payload.call(enemy.global_position, 0.8)
					fired += 1
		if tick == 11:
			# The wave breaks on the strongest thing it was rolling toward, so a
			# boss standing in front of the pair takes the whole weight of it
			# rather than one lick of foam.
			var marks := c._priority_targets(front, 420.0, 1)
			if not marks.is_empty():
				var crash := marks[0].global_position
				c._damage_area(crash, 170.0, unit * 1.4)
				c._draw_ring(crash, 170.0, Color("fff8e7"), 14.0)
				c._spawn_combat_flare(crash, Color("fff8e7"), color, 160.0, 0.36)
				payload.call(crash, 2.0)
				c.impact.emit(crash, 360.0)
			for spill in 3:
				var pool := MilkPoolScript.new() as MilkPool
				pool.batched = c.milk_renderer != null
				pool.configure(front + across * (float(spill) - 1.0) * 180.0, c.spatial_grid, unit * 0.1, 110.0,
					0.5, color, 3.0, -1, source)
				c.add_child(pool))


## 물수제비 물고기: a fish the size of a cat leaves each survivor and skips from
## body to body, never the same one twice. Every landing is a splash — and a
## payload.
static func _skipping_fish(c: WeaponController, source: String, unit: float, color: Color, payload: Callable) -> void:
	for index in c.players.size():
		var player := c.players[index]
		if player.downed:
			continue
		var fish = ReturningToyScript.new()
		fish.anchor = player
		fish.grid = c.spatial_grid
		fish.tint = color
		fish.damage = 0.0
		fish.size_scale = 2.8
		# Over the crowd and over its own splashes: the fish is the joke, and a
		# joke buried under the explosions it causes does not land.
		fish.z_index = 6
		c.add_child(fish)
		# Drawn by the toy, flown by the ticker below: the toy's own flight is an
		# out-and-back around its thrower, and this one never comes back.
		fish.set_physics_process(false)
		fish.global_position = player.global_position
		var visited: Array[ChaserEnemy] = []
		# The fish lives in here rather than being captured by the tick below: a
		# lambda that captures a node the ticks outlive errors on every tick after
		# the node goes, before its own validity check can run.
		var hop := {"at": player.global_position, "fish": fish}
		c._repeat(source, 0.13, 9, func(tick: int) -> void:
			var swimmer = hop["fish"]
			if not is_instance_valid(swimmer):
				return
			var from: Vector2 = hop["at"]
			var next := c.spatial_grid.nearest(from, 340.0, visited)
			if next == null:
				# Nothing new in reach: skip on the same water again rather than
				# sink, so a lone boss takes every bounce.
				next = c.spatial_grid.nearest(from, 340.0)
			if next == null or tick == 8:
				swimmer.queue_free()
				if next == null:
					return
			visited.append(next)
			var at := next.global_position
			hop["at"] = at
			swimmer.global_position = at
			swimmer.rotation = from.angle_to_point(at)
			swimmer.age = fposmod(float(tick) * 0.13, 1.0)
			swimmer.queue_redraw()
			c._damage_area(at, 70.0, unit * 0.45)
			c._draw_ring(at, 70.0, Color(color.lightened(0.4), 0.8), 6.0)
			payload.call(at, 0.9))
