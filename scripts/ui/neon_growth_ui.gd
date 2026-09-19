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
## Overlay-local x the growth fan is centred on.
const FAN_CENTER_X := 625.0
## The row of actions under the fan: 다시 뽑기 and 전체 능력치, side by side.
const ACTION_Y := 446.0
const ACTION_SIZE := Vector2(232, 42)
const DETAILS_SIZE := Vector2(196, 42)
const ACTION_GAP := 12.0

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
		for state in ["normal", "hover", "pressed"]:
			reroll.add_theme_stylebox_override(state, surface(CYAN, state != "normal"))
		trim(reroll, CYAN, true)
	_partner(main, 1 - primary)
	_place_actions(main, primary)
	var hint: Control = main.level_overlay.get_node("NeonHint")
	hint.text = "좋은 선택이 더 강한 고양이를 만든다"
	hint.color = Color("d9ecff")
	var controls: Label = main.level_overlay.get_node("NeonControls")
	controls.text = "A / D    W 확정    우클릭    상세 보기" if primary == 0 else "← / →    ↑ 확정    우클릭    상세 보기"
	if main.last_input_gamepad[primary]:
		controls.text = "LB / RB 이동    A 확정    B 취소"
	if main.selected_upgrade_indices[primary] >= 0:
		hint.text = "선택 완료  ·  동료를 기다리는 중"
		hint.color = Color("8ff5d2")
	# Compact health plaques leave the paused playfield open above the hand.
	for slot in 2:
		main.combat_hud.get_node("P%dFrame" % (slot + 1)).size.y = 76 if slot == main.local_view_slot() else 68


## The partner's hand: the same cards in the same fan, dealt small and
## see-through in the top-right corner. Only the card they have taken (or are
## pointing at) keeps its colour; the rest go grey, so the one thing to read
## from across the screen is which card it is.
const PARTNER_SCALE := 0.44
const PARTNER_ALPHA := 0.78
const PARTNER_FAN_X := 1120.0
## Overlay-local line the fan's cards stand on (the overlay sits at y=176).
const PARTNER_FAN_BASE := 140.0


static func _partner_card(card: Label, index: int, count: int, selected: bool, angle: float) -> void:
	var old_tween = card.get_meta("neon_tween") if card.has_meta("neon_tween") else null
	if old_tween is Tween and old_tween.is_valid():
		old_tween.kill()
	card.set_meta("neon_shown", false)
	var spread := 70.0 if count <= 3 else (56.0 if count == 4 else 44.0)
	var middle := (count - 1) * 0.5
	# The pivot is the card's bottom centre, so the fan stands on one line.
	card.position = Vector2(PARTNER_FAN_X + (index - middle) * spread, PARTNER_FAN_BASE) - card.pivot_offset
	card.rotation = angle
	card.scale = Vector2.ONE * PARTNER_SCALE
	card.z_index = 4 if selected else 2
	card.modulate = Color(0.94, 0.94, 0.94, PARTNER_ALPHA)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_saturation(card, 1.0 if selected else 0.0)


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
		"fusion": main._fusion_partner_for_option(slot, option).get("texture"),
		"fusion_name": String(main._fusion_partner_for_option(slot, option).get("name", "")),
		"tech": tech,
		"advice": "discouraged" if against else ("recommended" if bool(option.get("recommended", false)) else "neutral"),
		"reason": String(option.get("discouragement_reason", reason)) if against else reason,
	}

static func _install(main: Node) -> void:
	if main.level_overlay.has_node("PartnerChoice"): return
	# No box: a caption over the partner's small fan (see _partner_card) and the
	# details shortcut under it. The fan itself is the partner's real cards.
	var panel := Control.new()
	panel.name = "PartnerChoice"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(PARTNER_FAN_X - 150.0, -56)
	panel.size = Vector2(300, 234)
	panel.z_index = 12
	main.level_overlay.add_child(panel)
	for spec in [["Heading", 0, 20, 14, VIOLET.lightened(0.4)], ["State", 20, 18, 12, Color("77f7df")],
			["Title", 90, 24, 14, INK]]:
		var caption := UI.label(panel, "", Rect2(0, spec[1], 300, spec[2]), spec[3], spec[4])
		caption.name = spec[0]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.9))
		caption.add_theme_constant_override("outline_size", 4)
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
		var style := surface(CYAN.darkened(0.35), state != "normal")
		style.bg_color = Color("0b1a30") if state == "normal" else Color("12294a")
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("b9d9f2"))
	button.add_theme_color_override("font_hover_color", INK)
	button.pressed.connect(func() -> void: main.ReviewUI.toggle_details(main))
	main.level_overlay.add_child(button)
	# The line that used to sit under the reroll button, on top of the XP bar,
	# now crowns the fan and bends with it (see arc_caption.gd).
	var hint := ArcCaption.new()
	hint.name = "NeonHint"
	hint.position = Vector2(FAN_CENTER_X - 330.0, 0)
	hint.size = Vector2(660, 60)
	hint.apex = Vector2(330, 38)
	hint.font_size = 21
	hint.accent = CYAN
	main.level_overlay.add_child(hint)
	var controls := UI.label(main.level_overlay, "", Rect2(825, 518, 425, 24), 12, Color("b7d8ed"))
	controls.name = "NeonControls"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

static func _partner(main: Node, slot: int) -> void:
	var panel: Control = main.level_overlay.get_node("PartnerChoice")
	var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
	var selected: int = main.selected_upgrade_indices[slot]
	var index: int = selected if selected >= 0 else main.upgrade_cursors[slot]
	var character: String = main.players[slot].character_name
	panel.get_node("Heading").text = "%s의 선택    %d장 중 1" % [character, choices.size()]
	panel.get_node("State").text = "✓ 선택 완료" if selected >= 0 else ("빌드 완성" if selected == -2 else "선택을 고민하는 중…")
	_fit_partner_panel(main, panel, slot)
	var title: Label = panel.get_node("Title")
	# The title is only spelled out when there is no fan to show it on.
	title.visible = choices.is_empty() or index < 0 or index >= choices.size()
	if title.visible:
		title.text = "성장 완료"
		return
	title.text = main.level_card_labels[slot][index].get_node("CardTitle").text


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


## Sizes the partner's caption panel to their fan, measured rather than guessed.
##
## The fan's lowest point is not a constant: a hand of five cards is dealt
## narrower and tilted harder than a hand of three, so the outer cards hang
## lower. The panel holds no art of its own, so it grows to reach the bottom of
## whatever fan is under it.
static func _fit_partner_panel(main: Node, panel: Control, slot: int) -> void:
	var lowest: float = PARTNER_FAN_BASE + (main.level_overlay as Control).position.y
	for card in main.level_card_labels[slot]:
		var partner_card := card as Control
		if partner_card == null or not partner_card.visible:
			continue
		lowest = maxf(lowest, partner_card.global_position.y + partner_card.size.y * partner_card.scale.y)
	panel.size.y = lowest - panel.global_position.y
