extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const G := preload("res://scripts/ui/layout_grid.gd")

## One full-width primary action, a strict 2x2 settings grid, and a final pair
## of run actions. Every edge shares the same 16px inset and centre gutter.
const PAUSE_ITEM_COUNT := 8
const PAUSE_SLOTS := [
	Rect2(20, 80, 340, 44), Rect2(20, 188, 340, 44), Rect2(20, 242, 340, 44),
	Rect2(20, 296, 340, 44), Rect2(20, 350, 340, 44), Rect2(20, 188, 340, 44),
	Rect2(20, 242, 340, 44), Rect2(20, 134, 340, 44),
]

static func pause_neighbor(index: int, direction: String, settings := false) -> int:
	var order := [0, 7, 1, 2, 3, 4] if settings else [0, 7, 5, 6]
	var step := -1 if direction in ["up", "left"] else 1
	return int(order[wrapi(order.find(index) + step, 0, order.size())])


static func button(parent: Control, caption: String, rect: Rect2, action: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE # Menus use explicit two-player cursors.
	b.add_theme_font_size_override("font_size", Palette.TYPE_BODY)
	b.add_theme_color_override("font_color", Palette.INK)
	b.add_theme_color_override("font_hover_color", Palette.INK)
	b.add_theme_color_override("font_pressed_color", Palette.INK)
	b.add_theme_color_override("font_disabled_color", Color(Palette.MUTED, 0.6))
	b.add_theme_stylebox_override("normal", Palette.button_surface())
	b.add_theme_stylebox_override("hover", Palette.button_surface("hover"))
	b.add_theme_stylebox_override("pressed", Palette.button_surface("pressed"))
	b.add_theme_stylebox_override("disabled", Palette.button_surface("disabled"))
	parent.add_child(b)
	b.pressed.connect(action)
	return b

## Mouse hit areas over the title rows. The labels themselves carry the styling
## and the state text; these sit on top of them so the same list works with a
## cursor, a pad and a pointer without any of the three knowing about the others.
static func refresh_title(main: Node) -> void:
	if not main.title_overlay.has_node("TitleHit0"):
		return
	var rows: Array = main._title_rows()
	for index in main.title_rows.size():
		var hit: Button = main.title_overlay.get_node("TitleHit%d" % index)
		var row: Label = main.title_rows[index]
		hit.visible = index < rows.size()
		hit.position = row.position
		hit.size = row.size
	if main.title_overlay.has_node("TitleMetaBack"):
		main.title_overlay.get_node("TitleMetaBack").visible = main.title_mode == "meta"


static func install(main: Node) -> void:
	button(main.character_overlay, "상세 보기    TAB / X", Rect2(936, 14, 224, 36), func() -> void:
		toggle_character_details(main)).name = "CharacterDetails"
	for index in main.title_rows.size():
		var hit := button(main.title_overlay, "", Rect2(0, 0, 10, 10), func() -> void: main._activate_title_item(index))
		hit.name = "TitleHit%d" % index
		# Transparent: the Label underneath is what is actually drawn, so the
		# button contributes a click target and nothing else.
		hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var meta_back := button(main.title_overlay, "메인 메뉴로", Rect2(870, 510, 180, 36), func() -> void: main._leave_title_subpage())
	meta_back.name = "TitleMetaBack"
	meta_back.visible = false
	for index in main.character_catalog.size():
		var tile: Panel = main.character_overlay.get_node("Roster%d" % index)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton and event.pressed) or main.lobby_input_cooldown > 0: return
			if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: return
			var slot := 0 if event.button_index == MOUSE_BUTTON_LEFT else 1
			main._set_character_choice(slot, index, false))
	for slot in 2:
		var join: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		join.mouse_filter = Control.MOUSE_FILTER_STOP
		join.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		join.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				main._join_lobby_slot(slot, -1, "키보드 WASD" if slot == 0 else "키보드 방향키"))
		# The same half-page card the select screen draws, so the buttons sit
		# under their own survivor rather than near them.
		var x := G.x(0.25 + slot * 5.75) - G.x(0)
		button(main.character_overlay, "이전", Rect2(x + G.GUTTER, 497, 90, 36), func() -> void: choose_cat(main, slot, -1)).name = "CharacterPrevious%d" % slot
		button(main.character_overlay, "다음", Rect2(x + G.GUTTER + 106.0, 497, 90, 36), func() -> void: choose_cat(main, slot, 1)).name = "CharacterNext%d" % slot
		var accent := Palette.P1 if slot == 0 else Palette.P2
		var confirm := button(main.character_overlay, "준비하기", Rect2(x + G.w(5.5) - 174.0 - G.GUTTER, 497, 174, 36), func() -> void:
			if main.lobby_input_cooldown > 0.0: return
			main._set_character_choice(slot, main.selected_character_indices[slot],
				not main.character_confirmed[slot]))
		confirm.name = "CharacterConfirm%d" % slot
		confirm.add_theme_stylebox_override("normal", Palette.button_surface("normal", accent, true))
		confirm.add_theme_stylebox_override("hover", Palette.button_surface("hover", accent, true))
		confirm.add_theme_stylebox_override("pressed", Palette.button_surface("pressed", accent, true))
		for index in main.LEVEL_CARD_SLOTS:
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
				elif e.button_index == MOUSE_BUTTON_LEFT and main.level_up_input_delay <= 0.0:
					if main.selected_upgrade_indices[slot] == index and main.selected_upgrade_indices[1 - slot] < 0:
						main._cancel_growth_choice(slot)
					elif main.selected_upgrade_indices[slot] < 0:
						main.upgrade_cursors[slot] = index
						main._confirm_growth_choice(slot, index))
		var reroll := button(main.level_overlay, "↻  다시 뽑기", Rect2(main.LEVEL_HALF_X[slot] + 232, 480, 176, 38), func() -> void:
			if main.level_up_active and main.level_up_input_delay <= 0.0 and main.selected_upgrade_indices[slot] < 0 and main.rerolls_remaining[slot] > 0:
				main._reroll_growth_choice(slot))
		reroll.name = "Reroll%d" % slot
		reroll.add_theme_stylebox_override("normal", Palette.button_surface("normal", accent, true))
		reroll.add_theme_stylebox_override("hover", Palette.button_surface("hover", accent, true))
		reroll.add_theme_stylebox_override("pressed", Palette.button_surface("pressed", accent, true))
		for index in main.resonance_cards.size():
			var card: Label = main.resonance_cards[index]
			button(card, "%s 선택" % main.player_label(slot), Rect2(14 + slot * 110, 244, 98, 32), func() -> void:
				if not main.resonance_vote_active: return
				main.resonance_votes[slot] = index
				main.resonance_cursors[slot] = index
				main._refresh_resonance_vote_ui())
	var result_menu := button(main.result_overlay, "메인 메뉴로", Rect2((G.w(8) - 300.0) * 0.5, 582, 300, 34), func() -> void:
		main.get_tree().paused = false
		main.get_tree().reload_current_scene())
	result_menu.name = "ResultMenu"
	var settings: Control = main.pause_overlay.get_node("SettingsRows")
	settings.hide()
	var pause_rects := PAUSE_SLOTS
	for index in PAUSE_ITEM_COUNT:
		var action := button(main.pause_overlay, "", pause_rects[index], func() -> void: main._activate_pause_item(index))
		action.name = "PauseAction%d" % index
		action.add_theme_font_size_override("font_size", 17 if index == 0 else 15)
	button(main.pause_overlay, "전체 능력치    TAB / X", Rect2(G.w(8) - 236, 24, 220, 36), func() -> void: toggle_details(main)).name = "PauseDetails"
	var snapshot := UI.plate(main.pause_overlay, Rect2(16, 370, G.w(8) - G.GUTTER * 2.0, 104), Palette.CARD)
	snapshot.name = "RunSnapshot"
	UI.label(snapshot, "이번 산책", Rect2(18, 10, 180, 22), 15, Palette.P1)
	for index in 4:
		var x := 18 + index * 182
		UI.label(snapshot, ["생존 시간", "공유 성장", "처치", "사슬 내구"][index], Rect2(x, 38, 168, 20), 13, Palette.MUTED)
		UI.label(snapshot, "", Rect2(x, 62, 168, 34), Palette.TYPE_VALUE, Palette.INK).name = "Metric%d" % index
	main.details_overlay = UI.plate(main.pause_overlay.get_parent(), Rect2(G.x(0), 132, G.w(12), 545), Palette.PANEL)
	main.details_overlay.name = "BuildDetails"
	main.details_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.details_overlay.z_index = 20
	main.details_overlay.hide()
	UI.label(main.details_overlay, "성장 기록    전체 능력치", Rect2(24, 12, 900, 40), Palette.TYPE_TITLE)
	button(main.details_overlay, "닫기    TAB / X", Rect2(G.w(12) - 210.0 - G.GUTTER, 16, 210, 34), func() -> void: toggle_details(main))
	for slot in 2:
		var x := 24.0 + slot * 576.0
		var header := UI.plate(main.details_overlay, Rect2(x, 64, 560, 72), Palette.CARD)
		header.name = "DetailHeader%d" % slot
		UI.icon(header, null, Rect2(12, 8, 56, 56)).name = "Portrait"
		UI.icon(header, null, Rect2(80, 14, 44, 44)).name = "Weapon"
		UI.label(header, "", Rect2(138, 10, 402, 27), 20, Palette.P1 if slot == 0 else Palette.P2).name = "Name"
		UI.label(header, "", Rect2(138, 39, 402, 23), 14, Palette.MUTED).name = "WeaponName"
		_detail_card(main.details_overlay, x, 146, "might", "공격", "Offense%d" % slot)
		_detail_card(main.details_overlay, x + 288, 146, "vitality", "생존", "Survival%d" % slot)
		_detail_card(main.details_overlay, x, 268, "overcharge", "협동", "Coop%d" % slot)
		_detail_card(main.details_overlay, x + 288, 268, "magnet", "탐색", "Utility%d" % slot)
		# Four lines now: the selected tech path also lives in the detail view,
		# with its real treasure and final-form names visible from the start.
		var build := UI.plate(main.details_overlay, Rect2(x, 384, 560, 116), Palette.CARD)
		build.name = "Build%d" % slot
		UI.label(build, "장비 구성", Rect2(16, 8, 150, 22), 14, Palette.GOLD)
		UI.label(build, "", Rect2(16, 32, 528, 78), 14, Palette.INK).name = "Value"
	UI.label(main.details_overlay, "한 화면에 핵심 수치와 장비를 모두 표시합니다    선택은 창을 닫은 뒤 확정", Rect2(24, 508, 1138, 24), 14, Palette.MUTED)


