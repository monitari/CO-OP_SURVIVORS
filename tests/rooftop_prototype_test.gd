extends SceneTree

## The 2.5D rooftop prototype, checked on the four claims it makes.
##
## Every one of them is a claim about the relationship between where something
## *is* and where it is *drawn*, because that gap is the only thing the height
## work introduces and therefore the only thing it can break. A prop that draws
## in the wrong place is a cosmetic bug; a chain that damages somewhere other
## than where it is drawn is a lost run.
##
## Pass `--capture` to also save the comparison shots. That needs a real
## renderer, so it is run windowed — under `--headless` there is no rendering
## device and every frame saved comes back empty.

const Scene := preload("res://scenes/rooftop_prototype.tscn")
const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const OUT := "res://.godot_runtime/rooftop25-"

var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "ROOFTOP25", 90.0)
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func run() -> void:
	RooftopSpace.view_mode = RooftopSpace.View.PERSPECTIVE
	RooftopSpace.focus = Vector2.ZERO
	Moonlight.enabled = true
	var stage := Scene.instantiate()
	root.add_child(stage)
	await process_frame
	if not Harness.require_loaded(self, stage, "ROOFTOP25"):
		return

	_check_projection()
	_check_perspective(stage)
	_check_props(stage)
	await _check_chain(stage)
	await _check_occlusion(stage)
	await _check_plate(stage)
	await shot("overview")
	await _check_edges(stage)
	await _check_footing(stage)
	await _check_weapon_heights(stage)

	# The other two views, which the same scene has to be able to fall back to
	# or there is nothing to compare the trapezoid against.
	await _look_in(stage, RooftopSpace.View.LIFTED)
	check(RooftopSpace.view_scale(9999.0) == 1.0, "Without perspective nothing is scaled by depth")
	check(RooftopSpace.project(Vector2(500.0, -400.0)) == Vector2(500.0, -400.0),
		"Without perspective the floor is left where it is")
	await shot("lifted")

	await _look_in(stage, RooftopSpace.View.FLAT)
	check(RooftopSpace.lift(80.0) == Vector2.ZERO, "The flat view collapses every lift")
	check(is_equal_approx(stage.props[0].screen_rect().size.y, stage.props[0].depth()),
		"The flat view gives back the screen space the props were reserving")
	await shot("flat")
	await _look_in(stage, RooftopSpace.View.PERSPECTIVE)

	await _check_run_untouched()

	if failures.is_empty():
		print("ROOFTOP25 OK")
		quit(0)
		return
	for failure in failures:
		push_error("ROOFTOP25: " + failure)
	quit(1)


## Switches the view the way F1 does and lets the scene settle into it, since
## the floor layers are all measured from the focus and every body has to be
## placed and scaled again.
func _look_in(stage, mode) -> void:
	RooftopSpace.view_mode = mode
	for frame in 4:
		stage._physics_process(1.0 / 60.0)
	stage._redraw_world()
	stage._refresh_legend()
	await process_frame


## The trapezoid itself: the claims that make this a perspective view rather
## than a taller version of the plan view.
func _check_perspective(stage) -> void:
	RooftopSpace.focus = Vector2.ZERO
	var near := RooftopSpace.view_scale(600.0)
	var far := RooftopSpace.view_scale(-600.0)
	check(near > 1.0 and far < 1.0, "Near ground is larger than far ground")
	check(RooftopSpace.project(RooftopSpace.focus) == RooftopSpace.focus,
		"The focus is the one point the view never moves")
	# The plate has to come out narrower at the back than at the front, which is
	# the whole of what "trapezoid" means here.
	var plate: Rect2 = stage.section.bounds
	var back_left := RooftopSpace.project(plate.position)
	var back_right := RooftopSpace.project(Vector2(plate.end.x, plate.position.y))
	var front_left := RooftopSpace.project(Vector2(plate.position.x, plate.end.y))
	var front_right := RooftopSpace.project(plate.end)
	check(back_right.x - back_left.x < front_right.x - front_left.x,
		"The far edge of the plate is narrower than the near edge")
	check(back_left.y < front_left.y, "The far edge is further up the screen")
	# Straight down the middle, the two sides close in by the same amount: a
	# trapezoid and not a wedge.
	check(is_equal_approx(back_left.x + back_right.x, front_left.x + front_right.x),
		"The plate tapers evenly toward the vanishing point")
	# And the order of the floor survives it, which is what the whole depth
	# sort and the see-through pass rest on.
	check(RooftopSpace.project(Vector2(0.0, -100.0)).y < RooftopSpace.project(Vector2(0.0, 100.0)).y,
		"Projection keeps front-to-back order")


