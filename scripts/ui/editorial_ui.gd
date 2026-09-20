extends RefCounted
## Layout and visual hierarchy only. Input and build calculations remain in main.
const Palette := preload("res://scripts/ui/cat_theme.gd")
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const LobbyAmbience := preload("res://scripts/ui/lobby_ambience.gd")
const Polaroid := preload("res://scripts/ui/polaroid.gd")
const G := preload("res://scripts/ui/layout_grid.gd")
const MetaProgressionData := preload("res://scripts/systems/meta_progression.gd")
const UIWrite := preload("res://scripts/ui/ui_write.gd")
## The survivor dossier's stat chips. Four across a 352px column, each holding an
## icon and a line like "범위 118%".
##
## Sized from the longest line the roster can produce, not from a round number:
## at 49px of text plus an 18px icon and real margins, four cells only fit that
## column if the stride is 89 and the gap between them is 5. The previous 80/88
## pair left the text 40px and silently cut the percent sign off every
## three-digit stat.
const STAT_CELL := 84.0
const STAT_STRIDE := 89.0
const STAT_ICON := 18.0

const ScrapbookBackdrop := preload("res://assets/ui/moonroof_scrapbook_backdrop_v2.png")
const TitleLogo := preload("res://assets/ui/moonroof_title_scrapbook_v4.png")
const SnapshotIgnisNeve := preload("res://assets/ui/title_snapshot_ignis_neve_v1.png")
const SnapshotTeraNova := preload("res://assets/ui/title_snapshot_tera_nova_v1.png")
const SnapshotSquad := preload("res://assets/ui/title_snapshot_squad_v1.png")
const SnapshotPrank := preload("res://assets/ui/title_snapshot_prank_v1.png")
## The fight's readout face. Everything the HUD asks you to read at a glance —
## the clock, the boss timer, the wave and kill counts, the meter captions, both
## health bars and the carried-item levels — is set in it rather than in the
## handwriting the menus use. See CatTheme.READOUT for why.
const ReadoutFont := Palette.READOUT
const HudPaw := preload("res://assets/ui/frames/hud_paw.svg")
const PLAYSTYLE := {
	"homing": "유도 별탄    단일 적 추적", "lightning": "연쇄 번개    적 사이로 전이",
	"flame": "불꽃 투사체    전방 화력", "frost": "빙결 오라    상시 둔화 피해",
	"scythe": "월도 낫    부채꼴 연속 베기", "chain": "사슬 파동    결속 공격",
	"orbit": "회전 별    3.8초 연타", "lance": "관통 광선    직선 공격",
	"mine": "결계 지뢰    밟을 때까지 유지", "gravity": "중력 붕괴    부드러운 흡인",
	"boomerang": "생선 부메랑    왕복 추적", "milk": "우유 웅덩이    지역 제어",
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
		15, Palette.NIGHT_MUTED)
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
	for narrow in [main.pause_overlay, main.result_overlay]:
		narrow.position = G.rect(2, 0.5).position
		narrow.size = Vector2(G.w(8), G.h(7))
	# Results need wider player summaries and permanent-upgrade cards. Ten grid
	# columns keep their 13px labels readable while staying inside the viewport.
	main.result_overlay.position = G.rect(1, 0).position
	main.result_overlay.size = Vector2(G.w(10), G.h(8))
	# The two choice screens are off the grid on purpose: each is a band across
	# the whole bottom of the viewport, not a panel inside the page margins, and
	# the run it interrupts stays visible above it. Both keep the vertical slide
	# main animates them with, so only their width is set here.
	for band in [main.level_overlay, main.resonance_overlay]:
		band.position.x = 0.0
		band.size = Vector2(G.VIEWPORT.x, main.LEVEL_OVERLAY_HEIGHT)
	_title(main)
	_lobby(main)
	_characters(main)
	_results(main)
	_pause(main)
	_hud(main)
	_resonance(main)
	main.pause_label.add_theme_color_override("font_color", Palette.INK)
	main.result_label.add_theme_color_override("font_color", Palette.INK)


