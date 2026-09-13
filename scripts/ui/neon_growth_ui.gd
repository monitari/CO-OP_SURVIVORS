extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const CardVisual := preload("res://scripts/ui/growth_card_visual.gd")
const CYAN := CardVisual.CYAN
const VIOLET := CardVisual.PARTNER
const INK := CardVisual.INK
const CARD_HOVER_LIFT := 24.0
const CARD_HOVER_TIME := 0.18

static func trim(parent: Control, tint: Color, selected := false, ears := false) -> void:
	CardVisual.decorate(parent, tint, selected, ears, parent is Label or parent.name == "PartnerChoice", false)


static func surface(tint: Color, selected := false) -> StyleBoxFlat:
	return CardVisual.surface(tint, selected)


static func refresh(main: Node) -> void:
	var primary: int = main.local_view_slot() if main.ai_companion or main.online.is_online() else main.focused_growth_slot()
	_install(main)
	for slot in 2:
		var own := slot == primary
		var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
		var count := choices.size()
		var chosen: int = main.selected_upgrade_indices[slot]
		var focus: int = chosen if chosen >= 0 else main.upgrade_cursors[slot]
		for index in main.level_card_labels[slot].size():
			var card: Label = main.level_card_labels[slot][index]
			var was_visible := card.visible
			card.visible = index < count and own
			if not card.visible:
				card.set_meta("neon_shown", false)
				continue
			var selected: bool = index == focus
			var width := 224.0 if count <= 3 else (208.0 if count == 4 else 182.0)
			var height := 348.0 if count <= 4 else 322.0
			var spread := 226.0 if count <= 3 else (220.0 if count == 4 else 190.0)
			var middle := (count - 1) * 0.5
			card.size = Vector2(width, height)
			card.pivot_offset = Vector2(width * 0.5, height)
			var target_position := Vector2(625 + (index - middle) * spread - width * 0.5, 70 + absf(index - middle) * 5)
			var target_rotation: float = (index - middle) / maxf(1.0, middle) * 0.11
			_animate_card(card, target_position, target_rotation, selected, was_visible)
			card.z_index = 8 if selected else 3
			card.modulate = Color.WHITE if chosen < 0 or selected else Color("aeb8cb")
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			_card(main, card, slot, choices[index], selected, width, height)
		var reroll: Button = main.level_overlay.get_node("Reroll%d" % slot)
		reroll.visible = own and reroll.visible
		reroll.position = Vector2(493, 444)
		reroll.size = Vector2(264, 46)
		reroll.add_theme_font_size_override("font_size", 21)
		for state in ["normal", "hover", "pressed"]:
			reroll.add_theme_stylebox_override(state, surface(CYAN, state != "normal"))
		trim(reroll, CYAN, true)
	_partner(main, 1 - primary)
	var hint: Label = main.level_overlay.get_node("NeonHint")
	hint.text = "좋은 선택이 더 강한 고양이를 만든다."
	hint.position.y = 500 if main.level_overlay.get_node("Reroll%d" % primary).visible else 456
	var controls: Label = main.level_overlay.get_node("NeonControls")
	controls.text = "A / D · W 확정    우클릭 · 상세 보기" if primary == 0 else "← / → · ↑ 확정    우클릭 · 상세 보기"
	if main.last_input_gamepad[primary]:
		controls.text = "LB / RB 이동 · A 확정 · B 취소"
	if main.selected_upgrade_indices[primary] >= 0:
		hint.text = "선택 완료 · 동료를 기다리는 중"
	# Compact health plaques leave the paused playfield open above the hand.
	for slot in 2:
		main.combat_hud.get_node("Carried%d" % slot).hide()
		main.combat_hud.get_node("P%dFrame" % (slot + 1)).size.y = 76 if slot == main.local_view_slot() else 68

static func _animate_card(card: Control, target: Vector2, angle: float, selected: bool, was_visible: bool) -> void:
	var destination := target + (Vector2.UP.rotated(angle) * CARD_HOVER_LIFT if selected else Vector2.ZERO)
	if was_visible and bool(card.get_meta("neon_shown", false)) and card.get_meta("neon_lifted_position", Vector2.INF) == destination:
		return
	var old_tween = card.get_meta("neon_tween") if card.has_meta("neon_tween") else null
	if old_tween is Tween and old_tween.is_valid():
		old_tween.kill()
	var first_show := not bool(card.get_meta("neon_shown", false)) or not was_visible
	if first_show:
		card.position = target
		card.rotation = angle
	card.scale = Vector2.ONE
	card.set_meta("neon_shown", true)
	card.set_meta("neon_rest_position", target)
	card.set_meta("neon_hover_lift", CARD_HOVER_LIFT)
	# Keep the fan angle and move along the card's own vertical axis. This is
	# equivalent to lifting an inner HTML card inside its rotated slot.
	var lifted_target := target
	if selected:
		lifted_target += Vector2.UP.rotated(angle) * CARD_HOVER_LIFT
	card.set_meta("neon_lifted_position", lifted_target)
	var tween := card.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", lifted_target, CARD_HOVER_TIME)
	tween.tween_property(card, "rotation", angle, CARD_HOVER_TIME)
	card.set_meta("neon_tween", tween)


