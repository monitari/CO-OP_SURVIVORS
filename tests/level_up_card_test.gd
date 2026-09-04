extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "LEVEL_UP_CARD_FAIL", 60.0)
	call_deferred("_run")


## The level-up screen used to apply an upgrade the instant a digit key was
## pressed. It is now a card screen: move a cursor, confirm, and stay able to
## back out until the partner also confirms — which only means anything if
## confirming genuinely defers the stat change instead of applying it early.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "LEVEL_UP_CARD_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_input_delay(main)
	_test_recommendation_and_build_readout(main)
	await _test_cursor_and_deferred_apply(main)
	await _test_reroll(main)
	await _test_no_immediate_repeat(main)

	if failures.is_empty():
		print("LEVEL_UP_CARD_PASS: recommendations, icon build readout, open delay, cursor, deferred apply, reroll, no repeat set")
		quit(0)
	else:
		for failure in failures:
			push_error("LEVEL_UP_CARD_FAIL: " + failure)
		quit(1)


func _open_level_up(main: Node) -> void:
	main.progression.add_experience(main.progression.required_experience)
	main._begin_level_up()
	main.level_up_input_delay = 0.0 # most tests want the screen immediately live


## Presses an action, runs one pass of the level-up input handler, releases.
## Matches how the other tests drive InputMap-based handlers directly rather
## than waiting on real frames.
func _tap(main: Node, action: String) -> void:
	Input.action_press(action)
	main._handle_level_up_input()
	Input.action_release(action)
	await process_frame


## Must cover every value any upgrade card can move — including the personal
## and shared attributes. A snapshot that only watched weapons and health
## silently passed when both players happened to draw shared-attribute cards,
## which changed real state the snapshot could not see.
func _stat_snapshot(main: Node) -> Array:
	var snapshot: Array = []
	for slot in 2:
		var weapons: Array = []
		for weapon in main.weapon_loadouts[slot]:
			weapons.append("%s|%.3f|%.3f|%d" % [
				String(weapon["weapon_id"]), float(weapon["damage"]), float(weapon["cooldown"]), int(weapon.get("tier", 1))
			])
		var player: ChainPlayer = main.players[slot]
		snapshot.append("%.2f|%.2f|%.3f|%.3f|%.3f|%d|%.3f|%.2f|%.2f|%s" % [
			player.move_speed, player.max_health,
			player.might, player.area, player.projectile_speed, player.amount,
			player.haste, player.armor, player.recovery,
			"/".join(weapons)
		])
	snapshot.append("%.3f|%.3f|%d" % [main.team_magnet, main.team_growth, main.team_luck])
	return snapshot



## P1 confirms with W and P2 with the up arrow — the very keys they move with.
## Opening the screen mid-stride used to read that held movement as a card
## confirmation, so the screen ignores input for a beat after it appears.
func _test_input_delay(main: Node) -> void:
	main.progression.add_experience(main.progression.required_experience)
	main._begin_level_up()
	_check(main.level_up_input_delay > 0.0, "opening the screen arms an input delay")

	var cursor_before: int = main.upgrade_cursors[0]
	await _tap(main, "p1_select_next")
	_check(main.upgrade_cursors[0] == cursor_before, "cursor input is ignored during the delay")
	await _tap(main, "p1_select_confirm")
	_check(main.selected_upgrade_indices[0] == -1, "a confirm arriving during the delay does not pick a card")
	await _tap(main, "p1_reroll")
	_check(main.rerolls_remaining[0] == 1, "a reroll arriving during the delay is not spent")

	# Burn the delay down the way the paused physics loop does.
	for tick in 60:
		if main.level_up_input_delay <= 0.0:
			break
		main._handle_level_up_input()
		await process_frame
	_check(main.level_up_input_delay <= 0.0, "the delay expires on its own")

	await _tap(main, "p1_select_confirm")
	_check(main.selected_upgrade_indices[0] >= 0, "input works normally once the delay has passed")

	await _tap(main, "p2_select_confirm")
	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	main.level_up_active = false
	paused = false
	await process_frame


