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
	visible = true
	set_physics_process(true)
	_ensure_glow()
	queue_redraw()


## Callers set `style` and `projectile_color` immediately after setup() and
## rely on the deferred redraw picking them up; the glow is deferred the same
## way and for the same reason.
func _ensure_glow() -> void:
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
	ground_position += direction * speed * delta
	# The node carries the drawing, so it is the one that gets placed. Applied to
	# the position rather than inside _draw because the node spins to face its
	# heading, and a lift baked into a rotated canvas would tip over with it.
	# On a flat roof this is the floor point unchanged, which is why the run is
	# not affected by it.
	position = RooftopSpace.raised(ground_position, flight_height)
	rotation = direction.angle()
	# Node scale and modulate rather than a redraw: an ember that burns down and
	# a star that steadies as it flies, for free at three hundred projectiles.
	var remaining := clampf(lifetime / maxf(0.001, spawn_lifetime), 0.0, 1.0)
	if style == "ember":
		scale = Vector2.ONE * (0.72 + remaining * 0.42)
		modulate.a = clampf(remaining * 2.6, 0.35, 1.0)
	elif style == "star":
		scale = Vector2.ONE * (1.12 - remaining * 0.12)

	var candidates: Array
	if spatial_grid != null:
		candidates = spatial_grid.query_radius(ground_position, radius + 32.0)
	else:
		candidates = get_tree().get_nodes_in_group("enemies")
	for candidate in candidates:
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead or hit_enemy_ids.has(enemy.get_instance_id()):
			continue
		if ground_position.distance_to(enemy.global_position) <= radius + enemy.radius:
			hit_enemy_ids[enemy.get_instance_id()] = true
			enemy.take_damage(damage, source_player, source_weapon)
			remaining_hits -= 1
			if remaining_hits <= 0:
				release()
				return


func release() -> void:
	if not active:
		return
	active = false
	visible = false
	set_physics_process(false)
	released.emit(self)


func _find_nearest_enemy() -> ChaserEnemy:
	if spatial_grid != null:
		return spatial_grid.nearest(ground_position, 900.0)
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


## Drawn along +X; the node's rotation points it. Everything here is static in
## local space on purpose — see the note on `style`.
func _draw() -> void:
	match style:
		"star":
			_draw_star_comet()
		"ember":
			_draw_ember()
		_:
			draw_line(Vector2(-22.0, 0.0), Vector2(-7.0, 0.0), Color(projectile_color, 0.28), radius, true)
			draw_circle(Vector2.ZERO, radius + 5.0, Color(projectile_color, 0.18))
			draw_circle(Vector2.ZERO, radius, projectile_color)


## 유도 별탄: a four-pointed star with a tapered trail, so a homing shot reads as
## the thing its name says it is rather than as a dot.
func _draw_star_comet() -> void:
	var tail := radius * 4.6
	draw_colored_polygon(PackedVector2Array([
		Vector2(-tail, 0.0), Vector2(-radius * 1.2, -radius * 0.72),
		Vector2(-radius * 1.2, radius * 0.72),
	]), Color(projectile_color, 0.22))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-tail * 0.55, 0.0), Vector2(-radius * 0.9, -radius * 0.4),
		Vector2(-radius * 0.9, radius * 0.4),
	]), Color(projectile_color, 0.4))
	draw_circle(Vector2.ZERO, radius + 5.0, Color(projectile_color, 0.16))
	var star := PackedVector2Array()
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var reach := radius * 1.55 if index % 2 == 0 else radius * 0.6
		star.append(Vector2.from_angle(angle) * reach)
	draw_colored_polygon(star, projectile_color)
	draw_circle(Vector2.ZERO, radius * 0.52, Color(projectile_color.lightened(0.65), 0.95))
	# Two sparks shed behind it, seeded per shot so a volley is not eight
	# identical stamps in a row.
	draw_circle(Vector2(-tail * 0.62, sin(shape_seed) * radius * 0.8), radius * 0.26, Color(projectile_color, 0.55))
	draw_circle(Vector2(-tail * 0.86, sin(shape_seed + 2.1) * radius * 0.6), radius * 0.18, Color(projectile_color, 0.35))


## 불꽃 투사체: a teardrop with a hot core and a ragged trailing edge, wobbled by
## the per-shot seed so a nine-ember nova is not nine copies of one sprite.
func _draw_ember() -> void:
	var wobble := sin(shape_seed) * 0.35
	var body := PackedVector2Array()
	for index in 10:
		var angle := TAU * float(index) / 10.0
		var stretch := 1.0 + cos(angle) * 0.42
		var ripple := 1.0 + sin(angle * 3.0 + shape_seed) * 0.14
		body.append(Vector2.from_angle(angle + wobble * 0.1) * radius * 1.35 * stretch * ripple)
	draw_colored_polygon(body, Color(projectile_color, 0.34))
	var core := PackedVector2Array()
	for index in 8:
		var angle := TAU * float(index) / 8.0
		core.append(Vector2.from_angle(angle) * radius * (0.92 + cos(angle) * 0.3))
	draw_colored_polygon(core, projectile_color)
	draw_circle(Vector2(radius * 0.22, 0.0), radius * 0.46, Color(projectile_color.lightened(0.7), 0.95))
	# The trailing lick of flame.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-radius * 1.2, -radius * 0.5), Vector2(-radius * 3.4 - wobble * 6.0, 0.0),
		Vector2(-radius * 1.2, radius * 0.5),
	]), Color(projectile_color.lightened(0.2), 0.3))


## Only the parts that are actually burning. An ember is mostly an orange body
## with a dark-edged silhouette, and making the whole shot additive erased both
## — the first attempt turned Ignis's nova into a single pale ring. So the hot
## centre and the tip of the trailing flame emit, and the body stays a body.
func _paint_glow(layer: GlowLayer) -> void:
	match style:
		"star":
			layer.draw_circle(Vector2.ZERO, radius * 1.6, Moonlight.glow(projectile_color, 0.16))
			layer.draw_circle(Vector2.ZERO, radius * 0.62, Moonlight.glow(projectile_color.lightened(0.7), 0.32))
		"ember":
			layer.draw_circle(Vector2(radius * 0.22, 0.0), radius * 0.95, Moonlight.glow(projectile_color.lightened(0.5), 0.28))
			layer.draw_circle(Vector2(-radius * 2.2, 0.0), radius * 0.55, Moonlight.glow(projectile_color, 0.13))
