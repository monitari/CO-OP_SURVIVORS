extends RefCounted


const Preview := preload("res://scripts/ui/survivor_preview.gd")
const CatTheme := preload("res://scripts/ui/cat_theme.gd")

static func transform(item: Control, origin: Vector2, target: Vector2, factor: float) -> void:
	if not item.has_meta("view_position"):
		item.set_meta("view_position", item.position)
	item.position = target + (Vector2(item.get_meta("view_position")) - origin) * factor
	item.scale = Vector2.ONE * factor


static func hud(main: Node) -> void:
	var local: int = main.local_view_slot()
	for slot in 2:
		var own := slot == local
		main.players[slot].display_name = main.player_label(slot)
		main.players[slot].display_index = main.display_player_number(slot)
		main.players[slot].queue_redraw()
		var bar: ProgressBar = main.p1_health_bar if slot == 0 else main.p2_health_bar
		var caption: Label = main.p1_health_text_label if slot == 0 else main.p2_health_text_label
		# Every client reads itself on the left and its partner on the right. Both
		# sides use identical geometry, mirrored around the screen centre.
		bar.position = Vector2(76, 27) if own else Vector2(884, 27)
		bar.size = Vector2(320, 22)
		bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END if own else ProgressBar.FILL_END_TO_BEGIN
		caption.position = bar.position
		caption.size = bar.size
		var portrait: Control = main.hud_portrait_icons[slot]
		portrait.position = Vector2(24, 16) if own else Vector2(1212, 16)
		portrait.size = Vector2(44, 44)
		portrait.scale = Vector2.ONE
		portrait.show()
		main.combat_hud.get_node("PlayerNumber%d" % slot).hide()
		main.combat_hud.get_node("PlayerIdentity%d" % slot).hide()
		var frame: Control = main.combat_hud.get_node("P%dFrame" % (slot + 1))
		frame.hide()
		# Equipment remains available in the details screen; moment-to-moment HUD
		# is deliberately reduced to portrait and health on both sides.
		var carried: Control = main.combat_hud.get_node("Carried%d" % slot)
		carried.hide()
		carried.set_meta("compact", true)


static func characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	var local: int = main.local_view_slot()
	var shared: bool = not main.ai_companion and not main.online.is_online()
	for slot in 2:
		var own := shared or slot == local
		var origin: Vector2 = Vector2(0 if slot == 0 else 575, 0)
		var target: Vector2 = origin if shared else Vector2(0 if own else 650, 0 if own else 48)
		var nodes: Array = [main.character_portrait_icons[slot], main.character_p1_label if slot == 0 else main.character_p2_label]
		for prefix in ["CharacterPanel", "CatNumber", "CatName", "CatWeapon", "CatRole", "CharacterPrevious", "CharacterNext", "CharacterConfirm"]:
			var item := screen.get_node_or_null("%s%d" % [prefix, slot])
			if item != null:
				nodes.append(item)
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			for prefix in ["CatStat", "CatStatIcon"]:
				var item: Control = screen.get_node("%s%d_%d" % [prefix, slot, stat])
				item.visible = own and (bool(screen.get_meta("show_details", false)) or stat < 4)
				nodes.append(item)
		for item: Control in nodes:
			item.set_meta("view_position", item.position)
			transform(item, origin, target, 1.0 if own else 0.78)
		var body: Control = main.character_p1_label if slot == 0 else main.character_p2_label
		body.visible = own
		screen.get_node("CatNumber%d" % slot).text = "%s" % main.player_label(slot)
		if not own:
			screen.get_node("CharacterPanel%d" % slot).size.y = 174
			screen.get_node("CharacterConfirm%d" % slot).position = Vector2(830, 290)
			for prefix in ["CharacterPrevious", "CharacterNext", "CatWeapon"]:
				screen.get_node("%s%d" % [prefix, slot]).hide()
		else:
			screen.get_node("CharacterPanel%d" % slot).size.y = 332
			for prefix in ["CharacterPrevious", "CharacterNext", "CatWeapon"]:
				screen.get_node("%s%d" % [prefix, slot]).show()
	var preview := screen.get_node_or_null("SurvivorPreview")
	if preview == null:
		preview = Preview.new()
		preview.name = "SurvivorPreview"
		preview.position = Vector2(680, 340)
		preview.size = Vector2(430, 195)
		screen.add_child(preview)
	preview.visible = not shared
	var character: Dictionary = main.character_catalog[main.selected_character_indices[local]]
	preview.set_character(character, main._build_weapon_state(character))
	screen.get_node("ControlFooter").text = "A / D 또는 패드 좌우    선택    W / 패드 A    준비    ESC    뒤로" if not shared else "나 A / D    W 준비     동료 ← / →    ↑ 준비     ESC 뒤로"

static func restore_characters(main: Node) -> void:
	for item in main.character_overlay.get_children():
		if item is Control and item.has_meta("view_position"):
			item.position = item.get_meta("view_position")
			item.scale = Vector2.ONE

static func details(main: Node) -> void:
	var shared: bool = not main.ai_companion and not main.online.is_online()
	for slot in 2:
		var own: bool = shared or slot == main.local_view_slot()
		for prefix in ["DetailHeader", "Offense", "Survival", "Coop", "Utility", "Build"]:
			var item: Control = main.details_overlay.get_node("%s%d" % [prefix, slot])
			item.visible = own
			var origin := Vector2(slot * 576, 0)
			var target := origin if shared else Vector2(288 if own else 900, 0 if own else -32)
			transform(item, origin, target, 1.0 if own else 0.42)
	var summary := main.details_overlay.get_node_or_null("PartnerSummary") as Label
	if summary == null:
		summary = Label.new()
		summary.name = "PartnerSummary"
		summary.position = Vector2(900, 75)
		summary.size = Vector2(250, 84)
		summary.add_theme_font_size_override("font_size", 14)
		summary.add_theme_color_override("font_color", Color("c8c3df"))
		main.details_overlay.add_child(summary)
	summary.visible = not shared
	if not shared:
		var partner: ChainPlayer = main.players[1 - main.local_view_slot()]
		summary.text = "동료    %s\n체력 %.0f / %.0f\n위력 %.0f%%    방어 %.1f" % [partner.character_name, partner.health, partner.max_health, partner.might * 100.0, partner.armor]
