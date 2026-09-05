extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")

static func button(parent: Control, caption: String, rect: Rect2, action: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE # Menus use explicit two-player cursors.
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Palette.INK)
	b.add_theme_color_override("font_hover_color", Palette.INK)
	b.add_theme_color_override("font_pressed_color", Palette.INK)
	b.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD, 8))
	b.add_theme_stylebox_override("hover", Palette.surface(Color("dce9dd"), 8))
	b.add_theme_stylebox_override("pressed", Palette.surface(Color("c7dccf"), 8))
	parent.add_child(b)
	b.pressed.connect(action)
	return b

static func install(main: Node) -> void:
	for index in main.character_catalog.size():
		var tile: Panel = main.character_overlay.get_node("Roster%d" % index)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton and event.pressed) or main.lobby_input_cooldown > 0: return
			if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: return
			var slot := 0 if event.button_index == MOUSE_BUTTON_LEFT else 1
			main.character_confirmed[slot] = false
			main.selected_character_indices[slot] = index
			main._refresh_character_select_ui())
	for slot in 2:
		var join: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		join.mouse_filter = Control.MOUSE_FILTER_STOP
		join.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		join.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				main._join_lobby_slot(slot, -1, "키보드 WASD" if slot == 0 else "키보드 방향키"))
		var x := 32.0 + slot * 548.0
		button(main.character_overlay, "이전", Rect2(x + 24, 540, 90, 32), func() -> void: choose_cat(main, slot, -1))
		button(main.character_overlay, "다음", Rect2(x + 122, 540, 90, 32), func() -> void: choose_cat(main, slot, 1))
		button(main.character_overlay, "확정 / 변경", Rect2(x + 330, 540, 174, 32), func() -> void:
			if main.lobby_input_cooldown > 0.0: return
			main.character_confirmed[slot] = not main.character_confirmed[slot]
			main._refresh_character_select_ui()
			if main.character_confirmed[0] and main.character_confirmed[1]: main._start_selected_run())
		for index in 3:
			var card: Label = main.level_card_labels[slot][index]
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.mouse_entered.connect(func() -> void:
				if main.selected_upgrade_indices[slot] < 0:
					main.upgrade_cursors[slot] = index
					main._refresh_level_up_ui())
			card.gui_input.connect(func(e: InputEvent) -> void:
				if not (e is InputEventMouseButton and e.pressed): return
				if e.button_index == MOUSE_BUTTON_RIGHT:
					main.upgrade_cursors[slot] = index
					toggle_details(main)
				elif e.button_index == MOUSE_BUTTON_LEFT and main.level_up_input_delay <= 0.0 and main.selected_upgrade_indices[slot] < 0:
					main._select_upgrade(slot + 1, index))
		button(main.level_overlay, "선택 취소", Rect2(300 + slot * 616, 426, 125, 32), func() -> void:
			if main.level_up_active:
				main.selected_upgrade_indices[slot] = -1
				main._refresh_level_up_ui()).name = "Cancel%d" % slot
		button(main.level_overlay, "다시 뽑기", Rect2(435 + slot * 616, 426, 160, 32), func() -> void:
			if main.level_up_active and main.level_up_input_delay <= 0.0 and main.selected_upgrade_indices[slot] < 0 and main.rerolls_remaining[slot] > 0:
				main._reroll_choices(slot + 1)).name = "Reroll%d" % slot
		for index in main.resonance_cards.size():
			var card: Label = main.resonance_cards[index]
			button(card, "P%d 선택" % (slot + 1), Rect2(16 + slot * 122, 240, 112, 32), func() -> void:
				if not main.resonance_vote_active: return
				main.resonance_votes[slot] = index
				main.resonance_cursors[slot] = index
				main._refresh_resonance_vote_ui())
	button(main.level_overlay, "상세 · TAB / X", Rect2(970, 24, 236, 32), func() -> void: toggle_details(main))
	button(main.result_overlay, "다시 결속하기", Rect2(310, 476, 300, 36), func() -> void:
		main.get_tree().paused = false
		main.get_tree().reload_current_scene())
	var settings: Control = main.pause_overlay.get_node("SettingsRows")
	settings.hide()
	for index in 6:
		button(main.pause_overlay, "", Rect2(32, 112 + index * 43, 596, 37), func() -> void: main._activate_pause_item(index)).name = "PauseAction%d" % index
	button(main.pause_overlay, "전체 능력치 · TAB / X", Rect2(32, 376, 596, 34), func() -> void: toggle_details(main))
	main.details_overlay = UI.plate(main.pause_overlay.get_parent(), Rect2(20, 132, 1240, 545), Palette.PANEL)
	main.details_overlay.name = "BuildDetails"
	main.details_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.details_overlay.z_index = 20
	main.details_overlay.hide()
	UI.label(main.details_overlay, "성장 기록 · 전체 능력치", Rect2(24, 12, 900, 40), 26)
	button(main.details_overlay, "닫기 · TAB / X", Rect2(952, 16, 210, 34), func() -> void: toggle_details(main))
	for slot in 2:
		var text := RichTextLabel.new()
		text.position = Vector2(24 + slot * 578, 68)
		text.size = Vector2(554, 418)
		text.add_theme_font_size_override("normal_font_size", 16)
		text.add_theme_color_override("default_color", Palette.INK)
		text.scroll_active = true
		main.details_overlay.add_child(text)
		text.name = "Details%d" % slot
	UI.label(main.details_overlay, "스크롤: 마우스 휠 / ↑ ↓ / 패드 방향키     ·     선택은 창을 닫은 뒤 확정", Rect2(24, 494, 1138, 26), 14, Palette.MUTED)

