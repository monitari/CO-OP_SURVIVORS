class_name WeaponField
extends Node2D
## Time-based weapon motion. Damage and drawing advance from the same clock so
## the visible sweep/orbit/implosion is the hit, not decoration after a teleport.

enum Kind { ORBIT, FROST, SCYTHE, GRAVITY }

var kind := Kind.ORBIT
var anchor: ChainPlayer
var spatial_grid: EnemySpatialGrid
var damage := 10.0
var effect_radius := 100.0
var count := 3
var speed := 2.4
var slow := 1.0
var color := Color.WHITE
var duration := 1.0
var age := 0.0
var tick := 0.0
var direction := Vector2.RIGHT
var arc := PI
var struck: Dictionary = {}
var pulls: Array[Dictionary] = []
var finished_callback: Callable
var shatter_frozen := false


func configure_orbit(p: ChainPlayer, grid: EnemySpatialGrid, hit: float, radius: float, shards: int, angular_speed: float, tint: Color) -> void:
	kind = Kind.ORBIT
	anchor = p
	spatial_grid = grid
	damage = hit * 0.34
	effect_radius = radius
	count = maxi(1, shards)
	speed = angular_speed
	color = tint
	duration = 3.8
	z_index = 3
	global_position = anchor.global_position
	queue_redraw()


func configure_frost(p: ChainPlayer, grid: EnemySpatialGrid, hit: float, radius: float, slow_amount: float, tint: Color, shatter := false) -> void:
	kind = Kind.FROST
	anchor = p
	spatial_grid = grid
	refresh_frost(hit, radius, slow_amount, tint, shatter)
	duration = INF
	z_index = 2
	global_position = anchor.global_position
	queue_redraw()


func refresh_frost(hit: float, radius: float, slow_amount: float, tint: Color, shatter := false) -> void:
	damage = hit * 0.23
	effect_radius = radius
	slow = slow_amount
	color = tint
	shatter_frozen = shatter


func configure_scythe(origin: Vector2, heading: Vector2, grid: EnemySpatialGrid, hit: float, radius: float, sweep_arc: float, tint: Color) -> void:
	kind = Kind.SCYTHE
	global_position = origin
	direction = heading.normalized()
	spatial_grid = grid
	damage = hit
	effect_radius = radius
	arc = sweep_arc
	color = tint
	duration = 0.34
	z_index = 4
	queue_redraw()


func configure_gravity(centre: Vector2, grid: EnemySpatialGrid, hit: float, radius: float, pull: float, tint: Color, callback := Callable()) -> void:
	kind = Kind.GRAVITY
	global_position = centre
	spatial_grid = grid
	damage = hit
	effect_radius = radius
	color = tint
	duration = 0.48
	finished_callback = callback
	for enemy in spatial_grid.query_radius(centre, radius + 45.0):
		if not is_instance_valid(enemy) or enemy.dead or centre.distance_to(enemy.global_position) > radius + enemy.radius:
			continue
		var distance := centre.distance_to(enemy.global_position)
		var travel := minf(pull, maxf(0.0, distance - 26.0)) * (0.22 if enemy.boss else 1.0)
		pulls.append({"enemy": enemy, "start": enemy.global_position, "end": enemy.global_position.move_toward(centre, travel)})
	z_index = 4
	queue_redraw()


func _physics_process(delta: float) -> void:
	age += delta
	if kind in [Kind.ORBIT, Kind.FROST]:
		if not is_instance_valid(anchor) or anchor.downed:
			if kind == Kind.ORBIT: queue_free()
			return
		global_position = anchor.global_position
	if kind == Kind.ORBIT:
		tick -= delta
		if tick <= 0.0:
			tick = 0.22
			_hit_orbit()
	elif kind == Kind.FROST:
		tick -= delta
		if tick <= 0.0:
			tick = 0.32
			_hit_frost()
	elif kind == Kind.SCYTHE:
		_hit_scythe()
	elif kind == Kind.GRAVITY:
		_step_gravity()
	queue_redraw()
	if age >= duration:
		if kind == Kind.GRAVITY:
			_finish_gravity()
		queue_free()


func _hit_orbit() -> void:
	var phase := age * speed
	var hit_ids: Dictionary = {}
	for shard in count:
		var point := global_position + Vector2.from_angle(phase + TAU * float(shard) / count) * effect_radius
		for enemy in spatial_grid.query_radius(point, 34.0):
			if not is_instance_valid(enemy) or enemy.dead or hit_ids.has(enemy.get_instance_id()): continue
			if point.distance_to(enemy.global_position) <= 26.0 + enemy.radius:
				hit_ids[enemy.get_instance_id()] = true
				enemy.take_damage(damage)


