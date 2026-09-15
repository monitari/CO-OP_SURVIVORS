class_name HomingProjectile
extends Node2D

signal released(projectile: HomingProjectile)

var target: ChaserEnemy
var direction := Vector2.RIGHT
var speed := 470.0
var turn_speed := 7.0
var damage := 22.0
var lifetime := 3.2
var radius := 8.0
var projectile_color := Color("43d9ff")
var homing_enabled := true
## What this projectile looks like. 유도 별탄 and 불꽃 투사체 were both a flat
## disc with a stub of a tail, which next to the drawn scythe sweep and the
## orbit ring read as placeholder art. The silhouette is now built once in local
## space and carried by the node's own rotation, so a comet and an ember cost
## exactly what the disc did — no per-frame redraw for either.
var style := "bolt"
var shape_seed := 0.0
var spawn_lifetime := 3.2
var remaining_hits := 1
var hit_enemy_ids: Dictionary = {}
var spatial_grid: EnemySpatialGrid
var active := false
var source_player := -1
var source_weapon := ""
## Resonance shots only. A slow applied to whatever the shot hits (1.0 is none),
## and a callback run where the shot finally lands — at its last hit, not at
## every body it passes through — so a volley can burst where it arrives.
## Both reset in setup(), because projectiles are pooled across every weapon.
var slow_on_hit := 1.0
var on_impact := Callable()
## Pool bookkeeping owned by WeaponController: where this shot sits in the active
## list (for an O(1) swap-remove) and whether it is already parked in the pool.
var active_index := -1
var in_pool := false
## Drawn by the controller's ProjectileRenderer instead of by this node.
var batched := false
## Ticks to wait before looking for a new target again after a search found
## nothing, or after this tick's search budget ran out.
var retarget_wait := 0
## The emitting part of the shot, on its own additive canvas item. Built once
## per pooled projectile and reused with it, so a nova of nine embers costs
## nine extra canvas items at most and never allocates mid-wave.
var glow: GlowLayer
## How far off the roof this shot flies, and the point on the roof it flies
## over. Zero everywhere the roof is flat, which is every screen the run
## currently has, and at zero `ground_position` simply tracks `position` and
## nothing below behaves differently from before this existed.
##
## Above zero the two separate: the shot is *drawn* higher up the screen while
## everything that decides anything — what it steers at, what it can hit, where
## its shadow falls — keeps using the floor point. A star that damages what it
## looks like it is passing over, rather than what is a few pixels below it, is
## the whole reason the height is kept out of the hit test.
var flight_height := 0.0
var ground_position := Vector2.ZERO


func setup(start_direction: Vector2, initial_target: ChaserEnemy) -> void:
	speed = 470.0
	turn_speed = 7.0
	damage = 22.0
	lifetime = 3.2
	radius = 8.0
	projectile_color = Color("43d9ff")
	homing_enabled = true
	style = "bolt"
	shape_seed = randf() * TAU
	spawn_lifetime = lifetime
	scale = Vector2.ONE
	modulate = Color.WHITE
	remaining_hits = 1
	hit_enemy_ids.clear()
	direction = start_direction.normalized()
	target = initial_target
	flight_height = 0.0
	ground_position = position
	active = true
	source_player = -1
	source_weapon = ""
	slow_on_hit = 1.0
	on_impact = Callable()
	retarget_wait = 0
	visible = true
	set_physics_process(true)
	_ensure_glow()
	queue_redraw()


## Callers set `style` and `projectile_color` immediately after setup() and
## rely on the deferred redraw picking them up; the glow is deferred the same
## way and for the same reason.
func _ensure_glow() -> void:
	if batched:
		if glow != null:
			glow.visible = false
		return
	if glow == null:
		glow = GlowLayer.attach(self, _paint_glow, -1)
	if glow != null:
		glow.visible = Moonlight.enabled
		glow.queue_redraw()


