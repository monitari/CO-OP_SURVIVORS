extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "DEBUG_INSPECTOR_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "DEBUG_INSPECTOR_FAIL"):
		return

	_check(main.debug_inspector != null, "debug builds install the runtime inspector")

	# The inspector can be opened before a run exists, and every menu is drawn
	# across the panel's half of the screen, so it has to fold rather than cover.
	var inspector = main.debug_inspector
	inspector.toggle()
	await process_frame
	_check(inspector.is_open and not inspector.panel.visible and inspector.ribbon.visible,
		"opening the inspector on the title screen folds it to the ribbon")
	_check(inspector.readout.text.contains("타이틀") and inspector.ribbon_label.text.contains("타이틀"),
		"folded telemetry still names the screen it yielded to")
	inspector.toggle()
	await process_frame
	_check(not inspector.panel.visible and not inspector.ribbon.visible,
		"closing the inspector hides the ribbon as well as the panel")

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true

	# Engine.time_scale is global and the inspector is not its only user: the
	# soak harnesses accelerate a run twentyfold before starting it. Resetting a
	# flat 1.0 on every run start silently un-accelerated them.
	Engine.time_scale = 20.0
	main._start_selected_run()
	_check(is_equal_approx(Engine.time_scale, 20.0),
		"starting a run leaves a simulation speed the inspector never set alone")
	Engine.time_scale = 1.0
	main.set_physics_process(false)
	await process_frame

	inspector.toggle()
	await process_frame
	_check(inspector.is_open and inspector.panel.visible, "F10 panel can be opened lazily")
	var panel_rect: Rect2 = inspector.panel.get_global_rect()
	var viewport_size: Vector2 = main.get_viewport().get_visible_rect().size
	_check(panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0
		and panel_rect.end.x <= viewport_size.x and panel_rect.end.y <= viewport_size.y,
		"debug panel remains inside the viewport (%s in %s)" % [panel_rect, viewport_size])
	_check(inspector.readout.size.x > 400.0 and inspector.readout.size.y > 600.0,
		"telemetry has enough room to remain scannable")
	_check(inspector.readout.text.contains("RUNTIME INSPECTOR"), "panel renders live run telemetry")
	_check(inspector.readout.text.contains(main.players[0].character_name), "telemetry identifies the selected survivor")

	var target := main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false) as ChaserEnemy
	target.position = main.players[0].global_position + Vector2(80.0, 0.0)
	main._register_enemy(target)
	main.spatial_grid.rebuild(main.enemies)
	# Held by reference rather than read back as main.enemies[0]: the attack below
	# is real damage, so the target can die and leave the array — and then the
	# check that the damage landed is the line that crashes.
	var health_before_visual_toggle: float = target.health
	inspector._toggle_combat_visuals()
	_check(not main.weapon_controller.visible and not main.flight_field.visible
		and not main.crowd_renderer._warnings.visible,
		"combat attack layers hide without hiding the crowd")
	main.weapon_controller.perform_attack(0, 0, 1.0)
	main.weapon_controller._physics_process(0.3)
	_check(not is_instance_valid(target) or target.dead or target.health < health_before_visual_toggle,
		"hiding combat visuals leaves attack damage and collision active")
	inspector._toggle_combat_visuals()
	_check(main.weapon_controller.visible and main.flight_field.visible,
		"combat attack layers restore after the debug toggle")

	# F11 and F12 already belonged to 전체화면 and 달빛 연출. The inspector borrows
	# them, and the borrow only works because both halves agree: the inspector
	# refuses them unless its panel is open, and main stands down for exactly that
	# window. Either half alone is worse than neither — with only main yielding,
	# the game's toggles are dead whenever the panel is closed too; with only the
	# inspector gating, one press fires both features at once.
	var moonlight_before: bool = Moonlight.enabled
	var was_open: bool = inspector.is_open
	inspector.is_open = false
	main._input(_key_press(KEY_F12))
	_check(Moonlight.enabled != moonlight_before,
		"with the panel closed, F12 is still the game's 달빛 연출 key")
	main._input(_key_press(KEY_F12))
	inspector.is_open = was_open
	moonlight_before = Moonlight.enabled
	main._input(_key_press(KEY_F12))
	_check(Moonlight.enabled == moonlight_before,
		"with the panel open, main leaves F12 to the inspector")

	var level_before := int(main.progression.level)
	inspector._grant_level()
	_check(main.level_up_active and int(main.progression.level) == level_before + 1,
		"level shortcut opens a real growth selection and consumes its XP")
	_check(main.debug_run_tainted, "the first state-changing shortcut marks the run as debug-mutated")

	# The panel sat exactly on P2's cards and reroll button, which is where this
	# shortcut sends you. Folding is only worth anything if the ribbon clears
	# every control on the screen it stepped aside for.
	_check(not inspector.panel.visible and inspector.ribbon.visible,
		"the growth screen the shortcut opened folds the panel out of its way")
	var ribbon_rect: Rect2 = inspector.ribbon.get_global_rect()
	_check(ribbon_rect.position.x >= 0.0 and ribbon_rect.position.y >= 0.0
		and ribbon_rect.end.x <= viewport_size.x and ribbon_rect.end.y <= viewport_size.y,
		"ribbon stays inside the viewport (%s in %s)" % [ribbon_rect, viewport_size])
	_check(inspector.ribbon.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and inspector.ribbon_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the ribbon never takes the pointer from the screen underneath it")
	for slot in 2:
		for card: Label in main.level_card_labels[slot]:
			if card.is_visible_in_tree():
				_check(not ribbon_rect.intersects(card.get_global_rect()),
					"folded ribbon leaves every P%d growth card clickable" % (slot + 1))
		for control_name in ["Reroll%d" % slot, "Cancel%d" % slot]:
			if main.level_overlay.has_node(control_name):
				var button: Control = main.level_overlay.get_node(control_name)
				_check(not ribbon_rect.intersects(button.get_global_rect()),
					"folded ribbon leaves %s clickable" % control_name)
	_close_level_modal(main)
	await process_frame
	_check(inspector.panel.visible and not inspector.ribbon.visible,
		"leaving the growth screen unfolds the panel again")

	var opening_damage := float(main.weapon_loadouts[0][0]["damage"])
	inspector._prepare_fusions()
	for slot in 2:
		var weapon: Dictionary = main.weapon_loadouts[slot][0]
		_check(int(weapon.get("tier", 1)) >= Evolutions.EVOLUTION_TIER,
			"fusion shortcut raises P%d's base weapon through real upgrade steps" % (slot + 1))
		# The shortcut buys tiers; Lv.7 does the rest by itself, so what it has
		# to produce is an enhanced weapon rather than a card offering one.
		_check(bool(weapon.get("evolved", false)),
			"fusion shortcut leaves P%d holding the enhanced weapon" % (slot + 1))
	_check(float(main.weapon_loadouts[0][0]["damage"]) > opening_damage,
		"preparation does not fake the tier label; it applies weapon power")
	_close_level_modal(main)

	main.players[0].health = 1.0
	main.players[1].downed = true
	main.players[1].health = 0.0
	main.chain_integrity = 2.0
	main.chain_overloaded = true
	inspector._repair_team()
	_check(is_equal_approx(main.players[0].health, main.players[0].max_health), "repair restores P1")
	_check(not main.players[1].downed and is_equal_approx(main.players[1].health, main.players[1].max_health),
		"repair revives and fully restores P2")
	_check(not main.chain_overloaded and is_equal_approx(main.chain_integrity, main.CHAIN_INTEGRITY_MAX),
		"repair clears chain overload and restores integrity")

	inspector._spawn_next_boss()
	_check(main.wave_director.boss_active and main.wave_director.bosses_spawned == 1,
		"boss shortcut advances the director by exactly one boss")
	_check(main.boss_enemy != null and is_instance_valid(main.boss_enemy), "spawned boss is registered with the HUD/combat scene")

	inspector._cycle_speed()
	_check(is_equal_approx(Engine.time_scale, 2.0), "speed shortcut cycles from 1x to 2x")
	_check(inspector._speed_text(0.15) == "0.15" and inspector._speed_text(1.0) == "1"
		and inspector._speed_text(5.0) == "5",
		"the slow-motion step reads 0.15, not a rounded 0")
	var points_before := int(main.meta_progression.points)
	main.run_stats["bosses"] = main.wave_director.BOSS_COUNT
	main._end_run(true)
	_check(main.run_reward == 0 and int(main.meta_progression.points) == points_before,
		"a debug-mutated clear cannot grant permanent currency")
	_check(main.result_overlay.get_node("ResultReason").text.contains("저장되지 않습니다"),
		"the result screen explains why debug-run progression is disabled")
	inspector.toggle()
	_check(not inspector.is_open and is_equal_approx(Engine.time_scale, 1.0),
		"closing the inspector restores normal simulation speed")

	if failures.is_empty():
		print("DEBUG_INSPECTOR_PASS: bounded F10 panel, telemetry/actions, tainted-run reward guard, safe speed reset")
		quit(0)
	else:
		for failure in failures:
			push_error("DEBUG_INSPECTOR_FAIL: " + failure)
		quit(1)


func _close_level_modal(main: Node) -> void:
	main.level_up_active = false
	main.level_overlay.visible = false
	main.selected_upgrade_indices[0] = -1
	main.selected_upgrade_indices[1] = -1
	paused = false


## A real key-down event, so the checks above go through the same action lookup
## the game does rather than calling the toggle directly.
func _key_press(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
