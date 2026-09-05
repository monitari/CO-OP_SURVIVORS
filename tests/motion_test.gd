extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const ParticleFieldScript := preload("res://scripts/systems/particle_field.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "MOTION_FAIL", 90.0)
	call_deferred("_run")


## Movement feedback: the part of the game that is only ever felt.
##
## A survivor used to change direction by having its drawn heading replaced
## between one frame and the next, which reads as the sprite being swapped
## rather than as a cat turning around. And the only mark anything left on the
## field was a death burst — running, dashing and landing a hit all produced
## nothing at all.
##
## None of this may touch play. The last check here is the important one: the
## particle field has to be inert.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "MOTION_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_turning_is_gradual(main)
	_test_turning_leans(main)
	_test_footfalls_only_while_moving(main)
	_test_particles_age_and_cap()
	_test_dash_leaves_marks(main)
	_test_particles_do_not_touch_play(main)

	if failures.is_empty():
		print("MOTION_PASS: heading turns over frames, cats leave marks, none of it touches play")
		quit(0)
	else:
		for failure in failures:
			push_error("MOTION_FAIL: " + failure)
		quit(1)


## A full reversal has to take several frames. Both ends matter: instant is the
## bug being fixed, and never arriving would be a survivor that permanently
## points the wrong way.
func _test_turning_is_gradual(main: Node) -> void:
	var player: ChainPlayer = main.players[0]
	player.facing = Vector2.RIGHT
	player.dash_timer = 0.0
	player._step_facing(1.0 / 60.0, Vector2.LEFT)
	_check(player.facing.dot(Vector2.LEFT) < 0.9,
		"one frame does not complete a reversal (%.2f)" % player.facing.dot(Vector2.LEFT))
	_check(player.facing.angle_to(Vector2.RIGHT) != 0.0, "but it does begin one")

	var frames := 1
	while frames < 200 and player.facing.dot(Vector2.LEFT) < 0.999:
		player._step_facing(1.0 / 60.0, Vector2.LEFT)
		frames += 1
	_check(frames >= 4, "a reversal takes several frames (%d)" % frames)
	_check(frames < 60, "and finishes well inside a second (%d frames)" % frames)

	# Movement itself must not be filtered — only the drawn heading is.
	player.last_input = Vector2.RIGHT
	player.facing = Vector2.LEFT
	var before := player.position
	player.position += Vector2.RIGHT * player.move_speed * (1.0 / 60.0)
	_check(player.position.x > before.x, "the body still moves the instant the input does")


## The lean is what turns a heading change into a visible motion. It has to
## appear during a turn and settle out of one, or it is a constant tilt.
func _test_turning_leans(main: Node) -> void:
	var player: ChainPlayer = main.players[0]
	player.facing = Vector2.RIGHT
	player.lean = 0.0
	for frame in 8:
		player._step_facing(1.0 / 60.0, Vector2.UP)
	var turning := absf(player.lean)
	_check(turning > 0.01, "turning leans the body (%.3f)" % turning)

	for frame in 90:
		player._step_facing(1.0 / 60.0, Vector2.UP)
	_check(absf(player.lean) < turning * 0.5,
		"and the lean settles once the turn is finished (%.3f)" % player.lean)


## Dust is emitted on a cadence while moving and not at all while standing —
## a standing cat kicking up dust is the version of this that looks broken.
##
## Driven through real input and the real step_movement rather than by
## re-implementing the emit rule here: a test that restates the condition it is
## checking passes whatever the game does.
func _test_footfalls_only_while_moving(main: Node) -> void:
	var player: ChainPlayer = main.players[0]
	# A GDScript lambda captures locals by value, so an `int` counter closed over
	# here would be incremented on a copy and read back as zero — which is how
	# the first version of this check passed while emitting nothing at all. The
	# tally lives in an array because arrays are passed by reference.
	var marks: Array[Vector2] = []
	var tally := func(at: Vector2, _color: Color) -> void: marks.append(at)
	player.footfall.connect(tally)
	player.downed = false
	player.footfall_timer = 0.0

	for frame in 60:
		player.step_movement(1.0 / 60.0)
	_check(marks.is_empty(), "a standing survivor leaves no dust (%d)" % marks.size())

	Input.action_press("p1_right")
	for frame in 60:
		player.step_movement(1.0 / 60.0)
	Input.action_release("p1_right")
	_check(marks.size() > 0, "a running survivor does")
	_check(marks.size() < 30, "but on a cadence rather than every frame (%d in a second)" % marks.size())

	var moving := marks.size()
	for frame in 60:
		player.step_movement(1.0 / 60.0)
	_check(marks.size() == moving, "and stops the moment the survivor does (%d)" % (marks.size() - moving))
	player.footfall.disconnect(tally)


func _test_particles_age_and_cap() -> void:
	var field := ParticleFieldScript.new() as ParticleField
	root.add_child(field)
	field.emit_dust(Vector2.ZERO, Color.WHITE)
	field.emit_sparks(Vector2.ZERO, Color.WHITE, 4)
	field.emit_ring(Vector2.ZERO, Color.WHITE, 40.0)
	field.emit_motes(Vector2.ZERO, Color.WHITE, 4)
	_check(field.particles.size() == 10, "every kind of mark is emitted (%d)" % field.particles.size())

	for frame in 120:
		field.step(1.0 / 60.0)
	_check(field.particles.is_empty(), "and every one of them expires (%d left)" % field.particles.size())

	for burst in 200:
		field.emit_sparks(Vector2.ZERO, Color.WHITE, 6)
	_check(field.particles.size() <= ParticleField.MAX_PARTICLES,
		"the field is capped under load (%d of %d)" % [field.particles.size(), ParticleField.MAX_PARTICLES])

	field.clear_all()
	_check(field.particles.is_empty(), "and a restart sweeps it")
	field.free()


func _test_dash_leaves_marks(main: Node) -> void:
	main.particles.clear_all()
	main.players[0].dash_cooldown = 0.0
	main.players[0].dash_timer = 0.0
	main.players[0].downed = false
	_check(main.players[0].try_dash(), "the fixture actually dashes")
	_check(main.particles.particles.size() > 0,
		"a dash leaves a trail behind it (%d marks)" % main.particles.particles.size())
	main.particles.clear_all()


## The whole point of a separate cosmetic layer is that it cannot reach play.
## Stepping a full field must not move, damage or otherwise touch anything.
func _test_particles_do_not_touch_play(main: Node) -> void:
	for burst in 40:
		main.particles.emit_sparks(Vector2(randf() * 400.0, randf() * 400.0), Color.WHITE, 6)
	var health_before: float = main.players[0].health
	var position_before: Vector2 = main.players[0].position
	var kills_before: int = main.kills
	var experience_before: int = main.progression.experience
	for frame in 30:
		main.particles.step(1.0 / 60.0)
	_check(is_equal_approx(main.players[0].health, health_before), "particles do not damage anyone")
	_check(main.players[0].position == position_before, "particles do not move anyone")
	_check(main.kills == kills_before and main.progression.experience == experience_before,
		"particles do not touch the run's score")
	main.particles.clear_all()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