static func _reink(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", Palette.INK)
	for child in node.get_children():
		_reink(child)


## Where the five main-menu cards sit (overlay-local). Hand-placed like paper
## laid on a desk — each card a few pixels off the line and turned a degree or
## so — but with one fixed 12px gap, so the stack reads as deliberate rather
## than misaligned. The two least-used actions are the smaller cards.
const TITLE_MENU_SLOTS := [
	Rect2(40, 222, 372, 72),
	Rect2(56, 306, 336, 56), Rect2(46, 374, 336, 56),
	Rect2(60, 442, 288, 48), Rect2(50, 502, 288, 48),
]
const TITLE_MENU_TILT := [-0.022, 0.017, -0.013, 0.021, -0.017]
## How far the card under the cursor slides out of the stack.
const TITLE_MENU_NUDGE := 14.0
## The marker-pen fill of the card under the cursor.
const TITLE_FOCUS := Color("f2c35e")


## A scrapbook page: the game's name hand-lettered top left over torn paper, the
## menu as a stack of paper cards under it, and the two cats as polaroids taped
## under the moon on the right. Nothing else is written on the page.
static func _title(main: Node) -> void:
	var screen: Control = main.title_overlay
	screen.chromeless = true
	# The sheet every sub-page (modes, growth, settings, credits) is written on.
	var menu_plate := Panel.new()
	menu_plate.name = "TitlePlate"
	menu_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_plate.add_theme_stylebox_override("panel", Palette.image_surface())
	screen.add_child(menu_plate)
	screen.move_child(menu_plate, 0)
	preload("res://scripts/ui/neon_growth_ui.gd").trim(menu_plate, Palette.TAPE, false, true)
	var ambience = LobbyAmbience.new()
	ambience.name = "TitleAmbience"
	ambience.setup_backdrop(ScrapbookBackdrop)
	screen.add_child(ambience)
	screen.move_child(ambience, 0)
	var brand := icon(screen, TitleLogo, Rect2(36, 18, 392, 196))
	brand.name = "BrandLockup"
	brand.set_meta("decorative_overhang", true)
	var collage := Control.new()
	collage.name = "SnapshotCollage"
	collage.set_anchors_preset(Control.PRESET_FULL_RECT)
	collage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(collage)
	_snapshot(collage, "SnapshotIgnisNeve", SnapshotIgnisNeve,
		Rect2(640, 115, 230, 230), -0.12)
	_snapshot(collage, "SnapshotTeraNova", SnapshotTeraNova,
		Rect2(870, 155, 225, 225), 0.085)
	_snapshot(collage, "SnapshotSquad", SnapshotSquad,
		Rect2(680, 350, 245, 245), 0.065)
	_snapshot(collage, "SnapshotPrank", SnapshotPrank,
		Rect2(890, 305, 210, 210), -0.115)
	label(screen, "", Rect2(392, 40, 400, 40), 27, Palette.INK).name = "TitleEyebrow"
	for index in main.title_rows.size():
		var row: Label = main.title_rows[index]
		place(row, G.inner(0, 0, 0.5, 3.9 + float(index) * 0.56, 4.0, 0.52), Palette.TYPE_HEADING)
		row.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
		# The toggle state is its own right-aligned label rather than padding on
		# the end of the caption: Korean names are different widths, so a padded
		# string put every state marker at a different place down the column.
		var state := label(row, "", Rect2(0, 0, row.size.x - 22, row.size.y), Palette.TYPE_BODY, Palette.P1_INK)
		state.name = "State"
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Tall enough for the credits, which is the longest of the three pages.
	place(main.title_note, G.inner(0, 0, 5.0, 3.9, 5.8, 2.3), 15, Palette.MUTED)
	var version_text := String(ProjectSettings.get_setting("application/config/version", "개발판"))
	var version := label(screen, "v" + version_text, Rect2(Palette.PADDING, screen.size.y - 38, 100, 30), Palette.TYPE_CAPTION, Palette.NIGHT_MUTED)
	version.name = "TitleVersion"
	var keys := footer(screen, "↑ ↓ 이동    ENTER / A 선택    ESC / B 뒤로")
	keys.name = "TitleKeys"
	for caption: Label in [version, keys]:
		caption.add_theme_color_override("font_color", Palette.CREAM)
		caption.add_theme_constant_override("outline_size", 4)
		caption.add_theme_color_override("font_outline_color", Color(Palette.INK, 0.85))
	screen.get_node("FooterRule").visible = false


static func _snapshot(parent: Control, node_name: String, texture: Texture2D,
		rect: Rect2, tilt: float) -> void:
	var photo := Polaroid.new()
	photo.name = node_name
	photo.position = rect.position
	photo.size = rect.size
	photo.rotation = tilt
	photo.sky_seed = node_name.hash()
	photo.caption_margin = Polaroid.BORDER
	photo.set_meta("decorative_overhang", true)
	parent.add_child(photo)
	photo.setup(texture, "", Palette.INK)
	photo.subject.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


static func refresh_title(main: Node) -> void:
	var rows: Array = main._title_rows()
	var meta: bool = main.title_mode == "meta"
	var menu: bool = main.title_mode == "menu"
	var credits: bool = main.title_mode == "credits"
	main.title_overlay.chromeless = true
	main.title_overlay.queue_redraw()
	var title_plate: Panel = main.title_overlay.get_node("TitlePlate")
	title_plate.visible = not menu
	title_plate.position = Vector2(232, 56)
	title_plate.size = Vector2(720, 544)
	main.title_overlay.get_node("TitleAmbience").visible = true
	main.title_overlay.get_node("BrandLockup").visible = menu
	main.title_overlay.get_node("SnapshotCollage").visible = menu
	var eyebrow: Label = main.title_overlay.get_node("TitleEyebrow")
	eyebrow.visible = not menu
	eyebrow.text = {
		"modes": "플레이 방식",
		"meta": "영구 성장",
		"settings": "설정",
		"credits": "제작진",
	}.get(main.title_mode, "")
	place(eyebrow, Rect2(264, 74, 656, 50), 34, Palette.INK)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The main page carries no sentence under the menu: every card says what it
	# is. The note is the sub-pages' reading area.
	main.title_note.visible = meta or credits
	if credits:
		main.title_note.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		place(main.title_note, Rect2(280, 140, 624, 352), 19, Palette.INK)
		main.title_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main.title_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	elif meta:
		var note := Palette.surface(Palette.PAPER_SHADE, 3)
		note.shadow_size = 0
		note.set_border_width_all(1)
		note.border_color = Color(Palette.INK_LINE, 0.35)
		note.set_content_margin_all(14)
		main.title_note.add_theme_stylebox_override("normal", note)
		place(main.title_note, Rect2(264, 482, 656, 100), 15, Palette.INK)
		main.title_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		main.title_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for index in main.title_rows.size():
		var row: Label = main.title_rows[index]
		if index >= rows.size():
			row.visible = false
			continue
		# Menu cards are laid crooked on the page; every sub-page is a sheet with
		# straight rows on it.
		row.rotation = 0.0
		row.add_theme_color_override("font_color", Palette.INK)
		if menu:
			var slot: Rect2 = TITLE_MENU_SLOTS[index]
			if main.title_cursor == index:
				slot.position.x += TITLE_MENU_NUDGE
			place(row, slot, 32 if index == 0 else (24 if index < 3 else 21), Palette.INK)
			row.pivot_offset = row.size * 0.5
			row.rotation = TITLE_MENU_TILT[index]
		elif meta:
			if main.meta_reset_pending:
				place(row, Rect2(344, 240 + index * 72, 496, 56), 18)
			elif index < 6:
				var column: int = index % 2
				var grid_row: int = index / 2
				place(row, Rect2(264 + column * 336, 144 + grid_row * 64, 320, 56), 15)
			else:
				place(row, Rect2(264, 352 + (index - 6) * 62, 656, 54), 17)
		elif credits:
			place(row, Rect2(392, 512, 400, 52), 19)
		elif main.title_mode == "modes":
			place(row, Rect2(304, 160 + index * 72, 576, 56), 20)
		else:
			place(row, Rect2(304, 128 + index * 58, 576, 50), 17)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.visible = index < rows.size()
		if not row.visible:
			continue
		var caption := String(rows[index])
		# Toggles carry their own state on the row. A settings list that only
		# names the setting makes a player press it to find out what it was.
		var state: Label = row.get_node("State")
		state.size = Vector2(row.size.x - 22, row.size.y)
		state.text = ""
		if main.title_mode == "settings" and index == 5:
			state.text = main.window_size_label()
			state.add_theme_color_override("font_color", Palette.GOLD_INK)
		elif main.title_mode == "settings" and index in [2, 3]:
			var volume: float = main.feedback.sound_volume if index == 2 else main.feedback.music_volume
			state.text = "%d%%" % roundi(volume * 100.0)
			state.add_theme_color_override("font_color", Palette.GOLD_INK if volume > 0.0 else Palette.MUTED)
		elif main.title_mode == "settings" and index < 7:
			var states := [main.screen_shake_enabled, main.feedback.damage_numbers_enabled,
				false, false, main.settings.large_text_enabled, false,
				main.is_fullscreen()]
			state.text = "● 켜짐" if states[index] else "○ 꺼짐"
			state.add_theme_color_override("font_color", Palette.GOLD_INK if states[index] else Palette.MUTED)
		elif main.title_mode == "meta" and not main.meta_reset_pending and index < 6:
			var entry: Dictionary = MetaProgressionData.UPGRADES[main.meta_page * 6 + index]
			var id := String(entry["id"])
			var rank: int = main.meta_progression.rank(id)
			var price: int = main.meta_progression.cost(id)
			state.text = "Lv.%d/%d    %s" % [rank, int(entry["max_rank"]), "MAX" if price <= 0 else "%d개" % price]
			state.add_theme_color_override("font_color", Palette.GOLD_INK if price <= main.meta_progression.points and price > 0 else Palette.MUTED)
		row.text = ("▶  " if main.title_cursor == index and not menu else "") + caption
		var focused: bool = main.title_cursor == index
		# Paper cards; the one under the cursor is coloured in with a marker and
		# lifted further off the page.
		var style := Palette.paper(TITLE_FOCUS if focused else Palette.PAPER_LIGHT, focused)
		style.set_border_width_all(Palette.BORDER_ACTIVE if focused else Palette.BORDER)
		style.set_content_margin_all(16)
		# The hand is taller than its point size; with the full 16px above and
		# below, a 56px card's minimum height outgrew its slot and pushed the
		# stack's gaps apart.
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		if not menu and not focused:
			style.shadow_offset = Vector2(2, 3)
		row.add_theme_stylebox_override("normal", style)
	match main.title_mode:
		"menu":
			main.title_note.text = ""
		"modes":
			main.title_note.text = ""
		"settings":
			main.title_note.text = ""
			if main.settings.last_save_error != OK:
				main.title_note.visible = true
				main.title_note.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
				place(main.title_note, Rect2(304, 536, 576, 40), 14, Palette.DANGER_INK)
				main.title_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				main.title_note.text = "저장할 수 없습니다. 저장 공간과 폴더 권한을 확인해 주세요."
		"meta":
			if main.meta_reset_pending or main.title_cursor == 7:
				main.title_note.text = "성장 초기화 · 사용한 생선 %d개 전액 환급 · 발견한 무기 기록 유지" % main.meta_progression.refund_value()
			elif main.title_cursor == 6:
				main.title_note.text = "성장 분야 전환    기초: 체력·위력·공속·이동·자력·행운    전문화: 방어·재생·치명·범위·지속·구조"
			else:
				var entry: Dictionary = MetaProgressionData.UPGRADES[main.meta_page * 6 + main.title_cursor]
				main.title_note.text = "보유 %d 달빛 생선    ·    %s\n%s · 단계마다 적용 · 다음 원정부터 반영" % [
					main.meta_progression.points, String(entry["name"]), String(entry["summary"])]
			if main.meta_progression.last_save_error != OK:
				main.title_note.text = "저장할 수 없습니다. 진행 상황은 변경되지 않았어요.\n\n저장 공간과 폴더 권한을 확인한 뒤 다시 시도해 주세요."
		"credits":
			main.title_note.text = "달빛 옥상 간식 수호대\n\n사슬로 묶인 두 고양이가\n달빛 든 옥상을 지키는 2인 협동 서바이버\n\n기획 · 프로그래밍 · 아트    monitari\n엔진    Godot 4\n\n함께 놀아준 모두에게 고맙습니다."
		_:
			main.title_note.text = "두 사람이 함께, 또는 AI 동료와 출발하세요.\n\n게임 시작에서 AI / 로컬 / LAN 모드를 선택하세요."


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
	ambience.setup_backdrop(ScrapbookBackdrop)
	screen.add_child(ambience)
	screen.move_child(ambience, 0)
	var lobby_brand := icon(screen, TitleLogo, Rect2(346, -26, 408, 204))
	lobby_brand.name = "LobbyBrandLockup"
	lobby_brand.set_meta("decorative_overhang", true)
	var prompt := label(screen, "P1과 P2가 연결되면 바로 출발", G.inner(0, 0, 3.5, 4, 5, 0.4), Palette.TYPE_VALUE, Palette.MUTED)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in 2:
		var item: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		item.name = "LobbyPlayer%d" % slot
		place(item, G.inner(0, 0, 0.5 + slot * 6.0, 4.65, 5.5, 1.25), 16, Palette.owner_ink(slot))
		item.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
		var style := item.get_theme_stylebox("normal") as StyleBoxFlat
		style.content_margin_left = 22
		style.content_margin_right = 22
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		var accent := Palette.P1 if slot == 0 else Palette.P2
		var cat_center_x := 147.0 if slot == 0 else 957.0
		var connector := ColorRect.new()
		connector.name = "LobbyConnector%d" % slot
		connector.color = Color(accent, 0.52)
		connector.position = Vector2(cat_center_x, 346)
		connector.size = Vector2(2, item.position.y - 346)
		connector.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(connector)
		var card_mark := ColorRect.new()
		card_mark.name = "LobbyCardAccent%d" % slot
		card_mark.color = Color(accent, 0.88)
		card_mark.position = item.position + Vector2(16, 0)
		card_mark.size = Vector2(item.size.x - 32, 3)
		card_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(card_mark)
	var hint := footer(screen, "P1  WASD / 패드 1    P2  방향키 / 패드 2    ESC / START  나가기")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The lobby is a paper page, unlike the night screens the footer usually sits on.
	hint.add_theme_color_override("font_color", Palette.MUTED)


static func refresh_lobby(main: Node) -> void:
	for slot in 2:
		var item: Label = main.lobby_p1_label if slot == 0 else main.lobby_p2_label
		item.add_theme_stylebox_override("normal",
			Palette.player_surface(slot, not main.lobby_joined[slot], main.lobby_joined[slot]))
		item.modulate.a = 1.0 if main.lobby_joined[slot] else 0.88


static func _characters(main: Node) -> void:
	var screen: Control = main.character_overlay
	screen.chromeless = true
	# The direction sheet is built as native controls: one strict roster strip,
	# two identical dossiers, and a fixed action stack. Nothing is positioned by
	# the length of its text.
	for child in screen.get_children():
		if child is Panel or (child is Label and child.text in ["나", "동료"]):
			screen.remove_child(child)
			child.queue_free()
	place(main.character_title, Rect2(24, 8, 488, 48), 38, Palette.CREAM)
	var backdrop := plate(screen, Rect2(8, 0, 1168, 640), Color("081321e8"))
	backdrop.name = "SelectionBackdrop"
	backdrop.z_index = -1
	main.character_title.text = "오늘 밤의 수호대"
	place(main.character_synergy_label, Rect2(520, 8, 272, 24), 15, Palette.MUTED)
	main.character_synergy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place(main.character_roster_label, Rect2(520, 32, 272, 20), 12, Palette.GOLD)
	main.character_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var title_rule := ColorRect.new()
	title_rule.name = "CharacterTitleRule"
	title_rule.color = Color(Palette.OUTLINE, 0.8)
	title_rule.position = Vector2(24, 56)
	title_rule.size = Vector2(1136, 1)
	title_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(title_rule)
	for index in main.character_catalog.size():
		# 12 x 80px cards + 11 x 8px gutters. The remaining 136px is split into
		# 64px/72px page insets so every edge still lands on the 8px grid.
		var slot_rect := Rect2(64 + index * 88, 64, 80, 104)
		var tile := plate(screen, slot_rect)
		tile.name = "Roster%d" % index
		# A contact sheet of little polaroids, each laid a touch off square.
		tile.pivot_offset = tile.size * 0.5
		tile.rotation = [-0.03, 0.022, -0.012, 0.028, -0.024, 0.014][index % 6]
		var shot := Panel.new()
		shot.name = "Photo"
		shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shot.position = Vector2(6, 6)
		shot.size = Vector2(68, 64)
		shot.add_theme_stylebox_override("panel", Palette.photo(0))
		tile.add_child(shot)
		icon(tile, Icons.survivor(String(main.character_catalog[index]["id"])), Rect2(8, 6, 64, 62))
		var name_label := label(tile, String(main.character_catalog[index]["name"]), Rect2(4, 72, 72, 26), 15)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in 2:
		# Two exact 560px dossiers with a single 16px centre gutter. These values
		# stay on the 8px grid and mirror the approved direction sheet.
		var card := Rect2(24 + slot * 576, 176, 560, 376)
		var x := card.position.x
		var bed := plate(screen, card)
		bed.name = "CharacterPanel%d" % slot
		bed.add_theme_stylebox_override("panel", Palette.player_surface(slot, true))
		screen.move_child(bed, 0)
		preload("res://scripts/ui/neon_growth_ui.gd").trim(
			bed, Palette.P1 if slot == 0 else Palette.P2, false, false)
		# The portrait is a polaroid pinned to the dossier: night-sky photograph,
		# white print border, turned a little off the page.
		var portrait_bed := plate(screen,
			Rect2(x + 16, card.position.y + 48, 160, 216), Palette.NIGHT_RAISED)
		portrait_bed.name = "CatPortraitBed%d" % slot
		portrait_bed.add_theme_stylebox_override("panel", Palette.photo(8))
		portrait_bed.pivot_offset = portrait_bed.size * 0.5
		portrait_bed.rotation = -0.03 if slot == 0 else 0.03
		var portrait: TextureRect = main.character_portrait_icons[slot]
		screen.move_child(portrait, screen.get_child_count() - 1)
		portrait.position = Vector2(x + 24, card.position.y + 56)
		portrait.size = Vector2(144, 200)
		# Same centre as the print, so the cat turns with the photo it is in.
		portrait.pivot_offset = portrait.size * 0.5
		portrait.rotation = portrait_bed.rotation
		label(screen, "%s" % main.player_label(slot),
			Rect2(x + 16, card.position.y + 8, 160, 32), 24,
			Palette.owner_ink(slot)).name = "CatNumber%d" % slot
		var heading := label(screen, "",
			Rect2(x + 192, card.position.y + 44, 352, 44), 34)
		heading.name = "CatName%d" % slot
		var status := label(screen, "", Rect2(x + 320, card.position.y + 8, 224, 32), 15,
			Palette.owner_ink(slot))
		status.name = "CatStatus%d" % slot
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var weapon_art := icon(screen, null,
			Rect2(x + 192, card.position.y + 184, 40, 40))
		weapon_art.name = "CatWeapon%d" % slot
		var role := label(screen, "",
			Rect2(x + 192, card.position.y + 88, 352, 32), 14, Palette.MUTED)
		role.name = "CatRole%d" % slot
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Four cells of STAT_CELL form the default stat row. The second row uses
		# the same template in detailed mode instead of hand-offset labels.
		#
		# The cell is sized from the longest thing it can ever hold rather than
		# from the shortest. "범위 118%" is 49px of Jua at this size and the text
		# box used to be 40px, so every survivor whose 위력, 공속, 범위 or 치명
		# reached three digits had its percent sign cut off — which is to say the
		# clipping fell exactly on the cats the number was worth reading for.
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var entry: Dictionary = CharacterCatalog.DISPLAYED_STATS[stat]
			var column := stat % 4
			var row := stat / 4
			var cell_x := x + 192.0 + column * STAT_STRIDE
			var cell_y := card.position.y + 128.0 + row * 48.0
			var stat_bed := plate(screen, Rect2(cell_x, cell_y, STAT_CELL, 40), Palette.NIGHT_RAISED)
			stat_bed.name = "CatStatBed%d_%d" % [slot, stat]
			stat_bed.add_theme_stylebox_override("panel", _chip_surface())
			icon(screen, Icons.upgrade(String(entry["icon"])),
				Rect2(cell_x + 6.0, cell_y + 11.0, STAT_ICON, STAT_ICON)
			).name = "CatStatIcon%d_%d" % [slot, stat]
			var value := label(screen, "", Rect2(
				cell_x + 6.0 + STAT_ICON + 4.0, cell_y + 4.0,
				STAT_CELL - STAT_ICON - 16.0, 32), 11)
			value.name = "CatStat%d_%d" % [slot, stat]
		var body: Label = main.character_p1_label if slot == 0 else main.character_p2_label
		place(body, Rect2(x + 240, card.position.y + 176, 304, 88), 14)
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The one number the pair is actually choosing. A survivor's leash shows up on
	# their own card as a word, which says what that cat contributes but never
	# what the two of them add up to, and the leash is the constraint the whole
	# run is played against. It sits on the pair row under both dossiers, next to
	# the synergy line, because it belongs to neither cat on its own.
	var leash := plate(screen, Rect2(24, 560, 280, 32))
	leash.name = "ChainPlate"
	icon(leash, Icons.upgrade("resolve"), Rect2(8, 4, 24, 24))
	label(leash, "연결 거리", Rect2(40, 4, 88, 24), 12, Palette.MUTED)
	var leash_value := label(leash, "", Rect2(144, 4, 120, 24), 17)
	leash_value.name = "ChainLength"
	place(main.character_synergy_label,
		Rect2(312, 560, 848, 32),
		Palette.TYPE_BODY, Palette.NIGHT_MUTED)
	main.character_synergy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer(screen, "나 A / D 이동    [W] 준비     동료 ← / → 이동    [↑] 준비     ESC / B 나가기")


## A recessed chip of darker paper written on the card itself — a stat, a
## count — rather than a piece laid on top of it, so no shadow and a faint edge.
static func _chip_surface() -> StyleBoxFlat:
	var chip := Palette.surface(Palette.PAPER_SHADE, 3)
	chip.shadow_size = 0
	chip.set_border_width_all(1)
	chip.border_color = Color(Palette.INK_LINE, 0.28)
	return chip


static func refresh_characters(main: Node) -> void:
	preload("res://scripts/ui/player_perspective.gd").restore_characters(main)
	var screen: Control = main.character_overlay
	var detailed := bool(screen.get_meta("show_details", false))
	if screen.has_node("CharacterDetails"):
		screen.get_node("CharacterDetails").text = "간단 보기    TAB / X" if detailed else "능력치 보기    TAB / X"
	if main.ai_companion:
		main.character_roster_label.text = "클릭으로 나 선택    AI는 조합에 맞춰 자동 선택"
	elif main.online != null and main.online.is_client():
		main.character_roster_label.text = "클릭으로 내 캐릭터 선택    동료는 직접 선택"
	elif main.online != null and main.online.is_host():
		main.character_roster_label.text = "클릭으로 내 캐릭터 선택    동료 선택을 기다리는 중"
	else:
		main.character_roster_label.text = "클릭 나    우클릭 동료"
	for slot in 2:
		var cat: Dictionary = main.character_catalog[main.selected_character_indices[slot]]
		screen.get_node("CatName%d" % slot).text = String(cat["name"])
		screen.get_node("CatStatus%d" % slot).text = "준비 완료" if main.character_confirmed[slot] else ("AI 동료" if main.ai_companion and slot != main.local_view_slot() else "캐릭터 선택 중")
		screen.get_node("CatWeapon%d" % slot).texture = Icons.weapon(String(cat["weapon_id"]))
		# The breed line, not the weapon line. Ten cats used to be introduced by
		# what their weapon does and two by who they are, because only the two
		# newest had no PLAYSTYLE entry to override them. The weapon still
		# describes itself on the level-up card and in the block below.
		screen.get_node("CatRole%d" % slot).text = "%s  ·  조작 난이도 %s" % [String(cat["title"]), CharacterCatalog.difficulty_stars(cat)]
		screen.get_node("CatRole%d" % slot).tooltip_text = cat["description"]
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var entry: Dictionary = CharacterCatalog.DISPLAYED_STATS[stat]
			screen.get_node("CatStat%d_%d" % [slot, stat]).text = CharacterCatalog.stat_text(cat, String(entry["field"]))
			screen.get_node("CatStat%d_%d" % [slot, stat]).visible = detailed or stat < 4
			screen.get_node("CatStatIcon%d_%d" % [slot, stat]).visible = detailed or stat < 4
			screen.get_node("CatStatBed%d_%d" % [slot, stat]).visible = detailed or stat < 4
		var body: Label = main.character_p1_label if slot == 0 else main.character_p2_label
		var panel: Panel = screen.get_node("CharacterPanel%d" % slot)
		var x := panel.position.x
		var portrait: TextureRect = main.character_portrait_icons[slot]
		var portrait_bed: Panel = screen.get_node("CatPortraitBed%d" % slot)
		if detailed:
			portrait_bed.position = Vector2(x + 16, panel.position.y + 48)
			portrait_bed.size = Vector2(160, 216)
			portrait.position = Vector2(x + 24, panel.position.y + 56)
			portrait.size = Vector2(144, 200)
			# The detailed view is where the plan goes: which final form this
			# starting weapon is on and what completes it. Choosing a cat is
			# choosing that route, and this is the screen where it is chosen.
			body.text = "%s\n%s\n연결 특성  ·  %s" % [
				String(cat["description"]), main._route_note(cat), main._chain_note(cat)]
			# 392..444 in screen terms: the second stat row ends at 392 and the
			# navigation buttons start at 448, so this is the whole of the room
			# there is. Three lines of 10 fit the Gowoon metrics; larger text did not, and the
			# box ran into 이전 / 다음.
			place(body, Rect2(x + 192, panel.position.y + 216, 352, 52), 10)
		else:
			portrait_bed.position = Vector2(x + 16, panel.position.y + 48)
			portrait_bed.size = Vector2(160, 216)
			portrait.position = Vector2(x + 24, panel.position.y + 56)
			portrait.size = Vector2(144, 200)
			body.text = "시작 무기  ·  %s\n%s\n\n%s" % [String(cat["weapon_name"]), String(PLAYSTYLE.get(String(cat["weapon_id"]), "자동 공격")), main._chain_note(cat)]
			place(body, Rect2(x + 240, panel.position.y + 176, 304, 88), 14)
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_theme_stylebox_override("panel",
			Palette.player_surface(slot, not main.character_confirmed[slot], main.character_confirmed[slot]))
		# Tape in the owner's colour; the marker ring circles a dossier once that
		# survivor is ready, the way you would circle a pick on a printed sheet.
		preload("res://scripts/ui/neon_growth_ui.gd").trim(panel,
			Palette.P1 if slot == main.local_view_slot() else Palette.P2,
			main.character_confirmed[slot], false)
		if screen.has_node("CharacterConfirm%d" % slot):
			var confirm: Button = screen.get_node("CharacterConfirm%d" % slot)
			confirm.disabled = not main._can_control_player_slot(slot)
			var confirm_key := "W" if slot == 0 else "↑"
			confirm.text = ("✓  준비 완료" if main.character_confirmed[slot] else "준비하기") + "    [%s]" % confirm_key
			confirm.add_theme_stylebox_override("normal",
				Palette.button_surface("normal", Palette.P1 if slot == 0 else Palette.P2, true))
		for action in ["CharacterPrevious%d" % slot, "CharacterNext%d" % slot]:
			if screen.has_node(action):
				(screen.get_node(action) as Button).disabled = not main._can_control_player_slot(slot)
	# One number for the two of them, read after both dossiers are refreshed:
	# it is the pair that has a leash, not either cat on its own.
	var pair_leash := CharacterCatalog.chain_length_for(
		main.character_catalog[main.selected_character_indices[0]],
		main.character_catalog[main.selected_character_indices[1]])
	# Resonance is the one system nothing on this screen asks the pair to do, and
	# a first-time player has no way to know it happens on its own. It rides the
	# pair line in the detailed view — it is a fact about the two of them, and the
	# default screen stays a portrait and four numbers.
	# Rebuilt rather than appended: this runs on every refresh, and appending
	# would grow the line a clause at a time as the cursor walks the roster.
	main.character_synergy_label.text = ("%s    ·    두 무기가 Lv.7에 이르면 공명 후보가 열립니다"
		% main._synergy_preview()) if detailed else main._synergy_preview()
	var leash_grade := "짧음" if pair_leash < 288.0 else ("보통" if pair_leash < 352.0 else "넓음")
	screen.get_node("ChainPlate/ChainLength").text = "%s  ·  %d" % [leash_grade, roundi(pair_leash)]
	for index in main.character_catalog.size():
		var tile: Panel = screen.get_node("Roster%d" % index)
		var style := tile.get_theme_stylebox("panel") as StyleBoxFlat
		var p1: bool = main.selected_character_indices[0] == index
		var p2: bool = main.selected_character_indices[1] == index
		style.border_color = Palette.P1_INK if p1 else (Palette.P2_INK if p2 else Palette.INK_LINE)
		style.set_border_width_all(Palette.BORDER_ACTIVE if p1 or p2 else Palette.BORDER)
		style.bg_color = Palette.CARD.lerp(Palette.P1 if p1 else Palette.P2, 0.3) if p1 or p2 else Palette.CARD
		# Only a picked print gets taped down; the rest of the sheet stays loose.
		preload("res://scripts/ui/neon_growth_ui.gd").trim(tile,
			Palette.P1 if p1 else (Palette.P2 if p2 else Color.TRANSPARENT),
			p1 or p2)

	preload("res://scripts/ui/player_perspective.gd").characters(main)
	for slot in 2:
		var cat: Dictionary = main.character_catalog[main.selected_character_indices[slot]]
		_animate_character_choice(screen.get_node("CharacterPanel%d" % slot),
			screen.get_node("CatName%d" % slot), main.character_portrait_icons[slot],
			String(cat["id"]))



static func _animate_character_choice(panel: Control, name_label: Control,
		portrait: Control, character_id: String) -> void:
	if String(panel.get_meta("shown_character", "")) == character_id:
		return
	panel.set_meta("shown_character", character_id)
	portrait.pivot_offset = portrait.size * 0.5
	name_label.pivot_offset = name_label.size * 0.5
	portrait.scale = Vector2.ONE * 0.78
	name_label.modulate.a = 0.25
	var tween := panel.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait, "scale", Vector2.ONE, 0.24)
	tween.tween_property(name_label, "modulate:a", 1.0, 0.16)


