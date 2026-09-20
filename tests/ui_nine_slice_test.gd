extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const CatTheme := preload("res://scripts/ui/cat_theme.gd")
const CatPanel := preload("res://scripts/ui/cat_panel.gd")
const CharacterCatalog := preload("res://scripts/catalogs/character_catalog.gd")
const EditorialUI := preload("res://scripts/ui/editorial_ui.gd")
var failures: Array[String] = []


func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/ui-nine-slice-progress.cfg")
	Harness.arm_watchdog(self, "UI_NINE_SLICE_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "UI_NINE_SLICE_FAIL"):
		return
	_check(main.title_rows[0].size.y > main.title_rows[1].size.y
		and main.title_rows[0].size.x > main.title_rows[1].size.x,
		"title screen gives the primary play action the largest card")
	_check(CatPanel.BACKDROP_ART.resource_path.ends_with("moonroof_backdrop_v3.png"),
		"menu screens use the v3 rooftop")
	_check(main.title_overlay.get_node("TitleAmbience/SceneBackdrop").texture.resource_path.ends_with(
		"moonroof_scrapbook_backdrop_v2.png"), "title uses the high-resolution scrapbook rooftop")
	_check(main.title_overlay.get_node("SnapshotCollage").get_child_count() == 4,
		"title uses four independent square character snapshots")
	_check(main.title_rows[1].size == main.title_rows[2].size
		and main.title_rows[3].size == main.title_rows[4].size,
		"title utility actions share one template per tier; got %s / %s" % [
			main.title_rows[1].size, main.title_rows[2].size])
	main.title_mode = "modes"
	main._refresh_title_ui()
	_check(not main.title_note.visible, "multiplayer choices have no right explanation box")
	_check(main.title_overlay.get_node("TitlePlate").size == Vector2(720, 544),
		"title subpages share the enlarged central panel")
	main.title_mode = "settings"
	main._refresh_title_ui()
	_check(not main.title_note.visible, "settings has no right explanation box")
	main.title_mode = "credits"
	main._refresh_title_ui()
	_check(main.title_note.visible and main.title_note.position.x == 280.0
		and main.title_note.size.x == 624.0,
		"credits content lives in the centered content box")
	main.title_mode = "meta"
	main._refresh_title_ui()
	_check(main.title_rows[0].position == Vector2(264, 144)
		and main.title_rows[1].position == Vector2(600, 144)
		and main.title_rows[0].size.y >= 56.0
		and main.title_rows[0].size.y <= 60.0
		and main.title_rows[1].size.y >= 56.0
		and main.title_rows[1].size.y <= 60.0,
		"permanent growth uses the same central two-column card system; got %s %s / %s %s" % [
			main.title_rows[0].position, main.title_rows[0].size,
			main.title_rows[1].position, main.title_rows[1].size])
	main._begin_title()
	main.lobby_input_cooldown = 0.0
	main._join_lobby_slot(0, -1, "키보드 WASD")
	main._finish_lobby()
	await process_frame
	var screen: Control = main.character_overlay
	_check(CatTheme.image_surface() is StyleBoxFlat and CatTheme.image_surface().bg_color.a < 1.0,
		"the shared panel surface is a see-through overlay rather than the v3 art")
	for index in main.character_catalog.size():
		var tile: Control = screen.get_node("Roster%d" % index)
		_check(tile.size == Vector2(80, 104), "roster tile %d keeps the shared template" % index)
		if index > 0:
			var previous_tile: Control = screen.get_node("Roster%d" % (index - 1))
			_check(tile.position.x - (previous_tile.position.x + previous_tile.size.x) == 8.0,
				"roster tile %d keeps an 8px gutter" % index)
	for slot in 2:
		var panel: Control = screen.get_node("CharacterPanel%d" % slot)
		var previous: Control = screen.get_node("CharacterPrevious%d" % slot)
		var next: Control = screen.get_node("CharacterNext%d" % slot)
		var confirm: Control = screen.get_node("CharacterConfirm%d" % slot)
		_check(panel.size == Vector2(560, 376), "player %d uses a 560x376 dossier" % slot)
		_check(panel.get_theme_stylebox("panel") is StyleBoxFlat
			and (panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a < 1.0,
			"player %d dossier is drawn as an overlay" % slot)
		_check(previous.size == Vector2(260, 40) and next.size == Vector2(260, 40),
			"player %d secondary buttons share one template; got %s / %s" % [slot, previous.size, next.size])
		_check(confirm.size == Vector2(528, 40),
			"player %d ready button fills its inset row; got %s" % [slot, confirm.size])
		_check(not previous.get_rect().intersects(confirm.get_rect())
			and not next.get_rect().intersects(confirm.get_rect()),
			"player %d button rows do not overlap" % slot)
		# Against the template's own constant rather than a copy of its numbers:
		# the rule being kept here is that every cell is the same cell, and a
		# literal turns a layout change into a test failure that says nothing.
		for stat in CharacterCatalog.DISPLAYED_STATS.size():
			var bed: Control = screen.get_node("CatStatBed%d_%d" % [slot, stat])
			_check(bed.size == Vector2(EditorialUI.STAT_CELL, 40),
				"player %d stat %d keeps the shared cell template (%s)" % [slot, stat, bed.size])
			var value: Label = screen.get_node("CatStat%d_%d" % [slot, stat])
			_check(bed.get_rect().encloses(value.get_rect()),
				"player %d stat %d keeps its value inside the cell" % [slot, stat])
	var left: Control = screen.get_node("CharacterPanel0")
	var right: Control = screen.get_node("CharacterPanel1")
	_check(right.position.x - (left.position.x + left.size.x) == 16.0,
		"player dossiers keep one 16px centre gutter")
	main.ai_companion = true
	main._refresh_character_select_ui()
	for slot in 2:
		var panel: Control = screen.get_node("CharacterPanel%d" % slot)
		var confirm: Control = screen.get_node("CharacterConfirm%d" % slot)
		var portrait: Control = main.character_portrait_icons[slot]
		var bed: Control = screen.get_node("CatPortraitBed%d" % slot)
		_check(panel.get_rect().encloses(confirm.get_rect()),
			"AI mode keeps player %d ready action inside its dossier" % slot)
		_check(portrait.get_index() > bed.get_index(),
			"player %d portrait renders above its background" % slot)
		_check(panel.scale == Vector2.ONE,
			"AI mode does not shrink partner information")
	_check(not left.get_rect().intersects(right.get_rect()),
		"AI mode keeps player dossiers separate")
	main._set_character_exit_confirm(true)
	_check(main.character_exit_confirm
		and screen.get_node("CharacterExitConfirm").visible,
		"character selection exposes an exit confirmation")
	main._set_character_exit_confirm(false)
	main.ReviewUI.toggle_character_details(main)
	for slot in 2:
		var body: Control = main.character_p1_label if slot == 0 else main.character_p2_label
		var previous: Control = screen.get_node("CharacterPrevious%d" % slot)
		var next: Control = screen.get_node("CharacterNext%d" % slot)
		_check(not body.get_rect().intersects(previous.get_rect())
			and not body.get_rect().intersects(next.get_rect()),
			"player %d detail copy stays clear of navigation actions" % slot)
	main._set_character_exit_confirm(true)
	main._confirm_character_exit()
	_check(main.title_active and main.title_overlay.visible
		and not main.character_select_active and not main.character_overlay.visible,
		"confirming character-select exit returns to the title")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("UI_NINE_SLICE_PASS: generated frame, repeated components, grid alignment")
		quit(0)
	else:
		for failure in failures:
			push_error("UI_NINE_SLICE_FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