func _hit_frost() -> void:
	for enemy in spatial_grid.query_radius(global_position, effect_radius + 45.0):
		if not is_instance_valid(enemy) or enemy.dead: continue
		if global_position.distance_to(enemy.global_position) <= effect_radius + enemy.radius:
			var already_frozen := enemy.slow_timer > 0.0
			enemy.take_damage(damage * (2.4 if shatter_frozen and already_frozen else 1.0))
			if is_instance_valid(enemy) and not enemy.dead: enemy.apply_slow(0.5, slow)


func _hit_scythe() -> void:
	var progress := clampf(age / duration, 0.0, 1.0)
	var blade_angle := direction.angle() - arc * 0.5 + arc * ease(progress, -1.7)
	var blade := Vector2.from_angle(blade_angle)
	for enemy in spatial_grid.query_radius(global_position, effect_radius + 45.0):
		if not is_instance_valid(enemy) or enemy.dead or struck.has(enemy.get_instance_id()): continue
		var offset: Vector2 = enemy.global_position - global_position
		if offset.length() <= effect_radius + enemy.radius and absf(blade.angle_to(offset.normalized())) <= 0.18 + enemy.radius / maxf(1.0, offset.length()):
			struck[enemy.get_instance_id()] = true
			enemy.take_damage(damage)


func _step_gravity() -> void:
	var progress := clampf(age / duration, 0.0, 1.0)
	var eased := ease(progress, 2.2)
	for pull in pulls:
		var enemy = pull.get("enemy")
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.global_position = (pull["start"] as Vector2).lerp(pull["end"], eased)


func _finish_gravity() -> void:
	for pull in pulls:
		var enemy = pull.get("enemy")
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.take_damage(damage)
			if is_instance_valid(enemy) and not enemy.dead: enemy.apply_slow(1.2, 0.55)
	if finished_callback.is_valid(): finished_callback.call()


func _draw() -> void:
	match kind:
		Kind.ORBIT:
			var phase := age * speed
			draw_arc(Vector2.ZERO, effect_radius, 0, TAU, 48, Color(color, 0.18), 2.0, true)
			for shard in count:
				var angle := phase + TAU * float(shard) / count
				var point := Vector2.from_angle(angle) * effect_radius
				draw_arc(Vector2.ZERO, effect_radius, angle - 0.42, angle, 10, Color(color, 0.42), 4.0, true)
				_draw_star(point, 11.0, color)
		Kind.FROST:
			for ring in 3:
				var start := age * (0.35 + ring * 0.1) + ring * 2.0
				draw_arc(Vector2.ZERO, effect_radius - ring * 7.0, start, start + 1.25, 18, Color(color, 0.20 + ring * 0.07), 2.5, true)
			for flake in 8:
				var at := Vector2.from_angle(flake * TAU / 8.0 - age * 0.18) * effect_radius * (0.62 + (flake % 2) * 0.2)
				draw_circle(at, 2.8, Color(color.lightened(0.4), 0.75))
		Kind.SCYTHE:
			var progress := clampf(age / duration, 0.0, 1.0)
			var start := direction.angle() - arc * 0.5
			var current := start + arc * ease(progress, -1.7)
			var trail := maxf(start, current - minf(0.75, arc * 0.45))
			draw_arc(Vector2.ZERO, effect_radius, trail, current, 18, Color(color.lightened(0.35), 0.95), 18.0, true)
			draw_arc(Vector2.ZERO, effect_radius - 18.0, trail, current, 18, Color(color, 0.35), 28.0, true)
			var tip := Vector2.from_angle(current) * effect_radius
			draw_line(Vector2.from_angle(current) * effect_radius * 0.22, tip, Color.WHITE, 3.0, true)
		Kind.GRAVITY:
			var progress := clampf(age / duration, 0.0, 1.0)
			for spiral in 4:
				var r := effect_radius * (1.0 - progress * 0.78) * (1.0 - spiral * 0.13)
				var start := -age * (5.0 + spiral)
				draw_arc(Vector2.ZERO, r, start, start + 3.9, 24, Color(color, 0.58 - spiral * 0.09), 4.0, true)
			draw_circle(Vector2.ZERO, 8.0 + progress * 18.0, Color(color, 0.18 + progress * 0.3))


func _draw_star(at: Vector2, radius: float, tint: Color) -> void:
	var points := PackedVector2Array()
	for index in 8:
		points.append(at + Vector2.from_angle(index * TAU / 8.0) * (radius if index % 2 == 0 else radius * 0.42))
	draw_colored_polygon(points, tint)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 1.5, true)