## What a hand needs beyond the painted cards: each card's tooltip, and the
## reroll button's state. Layout and painting are NeonGrowthUI's.
static func refresh_growth(main: Node, slot: int) -> void:
	var complete: bool = main.selected_upgrade_indices[slot] == -2
	var locked: bool = main.selected_upgrade_indices[slot] >= 0
	var choices: Array = main.p1_choices if slot == 0 else main.p2_choices
	for index in choices.size():
		var option: Dictionary = choices[index]
		var card: Label = main.level_card_labels[slot][index]
		var against := bool(option.get("discouraged", false))
		var reason := String(option.get("discouragement_reason" if against else "recommendation_reason", ""))
		card.tooltip_text = "%s\n%s\n%s" % [String(option["title"]), main._upgrade_preview(slot, option),
			reason if not reason.is_empty() else "현재 구성에서 무난한 선택입니다."]
	var reroll: Button = main.level_overlay.get_node_or_null("Reroll%d" % slot)
	if reroll != null:
		var tech_hand := not choices.is_empty() and choices.all(func(option: Dictionary) -> bool: return String(option["id"]) == "choose_tech")
		reroll.visible = slot == main.focused_growth_slot() and not locked and not complete and not tech_hand and main.rerolls_remaining[slot] > 0
		reroll.disabled = main.level_up_input_delay > 0.0
		reroll.text = "↻  다시 뽑기    %d" % main.rerolls_remaining[slot]


