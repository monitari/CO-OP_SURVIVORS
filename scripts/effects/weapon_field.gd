class_name WeaponField
extends Node2D
## Time-based weapon motion. Damage and drawing advance from the same clock so
## the visible sweep/orbit/implosion is the hit, not decoration after a teleport.

enum Kind { ORBIT, FROST, SCYTHE, GRAVITY }
## Probe section per kind, so the profiler says which kind of field is costing.
const KIND_PROBES: Array[StringName] = [&"field:orbit", &"field:frost", &"field:scythe", &"field:gravity"]

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
## Orbit only: shard_hits[shard][enemy instance id] -> the age at which that
## shard last hit that enemy. Kept per shard because the whole point of a ring of
## shards is that each one is its own blade. It was one dictionary keyed by the
## string "<shard>:<id>", which formatted a new string for every body near every
## shard on every physics tick — a few hundred allocations a tick in a crowd, for
## a lookup two integers can do.
var shard_hits: Array[Dictionary] = []
var pulls: Array[Dictionary] = []
var finished_callback: Callable
## Hostile shots this field is allowed to knock down — the controller's own
## array, shared rather than copied, so a shot removed here is gone everywhere.
## Left empty for the fields whose weapons do not shoot things out of the air.
var enemy_shots: Array = []
var shatter_frozen := false
var source_player := -1
var source_weapon := ""
## How big the weapon behind this field has grown (WeaponGrowth.presence). A
## blade's edge and an orbit's stones are drawn at this multiple, and a stone's
## contact grows with it: the stone the pair can see is the stone that hits.
var presence := 1.0
var stone_reach_scale := 1.0
## The light this field casts back onto the roof, for the two kinds that are a
## condition rather than an event. It travels with the field and lives as long as
## it does, which is why it is a child of this node instead of coming out of
## LightField's pool: the pool is for casts, and a cast must never be able to
## evict the cold ring a survivor is standing inside of.
var sustained_light: PointLight2D
## Frost is the one light in the game that is not warm. The aura is a cold ring
## the survivor stands in the middle of, so it is lit with the moon's own colour
## rather than the weapon's, and faintly: the art direction asks for area-effect
## interiors to stay faint and their borders crisp, and a bright interior here
## would flatten the ring that carries the reading.
const FROST_LIGHT_ENERGY := 0.10
## The collapse, on the other hand, takes light out of the floor instead of
## adding it, so the roof goes darker toward the middle of the well. Nothing
## else in the game subtracts, which is what makes it read as a collapse rather
## than as one more glowing circle.
const GRAVITY_LIGHT_ENERGY := 0.24
const MAX_RENDER_RADIUS := 1800.0
const ORBIT_FADE_IN := 0.24
const ORBIT_FADE_OUT := 0.42
## The frost aura's moving part — its turning arcs and drifting flakes — on a
## canvas item of its own, so the two large filled discs underneath are drawn
## once instead of every tick. See _present.
var _frost_motion: DrawProxy
## What the static layer was last drawn with; a change means drawing it again.
var _drawn_key := ""


func configure_orbit(p: ChainPlayer, grid: EnemySpatialGrid, hit: float, radius: float, shards: int, angular_speed: float, tint: Color, duration_scale := 1.0, owner := -1, weapon_id := "") -> void:
	kind = Kind.ORBIT
	anchor = p
	spatial_grid = grid
	# Per shard pass rather than per tick. The old model checked the whole ring
	# five times a second and let one enemy be hit only once per check, so a
	# boss standing in the ring took the same damage from five shards as from
	# one — which made 파편 증식 worth nothing at all against a single target.
	# Each shard now lands its own hit, so the per-hit number is much larger
	# and both the shard count and the orbit speed became real damage upgrades.
	damage = hit * 1.15
	effect_radius = radius
	count = maxi(1, shards)
	speed = angular_speed
	color = tint
	duration = 3.8 * duration_scale
	source_player = owner
	source_weapon = weapon_id
	z_index = 3
	modulate.a = 0.0
	global_position = anchor.global_position
	queue_redraw()


