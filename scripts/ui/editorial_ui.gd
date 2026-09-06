extends RefCounted
## Layout and visual hierarchy only. Input and build calculations remain in main.
const Palette := preload("res://scripts/ui/cat_theme.gd")
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const LobbyAmbience := preload("res://scripts/ui/lobby_ambience.gd")
const TitleLogo := preload("res://assets/ui/title/moonroof_title.png")
const PLAYSTYLE := {
	"homing": "유도 별탄 · 단일 적 추적", "lightning": "연쇄 번개 · 적 사이로 전이",
	"flame": "불꽃 투사체 · 전방 화력", "frost": "빙결 오라 · 상시 둔화 피해",
	"scythe": "월도 낫 · 부채꼴 연속 베기", "chain": "사슬 파동 · 결속 공격",
	"orbit": "회전 별 · 3.8초 연타", "lance": "관통 광선 · 직선 공격",
	"mine": "결계 지뢰 · 밟을 때까지 유지", "gravity": "중력 붕괴 · 부드러운 흡인",
}



static func label(parent: Node, text: String, rect: Rect2, font_size := 18, ink: Color = Palette.INK) -> Label:
	var item := Label.new()
	item.text = text
	place(item, rect, font_size, ink)
	parent.add_child(item)
	return item


static func place(item: Label, rect: Rect2, font_size: int, ink: Color = Palette.INK) -> void:
	item.position = rect.position
	item.size = rect.size
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", ink)
	item.clip_text = true
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func plate(parent: Node, rect: Rect2, tint: Color = Palette.CARD) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", Palette.surface(tint, 14))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


static func icon(parent: Node, texture: Texture2D, rect: Rect2) -> TextureRect:
	var item := TextureRect.new()
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.texture = texture
	item.position = rect.position
	item.size = rect.size
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item


static func apply(main: Node) -> void:
	for screen in [main.lobby_overlay, main.character_overlay, main.level_overlay,
		main.resonance_overlay, main.pause_overlay, main.result_overlay]:
		_reink(screen)
	_lobby(main)
	_characters(main)
	_growth(main)
	_results(main)
	_pause(main)
	_hud(main)
	place(main.resonance_title, Rect2(32, 20, 840, 42), 28)
	main.resonance_title.text = "함께 쓰는 필살기"
	main.resonance_status.add_theme_color_override("font_color", Palette.MUTED)
	for card: Label in main.resonance_cards:
		card.add_theme_color_override("font_color", Palette.INK)
		var pips: Label = card.get_node("Pips")
		pips.add_theme_color_override("font_color", Palette.CREAM)
	main.pause_label.add_theme_color_override("font_color", Palette.INK)
	main.result_label.add_theme_color_override("font_color", Palette.INK)
	main.team_stats_label.add_theme_stylebox_override("normal", Palette.surface(Palette.PANEL, 10))
	main.team_stats_label.add_theme_color_override("font_color", Palette.MUTED)
	for slot in 2:
		for row in [main.level_weapon_icons[slot], main.level_treasure_icons[slot]]:
			for item: TextureRect in row:
				item.get_node("Tier").add_theme_color_override("font_color", Palette.CREAM)