func _check_projection() -> void:
	RooftopSpace.focus = Vector2.ZERO
	check(RooftopSpace.lift(50.0).y < 0.0 and is_zero_approx(RooftopSpace.lift(50.0).x),
		"Height only ever moves a drawing up the screen")
	check(RooftopSpace.raised(Vector2(0.0, 0.0), 30.0).x == 0.0,
		"Height never moves a thing sideways off the point it stands on")
	check(RooftopSpace.in_front_of(200.0, 180.0) and not RooftopSpace.in_front_of(180.0, 200.0),
		"Front to back is decided by the ground contact line")
	# The two faces have to be far enough apart to read as a fold rather than as
	# a gradient, or the thickness is not visible at the sizes this game draws at.
	var top := RooftopSpace.top_face(Color("6a5442"))
	var front := RooftopSpace.front_face(Color("6a5442"))
	check(top.get_luminance() > front.get_luminance() * 1.5, "A lit top reads clearly against a shaded front")


func _check_props(stage) -> void:
	var pipe: RooftopProp = null
	for prop in stage.props:
		if prop.kind == "pipe":
			pipe = prop
			break
	check(pipe != null and pipe.bulky(), "The tall prop is bulky enough to hide a cat")
	var rect: Rect2 = pipe.screen_rect()
	check(is_equal_approx(rect.end.y, pipe.position.y), "A prop's drawn extent ends where it meets the floor")
	check(rect.size.y > pipe.height() * 0.5, "A prop's drawn extent includes the height it stands up")
	var duct: RooftopProp = null
	for prop in stage.props:
		if prop.kind == "duct":
			duct = prop
			break
	check(duct != null and not duct.bulky(), "Low ducting never triggers the see-through pass")


## Stands the pair on two exact points on the floor and lets the scene catch up
## without running the simulation, which would move them again. The focus goes
## with them: the perspective is measured from the camera, so a pose that did
## not move it would be judged through the view of somewhere else.
func _pose(stage, a: Vector2, b: Vector2) -> void:
	RooftopSpace.focus = (a + b) * 0.5
	stage.players[0].position = a
	stage.players[1].position = b
	stage._update_chain()
	stage._to_view()


func _check_chain(stage) -> void:
	# Slack: the pair standing close. The chain has to bow toward the viewer and
	# its middle has to come down toward the floor.
	_pose(stage, Vector2(-60.0, 0.0), Vector2(60.0, 0.0))
	var slack_ground: PackedVector2Array = stage.chain_path()
	var belly: Vector2 = slack_ground[slack_ground.size() / 2]
	check(belly.y > 20.0, "A slack chain bows toward the viewer")
	check(stage.chain_arc.height_at(0.5) < stage.chain_arc.height_at(0.0) * 0.5,
		"A slack chain's middle falls toward the floor")

	# The claim that matters for play: what the chain damages is the curve it is
	# drawn as. An enemy sitting in the belly is hit; the same enemy parked on
	# the straight line between the cats is not, because the rope is not there.
	check(stage._touches_path(slack_ground, belly, 8.0), "The chain damages along its own belly")
	check(not stage._touches_path(slack_ground, Vector2(0.0, 0.0), 8.0),
		"A slack chain does not damage the straight line it is not lying on")

	# Taut: the pair at the end of the leash. The rope straightens and leaves
	# the floor, and the two readings converge again.
	_pose(stage, Vector2(-stage.chain_length * 0.5, 0.0), Vector2(stage.chain_length * 0.5, 0.0))
	var taut: PackedVector2Array = stage.chain_path()
	check(absf(taut[taut.size() / 2].y) < 1.0, "A taut chain is straight")
	check(is_equal_approx(stage.chain_arc.height_at(0.5), stage.chain_arc.height_at(0.0)),
		"A taut chain hangs level")
	check(stage.chain_flow.curve.size() == taut.size(), "The running light is given the hung rope to follow")
	check(stage.chain_flow.point_at(0.5).distance_to(
		RooftopSpace.raised(taut[taut.size() / 2], RooftopSpace.CHAIN_ANCHOR) - stage.chain_arc.position) < 2.0,
		"The light samples the chain rather than the chord")
	# The rope sorts against the furniture instead of living under all of it, so
	# both halves have to be anchored where the sorting expects them.
	check(stage.chain_arc.get_parent() == stage.stage and stage.chain_flow.get_parent() == stage.stage,
		"The chain sorts in the same layer as the props")
	check(stage.chain_arc.position.distance_to(
		(stage.players[0].position + stage.players[1].position) * 0.5) < 0.01,
		"The chain is anchored at the pair's midpoint")
	await shot("chain-taut")

	_pose(stage, Vector2(-60.0, 0.0), Vector2(60.0, 0.0))
	await shot("chain-slack")