static func toggle_character_details(main: Node) -> void:
	main.character_overlay.set_meta("show_details", not bool(main.character_overlay.get_meta("show_details", false)))
	UI.refresh_characters(main)


static func _detail_card(parent: Control, x: float, y: float, icon_id: String, title: String, node_name: String) -> void:
	var card := UI.plate(parent, Rect2(x, y, 272, 112), Palette.CARD)
	card.name = node_name
	UI.icon(card, Icons.upgrade(icon_id), Rect2(14, 12, 30, 30))
	UI.label(card, title, Rect2(52, 13, 214, 26), 15, Palette.GOLD)
	var value := UI.label(card, "", Rect2(14, 43, 244, 62), 13, Palette.INK)
	value.name = "Value"
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func choose_cat(main: Node, slot: int, direction: int) -> void:
	if main.lobby_input_cooldown > 0.0: return
	main._set_character_choice(slot,
		wrapi(main.selected_character_indices[slot] + direction, 0, main.character_catalog.size()), false)

static func refresh_pause(main: Node) -> void:
	if not main.pause_overlay.has_node("PauseAction0"): return
	var screen: Control = main.pause_overlay
	screen.position = Vector2(450, 125 if main.pause_settings else 180)
	screen.size = Vector2(380, 470 if main.pause_settings else 360)
	for child in screen.get_children():
		if child is Label or child.name in ["SettingsRows", "RunSnapshot"]:
			child.hide()
	var heading: Label = screen.get_node("PauseHeading")
	heading.show()
	UI.place(heading, Rect2(20, 16, 340, 42), 24)
	heading.text = "설정" if main.pause_settings else "잠시 쉬어가기"
	if main.restart_pending:
		heading.text = "게임을 종료할까요?" if main.pending_quits else "메뉴로 돌아갈까요?"
	var names := ["계속하기", "화면 흔들림", "피해 숫자", "효과음", "음악", "메인 메뉴로", "게임 종료", "돌아가기" if main.pause_settings else "설정"]
	var states := [true, main.screen_shake_enabled, main.feedback.damage_numbers_enabled, main.feedback.sound_enabled, main.feedback.music_enabled]
	var order := [0, 7, 1, 2, 3, 4] if main.pause_settings else [0, 7, 5, 6]
	for index in PAUSE_ITEM_COUNT:
		var button: Button = screen.get_node("PauseAction%d" % index)
		button.visible = index < 2 if main.restart_pending else index in order
		button.position = PAUSE_SLOTS[index].position
		button.size = PAUSE_SLOTS[index].size
		button.text = names[index]
		if index in [1, 2, 3, 4]:
			button.text += "        " + ("켜짐" if states[index] else "꺼짐")
		if main.restart_pending and index < 2:
			button.position = Vector2(20, 100 + index * 60)
			button.text = "취소" if index == 0 else "종료" if main.pending_quits else "메뉴로 돌아가기"
		button.add_theme_stylebox_override("normal", Palette.button_surface("hover" if index == main.pause_cursor else "normal", Palette.P1, index == main.pause_cursor))
	var details: Button = screen.get_node("PauseDetails")
	details.visible = not main.restart_pending and not main.pause_settings
	details.position = Vector2(20, 302)
	details.size = Vector2(340, 34)
	details.text = "내 장비    능력치   TAB"
	main.pause_label.hide()


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
		header.get_node("Name").text = "%s  %s" % [main.player_label(slot), p.character_name]
		header.get_node("WeaponName").text = "%d 무기    %d 보물" % [main.weapon_loadouts[slot].size(), main.treasure_loadouts[slot].size()]
		main.details_overlay.get_node("Offense%d/Value" % slot).text = "위력 %d%%    치명 %d%%    발동 %d%%\n추가 +%d    관통 +%d    탄속 %d%%    지속 %d%%" % [roundi(p.might * 100), roundi(p.crit_chance * 100), roundi(100.0 / p.haste), p.amount, p.pierce, roundi(p.projectile_speed * 100), roundi(p.duration * 100)]
		main.details_overlay.get_node("Survival%d/Value" % slot).text = "HP %.0f/%.0f    방어 %.0f    재생 %.1f/s\n회피 %d%%    반사 %d%%    목숨 %d" % [p.health, p.max_health, p.armor, p.recovery, roundi(p.dodge_chance * 100), roundi(p.thorns * 100), p.second_chances]
		main.details_overlay.get_node("Coop%d/Value" % slot).text = "사슬 %.0f    구조 %.2f초    유예 %.0f초\n과충전 +%d%%    밀착 +%d%%    대시 %.0f" % [main.chain_max_length, 2.6 / (1.0 + p.resolve * 0.05), p.BLEEDOUT_BASE + p.resolve, roundi((0.25 + main.team_overcharge) * 100), roundi(main.team_close_power * 100), main.team_dash_burst]
		main.details_overlay.get_node("Utility%d/Value" % slot).text = "이속 %.0f    범위 %d%%    자력 %d%%\nXP %d%%    강적 +%d%%    행운 %d    흡혈 %.1f%%\n레벨 회복 %d%%    드롭 +%d%%" % [p.move_speed, roundi(p.area * 100), roundi(main.team_magnet * 100), roundi(main.team_growth * 100), roundi(main.team_hunt_bonus * 100), main.team_luck, main.team_lifesteal * 100.0, roundi(main.team_level_heal * 100), roundi(main.team_greed * 100)]
		var build_lines: Array[String] = []
		var weapon_names: Array[String] = []
		for index in main.weapon_loadouts[slot].size():
			var w: Dictionary = main.weapon_loadouts[slot][index]
			# A weapon a resonance is firing for still has a level, and that level
			# still feeds the resonance — this is the one readout with room to say
			# both, so the HUD and the growth row can get away with just "공명".
			var silenced: String = "    공명 전담" if main.resonance_system.is_bound(slot, index) else ""
			weapon_names.append("%s Lv.%d%s" % [w["weapon_name"], w.get("tier", 1), silenced])
		var treasure_names: Array[String] = []
		for treasure: Dictionary in main.treasure_loadouts[slot]:
			treasure_names.append("%s Lv.%d" % [treasure["name"], treasure["tier"]])
		build_lines.append("무기  " + ("    ".join(weapon_names) if not weapon_names.is_empty() else "없음"))
		build_lines.append("보물  " + ("    ".join(treasure_names) if not treasure_names.is_empty() else "없음"))
		build_lines.append("보물 강화  " + main._fusion_progress_line(slot))
		var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
		if main.level_up_active and not choices.is_empty():
			var choice: Dictionary = choices[main.upgrade_cursors[slot]]
			build_lines.append("선택  %s    ★ %s" % [String(choice["title"]).replace("\n", " "), String(choice.get("recommendation_reason", "균형 성장")).split("   ")[0]])
		main.details_overlay.get_node("Build%d/Value" % slot).text = "\n".join(build_lines)

	preload("res://scripts/ui/player_perspective.gd").details(main)
