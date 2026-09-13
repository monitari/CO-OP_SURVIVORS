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
	RooftopSpace.depth_scale = 1.0
	Moonlight.enabled = true
	var stage := Scene.instantiate()
	root.add_child(stage)
	await process_frame
	if not Harness.require_loaded(self, stage, "ROOFTOP25"):
		return

	_check_projection()
	_check_props(stage)
	await _check_chain(stage)
	await _check_occlusion(stage)
	await _check_plate(stage)
	await shot("overview")
	await _check_edges(stage)
	await _check_footing(stage)
	await _check_weapon_heights(stage)

	# The dial the whole comparison hangs off. With it at zero the roof has to
	# fall back to the flat plan view, props and all, or the before/after shot
	# is not a before and after of one scene.
	RooftopSpace.depth_scale = 0.0
	stage._redraw_world()
	stage._refresh_legend()
	check(RooftopSpace.lift(80.0) == Vector2.ZERO, "Height off collapses every lift")
	check(is_equal_approx(stage.props[0].screen_rect().size.y, stage.props[0].depth()),
		"Height off also gives back the screen space the props were reserving")
	await shot("flat")
	RooftopSpace.depth_scale = 1.0
	stage._redraw_world()
	stage._refresh_legend()

	await _check_run_untouched()

	if failures.is_empty():
		print("ROOFTOP25 OK")
		quit(0)
		return
	for failure in failures:
		push_error("ROOFTOP25: " + failure)
	quit(1)


func _check_projection() -> void:
	check(RooftopSpace.lift(50.0).y < 0.0 and is_zero_approx(RooftopSpace.lift(50.0).x),
		"Height only ever moves a drawing up the screen")
	check(RooftopSpace.raised(Vector2(120.0, 40.0), 30.0).x == 120.0,
		"Height never moves the point a thing is anchored to")
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


func _check_chain(stage) -> void:
	# Slack: the pair standing close. The chain has to bow toward the viewer and
	# its middle has to come down toward the floor.
	stage.players[0].position = Vector2(-60.0, 0.0)
	stage.players[1].position = Vector2(60.0, 0.0)
	stage._update_chain()
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
	stage.players[0].position = Vector2(-stage.chain_length * 0.5, 0.0)
	stage.players[1].position = Vector2(stage.chain_length * 0.5, 0.0)
	stage._update_chain()
	var taut: PackedVector2Array = stage.chain_path()
	check(absf(taut[taut.size() / 2].y) < 1.0, "A taut chain is straight")
	check(is_equal_approx(stage.chain_arc.height_at(0.5), stage.chain_arc.height_at(0.0)),
		"A taut chain hangs level")
	check(stage.chain_flow.curve.size() == taut.size(), "The running light is given the hung rope to follow")
	check(stage.chain_flow.point_at(0.5).distance_to(
		RooftopSpace.raised(taut[taut.size() / 2] - stage.chain_arc.position, RooftopSpace.CHAIN_ANCHOR)) < 2.0,
		"The light samples the chain rather than the chord")
	# The rope sorts against the furniture instead of living under all of it, so
	# both halves have to be anchored where the sorting expects them.
	check(stage.chain_arc.get_parent() == stage.stage and stage.chain_flow.get_parent() == stage.stage,
		"The chain sorts in the same layer as the props")
	check(stage.chain_arc.position.distance_to(
		(stage.players[0].position + stage.players[1].position) * 0.5) < 0.01,
		"The chain is anchored at the pair's midpoint")
	await shot("chain-taut")

	stage.players[0].position = Vector2(-60.0, 0.0)
	stage.players[1].position = Vector2(60.0, 0.0)
	stage._update_chain()
	await shot("chain-slack")


func _check_occlusion(stage) -> void:
	var pipe: RooftopProp = null
	for prop in stage.props:
		if prop.kind == "pipe":
			pipe = prop
			break
	# Standing just behind the pipe: hidden, and therefore owed a silhouette.
	stage.players[0].position = pipe.position - Vector2(0.0, 26.0)
	stage.players[1].position = pipe.position - Vector2(150.0, 40.0)
	check(_is_covered(stage, stage.players[0]), "A cat behind the tall prop is hidden by it")
	check(not _is_covered(stage, stage.players[1]), "A cat clear of it is not")
	# Grazing the corner of a prop is not being hidden by it. Without a share to
	# clear, the silhouette fires on every near miss and stops meaning anything.
	stage.players[1].position = pipe.position - Vector2(pipe.width() * 0.5 + 8.0, 30.0)
	check(not _is_covered(stage, stage.players[1]), "Brushing past a prop does not raise a silhouette")
	# And stepping out in front has to give the cat back without a silhouette,
	# or the see-through pass is just a permanent outline on everything.
	stage.players[0].position = pipe.position + Vector2(0.0, 40.0)
	check(not _is_covered(stage, stage.players[0]), "Walking in front of a prop gives the cat back")
	stage.players[0].position = pipe.position - Vector2(0.0, 26.0)
	stage._update_chain()
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
	check(star.flight_height > 0.0, "The star flies at body height")
	check(star.position.y < star.ground_position.y, "A flying shot is drawn above the roof it crosses")
	check(is_equal_approx(star.position.x, star.ground_position.x),
		"Height never moves a shot sideways")
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
	check(RooftopSpace.raised(cat.position, cat.stand_height).y < cat.position.y,
		"A standing cat is drawn above the point it stands on")
	cat.last_input = Vector2.RIGHT
	check(cat.try_dash(), "The dash is available to lean into")
	stage.world_camera.zoom = Vector2.ONE * 2.1
	for frame in 3:
		stage._physics_process(1.0 / 120.0)
	check(cat.dash_timer > 0.0, "The shot catches the burst mid-flight")
	stage.world_camera.position = cat.position
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
	stage.players[0].position = at - Vector2(70.0, 0.0)
	stage.players[1].position = at + Vector2(70.0, 0.0)
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
	stage.players[0].position = Vector2(-120.0, 60.0)
	stage.players[1].position = Vector2(120.0, 60.0)
	for frame in 30:
		stage._physics_process(1.0 / 60.0)
	check(stage.players[0].position.distance_to(stage.players[1].position) <= stage.chain_length + 1.0,
		"The leash still holds while the roof has height")
	check(stage.enemies.size() > 0, "Enemies walk the plate so movement can be judged against something")
	await process_frame


## The live run must be exactly where it was. Height is opt-in per survivor and
## nothing in main.gd opts in yet, so a run's cats still draw at their own
## position with the shadow Moonlight has always put under them.
func _check_run_untouched() -> void:
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
	main.queue_free()
	await process_frame
