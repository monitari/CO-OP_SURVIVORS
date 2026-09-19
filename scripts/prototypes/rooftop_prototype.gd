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
const UIFont := preload("res://scripts/ui/cat_theme.gd").FAMILY

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
## Names for the three views, in the order F1 walks through them.
const VIEW_NAMES := ["평면", "높이", "원근"]
const GROUND_INTERVAL := 3.4
## Where P1 and P2 start, either side of the plate's middle.
const START_GAP := 150.0
## How much of a cat has to be behind something before it is drawn through it.
const HIDDEN_SHARE := 0.34
const CAMERA_ZOOM := 0.7
## How much of the drop past the far parapet, and of the wall below the near
## one, the camera is allowed to travel far enough to show.
const SKY_HEADROOM := 170.0
const WALL_HEADROOM := 120.0

var section: RooftopSection
var night: DrawProxy
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
## Every actor's point on the flat floor, which is the only position any rule in
## this scene reads. Node positions hold the *projected* point between frames so
## the scene draws itself in perspective, and gameplay never sees them: the
## physics step puts the grounds back on the nodes, runs, takes the new grounds
## off again, and only then projects. That swap is what keeps a cat's walking
## speed the same at the far edge of the roof as at the near one, which a scene
## played directly in projected coordinates could not manage.
var grounds: Array[Vector2] = []
var enemy_grounds: Array[Vector2] = []
var props: Array[RooftopProp] = []
var chain_length := 360.0
var spawn_timer := 0.0
var shot_timer := 0.0
var ground_timer := 1.0
var shots: Array[HomingProjectile] = []
## Floor weapons, kept so the view can place them. A puddle is a decal lying on
## the roof, so it belongs at its floor point scaled by the depth there — left
## alone it would be a circle painted flat over a receding surface, which is
## exactly the thing a projected floor makes obvious.
var pools: Array[MilkPool] = []
var pool_grounds: Array[Vector2] = []
var elapsed := 0.0
## P2 tags along until someone actually presses its keys, so one person can
## walk the pair around the plate and still see the chain do its work.
var companion_is_local := false
var show_silhouettes := true
var hang_chain := true


func _ready() -> void:
	# The scene exists to be looked at in perspective — that is the thing being
	# judged — so it opens in that view rather than in the LIFTED default the
	# static var otherwise carries over from wherever it was last left (a test
	# run, an earlier launch). F1 still cycles through all three from here.
	RooftopSpace.view_mode = RooftopSpace.View.PERSPECTIVE
	_bind_input()
	_build_world()
	_place_props()
	_spawn_pair()
	RooftopSpace.focus = (players[0].position + players[1].position) * 0.5
	world_camera.position = RooftopSpace.focus
	_to_view()
	set_process(true)
	set_physics_process(true)


