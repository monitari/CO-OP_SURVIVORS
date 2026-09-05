extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []
var checked := 0


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "LAYOUT_FAIL", 120.0)
	call_deferred("_run")


## Nothing sticks out, nothing is cut off, nothing sits on top of anything else.
##
## Every screen is built from hand-written rectangles, so a longer Korean string,
## a new font, or one more stat in a row moves text out of its box — and every
## label in this project has `clip_text` on, which means it is cut **silently**.
## The first three of these are checked mechanically across every overlay:
##
##   OVERFLOW  a control whose rectangle leaves its parent's
##   HCLIP     a non-wrapping label whose text is wider than its box
##   VCLIP     a label with more lines than fit
##
## Everything is asserted with the screen forced visible, because a hidden
## Control still has a size and the bug is present whether or not it is on
## screen at the moment the test looks.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "LAYOUT_FAIL"):
		return
	await process_frame

	main._refresh_lobby_ui()
	main._finish_lobby()
	await process_frame
	main._refresh_character_select_ui()
	await process_frame
	_audit("로비", main.lobby_overlay)
	_audit("생존자 선택", main.character_overlay)

	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	# A build with everything in it: four weapons and four treasures each, which
	# is the widest the readouts ever get.
	for slot in 2:
		for character in CharacterCatalog.all_characters():
			if main.weapon_loadouts[slot].size() >= main.WEAPON_LOADOUT_CAP:
				break
			if String(character["weapon_id"]) == String(main.weapon_loadouts[slot][0]["weapon_id"]):
				continue
			main._apply_upgrade(slot, {"id": "unlock_weapon", "weapon_slot": -1, "character": character})
		for treasure in TreasureCatalog.all_treasures():
			if main.treasure_loadouts[slot].size() >= main.TREASURE_LOADOUT_CAP:
				break
			main._apply_upgrade(slot, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	main.showcase_queue.clear()

	main.progression.add_experience(99999)
	main._begin_level_up()
	main.level_up_input_delay = 0.0
	main._refresh_level_up_ui()
	await process_frame
	_audit("성장 선택", main.level_overlay)
	main.level_up_active = false
	main.level_overlay.visible = false
	paused = false

	main._update_hud()
	await process_frame
	_audit("전투 HUD", main.combat_hud)
	_test_the_play_field_shows_the_whole_build(main)

	main._set_pause(true)
	await process_frame
	_audit("일시정지", main.pause_overlay)
	main._set_pause(false)

	main._end_run(true)
	# One real tick: which overlays and HUD panels are visible is decided in
	# _physics_process, so a test with physics disabled reads a stale flag and
	# passes whatever the rule says. main runs on PROCESS_MODE_ALWAYS, so this
	# ticks even though _end_run paused the tree.
	main.set_physics_process(true)
	# Several, not one: _physics_process swallows a couple of ticks whenever a
	# modal has just closed (modal_input_guard), so a single frame can return
	# before it reaches the visibility rules at all.
	for frame in 6:
		await physics_frame
	main.set_physics_process(false)
	await process_frame
	_audit("결과", main.result_overlay)
	_test_the_result_screen_owns_the_screen(main)

	print("LAYOUT_METRICS: %d controls audited" % checked)
	if failures.is_empty():
		print("LAYOUT_PASS: nothing overflows, nothing is clipped")
		quit(0)
	else:
		for failure in failures:
			push_error("LAYOUT_FAIL: " + failure)
		quit(1)


## The play screen is where a build lives, so it has to show the build: both
## rows, both survivors, with the tier on each icon. It used to show four weapon
## icons and nothing else — no treasures at all, and no way to tell a tier-one
## weapon from a tier-seven one without opening a menu.
func _test_the_play_field_shows_the_whole_build(main: Node) -> void:
	for slot in 2:
		var holder: Control = main.combat_hud.get_node("Carried%d" % slot)
		_check(holder.visible, "P%d's build readout is on screen during play" % (slot + 1))
		for row: String in ["Weapon", "Treasure"]:
			var carried: Array = main.weapon_loadouts[slot] if row == "Weapon" else main.treasure_loadouts[slot]
			_check(not carried.is_empty(), "the fixture actually gave P%d %s" % [slot + 1, row])
			for index in 4:
				var art: TextureRect = holder.get_node("%s%d" % [row, index])
				_check(art.visible == (index < carried.size()),
					"P%d %s slot %d is shown exactly when it is carried" % [slot + 1, row, index])
				if not art.visible:
					continue
				_check(art.texture != null, "P%d %s %d draws an icon" % [slot + 1, row, index])
				var tier: Label = art.get_node("Tier")
				_check(tier.text == "T%d" % int((carried[index] as Dictionary).get("tier", 1)),
					"P%d %s %d states its tier (%s)" % [slot + 1, row, index, tier.text])
		# Both rows have to stay on screen: P2's sits against the right edge and
		# a wider icon or a fifth slot would push it off.
		var far_right: float = holder.position.x + 3.0 * 38.0 + 30.0
		_check(far_right <= 1280.0, "P%d's readout stays inside the viewport (%.0f)" % [slot + 1, far_right])


## The run is over; the bars along the top are stale, and the P2 panel reaches
## far enough right to clip the result panel's own corner.
func _test_the_result_screen_owns_the_screen(main: Node) -> void:
	_check(main.result_overlay.visible, "the result screen is up")
	_check(not main.combat_hud.visible, "and the combat HUD is not drawn over it")


func _audit(screen_name: String, screen: Control) -> void:
	var previously := screen.visible
	screen.visible = true
	_walk(screen_name, screen)
	screen.visible = previously


func _walk(screen_name: String, node: Control) -> void:
	var bounds := Rect2(Vector2.ZERO, node.size)
	for child in node.get_children():
		var control := child as Control
		if control == null:
			continue
		checked += 1
		if control is Label:
			_check_label(screen_name, control as Label)
		# The tier badge deliberately hangs off the corner of the icon it labels.
		if node.size.x > 0.0 and control.name != "Tier":
			var own := Rect2(control.position, control.size)
			_check(bounds.grow(1.0).encloses(own),
				"%s · %s stays inside %s (%s in %s)" % [
					screen_name, control.name, node.name, str(own), str(bounds)])
		_walk(screen_name, control)


func _check_label(screen_name: String, item: Label) -> void:
	if String(item.text).is_empty():
		return
	_check(item.get_line_count() <= item.get_visible_line_count(),
		"%s · %s is not cut off vertically (%d lines, %d fit): %s" % [
			screen_name, item.name, item.get_line_count(), item.get_visible_line_count(),
			String(item.text).replace("\n", " / ")])
	if item.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return
	var font := item.get_theme_font("font")
	var font_size := item.get_theme_font_size("font_size")
	var room := item.size.x - _horizontal_padding(item)
	for line in String(item.text).split("\n"):
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_check(width <= room + 1.0,
			"%s · %s is not cut off horizontally (%.0fpx of text in %.0fpx): %s" % [
				screen_name, item.name, width, room, line])


func _horizontal_padding(item: Label) -> float:
	var style := item.get_theme_stylebox("normal") as StyleBoxFlat
	if style == null:
		return 0.0
	return style.content_margin_left + style.content_margin_right


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
