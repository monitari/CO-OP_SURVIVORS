extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const Review := preload("res://scripts/ui/review_ui.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")


static func install(main: Node) -> void:
	Review.button(main.lobby_overlay, "혼자 + AI 동료   [B]", Rect2(432, 530, 320, 40),
		func() -> void: main._join_ai_companion()).name = "JoinCompanion"
	Review.button(main.lobby_overlay, "LAN 방 만들기   [H]", Rect2(244, 480, 220, 40),
		func() -> void: main.online.host_game()).name = "HostLan"
	var address := LineEdit.new()
	address.name = "LanAddress"
	address.text = "127.0.0.1"
	address.placeholder_text = "호스트 IP 주소"
	address.position = Vector2(476, 480)
	address.size = Vector2(220, 40)
	address.add_theme_stylebox_override("normal", Palette.button_surface())
	address.add_theme_stylebox_override("focus", Palette.button_surface("hover", Palette.GOLD, true))
	address.add_theme_color_override("font_color", Palette.INK)
	address.tooltip_text = "같은 네트워크에 있는 방장의 IP 주소를 입력하세요"
	address.add_theme_font_size_override("font_size", 15)
	main.lobby_overlay.add_child(address)
	Review.button(main.lobby_overlay, "참가   [J]", Rect2(708, 480, 148, 40),
		func() -> void: main.online.join_game(address.text)).name = "JoinLan"
	var status := UI.label(main.lobby_overlay, "", Rect2(244, 578, 612, 18), 13, Palette.MUTED)
	main.lobby_overlay.get_node("JoinCompanion").add_theme_stylebox_override("normal", Palette.button_surface("normal", Palette.GOLD, true))
	status.name = "NetworkStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Puts the authored rectangles back before a refresh recomputes the dimming,
## so nothing accumulates across repeated refreshes.
static func restore(main: Node) -> void:
	for cards: Array in main.level_card_labels:
		for card: Label in cards:
			card.modulate = Color.WHITE
			card.mouse_filter = Control.MOUSE_FILTER_STOP

	for slot in 2:
		var reroll: Control = main.level_overlay.get_node_or_null("Reroll%d" % slot)
		# Reset client layout when a later run uses local multiplayer.
		if reroll != null:
			reroll.position.x = main.LEVEL_HALF_X[slot] + 232


## Both survivors' fans are drawn at once — a player can see what their partner
## is pointing at before either commits, which is the negotiation the mode is
## about. Only one of them has the controls at any moment, so the side whose turn
## it is not is dimmed rather than taken away: hiding it meant the pair chose
## blind, one after the other, with the screen changing shape between them.
const WAITING_TINT := Color(0.90, 0.90, 0.90, 1.0)


static func refresh(main: Node) -> void:
	var focus: int = main.focused_growth_slot()
	for slot in 2:
		for card: Label in main.level_card_labels[slot]:
			card.modulate *= Color.WHITE if slot == focus else WAITING_TINT

	if main.ai_companion or main.online.is_online():
		var local: int = main.local_view_slot()
		for slot in 2:
			var own := slot == local
			var picked: int = main.selected_upgrade_indices[slot]
			var shown: int = picked if picked >= 0 else main.upgrade_cursors[slot]
			for index in main.level_card_labels[slot].size():
				var card: Label = main.level_card_labels[slot][index]
				if own:
					card.mouse_filter = Control.MOUSE_FILTER_STOP
					var count: int = (main.p1_choices if slot == 0 else main.p2_choices).size()
					var spread := minf(176.0, 850.0 / maxf(1.0, count - 1.0))
					card.position.x = 640.0 + (index - (count - 1) * 0.5) * spread - card.size.x * 0.5
				else:
					card.visible = card.visible and index == shown
					card.pivot_offset = Vector2.ZERO
					card.rotation = 0.0
					card.position = Vector2(1060, -120)
					card.mouse_filter = Control.MOUSE_FILTER_IGNORE
					card.scale = Vector2.ONE * 0.48
			var reroll: Control = main.level_overlay.get_node_or_null("Reroll%d" % slot)
			if reroll != null:
				reroll.visible = own and reroll.visible
				if own:
					reroll.position.x = 552
	preload("res://scripts/ui/neon_growth_ui.gd").refresh(main)


static func lan_address(main: Node) -> String:
	var input := main.lobby_overlay.get_node_or_null("LanAddress") as LineEdit
	return input.text if input != null else "127.0.0.1"