func _physics_process(delta: float) -> void:
	if not active:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		release()
		return
	if homing_enabled and (not is_instance_valid(target) or target.dead):
		target = _find_nearest_enemy()
	if homing_enabled and is_instance_valid(target):
		var desired := ground_position.direction_to(target.global_position)
		direction = direction.lerp(desired, minf(1.0, turn_speed * delta)).normalized()
	var travelled_from := ground_position
	ground_position += direction * speed * delta
	# The node carries the drawing, so it is the one that gets placed. Applied to
	# the position rather than inside _draw because the node spins to face its
	# heading, and a lift baked into a rotated canvas would tip over with it.
	# On a flat roof this is the floor point unchanged, which is why the run is
	# not affected by it.
	# Node scale and modulate rather than a redraw: an ember that burns down and
	# a star that steadies as it flies, for free at three hundred projectiles.
	# Position, heading and scale go to the node as one transform: three separate
	# property writes were three trips into the engine per shot per tick.
	var remaining := clampf(lifetime / maxf(0.001, spawn_lifetime), 0.0, 1.0)
	var grow := 1.0
	if style == "ember":
		grow = 0.72 + remaining * 0.42
		modulate.a = clampf(remaining * 2.6, 0.35, 1.0)
	elif style == "star":
		grow = 1.12 - remaining * 0.12
	else:
		grow = scale.x
	var facing := direction * grow
	# (-y, x) is the heading turned +90°, the y axis `rotation` would have made;
	# orthogonal() turns the other way and would mirror every shot.
	transform = Transform2D(facing, Vector2(-facing.y, facing.x), RooftopSpace.raised(ground_position, flight_height))

	if spatial_grid != null:
		_hit_along(travelled_from)
		return
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead or hit_enemy_ids.has(enemy.get_instance_id()):
			continue
		if ground_position.distance_to(enemy.global_position) <= radius + enemy.radius:
			hit_enemy_ids[enemy.get_instance_id()] = true
			enemy.take_damage(damage, source_player, source_weapon)
			if slow_on_hit < 1.0 and is_instance_valid(enemy) and not enemy.dead:
				enemy.apply_slow(1.4, slow_on_hit)
			remaining_hits -= 1
			if remaining_hits <= 0:
				var impact := on_impact
				var landed := ground_position
				release()
				if impact.is_valid():
					impact.call(landed)
				return


## One buffer for every shot's contact lookup: the hits are applied before the
## next shot runs, so nothing holds on to it.
static var _contacts: Array[ChaserEnemy] = []


## Collision against the grid. Only as many contacts as the shot can still spend
## are collected, so a single-hit shot in a pile of six hundred reads one body,
## and the hit history is skipped inside the lookup rather than after it.
func _hit_along(travelled_from: Vector2) -> void:
	var found := spatial_grid.projectile_contacts(travelled_from, ground_position, radius, remaining_hits, hit_enemy_ids, _contacts)
	for index in found:
		var enemy := _contacts[index]
		# Re-checked: an earlier hit this tick may already have ended this body.
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		hit_enemy_ids[enemy.get_instance_id()] = true
		enemy.take_damage(damage, source_player, source_weapon)
		if slow_on_hit < 1.0 and is_instance_valid(enemy) and not enemy.dead:
			enemy.apply_slow(1.4, slow_on_hit)
		remaining_hits -= 1
		if remaining_hits <= 0:
			_contacts.clear()
			var impact := on_impact
			var landed := ground_position
			release()
			if impact.is_valid():
				impact.call(landed)
			return
	_contacts.clear()


func release() -> void:
	if not active:
		return
	active = false
	visible = false
	set_physics_process(false)
	released.emit(self)


## How many shots may search for a new target in one physics tick. A wave of
## kills can orphan a thousand shots at once, and every one of them searching on
## the same tick was a 160ms hitch. The rest keep flying straight and search on
## the following ticks; at 60Hz the budget covers 2,000 orphans in under four
## ticks. resonance_mechanics/projectile tests pin the delay.
const RETARGET_BUDGET := 640
## After a search finds nothing in range, wait this many ticks before the next.
const RETARGET_EMPTY_WAIT := 3
static var _retarget_tick := -1
static var _retargets_left := 0


## Resets the shared per-tick search budget. The benchmark calls this between
## simulated ticks; the game relies on the physics frame counter instead.
static func reset_retarget_budget(tick := -2) -> void:
	_retarget_tick = tick
	_retargets_left = RETARGET_BUDGET