func configure_frost(p: ChainPlayer, grid: EnemySpatialGrid, hit: float, radius: float, slow_amount: float, tint: Color, shatter := false, owner := -1, weapon_id := "") -> void:
	kind = Kind.FROST
	anchor = p
	spatial_grid = grid
	refresh_frost(hit, radius, slow_amount, tint, shatter)
	source_player = owner
	source_weapon = weapon_id
	duration = INF
	z_index = 2
	global_position = anchor.global_position
	if sustained_light == null:
		sustained_light = LightField.attach(self, Moonlight.MOON, radius * 1.15, FROST_LIGHT_ENERGY)
	queue_redraw()


func refresh_frost(hit: float, radius: float, slow_amount: float, tint: Color, shatter := false) -> void:
	damage = hit * 0.23
	effect_radius = radius
	slow = slow_amount
	color = tint
	shatter_frozen = shatter


func configure_scythe(origin: Vector2, heading: Vector2, grid: EnemySpatialGrid, hit: float, radius: float, sweep_arc: float, tint: Color, owner := -1, weapon_id := "") -> void:
	kind = Kind.SCYTHE
	global_position = origin
	direction = heading.normalized()
	spatial_grid = grid
	damage = hit
	effect_radius = radius
	arc = sweep_arc
	color = tint
	source_player = owner
	source_weapon = weapon_id
	duration = 0.34
	z_index = 4
	queue_redraw()


func configure_gravity(centre: Vector2, grid: EnemySpatialGrid, hit: float, radius: float, pull: float, tint: Color, callback := Callable(), owner := -1, weapon_id := "") -> void:
	kind = Kind.GRAVITY
	global_position = centre
	spatial_grid = grid
	damage = hit
	effect_radius = radius
	color = tint
	duration = 0.48
	finished_callback = callback
	source_player = owner
	source_weapon = weapon_id
	for enemy in spatial_grid.query_radius(centre, radius + 45.0):
		if not is_instance_valid(enemy) or enemy.dead or centre.distance_to(enemy.global_position) > radius + enemy.radius:
			continue
		var distance := centre.distance_to(enemy.global_position)
		# Planters are rooted scenery: keep them in the impacted set so the
		# collapse still damages them, but give them zero travel.
		var travel := 0.0 if enemy.scenery else minf(pull, maxf(0.0, distance - 26.0)) * (0.22 if enemy.boss else 1.0)
		pulls.append({"enemy": enemy, "start": enemy.global_position, "end": enemy.global_position.move_toward(centre, travel)})
	z_index = 4
	sustained_light = LightField.attach(self, tint, radius * 1.1, GRAVITY_LIGHT_ENERGY, true)
	queue_redraw()


func _physics_process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_physics_process(delta)
	FrameProbe.add(KIND_PROBES[kind], probe_started)


func _probed_physics_process(delta: float) -> void:
	age += delta
	if kind in [Kind.ORBIT, Kind.FROST]:
		if not is_instance_valid(anchor) or anchor.downed:
			if kind == Kind.ORBIT: queue_free()
			return
		global_position = anchor.global_position
		# The aura's reach changes as the weapon levels and as the area attribute
		# moves, and the light has to be the size of the ring it belongs to.
		if kind == Kind.FROST and sustained_light != null:
			sustained_light.texture_scale = maxf(0.2, effect_radius * 1.15 / 64.0)
	if kind == Kind.ORBIT:
		_update_orbit_fade()
		# Every frame, not on a tick: a shard sweeping past an enemy between two
		# ticks used to miss it entirely, which is why a visibly-connecting ring
		# often did nothing.
		_hit_orbit()
		_break_orbit_shots()
	elif kind == Kind.FROST:
		tick -= delta
		if tick <= 0.0:
			tick = 0.42
			_hit_frost()
	elif kind == Kind.SCYTHE:
		_hit_scythe()
	elif kind == Kind.GRAVITY:
		_step_gravity()
	_present()
	if age >= duration:
		if kind == Kind.GRAVITY:
			_finish_gravity()
		queue_free()


