extends RefCounted
const UI := preload("res://scripts/ui/editorial_ui.gd")
const Review := preload("res://scripts/ui/review_ui.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")


static func install(main: Node) -> void:
	# AI/local are selected one screen earlier. Keeping an AI action in the LAN
	# room made this look like another way to fill an empty slot.
	var host_section := UI.plate(main.lobby_overlay, Rect2(50, 478, 534, 94),
		Palette.CARD.lerp(Palette.P1, 0.045))
	host_section.name = "HostLanSection"
	UI.label(host_section, "LAN 방 만들기", Rect2(16, 8, 196, 26),
		Palette.TYPE_BODY, Palette.P1)
	UI.label(host_section, "이 PC에서 방을 열고 친구를 기다립니다", Rect2(16, 34, 298, 42),
		Palette.TYPE_CAPTION, Palette.MUTED)
	var host := Review.button(host_section, "LAN 방 만들기   [H]", Rect2(318, 18, 200, 58),
		func() -> void: main.online.host_game())
	host.name = "HostLan"
	_style_lan_button(host, Palette.P1)

	var join_section := UI.plate(main.lobby_overlay, Rect2(650, 478, 534, 94),
		Palette.CARD.lerp(Palette.P2, 0.045))
	join_section.name = "JoinLanSection"
	UI.label(join_section, "LAN 참가", Rect2(16, 8, 180, 26),
		Palette.TYPE_BODY, Palette.P2)
	var address := LineEdit.new()
	address.name = "LanAddress"
	address.placeholder_text = "호스트 IP 입력"
	address.position = Vector2(16, 42)
	address.size = Vector2(292, 36)
	address.add_theme_stylebox_override("normal", Palette.button_surface())
	address.add_theme_stylebox_override("focus", Palette.button_surface("hover", Palette.P2, true))
	address.add_theme_color_override("font_color", Palette.INK)
	address.add_theme_color_override("font_placeholder_color", Color(Palette.MUTED, 0.78))
	address.tooltip_text = "같은 네트워크에 있는 방장의 IP 주소를 입력하세요"
	address.add_theme_font_size_override("font_size", 15)
	join_section.add_child(address)
	var join := Review.button(join_section, "LAN 참가   [J]", Rect2(320, 18, 198, 58),
		func() -> void: main.online.join_game(address.text))
	join.name = "JoinLan"
	_style_lan_button(join, Palette.P2)

	var status := UI.label(main.lobby_overlay, "", Rect2(244, 574, 696, 20), 13, Palette.MUTED)
	status.name = "NetworkStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var leave := Review.button(main.lobby_overlay, "나가기", Rect2(1052, 14, 116, 36),
		func() -> void: main._set_lobby_exit_confirm(true))
	leave.name = "LobbyExit"
	_install_exit_confirm(main)


static func _style_lan_button(button: Button, accent: Color) -> void:
	button.add_theme_stylebox_override("normal", Palette.button_surface("normal", accent, true))
	button.add_theme_stylebox_override("hover", Palette.button_surface("hover", accent, true))
	button.add_theme_stylebox_override("pressed", Palette.button_surface("pressed", accent, true))
	button.add_theme_color_override("font_color", Palette.CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


static func _install_exit_confirm(main: Node) -> void:
	var layer := Control.new()
	layer.name = "LobbyExitConfirm"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 50
	layer.hide()
	main.lobby_overlay.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.055, 0.80)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var panel := UI.plate(layer, Rect2(368, 198, 448, 232), Palette.PANEL)
	panel.name = "ExitPanel"
	UI.label(panel, "LAN 방에서 나갈까요?", Rect2(24, 24, 400, 40),
		Palette.TYPE_HEADING, Palette.CREAM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var copy := UI.label(panel,
		"연결과 현재 참가 상태를 정리하고\n메인 메뉴로 돌아갑니다.",
		Rect2(32, 76, 384, 56), Palette.TYPE_BODY, Palette.MUTED)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Review.button(panel, "방에 머무르기", Rect2(24, 156, 192, 48), func() -> void:
		main._set_lobby_exit_confirm(false)).name = "ExitCancel"
	var accept := Review.button(panel, "LAN 방 나가기", Rect2(232, 156, 192, 48), func() -> void:
		main._confirm_lobby_exit())
	accept.name = "ExitAccept"
	_style_lan_button(accept, Palette.P2)


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
	var input := main.lobby_overlay.find_child("LanAddress", true, false) as LineEdit
	return input.text if input != null else ""