func _build_world() -> void:
	# The floor first, then the city it looks down on, then the walls that close
	# the gap between them. The order is the roof's own section drawing, and the
	# reason it is three nodes rather than one is that the floor's trim has to
	# be under the city while the walls have to be over it.
	# A trapezoid does not fill a rectangular screen, and what is left over at
	# its corners is the night the building stands in. Painting it deliberately
	# is the difference between a roof floating in a void and a roof the view
	# happens not to reach the far side of.
	night = ProxyScript.new() as DrawProxy
	night.z_index = -40
	night.live = true
	night.painter = func(canvas: CanvasItem) -> void:
		canvas.draw_rect(Rect2(RooftopSpace.focus - Vector2(2400.0, 1600.0), Vector2(4800.0, 3200.0)),
			RooftopSection.SKY)
	add_child(night)

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

	# The chain joins the sorted layer, but at its own depth under the actors
	# rather than sorted among them — see ChainArc.BEHIND_ACTORS for why that is
	# a rule and not a preference. Both nodes are added here so the running
	# light lands on the rope, and both are given the pair's colour every frame.
	chain_arc = ChainArcScript.new() as ChainArc
	stage.add_child(chain_arc)
	chain_flow = ChainFlowScript.new() as ChainFlow
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
	grounds.clear()
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
		grounds.append(cat.position)
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
		"옥상 2.5D 시제품    WASD 이동 / Space 대시    방향키로 동료 조작",
		"별은 몸 높이    우유는 바닥 — 그림자와 착탄 빛으로 구분",
		"F1 시점 %s    F2 실루엣 비침 %s    F3 사슬 처짐 %s    F12 달빛 %s" % [
			VIEW_NAMES[RooftopSpace.view_mode], _state(show_silhouettes),
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
			# Cycles the same roof through all three views rather than switching
			# one off. Nothing about the scene changes except how it is being
			# looked at, which is the only way to tell whether the trapezoid is
			# paying for itself against the plan view it replaced.
			RooftopSpace.view_mode = (RooftopSpace.view_mode + 1) % VIEW_NAMES.size()
			_to_view()
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
	# The projection is measured from wherever the camera actually is, not from
	# where it is heading, so that the floor does not slide under the pair while
	# the view is still catching up to them.
	RooftopSpace.focus = world_camera.position
	_to_ground()
	_drive_companion()
	for cat in players:
		cat.step_movement(delta)
		cat.step_recovery(delta)
		cat.step_bleedout(delta)
	_apply_chain_constraint()
	_clamp_to_plate()
	grid.rebuild(enemies)
	_step_enemies(delta)
	_fire_weapons(delta)
	_update_chain()
	flight.step(delta)
	particles.step(delta)
	_to_view()
	_update_camera(delta)
	if RooftopSpace.view_mode == RooftopSpace.View.PERSPECTIVE:
		# Every piece of architecture is measured from the focus, so all of it is
		# stale the moment the camera moves. Only the floor layers pay this — the
		# props and the actors are billboards whose drawings never change, just
		# where they are placed and how big they are.
		_redraw_world()


## Puts the flat floor back under the actors for the length of one step. Between
## calls their nodes hold projected positions, which are for looking at and for
## nothing else.
func _to_ground() -> void:
	for index in players.size():
		players[index].position = grounds[index]
	for index in enemies.size():
		if is_instance_valid(enemies[index]):
			enemies[index].position = enemy_grounds[index]


## And takes them off again, placing and sizing every body by the view. A body
## is a billboard: it moves to where its floor point projects to and is scaled by
## how far away that is, and it is never sheared — a cat leaning with the
## perspective reads as a cat falling over.
func _to_view() -> void:
	for index in players.size():
		grounds[index] = players[index].position
		players[index].position = RooftopSpace.project(grounds[index])
		players[index].scale = Vector2.ONE * RooftopSpace.view_scale(grounds[index].y)
	for index in enemies.size():
		var enemy := enemies[index]
		if not is_instance_valid(enemy):
			continue
		enemy_grounds[index] = enemy.position
		enemy.position = RooftopSpace.project(enemy_grounds[index])
		# Rebuilt from the two things that decide it rather than multiplied into
		# what is already there. An enemy spends its own scale on the hit flash,
		# so scaling the node in place compounded the view into itself every
		# frame and grew a chaser to the size of the roof in about a second.
		enemy.scale = Vector2.ONE * RooftopSpace.view_scale(enemy_grounds[index].y) 			* (1.0 + enemy.hit_flash * 0.22)
	for prop in props:
		prop.position = RooftopSpace.project(prop.ground)
		prop.scale = Vector2.ONE * RooftopSpace.view_scale(prop.ground.y)
	var living_pools: Array[MilkPool] = []
	var living_pool_grounds: Array[Vector2] = []
	for index in pools.size():
		var pool := pools[index]
		if not is_instance_valid(pool):
			continue
		var ground: Vector2 = pool_grounds[index]
		var scale := RooftopSpace.view_scale(ground.y)
		pool.position = RooftopSpace.project(ground)
		# Squashed as well as scaled: a puddle lies in the floor plane rather
		# than facing the camera, so a round one is an ellipse from here.
		pool.scale = Vector2(scale, scale * RooftopSpace.floor_squash(ground.y))
		living_pools.append(pool)
		living_pool_grounds.append(pool_grounds[index])
	pools = living_pools
	pool_grounds = living_pool_grounds


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


## Where the chain actually lies on the roof: its path across the flat floor, in
## the same world coordinates every rule in this scene uses. What the chain
## damages is read from here and what it is drawn as is the projection of the
## very same samples, which is the one place this scene cannot afford the two to
## drift apart.
func chain_path() -> PackedVector2Array:
	return chain_arc.ground_points()


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
	# The arc takes floor points and moves itself to where the middle of the rope
	# projects to; the light is pinned to the same anchor and handed the rope in
	# that frame, so the two can never disagree about where the chain is.
	chain_arc.set_state(players[0].position, players[1].position, tint,
		chain_length if hang_chain else 0.001)
	chain_flow.position = chain_arc.position
	chain_flow.set_state(
		RooftopSpace.raised(players[0].position, RooftopSpace.CHAIN_ANCHOR) - chain_arc.position,
		RooftopSpace.raised(players[1].position, RooftopSpace.CHAIN_ANCHOR) - chain_arc.position,
		tint, band, false, false)
	chain_flow.curve = chain_arc.local_points()


func _step_enemies(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0 and enemies.size() < ENEMY_TARGET:
		spawn_timer = SPAWN_INTERVAL
		_spawn_enemy()
	var path := chain_path()
	var living: Array[ChaserEnemy] = []
	# Grounds are rebuilt alongside the list they belong to. Two arrays kept in
	# step by index is the cheapest way to give a body a second position, and it
	# only works if every place that drops an enemy drops its floor point in the
	# same breath.
	var living_grounds: Array[Vector2] = []
	for index in enemies.size():
		var enemy := enemies[index]
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
		living_grounds.append(enemy.position)
	enemies = living
	enemy_grounds = living_grounds


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
	enemy_grounds.append(at)


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
	flight.track(shot)
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
	var at := players[1].position + players[1].facing * 90.0
	pool.configure(at, grid, 9.0, 58.0, 0.55, Color("f2e2c4"), 3.6, 1, GROUND_WEAPON)
	pools.append(pool)
	pool_grounds.append(at)


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
	for index in players.size():
		var cat := players[index]
		if not _is_hidden(cat, covers):
			continue
		hidden = true
		var ground: Vector2 = grounds[index]
		var scale := RooftopSpace.view_scale(ground.y)
		var at := RooftopSpace.raised(ground, cat.stand_height)
		canvas.draw_circle(at, cat.radius * scale, Color(cat.body_color, 0.22))
		canvas.draw_arc(at, cat.radius * scale, 0.0, TAU, 26, Color(cat.body_color, 0.75), 2.0, true)
		# The contact mark is the part that actually answers "where is it": the
		# silhouette says which cat, the ring on the floor says where it stands.
		canvas.draw_arc(RooftopSpace.project(ground), cat.radius * 0.55 * scale, 0.0, TAU, 18,
			Color(cat.body_color, 0.5), 1.6, true)
	if hidden:
		canvas.draw_polyline(chain_arc.drawn_points(), Color(chain_arc.tint, 0.3), 2.0, true)


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
		# Both sides of this comparison are projected rows. The projection keeps
		# the order of the floor, so front-to-back means the same thing here as
		# it does on the flat plane.
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
	# The near parapet, as the band of screen it actually covers: from the top of
	# its lid down to where its face meets the wall below.
	var outer := section.bounds.grow(RooftopSection.PARAPET_DEPTH)
	var lid := RooftopSpace.raised(Vector2(outer.position.x, section.bounds.end.y), RooftopSection.PARAPET_HEIGHT)
	var foot := RooftopSpace.project(Vector2(outer.end.x, outer.end.y))
	covers.append([
		Rect2(lid.x, lid.y, foot.x - lid.x, foot.y - lid.y), foot.y,
	])
	return covers


## What the cat covers on screen. Built from the projected body rather than from
## the floor point, since that is the thing a prop can actually hide.
func _body_rect(cat: ChainPlayer) -> Rect2:
	var scale := cat.scale.x
	var at := cat.position + RooftopSpace.lift(cat.stand_height) * scale
	var reach := cat.radius * scale
	# The drawing hangs well below the point the cat stands on — the portrait is
	# nearly three times the collision radius and is centred on it — so the rect
	# has to reach past the floor point as well as above it. Measuring only down
	# to the floor line let a cat stand with its whole lower half behind the near
	# parapet and count as unhidden.
	var top := at.y - reach * 1.6
	return Rect2(at.x - reach, top, reach * 2.0, (cat.position.y + reach * 1.3) - top)
