class_name RooftopPrototype
extends Node2D
## The 2.5D rooftop, small enough to judge.
##
## The play rules stay two-dimensional: everything here moves on a plane, every
## hit is resolved on that plane, and nothing in this scene knows what a Z axis
## is. What it adds is the three things that make a flat plane read as a roof
## you are standing on — a floor with an edge you can see the thickness of,
## props with a top and a front, and a chain that hangs rather than being ruled.
##
## It is a separate scene rather than a change to the run because the question
## it exists to answer cannot be asked in the run. "Does movement still read?"
## needs a before and an after of the *same* fight, and the run's roof is
## endless and randomly furnished — two passes over it are never the same scene
## twice. Here the plate, the props and the spawns are fixed, so the four
## toggles below produce comparable pictures:
##
##   F1  height on/off — collapses the projection to the flat plan view the run
##       uses today. Everything else stays put, so this is the direct answer to
##       "is the tilt paying for itself?"
##   F2  see-through silhouettes on/off, for judging whether a cat behind a
##       planter is genuinely lost without them
##   F3  chain hang on/off — hung rope against the straight segment
##   F12 the existing moonlight pass, unchanged
##
## What this deliberately does not do is weapons. Height per weapon — milk and
## ice on the floor, stars and lightning at body height — is the next pass, and
## the reason it waits is that a projectile's height is only legible once the
## ground it is flying over has a legible height of its own.

const PropScript := preload("res://scripts/entities/rooftop_prop.gd")
const SectionScript := preload("res://scripts/entities/rooftop_section.gd")
const ProxyScript := preload("res://scripts/effects/draw_proxy.gd")
const ChainArcScript := preload("res://scripts/effects/chain_arc.gd")
const ChainFlowScript := preload("res://scripts/effects/chain_flow.gd")
const ParticleScript := preload("res://scripts/systems/particle_field.gd")
const FlightScript := preload("res://scripts/effects/flight_field.gd")
const GridScript := preload("res://scripts/systems/enemy_spatial_grid.gd")
const ProjectileScript := preload("res://scripts/entities/projectile.gd")
const MilkPoolScript := preload("res://scripts/effects/milk_pool.gd")
const MineScript := preload("res://scripts/entities/proximity_mine.gd")
const UIFont := preload("res://assets/fonts/Jua-Regular.ttf")

## The chain is the only weapon in this scene. That is not a shortcut: the
## chain is the mechanic whose drawn shape and damaged shape have to agree, so
## a prototype about how the chain looks should also be the one that proves the
## two are the same curve. Damage per second of contact.
const CHAIN_DAMAGE := 74.0
const ENEMY_TARGET := 7
const SPAWN_INTERVAL := 1.5
## One weapon from each half of the roster, so the two heights can be compared
## in the same fight rather than described. The star flies at body height with a
## shadow running under it; the milk and the mine are the floor.
const AIR_WEAPON := "homing"
const GROUND_WEAPON := "milk"
const SHOT_INTERVAL := 0.62
const GROUND_INTERVAL := 3.4
## Where P1 and P2 start, either side of the plate's middle.
const START_GAP := 150.0
## How much of a cat has to be behind something before it is drawn through it.
const HIDDEN_SHARE := 0.34
const CAMERA_ZOOM := 0.82
## How much of the drop past the far parapet, and of the wall below the near
## one, the camera is allowed to travel far enough to show.
const SKY_HEADROOM := 200.0
const WALL_HEADROOM := 260.0

var section: RooftopSection
var backdrop: DrawProxy
var near_city: DrawProxy
var walls: DrawProxy
var near_edge: DrawProxy
var xray: DrawProxy
var stage: Node2D
var chain_arc: ChainArc
var chain_flow: ChainFlow
var particles: ParticleField
var flight: FlightField
var grid: EnemySpatialGrid
var world_camera: Camera2D
var legend: Label

var players: Array[ChainPlayer] = []
var enemies: Array[ChaserEnemy] = []
var props: Array[RooftopProp] = []
var chain_length := 360.0
var spawn_timer := 0.0
var shot_timer := 0.0
var ground_timer := 1.0
var shots: Array[HomingProjectile] = []
var elapsed := 0.0
## P2 tags along until someone actually presses its keys, so one person can
## walk the pair around the plate and still see the chain do its work.
var companion_is_local := false
var show_silhouettes := true
var hang_chain := true


