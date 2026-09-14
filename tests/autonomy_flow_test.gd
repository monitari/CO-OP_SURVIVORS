extends SceneTree

const Scene := preload("res://scenes/main.tscn")
const Bot := preload("res://scripts/systems/companion_controller.gd")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/autonomy-progress.cfg")
	Harness.arm_watchdog(self, "AUTONOMY", 40.0)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/autonomy-" + name + ".png")

func run() -> void:
	var main := Scene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "AUTONOMY"):
		return
	main._activate_title_item(0)
	check(main.title_mode == "modes", "Start opens modes")
	await shot("modes")
	main._activate_title_item(0)
	check(main.ai_companion and main.character_select_active, "AI mode skips manual join")
	check(not main.character_confirmed[1], "AI thinks before readying")
	main._step_ai_character(1.5)
	check(main.character_confirmed[1], "AI finishes thinking")
	await shot("characters")
	main._start_selected_run()
	for frame in 4:
		await physics_frame
	main.set_physics_process(false)
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(100, 0)
	main.weapon_loadouts[1] = [{"weapon_id": "chain"}]
	var command := Bot.command(main.players[1], main.players[0], main.spatial_grid, [], 400.0, main)
	check(command.movement.x > 0.0, "Chain loadout spreads out while human stands still")
	main.players[0].downed = true
	command = Bot.command(main.players[1], main.players[0], main.spatial_grid, [], 400.0, main)
	check(command.movement.x < 0.0, "Rescue overrides chain positioning")
	main.players[0].downed = false
	main.weapon_loadouts[1] = [main._build_weapon_state(main.selected_characters[1])]
	main._update_hud()
	check(main.combat_hud.get_node("Carried0").visible and main.combat_hud.get_node("Carried1").visible,
		"Both loadouts sit under their health bars")
	await shot("hud")
	main.online.session.role = NetworkSession.Role.CLIENT
	main._update_hud()
	check(main.display_player_number(1) == 1 and main.display_player_number(0) == 2, "Client sees itself as P1")
	check(main.p2_health_bar.position.x < main.p1_health_bar.position.x, "Client health occupies primary HUD")
	check(main.combat_hud.get_node("Carried1").visible, "Client sees its own full loadout")
	await shot("client-hud")
	main.online.session.role = NetworkSession.Role.OFFLINE
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main._refresh_level_up_ui()
	for frame in 35:
		main._physics_process(1.0 / 60.0)
		await process_frame
	await shot("growth")
	var director := WaveDirector.new()
	root.add_child(director)
	var pots: Array = director._spawn_planters_near(Vector2(4000, 4000), 1.0)
	check(pots.size() <= 5, "Planter cap")
	for a in pots.size():
		for b in range(a + 1, pots.size()):
			check(pots[a].position.distance_to(pots[b].position) >= 480.0, "Planters are separated")
	for pot in pots:
		pot.free()
	director.queue_free()
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("AUTONOMY_PASS" if failures.is_empty() else "AUTONOMY_FAIL")
	quit(0 if failures.is_empty() else 1)