static func _card(main: Node, card: Label, slot: int, option: Dictionary, selected: bool, width: float, height: float) -> void:
	var kind := String(option["id"])
	var tech := kind == "choose_tech"
	# Card borders describe ownership. The partner's warm orange is reserved for
	# their own hand and summary, so rarity/category can never be mistaken for P2.
	var tint := CYAN if slot == main.local_view_slot() else VIOLET
	var style := surface(tint, selected)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 178 if tech else (214 if height > 330 else 190)
	style.content_margin_bottom = 56
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_font_size_override("font_size", 13 if tech else (16 if width > 190 else 14))
	card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	card.clip_text = true
	card.text = main._upgrade_preview(slot, option) if kind != "choose_tech" else UI.compact_growth_description(option)
	var category: Label = card.get_node("Category")
	category.position = Vector2(30, 12)
	category.size = Vector2(width - 60, 25)
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category.add_theme_font_size_override("font_size", 17 if width > 190 else 14)
	category.add_theme_color_override("font_color", tint.lightened(0.35))
	var icon: TextureRect = card.get_node("Icon")
	var art := 80.0 if tech else (106.0 if height > 330 else 86.0)
	icon.position = Vector2((width - art) * 0.5, 45)
	icon.size = Vector2.ONE * art
	var title: Label = card.get_node("CardTitle")
	title.position = Vector2(13, 123 if tech else (155 if height > 330 else 132))
	title.size = Vector2(width - 26, 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21 if width > 190 else 17)
	var scope: Label = card.get_node("Scope")
	scope.visible = false
	var fusion: TextureRect = card.get_node("FusionMark")
	fusion.position = Vector2(width - 45, 52)
	fusion.size = Vector2(32, 32)
	var badge: Label = card.get_node("Recommendation")
	var reason := String(option.get("recommendation_reason", "무난한 성장"))
	var against := bool(option.get("discouraged", false))
	badge.text = ("👎 " + String(option.get("discouragement_reason", reason))) if against else ("👍 " if bool(option.get("recommended", false)) else "— ") + reason
	badge.position = Vector2(10, height - 47)
	badge.size = Vector2(width - 20, 36)
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_stylebox_override("normal", surface(tint.darkened(0.3)))
	badge.add_theme_color_override("font_color", Color("ffafbd") if against else Color("71ffcd"))
	trim(card, tint, selected, false)

static func _install(main: Node) -> void:
	if main.level_overlay.has_node("PartnerChoice"): return
	var panel := Panel.new()
	panel.name = "PartnerChoice"
	panel.position = Vector2(968, -82)
	panel.size = Vector2(290, 146)
	panel.z_index = 12
	panel.add_theme_stylebox_override("panel", surface(VIOLET))
	main.level_overlay.add_child(panel)
	trim(panel, VIOLET)
	UI.label(panel, "", Rect2(15, 10, 260, 24), 15, VIOLET.lightened(0.4)).name = "Heading"
	UI.label(panel, "", Rect2(15, 35, 260, 20), 12, Color("77f7df")).name = "State"
	UI.icon(panel, null, Rect2(18, 59, 52, 52)).name = "Art"
	UI.label(panel, "", Rect2(80, 56, 195, 26), 15, INK).name = "Title"
	var detail := UI.label(panel, "", Rect2(80, 82, 195, 29), 11, Color("cad8f1"))
	detail.name = "Detail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var button := Button.new()
	button.text = "⌕  전체 능력치 · TAB"
	button.position = Vector2(46, 113)
	button.size = Vector2(198, 25)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", surface(VIOLET.darkened(0.4)))
	button.pressed.connect(func() -> void: main.ReviewUI.toggle_details(main))
	panel.add_child(button)
	for key in ["Heading", "State", "Title"]:
		panel.get_node(key).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := UI.label(main.level_overlay, "", Rect2(300, 500, 650, 24), 14, Color("9abfe0"))
	hint.name = "NeonHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var controls := UI.label(main.level_overlay, "", Rect2(825, 518, 425, 24), 12, Color("b7d8ed"))
	controls.name = "NeonControls"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

static func _partner(main: Node, slot: int) -> void:
	var panel: Panel = main.level_overlay.get_node("PartnerChoice")
	var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
	var selected: int = main.selected_upgrade_indices[slot]
	var index: int = selected if selected >= 0 else main.upgrade_cursors[slot]
	var character: String = main.players[slot].character_name
	panel.get_node("Heading").text = "%s의 선택 · %d장 중 1" % [character, choices.size()]
	panel.get_node("State").text = "✓ 선택 완료" if selected >= 0 else ("빌드 완성" if selected == -2 else "선택을 고민하는 중…")
	if choices.is_empty() or index < 0 or index >= choices.size():
		panel.get_node("Art").texture = null
		panel.get_node("Title").text = "성장 완료"
		panel.get_node("Detail").text = "남은 동료의 선택을 기다립니다."
		return
	var option: Dictionary = choices[index]
	var original: Label = main.level_card_labels[slot][index]
	panel.get_node("Art").texture = original.get_node("Icon").texture
	panel.get_node("Title").text = original.get_node("CardTitle").text
	var detail: String = main._upgrade_preview(slot, option)
	panel.get_node("Detail").text = detail.split("\n")[0]
	panel.tooltip_text = panel.get_node("Title").text + "\n" + detail
