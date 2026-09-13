extends SceneTree
const Scene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/neon-test.cfg")
	Harness.arm_watchdog(self, "NEON_GROWTH", 40.0)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func shot(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/neon-" + label + ".png")

func run() -> void:
	var main := Scene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "NEON_GROWTH"): return
	main.ai_companion = true
	main.selected_character_indices[0] = 1
	main.selected_character_indices[1] = 11
	main._start_selected_run()
	main.title_active = false
	main.character_select_active = false
	main.title_overlay.hide()
	main.character_overlay.hide()
	main.combat_hud.show()
	main.set_physics_process(false)
	main.elapsed = 22
	main.kills = 15
	main.players[0].health = main.players[0].max_health * 0.85
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0
	main.p1_choices.assign([
		{"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("might"), "title": "테크 필수: 격노의 인장", "description": "공격력 +9%"},
		{"id": "weapon_rate", "weapon_slot": 0, "title": "고속 시전", "description": "발동 간격 감소"},
		{"id": "special_a", "weapon_slot": 0, "title": "연쇄 전도", "description": "연쇄 공격 증가"}
	])
	main.p2_choices.assign([
		{"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("haste"), "title": "빠른 수염", "description": "발동 간격 감소"}
	])
	main._annotate_recommendations(0, main.p1_choices)
	main._annotate_recommendations(1, main.p2_choices)
	main.selected_upgrade_indices.assign([-1, 0])
	main.upgrade_cursors.assign([1, 0])
	main._refresh_level_up_ui()
	var moving_card: Label = main.level_card_labels[0][2]
	var before_motion := moving_card.position
	main.upgrade_cursors[0] = 2
	main._refresh_level_up_ui()
	check(moving_card.position.distance_to(before_motion) < 0.1,
		"cursor change does not snap the card upward")
	for frame in 16: await process_frame
	var rest: Vector2 = moving_card.get_meta("neon_rest_position")
	var lifted: Vector2 = rest + Vector2.UP.rotated(moving_card.rotation) * 24.0
	check(moving_card.position.distance_to(lifted) < 1.0,
		"cursor card eases upward along its own rotated axis")
	var body_style := moving_card.get_theme_stylebox("normal") as StyleBoxFlat
	check(body_style.content_margin_top >= 190, "frame decoration preserves the body below title and art")
	var settled := moving_card.position
	main._refresh_level_up_ui()
	check(moving_card.position.distance_to(settled) < 0.1, "unrelated refresh preserves settled card position")
	main.upgrade_cursors[0] = 0
	main._refresh_level_up_ui()
	await process_frame
	var interrupted := moving_card.position
	main.upgrade_cursors[0] = 2
	main._refresh_level_up_ui()
	check(moving_card.position.distance_to(interrupted) < 0.1, "rapid reversal continues from current position")
	main._update_hud()
	for frame in 24: await process_frame
	await shot("three")
	check(main.level_card_labels[0][1].size.x == 224, "three cards use large readable art")
	check(main.level_overlay.get_node("PartnerChoice/State").text == "✓ 선택 완료", "partner lock shown")
	check(not main.combat_hud.get_node("P1Frame/PortraitPlaque").visible,
		"portrait backing box is removed")
	check(not main.combat_hud.get_node("PlayerIdentity0").text.contains("개인 Lv."),
		"personal level is removed from player identity")
	check(not main.combat_hud.get_node("Carried0/WeaponSlot1").visible,
		"unused equipment sockets do not reserve empty boxes")
	var rerolls: int = main.rerolls_remaining[0]
	main.level_overlay.get_node("Reroll0").pressed.emit()
	check(main.rerolls_remaining[0] == rerolls - 1, "reroll button still works")
	main.level_up_input_delay = 0
	main.p1_choices.clear()
	for index in 6:
		main.p1_choices.append({"id": "weapon_power", "weapon_slot": 0, "title": "화력 성장 %d" % (index + 1), "description": "무기 피해 증가"})
	main._annotate_recommendations(0, main.p1_choices)
	main.upgrade_cursors[0] = 2
	main._refresh_level_up_ui()
	for card: Label in main.level_card_labels[0]:
		check(card.visible and card.position.x > 0 and card.position.x + card.size.x < 1280, "six cards fit viewport")
	await shot("six")
	main.online.session.role = NetworkSession.Role.CLIENT
	main.p2_choices = main.p1_choices.duplicate(true)
	main.selected_upgrade_indices.assign([0, -1])
	main._refresh_level_up_ui()
	check(main.level_card_labels[1][5].visible and not main.level_card_labels[0][0].visible, "client sees own hand")
	await shot("client")
	main.online.session.role = NetworkSession.Role.OFFLINE
	main.ai_companion = false
	main._refresh_level_up_ui()
	check(main.level_card_labels[1][0].visible, "local focus hands off to second player")
	main.selected_upgrade_indices.assign([-1, -1])
	main._refresh_level_up_ui()
	check(main.level_card_labels[0][0].visible, "local first player regains focus")
	main.level_up_input_delay = 0
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	main.level_card_labels[0][2].gui_input.emit(event)
	check(main.selected_upgrade_indices[0] == 2, "card click still confirms")
	paused = false
	main.free()
	for failure in failures: push_error(failure)
	print("NEON_GROWTH_PASS" if failures.is_empty() else "NEON_GROWTH_FAIL")
	quit(0 if failures.is_empty() else 1)