func _ready() -> void:
	_bind_input()
	_build_world()
	_place_props()
	_spawn_pair()
	set_process(true)
	set_physics_process(true)


func _build_world() -> void:
	# The floor first, then the city it looks down on, then the walls that close
	# the gap between them. The order is the roof's own section drawing, and the
	# reason it is three nodes rather than one is that the floor's trim has to
	# be under the city while the walls have to be over it.
	section = SectionScript.new() as RooftopSection
	add_child(section)
	backdrop = ProxyScript.new() as DrawProxy
	backdrop.z_index = -24
	backdrop.painter = func(canvas: CanvasItem) -> void: section.draw_backdrop(canvas)
	add_child(backdrop)
	near_city = ProxyScript.new() as DrawProxy
	near_city.z_index = -22
	near_city.painter = func(canvas: CanvasItem) -> void: section.draw_near_city(canvas)
	add_child(near_city)
	walls = ProxyScript.new() as DrawProxy
	walls.z_index = -20
	walls.painter = func(canvas: CanvasItem) -> void: section.draw_walls(canvas)
	add_child(walls)


	particles = ParticleScript.new() as ParticleField
	add_child(particles)

	grid = GridScript.new() as EnemySpatialGrid
	flight = FlightScript.new() as FlightField
	add_child(flight)

	# The one node in the scene that sorts. Props, cats and enemies are all its
	# children at the same depth, so Godot orders them by where each one meets
	# the floor — which is the whole of the front-to-back rule, and the reason
	# every one of those classes anchors its drawing to that point.
	stage = Node2D.new()
	stage.name = "Stage"
	stage.y_sort_enabled = true
	stage.z_index = 4
	add_child(stage)

	# The chain joins the sorted layer rather than sitting under all of it. Both
	# halves are anchored at the pair's midpoint and drawn around it, so the rope
	# sorts against the furniture by the same ground line everything else uses —
	# a chain permanently behind every planter went behind them even when both
	# cats were standing in front.
	chain_arc = ChainArcScript.new() as ChainArc
	chain_arc.z_index = 0
	stage.add_child(chain_arc)
	chain_flow = ChainFlowScript.new() as ChainFlow
	chain_flow.z_index = 0
	stage.add_child(chain_flow)

	near_edge = ProxyScript.new() as DrawProxy
	near_edge.z_index = 10
	near_edge.painter = func(canvas: CanvasItem) -> void: section.draw_near_edge(canvas)
	add_child(near_edge)

	xray = ProxyScript.new() as DrawProxy
	xray.z_index = 12
	xray.live = true
	xray.painter = _draw_silhouettes
	add_child(xray)

	world_camera = Camera2D.new()
	world_camera.enabled = true
	world_camera.position_smoothing_enabled = false
	# Pulled back far enough that the plate's own edge is reachable in frame.
	# That is not a framing preference, it is the subject: the thickness of this
	# roof is only ever visible at the moment the floor stops, so a view that
	# can never contain an edge cannot answer the question the scene is asking.
	world_camera.zoom = Vector2.ONE * CAMERA_ZOOM
	add_child(world_camera)
	_build_legend()


## Hand-placed rather than hashed out of the cell grid the run uses. A fixed
## arrangement is the point: the same planter has to be in the same place in
## the before shot and the after one, and a few deliberate cases — one pipe
## tall enough to hide a cat completely, one cluster to walk between — say more
## about whether the depth reads than a scattering would.
func _place_props() -> void:
	var layout := [
		["planter", Vector2(-430.0, -250.0)], ["planter", Vector2(-330.0, -150.0)],
		["planter", Vector2(360.0, -300.0)], ["vent", Vector2(-120.0, 60.0)],
		["vent", Vector2(470.0, 120.0)], ["crate", Vector2(150.0, -180.0)],
		["crate", Vector2(205.0, -120.0)], ["crate", Vector2(-560.0, 240.0)],
		["duct", Vector2(-40.0, 330.0)], ["duct", Vector2(430.0, -20.0)],
		["pipe", Vector2(-250.0, 190.0)], ["pipe", Vector2(620.0, 320.0)],
		["planter", Vector2(-640.0, -80.0)], ["vent", Vector2(230.0, 260.0)],
	]
	for index in layout.size():
		var entry: Array = layout[index]
		var prop := PropScript.new() as RooftopProp
		prop.setup(String(entry[0]), entry[1] as Vector2, index)
		stage.add_child(prop)
		props.append(prop)


