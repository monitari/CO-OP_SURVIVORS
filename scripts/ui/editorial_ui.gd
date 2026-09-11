extends RefCounted
## Layout and visual hierarchy only. Input and build calculations remain in main.
const Palette := preload("res://scripts/ui/cat_theme.gd")
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const LobbyAmbience := preload("res://scripts/ui/lobby_ambience.gd")
const G := preload("res://scripts/ui/layout_grid.gd")
const MetaProgressionData := preload("res://scripts/systems/meta_progression.gd")
const TitleLogo := preload("res://assets/ui/moonroof_title.png")
const HudPaw := preload("res://assets/ui/frames/hud_paw.svg")
const PLAYSTYLE := {
	"homing": "유도 별탄 · 단일 적 추적", "lightning": "연쇄 번개 · 적 사이로 전이",
	"flame": "불꽃 투사체 · 전방 화력", "frost": "빙결 오라 · 상시 둔화 피해",
	"scythe": "월도 낫 · 부채꼴 연속 베기", "chain": "사슬 파동 · 결속 공격",
	"orbit": "회전 별 · 3.8초 연타", "lance": "관통 광선 · 직선 공격",
	"mine": "결계 지뢰 · 밟을 때까지 유지", "gravity": "중력 붕괴 · 부드러운 흡인",
	"boomerang": "생선 부메랑 · 왕복 추적", "milk": "우유 웅덩이 · 지역 제어",
}



static func label(parent: Node, text: String, rect: Rect2, font_size := Palette.TYPE_BODY, ink: Color = Palette.INK) -> Label:
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
	panel.add_theme_stylebox_override("panel", Palette.surface(tint))
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