func _test_recommendation_and_build_readout(main: Node) -> void:
	main.resonance_system.active_resonances.clear()
	main.weapon_loadouts[0][0]["tier"] = 2
	main.weapon_loadouts[1][0]["tier"] = 3
	var choices: Array[Dictionary] = [
		{"id": "weapon_power", "weapon_slot": 0, "title": "공명 직전 강화"},
		{"id": "vitality", "weapon_slot": -1, "title": "생명력"},
		{"id": "move", "weapon_slot": -1, "title": "이동"},
	]
	main._annotate_recommendations(0, choices)
	_check(bool(choices[0]["recommended"]), "a tier-3 upgrade that unlocks a resonance is recommended")
	_check(String(choices[0]["recommendation_reason"]).contains("공명 해금"), "the recommendation explains its tech-graph reason")
	var recommendation_count := 0
	for option in choices:
		recommendation_count += 1 if bool(option["recommended"]) else 0
		_check(option.has("recommendation_score") and option.has("recommendation_reason"), "every offered card receives an explainable score")
	_check(recommendation_count == 1, "exactly one card is marked recommended")

	# Restore the normal opening tiers before the randomized card-flow checks.
	main.weapon_loadouts[0][0]["tier"] = 1
	main.weapon_loadouts[1][0]["tier"] = 1
	main.p1_choices = main._get_upgrade_choices(1)
	main.p2_choices = main._get_upgrade_choices(2)
	main._refresh_level_up_ui()
	var recommended_cards := 0
	for card: Label in main.level_card_labels[0]:
		var icon := card.get_node("Icon") as TextureRect
		var badge := card.get_node("Recommendation") as Label
		_check(icon.texture != null, "every upgrade card renders a mapped icon")
		recommended_cards += 1 if badge.visible else 0
	_check(recommended_cards == 1, "the recommendation badge is visible on one dealt card")
	_check(main.p1_level_footer.text.contains("공격") and main.p1_level_footer.text.contains("탄속")
		and main.p1_level_footer.text.contains("재생") and main.p1_level_footer.text.contains("이동"),
		"the level-up build readout always lists the full personal stat set")
	_check(main.level_weapon_icons[0][0].visible and main.level_weapon_icons[0][0].texture != null,
		"owned weapons render as tiered icons")

func _test_cursor_and_deferred_apply(main: Node) -> void:
	_open_level_up(main)
	_check(main.level_up_active, "gaining a level opens the card screen")
	_check(main.p1_choices.size() == 3, "three cards are offered")
	_check(main.upgrade_cursors[0] == 0 and main.selected_upgrade_indices[0] == -1, "cursor starts at the first card, nothing locked")

	await _tap(main, "p1_select_next")
	_check(main.upgrade_cursors[0] == 1, "next moves the cursor right")
	await _tap(main, "p1_select_next")
	await _tap(main, "p1_select_next")
	_check(main.upgrade_cursors[0] == 0, "the cursor wraps around the three cards")
	await _tap(main, "p1_select_previous")
	_check(main.upgrade_cursors[0] == 2, "previous wraps backwards")

	var before := _stat_snapshot(main)
	await _tap(main, "p1_select_confirm")
	_check(main.selected_upgrade_indices[0] == 2, "confirm locks the card under the cursor")
	_check(_stat_snapshot(main) == before, "confirming alone changes nothing yet — the upgrade is deferred")
	_check(main.level_up_active, "the screen stays open while one player is still choosing")

	await _tap(main, "p1_select_cancel")
	_check(main.selected_upgrade_indices[0] == -1, "a locked player can back out while the partner is still choosing")
	_check(_stat_snapshot(main) == before, "cancelling leaves stats untouched")

	await _tap(main, "p1_select_confirm")
	await _tap(main, "p2_select_confirm")
	_check(_stat_snapshot(main) != before, "both confirmations apply the upgrades together")
	_check(not main.level_up_active or main.resonance_vote_active, "the card screen closes once both players commit")
	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	main.level_up_active = false
	paused = false
	await process_frame


func _test_reroll(main: Node) -> void:
	main.rerolls_remaining[0] = 1
	main.rerolls_remaining[1] = 1
	_open_level_up(main)
	var first_titles := _titles(main.p1_choices)

	await _tap(main, "p1_reroll")
	_check(main.rerolls_remaining[0] == 0, "a reroll is spent")
	_check(main.upgrade_cursors[0] == 0, "rerolling resets the cursor")
	_check(main.rerolls_remaining[1] == 1, "one player's reroll does not consume the partner's")

	await _tap(main, "p1_reroll")
	_check(main.rerolls_remaining[0] == 0, "a second reroll is refused once the budget is spent")
	print("REROLL_METRICS: before=%s after=%s" % [", ".join(first_titles), ", ".join(_titles(main.p1_choices))])

	await _tap(main, "p1_select_confirm")
	await _tap(main, "p2_select_confirm")
	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	main.level_up_active = false
	paused = false
	await process_frame


func _test_no_immediate_repeat(main: Node) -> void:
	_open_level_up(main)
	var first_keys := _keys(main, main.p1_choices)
	await _tap(main, "p1_select_confirm")
	await _tap(main, "p2_select_confirm")
	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	main.level_up_active = false
	paused = false
	await process_frame

	_open_level_up(main)
	var second_keys := _keys(main, main.p1_choices)
	_check(first_keys != second_keys, "the very next level-up does not offer the identical three cards")
	main.level_up_active = false
	paused = false
	await process_frame


func _titles(choices: Array) -> Array[String]:
	var titles: Array[String] = []
	for option in choices:
		titles.append(String(option["title"]))
	return titles


func _keys(main: Node, choices: Array) -> Array[String]:
	var keys: Array[String] = []
	for option in choices:
		keys.append(String(main._option_key(option)))
	keys.sort()
	return keys


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
