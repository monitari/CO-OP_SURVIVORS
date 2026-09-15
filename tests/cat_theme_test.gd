extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const CatPanel := preload("res://scripts/ui/cat_panel.gd")
const TestHarness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "CAT_THEME_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "CAT_THEME_FAIL"):
		return
	_check(not main.combat_hud.visible, "lobby hides empty combat HUD")
	var host: Control = main.hud_layer.get_node("ThemeHost")
	_check(main.lobby_title.get_theme_font("font") == host.theme.default_font,
		"Korean font theme reaches labels, not an empty sibling")
	_check(String(host.theme.default_font.resource_path).ends_with("Jua-Regular.ttf"),
		"the bundled rounded Korean font drives the UI on every machine")
	_check(main.lobby_overlay.has_node("LobbyAmbience/TitleLogo"), "lobby uses the large title asset")
	var ambience: Control = main.lobby_overlay.get_node("LobbyAmbience")
	var logo: TextureRect = ambience.get_node("TitleLogo")
	var logo_y := logo.position.y
	for frame in 8: await process_frame
	_check(not is_equal_approx(logo.position.y, logo_y), "the title has a restrained idle animation")
	_check(not main.lobby_title.visible, "the old duplicate text title is removed")
	for panel in [main.lobby_overlay, main.character_overlay, main.level_overlay,
		main.resonance_overlay, main.pause_overlay, main.result_overlay]:
		_check(panel.get_script() == CatPanel, "every modal uses shared cat skin")
		_check(panel.color.a == 0.0, "old square fill does not cover rounded skin")
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "decoration does not consume input")
	_fit(main.lobby_p1_label, "waiting lobby slot")
	_check_icon_bounds(main.lobby_overlay)
	main.lobby_input_cooldown = 0
	main._join_lobby_slot(0, -1, "키보드 WASD")
	await process_frame
	_fit(main.lobby_p1_label, "joined lobby slot")
	main._finish_lobby()
	var animated_panel: Panel = main.character_overlay.get_node("CharacterPanel0")
	var next_character: int = (main.selected_character_indices[0] + 1) % main.character_catalog.size()
	main.selected_character_indices[0] = next_character
	main._refresh_character_select_ui()
	_check(main.character_portrait_icons[0].scale.x < 1.0,
		"character portrait begins a soft selection transition")
	_check((animated_panel.get_node("NeonTrim") as Control).accent == main.CatTheme.P1
		and (main.character_overlay.get_node("CharacterPanel1/NeonTrim") as Control).accent == main.CatTheme.P2,
		"character dossiers use distinct cyan and orange ownership colours")
	await main.get_tree().create_timer(0.3, true).timeout
	_check(main.character_portrait_icons[0].scale.is_equal_approx(Vector2.ONE),
		"character selection transition settles cleanly")
	for index in main.character_catalog.size():
		main.selected_character_indices[0] = index
		main.selected_character_indices[1] = index
		main._refresh_character_select_ui()
		await process_frame
		_fit(main.character_p1_label, "character %d" % index)
		_check(not main.character_overlay.get_node("CatStat0_7").visible,
			"simple character view hides secondary statistics")
		main.ReviewUI.toggle_character_details(main)
		await process_frame
		_fit(main.character_p1_label, "detailed character %d" % index)
		_check(main.character_overlay.get_node("CatStat0_7").visible,
			"detailed character view restores every statistic")
		main.ReviewUI.toggle_character_details(main)
	_check_icon_bounds(main.character_overlay)
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	await physics_frame
	_check(main.combat_hud.visible, "combat HUD returns on start")
	var saved_health: float = main.players[0].health
	main.players[0].health = 1.0
	main._update_hud()
	var alert: Panel = main.combat_hud.get_node("TacticalAlert")
	_check(alert.visible and String(alert.get_node("Action").text).contains("나 체력 위험"),
		"critical health names the player and an escape action")
	main.players[1].downed = true
	main._update_hud()
	_check(String(alert.get_node("Action").text).contains("동료 구조 필요"),
		"rescuing a downed partner takes priority over low health")
	main.players[0].health = saved_health
	main.players[1].downed = false
	main._update_hud()
	_check(not alert.visible, "the action banner disappears when danger clears")
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0
	main._refresh_level_up_ui()
	await process_frame
	# The deciding player's hand; the partner's is deliberately dealt small.
	var cards: Array = main.level_card_labels[main.focused_growth_slot()]
	for index in cards.size():
		var card: Label = cards[index]
		if card.visible:
			# The hand is a fan, so a card may be tilted — but never scaled:
			# a card that grows under the cursor shoves its neighbours and
			# the whole row starts moving as the cursor walks it.
			_check(card.scale.is_equal_approx(Vector2.ONE),
				"growth cards keep their size while focus is shown by the border and the tilt")
			_fit(card, "growth card")
			_fit(card.get_node("CardTitle"), "growth title")
	_check_icon_bounds(main.level_overlay)
	main.fusion_discovered = true
	# Every treasure description, not merely three randomly drawn short ones.
	for treasure in main.Treasures.all_treasures():
		main.p1_choices.clear()
		var option := {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure,
			"title": "새 보물: " + String(treasure["name"]), "recommended": true,
			"recommendation_reason": "공명 해금   긴 이름의 공명 후보"}
		option["description"] = main._upgrade_preview(0, option)
		main.p1_choices.append(option)
		main._refresh_level_up_ui()
		await process_frame
		_fit(main.level_card_labels[0][0], "treasure " + String(treasure["id"]))
		_fit(main.level_card_labels[0][0].get_node("CardTitle"), "treasure title")
	main.level_up_active = false
	main.level_overlay.visible = false
	main.resonance_candidates = main.resonance_system.catalog.slice(0, 3)
	main.resonance_overlay.visible = true
	main._refresh_resonance_vote_ui()
	await process_frame
	for card in main.resonance_cards:
		_fit(card, "resonance card")
		_check(card.get_node("Cat0").texture != null, "resonance carries a cat portrait")
	for entry in main.resonance_system.catalog:
		main.resonance_candidates.clear()
		main.resonance_candidates.append(entry)
		main._refresh_resonance_vote_ui()
		await process_frame
		_fit(main.resonance_cards[0], "resonance " + String(entry["name"]))
	main.resonance_overlay.visible = false
	main._set_pause(true)
	await process_frame
	_fit(main.pause_label, "pause settings")
	main.EditorialUI.connection_notice(main, 0)
	await process_frame
	_fit(main.pause_label, "disconnected controller instructions")
	main._end_run(true)
	await process_frame
	_check_icon_bounds(main.result_overlay)
	_fit(main.result_overlay.get_node("CoopRecord"), "co-op record")
	if failures.is_empty():
		print("CAT_THEME_PASS: all screens skinned, Korean font inherited, roster and cards fit")
		quit(0)
	else:
		for failure in failures:
			push_error("CAT_THEME_FAIL: " + failure)
		quit(1)


func _fit(label: Label, context: String) -> void:
	_check(label.get_line_count() <= label.get_visible_line_count(),
		"%s fits (%d lines, %d visible)" % [context, label.get_line_count(), label.get_visible_line_count()])


func _check(ok: bool, context: String) -> void:
	if not ok:
		failures.append(context)


func _check_icon_bounds(node: Node) -> void:
	if node is TextureRect and node.get_parent() is Control:
		var parent: Control = node.get_parent()
		if parent.size.x > 0 and parent.size.y > 0:
			_check(Rect2(Vector2.ZERO, parent.size).encloses(node.get_rect()),
				"icon %s stays inside parent (%s vs %s)" % [node.name, node.get_rect(), parent.size])
	for child in node.get_children():
		_check_icon_bounds(child)