## The re-hit window is per shard, so an enemy parked in the ring takes one
## hit from every shard that sweeps over it. Long enough that a shard sitting on
## top of a slow enemy cannot machine-gun it, short enough that a fast ring is
## rewarded for being fast.
const ORBIT_REHIT := 0.45


func _hit_orbit() -> void:
	var phase := age * speed
	while shard_hits.size() < count:
		shard_hits.append({})
	for shard in count:
		var point := global_position + Vector2.from_angle(phase + TAU * float(shard) / count) * effect_radius
		var hits: Dictionary = shard_hits[shard]
		var reach := _shard_reach()
		for enemy in spatial_grid.query_radius(point, reach + 8.0):
			if not is_instance_valid(enemy) or enemy.dead: continue
			if point.distance_to(enemy.global_position) > reach + enemy.radius: continue
			var key := enemy.get_instance_id()
			if age - float(hits.get(key, -ORBIT_REHIT)) < ORBIT_REHIT: continue
			hits[key] = age
			enemy.take_damage(damage, source_player, source_weapon)


## Shards bat away what flies into them. Swept every frame at each shard's own
## position, like the enemy hit above, so a shot crossing the ring between two
## frames is caught by the same geometry that would have caught a body there.
func _break_orbit_shots() -> void:
	if enemy_shots.is_empty():
		return
	var phase := age * speed
	for shard in count:
		var point := global_position + Vector2.from_angle(phase + TAU * float(shard) / count) * effect_radius
		EnemyProjectile.break_within(enemy_shots, point, _shard_reach())


## How close a stone has to pass to strike. 26 at Lv.1, and a third of the
## drawn growth on top: the stone reads much bigger, but a ring that doubled its
## contact with every level would stop being a ring and become a disc.
func _shard_reach() -> float:
	return 26.0 * stone_reach_scale * (1.0 + (presence - 1.0) * 0.35)


func _update_orbit_fade() -> void:
	var fade_in := smoothstep(0.0, ORBIT_FADE_IN, age)
	var fade_out := smoothstep(0.0, ORBIT_FADE_OUT, maxf(0.0, duration - age))
	modulate.a = minf(fade_in, fade_out)


func _hit_frost() -> void:
	for enemy in spatial_grid.query_radius(global_position, effect_radius + 45.0):
		if not is_instance_valid(enemy) or enemy.dead: continue
		if global_position.distance_to(enemy.global_position) <= effect_radius + enemy.radius:
			var already_frozen := enemy.slow_timer > 0.0
			enemy.take_damage(damage * (2.4 if shatter_frozen and already_frozen else 1.0), source_player, source_weapon)
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
			enemy.take_damage(damage, source_player, source_weapon)
	# The crescent cuts shots out of the air on the same pass. Sampled along the
	# blade line rather than over the whole sector, so a swing clears what it
	# actually swept through and not everything standing in front of the survivor.
	if not enemy_shots.is_empty():
		for step in 4:
			var along := effect_radius * (0.25 + 0.25 * float(step))
			EnemyProjectile.break_within(enemy_shots, global_position + blade * along, effect_radius * 0.22)


func _step_gravity() -> void:
	var progress := clampf(age / duration, 0.0, 1.0)
	var eased := ease(progress, 2.2)
	if sustained_light != null:
		# Deepens and closes with the well: the dark spot is smallest and
		# strongest at the instant everything it caught arrives in the middle.
		sustained_light.energy = GRAVITY_LIGHT_ENERGY * eased
		sustained_light.texture_scale = maxf(0.2, effect_radius * (1.1 - eased * 0.55) / 64.0)
	for pull in pulls:
		var enemy = pull.get("enemy")
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.global_position = (pull["start"] as Vector2).lerp(pull["end"], eased)


func _finish_gravity() -> void:
	for pull in pulls:
		var enemy = pull.get("enemy")
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.take_damage(damage, source_player, source_weapon)
			if is_instance_valid(enemy) and not enemy.dead: enemy.apply_slow(1.2, 0.55)
	if finished_callback.is_valid(): finished_callback.call()