func _spawn_pair() -> void:
	var roster := CharacterCatalog.all_characters()
	var picks := [roster[0], roster[min(3, roster.size() - 1)]]
	for index in 2:
		var cat := ChainPlayer.new()
		cat.setup(index + 1, Color(picks[index]["color"]))
		cat.apply_character(picks[index])
		cat.display_index = index + 1
		cat.display_name = "나" if index == 0 else "동료"
		cat.position = Vector2(START_GAP * (float(index) * 2.0 - 1.0), 90.0)
		# Inside a sorted layer every actor has to share one depth, or z_index
		# decides the order before the sorting ever gets a say.
		cat.z_index = 0
		cat.stand_height = RooftopSpace.CAT_STAND
		cat.input_source = ChainPlayer.InputSource.LOCAL if index == 0 else ChainPlayer.InputSource.AI
		cat.footfall.connect(_on_footfall)
		stage.add_child(cat)
		players.append(cat)
	chain_length = CharacterCatalog.chain_length_for(picks[0], picks[1])


func _bind_input() -> void:
	# The prototype runs without main.gd, so it registers the handful of actions
	# it actually reads. Same physical keys as the run, so muscle memory carries.
	var keys := {
		"p1_left": KEY_A, "p1_right": KEY_D, "p1_up": KEY_W, "p1_down": KEY_S, "p1_dash": KEY_SPACE,
		"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_up": KEY_UP, "p2_down": KEY_DOWN,
		"p2_dash": KEY_PERIOD,
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


func _build_legend() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	legend = Label.new()
	legend.add_theme_font_override("font", UIFont)
	legend.add_theme_font_size_override("font_size", 15)
	legend.add_theme_color_override("font_color", Color("d7e6f2"))
	legend.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	legend.add_theme_constant_override("shadow_offset_y", 2)
	legend.position = Vector2(24.0, 18.0)
	layer.add_child(legend)
	_refresh_legend()


func _refresh_legend() -> void:
	legend.text = "\n".join([
		"옥상 2.5D 시제품 · WASD 이동 / Space 대시 · 방향키로 동료 조작",
		"별은 몸 높이 · 우유는 바닥 — 그림자와 착탄 빛으로 구분",
		"F1 높이 %s · F2 실루엣 비침 %s · F3 사슬 처짐 %s · F12 달빛 %s" % [
			_state(RooftopSpace.depth_scale > 0.5), _state(show_silhouettes),
			_state(hang_chain), _state(Moonlight.enabled),
		],
	])


func _state(on: bool) -> String:
	return "켜짐" if on else "꺼짐"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F1:
			# Collapsing the projection rather than hiding the props: the same
			# roof, the same furniture, seen straight down. Only the lift goes.
			RooftopSpace.depth_scale = 0.0 if RooftopSpace.depth_scale > 0.5 else 1.0
			_redraw_world()
		KEY_F2:
			show_silhouettes = not show_silhouettes
		KEY_F3:
			hang_chain = not hang_chain
		KEY_F12:
			Moonlight.enabled = not Moonlight.enabled
			_redraw_world()
		_:
			return
	_refresh_legend()


func _redraw_world() -> void:
	section.queue_redraw()
	backdrop.queue_redraw()
	near_city.queue_redraw()
	walls.queue_redraw()
	near_edge.queue_redraw()
	for prop in props:
		prop.queue_redraw()
	for cat in players:
		cat.queue_redraw()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_redraw()


func _physics_process(delta: float) -> void:
	elapsed += delta
	_drive_companion()
	for cat in players:
		cat.step_movement(delta)
		cat.step_recovery(delta)
		cat.step_bleedout(delta)
	_apply_chain_constraint()
	_clamp_to_plate()
	_update_chain()
	grid.rebuild(enemies)
	_step_enemies(delta)
	_fire_weapons(delta)
	flight.step(delta)
	particles.step(delta)
	_update_camera(delta)


## The leash, reduced to the part this scene needs: neither cat may end a frame
## further from the other than the chain is long, and the one straining outward
## is the one pulled back. The run's version also loads, warns and overloads;
## none of that changes what the rope looks like, so none of it is here.
func _apply_chain_constraint() -> void:
	var span := players[1].position - players[0].position
	var over := span.length() - chain_length
	if over <= 0.0:
		return
	var pull := span.normalized() * over
	var first_strain := players[0].current_input.dot(-span.normalized())
	var second_strain := players[1].current_input.dot(span.normalized())
	var share := clampf(inverse_lerp(-1.0, 1.0, first_strain - second_strain), 0.0, 1.0)
	players[0].position += pull * (1.0 - share)
	players[1].position -= pull * share


## The parapet is the one piece of scenery here that is not decoration, so the
## pair is actually held inside it. Everything else on this roof can be walked
## straight through, exactly as it can in the run.
func _clamp_to_plate() -> void:
	var field := section.bounds.grow(-26.0)
	for cat in players:
		cat.position.x = clampf(cat.position.x, field.position.x, field.end.x)
		cat.position.y = clampf(cat.position.y, field.position.y, field.end.y)


func _drive_companion() -> void:
	var companion := players[1]
	if companion.input_source == ChainPlayer.InputSource.LOCAL:
		return
	var pressed := Input.get_vector("p2_left", "p2_right", "p2_up", "p2_down")
	if pressed.length_squared() > 0.04:
		companion.input_source = ChainPlayer.InputSource.LOCAL
		companion_is_local = true
		return
	# Hold station off the leader's shoulder at a little over half the leash, so
	# the chain spends most of its time slack and the sag is what you see.
	var anchor := players[0].position - players[0].facing * chain_length * 0.45
	var offset := anchor - companion.position
	companion.set_command(offset / 60.0 if offset.length() > 26.0 else Vector2.ZERO)


## Where the chain actually lies on the roof, in world coordinates.
##
## The two chain nodes are anchored at the pair's midpoint so the sorted layer
## can order them, which means everything they hand back is measured from that
## anchor. Damage and the see-through pass both want the floor, so the
## conversion lives here rather than in either of their callers.
func chain_path() -> PackedVector2Array:
	var path := PackedVector2Array()
	for point in chain_arc.ground_points():
		path.append(point + chain_arc.position)
	return path


func _update_chain() -> void:
	var ratio := players[0].position.distance_to(players[1].position) / chain_length
	var tint := Color("43d9ff")
	var band := 0
	if ratio >= 0.95:
		band = 3
		tint = Color("ff5d8f")
	elif ratio >= 0.8:
		band = 2
		tint = Color("fff275")
	elif ratio >= 0.55:
		band = 1
		tint = Color("8ecae6")
	# Turning the hang off feeds the arc a leash it can never be slack against,
	# which is the straight segment the run draws today — same code path, so the
	# comparison is of the shape alone and not of two different renderers.
	var anchor := (players[0].position + players[1].position) * 0.5
	chain_arc.position = anchor
	chain_flow.position = anchor
	chain_arc.set_state(players[0].position - anchor, players[1].position - anchor, tint,
		chain_length if hang_chain else 0.001)
	chain_flow.set_state(players[0].position - anchor, players[1].position - anchor, tint, band, false, false)
	chain_flow.curve = chain_arc.drawn_points()


func _step_enemies(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0 and enemies.size() < ENEMY_TARGET:
		spawn_timer = SPAWN_INTERVAL
		_spawn_enemy()
	var path := chain_path()
	var living: Array[ChaserEnemy] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		enemy.step(players, delta)
		# The chain kills what it sweeps over, and it sweeps along the curve it
		# is drawn as. On a slack chain that belly is a real difference of some
		# fifty pixels, so "the rope you can see is the rope that hurts" has to
		# be sampled and not assumed.
		if _touches_path(path, enemy.global_position, enemy.radius + 7.0):
			enemy.take_damage(CHAIN_DAMAGE * delta)
			if enemy.dead:
				particles.emit_sparks(enemy.global_position, Color("ffd6e8"), 7)
				continue
		living.append(enemy)
	enemies = living


func _spawn_enemy() -> void:
	var enemy := ChaserEnemy.new()
	enemy.setup(1.0, "chaser")
	enemy.z_index = 0
	var edge := section.bounds.grow(-60.0)
	var corner := randi() % 4
	var at := Vector2(randf_range(edge.position.x, edge.end.x), randf_range(edge.position.y, edge.end.y))
	# Pushed out to one edge so the walk in is long enough to watch it pass
	# behind and in front of the furniture, which is the thing being judged.
	match corner:
		0: at.y = edge.position.y
		1: at.y = edge.end.y
		2: at.x = edge.position.x
		_: at.x = edge.end.x
	enemy.position = at
	stage.add_child(enemy)
	enemies.append(enemy)


## The two halves of the roster, fired side by side.
##
## This is the part of the height work that only shows in motion: a star drawn
## at body height with a shadow sliding along the floor under it occupies space
## in a way a puddle lying on that floor does not, and neither reads as having a
## height at all until the other one is next to it.
func _fire_weapons(delta: float) -> void:
	shot_timer -= delta
	ground_timer -= delta
	if shot_timer <= 0.0 and not enemies.is_empty():
		shot_timer = SHOT_INTERVAL
		_fire_star()
	if ground_timer <= 0.0:
		ground_timer = GROUND_INTERVAL
		_pour_milk()
	var airborne: Array[HomingProjectile] = []
	for shot in shots:
		if is_instance_valid(shot) and shot.active:
			airborne.append(shot)
	shots = airborne


func _fire_star() -> void:
	var from := players[0]
	var target := grid.nearest(from.position, 900.0)
	if target == null:
		return
	var shot := ProjectileScript.new() as HomingProjectile
	add_child(shot)
	shot.global_position = from.position
	shot.setup(from.position.direction_to(target.global_position), target)
	shot.spatial_grid = grid
	shot.style = "star"
	shot.projectile_color = from.body_color
	shot.damage = 26.0
	shot.flight_height = RooftopSpace.weapon_height(AIR_WEAPON)
	shot.released.connect(_on_shot_landed.bind(shot))
	flight.track(shot, shot.flight_height, shot.radius)
	shots.append(shot)


## A star is spent where it stops, and where it stops is a point on the roof —
## so the mark it leaves goes on the floor under it, not at the height it was
## flying at.
func _on_shot_landed(_released: HomingProjectile, shot: HomingProjectile) -> void:
	flight.flash(shot.ground_position, shot.projectile_color, 30.0)
	shot.queue_free()


func _pour_milk() -> void:
	var pool := MilkPoolScript.new() as MilkPool
	add_child(pool)
	# Smaller and shorter-lived than the run pours them. At full size two pools
	# overlap into one pale sheet across the middle of the plate, and a floor
	# weapon that covers the floor is no longer a demonstration of what a floor
	# weapon looks like against the roof it is lying on.
	pool.configure(players[1].position + players[1].facing * 90.0, grid,
		9.0, 58.0, 0.55, Color("f2e2c4"), 3.6, 1, GROUND_WEAPON)


func _touches_path(path: PackedVector2Array, at: Vector2, reach: float) -> bool:
	for index in path.size() - 1:
		if Geometry2D.get_closest_point_to_segment(at, path[index], path[index + 1]).distance_to(at) <= reach:
			return true
	return false


func _on_footfall(at: Vector2, color: Color) -> void:
	particles.emit_dust(at, color)


func _update_camera(delta: float) -> void:
	var midpoint := (players[0].position + players[1].position) * 0.5
	# Lifted the same way every body in this scene is lifted, so the pair sits
	# where the eye expects rather than riding low once the roof gained height.
	midpoint += RooftopSpace.lift(RooftopSpace.CAT_STAND) - Vector2(0.0, 60.0)
	var half := Vector2(640.0, 360.0) / CAMERA_ZOOM
	var limit_low := Vector2(
		section.bounds.position.x - 90.0 + half.x, section.far_limit() - SKY_HEADROOM + half.y)
	var limit_high := Vector2(
		section.bounds.end.x + 90.0 - half.x, section.bounds.end.y + WALL_HEADROOM - half.y)
	midpoint.x = clampf(midpoint.x, minf(limit_low.x, limit_high.x), maxf(limit_low.x, limit_high.x))
	midpoint.y = clampf(midpoint.y, minf(limit_low.y, limit_high.y), maxf(limit_low.y, limit_high.y))
	world_camera.position = world_camera.position.lerp(midpoint, minf(1.0, delta * 8.0))
	# Only the city lags. The floor the fight happens on and everything standing
	# on it move exactly with the camera, because a play surface that drifts is
	# a play surface nobody can aim across.
	backdrop.position.x = world_camera.position.x * RooftopSection.SKYLINE_LAG
	near_city.position.x = world_camera.position.x * RooftopSection.NEAR_LAG


## Everything that is currently hidden, drawn faintly on top of whatever is
## hiding it.
##
## The rule this scene is testing is that depth may cost visibility but must
## never cost *position*. A cat that walks behind a pipe should be behind the
## pipe — that is the whole point — but the player still has to know which side
## of it the cat came out on, and a chain whose middle disappears behind a vent
## still has to say where it is about to sweep.
func _draw_silhouettes(canvas: CanvasItem) -> void:
	if not show_silhouettes:
		return
	var covers := _occluders()
	var hidden := false
	for cat in players:
		if not _is_hidden(cat, covers):
			continue
		hidden = true
		var at := RooftopSpace.raised(cat.position, cat.stand_height)
		canvas.draw_circle(at, cat.radius, Color(cat.body_color, 0.22))
		canvas.draw_arc(at, cat.radius, 0.0, TAU, 26, Color(cat.body_color, 0.75), 2.0, true)
		# The contact mark is the part that actually answers "where is it": the
		# silhouette says which cat, the ring on the floor says where it stands.
		canvas.draw_arc(cat.position, cat.radius * 0.55, 0.0, TAU, 18, Color(cat.body_color, 0.5), 1.6, true)
	if hidden:
		var rope := PackedVector2Array()
		for point in chain_arc.drawn_points():
			rope.append(point + chain_arc.position)
		canvas.draw_polyline(rope, Color(chain_arc.tint, 0.3), 2.0, true)


## Whether enough of this cat is behind something to be worth showing through.
##
## The threshold is the whole of it. A cat brushing past the corner of a vent
## overlaps it by a few pixels and is in no danger of being lost, and putting a
## ring on that cat every time it walks near furniture turns the see-through
## pass into a permanent outline nobody reads any more. So the silhouette waits
## until a real share of the body is actually gone.
func _is_hidden(cat: ChainPlayer, covers: Array) -> bool:
	var body := _body_rect(cat)
	var area := body.get_area()
	if area <= 0.0:
		return false
	for cover: Array in covers:
		if float(cover[1]) <= cat.position.y:
			continue
		var shared := (cover[0] as Rect2).intersection(body)
		if shared.get_area() / area >= HIDDEN_SHARE:
			return true
	return false


## Screen rectangles that can hide something, each with the floor line that
## decides who it hides: the props, and the near parapet the plate ends at.
func _occluders() -> Array:
	var covers: Array = []
	for prop in props:
		if prop.bulky():
			covers.append([prop.screen_rect(), prop.position.y])
	var wall_top := section.bounds.end.y - RooftopSection.PARAPET_HEIGHT * RooftopSpace.tilt()
	covers.append([
		Rect2(section.bounds.position.x, wall_top, section.bounds.size.x,
			section.bounds.end.y + RooftopSection.PARAPET_DEPTH - wall_top),
		section.bounds.end.y + RooftopSection.PARAPET_DEPTH,
	])
	return covers


func _body_rect(cat: ChainPlayer) -> Rect2:
	var at := RooftopSpace.raised(cat.position, cat.stand_height)
	return Rect2(at.x - cat.radius, at.y - cat.radius * 1.6, cat.radius * 2.0, cat.radius * 1.6 + (cat.position.y - at.y))