func _find_nearest_enemy() -> ChaserEnemy:
	if spatial_grid != null:
		if retarget_wait > 0:
			retarget_wait -= 1
			return null
		var tick := Engine.get_physics_frames()
		if _retarget_tick != -2 and tick != _retarget_tick:
			_retarget_tick = tick
			_retargets_left = RETARGET_BUDGET
		if _retargets_left <= 0:
			return null
		_retargets_left -= 1
		var found := spatial_grid.nearest(ground_position, 900.0)
		if found == null:
			retarget_wait = RETARGET_EMPTY_WAIT
		return found
	var nearest: ChaserEnemy
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var distance := ground_position.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _draw() -> void:
	if batched:
		return
	paint_body(self, style, radius, projectile_color, shape_seed)


## Mask layers for the batch renderer's atlas. LAYER_ALL draws the shot the way it
## has always looked; the others draw only the parts of one colour family, in
## white, with each part's own alpha — the renderer's shader puts the colours
## back. Parts of the same colour composite to that colour with a combined
## alpha, so one mask per family reproduces the node drawing exactly.
const LAYER_ALL := -1
const LAYER_BASE := 0
const LAYER_HOT := 1
const LAYER_TRAIL := 2


static func _tone(color: Color, alpha: float, lighten: float, part: int, layer: int) -> Color:
	if layer == LAYER_ALL:
		return Color(color.lightened(lighten) if lighten > 0.0 else color, alpha)
	return Color(1.0, 1.0, 1.0, alpha) if part == layer else Color(1.0, 1.0, 1.0, 0.0)


## Drawn along +X; the node's rotation points it. Everything here is static in
## local space on purpose — see the note on `style`.
static func paint_body(canvas: CanvasItem, shape: String, shot_radius: float, color: Color, shot_seed: float, layer := LAYER_ALL) -> void:
	match shape:
		"star":
			_paint_star_comet(canvas, shot_radius, color, shot_seed, layer)
		"ember":
			_paint_ember(canvas, shot_radius, color, shot_seed, layer)
		_:
			if layer != LAYER_ALL and layer != LAYER_BASE:
				return
			canvas.draw_line(Vector2(-22.0, 0.0), Vector2(-7.0, 0.0), _tone(color, 0.28, 0.0, LAYER_BASE, layer), shot_radius, true)
			canvas.draw_circle(Vector2.ZERO, shot_radius + 5.0, _tone(color, 0.18, 0.0, LAYER_BASE, layer))
			canvas.draw_circle(Vector2.ZERO, shot_radius, _tone(color, color.a, 0.0, LAYER_BASE, layer))


## 유도 별탄: a four-pointed star with a tapered trail, so a homing shot reads as
## the thing its name says it is rather than as a dot.
static func _paint_star_comet(canvas: CanvasItem, shot_radius: float, color: Color, shot_seed: float, layer: int) -> void:
	var tail := shot_radius * 4.6
	if layer == LAYER_ALL or layer == LAYER_BASE:
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(-tail, 0.0), Vector2(-shot_radius * 1.2, -shot_radius * 0.72),
			Vector2(-shot_radius * 1.2, shot_radius * 0.72),
		]), _tone(color, 0.22, 0.0, LAYER_BASE, layer))
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(-tail * 0.55, 0.0), Vector2(-shot_radius * 0.9, -shot_radius * 0.4),
			Vector2(-shot_radius * 0.9, shot_radius * 0.4),
		]), _tone(color, 0.4, 0.0, LAYER_BASE, layer))
		canvas.draw_circle(Vector2.ZERO, shot_radius + 5.0, _tone(color, 0.16, 0.0, LAYER_BASE, layer))
		var star := PackedVector2Array()
		for index in 8:
			var angle := TAU * float(index) / 8.0
			var reach := shot_radius * 1.55 if index % 2 == 0 else shot_radius * 0.6
			star.append(Vector2.from_angle(angle) * reach)
		canvas.draw_colored_polygon(star, _tone(color, color.a, 0.0, LAYER_BASE, layer))
	if layer == LAYER_ALL or layer == LAYER_HOT:
		canvas.draw_circle(Vector2.ZERO, shot_radius * 0.52, _tone(color, 0.95, 0.65, LAYER_HOT, layer))
	if layer == LAYER_ALL or layer == LAYER_BASE:
		# Two sparks shed behind it, seeded per shot so a volley is not eight
		# identical stamps in a row.
		canvas.draw_circle(Vector2(-tail * 0.62, sin(shot_seed) * shot_radius * 0.8), shot_radius * 0.26, _tone(color, 0.55, 0.0, LAYER_BASE, layer))
		canvas.draw_circle(Vector2(-tail * 0.86, sin(shot_seed + 2.1) * shot_radius * 0.6), shot_radius * 0.18, _tone(color, 0.35, 0.0, LAYER_BASE, layer))