## Every field redrew itself every physics tick, which made weapon fields the
## second most expensive thing drawn in a late run (1.0ms a tick for five of
## them, tests/perf_bench_capture.gd). Two of the four kinds do not need it.
##
## An orbit ring turns as one piece — every shard and every trail sits at the
## same phase offset — so it is drawn once at phase zero and the node's own
## rotation turns it. A frost aura is two large filled discs that never change
## until the weapon levels, with a few arcs and flakes turning over them; the
## discs stay on this node and the motion moves to a child canvas item. The two
## short-lived kinds, the scythe sweep and the collapsing well, change shape
## every frame and still redraw.
func _present() -> void:
	match kind:
		Kind.ORBIT:
			rotation = age * speed
			_redraw_if_changed()
		Kind.FROST:
			_redraw_if_changed()
			if _frost_motion == null:
				_frost_motion = DrawProxy.new()
				_frost_motion.name = "FrostMotion"
				_frost_motion.painter = _draw_frost_motion
				add_child(_frost_motion)
			_frost_motion.queue_redraw()
		_:
			queue_redraw()


func _redraw_if_changed() -> void:
	var key := "%.2f|%d|%s" % [_visible_radius(), count, color.to_html()]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _draw_frost_motion(canvas: CanvasItem) -> void:
	var visible_radius := _visible_radius()
	for ring in 3:
		var start := age * (0.35 + ring * 0.1) + ring * 2.0
		canvas.draw_arc(Vector2.ZERO, maxf(1.0, visible_radius - ring * 7.0), start, start + 1.25, 18, Color(color, 0.20 + ring * 0.07), 2.5, true)
	for flake in 8:
		var at := Vector2.from_angle(flake * TAU / 8.0 - age * 0.18) * visible_radius * (0.62 + (flake % 2) * 0.2)
		canvas.draw_circle(at, 2.8, Color(color.lightened(0.4), 0.75))


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:weapon_field", probe_started)


