extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const CardVisual := preload("res://scripts/ui/growth_card_visual.gd")
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const CYAN := CardVisual.CYAN
const VIOLET := CardVisual.PARTNER
const INK := CardVisual.INK
const CARD_HOVER_LIFT := 24.0
const CARD_HOVER_TIME := 0.18
const ArcCaption := preload("res://scripts/ui/arc_caption.gd")
const L := preload("res://scripts/systems/loc.gd")
## Overlay-local x the growth fan is centred on.
const FAN_CENTER_X := 625.0
## The row of actions under the fan: 다시 뽑기 and 전체 능력치, side by side.
const ACTION_Y := 446.0
const ACTION_SIZE := Vector2(232, 42)
const DETAILS_SIZE := Vector2(196, 42)
const ACTION_GAP := 12.0
## The partner's summary plaque, top right. It is anchored by its bottom edge
## and its right edge: the bottom is the line the fan's tallest card starts
## below, and the right is the overlay's own margin. Only the height moves, and
## it moves upward, so a longer caption can never push the plaque into the hand.
const PARTNER_RIGHT := 1256.0
const PARTNER_WIDTH := 290.0
const PARTNER_BOTTOM := 60.0
const PARTNER_PADDING := 10.0
const PARTNER_TEXT_X := 84.0

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
			card.visible = index < count
			if not card.visible:
				card.set_meta("neon_shown", false)
				continue
			var selected: bool = index == focus
			var width := 224.0 if count <= 3 else (208.0 if count == 4 else 182.0)
			var height := 348.0 if count <= 4 else 322.0
			var middle := (count - 1) * 0.5
			card.size = Vector2(width, height)
			card.pivot_offset = Vector2(width * 0.5, height)
			var target_rotation: float = (index - middle) / maxf(1.0, middle) * 0.11
			_card(main, card, slot, choices[index], selected, width, height)
			if not own:
				_partner_card(card, index, count, selected, target_rotation)
				continue
			var spread := 226.0 if count <= 3 else (220.0 if count == 4 else 190.0)
			var target_position := Vector2(FAN_CENTER_X + (index - middle) * spread - width * 0.5, 70 + absf(index - middle) * 5)
			if card.scale != Vector2.ONE:
				# Coming back from the partner's small fan: deal it in fresh.
				card.set_meta("neon_shown", false)
			_animate_card(card, target_position, target_rotation, selected, was_visible)
			card.z_index = 8 if selected else 3
			card.modulate = Color.WHITE if chosen < 0 or selected else Color("aeb8cb")
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			_set_saturation(card, 1.0)
		var reroll: Button = main.level_overlay.get_node("Reroll%d" % slot)
		reroll.visible = own and reroll.visible
		reroll.size = ACTION_SIZE
		reroll.add_theme_font_size_override("font_size", 18)
		var owner_accent := CYAN if slot == 0 else VIOLET
		for state in ["normal", "hover", "pressed"]:
			reroll.add_theme_stylebox_override(state, UI.Palette.button_surface(state, owner_accent, true))
		trim(reroll, owner_accent, false)
	_partner(main, 1 - primary)
	_place_actions(main, primary)
	# ArcCaption draws its own glyphs, so Godot's automatic caption translation
	# never reaches it — its line has to arrive already translated.
	var hint: Control = main.level_overlay.get_node("NeonHint")
	hint.text = L.f("%s의 성장 선택", L.t(main.players[primary].character_name))
	hint.color = Color("d9ecff")
	var controls: Label = main.level_overlay.get_node("NeonControls")
	controls.text = "A / D 이동    [W] 선택 확정    우클릭 상세" if primary == 0 else "← / → 이동    [↑] 선택 확정    우클릭 상세"
	if main.last_input_gamepad[primary]:
		controls.text = "LB / RB 이동    A 확정    B 취소"
	if main.selected_upgrade_indices[primary] >= 0:
		hint.text = L.t("선택 완료  ·  동료를 기다리는 중")
		hint.color = Color("8ff5d2")
	# Compact health plaques leave the paused playfield open above the hand.
	for slot in 2:
		main.combat_hud.get_node("P%dFrame" % (slot + 1)).size.y = 76 if slot == main.local_view_slot() else 68


## The partner's full hand used to be shrunk into the top-right corner. At 44%
## scale it was too small to read and overlapped the local player's last card.
## The real cards are now hidden and represented by one readable summary note.
static func _partner_card(card: Label, _index: int, _count: int, _selected: bool, _angle: float) -> void:
	var old_tween = card.get_meta("neon_tween") if card.has_meta("neon_tween") else null
	if old_tween is Tween and old_tween.is_valid():
		old_tween.kill()
	card.set_meta("neon_shown", false)
	card.hide()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE


static var _grey_shader: Shader


## Desaturates a whole card — frame, art and text — without repainting it.
static func _set_saturation(card: Control, amount: float) -> void:
	if amount >= 1.0:
		card.material = null
		return
	if _grey_shader == null:
		_grey_shader = Shader.new()
		_grey_shader.code = """shader_type canvas_item;
uniform float saturation = 0.0;
void fragment() {
	float grey = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(vec3(grey), COLOR.rgb, saturation);
}"""
	var grey := card.material as ShaderMaterial
	if grey == null:
		grey = ShaderMaterial.new()
		grey.shader = _grey_shader
		card.material = grey
	grey.set_shader_parameter("saturation", amount)
	for child in card.get_children():
		if child is CanvasItem:
			child.use_parent_material = true


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
	# Card borders describe ownership. The partner's warm orange is reserved for
	# their own hand and summary, so rarity/category can never be mistaken for P2.
	CardVisual.paint(card, card_model(main, slot, option), card_tint(main, slot), selected, width, height)


static func card_tint(main: Node, slot: int) -> Color:
	if slot < 0:
		return CardVisual.CHEST
	return CYAN if slot == main.local_view_slot() else VIOLET


## What a growth card says about `option`, for CardVisual.paint. The chest takes
## this before it applies a reward, because the preview is a before/after of the
## build the reward is about to change.
static func card_model(main: Node, slot: int, option: Dictionary) -> Dictionary:
	var tech := String(option["id"]) == "choose_tech"
	var against := bool(option.get("discouraged", false))
	var reason := String(option.get("recommendation_reason", "무난한 성장"))
	var fusion: Dictionary = main._fusion_partner_for_option(slot, option)
	var kind: String = {
		"choose_tech": "tech", "unlock_weapon": "new_weapon",
		"unlock_treasure": "new_treasure", "treasure_upgrade": "treasure",
	}.get(String(option["id"]), "weapon")
	return {
		"category": UI.growth_category(option),
		"kind": kind,
		"sections": main._card_sections(slot, option),
		"title": UI.growth_title(option),
		"body": UI.compact_growth_description(option) if tech else main._upgrade_preview(slot, option),
		"icon": Icons.upgrade(main._option_icon_id(slot, option), main._option_weapon_id(slot, option)),
		"fusion": fusion.get("texture"),
		"fusion_name": String(fusion.get("name", "")),
		"fusion_tier": main.Evolutions.REQUIRED_TREASURE_TIER,
		"tech": tech,
		"advice": "discouraged" if against else ("recommended" if bool(option.get("recommended", false)) else "neutral"),
		"reason": String(option.get("discouragement_reason", reason)) if against else reason,
	}

static func _install(main: Node) -> void:
	if main.level_overlay.has_node("PartnerChoice"): return
	var panel := UI.plate(main.level_overlay,
		Rect2(PARTNER_RIGHT - PARTNER_WIDTH, PARTNER_BOTTOM - 106.0, PARTNER_WIDTH, 106.0),
		UI.Palette.PAPER_LIGHT)
	panel.name = "PartnerChoice"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 12
	trim(panel, VIOLET, false, true)
	var partner_icon := UI.icon(panel, null, Rect2(12, 22, 62, 62))
	partner_icon.name = "PartnerIcon"
	# The four lines used to be placed at hand-picked y values 17px apart while a
	# Label's own minimum height at these font sizes is 22 — so every line sat on
	# top of the one above it, and the plaque read as one smudge (see the capture
	# in tests/localization_fit_test.gd). Stacking them lets each line claim the
	# height its font actually needs, in Korean and in English alike.
	var column := VBoxContainer.new()
	column.name = "Captions"
	column.position = Vector2(PARTNER_TEXT_X, PARTNER_PADDING)
	column.size = Vector2(PARTNER_WIDTH - PARTNER_TEXT_X - PARTNER_PADDING, 0)
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	for spec in [["Heading", 12, UI.Palette.P2_INK], ["State", 11, UI.Palette.MUTED],
			["Title", 15, UI.Palette.INK], ["Summary", 11, UI.Palette.MUTED]]:
		var caption := Label.new()
		caption.name = spec[0]
		caption.add_theme_font_size_override("font_size", spec[1])
		caption.add_theme_color_override("font_color", spec[2])
		caption.clip_text = true
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		column.add_child(caption)
	# The whole-build view sits beside 다시 뽑기 rather than under the partner's
	# fan: both are things to do *about* this hand before choosing from it, and a
	# player looking for either looks under their own cards, not at the corner
	# where the partner's miniatures are.
	var button := Button.new()
	button.name = "Details"
	button.text = "⌕  전체 능력치   TAB"
	button.size = DETAILS_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, UI.Palette.button_surface(state, UI.Palette.GOLD))
	button.add_theme_color_override("font_color", UI.Palette.INK)
	button.add_theme_color_override("font_hover_color", UI.Palette.INK)
	button.add_theme_color_override("font_pressed_color", UI.Palette.INK)
	button.pressed.connect(func() -> void: main.ReviewUI.toggle_details(main))
	main.level_overlay.add_child(button)
	# The line that used to sit under the reroll button, on top of the XP bar,
	# now crowns the fan and bends with it (see arc_caption.gd).
	var hint := ArcCaption.new()
	hint.name = "NeonHint"
	hint.position = Vector2(FAN_CENTER_X - 330.0, 0)
	hint.size = Vector2(660, 60)
	# 26, not 38: the centre card's category tape overhangs its top edge by ten
	# pixels and sits directly under the middle of the arc, which is the lowest
	# point of the caption. At 38 the two touched.
	hint.apex = Vector2(330, 26)
	hint.font_size = 21
	hint.accent = CYAN
	main.level_overlay.add_child(hint)
	var controls := UI.label(main.level_overlay, "", Rect2(760, 516, 490, 26), 14, Color("d9ecff"))
	controls.name = "NeonControls"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

