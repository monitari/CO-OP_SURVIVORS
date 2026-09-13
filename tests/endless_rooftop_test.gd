extends SceneTree
const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, "ENDLESS_ROOFTOP", 90.0)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/endless-" + label + ".png")

## The picture is a resample, and a resample has exactly two ways to look wrong:
## it reads outside what it was given, or it reads the wrong number of texels per
## pixel. Both are decided by constants that are easy to retune and impossible to
## eyeball, so both are checked here against the mapping itself.
func _check_resample(view) -> void:
	var reach := Vector2.ZERO
	var densest := 0.0
	var sparsest := INF
	# The shader walks UV across the whole display, so the whole display is
	# walked here — corners included, since the corners are where both the reach
	# and the density go to their extremes.
	for step_y in 33:
		var py := float(step_y) / 32.0 - 0.5
		var row := 1.0 + EndlessRooftopView.PERSPECTIVE * py / EndlessRooftopView.TILT
		var down := EndlessRooftopView.TILT + EndlessRooftopView.PERSPECTIVE * py
		reach = reach.max(Vector2(absf(0.5 / row), absf(py / down)))
		# Source texels per output pixel, on each axis, at this row. The overscan
		# cancels out of both: a wider buffer is a wider slice of floor, never a
		# denser one. Only SUPERSAMPLE moves these.
		densest = maxf(densest, maxf(1.0 / row, EndlessRooftopView.TILT / (down * down)))
		sparsest = minf(sparsest, minf(1.0 / row, EndlessRooftopView.TILT / (down * down)))
	var needed := reach * 2.0
	check(EndlessRooftopView.OVERSCAN.x >= needed.x and EndlessRooftopView.OVERSCAN.y >= needed.y,
		"The overscan covers every corner the projection reads (needs %.3v)" % needed)
	check(EndlessRooftopView.OVERSCAN.x < needed.x * 1.1 and EndlessRooftopView.OVERSCAN.y < needed.y * 1.1,
		"The overscan is not spending source resolution on floor nothing samples")
	check(sparsest * EndlessRooftopView.SUPERSAMPLE >= 1.0,
		"Nowhere on screen is magnified, which is what made the picture soft (%.3f)" % sparsest)
	check(densest * EndlessRooftopView.SUPERSAMPLE <= 2.0,
		"Nowhere on screen minifies past what the shader's four taps can filter (%.3f)" % densest)

	# A window larger than the authored size has to grow the buffer with it. The
	# override is what keeps that from changing how much roof the camera shows.
	var logical := Vector2(1280, 720)
	var at_720 := EndlessRooftopView.source_size(logical, logical)
	var at_1080 := EndlessRooftopView.source_size(logical, Vector2(1920, 1080))
	check(at_1080.x > at_720.x and at_1080.y > at_720.y,
		"A maximised window is rendered at the pixels it actually has")
	check(float(at_720.x) / (logical.x * EndlessRooftopView.OVERSCAN.x) >= EndlessRooftopView.SUPERSAMPLE - 0.01,
		"The authored window still gets its full sample density")
	check(Vector2(view.surface.size_2d_override) == (view.view_size * EndlessRooftopView.OVERSCAN).ceil(),
		"The battlefield keeps thinking in authored units however dense the buffer is")

	# The camera is rounded onto the buffer's texel grid, because a world sliding
	# across that grid by fractions of a texel is what makes a resample crawl.
	var zoom := Vector2.ONE * 0.73
	var texels: Vector2 = view.texel_density(zoom)
	var snapped: Vector2 = view.snap_to_source_texels(Vector2(413.37, -208.91), zoom)
	var landed := snapped * texels
	check(absf(landed.x - roundf(landed.x)) < 0.001 and absf(landed.y - roundf(landed.y)) < 0.001,
		"A snapped camera sits on whole source texels")
	check(snapped.distance_to(Vector2(413.37, -208.91)) < 1.0 / minf(texels.x, texels.y),
		"The snap never moves the camera by more than the texel it rounded to")


func run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "ENDLESS_ROOFTOP"):
		return
	main._begin_lobby()
	main._join_ai_companion()
	main._start_selected_run()
	await physics_frame
	main.set_physics_process(false)
	main.modal_dim.visible = false
	main.combat_hud.visible = true
	var view = main.rooftop_view
	for at in [Vector2.ZERO, Vector2(-600, -350), Vector2(600, 350), Vector2(0, 280)]:
		check(view.unproject_offset(view.project_offset(at)).distance_to(at) < 0.01,
			"Screen projection and its inverse agree")
	check(view.project_offset(Vector2(500, -300)).x < view.project_offset(Vector2(500, 300)).x,
		"The far floor recedes while the near floor widens")
	_check_resample(view)
	check(main.players[0].get_viewport() == view.surface
		and main.weapon_controller.get_viewport() == view.surface
		and main.field_items.get_viewport() == view.surface,
		"Actors, weapons and loot use exactly the same projection")
	check(main.combat_hud.get_viewport() == root, "HUD is outside the battlefield projection")
	main.players[0].position = Vector2(-100, 30)
	main.players[1].position = Vector2(100, 30)
	for i in 5:
		var enemy = main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false)
		enemy.position = Vector2(-300 + i * 150, -120 + (i % 2) * 310)
		main._register_enemy(enemy)
	main._update_chain_visual()
	for i in 40:
		main._update_camera(1.0 / 60.0)
	main._update_hud()
	await capture("opening")
	var prop: RooftopProp = main.rooftop_props.living_props()[0]
	main.players[0].position = prop.screen_rect().get_center()
	main.players[1].position = main.players[0].position + Vector2(120, 0)
	for i in 40:
		main.rooftop_props.update_visibility(main.players, 1.0 / 60.0)
	check(prop.modulate.a < 0.15, "Furniture gently clears the immediate fight")
	for i in 40:
		main._update_camera(1.0 / 60.0)
	main._update_chain_visual()
	await capture("clearance")
	main.players[0].position += Vector2(900, 0)
	main.players[1].position += Vector2(900, 0)
	for i in 40:
		main.rooftop_props.update_visibility(main.players, 1.0 / 60.0)
	check(prop.modulate.a > 0.6, "Scenery returns when the pair leaves")
	# The viewport must never run past the generated floor, even at max zoom-out
	# and far beyond the original authored patch.
	var far := Vector2(120000, -90000)
	main.players[0].position = far - Vector2(100, 0)
	main.players[1].position = far + Vector2(100, 0)
	main.world_camera.position = far
	main.world_camera.zoom = Vector2.ONE * 0.45
	main._update_camera(0.0)
	main._update_chain_visual()
	var floor_bounds := Rect2(main.arena_floor.draw_origin - Vector2.ONE * main.arena_floor.draw_margin,
		Vector2.ONE * main.arena_floor.draw_margin * 2.0)
	check(floor_bounds.encloses(main._visible_world_rect()), "Far travel and zoom-out never expose empty floor")
	check(main.rooftop_props.living_props().size() < 100, "Scenery count stays bounded after far travel")
	await capture("far")
	for failure in failures:
		push_error("ENDLESS_ROOFTOP: " + failure)
	if failures.is_empty():
		print("ENDLESS_ROOFTOP_PASS")
	quit(0 if failures.is_empty() else 1)
