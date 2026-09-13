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
	# The neon hand owns all card transforms and partner presentation.
	preload("res://scripts/ui/neon_growth_ui.gd").refresh(main)


static func lan_address(main: Node) -> String:
	var input := main.lobby_overlay.get_node_or_null("LanAddress") as LineEdit
	return input.text if input != null else "127.0.0.1"