static func _reink(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", Palette.INK)
	for child in node.get_children():
		_reink(child)


static func _lobby(main: Node) -> void:
	var screen: Control = main.lobby_overlay
	# Replace only the decorative captions/portraits, keeping live join controls.
	for child in screen.get_children():
		if child not in [main.lobby_title, main.lobby_p1_label, main.lobby_p2_label]:
			screen.remove_child(child)
			child.queue_free()
	main.lobby_title.text = ""
	main.lobby_title.visible = false
	var ambience = LobbyAmbience.new()
	ambience.name = "LobbyAmbience"
	ambience.setup(TitleLogo, Icons.survivor("lyra"), Icons.survivor("volta"))
	screen.add_child(ambience)
	screen.move_child(ambience, 0)
	var prompt := label(screen, "두 고양이가 모이면 바로 출발", Rect2(300, 334, 500, 28), 18, Palette.MUTED)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in 2:
		var item: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		place(item, Rect2(48 + slot * 510, 382, 494, 142), 21, Palette.P1 if slot == 0 else Palette.P2)
		item.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
		var style := item.get_theme_stylebox("normal") as StyleBoxFlat
		style.set_content_margin_all(22)
	var hint := label(screen, "ESC / START  참가 취소", Rect2(325, 550, 450, 24), 14, Palette.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func _characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	# Existing large backgrounds are replaced with aligned dossier cards.
	for child in screen.get_children():
		if child is Panel or (child is Label and child.text in ["P1", "P2"]):
			screen.remove_child(child)
			child.queue_free()
	place(main.character_title, Rect2(32, 20, 700, 40), 28)
	main.character_title.text = "오늘 밤의 수호대"
	place(main.character_roster_label, Rect2(790, 26, 314, 24), 14, Palette.MUTED)
	main.character_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in main.character_catalog.size():
		var step: float = 1080.0 / main.character_catalog.size()
		var tile := plate(screen, Rect2(32 + index * step, 76, step - 8, 82))
		tile.name = "Roster%d" % index
		icon(tile, Icons.survivor(String(main.character_catalog[index]["id"])), Rect2((step - 62) * 0.5, 3, 54, 54))
		var name_label := label(tile, String(main.character_catalog[index]["name"]), Rect2(4, 55, step - 16, 23), 13)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in 2:
		var x := 32.0 + slot * 548.0
		var bed := plate(screen, Rect2(x, 178, 528, 402))
		screen.move_child(bed, 0)
		var portrait: TextureRect = main.character_portrait_icons[slot]
		portrait.position = Vector2(x + 22, 204)
		portrait.size = Vector2(104, 104)
		label(screen, "P%d" % (slot + 1), Rect2(x + 146, 194, 50, 25), 14, Palette.P1 if slot == 0 else Palette.P2)
		var heading := label(screen, "", Rect2(x + 146, 219, 354, 38), 28)
		heading.name = "CatName%d" % slot
		var weapon_art := icon(screen, null, Rect2(x + 22, 312, 46, 46))
		weapon_art.name = "CatWeapon%d" % slot
		var role := label(screen, "", Rect2(x + 146, 261, 354, 48), 15, Palette.MUTED)
		role.name = "CatRole%d" % slot
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Eight meaningful axes in a compact 4x2 grid. Weapon art anchors the first
		# cell, so loadout identity is visible before anyone reads a description.
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var entry: Dictionary = CharacterCatalog.DISPLAYED_STATS[stat]
			var column := stat % 4
			var row := stat / 4
			icon(screen, Icons.upgrade(String(entry["icon"])),
				Rect2(x + 82 + column * 108, 312 + row * 39, 25, 25))
			var value := label(screen, "", Rect2(x + 109 + column * 108, 309 + row * 39, 80, 32), 13)
			value.name = "CatStat%d_%d" % [slot, stat]
		var body: Label = main.character_p1_label if slot == 0 else main.character_p2_label
		place(body, Rect2(x + 24, 398, 480, 150), 15)
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	place(main.character_synergy_label, Rect2(32, 593, 1076, 42), 15, Palette.MUTED)


static func refresh_characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	main.character_roster_label.text = "클릭 P1 · 우클릭 P2"
	for slot in 2:
		var cat: Dictionary = main.character_catalog[main.selected_character_indices[slot]]
		screen.get_node("CatName%d" % slot).text = String(cat["name"])
		screen.get_node("CatWeapon%d" % slot).texture = Icons.weapon(String(cat["weapon_id"]))
		screen.get_node("CatRole%d" % slot).text = "%s\n조작 난이도 %s" % [PLAYSTYLE.get(String(cat["weapon_id"]), cat["title"]), CharacterCatalog.difficulty_stars(cat)]
		screen.get_node("CatRole%d" % slot).tooltip_text = cat["description"]
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var entry: Dictionary = CharacterCatalog.DISPLAYED_STATS[stat]
			screen.get_node("CatStat%d_%d" % [slot, stat]).text = CharacterCatalog.stat_text(cat, String(entry["field"]))
	for index in main.character_catalog.size():
		var tile: Panel = screen.get_node("Roster%d" % index)
		var style := tile.get_theme_stylebox("panel") as StyleBoxFlat
		var p1: bool = main.selected_character_indices[0] == index
		var p2: bool = main.selected_character_indices[1] == index
		style.border_color = Palette.P1 if p1 else (Palette.P2 if p2 else Palette.OUTLINE)
		style.set_border_width_all(3 if p1 or p2 else 1)
		style.bg_color = Color("e0ebe2") if p1 else (Color("e9e1ee") if p2 else Palette.CARD)


static func _growth(main: Node) -> void:
	var screen: Control = main.level_overlay
	place(main.level_title, Rect2(24, 16, 860, 42), 28)
	for slot in 2:
		var x := 8.0 + slot * 616.0
		var panel := plate(screen, Rect2(x - 4, 58, 608, 418), Palette.P1 if slot == 0 else Palette.P2)
		panel.name = "GrowthPanel%d" % slot
		panel.modulate = Color(1.0, 1.0, 1.0, 0.18)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.move_child(panel, 0)
		var heading := label(screen, "", Rect2(x + 8, 70, 590, 26), 16, Palette.P1 if slot == 0 else Palette.P2)
		heading.name = "GrowthName%d" % slot
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for card: Label in main.level_card_labels[slot]:
			card.add_theme_color_override("font_color", Palette.INK)
			card.add_theme_font_size_override("font_size", 16)
			card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			var style := card.get_theme_stylebox("normal") as StyleBoxFlat
			style.set_corner_radius_all(12)
			style.content_margin_left = 16
			style.content_margin_right = 16
			style.content_margin_top = 142
			var art: TextureRect = card.get_node("Icon")
			art.position = Vector2(14, 17)
			var category := label(card, "", Rect2(92, 24, 88, 42), 13, Palette.MUTED)
			category.name = "Category"
			category.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var title := label(card, "", Rect2(16, 86, 164, 50), 16)
			title.name = "CardTitle"
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_theme_font_size_override("font_size", 14)
			var badge: Label = card.get_node("Recommendation")
			badge.add_theme_color_override("font_color", Palette.P1)
			badge.add_theme_stylebox_override("normal", Palette.surface(Color("dfebda"), 8))
			badge.add_theme_font_size_override("font_size", 14)
		var footer: Label = main.p1_level_footer if slot == 0 else main.p2_level_footer
		footer.add_theme_color_override("font_color", Palette.MUTED)
		var stats := label(screen, "", Rect2(x + 268, 372, 330, 44), 12, Palette.MUTED)
		stats.name = "BuildStats%d" % slot
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	place(main.team_stats_label, Rect2(24, 430, 1192, 26), 13, Palette.MUTED)
	main.team_stats_label.visible = false


static func refresh_growth(main: Node, slot: int) -> void:
	var screen: Control = main.level_overlay
	screen.get_node("GrowthName%d" % slot).text = "P%d  %s" % [slot + 1, main.selected_characters[slot]["name"]]
	var player: Node = main.players[slot]
	screen.get_node("BuildStats%d" % slot).text = "공격 %d%%   범위 %d%%   이속 %d\n방어 %.0f   회복 %.1f/s" % [
		int(player.might * 100), int(player.area * 100), int(player.move_speed), player.armor, player.recovery]
	var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
	for index in choices.size():
		var option: Dictionary = choices[index]
		var card: Label = main.level_card_labels[slot][index]
		var kind := String(option["id"])
		card.get_node("Category").text = "새 보물" if kind == "unlock_treasure" else ("새 무기" if kind == "unlock_weapon" else ("합성" if kind == "evolve_weapon" else "강화"))
		card.get_node("CardTitle").text = String(option["title"]).replace("새 보물: ", "").replace("신규 기술: ", "").replace("합성: ", "")
		card.text = String(option["description"])
		card.text = card.text.replace(", ", "\n").replace("출혈 시간", "구조 시간").replace("내구도 소모", "내구 소모")
		if kind == "evolve_weapon":
			card.text = short_evolution(String(option["evolution"]["weapon_id"]))
		card.tooltip_text = String(option["title"]) + "\n" + String(option["description"])
		# The badge carries whichever advice the card actually has. It used to
		# always print a star, so a card marked against still read as endorsed.
		var badge: Label = card.get_node("Recommendation")
		var against := bool(option.get("discouraged", false))
		var reason := String(option.get("discouragement_reason" if against else "recommendation_reason", ""))
		badge.text = ("▽ " if against else "★ ") + reason.split("   ")[0]
		badge.tooltip_text = reason
		badge.add_theme_color_override("font_color", Color("9a5b4c") if against else Palette.P1)
		badge.add_theme_stylebox_override("normal",
			Palette.surface(Color("efdcd6") if against else Color("dfebda"), 8))
	var footer: Label = main.p1_level_footer if slot == 0 else main.p2_level_footer
	place(footer, Rect2(268 + slot * 616, 418, 330, 22), 13, Palette.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.text = "무기 %d/4 · 보물 %d/4 · 뽑기 %d" % [main.weapon_loadouts[slot].size(), main.treasure_loadouts[slot].size(), main.rerolls_remaining[slot]]
	if main.level_up_input_delay > 0.0:
		footer.text = "무기 %d/4 · 보물 %d/4 · 잠시 후 선택" % [main.weapon_loadouts[slot].size(), main.treasure_loadouts[slot].size()]
	if screen.has_node("Reroll%d" % slot):
		screen.get_node("Reroll%d" % slot).disabled = main.level_up_input_delay > 0.0 or main.selected_upgrade_indices[slot] >= 0 or main.rerolls_remaining[slot] <= 0
		screen.get_node("Cancel%d" % slot).disabled = main.selected_upgrade_indices[slot] < 0


static func short_evolution(id: String) -> String:
	return {
		"starpiercer": "유도탄 + 관통 광선\n공명 조합 해금", "thunder_god": "범위 안 적 동시 낙뢰\n공명 조합 해금",
		"supernova": "불씨 뒤 2차 폭발\n공명 조합 해금", "absolute_zero": "빙결 후 파쇄\n공명 조합 해금",
		"black_moon": "주변을 두 번 회전베기\n공명 조합 해금", "stigmata": "사슬 화상 + 공동 회복\n공명 조합 해금",
		"celestial": "양방향 이중 궤도\n공명 조합 해금", "judgement": "세 갈래 관통 공격\n공명 조합 해금",
		"ruin_garden": "원형 지뢰밭 설치\n공명 조합 해금", "event_horizon": "흡인 후 중심 폭발\n공명 조합 해금"
	}.get(id, "최종 공격 · 상세 확인")


static func _hud(main: Node) -> void:
	# Keep only the boss's explicit warning plate; ordinary HUD floats over play.
	for child in main.combat_hud.get_children():
		if child is ColorRect and child != main.boss_hud_panel:
			child.hide()
	main.p1_status_label.visible = false
	main.p2_status_label.visible = false
	for slot in 2:
		var bar: ProgressBar = main.p1_health_bar if slot == 0 else main.p2_health_bar
		var caption: Label = main.p1_health_text_label if slot == 0 else main.p2_health_text_label
		bar.position = Vector2(78 if slot == 0 else 922, 30)
		bar.size = Vector2(280, 24)
		caption.position = bar.position
		caption.size = bar.size
	for item in [main.chain_bar, main.chain_distance_text_label]:
		item.position = Vector2(480, 57)
		item.size = Vector2(156, 18)
	for item in [main.chain_integrity_bar, main.chain_integrity_text_label]:
		item.position = Vector2(644, 57)
		item.size = Vector2(156, 18)
	place(main.chain_status_label, Rect2(480, 77, 205, 20), 12, Palette.CREAM)
	place(main.resonance_status_label, Rect2(685, 77, 115, 20), 12, Palette.CREAM)
	main.boss_label.add_theme_color_override("font_color", Color("f0cca2"))
	place(main.boss_label, Rect2(440, 100, 180, 22), 13, Palette.CREAM)
	main.boss_bar.position = Vector2(626, 103)
	main.boss_bar.size = Vector2(214, 16)
	main.boss_health_text_label.position = main.boss_bar.position
	main.boss_health_text_label.size = main.boss_bar.size
	main.boss_health_text_label.add_theme_font_size_override("font_size", 11)
	main.tutorial_label.add_theme_color_override("font_color", Color("f0cca2"))
	place(main.hud_label, Rect2(584, 14, 112, 36), 29, Palette.CREAM)
	main.hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wave_readout := label(main.combat_hud, "", Rect2(702, 22, 138, 24), 12, Color("b9cbc8"))
	wave_readout.name = "WaveReadout"
	wave_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var objective_readout := label(main.combat_hud, "", Rect2(440, 22, 138, 24), 12, Color("e4c899"))
	objective_readout.name = "ObjectiveReadout"
	# Two rows per survivor: weapons on top, treasures under them, each icon
	# carrying its own tier. The play screen showed weapons only and showed them
	# without tiers, so half of what a build actually is — the treasures, and how
	# deep anything was — could only be seen by opening a menu.
	for slot in 2:
		var holder := Control.new()
		holder.position = Vector2(28 if slot == 0 else 1096, 62)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.name = "Carried%d" % slot
		main.combat_hud.add_child(holder)
		for row in ["Weapon", "Treasure"]:
			for index in 4:
				var art := icon(holder, null, Rect2(index * 38, 0 if row == "Weapon" else 40, 30, 30))
				art.name = "%s%d" % [row, index]
				# A bare number, outlined rather than plated: over a busy play field
				# eight little boxes read as UI chrome, and the thing a player
				# actually wants at a glance is the digit.
				var tier := label(art, "", Rect2(11, 15, 26, 18), 13, Palette.CREAM)
				tier.name = "Tier"
				tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tier.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.95))
				tier.add_theme_constant_override("outline_size", 5)


static func refresh_hud(main: Node) -> void:
	main.hud_label.text = "%02d:%02d" % [int(main.elapsed) / 60, int(main.elapsed) % 60]
	main.combat_hud.get_node("WaveReadout").text = "%s · %d 처치" % ["휴식" if main.wave_director.in_calm else "%d파" % maxi(1, main.wave_director.wave_index + 1), main.kills]
	# Five bosses, so the readout has to say which one is coming and how many
	# are left rather than counting down to a single event once and then being
	# permanently wrong for the remaining twenty minutes.
	var director: WaveDirector = main.wave_director
	var readout: String
	if main.chain_warded():
		readout = "사슬 결계  %.1f초" % main.chain_ward_remaining
	elif director.boss_active:
		readout = ""
	elif director.bosses_remaining() <= 0:
		readout = "최종 격파"
	else:
		var remaining := maxi(0, int(director.next_boss_time() - main.elapsed))
		readout = "%d번째 보스  %02d:%02d" % [
			director.bosses_spawned + 1, remaining / 60, remaining % 60
		]
	main.combat_hud.get_node("ObjectiveReadout").text = readout
	for slot in 2:
		var holder: Control = main.combat_hud.get_node("Carried%d" % slot)
		holder.visible = not (main.level_up_active or main.resonance_vote_active or main.pause_active or main.game_over)
		_refresh_carried_row(holder, "Weapon", main.weapon_loadouts[slot], true)
		_refresh_carried_row(holder, "Treasure", main.treasure_loadouts[slot], false)


## One row of the play-field build readout. Tiers are drawn over the corner of
## their own icon rather than beside it: the row has to stay inside the margin
## the play field leaves it, and a tier is only ever a glance.
static func _refresh_carried_row(holder: Control, prefix: String, carried: Array, is_weapon: bool) -> void:
	for index in 4:
		var art: TextureRect = holder.get_node("%s%d" % [prefix, index])
		art.visible = index < carried.size()
		if not art.visible:
			continue
		var entry: Dictionary = carried[index]
		art.texture = Icons.weapon(String(entry["weapon_id"])) if is_weapon else Icons.upgrade(String(entry["id"]))
		var tier: Label = art.get_node("Tier")
		tier.text = str(int(entry.get("tier", 1)))


static func _results(main: Node) -> void:
	var screen: Control = main.result_overlay
	label(screen, "", Rect2(32, 24, 850, 44), 30).name = "ResultHeading"
	label(screen, "", Rect2(32, 74, 850, 28), 16, Palette.MUTED).name = "ResultReason"
	for index in 3:
		var tile := plate(screen, Rect2(32 + index * 290, 120, 274, 120))
		var ids := ["move", "might", "growth"]
		var names := ["생존 시간", "처치", "공유 레벨"]
		icon(tile, Icons.upgrade(ids[index]), Rect2(18, 14, 32, 32))
		label(tile, names[index], Rect2(60, 17, 190, 28), 15, Palette.MUTED)
		label(tile, "", Rect2(20, 52, 230, 52), 36).name = "Value"
		tile.name = "ResultMetric%d" % index
	for slot in 2:
		var x := 32 + slot * 435
		var tile := plate(screen, Rect2(x, 260, 419, 108))
		screen.move_child(tile, 0)
		var portrait: TextureRect = screen.get_node("ResultCat%d" % slot)
		portrait.position = Vector2(x + 12, 275)
		portrait.size = Vector2(72, 72)
		label(screen, "", Rect2(x + 98, 270, 298, 28), 18, Palette.P1 if slot == 0 else Palette.P2).name = "ResultName%d" % slot
		for index in 4:
			icon(screen, null, Rect2(x + 98 + index * 51, 309, 42, 42)).name = "ResultWeapon%d_%d" % [slot, index]
	label(screen, "협동 기록", Rect2(32, 388, 850, 24), 14, Palette.GOLD)
	label(screen, "", Rect2(32, 417, 850, 30), 16, Palette.MUTED).name = "CoopRecord"
	# Sized to its own text rather than to the panel: an 850px plate holding one
	# centred phrase read as two empty boxes with a button wedged between them.
	place(main.result_label, Rect2(311, 470, 292, 42), 18, Palette.INK)
	main.result_label.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD, 10))
	main.result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func refresh_result(main: Node, victory: bool) -> void:
	var screen: Control = main.result_overlay
	screen.get_node("ResultHeading").text = "옥상 수호 성공" if victory else "오늘의 산책 종료"
	screen.get_node("ResultReason").text = "폭주 청소 로봇을 멈췄어요. 간식은 무사합니다!" if victory else "구조가 늦어졌어요. 다시 발맞춰 도전해요."
	var values := ["%02d:%02d" % [int(main.elapsed) / 60, int(main.elapsed) % 60], str(main.kills), "LV.%d" % main.progression.level]
	for index in 3:
		screen.get_node("ResultMetric%d/Value" % index).text = values[index]
	for slot in 2:
		screen.get_node("ResultName%d" % slot).text = "P%d  %s" % [slot + 1, main.players[slot].character_name]
		for index in 4:
			var art: TextureRect = screen.get_node("ResultWeapon%d_%d" % [slot, index])
			art.visible = index < main.weapon_loadouts[slot].size()
			if art.visible:
				art.texture = Icons.weapon(String(main.weapon_loadouts[slot][index]["weapon_id"]))
	screen.get_node("CoopRecord").text = main._run_stats_summary()
	main.result_label.text = "ENTER / A  다시 결속하기"


