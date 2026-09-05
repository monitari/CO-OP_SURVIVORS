extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")
const Icons := preload("res://scripts/ui/icon_catalog.gd")

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
	var pause_rects := [
		Rect2(32, 112, 252, 62), Rect2(316, 138, 230, 72),
		Rect2(558, 138, 230, 72), Rect2(316, 226, 230, 72),
		Rect2(558, 226, 230, 72), Rect2(32, 188, 252, 48),
	]
	for index in 6:
		var action := button(main.pause_overlay, "", pause_rects[index], func() -> void: main._activate_pause_item(index))
		action.name = "PauseAction%d" % index
		action.add_theme_font_size_override("font_size", 17 if index == 0 else 15)
	button(main.pause_overlay, "전체 능력치 · TAB / X", Rect2(32, 250, 252, 48), func() -> void: toggle_details(main)).name = "PauseDetails"
	var snapshot := UI.plate(main.pause_overlay, Rect2(32, 318, 756, 120), Palette.CARD)
	snapshot.name = "RunSnapshot"
	UI.label(snapshot, "RUN SNAPSHOT", Rect2(18, 12, 180, 22), 13, Palette.GOLD)
	UI.label(snapshot, "", Rect2(18, 39, 720, 62), 16, Palette.INK).name = "Value"
	main.details_overlay = UI.plate(main.pause_overlay.get_parent(), Rect2(20, 132, 1240, 545), Palette.PANEL)
	main.details_overlay.name = "BuildDetails"
	main.details_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.details_overlay.z_index = 20
	main.details_overlay.hide()
	UI.label(main.details_overlay, "성장 기록 · 전체 능력치", Rect2(24, 12, 900, 40), 26)
	button(main.details_overlay, "닫기 · TAB / X", Rect2(952, 16, 210, 34), func() -> void: toggle_details(main))
	for slot in 2:
		var x := 24.0 + slot * 602.0
		var header := UI.plate(main.details_overlay, Rect2(x, 64, 578, 72), Palette.CARD)
		header.name = "DetailHeader%d" % slot
		UI.icon(header, null, Rect2(12, 8, 56, 56)).name = "Portrait"
		UI.icon(header, null, Rect2(80, 14, 44, 44)).name = "Weapon"
		UI.label(header, "", Rect2(138, 10, 420, 27), 20, Palette.P1 if slot == 0 else Palette.P2).name = "Name"
		UI.label(header, "", Rect2(138, 39, 420, 23), 14, Palette.MUTED).name = "WeaponName"
		_detail_card(main.details_overlay, x, 146, "might", "공격", "Offense%d" % slot)
		_detail_card(main.details_overlay, x + 293, 146, "vitality", "생존", "Survival%d" % slot)
		_detail_card(main.details_overlay, x, 268, "overcharge", "협동", "Coop%d" % slot)
		_detail_card(main.details_overlay, x + 293, 268, "magnet", "탐색", "Utility%d" % slot)
		var build := UI.plate(main.details_overlay, Rect2(x, 390, 578, 104), Palette.CARD)
		build.name = "Build%d" % slot
		UI.label(build, "장비 구성", Rect2(16, 10, 150, 22), 14, Palette.GOLD)
		UI.label(build, "", Rect2(16, 36, 546, 58), 14, Palette.INK).name = "Value"
	UI.label(main.details_overlay, "한 화면에 핵심 수치와 장비를 모두 표시합니다 · 선택은 창을 닫은 뒤 확정", Rect2(24, 502, 1138, 24), 14, Palette.MUTED)