## The small heading over a growth card's art.
static func growth_category(option: Dictionary) -> String:
	match String(option["id"]):
		"choose_tech":
			return {
				"force": "공격 변형", "tempo": "공격 변형",
				"control": "영역 변형", "balanced": "협동 변형",
			}.get(String((option["tech"] as Dictionary).get("profile", "balanced")), "테크 결정")
		"unlock_treasure":
			return "새 보물"
		"treasure_upgrade":
			return "보물 강화"
		"unlock_weapon":
			return "새 무기"
	return "무기 강화"


## The card title: the option's own title without the prefix the category
## heading already says.
static func growth_title(option: Dictionary) -> String:
	return String(option.get("title", "")).replace("새 보물: ", "").replace("신규 기술: ", "").replace("보물 강화: ", "").replace("무기 진화: ", "")


static func compact_growth_description(option: Dictionary) -> String:
	var description := String(option.get("description", ""))
	if String(option.get("id", "")) not in ["unlock_treasure", "treasure_upgrade"]:
		return description
	return description.replace(
		"투사체  장판 지속시간", "투사체  장판 지속").replace(
		"가한 피해 0.6%를 팀 체력으로 회복    초당 최대 1.5",
		"피해의 0.6% 팀 회복\n초당 최대 +1.5")


## The resonance vote is a growth screen now (see main._refresh_resonance_vote_ui),
## so this pass places its captions the way the growth screen's are placed and
## leaves the cards alone: they are full growth cards, fanned and painted every
## refresh by CardVisual, and a layout pass that repositioned and restyled them
## here would be a second opinion about a card the refresh is already drawing.
## The footer rule is gone with the panel frame for the same reason — there is a
## paused fight behind this screen and a horizontal line drawn across it reads as
## a seam in the world rather than as a divider in a window.
static func _resonance(main: Node) -> void:
	var screen: Control = main.resonance_overlay
	place(main.resonance_title,
		Rect2(0, 2, screen.size.x, 34), Palette.TYPE_TITLE, Palette.GOLD)
	main.resonance_title.text = "함께 쓰는 필살기 — 하나를 고르세요"
	main.resonance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for child in screen.get_children():
		if child is Label and String(child.text).begins_with("보스가 남긴"):
			child.name = "ResonanceSubtitle"
			place(child, Rect2(0, 36, screen.size.x, 22), Palette.TYPE_CAPTION, Palette.NIGHT_MUTED)
			(child as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place(main.resonance_status, Rect2(300, 468, screen.size.x - 600.0, 44),
		Palette.TYPE_BODY, Palette.NIGHT_MUTED)
	main.resonance_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Bottom-right, where the growth screen's own controls line sits, and clear
	# of the full-width XP bar the band is standing on.
	var controls: Label = screen.get_node_or_null("ResonanceControls")
	if controls != null:
		place(controls, Rect2(825, 518, 425, 24), Palette.TYPE_CAPTION, Palette.NIGHT_MUTED)
		controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


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
		var x := 76.0 if slot == 0 else 884.0
		var accent := Palette.P1 if slot == 0 else Palette.P2
		bar.position = Vector2(x, 27)
		bar.size = Vector2(320, 22)
		var track := Palette.surface(Palette.NIGHT)
		track.border_color = Palette.OUTLINE
		var fill := Palette.surface(Palette.P1 if slot == 0 else Palette.P2, Palette.RADIUS)
		fill.set_border_width_all(0)
		bar.add_theme_stylebox_override("background", track)
		bar.add_theme_stylebox_override("fill", fill)
		caption.position = bar.position
		caption.size = bar.size
		caption.add_theme_font_override("font", ReadoutFont)
		caption.add_theme_font_size_override("font_size", 15)
		caption.add_theme_color_override("font_color", Color.WHITE)
		caption.add_theme_color_override("font_outline_color", Color("071125"))
		caption.add_theme_constant_override("outline_size", 2)
		main.hud_portrait_icons[slot].position = Vector2(24 if slot == 0 else 1212, 16)
		main.hud_portrait_icons[slot].size = Vector2(44, 44)
		var number := label(main.combat_hud, "%s" % main.player_label(slot), Rect2(x + 58, 11, 32, 20), 13, accent)
		number.name = "PlayerNumber%d" % slot
		var identity := label(main.combat_hud, "", Rect2(x + 94, 9, 278, 24), 16, accent)
		identity.name = "PlayerIdentity%d" % slot
		for tag: Label in [number, identity]:
			tag.add_theme_font_override("font", ReadoutFont)
	# Three readings, three equal columns, one shape each. The strip used to hold
	# two meters and a loose string ("공명 1/3") beside them, so the one reading
	# that is a count of things the pair owns was the one you had to read rather
	# than see — in a row that had already taught the eye to expect bars.
	var strip_left := SHARED_LEFT + 18.0
	var strip_width := SHARED_WIDTH - 36.0
	var column := (strip_width - METER_GAP * 2.0) / 3.0
	var columns: Array[float] = [
		strip_left,
		strip_left + column + METER_GAP,
		strip_left + (column + METER_GAP) * 2.0,
	]
	for item in [main.chain_bar, main.chain_distance_text_label]:
		item.position = Vector2(columns[0], SHARED_TOP + 43.0)
		item.size = Vector2(column, 18)
	for item in [main.chain_integrity_bar, main.chain_integrity_text_label]:
		item.position = Vector2(columns[2], SHARED_TOP + 43.0)
		item.size = Vector2(column, 18)
	# Put text above thin meters so a full bright fill cannot wash out its label.
	# The shared strip is a paper note taped to the top of the screen, so its
	# readings are written in ink.
	for caption: Label in [main.chain_distance_text_label, main.chain_integrity_text_label]:
		caption.position.y = SHARED_TOP + 37.0
		caption.add_theme_font_override("font", ReadoutFont)
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", Palette.INK)
		caption.add_theme_constant_override("outline_size", 0)
	for meter: ProgressBar in [main.chain_bar, main.chain_integrity_bar]:
		meter.position.y = SHARED_TOP + 60.0
		meter.size.y = 6
		var track := Palette.surface(Color(Palette.INK, 0.16), 3)
		track.set_border_width_all(0)
		meter.add_theme_stylebox_override("background", track)
		var meter_fill := Palette.surface(Palette.GOLD.darkened(0.12), 3)
		meter_fill.set_border_width_all(0)
		meter.add_theme_stylebox_override("fill", meter_fill)
	place(main.resonance_status_label, Rect2(columns[1], SHARED_TOP + 37.0, column, 20), 14, Palette.P2_INK)
	main.resonance_status_label.add_theme_font_override("font", ReadoutFont)
	main.resonance_status_label.add_theme_constant_override("outline_size", 0)
	main.resonance_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.resonance_status_label.visible = true
	if main.resonance_pips != null:
		main.resonance_pips.position = Vector2(columns[1], SHARED_TOP + 60.0)
		main.resonance_pips.size = Vector2(column, 6)
	place(main.chain_status_label, Rect2(strip_left, SHARED_TOP + 72.0, strip_width, 20), 14, Palette.MUTED)
	main.chain_status_label.add_theme_font_override("font", ReadoutFont)
	main.chain_status_label.add_theme_constant_override("outline_size", 0)
	main.chain_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Clear of the shared frame (8..104) rather than tucked against it: the boss
	# bar paints its own name, rank pips and numbers in a strip above the fill,
	# and that strip needs room that the frame's bottom edge was taking.
	main.boss_label.add_theme_color_override("font_color", Color("f0cca2"))
	place(main.boss_label, Rect2(G.x(3.9), 128, G.w(1.8), 22), 13, Palette.CREAM)
	main.boss_label.visible = false
	main.boss_bar.position = Vector2(SHARED_LEFT, SHARED_TOP + 112.0)
	main.boss_bar.size = Vector2(SHARED_WIDTH, 44.0)
	main.boss_health_text_label.position = main.boss_bar.position
	main.boss_health_text_label.size = Vector2(500.0, 22.0)
	main.boss_health_text_label.add_theme_font_override("font", ReadoutFont)
	main.boss_health_text_label.add_theme_font_size_override("font_size", 16)
	main.xp_bar.position = Vector2(0, 690)
	main.xp_bar.size = Vector2(1280, 30)
	main.xp_bar.add_theme_stylebox_override("background", Palette.surface(Color("17263a99")))
	var xp_fill := Palette.surface(Palette.GOLD)
	xp_fill.set_border_width_all(0)
	main.xp_bar.add_theme_stylebox_override("fill", xp_fill)
	place(main.xp_text_label, Rect2(0, 690, 1280, 30), 16, Palette.CREAM)
	main.xp_text_label.add_theme_font_override("font", ReadoutFont)
	main.xp_text_label.add_theme_color_override("font_outline_color", Color("071125"))
	main.xp_text_label.add_theme_constant_override("outline_size", 4)
	main.xp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.xp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The clock is the page's centre line, so it is centred on the content span
	# rather than snapped to a column edge — 48..1232 has its middle at 640.
	place(main.hud_label, Rect2(574, SHARED_TOP + 1.0, 132, 38), 34, Palette.INK)
	main.hud_label.add_theme_font_override("font", ReadoutFont)
	main.hud_label.add_theme_constant_override("outline_size", 0)
	main.hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wave_readout := label(main.combat_hud, "", Rect2(SHARED_LEFT + 274.0, SHARED_TOP + 10.0, 152, 25), 16, Palette.INK)
	wave_readout.name = "WaveReadout"
	wave_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var objective_readout := label(main.combat_hud, "", Rect2(SHARED_LEFT + 18.0, SHARED_TOP + 10.0, 166, 25), 16, Palette.GOLD_INK)
	objective_readout.name = "ObjectiveReadout"
	for readout: Label in [wave_readout, objective_readout]:
		readout.add_theme_font_override("font", ReadoutFont)
		readout.add_theme_constant_override("outline_size", 0)
	# What each survivor carries, directly under their health bar: weapons on the
	# first row, treasures on the second, only what has actually been picked up,
	# each with its level in the bottom-right corner.
	for slot in 2:
		var holder := Control.new()
		holder.size = Vector2(CARRIED_PITCH * float(main.WEAPON_LOADOUT_CAP) - (CARRIED_PITCH - CARRIED_CELL),
			CARRIED_PITCH + CARRIED_CELL)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.name = "Carried%d" % slot
		main.combat_hud.add_child(holder)
		var cap: int = int(main.WEAPON_LOADOUT_CAP)
		for row in ["Weapon", "Treasure"]:
			var weapon_row: bool = row == "Weapon"
			for index in cap:
				var socket := plate(holder, Rect2(0, 0, CARRIED_CELL, CARRIED_CELL), Palette.NIGHT)
				socket.name = "%sSlot%d" % [row, index]
				# No border of its own: the cooldown ring traces this box's edge and
				# is the border (see equipment_border.gd), so the two can no longer
				# disagree at the corners.
				var style := Palette.surface(Color("0b1628e6"), 8)
				style.set_border_width_all(0)
				socket.add_theme_stylebox_override("panel", style)
				var art := icon(holder, null, Rect2(0, 0, CARRIED_CELL - 4, CARRIED_CELL - 4))
				art.name = "%s%d" % [row, index]
				# The level is a small chip hung on the corner rather than a number
				# printed across the art.
				var tier := label(art, "", Rect2(CARRIED_CELL - 20, CARRIED_CELL - 17, 16, 13), 10, Palette.CREAM)
				tier.add_theme_font_override("font", ReadoutFont)
				var chip := Palette.surface(Color("08111fee"), 5)
				chip.border_color = Color(Palette.OUTLINE, 0.9)
				chip.content_margin_left = 2
				chip.content_margin_right = 2
				tier.add_theme_stylebox_override("normal", chip)
				tier.z_index = 2
				var border := preload("res://scripts/ui/equipment_border.gd").new()
				border.name = "CooldownBorder"
				border.game = main
				border.owner_slot = slot
				border.item_slot = index
				border.weapon = weapon_row
				border.size = Vector2(CARRIED_CELL, CARRIED_CELL)
				socket.add_child(border)
				tier.name = "Tier"
				tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		layout_carried(holder, slot == 1)
	var alert := plate(main.combat_hud, Rect2(388, 650, 504, 46), Palette.NIGHT_PANEL)
	alert.name = "TacticalAlert"
	alert.hide()
	var action := label(alert, "", Rect2(14, 4, 476, 38), 19, Palette.CREAM)
	action.name = "Action"
	action.add_theme_font_override("font", ReadoutFont)
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER



## Space between the three readings in the shared HUD strip.
const METER_GAP := 14.0
## The shared strip's box. Everything in it — the clock, the two readouts, the
## three meters and the boss bar under it — is placed from these, so the strip
## can be nudged without three separate lists of magic numbers drifting apart.
const SHARED_LEFT := 418.0
const SHARED_TOP := 16.0
const SHARED_WIDTH := 444.0
const CARRIED_CELL := 34.0
const CARRIED_PITCH := 38.0


## Places a carried-equipment ribbon's cells. Mirrored for the survivor on the
## right, whose health bar also fills from the right: their first item sits
## nearest their own portrait, just as it does on the left.
static func layout_carried(holder: Control, mirrored: bool) -> void:
	if holder.has_meta("mirrored") and bool(holder.get_meta("mirrored")) == mirrored:
		return
	holder.set_meta("mirrored", mirrored)
	for row in ["Weapon", "Treasure"]:
		var y := 0.0 if row == "Weapon" else CARRIED_PITCH
		var index := 0
		while holder.has_node("%s%d" % [row, index]):
			var x := float(index) * CARRIED_PITCH
			if mirrored:
				x = holder.size.x - CARRIED_CELL - x
			holder.get_node("%sSlot%d" % [row, index]).position = Vector2(x, y)
			holder.get_node("%s%d" % [row, index]).position = Vector2(x + 2.0, y + 2.0)
			index += 1


## Native panels share menu geometry. The survivor portrait used to sit on a
## cream plaque of its own; the plaque lost its fill when the HUD went
## translucent and what was left was a 40x40 panel drawing a 1px outline at a
## third alpha over a dark roof — invisible, referenced by nothing, and still a
## Control in the frame. The portrait stands on the frame itself now.
static func _install_hud_frames(main: Node) -> void:
	for slot in 2:
		var x := 14.0 if slot == 0 else 874.0
		var panel := plate(main.combat_hud, Rect2(x, 8, 392, 124), Palette.HUD)
		panel.name = "P%dFrame" % (slot + 1)
		panel.z_index = -2
		panel.hide()
		var style := Palette.surface(Palette.HUD)
		style.border_color = Color(Palette.P1 if slot == 0 else Palette.P2, 0.42)
		panel.add_theme_stylebox_override("panel", style)
		var paw := icon(panel, HudPaw, Rect2(374, 98, 12, 12))
		paw.modulate = Palette.P1.darkened(0.22) if slot == 0 else Palette.P2.darkened(0.22)
	# Its last line (chain status, y 77..97) is the bottom of what it holds; the
	# 116px box left an empty strip under it.
	# y=16 rather than y=8: this frame wears the cat ears, and they stand ~14px
	# proud of the panel — at 8 the tips were cut off by the top of the screen,
	# which read as the HUD being clipped rather than as a decoration.
	var shared := plate(main.combat_hud, Rect2(SHARED_LEFT, SHARED_TOP, SHARED_WIDTH, 98), Palette.HUD)
	shared.name = "SharedFrame"
	shared.z_index = -2
	# The one piece of paper on the fight: a note taped across the top of the
	# screen with the clock and the pair's shared readings written on it.
	var shared_style := Palette.paper(Color(Palette.PAPER_LIGHT, 0.96), true)
	shared_style.border_color = Color(Palette.INK_LINE, 0.72)
	shared_style.set_border_width_all(2)
	shared_style.shadow_color = Color(Palette.PAPER_SHADOW, 0.82)
	shared_style.shadow_size = 7
	shared_style.shadow_offset = Vector2(0, 4)
	shared.add_theme_stylebox_override("panel", shared_style)
	preload("res://scripts/ui/neon_growth_ui.gd").trim(shared, Palette.TAPE, false, false)


static func refresh_hud(main: Node) -> void:
	preload("res://scripts/ui/player_perspective.gd").hud(main)
	_refresh_tactical_alert(main)
	main.hud_label.text = "%02d:%02d" % [int(main.elapsed) / 60, int(main.elapsed) % 60]
	main.xp_text_label.text = "LV.%d    XP %d / %d" % [main.progression.level, int(main.progression.experience), int(main.progression.required_experience)]
	main.combat_hud.get_node("WaveReadout").text = "%s    %d 처치" % ["휴식" if main.wave_director.in_calm else "%d파" % maxi(1, main.wave_director.wave_index + 1), main.kills]
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
		var health: ProgressBar = main.p1_health_bar if slot == 0 else main.p2_health_bar
		var fill := health.get_theme_stylebox("fill") as StyleBoxFlat
		var endangered: bool = main.players[slot].downed or main.players[slot].health <= main.players[slot].max_health * 0.25
		UIWrite.bg_color(fill, Color("c65567") if endangered else (
			Palette.P1 if slot == main.local_view_slot() else Palette.P2))
		main.combat_hud.get_node("PlayerIdentity%d" % slot).text = ""
		holder.visible = not bool(holder.get_meta("compact", false)) and not (main.resonance_vote_active or main.pause_active or main.game_over)
		_refresh_carried_row(holder, "Weapon", main.weapon_loadouts[slot], true)
		_refresh_carried_row(holder, "Treasure", main.treasure_loadouts[slot], false)
		var frame: Control = main.combat_hud.get_node("P%dFrame" % (slot + 1))
		frame.size.y = (76.0 if slot == main.local_view_slot() else 68.0) if main.level_up_active else 124.0
		frame.hide()


## Explicit level captions distinguish equipment levels from item quantities.
static func _refresh_carried_row(holder: Control, prefix: String, carried: Array,
		is_weapon: bool) -> void:
	var index := 0
	while holder.has_node("%s%d" % [prefix, index]):
		var art: TextureRect = holder.get_node("%s%d" % [prefix, index])
		art.visible = index < carried.size()
		holder.get_node("%sSlot%d" % [prefix, index]).visible = art.visible
		if not art.visible:
			index += 1
			continue
		var entry: Dictionary = carried[index]
		UIWrite.texture(art, Icons.weapon(String(entry["weapon_id"])) if is_weapon else Icons.upgrade(String(entry["id"])))
		art.modulate = Color.WHITE
		var tier: Label = art.get_node("Tier")
		tier.text = str(int(entry.get("tier", 1)))
		art.mouse_filter = Control.MOUSE_FILTER_PASS
		UIWrite.tooltip(art, "%s    Lv.%d" % [String(entry.get("weapon_name", entry.get("name", "보물"))), int(entry.get("tier", 1))])
		# The socket's own border sets the tier colour (gold while resonating) and
		# refreshes itself every frame; writing CREAM here as well made the two
		# fight over the same label once per tick, and each write re-shaped it.
		holder.get_node("%sSlot%d/CooldownBorder" % [prefix, index]).refresh()
		index += 1


## One actionable message, ordered by urgency. No blinking or permanent warning.
static func _refresh_tactical_alert(main: Node) -> void:
	var alert: Panel = main.combat_hud.get_node("TacticalAlert")
	var message := ""
	if main.players[0].downed or main.players[1].downed:
		var slot := 0 if main.players[0].downed else 1
		message = "%s 구조 필요    동료 곁에 머무르세요" % main.player_label(slot)
	elif main.chain_overloaded:
		message = "사슬 과부하    서로 가까이 붙으세요"
	elif main.chain_bar.value >= 95.0:
		message = "사슬 한계    두 고양이의 거리를 줄이세요"
	elif main.players[0].health <= main.players[0].max_health * 0.25 or main.players[1].health <= main.players[1].max_health * 0.25:
		var slot := 0 if main.players[0].health <= main.players[0].max_health * 0.25 else 1
		message = "%s 체력 위험    적과 거리를 벌리세요" % main.player_label(slot)
	elif main.chain_integrity < 40.0:
		message = "사슬 내구 부족    가까이 붙어 회복하세요"
	alert.visible = not message.is_empty() and not (main.level_up_active or main.resonance_vote_active or main.pause_active or main.game_over)
	alert.get_node("Action").text = message
	var style := alert.get_theme_stylebox("panel") as StyleBoxFlat
	UIWrite.border_color(style, Color("f09a8b"))
	if style.border_width_left != 4:
		style.border_width_left = 4


static func _results(main: Node) -> void:
	var screen: Control = main.result_overlay
	var wide := screen.size.x - G.GUTTER * 2.0
	label(screen, "", Rect2(G.GUTTER, 18, wide, 40), Palette.TYPE_TITLE).name = "ResultHeading"
	label(screen, "", Rect2(G.GUTTER, 58, wide, 26), Palette.TYPE_BODY, Palette.MUTED).name = "ResultReason"
	var highlight := label(screen, "", Rect2(G.GUTTER, 87, wide, 28), 18, Palette.GOLD_INK)
	highlight.name = "ResultHighlight"
	highlight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in 3:
		# Three metric tiles across the dialogue, sharing one gutter each.
		var tile := plate(screen, G.slice(Rect2(G.GUTTER, 120, wide, 112), 3, index))
		var ids := ["move", "might", "growth"]
		var names := ["생존 시간", "처치", "공유 레벨"]
		icon(tile, Icons.upgrade(ids[index]), Rect2(18, 14, 32, 32))
		label(tile, names[index], Rect2(60, 17, tile.size.x - 76.0, 28), 15, Palette.MUTED)
		label(tile, "", Rect2(20, 52, tile.size.x - 40.0, 52), Palette.TYPE_METRIC).name = "Value"
		tile.name = "ResultMetric%d" % index
	for slot in 2:
		var half := G.slice(Rect2(G.GUTTER, 244, wide, 150), 2, slot)
		var x := half.position.x
		var tile := plate(screen, half)
		screen.move_child(tile, 0)
		var portrait: TextureRect = screen.get_node("ResultCat%d" % slot)
		portrait.position = Vector2(x + G.GUTTER, 260)
		portrait.size = Vector2(64, 64)
		label(screen, "", Rect2(x + 92, 256, half.size.x - 108, 26), 20, Palette.owner_ink(slot)).name = "ResultName%d" % slot
		var player_stats := label(screen, "", Rect2(x + 92, 285, half.size.x - 108, 40), 12, Palette.MUTED)
		player_stats.name = "ResultPlayerStats%d" % slot
		player_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for index in 4:
			var weapon_x := x + 92 + index * 82
			icon(screen, null, Rect2(weapon_x, 330, 44, 44)).name = "ResultWeapon%d_%d" % [slot, index]
			var dps := label(screen, "", Rect2(weapon_x - 9, 374, 62, 20), 12, Palette.MUTED)
			dps.name = "ResultWeaponDps%d_%d" % [slot, index]
			dps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(screen, "함께 지킨 기록    획득물", Rect2(G.GUTTER, 406, wide, 22), 16, Palette.GOLD_INK)
	var coop := label(screen, "", Rect2(G.GUTTER, 430, wide, 44), 15, Palette.MUTED)
	coop.name = "CoopRecord"
	coop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var meta_title := label(screen, "", Rect2(G.GUTTER, 468, wide, 22), 16, Palette.GOLD_INK)
	meta_title.name = "MetaTitle"
	for index in 6:
		var card_width := (wide - 5.0 * 8.0) / 6.0
		# Moved up, and the restart button moved below, because the two used to
		# occupy the same rows: the moon-fish row arrived on this screen after the
		# button and nothing shifted to make space, so the button sat across two of
		# the six cards. Their names were unreadable and they could not be clicked.
		var card := label(screen, "", Rect2(G.GUTTER + index * (card_width + 8.0), 494, card_width, 66), 11, Palette.INK)
		card.name = "MetaUpgrade%d" % index
		card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_stylebox_override("normal", Palette.surface(Palette.CARD))
	# Sized to its own text rather than to the panel: an 850px plate holding one
	# centred phrase read as two empty boxes with a button wedged between them.
	place(main.result_label, Rect2(G.GUTTER, 616, wide, 18), 13, Palette.MUTED)
	main.result_label.remove_theme_stylebox_override("normal")
	main.result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func refresh_result(main: Node, victory: bool) -> void:
	var screen: Control = main.result_overlay
	screen.get_node("ResultHeading").text = "옥상 수호 성공" if victory else "오늘의 산책 종료"
	screen.get_node("ResultReason").text = "폭주 청소 로봇을 멈췄어요. 간식은 무사합니다!" if victory else "구조가 늦어졌어요. 다시 발맞춰 도전해요."
	screen.get_node("ResultHighlight").text = main._result_highlight()
	var values := ["%02d:%02d" % [int(main.elapsed) / 60, int(main.elapsed) % 60], str(main.kills), "LV.%d" % main.progression.level]
	for index in 3:
		screen.get_node("ResultMetric%d/Value" % index).text = values[index]
	for slot in 2:
		screen.get_node("ResultName%d" % slot).text = "%s  %s" % [main.player_label(slot), main.players[slot].character_name]
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
				art.tooltip_text = "%s    총 피해 %.0f" % [
					String(main.weapon_loadouts[slot][index]["weapon_name"]),
					float(main.run_stats["weapon_damage"][slot].get(weapon_id, 0.0)),
				]
	screen.get_node("CoopRecord").text = main._run_stats_summary()
	main._refresh_meta_result_ui()
	main.result_label.text = "SPACE / Y 강화 구매    ENTER / A 같은 조합 재도전    ESC / B 메인 메뉴"


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
	main.pause_label.text = "ESC / START  계속하기\nENTER  처음부터     F11  전체 화면\n대시  나 SPACE    동료 .    패드 RT"


static func connection_notice(main: Node, device: int) -> void:
	# Keep the navigable menu; a disconnect must not strand mouse/pad users.
	main._update_pause_text()
	main.pause_overlay.get_node("PauseHeading").text = "%s 패드 연결 끊김    키보드 사용 가능" % main.player_label(device)
	return
