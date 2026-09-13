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
