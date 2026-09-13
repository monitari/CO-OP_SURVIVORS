extends SceneTree
const Scene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []
func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/readability-progress.cfg")
	Harness.arm_watchdog(self, "READABILITY", 45.0)
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/readability-" + name + ".png")
func run() -> void:
	var main := Scene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "READABILITY"): return
	main._begin_lobby()
	main.lobby_input_cooldown = 0.0
	main._join_ai_companion()
	main._step_ai_character(1.5)
	main._start_selected_run()
	for frame in 5: await physics_frame
	main.set_physics_process(false)
	main.players[0].health = 40.0
	main.players[1].health = 40.0
	main.kills = 17
	var enemy: ChaserEnemy = main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false)
	main._register_enemy(enemy)
	enemy.take_damage(100000.0)
	check(main.kills == 18 and main.players[0].health == 40.0 and main.players[1].health == 40.0, "18 kills no longer grant free healing")
	main._update_hud()
	var holder: Control = main.combat_hud.get_node("Carried0")
	var socket: Control = holder.get_node("WeaponSlot0")
	check(socket.size.x == socket.size.y, "Equipment sockets are square")
	var border = socket.get_node("CooldownBorder")
	main.attack_timers[0][0] = main._weapon_interval(0, 0) * 0.5
	border.refresh()
	check(is_equal_approx(border.progress, 0.5), "Border uses real weapon cooldown")
	check(holder.get_node("Weapon0/Tier").text == "1", "Tier uses only a number")
	main.treasure_loadouts[0].append({"id": "catnip", "tier": 2})
	main._update_hud()
	var passive = holder.get_node("TreasureSlot0/CooldownBorder")
	passive.refresh()
	check(passive.visible and passive.continuous, "Newly acquired passive has a continuous border")
	main.resonance_system.activate({"id": "guided_thunder", "name": "추적 뇌광", "cooldown": 6.0, "weapon_a_slot": 0, "weapon_b_slot": 0})
	border.refresh()
	check(border.resonating and holder.get_node("Weapon0/Tier").text == "I", "Bound weapons use golden Roman resonance number")
	check(main.player_label(0) == "나" and main.player_label(1) == "동료", "Player labels are relative")
	var snapshot: Dictionary = main.online._snapshot()
	main.online.session.role = NetworkSession.Role.CLIENT
	main.online._apply_snapshot(snapshot)
	main._update_hud()
	check(main.player_label(1) == "나" and main.players[1].display_name == "나", "Client identifies itself as me")
	check(main.resonance_system.active_resonances.size() == 1 and main.attack_timers == snapshot["attack_timers"], "Client receives authoritative equipment cooldowns")
	main.online.session.role = NetworkSession.Role.OFFLINE
	main._update_hud()
	await shot("equipment")
	main._set_pause(true)
	main._physics_process(0.0)
	check(main.modal_dim.veil_only and paused, "Pause veils the frozen game")
	check(not main.pause_overlay.get_node("RunSnapshot").visible, "Pause removes stat dashboard")
	check(not main.pause_overlay.get_node("PauseAction1").visible, "Settings collapsed by default")
	await shot("pause")
	main._activate_pause_item(7)
	check(main.pause_settings and main.pause_overlay.get_node("PauseAction1").visible, "Settings remain accessible")
	await shot("settings")
	main._activate_pause_item(7)
	main._activate_pause_item(5)
	await shot("confirm")
	main._activate_pause_item(0)
	main._set_pause(false)
	var director := WaveDirector.new()
	root.add_child(director)
	var previous_rate := 0.0
	for wave in [0, 5, 10, 20, 35, 45]:
		director.wave_index = wave
		var rate := float(director.spawn_batch_size()) / director.spawn_interval()
		check(rate > previous_rate, "Spawn throughput grows through the run")
		previous_rate = rate
	for i in 30:
		var body := director._acquire_enemy("chaser", 2.0, Vector2.ZERO, false, false)
		check(body.position.length() >= 900.0 and body.position.length() < main.ENEMY_CULL_RADIUS, "Enemies spawn farther out without immediate culling")
		director.release_enemy(body)
	director.queue_free()
	main.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("READABILITY_PASS" if failures.is_empty() else "READABILITY_FAIL")
	quit(0 if failures.is_empty() else 1)