## 불꽃 투사체: a teardrop with a hot core and a ragged trailing edge, wobbled by
## the per-shot shot_seed so a nine-ember nova is not nine copies of one sprite.
static func _paint_ember(canvas: CanvasItem, shot_radius: float, color: Color, shot_seed: float, layer: int) -> void:
	var wobble := sin(shot_seed) * 0.35
	if layer == LAYER_ALL or layer == LAYER_BASE:
		var body := PackedVector2Array()
		for index in 10:
			var angle := TAU * float(index) / 10.0
			var stretch := 1.0 + cos(angle) * 0.42
			var ripple := 1.0 + sin(angle * 3.0 + shot_seed) * 0.14
			body.append(Vector2.from_angle(angle + wobble * 0.1) * shot_radius * 1.35 * stretch * ripple)
		canvas.draw_colored_polygon(body, _tone(color, 0.34, 0.0, LAYER_BASE, layer))
		var core := PackedVector2Array()
		for index in 8:
			var angle := TAU * float(index) / 8.0
			core.append(Vector2.from_angle(angle) * shot_radius * (0.92 + cos(angle) * 0.3))
		canvas.draw_colored_polygon(core, _tone(color, color.a, 0.0, LAYER_BASE, layer))
	if layer == LAYER_ALL or layer == LAYER_HOT:
		canvas.draw_circle(Vector2(shot_radius * 0.22, 0.0), shot_radius * 0.46, _tone(color, 0.95, 0.7, LAYER_HOT, layer))
	if layer == LAYER_ALL or layer == LAYER_TRAIL:
		# The trailing lick of flame.
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(-shot_radius * 1.2, -shot_radius * 0.5), Vector2(-shot_radius * 3.4 - wobble * 6.0, 0.0),
			Vector2(-shot_radius * 1.2, shot_radius * 0.5),
		]), _tone(color, 0.3, 0.2, LAYER_TRAIL, layer))


## Only the parts that are actually burning. An ember is mostly an orange body
## with a dark-edged silhouette, and making the whole shot additive erased both
## — the first attempt turned Ignis's nova into a single pale ring. So the hot
## centre and the tip of the trailing flame emit, and the body stays a body.
func _paint_glow(layer_node: GlowLayer) -> void:
	paint_glow(layer_node, style, radius, projectile_color)


## Glow parts. In mask mode layer 0 is the first disc and layer 1 the second,
## drawn at full alpha; their colours and strengths live in the renderer's shader.
static func paint_glow(canvas: CanvasItem, shape: String, shot_radius: float, color: Color, layer := LAYER_ALL) -> void:
	var mask := layer != LAYER_ALL
	match shape:
		"star":
			if not mask or layer == 0:
				canvas.draw_circle(Vector2.ZERO, shot_radius * 1.6, Color.WHITE if mask else Moonlight.glow(color, 0.16))
			if not mask or layer == 1:
				canvas.draw_circle(Vector2.ZERO, shot_radius * 0.62, Color.WHITE if mask else Moonlight.glow(color.lightened(0.7), 0.32))
		"ember":
			if not mask or layer == 0:
				canvas.draw_circle(Vector2(shot_radius * 0.22, 0.0), shot_radius * 0.95, Color.WHITE if mask else Moonlight.glow(color.lightened(0.5), 0.28))
			if not mask or layer == 1:
				canvas.draw_circle(Vector2(-shot_radius * 2.2, 0.0), shot_radius * 0.55, Color.WHITE if mask else Moonlight.glow(color, 0.13))
