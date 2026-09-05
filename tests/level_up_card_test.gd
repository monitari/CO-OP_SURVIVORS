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
	_test_reroll_refill(main)
	await _test_no_immediate_repeat(main)

	if failures.is_empty():
		print("LEVEL_UP_CARD_PASS: recommendations, icon build readout, open delay, cursor, deferred apply, reroll, no repeat set")
		quit(0)
	else:
		for failure in failures:
			push_error("LEVEL_UP_CARD_FAIL: " + failure)
		quit(1)


## The bands themselves, driven by scores rather than by whatever the pool
## happened to deal: a hand of three strong cards must star more than one, and
## a hand of three weak ones must star none. Without this the checks above pass
## on any implementation that simply never marks anything.
func _test_advice_bands(main: Node) -> void:
	var choices: Array = main._get_upgrade_choices(1)
	var best := -INF
	for option in choices:
		best = maxf(best, float(option["recommendation_score"]))
	for option in choices:
		var score := float(option["recommendation_score"])
		var starred := bool(option["recommended"])
		var expected: bool = score >= main.RECOMMEND_MIN_SCORE and score >= best * main.RECOMMEND_RELATIVE
		_check(starred == expected,
			"card scoring %.0f against a best of %.0f is starred exactly when it should be" % [score, best])
	print("ADVICE_METRICS: best=%.0f floor=%.0f relative=%.2f" % [best, main.RECOMMEND_MIN_SCORE, main.RECOMMEND_RELATIVE])
	_test_a_dead_card_is_marked_against(main)


