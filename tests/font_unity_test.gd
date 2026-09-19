extends SceneTree

## Menus, cards and combat readings use one expressive bundled family.
##
## The HUD used to get Jua from a Theme hung on one Control host, which covered
## the menus and missed everything drawn outside that subtree: floating damage
## numbers, the P1/P2 badges over the cats and the downed prompt all fell back
## to the engine's built-in font, so a fight showed two typefaces at once. The
## family is now set on ThemeDB as well (project.godot `gui/theme/custom_font`
## plus CatTheme.adopt), and this walks the live tree to keep it that way.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const FAMILY := "MemomentKkukkukk.ttf"

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
	_check(_is_family(DamageNumberField.UIFont), "floating damage number")
	_check(numbers > 0, "a damage number was actually spawned to check")
	_check(_is_family(main.players[0].UIFont), "the survivor badge drawn onto the world")
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
		print("FONT_UNITY_PASS: %d text nodes use the bundled display family" % checked)
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
			_check(_is_family((node as Control).get_theme_font("font")),
				"%s: %s" % [screen, node.get_path()])
	elif node is RichTextLabel:
		if (node as Control).is_visible_in_tree():
			checked += 1
			_check(_is_family((node as Control).get_theme_font("normal_font")),
				"%s: %s" % [screen, node.get_path()])
	for child in node.get_children():
		_walk(child, screen)


func _is_family(font: Font) -> bool:
	return font != null and String(font.resource_path).ends_with(FAMILY)


func _check(ok: bool, context: String) -> void:
	if not ok:
		failures.append(context)
