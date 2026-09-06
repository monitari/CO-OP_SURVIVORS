extends SceneTree
const Main := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const Value := preload("res://scripts/systems/upgrade_value.gd")
var failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, "REVIEW_FAIL", 60)
	call_deferred("_run")

func _run() -> void:
	var main := Main.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "REVIEW_FAIL"): return
	main.settings.settings_path = "res://.godot_runtime/review-settings.cfg"
	main._on_joy_connection_changed(0, false)
	check(not main.pause_active, "disconnect in join lobby does not open an unreachable pause menu")
	main._start_selected_run()
	main.set_physics_process(false)
	main._set_pause(true)
	# A/Enter must resume, never restart, at the default pause cursor.
	await _press(main, "menu_confirm")
	check(not main.pause_active and is_instance_valid(main), "default confirm resumes safely")
	main._set_pause(true)
	await _press(main, "menu_next")
	check(main.pause_cursor == 1, "pad/keyboard navigation reaches settings")
	var before: bool = main.screen_shake_enabled
	await _press(main, "menu_confirm")
	check(main.screen_shake_enabled != before, "selected setting changes on confirm")
	main._activate_pause_item(5)
	check(main.restart_pending and main.pause_cursor == 0, "restart asks confirmation with cancel focused")
	main._activate_pause_item(1)
	check(main.restart_pending and is_instance_valid(main), "opening double-click cannot restart")
	await _press(main, "menu_confirm")
	check(not main.restart_pending and main.pause_active, "default confirmation cancels restart")
	main.ReviewUI.toggle_details(main)
	check(main.details_overlay.visible and not main.pause_overlay.visible, "details exclusively cover the menu")
	for slot in 2:
		var section_text := " ".join([
			main.details_overlay.get_node("Offense%d/Value" % slot).text,
			main.details_overlay.get_node("Survival%d/Value" % slot).text,
			main.details_overlay.get_node("Coop%d/Value" % slot).text,
			main.details_overlay.get_node("Utility%d/Value" % slot).text,
			main.details_overlay.get_node("Build%d/Value" % slot).text,
		])
		for term in ["치명", "회피", "구조", "자력", "과충전", "무기"]:
			check(section_text.contains(term), "full stat category: " + term)
	main.ReviewUI.toggle_details(main)
	check(main.pause_overlay.visible and main.pause_active, "closing details preserves pause")
	main.ReviewUI.toggle_details(main)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	main._physics_process(1.0 / 60.0)
	check(not main.details_overlay.visible and main.pause_active, "escape closes only the details, not the paused run")
	main._set_pause(false)
	main.weapon_loadouts[0][0]["cooldown"] = 0.2
	check(not Value.has_effect(main, 0, {"id": "weapon_rate", "weapon_slot": 0}), "capped rate excluded")
	main.weapon_loadouts[0][0] = main._build_weapon_state(main.character_catalog[3])
	main.weapon_loadouts[0][0]["slow"] = 0.34
	check(not Value.has_effect(main, 0, {"id": "special_b", "weapon_slot": 0}), "capped slow excluded")
	main.weapon_loadouts[0][0] = main._build_weapon_state(main.character_catalog[4])
	main.weapon_loadouts[0][0]["arc"] = PI * 1.5
	check(not Value.has_effect(main, 0, {"id": "special_b", "weapon_slot": 0}), "capped arc excluded")
	main.weapon_loadouts[0][0] = main._build_weapon_state(main.character_catalog[0])
	main.weapon_loadouts[0][0]["tier"] = 7
	var required: Dictionary = main.Treasures.build_state(main.Treasures.by_id("pierce"))
	required["tier"] = 4
	main.treasure_loadouts[0] = [required]
	for iteration in 40:
		var found := false
		for option in main._get_upgrade_choices(1):
			found = found or option["id"] == "evolve_weapon"
		check(found, "fusion guaranteed even across repeated rerolls")
	var power := {"id": "weapon_power", "weapon_slot": 0}
	check(is_equal_approx(Value.gain(main, 0, power), 0.20), "single weapon damage gain is 20 percent")
	main.weapon_loadouts[0].append(main._build_weapon_state(main.character_catalog[1]))
	check(Value.gain(main, 0, power) < 0.25, "single weapon gain weighted by whole loadout")
	var lightning: Dictionary = main.weapon_loadouts[0][1]
	lightning["jumps"] = 3
	var low_jump := Value.gain(main, 0, {"id": "special_a", "weapon_slot": 1})
	lightning["jumps"] = 20
	check(Value.gain(main, 0, {"id": "special_a", "weapon_slot": 1}) < low_jump, "chain falloff reduces marginal recommendation")
	check(not Value.benefits_loadout([main._build_weapon_state(main.character_catalog[3])], "amount"), "extra shots do not falsely benefit a frost-only build")
	main.team_overcharge = 0.1
	# Placed as a fraction of the leash rather than at a fixed 320px: the chain
	# length is decided by which two cats were picked now, so a hard-coded gap
	# lands in a different chain state depending on the roster.
	var overcharge_gap: float = main.chain_max_length * 0.88 * 0.5
	main.players[0].position = Vector2(-overcharge_gap, 0)
	main.players[1].position = Vector2(overcharge_gap, 0)
	main._update_hud()
	check(main.chain_status_label.text.contains("+35%"), "HUD reflects upgraded overcharge")
	# Measured crit damage, not merely a stat field.
	main.weapon_loadouts[0] = [main._build_weapon_state(main.character_catalog[3])]
	var dummy := ChaserEnemy.new()
	main.add_child(dummy)
	dummy.setup(0)
	dummy.health = 10000
	dummy.max_health = 10000
	dummy.position = main.players[0].position + Vector2(80, 0)
	main._register_enemy(dummy)
	main.spatial_grid.rebuild(main.enemies)
	main.players[0].crit_chance = 0.0
	var health: float = dummy.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var normal: float = health - dummy.health
	main.players[0].crit_chance = 1.0
	health = dummy.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	check(is_equal_approx(health - dummy.health, normal * 2.0), "critical attack actually doubles damage")
	# Driven through a real step rather than by writing rotation and waiting. The
	# body used to be re-oriented by a transform notification, which fired on every
	# position write the crowd made and cost more than the work it guarded; the
	# step now does it once at the end, after it has chosen this frame's heading.
	# So the step is what has to be exercised, and it is also the stronger check:
	# the enemy picks its own rotation here, and the painted body still ends level.
	dummy.position = main.players[0].position + Vector2(80, 55)
	dummy.step(main.players, 1.0 / 60.0)
	check(absf(dummy.rotation) > 0.001, "the enemy node really is rotated to face its target")
	check(absf(dummy.body_sprite.global_rotation) < 0.001, "sprite stays upright while telegraph rotates")
	check(dummy.z_index > 3, "enemy warnings stay above friendly rings")
	# This used to assert the opposite: that the select card printed the fusion
	# recipe ("합성 X T7 + Y T4"). That was reversed on purpose — the first fusion
	# is meant to be found during a run, not read off a menu before it starts.
	# What select owes the player is how the survivor plays right now.
	var card: String = main._format_character_card(0)
	check(not card.contains("합성"), "character select does not spoil the fusion recipe")
	check(not card.contains("난이도"), "character select removes difficulty labels")
	main.progression.add_experience(main.progression.required_experience)
	main._begin_level_up()
	main.level_up_input_delay = 0
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	main.level_card_labels[0][1].gui_input.emit(event)
	check(main.selected_upgrade_indices[0] == 1 and main.selected_upgrade_indices[1] == -1, "mouse card locks only its owner")
	main._finish_level_up()
	var boss := ChaserEnemy.new()
	main.add_child(boss)
	boss.setup(3, "brute", false, true)
	boss.position = Vector2(0, -500)
	main._register_enemy(boss)
	main.screen_shake_enabled = false
	for frame in 120: main._update_camera(1.0 / 60.0)
	main.world_camera.force_update_scroll()
	for actor in [boss, main.players[0], main.players[1]]:
		var projected: Vector2 = main.world_camera.get_canvas_transform() * actor.global_position
		check(projected.y > 205 and projected.y < 650, "camera protects actor from HUD")
	if failures.is_empty(): print("REVIEW_PASS: safe inputs, mouse selection, full stats, caps, guaranteed fusion, marginal scoring, actual crit, art, camera")
	else:
		for failure in failures: push_error("REVIEW_FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _press(main: Node, action: String) -> void:
	await physics_frame
	await process_frame
	Input.action_press(action)
	main._handle_pause_input()
	Input.action_release(action)
	await physics_frame
	await process_frame

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