func _check_occlusion(stage) -> void:
	var pipe: RooftopProp = null
	for prop in stage.props:
		if prop.kind == "pipe":
			pipe = prop
			break
	# Placed against the pipe's floor point, not its drawn one — in perspective
	# those are two different places.
	var spot: Vector2 = pipe.ground
	# Standing just behind the pipe: hidden, and therefore owed a silhouette.
	_pose(stage, spot - Vector2(0.0, 26.0), spot - Vector2(150.0, 40.0))
	check(_is_covered(stage, stage.players[0]), "A cat behind the tall prop is hidden by it")
	check(not _is_covered(stage, stage.players[1]), "A cat clear of it is not")
	# Grazing the corner of a prop is not being hidden by it. Without a share to
	# clear, the silhouette fires on every near miss and stops meaning anything.
	_pose(stage, spot - Vector2(pipe.width() + 30.0, 30.0), spot - Vector2(260.0, 40.0))
	check(not _is_covered(stage, stage.players[0]), "Brushing past a prop does not raise a silhouette")
	# And stepping out in front has to give the cat back without a silhouette,
	# or the see-through pass is just a permanent outline on everything.
	_pose(stage, spot + Vector2(0.0, 40.0), spot - Vector2(150.0, 40.0))
	check(not _is_covered(stage, stage.players[0]), "Walking in front of a prop gives the cat back")
	_pose(stage, spot - Vector2(0.0, 26.0), spot - Vector2(150.0, 40.0))
	await shot("occlusion")


## Weapons that own the floor against weapons that pass over it.
##
## The claim being checked is the same one the chain makes and it is the one
## that matters for play: height changes where a shot is *drawn* and never where
## it *hits*. A star aimed at an enemy that damaged something a few pixels below
## itself would be a weapon nobody could aim.
func _check_weapon_heights(stage) -> void:
	check(RooftopSpace.weapon_height("milk") == 0.0 and RooftopSpace.weapon_height("mine") == 0.0,
		"Floor weapons stay on the floor")
	check(RooftopSpace.weapon_height("homing") > 0.0 and RooftopSpace.weapon_height("lightning") > 0.0,
		"Body-height weapons leave it")
	check(RooftopSpace.weapon_height("nonesuch") == 0.0, "An unlisted weapon is on the ground")

	await _walk_to(stage, Vector2(-200.0, 0.0))
	stage.shot_timer = 0.0
	for frame in 20:
		stage._physics_process(1.0 / 60.0)
	check(not stage.shots.is_empty(), "The pair actually fires something")
	# Named `star` rather than `shot`, which is this file's capture helper.
	var star: HomingProjectile = stage.shots[0]
	# Stepped by hand. A projectile runs on the engine's own physics tick rather
	# than on the stage's, so how many times it has moved by this line depends on
	# how fast the frames above happened to come — which passed windowed and
	# failed headless, where a freshly fired shot was still sitting at its
	# spawn point with its lift not yet applied.
	star._physics_process(1.0 / 60.0)
	check(star.flight_height > 0.0, "The star flies at body height")
	# Measured against the piece of floor the shot is over *as it is drawn*, not
	# against the raw floor coordinate: under a perspective the projection moves
	# that point too, and height is only the difference between the two.
	var under := RooftopSpace.project(star.ground_position)
	check(star.position.y < under.y, "A flying shot is drawn above the roof it crosses")
	check(is_equal_approx(star.position.x, under.x), "Height never moves a shot sideways")
	check(stage.flight.flyers.size() > 0, "Something is drawing the shadow under it")
	await shot("weapons")


## Standing on the floor rather than lying on it: the body is drawn above the
## point the cat occupies, the shadow stays at that point, and a dash throws the
## one forward while dragging the other out behind it.
##
## Shot close, because this is the one part of the pass that is measured in a
## handful of pixels and cannot be judged from a whole-plate view.
func _check_footing(stage) -> void:
	await _walk_to(stage, Vector2(0.0, 120.0))
	var cat: ChainPlayer = stage.players[0]
	check(cat.stand_height > 0.0, "The prototype's cats stand off the roof")
	check(RooftopSpace.raised(stage.grounds[0], cat.stand_height).y < RooftopSpace.project(stage.grounds[0]).y,
		"A standing cat is drawn above the point it stands on")
	cat.last_input = Vector2.RIGHT
	check(cat.try_dash(), "The dash is available to lean into")
	stage.world_camera.zoom = Vector2.ONE * 2.1
	for frame in 3:
		stage._physics_process(1.0 / 120.0)
	check(cat.dash_timer > 0.0, "The shot catches the burst mid-flight")
	stage.world_camera.position = RooftopSpace.project(stage.grounds[0])
	await shot("footing")
	stage.world_camera.zoom = Vector2.ONE * stage.CAMERA_ZOOM