static func _partner(main: Node, slot: int) -> void:
	var panel: Control = main.level_overlay.get_node("PartnerChoice")
	var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
	var selected: int = main.selected_upgrade_indices[slot]
	var index: int = selected if selected >= 0 else main.upgrade_cursors[slot]
	var character: String = L.t(main.players[slot].character_name)
	var column: VBoxContainer = panel.get_node("Captions")
	var title: Label = column.get_node("Title")
	var summary: Label = column.get_node("Summary")
	var partner_icon: TextureRect = panel.get_node("PartnerIcon")
	var room := PARTNER_WIDTH - PARTNER_TEXT_X - PARTNER_PADDING
	UI.fit_text(column.get_node("Heading"),
		L.f("동료 %s    %d장 중 선택", [character, choices.size()]), 12, 9, room)
	UI.fit_text(column.get_node("State"),
		L.t("✓ 선택 완료") if selected >= 0
		else (L.t("빌드 완성") if selected == -2 else L.t("선택을 고민하는 중…")), 11, 9, room)
	if choices.is_empty() or index < 0 or index >= choices.size():
		UI.fit_text(title, L.t("성장 완료"), 15, 11, room)
		UI.fit_text(summary, L.t("다음 전투를 준비합니다"), 11, 9, room)
		partner_icon.texture = null
		partner_icon.hide()
		_size_partner(panel, column, partner_icon)
		return
	var option: Dictionary = choices[index]
	UI.fit_text(title, UI.growth_title(option), 15, 11, room)
	UI.fit_text(summary,
		String(option.get("recommendation_reason", UI.growth_category(option))).split("   ")[0], 11, 9, room)
	partner_icon.texture = Icons.upgrade(main._option_icon_id(slot, option), main._option_weapon_id(slot, option))
	partner_icon.visible = partner_icon.texture != null
	_size_partner(panel, column, partner_icon)


## Grows the plaque upward around whatever the four lines need. The bottom edge
## is fixed because that is the edge the hand is measured against.
static func _size_partner(panel: Control, column: VBoxContainer, partner_icon: TextureRect) -> void:
	var content := column.get_combined_minimum_size().y + PARTNER_PADDING * 2.0
	panel.size.y = maxf(96.0, content)
	panel.position.y = PARTNER_BOTTOM - panel.size.y
	column.size.y = column.get_combined_minimum_size().y
	partner_icon.position.y = (panel.size.y - partner_icon.size.y) * 0.5


## The row under the fan: 다시 뽑기 and 전체 능력치, centred together, or the
## details button alone when there is nothing left to reroll.
static func _place_actions(main: Node, primary: int) -> void:
	var details: Button = main.level_overlay.get_node("Details")
	var reroll: Button = main.level_overlay.get_node("Reroll%d" % primary)
	var row := DETAILS_SIZE.x + ((ACTION_SIZE.x + ACTION_GAP) if reroll.visible else 0.0)
	var left := FAN_CENTER_X - row * 0.5
	if reroll.visible:
		reroll.position = Vector2(left, ACTION_Y)
		left += ACTION_SIZE.x + ACTION_GAP
	details.position = Vector2(left, ACTION_Y)
	details.visible = true
