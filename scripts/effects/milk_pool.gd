class_name MilkPool
extends Node2D

## 우유 흩뿌리기. A puddle that lands somewhere near the pair and stays there.
##
## Every other weapon in the roster answers "what am I pointing at". This one
## does not point: the milk falls where it falls, and its value is decided by
## where the pair chose to stand rather than by what happened to be in front of
## them. Standing in it is bad for the enemy and free for the cats, so it turns
## a stretch of rooftop into ground the pair owns for a few seconds.
##
## Drawn and damaged from one clock, like WeaponField: the spreading splash is
## the hit, not decoration played over a hit that already happened.

var grid: EnemySpatialGrid
var damage := 12.0
var pool_radius := 74.0
var slow := 0.55
var tint := Color("f2e2c4")
var age := 0.0
var tick := 0.0
var duration := 4.6
var splash_seed := 0.0
var source_player := -1
var source_weapon := ""

## Slow enough that a puddle is a place rather than a damage tick, fast enough
## that walking through one still costs something.
const TICK_INTERVAL := 0.45
const SPREAD_TIME := 0.28
const FADE_TIME := 0.7
## A pool of milk on a moonlit roof is a pale thing lying flat, and pale flat
## things pick light up and hand some of it back. Kept very low on purpose:
## this is the floor catching the moon, not a weapon announcing itself, and it
## sits under the cats and the crowd where a bright light would wash out the
## silhouettes the fight is read from.
const POOL_LIGHT_ENERGY := 0.09
var pool_light: PointLight2D


func configure(at: Vector2, spatial_grid: EnemySpatialGrid, hit: float, radius: float,
		slow_amount: float, colour: Color, life := 4.6, owner_index := -1, weapon_id := "") -> void:
	global_position = at
	grid = spatial_grid
	damage = hit
	pool_radius = radius
	slow = slow_amount
	tint = colour
	duration = life
	source_player = owner_index
	source_weapon = weapon_id
	splash_seed = randf() * TAU
	z_index = -1 # Under the cats and the enemies: it is the floor, not an effect.
	if pool_light == null:
		pool_light = LightField.attach(self, colour, radius * 1.2, POOL_LIGHT_ENERGY)
	queue_redraw()


func _physics_process(delta: float) -> void:
	age += delta
	tick -= delta
	if tick <= 0.0 and age >= SPREAD_TIME:
		tick = TICK_INTERVAL
		_soak()
	if pool_light != null:
		# Spreads with the splash and goes out with the puddle, so the lit patch
		# of roof is always exactly the wet patch of roof.
		var spread := _spread()
		var fade := clampf((duration - age) / FADE_TIME, 0.0, 1.0)
		pool_light.energy = POOL_LIGHT_ENERGY * spread * fade
		pool_light.texture_scale = maxf(0.2, pool_radius * spread * 1.2 / 64.0)
	queue_redraw()
	if age >= duration:
		queue_free()


func _soak() -> void:
	if grid == null:
		return
	var reach := pool_radius * _spread()
	for enemy in grid.query_radius(global_position, reach + 40.0):
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		if global_position.distance_to(enemy.global_position) > reach + enemy.radius:
			continue
		enemy.take_damage(damage, source_player, source_weapon)
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(TICK_INTERVAL + 0.25, slow)


## 0 to 1 as the splash opens out, then held. The pool does not shrink as it
## expires — it fades, so its footprint never lies about what it is hitting.
func _spread() -> float:
	return ease(clampf(age / SPREAD_TIME, 0.0, 1.0), -1.8)


func _draw() -> void:
	var reach := pool_radius * _spread()
	if reach <= 1.0:
		return
	var alpha := minf(1.0, (duration - age) / FADE_TIME)
	# An irregular rim rather than a circle: a spilled puddle that is a perfect
	# disc reads as a targeting decal, which is exactly what this is not.
	var rim := PackedVector2Array()
	for index in 26:
		var angle := TAU * float(index) / 26.0
		var wobble := 1.0 + sin(angle * 3.0 + splash_seed) * 0.09 + sin(angle * 5.0 - splash_seed) * 0.05
		rim.append(Vector2.from_angle(angle) * reach * wobble)
	draw_colored_polygon(rim, Color(tint, 0.30 * alpha))
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(tint.lightened(0.35), 0.7 * alpha), 3.0, true)
	# A brighter core and a few droplets, so a fresh pool is obviously wetter
	# than one that is about to dry.
	draw_circle(Vector2.ZERO, reach * 0.46, Color(tint.lightened(0.25), 0.22 * alpha))
	for index in 5:
		var angle := splash_seed + TAU * float(index) / 5.0
		draw_circle(Vector2.from_angle(angle) * reach * 0.72, reach * 0.09,
			Color(tint.lightened(0.4), 0.45 * alpha))
