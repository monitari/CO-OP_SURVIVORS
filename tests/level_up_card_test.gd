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
	_test_hand_composition(main)
	_test_recommendation_and_build_readout(main)
	_test_luck_and_fan_hand(main)
	await _test_cursor_and_deferred_apply(main)
	await _test_reroll(main)
	_test_reroll_refill(main)
	await _test_no_immediate_repeat(main)

	if failures.is_empty():
		print("LEVEL_UP_CARD_PASS: recommendations, four-card fan, direct selection, cursor and reroll flow")
		quit(0)
	else:
		for failure in failures:
			push_error("LEVEL_UP_CARD_FAIL: " + failure)
		quit(1)


## What a hand is made of.
##
## The pool used to be one flat shuffle in which every owned weapon had four
## entries (화력 · 속도 · 특성 A · 특성 B) and every owned treasure one, against a
## couple of new-weapon cards. A survivor with a full loadout was drawing three
## cards from roughly twenty that all said "make what you already have bigger",
## which is why the opening of a run read as a formality: the same weapon was
## offered a damage card nearly every level and simply snowballed.
##
## Two properties replaced it and this is what holds them honest:
##
##   1. a weapon takes at most one slot in a hand, whatever its own axes offer
##   2. while a slot is open, every hand carries one piece of gear the survivor
##      has never held, so discovery does not depend on the shuffle
##
## Sampled over many draws, since both are claims about every hand rather than
## about a lucky one.
func _test_hand_composition(main: Node) -> void:
	# Four weapons, deliberately grown past the route gate so each of them has
	# several axes to offer and would have flooded the old pool.
	while main.weapon_loadouts[0].size() < main.WEAPON_LOADOUT_CAP:
		var candidates: Array = main._pick_unowned_characters(0, 1)
		if candidates.is_empty():
			break
		main._apply_upgrade(0, {"id": "unlock_weapon", "weapon_slot": -1, "character": candidates[0]})
	for weapon_slot in main.weapon_loadouts[0].size():
		for step in 3:
			var option := {"id": "weapon_power", "weapon_slot": weapon_slot}
			if main.WeaponGrowthScript.needs_tech(main.weapon_loadouts[0][weapon_slot]):
				var routes: Array = main.WeaponTechs.for_weapon(
					String(main.weapon_loadouts[0][weapon_slot].get("base_weapon_id",
						main.weapon_loadouts[0][weapon_slot]["weapon_id"])))
				option = {"id": "choose_tech", "weapon_slot": weapon_slot, "tech": routes[0]}
			main._apply_upgrade(0, option)

	var worst_crowding := 0
	var discovery_missing := 0
	var draws := 40
	for draw in draws:
		main.last_upgrade_choice_keys[0] = []
		var hand: Array = main._get_upgrade_choices(1)
		var per_weapon: Dictionary = {}
		var discovery := 0
		for option in hand:
			var id := String((option as Dictionary)["id"])
			if id in ["unlock_weapon", "unlock_treasure"]:
				discovery += 1
				continue
			var weapon_slot: int = int((option as Dictionary).get("weapon_slot", -1))
			if weapon_slot < 0:
				continue
			per_weapon[weapon_slot] = int(per_weapon.get(weapon_slot, 0)) + 1
			worst_crowding = maxi(worst_crowding, int(per_weapon[weapon_slot]))
		if main.treasure_loadouts[0].size() < main.TREASURE_LOADOUT_CAP and discovery == 0:
			discovery_missing += 1
	_check(worst_crowding <= 1,
		"no weapon takes more than one card in a hand (worst seen: %d in %d draws)"
			% [worst_crowding, draws])
	_check(discovery_missing == 0,
		"every hand offers gear the survivor has never held while a slot is open (%d of %d draws did not)"
			% [discovery_missing, draws])


