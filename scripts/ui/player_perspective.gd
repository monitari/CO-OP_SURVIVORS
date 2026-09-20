extends RefCounted


const CatTheme := preload("res://scripts/ui/cat_theme.gd")
const UI := preload("res://scripts/ui/editorial_ui.gd")

static func hud(main: Node) -> void:
	var local: int = main.local_view_slot()
	# Everything below is layout, and layout only changes when whose view this is
	# changes — the local slot, or a player's relative label after an online
	# role swap. It ran every physics tick regardless, repositioning and
	# resizing both bars, both captions and both portraits and forcing a redraw of
	# both survivors, sixty times a second, to put them exactly where they were.
	var key := "%d|%s|%s" % [local, main.player_label(0), main.player_label(1)]
	if main.combat_hud.get_meta("perspective_key", "") == key:
		return
	main.combat_hud.set_meta("perspective_key", key)
	for slot in 2:
		var own := slot == local
		main.players[slot].display_name = main.player_label(slot)
		main.players[slot].display_index = main.display_player_number(slot)
		main.players[slot].queue_redraw()
		var bar: ProgressBar = main.p1_health_bar if slot == 0 else main.p2_health_bar
		var caption: Label = main.p1_health_text_label if slot == 0 else main.p2_health_text_label
		# Every client reads itself on the left and its partner on the right. Both
		# sides use identical geometry, mirrored around the screen centre.
		bar.position = Vector2(UI.PLAYER_BAR_LEFT, UI.PLAYER_ROW_TOP) if own else Vector2(UI.PLAYER_BAR_RIGHT, UI.PLAYER_ROW_TOP)
		bar.size = Vector2(UI.PLAYER_BAR_WIDTH, 24)
		bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END if own else ProgressBar.FILL_END_TO_BEGIN
		caption.position = bar.position
		caption.size = bar.size
		var portrait: Control = main.hud_portrait_icons[slot]
		portrait.position = Vector2(20, 14) if own else Vector2(1208, 14)
		portrait.size = Vector2(52, 52)
		portrait.scale = Vector2.ONE
		portrait.show()
		var number: Label = main.combat_hud.get_node("PlayerNumber%d" % slot)
		var identity: Label = main.combat_hud.get_node("PlayerIdentity%d" % slot)
		var level: Label = main.combat_hud.get_node("PlayerLevel%d" % slot)
		if own:
			identity.position = Vector2(UI.PLAYER_IDENTITY_LEFT, UI.PLAYER_ROW_TOP)
			identity.size = Vector2(80, 24)
			identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			level.position = Vector2(UI.PLAYER_LEVEL_LEFT, UI.PLAYER_ROW_TOP)
			number.position = Vector2(UI.PLAYER_ROLE_LEFT, UI.PLAYER_ROW_TOP)
			number.size = Vector2(28, 24)
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			identity.position = Vector2(UI.PLAYER_IDENTITY_RIGHT, UI.PLAYER_ROW_TOP)
			identity.size = Vector2(80, 24)
			identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			level.position = Vector2(UI.PLAYER_LEVEL_RIGHT, UI.PLAYER_ROW_TOP)
			number.position = Vector2(UI.PLAYER_ROLE_RIGHT, UI.PLAYER_ROW_TOP)
			number.size = Vector2(28, 24)
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number.show()
		identity.show()
		level.show()
		var ring: Control = main.combat_hud.get_node("PlayerPortraitRing%d" % slot)
		ring.position = Vector2(14, 8) if own else Vector2(1202, 8)
		ring.show()
		var frame: Control = main.combat_hud.get_node("P%dFrame" % (slot + 1))
		frame.position = Vector2(10, 8) if own else Vector2(982, 8)
		frame.hide()
		# Carried equipment forms a compact row below each player's combined
		# identity, contribution and health line.
		var carried: Control = main.combat_hud.get_node("Carried%d" % slot)
		carried.position = Vector2(90, 50) if own else Vector2(1190 - carried.size.x, 50)
		carried.set_meta("compact", false)
		UI.layout_carried(carried, not own)


static func characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	var detailed := bool(screen.get_meta("show_details", false))
	# Keep both builds readable in local, AI, and online play. Input ownership
	# is handled by the existing button permissions, independently of layout.
	for slot in 2:
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			for prefix in ["CatStatBed", "CatStat", "CatStatIcon"]:
				screen.get_node("%s%d_%d" % [prefix, slot, stat]).visible = detailed or stat < 4
		var body: Control = main.character_p1_label if slot == 0 else main.character_p2_label
		body.show()
		screen.get_node("CatNumber%d" % slot).text = "P%d  ·  %s" % [main.display_player_number(slot), main.player_label(slot)]
		screen.get_node("CharacterPanel%d" % slot).size.y = 376
		for prefix in ["CharacterPrevious", "CharacterNext", "CatWeapon"]:
			screen.get_node("%s%d" % [prefix, slot]).visible = prefix != "CatWeapon" or not detailed
	screen.get_node("ControlFooter").text = "A / D 또는 패드 좌우    선택    W / 패드 A    준비    ESC    뒤로" if main.ai_companion or main.online.is_online() else "나 A / D    W 준비     동료 ← / →    ↑ 준비     ESC 뒤로"

static func restore_characters(main: Node) -> void:
	for item in main.character_overlay.get_children():
		if item is Control and item.has_meta("view_position"):
			item.position = item.get_meta("view_position")
			item.scale = Vector2.ONE

## One sheet at a time, never the partner's beside it. With an AI partner or
## online that sheet is always your own; in local co-op both players are "me",
## so it opens on whoever is deciding and DetailSwap flips it.
static func details(main: Node) -> void:
	var shared: bool = not main.ai_companion and not main.online.is_online()
	var shown: int = int(main.details_overlay.get_meta("detail_slot", 0)) if shared else main.local_view_slot()
	for slot in 2:
		for prefix in ["DetailHeader", "Offense", "Survival", "Coop", "Utility", "Build"]:
			main.details_overlay.get_node("%s%d" % [prefix, slot]).visible = slot == shown
	main.details_overlay.get_node("DetailSwap").visible = shared
