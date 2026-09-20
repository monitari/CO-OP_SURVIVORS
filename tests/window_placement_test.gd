extends SceneTree

## The window sits where the pointer thinks it does, and 전체화면 is visible.
##
## The two shipped bugs this guards were one bug. A 1920x1080 client area does
## not fit a 1080p desktop once the window manager adds a title bar, and the old
## code answered that by dropping the frame and letting the window cover the
## whole desktop — then never moving it. Its client origin stayed where the
## framed window's outer corner had been, (1912, -31) on a 1080p desktop, so the
## picture and the pointer disagreed by the height of a title bar and every
## button had to be clicked a little below itself. The same trick made windowed
## mode pixel-identical to full screen, so the 전체화면 row appeared dead.
##
## Needs a real display server: headless has no window to place.
##
##   godot --path . --script tests/window_placement_test.gd

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const Main := preload("res://scripts/main.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WINDOW_PLACEMENT_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	# Pure arithmetic first, so a desktop that happens to fit everything still
	# exercises the clamp.
	_check(Main.fit_window_size(Vector2i(1280, 720), Vector2i(1904, 993)) == Vector2i(1280, 720),
		"a window that already fits is left alone")
	for room in [Vector2i(1904, 993), Vector2i(1366, 728), Vector2i(1000, 900)]:
		var fitted := Main.fit_window_size(Vector2i(1920, 1080), room)
		_check(fitted.x <= room.x and fitted.y <= room.y,
			"1920x1080 clamped into %s fits it: %s" % [room, fitted])
		# Off by a pixel is a one-pixel letterbox along the top of every screen.
		_check(fitted.x * 9 == fitted.y * 16,
			"the clamped window is 16:9 to the pixel: %s" % fitted)

	if DisplayServer.get_name() == "headless":
		print("WINDOW_PLACEMENT_SKIP: no display server; clamp arithmetic checked")
		quit(0 if failures.is_empty() else 1)
		return

	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WINDOW_PLACEMENT_FAIL"):
		return

	main._set_fullscreen(false)
	await process_frame
	_check(not main.is_fullscreen(), "the window starts out of full screen")
	# The frame is what makes the two modes tell themselves apart, and dropping
	# it is what left the window unplaced.
	_check(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),
		"a windowed window keeps its frame")
	var windowed_size := DisplayServer.window_get_size()
	var windowed_origin := DisplayServer.window_get_position()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# The bug, stated: the client rect has to be on the screen, because every
	# pointer event is reported against its origin.
	_check(usable.encloses(Rect2i(windowed_origin, windowed_size)),
		"the client area is inside the usable desktop: %s in %s" % [
			Rect2i(windowed_origin, windowed_size), usable])
	_check(usable.encloses(Rect2i(DisplayServer.window_get_position_with_decorations(),
		DisplayServer.window_get_size_with_decorations())),
		"the frame around it is on the screen too")
	_check(main.applied_window_size == windowed_size,
		"the reported window size is the one the window actually has")

	main._set_fullscreen(true)
	await process_frame
	_check(main.is_fullscreen(), "전체화면 켜짐 puts the window in a full-screen mode")
	_check(DisplayServer.window_get_size() == DisplayServer.screen_get_size(
		DisplayServer.window_get_current_screen()), "full screen covers the screen")

	main._set_fullscreen(false)
	await process_frame
	_check(not main.is_fullscreen(), "전체화면 꺼짐 returns to a window")
	# The complaint was that the switch did nothing. Whatever else is true, the
	# two states have to look different.
	_check(DisplayServer.window_get_size() != DisplayServer.screen_get_size(
		DisplayServer.window_get_current_screen())
		or DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) == false,
		"leaving full screen is something a player can see")
	_check(usable.encloses(Rect2i(DisplayServer.window_get_position(),
		DisplayServer.window_get_size())),
		"the window is still on the screen after a round trip through full screen")

	# The ways out of full screen. F11 was always bound; Alt+Enter is the one a
	# player reaches for first, and it is a chord rather than an action because
	# Godot matches a bound plain Enter against Alt+Enter too — so the same press
	# would otherwise also fire menu_confirm and 재시작.
	var saved_preference: bool = main.settings.fullscreen_enabled
	main.title_mode = "menu"
	main.title_cursor = 0
	main.modal_input_guard = 0
	for chord in [true, false]:
		var opening := _press(KEY_ENTER if chord else KEY_F11, chord)
		var label := "Alt+Enter" if chord else "F11"
		main._input(opening)
		_check(main.is_fullscreen(), "%s turns 전체화면 on" % label)
		main._input(_press(KEY_ENTER if chord else KEY_F11, chord))
		_check(not main.is_fullscreen(), "%s turns it back off" % label)
	_check(main.modal_input_guard > 0,
		"Alt+Enter drops the next input tick, so the polled menu_confirm on the "
		+ "same Enter cannot also activate whatever the cursor is sitting on")
	_check(main.title_mode == "menu" and main.title_cursor == 0,
		"Alt+Enter left the menu where it was")
	main._input(_press(KEY_ENTER, false))
	_check(not main.is_fullscreen(), "a plain Enter is not a full-screen key")
	main.settings.fullscreen_enabled = saved_preference
	main.settings.save_settings()

	if failures.is_empty():
		print("WINDOW_PLACEMENT_PASS: window %s at %s, full screen round-trips, F11 and Alt+Enter" % [
			windowed_size, windowed_origin])
		quit(0)
	else:
		for failure in failures:
			push_error("WINDOW_PLACEMENT_FAIL: " + failure)
		quit(1)


static func _press(code: int, alt: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code as Key
	event.physical_keycode = code as Key
	event.alt_pressed = alt
	event.pressed = true
	return event


func _check(ok: bool, context: String) -> void:
	if not ok:
		failures.append(context)