static func choose_cat(main: Node, slot: int, direction: int) -> void:
	if main.lobby_input_cooldown > 0.0: return
	main.character_confirmed[slot] = false
	main.selected_character_indices[slot] = wrapi(main.selected_character_indices[slot] + direction, 0, main.character_catalog.size())
	main._refresh_character_select_ui()

static func refresh_pause(main: Node) -> void:
	if not main.pause_overlay.has_node("PauseAction0"): return
	main.pause_overlay.get_node("SettingsRows").hide()
	var names := ["계속하기", "화면 흔들림", "피해 숫자", "효과음", "음악", "처음부터 다시"]
	var states := [true, main.screen_shake_enabled, main.feedback.damage_numbers_enabled, main.feedback.sound_enabled, main.feedback.music_enabled]
	main.pause_overlay.get_node("PauseHeading").text = "현재 판을 종료할까요?" if main.restart_pending else "잠시 쉬어가기"
	for index in 6:
		var b: Button = main.pause_overlay.get_node("PauseAction%d" % index)
		b.visible = not main.restart_pending or index < 2
		var caption: String = (["취소 · 계속 쉬기", "종료하고 처음부터"] [index] if main.restart_pending and index < 2 else names[index])
		if not main.restart_pending and index in [1, 2, 3, 4]: caption += "   ·   " + ("켜짐" if states[index] else "꺼짐")
		b.text = ("▶  " if main.pause_cursor == index else "") + caption
	UI.place(main.pause_label, Rect2(32, 416, 596, 38), 14)
	main.pause_label.text = "↑ ↓ / 패드 방향키 이동 · ENTER / A 선택 · ESC / B 닫기"
	if main.restart_pending:
		main.pause_label.text = "현재 판의 성장과 기록은 사라집니다. 취소가 기본 선택입니다."

static func toggle_details(main: Node) -> void:
	if not (main.level_up_active or main.pause_active) or main.resonance_vote_active: return
	main.details_overlay.visible = not main.details_overlay.visible
	main.modal_input_guard = 2
	main.level_overlay.visible = main.level_up_active and not main.details_overlay.visible
	main.pause_overlay.visible = main.pause_active and not main.details_overlay.visible
	if not main.details_overlay.visible: return
	for slot in 2:
		var p: Node = main.players[slot]
		var lines: Array[String] = ["P%d  %s" % [slot + 1, p.character_name],
			"체력 %.0f/%.0f   방어 %.0f   회복 %.1f/s" % [p.health, p.max_health, p.armor, p.recovery],
			"공격 %d%%   범위 %d%%   발동 간격 %d%%" % [roundi(p.might * 100), roundi(p.area * 100), roundi(p.haste * 100)],
			"추가 발사 %d   관통 +%d   치명타 %d%% (2배)" % [p.amount, p.pierce, roundi(p.crit_chance * 100)],
			"이속 %.0f   탄속 %d%%   반사 %d%%" % [p.move_speed, roundi(p.projectile_speed * 100), roundi(p.thorns * 100)],
			"다운 유예 %.0f초   동료 구조 %.2f초" % [p.BLEEDOUT_BASE + p.resolve, 2.6 / (1.0 + p.resolve * 0.05)],
			"공유 XP %d%% · 자석 %d%% · 행운 %d · 욕심 +%d%%" % [roundi(main.team_growth * 100), roundi(main.team_magnet * 100), main.team_luck, roundi(main.team_greed * 100)],
			"사슬 %.0f   과충전 공격 +%d%% · 내구 소모 %d%%" % [main.chain_max_length, roundi((0.25 + main.team_overcharge) * 100), roundi(maxf(0.25, 1.0 - main.team_overcharge * 1.2) * 100)], ""]
		var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
		if main.level_up_active and not choices.is_empty():
			var choice: Dictionary = choices[main.upgrade_cursors[slot]]
			lines.append(String(choice["title"]).replace("\n", " · "))
			lines.append(String(choice["description"]))
			lines.append("추천 근거: " + String(choice.get("recommendation_reason", "균형 성장")))
		lines.append("합성  " + main._fusion_progress_line(slot))
		for w: Dictionary in main.weapon_loadouts[slot]:
			lines.append("%s T%d · 피해 %.1f · 발동 %.2f초" % [w["weapon_name"], w.get("tier", 1), float(w["damage"]) * p.might, maxf(0.12, float(w["cooldown"]) * p.haste)])
		lines.append("치명타는 발동마다 판정 · 추가 발사/관통은 해당 무기에 적용")
		lines.append("화력은 명중·범위 가정에 따른 비교 추정치입니다.")
		main.details_overlay.get_node("Details%d" % slot).text = "\n".join(lines)
		main.details_overlay.get_node("Details%d" % slot).scroll_to_line(0)