## The bands themselves, driven by scores rather than by whatever the pool
## happened to deal. Four properties, and between them they rule out both ways
## of passing the checks above by doing nothing useful — an implementation that
## never marks anything, and one that marks everything.
##
##   1. nothing below the bar is starred
##   2. the weakest card in a hand is never starred, so a hand is never entirely
##      recommended
##   3. at most half a hand carries a star
##   4. a hand whose cards are all within ADVICE_MIN_SPREAD of each other is
##      not starred at all — the screen declines to invent a right answer
##
## The bar is the absolute floor or a share of the best card, whichever is
## higher, which is the rule main.gd applies.
func _test_advice_bands(main: Node) -> void:
	var choices: Array = main._get_upgrade_choices(1)
	var best := -INF
	var worst := INF
	for option in choices:
		best = maxf(best, float(option["recommendation_score"]))
		worst = minf(worst, float(option["recommendation_score"]))
	var bar: float = maxf(main.RECOMMEND_MIN_SCORE, best * main.RECOMMEND_RELATIVE)
	var flat: bool = best - worst < main.ADVICE_MIN_SPREAD
	var starred := 0
	for option in choices:
		var score := float(option["recommendation_score"])
		if not bool(option["recommended"]):
			continue
		starred += 1
		_check(not flat, "a hand of cards within a hair of each other stars none of them")
		_check(score >= bar, "a starred card clears the bar (%.0f against %.0f)" % [score, bar])
		_check(score > worst, "the weakest card in the hand is not the one starred")
	_check(starred <= maxi(1, choices.size() / 2),
		"at most half a hand is starred (%d of %d)" % [starred, choices.size()])
	print("ADVICE_METRICS: best=%.0f worst=%.0f bar=%.0f starred=%d" % [best, worst, bar, starred])
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
		var treasures: Array = []
		for treasure in main.treasure_loadouts[slot]:
			treasures.append("%s@%d" % [String(treasure["id"]), int(treasure.get("tier", 1))])
		var player: ChainPlayer = main.players[slot]
		# The attributes, plus the two loadouts themselves.
		#
		# Listing attributes alone could never be complete: a card may move any
		# of ~20 player and team fields, and the list here was missing crit,
		# dodge, pierce, duration, thorns and every shared-treasure effect — so a
		# hand where both survivors happened to take a 처형자의 표식 or a 질주
		# 발톱 read as "nothing was applied" and failed the test at random. The
		# loadouts close it structurally instead: a treasure card always changes
		# treasure_loadouts and a weapon card always changes a weapon tier, so no
		# card can be invisible here regardless of which field it touches.
		snapshot.append("%.2f|%.2f|%.3f|%.3f|%.3f|%d|%.3f|%.2f|%.2f|%.3f|%.3f|%d|%.3f|%s" % [
			player.move_speed, player.max_health,
			player.might, player.area, player.projectile_speed, player.amount,
			player.haste, player.armor, player.recovery,
			player.crit_chance, player.dodge_chance, player.pierce, player.duration,
			"/".join(weapons) + "#" + "/".join(treasures)
		])
	snapshot.append("%.3f|%.3f|%d|%.2f" % [
		main.team_magnet, main.team_growth, main.team_luck, main.chain_max_length])
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
	# The partner is already enhanced, so P1's enhancement is the card that completes the
	# pair's resonance. Nothing short of an enhancement can do that any more, which is
	# exactly what the recommendation has to be able to see.
	main.WeaponTechs.apply_to_state(main.weapon_loadouts[0][0],
		main.WeaponTechs.for_weapon(String(main.weapon_loadouts[0][0]["weapon_id"]))[0])
	main.weapon_loadouts[0][0]["tier"] = EvolutionCatalog.EVOLUTION_TIER - 1
	var partner: Dictionary = main.weapon_loadouts[1][0]
	main.weapon_loadouts[1][0] = EvolutionCatalog.build_state(
		EvolutionCatalog.for_base(String(partner["weapon_id"])), partner
	)
	# The tier card that takes this weapon to Lv.7 is the one that completes the
	# pair's resonance, because Lv.7 enhances on the spot.
	var choices: Array[Dictionary] = [
		{"id": "weapon_power", "weapon_slot": 0, "title": "마력 증폭"},
		{"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("vitality"), "title": "생명의 결정"},
		{"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("move"), "title": "경보의 장화"},
	]
	main._annotate_recommendations(0, choices)
	_check(bool(choices[0]["recommended"]), "an enhancement that completes a resonance is recommended")
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
		_check(badge.visible, "every card shows recommended, discouraged or neutral advice")
		if starred:
			_check(String(badge.text).begins_with("👍"), "a recommendation reads as one")
			_check(float(option["recommendation_score"]) >= main.RECOMMEND_MIN_SCORE,
				"a starred card clears the absolute bar (%.0f)" % float(option["recommendation_score"]))
		if against:
			_check(String(badge.text).begins_with("👎"), "a warning reads as one")
			_check(not String(option.get("discouragement_reason", "")).is_empty(),
				"a warning says why")
		recommended_cards += 1 if starred else 0
		discouraged_cards += 1 if against else 0
	_check(discouraged_cards < main.p1_choices.size(),
		"the whole hand is never marked against (%d of %d)" % [discouraged_cards, main.p1_choices.size()])
	_check(recommended_cards + discouraged_cards <= main.p1_choices.size(), "advice does not double up")
	_test_advice_bands(main)
	# The in-world growth moment draws only the cards and the reroll action: the
	# band holds no loose panels, labels or icons of its own.
	for child in main.level_overlay.get_children():
		_check(child is Label and child in main.level_card_labels[0] + main.level_card_labels[1]
			or child is Button or child.name in ["PartnerChoice", "NeonHint", "NeonControls"],
			"growth band child %s is a card, a button or the partner caption" % child.name)


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
	_check(not main.level_overlay.get_node("Reroll0").visible and main.level_overlay.get_node("Reroll1").visible,
		"only the active player's reroll remains after focus passes")
	# The partner's unreadably small fan is replaced by one summary note. It
	# carries the chosen title and state without covering the active hand.
	for index in main.p1_choices.size():
		var locked_card: Label = main.level_card_labels[0][index]
		_check(not locked_card.visible, "the partner's full cards do not overlap the active hand")
	_check(main.level_overlay.get_node("PartnerChoice/Captions/State").text == "✓ 선택 완료",
		"the partner summary shows that their choice is locked")
	_check(not main.level_overlay.get_node("PartnerChoice/Captions/Title").text.is_empty(),
		"the partner summary names the chosen growth")

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


func _test_luck_and_fan_hand(main: Node) -> void:
	seed(88021)
	main.team_luck = 0
	var ordinary_fourths := 0
	for draw in 500:
		ordinary_fourths += 1 if main._growth_choice_count() == 4 else 0
	main.team_luck = 4
	var lucky_fourths := 0
	for draw in 500:
		lucky_fourths += 1 if main._growth_choice_count() == 4 else 0
	_check(ordinary_fourths == 0, "zero luck keeps the normal three-card hand")
	_check(lucky_fourths > 90 and lucky_fourths < 190,
		"luck four produces a fourth option sometimes, not always (%d/500)" % lucky_fourths)

	main.team_luck = 20
	main.selected_upgrade_indices[0] = -1
	main.upgrade_cursors[0] = 0
	for attempt in 20:
		main.p1_choices = main._get_upgrade_choices(1)
		if main.p1_choices.size() == 4:
			break
	main._refresh_level_up_ui()
	_check(main.level_card_labels[0].size() == 6 and main.p1_choices.size() == 4,
		"the UI has a real fourth card slot when luck grants it")
	var cards: Array = main.level_card_labels[0].filter(func(card: Control) -> bool: return card.visible)
	# A fan overlaps on purpose. What has to hold is that each card steps clear
	# of the one before it, so all four titles stay readable, and that a lucky
	# fourth card keeps the shape a three-card hand has instead of re-flowing
	# the screen into a grid.
	for index in range(1, cards.size()):
		var step: float = cards[index].position.x - cards[index - 1].position.x
		_check(step >= 100.0 and step <= cards[index].size.x + 24,
			"four cards leave each candidate reachable")
	var focused: int = main.upgrade_cursors[0]
	for index in cards.size():
		var card: Label = cards[index]
		_check(card.scale.is_equal_approx(Vector2.ONE), "focus does not enlarge a growth card")
		var rest: Vector2 = card.get_meta("neon_rest_position")
		var destination: Vector2 = card.get_meta("neon_lifted_position")
		if index == focused:
			var local_lift := destination - rest
			_check(local_lift.dot(Vector2.UP.rotated(card.rotation)) > 20.0,
				"the focused card rises along its own axis without losing the fan angle")
		else:
			_check(destination.distance_to(rest) < 0.1,
				"unfocused cards rest in the fan")
	_check(int(cards[focused].z_index) > int(cards[(focused + 1) % cards.size()].z_index),
		"the focused card lifts clear of its neighbours")
	# Outer cards sit lower than the middle of the fan, which is what makes it
	# read as a hand — and is also the thing most likely to fall off the band.
	for card: Label in cards:
		_check(card.position.y + card.size.y <= main.level_overlay.size.y,
			"the fan stays inside the growth band (%.0f of %.0f)" % [
				card.position.y + card.size.y, main.level_overlay.size.y])
		_check(not card.get_rect().intersects(main.level_overlay.get_node("Reroll0").get_rect()),
			"fan cards never cover the reroll button")
		_check(card.position.x >= 0.0 and card.position.x + card.size.x <= 1280,
			"all four cards stay inside the viewport")
	print("FAN_METRICS: cards=%s" % str(cards.map(func(card: Label) -> String: return "%s/%s" % [card.position, card.size])))
	main.level_card_labels[0][3].mouse_entered.emit()
	_check(main.upgrade_cursors[0] == 3 and main.level_card_labels[0][3].scale.is_equal_approx(Vector2.ONE),
		"mouse hover moves the cursor without resizing the card")
	# Check rotated corners, not just unrotated rectangles, at every focus.
	for cursor in cards.size():
		main.upgrade_cursors[0] = cursor
		main._refresh_level_up_ui()
		for card: Label in cards:
			var style := card.get_theme_stylebox("normal") as StyleBoxFlat
			_check(is_equal_approx(card.modulate.a * style.bg_color.a, 1.0),
				"overlapping cards never show the text behind them")
			for corner: Vector2 in [Vector2.ZERO, Vector2(card.size.x, 0), card.size, Vector2(0, card.size.y)]:
				var point := card.get_transform() * corner
				_check(point.x >= 0.0 and point.x <= 1280 and point.y >= 30.0 and point.y < 444.0,
					"rotated card corners stay inside the viewport above the action buttons")
	_check(main.level_overlay.has_node("Reroll0") and not main.level_overlay.has_node("Confirm0")
		and not main.level_overlay.has_node("Cancel0"),
		"the fan keeps only its reroll action")
	main.team_luck = 0
	main.p1_choices = main._get_upgrade_choices(1)
	main.p2_choices = main._get_upgrade_choices(2)
	main._refresh_level_up_ui()


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