static func _pause(main: Node) -> void:
	var screen: Control = main.pause_overlay
	for child in screen.get_children():
		if child is TextureRect:
			screen.remove_child(child)
			child.queue_free()
	label(screen, "잠시 쉬어가기", Rect2(32, 24, 595, 42), 28).name = "PauseHeading"
	label(screen, "일시정지  /  두 고양이가 기다려요", Rect2(32, 71, 595, 24), 14, Palette.MUTED)
	var settings := Control.new()
	settings.name = "SettingsRows"
	settings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(settings)
	for index in 4:
		var row := plate(settings, Rect2(32, 113 + index * 47, 596, 41))
		var names := ["화면 흔들림", "피해 숫자", "효과음", "음악"]
		label(row, "F%d" % (index + 1), Rect2(16, 7, 40, 27), 14, Palette.GOLD)
		label(row, names[index], Rect2(72, 7, 400, 27), 17)
		var value := label(row, "", Rect2(494, 7, 82, 27), 15, Palette.P1)
		value.name = "Value"
		row.name = "Setting%d" % index
	place(main.pause_label, Rect2(32, 328, 596, 113), 16)


static func refresh_pause(main: Node) -> void:
	var screen: Control = main.pause_overlay
	screen.get_node("SettingsRows").visible = true
	screen.get_node("PauseHeading").text = "잠시 쉬어가기"
	var values := [main.screen_shake_enabled, main.feedback.damage_numbers_enabled,
		main.feedback.sound_enabled, main.feedback.music_enabled]
	for index in 4:
		screen.get_node("SettingsRows/Setting%d/Value" % index).text = "켜짐" if values[index] else "꺼짐"
	place(main.pause_label, Rect2(32, 328, 596, 113), 16)
	main.pause_label.text = "ESC / START  계속하기\nENTER  처음부터     F11  전체 화면\n대시  P1 SPACE · P2 . · 패드 RT"


static func connection_notice(main: Node, device: int) -> void:
	# Keep the navigable menu; a disconnect must not strand mouse/pad users.
	main._update_pause_text()
	main.pause_overlay.get_node("PauseHeading").text = "P%d 패드 연결 끊김 · 키보드 사용 가능" % (device + 1)
	return