static func footer(parent: Control, text: String) -> Label:
	var rule := ColorRect.new()
	rule.name = "FooterRule"
	rule.color = Color(Palette.OUTLINE, 0.72)
	rule.position = Vector2(Palette.PADDING, parent.size.y - 42.0)
	rule.size = Vector2(parent.size.x - Palette.PADDING * 2.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	var item := label(parent, text,
		Rect2(Palette.PADDING, parent.size.y - 38.0, parent.size.x - Palette.PADDING * 2.0, 30.0),
		Palette.TYPE_CAPTION, Palette.MUTED)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.name = "ControlFooter"
	return item


static func apply(main: Node) -> void:
	for screen in [main.title_overlay, main.lobby_overlay, main.character_overlay, main.level_overlay,
		main.resonance_overlay, main.pause_overlay, main.result_overlay]:
		_reink(screen)
	# Six overlays used to sit at six unrelated origins. They are columns now:
	# the two screens that need the whole page take all twelve, and the three
	# that are a dialogue rather than a workspace take the middle eight.
	for wide in [main.title_overlay, main.lobby_overlay, main.character_overlay]:
		wide.position = G.rect(0, 0).position
		wide.size = Vector2(G.w(12), G.h(8))
	for narrow in [main.resonance_overlay, main.pause_overlay, main.result_overlay]:
		narrow.position = G.rect(2, 0.5).position
		narrow.size = Vector2(G.w(8), G.h(7))
	# Results gained a permanent-upgrade row. It uses the eighth grid row while
	# the two shorter dialogue screens keep their original seven-row plate.
	main.result_overlay.position = G.rect(2, 0).position
	main.result_overlay.size = Vector2(G.w(8), G.h(8))
	# The growth screen keeps the vertical slide main animates it with, so only
	# its horizontal placement and width come from the grid.
	main.level_overlay.position.x = G.x(0)
	main.level_overlay.size = Vector2(G.w(12), 568)
	_title(main)
	_lobby(main)
	_characters(main)
	_growth(main)
	_results(main)
	_pause(main)
	_hud(main)
	_resonance(main)
	main.pause_label.add_theme_color_override("font_color", Palette.INK)
	main.result_label.add_theme_color_override("font_color", Palette.INK)
	main.team_stats_label.add_theme_stylebox_override("normal", Palette.surface(Palette.PANEL))
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


## The front door. Built from the same ambience node the lobby uses — logo, two
## cats, a moon — with the menu laid down its left side, so starting a game is
## the same picture gaining a room rather than a different screen entirely.
static func _title(main: Node) -> void:
	var screen: Control = main.title_overlay
	var ambience = LobbyAmbience.new()
	ambience.name = "TitleAmbience"
	ambience.setup(TitleLogo, Icons.survivor("lyra"), Icons.survivor("volta"))
	screen.add_child(ambience)
	screen.move_child(ambience, 0)
	label(screen, "한 화면에서 함께 지키는 로컬 2인 협동",
		Rect2(Palette.PADDING, 12, 250, 24), Palette.TYPE_CAPTION, Palette.GOLD).name = "TitleEyebrow"
	for index in main.title_rows.size():
		var row: Label = main.title_rows[index]
		place(row, G.inner(0, 0, 0.5, 3.9 + float(index) * 0.56, 4.0, 0.52), Palette.TYPE_HEADING)
		row.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
		# The toggle state is its own right-aligned label rather than padding on
		# the end of the caption: Korean names are different widths, so a padded
		# string put every state marker at a different place down the column.
		var state := label(row, "", Rect2(0, 0, row.size.x - 22, row.size.y), Palette.TYPE_BODY, Palette.P1)
		state.name = "State"
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Tall enough for the credits, which is the longest of the three pages.
	place(main.title_note, G.inner(0, 0, 5.0, 3.9, 5.8, 2.3), 15, Palette.MUTED)
	var version_text := String(ProjectSettings.get_setting("application/config/version", "개발판"))
	var version := label(screen, "v" + version_text, Rect2(Palette.PADDING, screen.size.y - 38, 100, 30), Palette.TYPE_CAPTION, Palette.MUTED)
	version.name = "TitleVersion"
	var keys := footer(screen, "↑ ↓ 이동 · ENTER / A 선택 · ESC / B 뒤로")
	keys.name = "TitleKeys"


static func refresh_title(main: Node) -> void:
	var rows: Array = main._title_rows()
	for index in main.title_rows.size():
		var row: Label = main.title_rows[index]
		row.visible = index < rows.size()
		if not row.visible:
			continue
		var caption := String(rows[index])
		# Toggles carry their own state on the row. A settings list that only
		# names the setting makes a player press it to find out what it was.
		var state: Label = row.get_node("State")
		state.text = ""
		if main.title_mode == "settings" and index < 5:
			var states := [main.screen_shake_enabled, main.feedback.damage_numbers_enabled,
				main.feedback.sound_enabled, main.feedback.music_enabled,
				DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN]
			state.text = "● 켜짐" if states[index] else "○ 꺼짐"
			state.add_theme_color_override("font_color", Palette.P1 if states[index] else Palette.MUTED)
		elif main.title_mode == "meta":
			var entry: Dictionary = MetaProgressionData.UPGRADES[index]
			var id := String(entry["id"])
			var rank: int = main.meta_progression.rank(id)
			var price: int = main.meta_progression.cost(id)
			state.text = "Lv.%d/%d · %s" % [rank, int(entry["max_rank"]), "MAX" if price <= 0 else "%d개" % price]
			state.add_theme_color_override("font_color", Palette.GOLD if price <= main.meta_progression.points and price > 0 else Palette.MUTED)
		row.text = ("▶  " if main.title_cursor == index else "     ") + caption
		var focused: bool = main.title_cursor == index
		var style := Palette.surface(Palette.CARD.lerp(Palette.P1, 0.10) if focused else Palette.CARD)
		style.border_color = Palette.P1 if focused else Palette.OUTLINE
		style.set_border_width_all(Palette.BORDER_ACTIVE if focused else Palette.BORDER)
		style.set_content_margin_all(10)
		row.add_theme_stylebox_override("normal", style)
	match main.title_mode:
		"settings":
			main.title_note.text = "설정은 바로 저장되고 다음에 켤 때도 그대로예요."
			if main.settings.last_save_error != OK:
				main.title_note.text += "\n\n저장할 수 없습니다. 저장 공간과 폴더 권한을 확인해 주세요."
		"meta":
			var entry: Dictionary = MetaProgressionData.UPGRADES[main.title_cursor]
			main.title_note.text = "영구 성장 · 보유 %d 달빛 생선\n\n%s\n%s\n\n선택하면 즉시 구매하며 다음 원정부터 적용됩니다." % [
				main.meta_progression.points, String(entry["name"]), String(entry["summary"])]
			if main.meta_progression.last_save_error != OK:
				main.title_note.text = "저장할 수 없습니다. 진행 상황은 변경되지 않았어요.\n\n저장 공간과 폴더 권한을 확인한 뒤 다시 시도해 주세요."
		"credits":
			main.title_note.text = "달빛 옥상 간식 수호대\n사슬로 묶인 두 고양이가 달빛 든 옥상을 지키는 2인 협동 서바이버.\n\n기획 · 프로그래밍 · 아트   monitari\n엔진   Godot 4\n\n함께 놀아준 모두에게 고맙습니다."
		_:
			main.title_note.text = "같은 PC에서 두 사람이 함께 플레이합니다.\n\n키보드 하나를 나눠 쓰거나 게임패드를 연결하세요. 두 사람이 참가하면 캐릭터를 고르고 출발합니다."


static func _lobby(main: Node) -> void:
	var screen: Control = main.lobby_overlay
	# Replace only the decorative captions/portraits, keeping live join controls.
	for child in screen.get_children():
		if child not in [main.lobby_title, main.lobby_p1_label, main.lobby_p2_label]:
			screen.remove_child(child)
			child.queue_free()
	main.lobby_title.text = "함께 출발하기"
	# The illustrated logo already carries the game title. Keep the legacy
	# scene label available to older callers, but do not draw it twice.
	main.lobby_title.visible = false
	place(main.lobby_title, Rect2(Palette.PADDING, 12, 170, 28), Palette.TYPE_HEADING)
	main.lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var ambience = LobbyAmbience.new()
	ambience.name = "LobbyAmbience"
	ambience.setup(TitleLogo, Icons.survivor("lyra"), Icons.survivor("volta"))
	screen.add_child(ambience)
	screen.move_child(ambience, 0)
	var prompt := label(screen, "두 고양이가 모이면 바로 출발", G.inner(0, 0, 3.5, 4, 5, 0.4), Palette.TYPE_VALUE, Palette.MUTED)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in 2:
		var item: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		item.name = "LobbyPlayer%d" % slot
		place(item, G.inner(0, 0, 0.5 + slot * 6.0, 4.65, 5.5, 1.25), Palette.TYPE_HEADING, Palette.P1 if slot == 0 else Palette.P2)
		item.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
		var style := item.get_theme_stylebox("normal") as StyleBoxFlat
		style.set_content_margin_all(22)
	var hint := footer(screen, "P1 WASD / 패드 1 · P2 방향키 / 패드 2 · ESC / START 참가 취소")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func refresh_lobby(main: Node) -> void:
	for slot in 2:
		var item: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		item.add_theme_stylebox_override("normal",
			Palette.player_surface(slot, not main.lobby_joined[slot], main.lobby_joined[slot]))
		item.modulate.a = 1.0 if main.lobby_joined[slot] else 0.88


static func _characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	# Existing large backgrounds are replaced with aligned dossier cards.
	for child in screen.get_children():
		if child is Panel or (child is Label and child.text in ["P1", "P2"]):
			screen.remove_child(child)
			child.queue_free()
	place(main.character_title, G.inner(0, 0, 0.25, 0.2, 7), Palette.TYPE_TITLE)
	main.character_title.text = "오늘 밤의 수호대"
	place(main.character_roster_label, G.inner(0, 0, 8.25, 0.28, 3.5, 0.35), 14, Palette.MUTED)
	main.character_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in main.character_catalog.size():
		# The roster strip is a slice row rather than columns: twelve cats do not
		# divide into twelve columns once the page margin is taken out.
		var strip := G.inner(0, 0, 0.25, 1.0, 11.5, 1.2)
		var slot_rect := G.slice(strip, main.character_catalog.size(), index, G.PAD)
		var tile := plate(screen, slot_rect)
		tile.name = "Roster%d" % index
		icon(tile, Icons.survivor(String(main.character_catalog[index]["id"])), Rect2((slot_rect.size.x - 54) * 0.5, 4, 54, 54))
		var name_label := label(tile, String(main.character_catalog[index]["name"]), Rect2(0, 58, slot_rect.size.x, 22), 13)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in 2:
		# Each survivor takes half the page: six columns, four rows deep.
		var card := G.inner(0, 0, 0.25 + slot * 5.75, 2.4, 5.5, 4.35)
		var x := card.position.x
		var bed := plate(screen, card)
		bed.name = "CharacterPanel%d" % slot
		screen.move_child(bed, 0)
		var portrait: TextureRect = main.character_portrait_icons[slot]
		portrait.position = Vector2(x + G.GUTTER, card.position.y + G.GUTTER)
		portrait.size = Vector2(104, 104)
		label(screen, "P%d" % (slot + 1), Rect2(x + 136, card.position.y + 6, 50, 25), 14, Palette.P1 if slot == 0 else Palette.P2)
		var heading := label(screen, "", Rect2(x + 136, card.position.y + 31, card.size.x - 152, 38), Palette.TYPE_TITLE)
		heading.name = "CatName%d" % slot
		var weapon_art := icon(screen, null, Rect2(x + G.GUTTER, card.position.y + 124, 46, 46))
		weapon_art.name = "CatWeapon%d" % slot
		var role := label(screen, "", Rect2(x + 136, card.position.y + 73, card.size.x - 152, 48), 15, Palette.MUTED)
		role.name = "CatRole%d" % slot
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Eight meaningful axes in a compact 4x2 grid. Weapon art anchors the first
		# cell, so loadout identity is visible before anyone reads a description.
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var entry: Dictionary = CharacterCatalog.DISPLAYED_STATS[stat]
			var column := stat % 4
			var row := stat / 4
			icon(screen, Icons.upgrade(String(entry["icon"])),
				Rect2(x + 76 + column * 108, card.position.y + 124 + row * 39, 25, 25))
			var value := label(screen, "", Rect2(x + 103 + column * 108, card.position.y + 121 + row * 39, 80, 32), 13)
			value.name = "CatStat%d_%d" % [slot, stat]
		var body: Label = main.character_p1_label if slot == 0 else main.character_p2_label
		place(body, Rect2(x + G.GUTTER, card.position.y + 196, card.size.x - G.GUTTER * 2.0, 96), Palette.TYPE_BODY)
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# The one number the pair is actually choosing. A survivor's leash shows up on
	# their own card as a word, which says what that cat contributes but never
	# what the two of them add up to, and the leash is the constraint the whole
	# run is played against. It sits on the pair row under both dossiers, next to
	# the synergy line, because it belongs to neither cat on its own.
	var leash := plate(screen, Rect2(G.x(0.25) - G.x(0), 548, G.w(2.9), 50))
	leash.name = "ChainPlate"
	icon(leash, Icons.upgrade("resolve"), Rect2(G.PAD, 13, 30, 30))
	label(leash, "사슬 길이", Rect2(46, 7, 120, 18), 13, Palette.MUTED)
	var leash_value := label(leash, "", Rect2(46, 25, 160, 24), 19)
	leash_value.name = "ChainLength"
	place(main.character_synergy_label,
		Rect2(G.x(3.35) - G.x(0), 548, G.w(8.4), 50),
		Palette.TYPE_BODY, Palette.MUTED)
	main.character_synergy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer(screen, "P1 A / D 이동 · W 확정     P2 ← / → 이동 · ↑ 확정     ESC 뒤로")


static func refresh_characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	main.character_roster_label.text = "클릭 P1 · 우클릭 P2"
	for slot in 2:
		var cat: Dictionary = main.character_catalog[main.selected_character_indices[slot]]
		screen.get_node("CatName%d" % slot).text = String(cat["name"])
		screen.get_node("CatWeapon%d" % slot).texture = Icons.weapon(String(cat["weapon_id"]))
		# The breed line, not the weapon line. Ten cats used to be introduced by
		# what their weapon does and two by who they are, because only the two
		# newest had no PLAYSTYLE entry to override them. The weapon still
		# describes itself on the level-up card and in the block below.
		screen.get_node("CatRole%d" % slot).text = "%s\n조작 난이도 %s" % [String(cat["title"]), CharacterCatalog.difficulty_stars(cat)]
		screen.get_node("CatRole%d" % slot).tooltip_text = cat["description"]
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var entry: Dictionary = CharacterCatalog.DISPLAYED_STATS[stat]
			screen.get_node("CatStat%d_%d" % [slot, stat]).text = CharacterCatalog.stat_text(cat, String(entry["field"]))
		var panel: Panel = screen.get_node("CharacterPanel%d" % slot)
		panel.add_theme_stylebox_override("panel",
			Palette.player_surface(slot, not main.character_confirmed[slot], main.character_confirmed[slot]))
		if screen.has_node("CharacterConfirm%d" % slot):
			var confirm: Button = screen.get_node("CharacterConfirm%d" % slot)
			confirm.text = "✓ 준비 완료" if main.character_confirmed[slot] else "준비하기"
			confirm.add_theme_stylebox_override("normal",
				Palette.button_surface("normal", Palette.P1 if slot == 0 else Palette.P2, true))
	# One number for the two of them, read after both dossiers are refreshed:
	# it is the pair that has a leash, not either cat on its own.
	var pair_leash := CharacterCatalog.chain_length_for(
		main.character_catalog[main.selected_character_indices[0]],
		main.character_catalog[main.selected_character_indices[1]])
	screen.get_node("ChainPlate/ChainLength").text = "%d px" % roundi(pair_leash)
	for index in main.character_catalog.size():
		var tile: Panel = screen.get_node("Roster%d" % index)
		var style := tile.get_theme_stylebox("panel") as StyleBoxFlat
		var p1: bool = main.selected_character_indices[0] == index
		var p2: bool = main.selected_character_indices[1] == index
		style.border_color = Palette.P1 if p1 else (Palette.P2 if p2 else Palette.OUTLINE)
		style.set_border_width_all(Palette.BORDER_ACTIVE if p1 or p2 else Palette.BORDER)
		style.bg_color = Palette.CARD.lerp(Palette.P1 if p1 else Palette.P2, 0.16) if p1 or p2 else Palette.CARD


static func _growth(main: Node) -> void:
	var screen: Control = main.level_overlay
	# The growth overlay slides vertically, so its children take x from the
	# grid and y from the panel itself.
	place(main.level_title, Rect2(G.PAD, 10, 300, 42), 28)
	var resonance_preview := label(screen, "", Rect2(320, 14, 610, 32), 14, Palette.GOLD)
	resonance_preview.name = "GrowthResonancePreview"
	resonance_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for slot in 2:
		var x: float = main.LEVEL_HALF_X[slot]
		var panel := plate(screen, Rect2(x, 58, G.w(6), 472), Palette.NIGHT_PANEL)
		panel.name = "GrowthPanel%d" % slot
		var panel_style := Palette.player_surface(slot, true, false, true)
		panel_style.border_color = Color(Palette.P1 if slot == 0 else Palette.P2, 0.72)
		panel.add_theme_stylebox_override("panel", panel_style)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.move_child(panel, 0)
		var heading := label(screen, "", Rect2(x + G.PAD, 68, 350, 26), 16, Palette.P1 if slot == 0 else Palette.P2)
		heading.name = "GrowthName%d" % slot
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		for card: Label in main.level_card_labels[slot]:
			card.add_theme_color_override("font_color", Palette.INK)
			card.add_theme_font_size_override("font_size", Palette.TYPE_BODY)
			card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			var style := card.get_theme_stylebox("normal") as StyleBoxFlat
			style.set_corner_radius_all(Palette.RADIUS)
			style.content_margin_left = 16
			style.content_margin_right = 16
			style.content_margin_top = 142
			var art: TextureRect = card.get_node("Icon")
			art.position = Vector2(14, 17)
			# Keep the upper-right corner free for the owned fusion partner seal.
			var scope := label(card, "", Rect2(88, 16, 88, 28), 11, Palette.MUTED)
			scope.name = "Scope"
			scope.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var category := label(card, "", Rect2(92, 52, 88, 30), 13, Palette.MUTED)
			category.name = "Category"
			category.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var title := label(card, "", Rect2(16, 86, 164, 50), Palette.TYPE_VALUE)
			title.name = "CardTitle"
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_theme_font_size_override("font_size", Palette.TYPE_BODY)
			var badge: Label = card.get_node("Recommendation")
			badge.add_theme_color_override("font_color", Palette.P1)
			badge.add_theme_stylebox_override("normal", Palette.surface(Palette.NIGHT_RAISED))
			badge.add_theme_font_size_override("font_size", Palette.TYPE_CAPTION)
		var footer: Label = main.p1_level_footer if slot == 0 else main.p2_level_footer
		footer.add_theme_color_override("font_color", Palette.MUTED)
		main.level_portrait_icons[slot].hide()
		for row_index in 2:
			var row: Array = main.level_weapon_icons[slot] if row_index == 0 else main.level_treasure_icons[slot]
			var row_y := 400.0 + row_index * 44.0
			label(screen, "무기" if row_index == 0 else "보물", Rect2(x + 12, row_y, 34, 42), 13, Palette.MUTED)
			for index in row.size():
				var art: TextureRect = row[index]
				var socket: Control = art.get_parent()
				socket.position = Vector2(x + 48 + index * 88, row_y)
				socket.size = Vector2(42, 42)
				art.size = Vector2(42, 42)
				var tier: Label = art.get_node("Tier")
				tier.position = Vector2(45, 11)
				tier.size = Vector2(38, 20)
				tier.add_theme_font_size_override("font_size", 10)
		# Status right, controls left: both stop a gutter short of the panel edge
		# instead of ending flush against it.
		var stats := label(screen, "", Rect2(x + G.w(6) - 220.0 - G.PAD, 68, 220, 24), 12, Palette.MUTED)
		stats.name = "BuildStats%d" % slot
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		stats.hide()
	place(main.team_stats_label, Rect2(G.PAD, 430, G.w(12) - G.GUTTER, 26), 13, Palette.MUTED)
	main.team_stats_label.visible = false
	var growth_footer := footer(screen, "카드를 고른 뒤 각자의 선택 확정 버튼을 누르세요 · 확정 후 상대가 고르는 동안 취소 가능")
	growth_footer.position.y = screen.size.y - 28
	growth_footer.size.y = 20
	screen.get_node("FooterRule").position.y = screen.size.y - 32


static func refresh_growth(main: Node, slot: int) -> void:
	var screen: Control = main.level_overlay
	var complete: bool = main.selected_upgrade_indices[slot] == -2
	var locked: bool = main.selected_upgrade_indices[slot] >= 0
	screen.get_node("GrowthName%d" % slot).text = "P%d %s  ·  %s" % [
		slot + 1, "빌드 완성 ✓" if complete else ("확정 ✓ · 상대 선택 대기" if locked else "선택 중"), main.selected_characters[slot]["name"]]
	var predicted: Dictionary = main._growth_resonance_preview()
	screen.get_node("GrowthResonancePreview").text = (
		"예상 공명 · %s · %s" % [predicted["name"], predicted["description"]]
		if not predicted.is_empty() else "테크를 맞추면 완성 공명을 미리 보여줍니다")
	var panel: Panel = screen.get_node("GrowthPanel%d" % slot)
	panel.add_theme_stylebox_override("panel", Palette.player_surface(slot, not locked, locked, true))
	var player: Node = main.players[slot]
	screen.get_node("BuildStats%d" % slot).text = "공격 %d%%   범위 %d%%   이속 %d\n방어 %.0f   회복 %.1f/s" % [
		int(player.might * 100), int(player.area * 100), int(player.move_speed), player.armor, player.recovery]
	var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
	for index in choices.size():
		var option: Dictionary = choices[index]
		var card: Label = main.level_card_labels[slot][index]
		var kind := String(option["id"])
		var category := card.get_node("Category") as Label
		if kind == "choose_tech":
			var profile := String((option["tech"] as Dictionary).get("profile", "balanced"))
			category.text = {
				"force": "피해 테크", "tempo": "연사 테크",
				"control": "제어 테크", "balanced": "균형 테크",
			}.get(profile, "테크 결정")
			category.add_theme_color_override("font_color", {
				"force": Color("ff8e72"), "tempo": Color("67c8ff"),
				"control": Color("80ed99"), "balanced": Palette.GOLD,
			}.get(profile, Palette.MUTED))
		else:
			category.text = "새 보물" if kind == "unlock_treasure" else ("보물 강화" if kind == "treasure_upgrade" else ("새 무기" if kind == "unlock_weapon" else ("최종 진화" if kind == "evolve_weapon" else "무기 강화")))
			category.add_theme_color_override("font_color", Palette.MUTED)
		var shared := false
		if kind == "unlock_treasure":
			shared = bool((option["treasure"] as Dictionary).get("shared", false))
		elif kind == "treasure_upgrade":
			shared = bool((main.treasure_loadouts[slot][int(option["treasure_slot"])] as Dictionary).get("shared", false))
		card.get_node("Scope").text = (
			"P%d 테크" % (slot + 1) if kind == "choose_tech"
			else "두 고양이에게 적용" if shared else "P%d에게 적용" % (slot + 1))
		card.get_node("CardTitle").text = String(option["title"]).replace("새 보물: ", "").replace("신규 기술: ", "").replace("보물 강화: ", "").replace("무기 진화: ", "")
		card.text = compact_growth_description(option)
		card.text = card.text.replace(", ", "\n").replace("출혈 시간", "구조 시간").replace("내구도 소모", "내구 소모")
		if choices.size() >= 4:
			card.text = compact_grid_description(card.text)
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
		badge.add_theme_color_override("font_color", Color("ffb2ac") if against else Palette.P1)
		badge.add_theme_stylebox_override("normal",
			Palette.surface(Palette.NIGHT_RAISED))
		badge.visible = kind != "choose_tech" and (bool(option.get("recommended", false)) or against)
	var footer: Label = main.p1_level_footer if slot == 0 else main.p2_level_footer
	place(footer, Rect2(main.LEVEL_HALF_X[slot] + G.w(6) - 212.0 - G.PAD, 68, 212, 22), 12, Palette.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.text = "무기 %d/4 · 보물 %d/4" % [main.weapon_loadouts[slot].size(), main.treasure_loadouts[slot].size()]
	if main.level_up_input_delay > 0.0:
		footer.text = "잠시 후 선택할 수 있습니다"
	if screen.has_node("Reroll%d" % slot):
		var confirm: Button = screen.get_node("Confirm%d" % slot)
		confirm.disabled = main.level_up_input_delay > 0.0 or locked or complete
		confirm.text = "✓ 빌드 완성" if complete else ("✓ 확정 완료" if locked else "선택 확정")
		var reroll: Button = screen.get_node("Reroll%d" % slot)
		var tech_hand := not choices.is_empty() and choices.all(func(option: Dictionary) -> bool: return String(option["id"]) == "choose_tech")
		reroll.disabled = main.level_up_input_delay > 0.0 or locked or complete or tech_hand or main.rerolls_remaining[slot] <= 0
		reroll.text = "테크 선택 · 재추첨 없음" if tech_hand else "다시 뽑기 · %d" % main.rerolls_remaining[slot]
		screen.get_node("Cancel%d" % slot).disabled = not locked or complete


static func compact_growth_description(option: Dictionary) -> String:
	var description := String(option.get("description", ""))
	if String(option.get("id", "")) not in ["unlock_treasure", "treasure_upgrade"]:
		return description
	return description.replace(
		"투사체·장판 지속시간", "투사체·장판 지속").replace(
		"가한 피해 0.6%를 팀 체력으로 회복 · 초당 최대 1.5",
		"피해의 0.6% 팀 회복\n초당 최대 +1.5")


static func compact_grid_description(description: String) -> String:
	var lines := description.split("\n", false)
	if lines.size() <= 2:
		return description
	# The first line is the core before/after value. The last line is either its
	# plain-language meaning or the slot result; full secondary detail remains
	# available in the always-accessible detail sheet and tooltip.
	return "%s\n%s" % [lines[0], lines[lines.size() - 1]]


static func short_evolution(id: String) -> String:
	return {
		"starpiercer": "유도탄 + 관통 광선\n공명 조합 해금", "thunder_god": "범위 안 적 동시 낙뢰\n공명 조합 해금",
		"supernova": "불씨 뒤 2차 폭발\n공명 조합 해금", "absolute_zero": "빙결 후 파쇄\n공명 조합 해금",
		"black_moon": "주변을 두 번 회전베기\n공명 조합 해금", "stigmata": "사슬 화상 + 공동 회복\n공명 조합 해금",
		"celestial": "양방향 이중 궤도\n공명 조합 해금", "judgement": "세 갈래 관통 공격\n공명 조합 해금",
		"ruin_garden": "원형 지뢰밭 설치\n공명 조합 해금", "event_horizon": "흡인 후 중심 폭발\n공명 조합 해금",
		"skipping_stone": "사방으로 튕기는 왕복 공격\n공명 조합 해금", "cream_tide": "바닥을 덮는 둔화 해일\n공명 조합 해금"
	}.get(id, "최종 공격 · 상세 확인")


static func _resonance(main: Node) -> void:
	var screen: Control = main.resonance_overlay
	place(main.resonance_title,
		Rect2(Palette.PADDING, 18, screen.size.x - Palette.PADDING * 2.0, 40),
		Palette.TYPE_TITLE)
	main.resonance_title.text = "함께 쓰는 필살기"
	main.resonance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for child in screen.get_children():
		if child is Label and String(child.text).begins_with("강화 무기"):
			child.name = "ResonanceSubtitle"
			place(child, Rect2(Palette.PADDING, 58, screen.size.x - Palette.PADDING * 2.0, 24),
				Palette.TYPE_CAPTION, Palette.MUTED)
	for index in main.resonance_cards.size():
		var card: Label = main.resonance_cards[index]
		card.position = Vector2(main.RESONANCE_CARD_MARGIN
			+ (main.RESONANCE_CARD_WIDTH + main.RESONANCE_CARD_GAP) * index,
			main.RESONANCE_CARD_Y)
		card.size = Vector2(main.RESONANCE_CARD_WIDTH, main.RESONANCE_CARD_HEIGHT)
		card.add_theme_font_size_override("font_size", Palette.TYPE_BODY)
		card.add_theme_color_override("font_color", Palette.INK)
		var style := Palette.surface(Palette.CARD)
		style.content_margin_left = Palette.PADDING
		style.content_margin_right = Palette.PADDING
		style.content_margin_top = 100
		style.content_margin_bottom = 78
		card.add_theme_stylebox_override("normal", style)
		var pips: Label = card.get_node("Pips")
		place(pips, Rect2(10, card.size.y - 38, card.size.x - 20, 28),
			Palette.TYPE_CAPTION, Palette.CREAM)
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pips.add_theme_stylebox_override("normal", Palette.surface(Palette.NIGHT_RAISED))
	place(main.resonance_status,
		Rect2(Palette.PADDING, screen.size.y - 108, screen.size.x - Palette.PADDING * 2.0, 54),
		Palette.TYPE_BODY, Palette.MUTED)
	main.resonance_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer(screen, "P1 A / D 이동 · W 확정 · S 취소     P2 ← / → 이동 · ↑ 확정 · ↓ 취소")


static func _hud(main: Node) -> void:
	# Keep only the boss's explicit warning plate; ordinary HUD floats over play.
	for child in main.combat_hud.get_children():
		if child is ColorRect and child != main.boss_hud_panel:
			child.hide()
	_install_hud_frames(main)
	main.p1_status_label.visible = false
	main.p2_status_label.visible = false
	for slot in 2:
		var bar: ProgressBar = main.p1_health_bar if slot == 0 else main.p2_health_bar
		var caption: Label = main.p1_health_text_label if slot == 0 else main.p2_health_text_label
		var x := 14.0 if slot == 0 else 874.0
		var accent := Palette.P1 if slot == 0 else Palette.P2
		bar.position = Vector2(x + 76, 34)
		bar.size = Vector2(300, 16)
		var track := Palette.surface(Palette.NIGHT)
		track.border_color = Palette.OUTLINE
		var fill := Palette.surface(accent.darkened(0.38), Palette.RADIUS)
		fill.set_border_width_all(0)
		bar.add_theme_stylebox_override("background", track)
		bar.add_theme_stylebox_override("fill", fill)
		caption.position = bar.position
		caption.size = bar.size
		caption.add_theme_font_size_override("font_size", 13)
		main.hud_portrait_icons[slot].position = Vector2(x + 10, 14)
		main.hud_portrait_icons[slot].size = Vector2(36, 36)
		label(main.combat_hud, "P%d" % (slot + 1), Rect2(x + 48, 14, 28, 20), 13, accent)
		label(main.combat_hud, "", Rect2(x + 80, 10, 290, 22), 15, accent).name = "PlayerIdentity%d" % slot
	for item in [main.chain_bar, main.chain_distance_text_label]:
		item.position = Vector2(G.x(4.35), 57)
		item.size = Vector2(G.w(1.6), 18)
	for item in [main.chain_integrity_bar, main.chain_integrity_text_label]:
		item.position = Vector2(G.x(6.0), 57)
		item.size = Vector2(G.w(1.6), 18)
	# Put text above thin meters so a full bright fill cannot wash out its label.
	for caption: Label in [main.chain_distance_text_label, main.chain_integrity_text_label]:
		caption.position.y = 53
	for meter: ProgressBar in [main.chain_bar, main.chain_integrity_bar]:
		meter.position.y = 73
		meter.size.y = 4
		meter.add_theme_stylebox_override("background", Palette.surface(Color("17263a99")))
		var meter_fill := Palette.surface(Palette.GOLD)
		meter_fill.set_border_width_all(0)
		meter.add_theme_stylebox_override("fill", meter_fill)
	place(main.chain_status_label, Rect2(G.x(4.35), 77, G.w(2), 20), 12, Palette.CREAM)
	place(main.resonance_status_label, Rect2(G.x(6.4), 77, G.w(1.2), 20), 12, Palette.CREAM)
	main.boss_label.add_theme_color_override("font_color", Color("f0cca2"))
	place(main.boss_label, Rect2(G.x(3.9), 100, G.w(1.8), 22), 13, Palette.CREAM)
	main.boss_bar.position = Vector2(G.x(5.8), 103)
	main.boss_bar.size = Vector2(G.w(2.2), 16)
	main.boss_health_text_label.position = main.boss_bar.position
	main.boss_health_text_label.size = main.boss_bar.size
	main.boss_health_text_label.add_theme_font_size_override("font_size", 11)
	main.boss_label.position.y = 130
	main.boss_bar.position.y = 133
	main.boss_health_text_label.position.y = 133
	main.xp_bar.position = Vector2(436, 118)
	main.xp_bar.size = Vector2(408, 4)
	main.xp_bar.add_theme_stylebox_override("background", Palette.surface(Color("17263a99")))
	var xp_fill := Palette.surface(Palette.GOLD)
	xp_fill.set_border_width_all(0)
	main.xp_bar.add_theme_stylebox_override("fill", xp_fill)
	place(main.xp_text_label, Rect2(436, 96, 408, 20), 13, Palette.GOLD)
	main.xp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The clock is the page's centre line, so it is centred on the content span
	# rather than snapped to a column edge — 48..1232 has its middle at 640.
	place(main.hud_label, Rect2((G.VIEWPORT.x - G.w(1.2)) * 0.5, 14, G.w(1.2), 36), Palette.TYPE_TITLE, Palette.CREAM)
	main.hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wave_readout := label(main.combat_hud, "", Rect2(700, 22, 100, 24), 12, Color("b9cbc8"))
	wave_readout.name = "WaveReadout"
	wave_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var objective_readout := label(main.combat_hud, "", Rect2(480, 22, 100, 24), 12, Color("e4c899"))
	objective_readout.name = "ObjectiveReadout"
	# Four reserved weapon slots explain the space before a build is full.
	for slot in 2:
		var holder := Control.new()
		holder.position = Vector2(26 if slot == 0 else 886, 56)
		holder.size = Vector2(368, 64)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.name = "Carried%d" % slot
		main.combat_hud.add_child(holder)
		for row in ["Weapon", "Treasure"]:
			var weapon_row: bool = row == "Weapon"
			var y := 0 if weapon_row else 35
			var cell_height := 32 if weapon_row else 26
			var icon_size := 28 if weapon_row else 22
			label(holder, "무기" if weapon_row else "보물", Rect2(0, y, 34, cell_height), 13, Color("a8bfbc"))
			for index in 4:
				var x := 36 + index * 82
				var socket := plate(holder, Rect2(x, y, 78, cell_height), Color("24464b"))
				socket.name = "%sSlot%d" % [row, index]
				var style := Palette.surface(Color("20334e55") if weapon_row else Color("20334e33"))
				style.border_color = Palette.OUTLINE
				socket.add_theme_stylebox_override("panel", style)
				# A faint socket already communicates capacity. Repeating plus signs
				# across every empty slot made the opening HUD look busier than play.
				var empty := label(socket, "", Rect2(0, 0, 78, cell_height), 16, Color("6a8585"))
				empty.name = "Empty"
				empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				var art := icon(holder, null, Rect2(x + 2, y + 2, icon_size, icon_size))
				art.name = "%s%d" % [row, index]
				var tier := label(art, "", Rect2(icon_size, 0, 46, icon_size), 13, Palette.CREAM)
				tier.name = "Tier"
				tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER



## Native panels share menu geometry, with cream confined to portrait plaques.
static func _install_hud_frames(main: Node) -> void:
	for slot in 2:
		var x := 14.0 if slot == 0 else 874.0
		var panel := plate(main.combat_hud, Rect2(x, 8, 392, 116), Palette.HUD)
		panel.name = "P%dFrame" % (slot + 1)
		panel.z_index = -2
		var style := Palette.surface(Palette.HUD)
		style.border_color = Color(Palette.P1 if slot == 0 else Palette.P2, 0.42)
		panel.add_theme_stylebox_override("panel", style)
		var portrait := plate(panel, Rect2(6, 4, 40, 40), Color(Palette.CREAM, 0.12))
		portrait.name = "PortraitPlaque"
		var paw := icon(panel, HudPaw, Rect2(374, 98, 12, 12))
		paw.modulate = Color("809998") if slot == 0 else Color("b59bcd")
	var shared := plate(main.combat_hud, Rect2(418, 8, 444, 116), Palette.HUD)
	shared.name = "SharedFrame"
	shared.z_index = -2
	var shared_style := Palette.surface(Palette.HUD)
	shared_style.border_color = Palette.OUTLINE
	shared.add_theme_stylebox_override("panel", shared_style)


static func refresh_hud(main: Node) -> void:
	main.hud_label.text = "%02d:%02d" % [int(main.elapsed) / 60, int(main.elapsed) % 60]
	main.xp_text_label.text = "공유 Lv.%d   ·   XP %d / %d" % [main.progression.level, int(main.progression.experience), int(main.progression.required_experience)]
	main.combat_hud.get_node("WaveReadout").text = "%s · %d 처치" % ["휴식" if main.wave_director.in_calm else "%d파" % maxi(1, main.wave_director.wave_index + 1), main.kills]
	# Five bosses, so the readout has to say which one is coming and how many
	# are left rather than counting down to a single event once and then being
	# permanently wrong for the remaining twenty minutes.
	var director: WaveDirector = main.wave_director
	var readout: String
	if main.chain_warded():
		readout = "황금 목줄  %.1f초" % main.chain_ward_remaining
	elif director.boss_active:
		readout = "%d/%d 보스 전투" % [director.bosses_spawned, WaveDirector.BOSS_COUNT]
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
		main.combat_hud.get_node("PlayerIdentity%d" % slot).text = "%s   ·   개인 Lv.%d" % [main.players[slot].character_name, int(main.run_stats["personal_levels"][slot])]
		holder.visible = not (main.level_up_active or main.resonance_vote_active or main.pause_active or main.game_over)
		_refresh_carried_row(holder, "Weapon", main.weapon_loadouts[slot], true)
		_refresh_carried_row(holder, "Treasure", main.treasure_loadouts[slot], false)


## Explicit level captions distinguish equipment levels from item quantities.
static func _refresh_carried_row(holder: Control, prefix: String, carried: Array, is_weapon: bool) -> void:
	for index in 4:
		var art: TextureRect = holder.get_node("%s%d" % [prefix, index])
		art.visible = index < carried.size()
		holder.get_node("%sSlot%d/Empty" % [prefix, index]).visible = not art.visible
		if not art.visible:
			continue
		var entry: Dictionary = carried[index]
		art.texture = Icons.weapon(String(entry["weapon_id"])) if is_weapon else Icons.upgrade(String(entry["id"]))
		var tier: Label = art.get_node("Tier")
		tier.text = "Lv.%d" % int(entry.get("tier", 1))


static func _results(main: Node) -> void:
	var screen: Control = main.result_overlay
	var wide := G.w(8) - G.GUTTER * 2.0
	label(screen, "", Rect2(G.GUTTER, 24, wide, 44), Palette.TYPE_TITLE).name = "ResultHeading"
	label(screen, "", Rect2(G.GUTTER, 74, wide, 28), Palette.TYPE_BODY, Palette.MUTED).name = "ResultReason"
	for index in 3:
		# Three metric tiles across the dialogue, sharing one gutter each.
		var tile := plate(screen, G.slice(Rect2(G.GUTTER, 120, wide, 120), 3, index))
		var ids := ["move", "might", "growth"]
		var names := ["생존 시간", "처치", "공유 레벨"]
		icon(tile, Icons.upgrade(ids[index]), Rect2(18, 14, 32, 32))
		label(tile, names[index], Rect2(60, 17, tile.size.x - 76.0, 28), 15, Palette.MUTED)
		label(tile, "", Rect2(20, 52, tile.size.x - 40.0, 52), Palette.TYPE_METRIC).name = "Value"
		tile.name = "ResultMetric%d" % index
	for slot in 2:
		var half := G.slice(Rect2(G.GUTTER, 252, wide, 150), 2, slot)
		var x := half.position.x
		var tile := plate(screen, half)
		screen.move_child(tile, 0)
		var portrait: TextureRect = screen.get_node("ResultCat%d" % slot)
		portrait.position = Vector2(x + G.GUTTER, 270)
		portrait.size = Vector2(64, 64)
		label(screen, "", Rect2(x + 92, 264, half.size.x - 108, 26), 18, Palette.P1 if slot == 0 else Palette.P2).name = "ResultName%d" % slot
		var player_stats := label(screen, "", Rect2(x + 92, 290, half.size.x - 108, 34), 12, Palette.MUTED)
		player_stats.name = "ResultPlayerStats%d" % slot
		player_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for index in 4:
			var weapon_x := x + 92 + index * 72
			icon(screen, null, Rect2(weapon_x, 329, 42, 42)).name = "ResultWeapon%d_%d" % [slot, index]
			var dps := label(screen, "", Rect2(weapon_x - 8, 372, 58, 18), 11, Palette.MUTED)
			dps.name = "ResultWeaponDps%d_%d" % [slot, index]
			dps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(screen, "함께 지킨 기록 · 획득물", Rect2(G.GUTTER, 410, wide, 22), 14, Palette.GOLD)
	var coop := label(screen, "", Rect2(G.GUTTER, 433, wide, 48), 14, Palette.MUTED)
	coop.name = "CoopRecord"
	coop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var meta_title := label(screen, "", Rect2(G.GUTTER, 486, wide, 22), 14, Palette.GOLD)
	meta_title.name = "MetaTitle"
	for index in 6:
		var card_width := (wide - 5.0 * 8.0) / 6.0
		# Moved up, and the restart button moved below, because the two used to
		# occupy the same rows: the moon-fish row arrived on this screen after the
		# button and nothing shifted to make space, so the button sat across two of
		# the six cards. Their names were unreadable and they could not be clicked.
		var card := label(screen, "", Rect2(G.GUTTER + index * (card_width + 8.0), 512, card_width, 64), 11, Palette.INK)
		card.name = "MetaUpgrade%d" % index
		card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
	# Sized to its own text rather than to the panel: an 850px plate holding one
	# centred phrase read as two empty boxes with a button wedged between them.
	place(main.result_label, Rect2(G.GUTTER, 620, wide, 18), 12, Palette.MUTED)
	main.result_label.remove_theme_stylebox_override("normal")
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
		screen.get_node("ResultPlayerStats%d" % slot).text = main._result_player_summary(slot)
		for index in 4:
			var art: TextureRect = screen.get_node("ResultWeapon%d_%d" % [slot, index])
			var dps: Label = screen.get_node("ResultWeaponDps%d_%d" % [slot, index])
			art.visible = index < main.weapon_loadouts[slot].size()
			dps.visible = art.visible
			if art.visible:
				var weapon_id := String(main.weapon_loadouts[slot][index]["weapon_id"])
				art.texture = Icons.weapon(weapon_id)
				dps.text = "%.1f DPS" % main._weapon_dps(slot, weapon_id)
				art.tooltip_text = "%s · 총 피해 %.0f" % [
					String(main.weapon_loadouts[slot][index]["weapon_name"]),
					float(main.run_stats["weapon_damage"][slot].get(weapon_id, 0.0)),
				]
	screen.get_node("CoopRecord").text = main._run_stats_summary()
	main._refresh_meta_result_ui()
	main.result_label.text = "SPACE / Y  강화 구매    ENTER / A  메인 메뉴로" if victory else "ENTER / A  메인 메뉴로"


static func _pause(main: Node) -> void:
	var screen: Control = main.pause_overlay
	for child in screen.get_children():
		if child is TextureRect:
			screen.remove_child(child)
			child.queue_free()
	label(screen, "잠시 쉬어가기", Rect2(G.GUTTER, 24, G.w(8) - G.GUTTER * 2.0, 42), Palette.TYPE_TITLE).name = "PauseHeading"
	label(screen, "일시정지  /  두 고양이가 기다려요", Rect2(G.GUTTER, 71, G.w(8) - G.GUTTER * 2.0, 24), Palette.TYPE_CAPTION, Palette.MUTED)
	var settings := Control.new()
	settings.name = "SettingsRows"
	settings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(settings)
	for index in 4:
		var row := plate(settings, Rect2(G.GUTTER, 113 + index * 47, G.w(8) - G.GUTTER * 2.0, 41))
		var names := ["화면 흔들림", "피해 숫자", "효과음", "음악"]
		label(row, "F%d" % (index + 1), Rect2(16, 7, 40, 27), 14, Palette.GOLD)
		label(row, names[index], Rect2(72, 7, 400, 27), 17)
		var value := label(row, "", Rect2(494, 7, 82, 27), 15, Palette.P1)
		value.name = "Value"
		row.name = "Setting%d" % index
	place(main.pause_label, Rect2(G.GUTTER, 328, G.w(8) - G.GUTTER * 2.0, 113), 16)


static func refresh_pause(main: Node) -> void:
	var screen: Control = main.pause_overlay
	screen.get_node("SettingsRows").visible = true
	screen.get_node("PauseHeading").text = "잠시 쉬어가기"
	var values := [main.screen_shake_enabled, main.feedback.damage_numbers_enabled,
		main.feedback.sound_enabled, main.feedback.music_enabled]
	for index in 4:
		screen.get_node("SettingsRows/Setting%d/Value" % index).text = "켜짐" if values[index] else "꺼짐"
	place(main.pause_label, Rect2(G.GUTTER, 328, G.w(8) - G.GUTTER * 2.0, 113), 16)
	main.pause_label.text = "ESC / START  계속하기\nENTER  처음부터     F11  전체 화면\n대시  P1 SPACE · P2 . · 패드 RT"


static func connection_notice(main: Node, device: int) -> void:
	# Keep the navigable menu; a disconnect must not strand mouse/pad users.
	main._update_pause_text()
	main.pause_overlay.get_node("PauseHeading").text = "P%d 패드 연결 끊김 · 키보드 사용 가능" % (device + 1)
	return