func _probed_draw() -> void:
	match kind:
		Kind.ORBIT:
			var visible_radius := _visible_radius()
			# Drawn at phase zero; the node's rotation carries the spin (_present).
			var phase := 0.0
			# Five commands for the whole ring rather than four per shard; see
			# BatchPaint. Halos first, then the ring and trails, then the stars
			# over everything, which is the order each shard drew itself in.
			draw_arc(Vector2.ZERO, visible_radius, 0, TAU, 48, Color(color, 0.18), 2.0, true)
			var halos := BatchPaint.new()
			var stars := BatchPaint.new()
			var trails := PackedVector2Array()
			var outlines := PackedVector2Array()
			for shard in count:
				var angle := phase + TAU * float(shard) / count
				var point := Vector2.from_angle(angle) * visible_radius
				halos.fill_circle(point, 20.0 * presence * stone_reach_scale, Color(color, 0.10), 16)
				BatchPaint.arc_segments(trails, Vector2.ZERO, visible_radius, angle - 0.42, angle, 10)
				var star := _star_points(point, 11.0 * presence * stone_reach_scale)
				stars.fill_fan(point, star, color)
				BatchPaint.loop_segments(outlines, star)
			halos.flush(self)
			draw_multiline(trails, Color(color, 0.42), 4.0 * presence, true)
			stars.flush(self)
			draw_multiline(outlines, Color.WHITE, 1.5, true)
		Kind.FROST:
			var visible_radius := _visible_radius()
			# The aura's filled footprint is the damage rule; arcs are texture, not
			# the only thing describing its reach. Fixed-vertex discs remain stable
			# when area upgrades push the radius far beyond the viewport; Godot's
			# adaptive draw_circle tessellation can overflow at extreme radii.
			draw_colored_polygon(_disc_points(visible_radius, 72), Color(color, 0.075))
			draw_colored_polygon(_disc_points(visible_radius * 0.66, 64), Color(color.lightened(0.25), 0.045))
			# The turning arcs and flakes are drawn by _draw_frost_motion.
		Kind.SCYTHE:
			var visible_radius := _visible_radius()
			var progress := clampf(age / duration, 0.0, 1.0)
			var start := direction.angle() - arc * 0.5
			var current := start + arc * ease(progress, -1.7)
			var trail := maxf(start, current - minf(0.9, arc * 0.5))
			# A dim full fan telegraphs the committed footprint, then a broad filled
			# crescent paints the portion the blade has actually crossed.
			draw_colored_polygon(_sector_points(visible_radius * 0.16, visible_radius, start, start + arc, 36), Color(color, 0.075))
			if current - trail > 0.001:
				draw_colored_polygon(_sector_points(visible_radius * 0.20, visible_radius, trail, current, 18), Color(color, 0.42))
			draw_colored_polygon(_sector_points(visible_radius * 0.70, visible_radius * 1.04, current - 0.16, current + 0.035, 7), Color(color.lightened(0.42), 0.92))
			draw_arc(Vector2.ZERO, visible_radius, trail, current, 18, Color(color.lightened(0.35), 0.95), 18.0 * presence, true)
			var tip := Vector2.from_angle(current) * visible_radius
			draw_line(Vector2.from_angle(current) * visible_radius * 0.22, tip, Color.WHITE, 3.0 * presence, true)
			# An afterimage just inside the edge, lagging the blade: the smear a fast
			# swing leaves on the eye, which is what makes it read as fast.
			var echo := maxf(start, current - 0.28)
			if current - echo > 0.001:
				draw_arc(Vector2.ZERO, visible_radius * 0.84, echo, current - 0.06, 10,
					Color(Color.WHITE, 0.35 * (1.0 - progress)), 5.0, true)
			# The glint on the edge, brightest mid-swing.
			var glint := sin(progress * PI)
			draw_circle(tip, (5.0 + glint * 7.0) * presence, Color(1.0, 1.0, 1.0, 0.75 * glint))
		Kind.GRAVITY:
			var visible_radius := _visible_radius()
			var progress := clampf(age / duration, 0.0, 1.0)
			var collapse_radius := visible_radius * (1.0 - progress * 0.78)
			draw_circle(Vector2.ZERO, collapse_radius, Color(color, 0.08 + progress * 0.08))
			draw_circle(Vector2.ZERO, collapse_radius * 0.58, Color(color.darkened(0.35), 0.18 + progress * 0.12))
			for spiral in 4:
				var r := visible_radius * (1.0 - progress * 0.78) * (1.0 - spiral * 0.13)
				var start := -age * (5.0 + spiral)
				draw_arc(Vector2.ZERO, r, start, start + 3.9, 24, Color(color, 0.58 - spiral * 0.09), 4.0, true)
			draw_circle(Vector2.ZERO, 8.0 + progress * 18.0, Color(color, 0.18 + progress * 0.3))


func _star_points(at: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 8:
		points.append(at + Vector2.from_angle(index * TAU / 8.0) * (radius if index % 2 == 0 else radius * 0.42))
	return points


func _sector_points(inner_radius: float, outer_radius: float, start: float, finish: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var span := finish - start
	# Exact full rings overlap both seam edges and fail polygon triangulation.
	# A sub-pixel angular sliver is invisible but keeps this a simple polygon.
	if absf(span) >= TAU - 0.001:
		finish = start + signf(span) * (TAU - 0.001)
	for index in segments + 1:
		points.append(Vector2.from_angle(lerpf(start, finish, float(index) / float(segments))) * outer_radius)
	for index in segments + 1:
		points.append(Vector2.from_angle(lerpf(finish, start, float(index) / float(segments))) * inner_radius)
	return points


func _disc_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_radius := clampf(radius, 1.0, MAX_RENDER_RADIUS)
	for index in segments:
		points.append(Vector2.from_angle(TAU * float(index) / float(segments)) * safe_radius)
	return points


func _visible_radius() -> float:
	return minf(effect_radius, MAX_RENDER_RADIUS)