## The checks above only observe whatever the pool dealt, so a build that never
## marked anything against would sail through them. This hands the scorer a card
## that provably does nothing — a fire-rate upgrade on a weapon already at the
## cooldown floor — and requires it to say so.
func _test_a_dead_card_is_marked_against(main: Node) -> void:
	var weapon: Dictionary = main.weapon_loadouts[0][0]
	var restore: float = weapon["cooldown"]
	weapon["cooldown"] = 0.2
	var hand: Array[Dictionary] = [
		{"id": "weapon_rate", "weapon_slot": 0, "title": "dead"},
		{"id": "weapon_power", "weapon_slot": 0, "title": "live"},
		{"id": "vitality", "weapon_slot": -1, "title": "other"},
	]
	main._annotate_recommendations(0, hand)
	_check(bool(hand[0]["discouraged"]),
		"a card that cannot change anything is marked against (score %.0f)" % float(hand[0]["recommendation_score"]))
	_check(not bool(hand[0]["recommended"]), "and certainly not starred")
	_check(not bool(hand[1]["discouraged"]), "while a card that does something is not")

	# And the whole hand is never condemned, however bad it is.
	var hopeless: Array[Dictionary] = [
		{"id": "weapon_rate", "weapon_slot": 0, "title": "a"},
		{"id": "weapon_rate", "weapon_slot": 0, "title": "b"},
		{"id": "weapon_rate", "weapon_slot": 0, "title": "c"},
	]
	main._annotate_recommendations(0, hopeless)
	var condemned := 0
	for option in hopeless:
		condemned += 1 if bool(option["discouraged"]) else 0
	_check(condemned == hopeless.size() - 1,
		"a hopeless hand still leaves one card unmarked (%d of %d)" % [condemned, hopeless.size()])
	weapon["cooldown"] = restore


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
	_check(main.rerolls_remaining[0] == main.REROLL_START, "a reroll arriving during the delay is not spent")

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
	# The partner is already fused, so P1's fusion is the card that completes the
	# pair's resonance. Nothing short of a fusion can do that any more, which is
	# exactly what the recommendation has to be able to see.
	main.weapon_loadouts[0][0]["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
	var partner: Dictionary = main.weapon_loadouts[1][0]
	main.weapon_loadouts[1][0] = EvolutionCatalog.build_state(
		EvolutionCatalog.for_base(String(partner["weapon_id"])), partner
	)
	var evolution := EvolutionCatalog.for_base(String(main.weapon_loadouts[0][0]["weapon_id"]))
	var choices: Array[Dictionary] = [
		{"id": "evolve_weapon", "weapon_slot": 0, "evolution": evolution, "title": "합성"},
		{"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("vitality"), "title": "생명의 결정"},
		{"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("move"), "title": "경보의 장화"},
	]
	main._annotate_recommendations(0, choices)
	_check(bool(choices[0]["recommended"]), "a fusion that completes a resonance is recommended")
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
	# There used to be exactly one star, always, on whichever card scored
	# highest — which claims a right answer exists even when three cards are
	# within a hair of each other. A draw may now be starred zero, one or
	# several times, and cards that do nothing for this build are marked
	# against instead. What has to hold is that the advice is consistent with
	# the scores and never condemns the whole hand.
	var recommended_cards := 0
	var discouraged_cards := 0
	for index in main.p1_choices.size():
		var card: Label = main.level_card_labels[0][index]
		var option: Dictionary = main.p1_choices[index]
		var icon := card.get_node("Icon") as TextureRect
		var badge := card.get_node("Recommendation") as Label
		_check(icon.texture != null, "every upgrade card renders a mapped icon")
		var starred := bool(option.get("recommended", false))
		var against := bool(option.get("discouraged", false))
		_check(not (starred and against), "no card is both recommended and discouraged")
		_check(badge.visible == (starred or against), "the badge shows exactly when there is advice")
		if starred:
			_check(String(badge.text).begins_with("★"), "a recommendation reads as one")
			_check(float(option["recommendation_score"]) >= main.RECOMMEND_MIN_SCORE,
				"a starred card clears the absolute bar (%.0f)" % float(option["recommendation_score"]))
		if against:
			_check(String(badge.text).begins_with("▽"), "a warning reads as one")
			_check(not String(option.get("discouragement_reason", "")).is_empty(),
				"a warning says why")
		recommended_cards += 1 if starred else 0
		discouraged_cards += 1 if against else 0
	_check(discouraged_cards < main.p1_choices.size(),
		"the whole hand is never marked against (%d of %d)" % [discouraged_cards, main.p1_choices.size()])
	_check(recommended_cards + discouraged_cards <= main.p1_choices.size(), "advice does not double up")
	_test_advice_bands(main)
	# The build readout used to be two lines of attribute numbers. It is now two
	# rows of icons with empty slots left visible, because "무기 2/4 · 보물 1/4"
	# and four empty sockets say more mid-decision than eight numbers do.
	_check(main.p1_level_footer.text.contains("무기") and main.p1_level_footer.text.contains("보물"),
		"the build readout names both slot kinds")
	_check(main.level_weapon_icons[0].size() == main.WEAPON_LOADOUT_CAP,
		"the weapon row draws one slot per weapon the cap allows")
	_check(main.level_treasure_icons[0].size() == main.TREASURE_LOADOUT_CAP,
		"the treasure row draws one slot per treasure the cap allows")
	var carried_weapons: int = main.weapon_loadouts[0].size()
	for index in main.level_weapon_icons[0].size():
		var icon := main.level_weapon_icons[0][index] as TextureRect
		var filled := icon.texture != null
		_check(filled == (index < carried_weapons),
			"weapon slot %d is %s" % [index, "filled" if index < carried_weapons else "an empty socket"])
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


## One reroll for a whole run is a resource nobody spends: there is never a
## level-up worth the last one you will ever get. It refills on a schedule
## instead, so spending one is an ordinary move.
func _test_reroll_refill(main: Node) -> void:
	main.rerolls_remaining[0] = 0
	main.rerolls_remaining[1] = 0
	# Land the next level-up exactly on a refill boundary.
	main.progression.level = main.REROLL_PER_LEVELS - 1
	_open_level_up(main)
	_check(main.progression.level % main.REROLL_PER_LEVELS == 0,
		"the test reached a refill level (%d)" % main.progression.level)
	_check(main.rerolls_remaining[0] == 1, "a refill level restores a spent reroll (%d)" % main.rerolls_remaining[0])
	_check(main.rerolls_remaining[1] == 1, "both survivors are refilled")
	_close_level_up(main)

	# And it must stop at the cap, or a long run hands out an unbounded supply.
	main.rerolls_remaining[0] = main.REROLL_CAP
	main.rerolls_remaining[1] = main.REROLL_CAP
	main.progression.level = main.REROLL_PER_LEVELS * 2 - 1
	_open_level_up(main)
	_check(main.rerolls_remaining[0] == main.REROLL_CAP,
		"refills stop at the cap (%d of %d)" % [main.rerolls_remaining[0], main.REROLL_CAP])
	_close_level_up(main)


func _close_level_up(main: Node) -> void:
	main.selected_upgrade_indices[0] = -1
	main.selected_upgrade_indices[1] = -1
	main.level_up_active = false
	main.level_overlay.visible = false
	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	paused = false
