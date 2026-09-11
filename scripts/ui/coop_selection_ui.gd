extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const Review := preload("res://scripts/ui/review_ui.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")


static func install(main: Node) -> void:
	Review.button(main.lobby_overlay, "혼자 + AI 동료   [B]", Rect2(432, 514, 320, 32),
		func() -> void: main._join_ai_companion()).name = "JoinCompanion"
	Review.button(main.lobby_overlay, "LAN 방 만들기   [H]", Rect2(244, 470, 220, 36),
		func() -> void: main.online.host_game()).name = "HostLan"
	var address := LineEdit.new()
	address.name = "LanAddress"
	address.text = "127.0.0.1"
	address.placeholder_text = "호스트 IP 주소"
	address.position = Vector2(476, 470)
	address.size = Vector2(220, 36)
	address.add_theme_font_size_override("font_size", 15)
	main.lobby_overlay.add_child(address)
	Review.button(main.lobby_overlay, "참가   [J]", Rect2(708, 470, 148, 36),
		func() -> void: main.online.join_game(address.text)).name = "JoinLan"
	var status := UI.label(main.lobby_overlay, "", Rect2(244, 550, 612, 18), 13, Palette.MUTED)
	status.name = "NetworkStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Capture the authored layout without changing node paths used by the UI.
	for child in main.level_overlay.get_children():
		if child is Control and child.position.y >= 58 and child.position.y <= 530:
			if child == main.team_stats_label or String(child.name).begins_with("Footer"):
				continue
			child.set_meta("coop_rect", Rect2(child.position, child.size))
			child.set_meta("coop_slot", 0 if child.position.x < main.LEVEL_HALF_X[1] else 1)
	var panel := UI.plate(main.level_overlay, Rect2(736, 100, 408, 276), Palette.NIGHT_PANEL)
	panel.name = "CompanionSummary"
	UI.icon(panel, null, Rect2(20, 20, 56, 56)).name = "Portrait"
	UI.label(panel, "", Rect2(92, 20, 294, 50), 18, Palette.P2).name = "Identity"
	var detail := UI.label(panel, "", Rect2(20, 92, 366, 154), 16, Palette.MUTED)
	detail.name = "Detail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Review.button(main.level_overlay, "P1 선택 다시 보기", Rect2(736, 398, 280, 36), func() -> void:
		main.selected_upgrade_indices[0] = -1
		main._refresh_level_up_ui()).name = "ReturnToFirst"


static func restore(main: Node) -> void:
	for child in main.level_overlay.get_children():
		if child.has_meta("coop_rect"):
			var rect: Rect2 = child.get_meta("coop_rect")
			child.position = rect.position
			child.size = rect.size
			child.visible = bool(child.get_meta("coop_visible", child.visible))


static func refresh(main: Node) -> void:
	var focus: int = main.focused_growth_slot()
	for child in main.level_overlay.get_children():
		if not child.has_meta("coop_rect"):
			continue
		child.set_meta("coop_visible", child.visible)
		var slot: int = child.get_meta("coop_slot")
		child.visible = child.visible and slot == focus
		if slot == focus:
			child.position.x += 72.0 - main.LEVEL_HALF_X[slot]
	var other := 1 - focus
	var panel: Control = main.level_overlay.get_node("CompanionSummary")
	panel.get_node("Portrait").texture = main.hud_portrait_icons[other].texture
	var ai: bool = main.ai_companion and other == 1
	var selected: int = main.selected_upgrade_indices[other]
	var status := "선택 완료" if selected >= 0 else ("빌드 완성" if selected == -2 else ("자동 선택 중" if ai else "다음 선택 차례"))
	panel.get_node("Identity").add_theme_color_override("font_color", Palette.P1 if other == 0 else Palette.P2)
	panel.get_node("Identity").text = "%s · %s\n%s" % ["AI 동료" if ai else "P%d" % (other + 1), main.players[other].character_name, status]
	var names: Array[String] = []
	for weapon: Dictionary in main.weapon_loadouts[other]:
		names.append(String(weapon["weapon_name"]))
	var detail := "무기 · " + " / ".join(names)
	var choices: Array = main.p1_choices if other == 0 else main.p2_choices
	if selected >= 0 and selected < choices.size():
		detail += "\n\n선택 · " + String(choices[selected]["title"]).replace("\n", " ")
	elif ai:
		detail += "\n\n이동 · 위험 회피 · 구조\n성장은 빌드에 맞춰 자동 선택"
	else:
		detail += "\n\n현재 플레이어가 확정하면\n다음 선택 화면으로 넘어갑니다."
	panel.get_node("Detail").text = detail
	main.level_title.text = "P%d 성장 선택 / LV.%02d" % [focus + 1, main.progression.level]
	main.level_overlay.get_node("ReturnToFirst").visible = not main.ai_companion and focus == 1 and main.selected_upgrade_indices[0] >= 0
	if main.level_overlay.has_node("ControlFooter"):
		main.level_overlay.get_node("ControlFooter").text = "내 카드 선택 → 선택 확정 · 동료의 빌드는 오른쪽에서 확인"


static func lan_address(main: Node) -> String:
	var input := main.lobby_overlay.get_node_or_null("LanAddress") as LineEdit
	return input.text if input != null else "127.0.0.1"
