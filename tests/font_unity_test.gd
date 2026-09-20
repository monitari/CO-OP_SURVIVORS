extends SceneTree

## Every word on screen is set in a bundled face, in the one its role calls for.
##
## The HUD used to get its font from a Theme hung on one Control host, which
## covered the menus and missed everything drawn outside that subtree: floating
## damage numbers, the P1/P2 badges over the cats and the downed prompt all fell
## back to the engine's built-in font, so a fight showed a typeface nobody chose.
## The display family is now set on ThemeDB as well (project.godot
## `gui/theme/custom_font` plus CatTheme.adopt), and this walks the live tree to
## keep it that way.
##
## There are two bundled faces and the split between them is the point. Gowoon
## now owns the backed top HUD as well as the menus; Jua remains for small text
## drawn directly over the moving world and the bottom XP strip. What this will
## not accept is a third engine or system face that nobody chose.

const MainScene := preload("res://scenes/main.tscn")
const CatTheme := preload("res://scripts/ui/cat_theme.gd")
const EdgePointer := preload("res://scripts/ui/edge_pointer.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const FAMILY := "GriunXHangeul_Gowoon-Rg.ttf"
const READOUT := "Jua-Regular.ttf"
const SYMBOL := "MemomentKkukkukk.ttf"

var failures: Array[String] = []
var checked := 0


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FONT_UNITY_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "FONT_UNITY_FAIL"):
		return
	_check(_is_family(ThemeDB.fallback_font),
		"ThemeDB fallback is the bundled family, so un-themed text cannot drift")
	# Both faces are read at 10-16px. MSDF at those sizes is what chewed the
	# handwriting's contours, and Jua was still importing with it switched on
	# while it was only ever a fallback.
	for face in [FAMILY, READOUT, SYMBOL]:
		var import_settings := FileAccess.get_file_as_string("res://assets/fonts/%s.import" % face)
		_check(import_settings.contains("multichannel_signed_distance_field=false")
			and import_settings.contains("oversampling=2.0"),
			"%s avoids MSDF contour damage and uses 2x oversampling" % face)
	# The symbol face carries what the other two are missing outright — the
	# middle dot in "거리·안정" among them — so neither may be left without it.
	for face: FontFile in [CatTheme.FAMILY, CatTheme.READOUT]:
		_check(face.fallbacks.size() == 1 and String(face.fallbacks[0].resource_path).ends_with(SYMBOL),
			"%s falls back to the symbol face and nothing else" % face.resource_path.get_file())
	# Menus.
	_walk(main, "lobby")
	main.lobby_input_cooldown = 0
	main._join_lobby_slot(0, -1, "키보드 WASD")
	main._join_lobby_slot(1, -1, "키보드 방향키")
	main._finish_lobby()
	await process_frame
	_walk(main, "character select")
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	await physics_frame
	_walk(main, "combat")
	# The pieces drawn into the world rather than into the HUD host: these are
	# the ones the old theme-host-only setup missed.
	main.feedback.damage_numbers_enabled = true
	main.feedback.show_damage(main.players[0].global_position, 123.0, Color.WHITE)
	await process_frame
	# Numbers are drawn by one batched field now, with the font it holds, rather
	# than being Labels that inherit the theme's.
	var numbers: int = main.feedback.live_damage_numbers()
	_check(_is_readout(DamageNumberField.UIFont), "floating damage number")
	_check(numbers > 0, "a damage number was actually spawned to check")
	_check(_is_readout(main.players[0].UIFont), "the survivor badge drawn onto the world")
	_check(_is_readout(EdgePointer.UIFont), "the off-screen pointer's distance")
	# The rebuilt top strip sits on opaque paper, so it shares the regular family
	# with the rest of the interface instead of reading as a bold separate skin.
	var paper_readouts: Array[String] = [
		"WaveReadout", "ObjectiveReadout", "PlayerNumber0", "PlayerNumber1",
		"PlayerIdentity0", "PlayerIdentity1",
	]
	for name in paper_readouts:
		var found: Label = main.combat_hud.get_node_or_null(name)
		_check(found != null and _is_family(found.get_theme_font("font")),
			"combat HUD reading: %s" % name)
	for reading: Label in [main.hud_label, main.chain_distance_text_label,
			main.chain_integrity_text_label, main.resonance_status_label,
			main.p1_health_text_label, main.p2_health_text_label]:
		_check(_is_family(reading.get_theme_font("font")),
			"combat HUD reading: %s" % reading.name)
	_check(_is_readout(main.xp_text_label.get_theme_font("font")),
		"bottom XP strip keeps the compact readout face")
	# Growth, pause and result.
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main._refresh_level_up_ui()
	await process_frame
	_walk(main, "growth")
	main.level_up_active = false
	main.level_overlay.visible = false
	main._set_pause(true)
	await process_frame
	_walk(main, "pause")
	main._set_pause(false)
	main._end_run(true)
	await process_frame
	_walk(main, "result")
	if failures.is_empty():
		print("FONT_UNITY_PASS: %d text nodes use a bundled face" % checked)
		quit(0)
	else:
		for failure in failures:
			push_error("FONT_UNITY_FAIL: " + failure)
		quit(1)


## Every visible text-bearing node under `node`, whatever theme path it took.
func _walk(node: Node, screen: String) -> void:
	if node is Label or node is Button or node is LineEdit:
		if (node as Control).is_visible_in_tree():
			checked += 1
			_check(_is_bundled((node as Control).get_theme_font("font")),
				"%s: %s" % [screen, node.get_path()])
	elif node is RichTextLabel:
		if (node as Control).is_visible_in_tree():
			checked += 1
			_check(_is_bundled((node as Control).get_theme_font("normal_font")),
				"%s: %s" % [screen, node.get_path()])
	for child in node.get_children():
		_walk(child, screen)


func _is_family(font: Font) -> bool:
	return font != null and String(font.resource_path).ends_with(FAMILY)


func _is_readout(font: Font) -> bool:
	return font != null and String(font.resource_path).ends_with(READOUT)


## Either bundled face, but nothing else: a node in the engine's built-in font
## is a node whose typeface nobody picked.
func _is_bundled(font: Font) -> bool:
	return _is_family(font) or _is_readout(font)


func _check(ok: bool, context: String) -> void:
	if not ok:
		failures.append(context)