## The two edges, and the claim that the camera can actually reach them. A roof
## whose thickness is only ever off screen has no thickness as far as the player
## is concerned, so this settles the framing as well as taking the shots.
func _check_edges(stage) -> void:
	await _walk_to(stage, Vector2(0.0, stage.section.bounds.position.y + 60.0))
	var top: float = stage.world_camera.position.y - 360.0 / stage.CAMERA_ZOOM
	check(top < stage.section.far_limit(), "Standing at the far edge shows the drop past it")
	await shot("edge-far")
	await _walk_to(stage, Vector2(0.0, stage.section.bounds.end.y - 60.0))
	var bottom: float = stage.world_camera.position.y + 360.0 / stage.CAMERA_ZOOM
	check(bottom > stage.section.bounds.end.y + RooftopSection.PARAPET_DEPTH,
		"Standing at the near edge shows the wall the roof sits on")
	await shot("edge-near")


## Puts the pair somewhere and lets the camera settle there, since the framing
## checks above are about where the camera ends up and not where it starts.
func _walk_to(stage, at: Vector2) -> void:
	_pose(stage, at - Vector2(70.0, 0.0), at + Vector2(70.0, 0.0))
	for frame in 60:
		stage._physics_process(1.0 / 60.0)
	await process_frame


func _is_covered(stage, cat: ChainPlayer) -> bool:
	return stage._is_hidden(cat, stage._occluders())


func _check_plate(stage) -> void:
	# The parapet is the one thing up here that is allowed to stop a cat, so it
	# has to actually stop one.
	stage.players[0].position = Vector2(9000.0, 9000.0)
	stage._clamp_to_plate()
	check(stage.section.bounds.has_point(stage.players[0].position), "The parapet holds the pair on the plate")
	_pose(stage, Vector2(-120.0, 60.0), Vector2(120.0, 60.0))
	for frame in 30:
		stage._physics_process(1.0 / 60.0)
	check(stage.grounds[0].distance_to(stage.grounds[1]) <= stage.chain_length + 1.0,
		"The leash still holds while the roof has height")
	check(stage.enemies.size() > 0, "Enemies walk the plate so movement can be judged against something")
	# The point of the ground/view swap: a cat covers the same distance per
	# second wherever it is standing. Walked at the back of the plate and at the
	# front, the two runs have to match on the floor even though they cover very
	# different amounts of screen.
	check(is_equal_approx(_walk_distance(stage, -420.0), _walk_distance(stage, 420.0)),
		"A cat walks the same distance at the back of the roof as at the front")
	await process_frame


## How far the leader actually travels across the floor in a fixed number of
## steps, starting from a given row.
func _walk_distance(stage, row: float) -> float:
	stage.grounds[0] = Vector2(-200.0, row)
	stage.grounds[1] = Vector2(-60.0, row)
	stage.players[1].input_source = ChainPlayer.InputSource.AI
	var start: Vector2 = stage.grounds[0]
	for frame in 20:
		stage.players[0].set_command(Vector2.RIGHT)
		stage.players[0].input_source = ChainPlayer.InputSource.AI
		stage._physics_process(1.0 / 60.0)
	return snappedf(start.distance_to(stage.grounds[0]), 0.01)


## The live run must be exactly where it was. Height is opt-in per survivor and
## nothing in main.gd opts in yet, so a run's cats still draw at their own
## position with the shadow Moonlight has always put under them.
func _check_run_untouched() -> void:
	# The view is a global switch, so the run has to be handed back the one it
	# expects. Nothing in main.gd projects anything, but leaving the prototype's
	# view on would be a trap for the next thing that reads it.
	RooftopSpace.view_mode = RooftopSpace.View.LIFTED
	RooftopSpace.focus = Vector2.ZERO
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "ROOFTOP25"):
		return
	main._begin_lobby()
	main.lobby_input_cooldown = 0.0
	main._join_ai_companion()
	main._step_ai_character(1.5)
	main._start_selected_run()
	for frame in 5:
		await physics_frame
	check(main.players[0].stand_height == 0.0 and main.players[1].stand_height == 0.0,
		"The run's survivors are still drawn flat on the roof")
	check(main.chain_flow.curve.is_empty(), "The run's chain light still follows the straight segment")
	check(RooftopSpace.project(Vector2(700.0, 700.0)) == Vector2(700.0, 700.0),
		"The run's floor is not projected")
	main.queue_free()
	await process_frame