static func _detail_card(parent: Control, x: float, y: float, icon_id: String, title: String, node_name: String) -> void:
	var card := UI.plate(parent, Rect2(x, y, 285, 112), Palette.CARD)
	card.name = node_name
	UI.icon(card, Icons.upgrade(icon_id), Rect2(14, 12, 30, 30))
	UI.label(card, title, Rect2(52, 13, 214, 26), 15, Palette.GOLD)
	var value := UI.label(card, "", Rect2(14, 43, 257, 62), 13, Palette.INK)
	value.name = "Value"
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
		if not main.restart_pending and index in [1, 2, 3, 4]: caption += "\n" + ("● 켜짐" if states[index] else "○ 꺼짐")
		b.text = ("▶  " if main.pause_cursor == index else "") + caption
		var style := Palette.surface(Palette.CARD.lerp(Palette.P1, 0.10) if main.pause_cursor == index else Palette.CARD, 10)
		style.border_color = Palette.P1 if main.pause_cursor == index else Palette.OUTLINE
		style.set_border_width_all(3 if main.pause_cursor == index else 1)
		b.add_theme_stylebox_override("normal", style)
	main.pause_overlay.get_node("PauseDetails").visible = not main.restart_pending
	main.pause_overlay.get_node("RunSnapshot").visible = not main.restart_pending
	if not main.restart_pending:
		main.pause_overlay.get_node("RunSnapshot/Value").text = "%02d:%02d  ·  LV.%d  ·  %d 처치\n%s / %s  ·  사슬 내구 %d%%" % [int(main.elapsed) / 60, int(main.elapsed) % 60, main.progression.level, main.kills, main.players[0].character_name, main.players[1].character_name, roundi(main.chain_integrity)]
	else:
		main.pause_overlay.get_node("PauseAction0").position = Vector2(158, 190)
		main.pause_overlay.get_node("PauseAction0").size = Vector2(252, 64)
		main.pause_overlay.get_node("PauseAction1").position = Vector2(430, 190)
		main.pause_overlay.get_node("PauseAction1").size = Vector2(252, 64)
	if not main.restart_pending:
		var rects := [Vector2(32, 112), Vector2(316, 138), Vector2(558, 138), Vector2(316, 226), Vector2(558, 226), Vector2(32, 188)]
		for index in 6:
			main.pause_overlay.get_node("PauseAction%d" % index).position = rects[index]
			main.pause_overlay.get_node("PauseAction%d" % index).size = Vector2(252, 62 if index == 0 else (48 if index == 5 else 72)) if index in [0, 5] else Vector2(230, 72)
	UI.place(main.pause_label, Rect2(32, 462, 756, 34), 14)
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
		var header: Panel = main.details_overlay.get_node("DetailHeader%d" % slot)
		header.get_node("Portrait").texture = Icons.survivor(String(main.selected_characters[slot]["id"]))
		header.get_node("Weapon").texture = Icons.weapon(String(main.weapon_loadouts[slot][0]["weapon_id"]))
		header.get_node("Name").text = "P%d  %s" % [slot + 1, p.character_name]
		header.get_node("WeaponName").text = "%d 무기 · %d 보물" % [main.weapon_loadouts[slot].size(), main.treasure_loadouts[slot].size()]
		main.details_overlay.get_node("Offense%d/Value" % slot).text = "위력 %d%% · 치명 %d%% · 발동 %d%%\n추가 +%d · 관통 +%d · 탄속 %d%%" % [roundi(p.might * 100), roundi(p.crit_chance * 100), roundi(100.0 / p.haste), p.amount, p.pierce, roundi(p.projectile_speed * 100)]
		main.details_overlay.get_node("Survival%d/Value" % slot).text = "HP %.0f/%.0f · 방어 %.0f · 재생 %.1f/s\n회피 %d%% · 반사 %d%% · 목숨 %d" % [p.health, p.max_health, p.armor, p.recovery, roundi(p.dodge_chance * 100), roundi(p.thorns * 100), p.second_chances]
		main.details_overlay.get_node("Coop%d/Value" % slot).text = "사슬 %.0f · 구조 %.2f초 · 유예 %.0f초\n과충전 +%d%% · 밀착 +%d%% · 대시 %.0f" % [main.chain_max_length, 2.6 / (1.0 + p.resolve * 0.05), p.BLEEDOUT_BASE + p.resolve, roundi((0.25 + main.team_overcharge) * 100), roundi(main.team_close_power * 100), main.team_dash_burst]
		main.details_overlay.get_node("Utility%d/Value" % slot).text = "이속 %.0f · 범위 %d%% · 자력 %d%%\nXP %d%% · 강적 +%d%% · 행운 %d\n레벨 회복 %d%% · 드롭 +%d%%" % [p.move_speed, roundi(p.area * 100), roundi(main.team_magnet * 100), roundi(main.team_growth * 100), roundi(main.team_hunt_bonus * 100), main.team_luck, roundi(main.team_level_heal * 100), roundi(main.team_greed * 100)]
		var build_lines: Array[String] = []
		var weapon_names: Array[String] = []
		for w: Dictionary in main.weapon_loadouts[slot]:
			weapon_names.append("%s T%d" % [w["weapon_name"], w.get("tier", 1)])
		var treasure_names: Array[String] = []
		for treasure: Dictionary in main.treasure_loadouts[slot]:
			treasure_names.append("%s T%d" % [treasure["name"], treasure["tier"]])
		build_lines.append("무기  " + (" · ".join(weapon_names) if not weapon_names.is_empty() else "없음"))
		build_lines.append("보물  " + (" · ".join(treasure_names) if not treasure_names.is_empty() else "없음"))
		var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
		if main.level_up_active and not choices.is_empty():
			var choice: Dictionary = choices[main.upgrade_cursors[slot]]
			build_lines.append("선택  %s · ★ %s" % [String(choice["title"]).replace("\n", " "), String(choice.get("recommendation_reason", "균형 성장")).split("   ")[0]])
		main.details_overlay.get_node("Build%d/Value" % slot).text = "\n".join(build_lines)
