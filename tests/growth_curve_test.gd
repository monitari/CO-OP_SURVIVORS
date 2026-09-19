extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")
const Techs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const EnemyScript := preload("res://scripts/entities/enemy.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "GROWTH_CURVE_FAIL", 90.0)
	call_deferred("_run")


## The shape of a build over a run: weapons and treasures start light and finish
## heavy, a route is chosen at a tier rather than on pickup, and the route decides
## what each card is worth. Each check measures the number a card actually moves,
## not the constant it is built from.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "GROWTH_CURVE_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_weapon_stages_escalate(main)
	_test_route_focus(main)
	_test_every_weapon_asks_for_its_route(main)
	_test_chest_respects_the_route_gate(main)
	_test_evolution_keeps_growth(main)
	_test_treasures_escalate(main)
	_test_route_specials_are_never_dead(main)
	_test_growth_has_a_ceiling(main)
	await _test_overload_blast(main)
	await _test_chain_double_pulse(main)

	if failures.is_empty():
		print("GROWTH_CURVE_PASS: light openings, heavy finishes, route-priced cards, live route specials")
		quit(0)
	else:
		for failure in failures:
			push_error("GROWTH_CURVE_FAIL: " + failure)
		quit(1)


func _character(weapon_id: String) -> Dictionary:
	for character in CharacterCatalog.all_characters():
		if String(character["weapon_id"]) == weapon_id:
			return character
	return {}


func _power_gain(main: Node, state: Dictionary) -> float:
	var copy := state.duplicate(true)
	main.weapon_loadouts[0] = [copy]
	var before := float(copy["damage"])
	main._apply_upgrade(0, {"id": "weapon_power", "weapon_slot": 0})
	return float(main.weapon_loadouts[0][0]["damage"]) / before - 1.0


func _test_weapon_stages_escalate(main: Node) -> void:
	var homing: Dictionary = main._build_weapon_state(_character("homing"))
	_check(float(homing["damage"]) < float(_character("homing")["weapon"]["damage"]) * 0.68,
		"a starting weapon opens lighter than the old 0.68 scale")
	var opening := _power_gain(main, homing)
	var routed := homing.duplicate(true)
	Techs.apply_to_state(routed, Techs.by_id("homing", "comet"))
	routed["tier"] = Growth.TECH_UNLOCK_TIER
	var route := _power_gain(main, routed)
	var evolution: Dictionary = main._selected_evolution_for_state(routed)
	var final_state: Dictionary = EvolutionCatalog.build_state(evolution, routed)
	var final := _power_gain(main, final_state)
	_check(opening < route and route < final,
		"one 화력 card is worth more at each stage (%.2f < %.2f < %.2f)" % [opening, route, final])
	_check(final > 0.126, "an enhanced weapon's card beats the old late-tier 12.6%% (%.3f)" % final)


func _test_route_focus(main: Node) -> void:
	var lightning: Dictionary = main._build_weapon_state(_character("lightning"))
	lightning["tier"] = Growth.TECH_UNLOCK_TIER
	var overload := lightning.duplicate(true)
	Techs.apply_to_state(overload, Techs.by_id("lightning", "overload"))
	var conductor := lightning.duplicate(true)
	Techs.apply_to_state(conductor, Techs.by_id("lightning", "conductor"))
	_check(_power_gain(main, overload) > _power_gain(main, conductor),
		"a force route grows damage faster than a tempo route")
	_check(Growth.rate_step(conductor) < Growth.rate_step(overload),
		"a tempo route grows speed faster than a force route")
	# The balanced third route is gone on purpose: a route that names all four
	# axes specialises in nothing, so every route now leans on exactly two and
	# away from exactly two.
	var untyped: Dictionary = main._build_weapon_state(_character("homing"))
	for axis in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
		_check(is_equal_approx(Growth.focus(untyped, axis), 1.0),
			"a weapon with no route yet leans on nothing (%s)" % axis)
	for weapon_id in ["homing", "lightning", "scythe", "lance", "gravity", "chain"]:
		for tech in Techs.for_weapon(weapon_id):
			var probe: Dictionary = main._build_weapon_state(_character(weapon_id))
			Techs.apply_to_state(probe, tech)
			var favoured := 0
			var reduced := 0
			for axis in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
				favoured += 1 if Growth.focus(probe, axis) > 1.0 else 0
				reduced += 1 if Growth.focus(probe, axis) < 1.0 else 0
			_check(favoured == 2 and reduced == 2,
				"%s/%s leans on two axes and away from two (%d/%d)" % [weapon_id, tech["id"], favoured, reduced])
	main.weapon_loadouts[0] = [overload]
	var preview: String = main._upgrade_preview(0, {"id": "weapon_power", "weapon_slot": 0})
	_check(preview.contains("테크 특화"), "a focused card says so on its face (%s)" % preview)


## 사슬 used to be the one weapon with a single route, so it was assigned one
## silently at Lv.3 and its owner never saw a route card at all. Every weapon
## offers two now, so every weapon asks — there is no weapon whose direction is
## decided for it.
func _test_every_weapon_asks_for_its_route(main: Node) -> void:
	var chain: Dictionary = main._build_weapon_state(_character("chain"))
	_check(String(chain.get("tech_id", "")).is_empty(), "the chain weapon arrives untyped")
	main.weapon_loadouts[0] = [chain]
	main.attack_timers[0] = [0.0]
	while int(main.weapon_loadouts[0][0]["tier"]) < Growth.TECH_UNLOCK_TIER:
		main._apply_upgrade(0, {"id": "weapon_rate", "weapon_slot": 0})
	_check(String(main.weapon_loadouts[0][0].get("tech_id", "")).is_empty(),
		"reaching the unlock tier does not pick a route on the player's behalf")
	var hand: Array[Dictionary] = main._get_upgrade_choices(1)
	_check(hand.size() == 2 and hand.all(func(option: Dictionary) -> bool: return String(option["id"]) == "choose_tech"),
		"it is asked instead, with both routes on the table")


func _test_chest_respects_the_route_gate(main: Node) -> void:
	var gated: Dictionary = main._build_weapon_state(_character("scythe"))
	gated["tier"] = Growth.TECH_UNLOCK_TIER
	main.weapon_loadouts[0] = [gated]
	for candidate in main._chest_upgrade_candidates():
		var option: Dictionary = candidate["option"]
		_check(not (int(candidate["slot"]) == 0 and int(option.get("weapon_slot", -1)) == 0),
			"a chest does not grow a weapon that is waiting on its route")


func _test_evolution_keeps_growth(main: Node) -> void:
	var fresh: Dictionary = main._build_weapon_state(_character("scythe"))
	Techs.apply_to_state(fresh, Techs.by_id("scythe", "execution"))
	fresh["tier"] = EvolutionCatalog.EVOLUTION_TIER
	var grown := fresh.duplicate(true)
	grown["damage"] = float(grown["damage"]) * 2.5
	var evolution: Dictionary = main._selected_evolution_for_state(fresh)
	var from_fresh: Dictionary = EvolutionCatalog.build_state(evolution, fresh)
	var from_grown: Dictionary = EvolutionCatalog.build_state(evolution, grown)
	_check(float(from_grown["damage"]) > float(from_fresh["damage"]) * 1.4,
		"damage grown before the enhancement carries into it (%.1f vs %.1f)" % [float(from_grown["damage"]), float(from_fresh["damage"])])


func _test_treasures_escalate(main: Node) -> void:
	var first := TreasureCatalog.increment("might", 1)
	var last := TreasureCatalog.increment("might", TreasureCatalog.MAX_TIER)
	_check(first < 0.09 and last > 0.09, "격노의 인장 starts below and ends above the old flat 9%% (%.3f → %.3f)" % [first, last])
	_check(TreasureCatalog.cumulative_weight(TreasureCatalog.MAX_TIER) > float(TreasureCatalog.MAX_TIER),
		"a maxed treasure is worth more than the old flat ladder")
	for tier in range(2, TreasureCatalog.MAX_TIER + 1):
		_check(TreasureCatalog.tier_weight(tier) > TreasureCatalog.tier_weight(tier - 1), "tier %d pays more than tier %d" % [tier, tier - 1])
	_check(is_equal_approx(TreasureCatalog.increment("amount", 1), TreasureCatalog.increment("amount", 9)),
		"count treasures keep a flat +1")

	var player: ChainPlayer = main.players[1]
	main.treasure_loadouts[1] = []
	var might_before := player.might
	main._apply_upgrade(1, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": TreasureCatalog.by_id("might")})
	var first_step := player.might - might_before
	for step in 5:
		main._apply_upgrade(1, {"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": 0})
	var before_seventh := player.might
	main._apply_upgrade(1, {"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": 0})
	_check(player.might - before_seventh > first_step * 1.8, "the seventh tier of a treasure pays far more than the first")
	main.treasure_loadouts[1] = [TreasureCatalog.build_state(TreasureCatalog.by_id("might"))]
	main.treasure_loadouts[1][0]["tier"] = 3
	var card: String = main._upgrade_preview(1, {"id": "treasure_upgrade", "treasure_slot": 0})
	_check(card.contains(TreasureCatalog.tier_text(TreasureCatalog.by_id("might"), 4)),
		"a deepen card names what the next tier gives (%s)" % card)


## A route whose delivery pins a field must not leave a special pointing at it.
func _test_route_specials_are_never_dead(main: Node) -> void:
	for weapon_id: String in Techs.TECHS:
		for tech in Techs.for_weapon(weapon_id):
			for key: String in ["a", "b"]:
				var state: Dictionary = main._build_weapon_state(_character(weapon_id))
				Techs.apply_to_state(state, tech)
				state["tier"] = Growth.TECH_UNLOCK_TIER
				var spec: Dictionary = main._special_spec(state, key)
				if spec.is_empty() or String(spec.get("target", "weapon")) == "run":
					continue
				var before := Techs.cast_state(state)
				var after_state := state.duplicate(true)
				main.apply_special_to_state(after_state, key)
				var after := Techs.cast_state(after_state)
				var moved := false
				for field in [String(spec["field"]), "tech_pierce", "splash", "arc", "range", "count", "jumps", "beams"]:
					if before.has(field) and after.has(field) and not is_equal_approx(float(before[field]), float(after[field])):
						moved = true
					elif before.has(field) != after.has(field):
						moved = true
				_check(moved, "%s/%s special %s changes what the weapon casts" % [weapon_id, String(tech["id"]), key])


## Growth rises, and it stops somewhere.
##
## Nothing here used to have a ceiling, and the compounding was the single worst
## balance failure the game had: eleven 화력 cards on a focused route multiplied a
## weapon's damage by thirty-five, 속도 cards drove every weapon in the roster
## onto the same hard 0.25s floor whatever it had started at, and 발사 수 and 반경
## cards simply added their delta forever. By the midpoint of a run the pair were
## an order of magnitude past anything the wave scaling answers, the screen was a
## wall of projectiles, and the frame rate went with it.
##
## Three ceilings, checked against a weapon grown the way a real run grows one.
## The numbers are deliberately loose — this guards the shape, not a tuning pass.
func _test_growth_has_a_ceiling(main: Node) -> void:
	# Every ceiling is a share of the weapon's *own* catalogue entry, and a weapon
	# grown this far has enhanced — so the entry to measure against is the
	# enhanced form's, not the one the run started from. Comparing a 성좌 관통포
	# against 유도 별탄's numbers would be measuring the enhancement, which is
	# supposed to change them, rather than measuring the growth ladder.
	for weapon_id in ["homing", "orbit", "milk"]:
		var character := _character(weapon_id)
		var opening: Dictionary = main._build_weapon_state(character)
		var opening_damage: float = opening["damage"]

		# Every card into 화력 on the route that focuses it — the worst case.
		var powered := _grow(main, character, "weapon_power")
		var multiple := float(powered["damage"]) / opening_damage
		_check(multiple < 20.0,
			"%s: pouring every card into 화력 stays under x20 (x%.1f)" % [weapon_id, multiple])
		_check(multiple > 4.0,
			"%s: and is still worth doing (x%.1f)" % [weapon_id, multiple])

		# Every card into 속도, then the fastest the survivor could ever cast it.
		var hastened := _grow(main, character, "weapon_rate")
		var catalogue_cooldown: float = Growth.catalogue_cooldown(hastened)
		main.weapon_loadouts[0] = [hastened]
		main.attack_timers[0] = [0.0]
		main.players[0].haste = main.HASTE_FLOOR
		var interval: float = main._weapon_interval(0, 0)
		main.players[0].haste = 1.0
		_check(interval >= catalogue_cooldown * Growth.INTERVAL_MIN_RATIO - 0.001,
			"%s: never casts faster than a third of its own catalogue interval (%.2fs of %.2fs)"
				% [weapon_id, interval, catalogue_cooldown])
		_check(interval < catalogue_cooldown * 0.75,
			"%s: and 속도 cards still visibly speed it up (%.2fs of %.2fs)"
				% [weapon_id, interval, catalogue_cooldown])

		# Every card into the count special.
		if opening.has("count"):
			var multiplied := _grow(main, character, "special_a")
			var baseline: Dictionary = main.UpgradeValue.baseline(multiplied)
			var extra := float(multiplied.get("count", 0)) - float(baseline.get("count", 0))
			_check(extra <= float(main.SPECIAL_CAP_BONUS["Count"]) + 0.01,
				"%s: 발사 수 stops at the cap (+%.0f of +%d over its own %d)"
					% [weapon_id, extra, int(main.SPECIAL_CAP_BONUS["Count"]), int(baseline.get("count", 0))])
			_check(extra >= 1.0, "%s: and the card is worth taking at all (+%.0f)" % [weapon_id, extra])


## One weapon grown to the tier ceiling with every card poured into `axis`,
## taking the route that focuses it — which is what a player committed to a
## weapon actually does.
func _grow(main: Node, character: Dictionary, axis: String) -> Dictionary:
	main.weapon_loadouts[0] = [main._build_weapon_state(character)]
	main.attack_timers[0] = [0.0]
	var routes: Array = Techs.for_weapon(String(character["weapon_id"]))
	var chosen: Dictionary = routes[0]
	for route in routes:
		if axis in (route as Dictionary).get("upgrades", []):
			chosen = route
	for step in 40:
		var state: Dictionary = main.weapon_loadouts[0][0]
		if int(state.get("tier", 1)) >= EvolutionCatalog.WEAPON_MAX_TIER:
			break
		if Growth.needs_tech(state):
			main._apply_upgrade(0, {"id": "choose_tech", "weapon_slot": 0, "tech": chosen})
			continue
		var option := {"id": axis, "weapon_slot": 0}
		if not main.UpgradeValue.has_effect(main, 0, option):
			option = {"id": "weapon_power", "weapon_slot": 0}
		main._apply_upgrade(0, option)
		main._apply_pending_evolutions(0)
	return main.weapon_loadouts[0][0]


func _spawn(main: Node, at: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "brute")
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.position = at
	main.add_child(enemy)
	main._register_enemy(enemy)
	return enemy


func _clear(main: Node) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	await process_frame


func _test_overload_blast(main: Node) -> void:
	await _clear(main)
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0, 300)
	main.players[0].crit_chance = 0.0
	var state: Dictionary = main._build_weapon_state(_character("lightning"))
	Techs.apply_to_state(state, Techs.by_id("lightning", "overload"))
	main.weapon_loadouts[0] = [state]
	var struck := _spawn(main, Vector2(150, 0))
	# Beside the first body and outside any one-jump chain: only the blast reaches it.
	var beside := _spawn(main, Vector2(150, 50))
	main.spatial_grid.rebuild(main.enemies)
	var beside_before := beside.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	_check(struck.health < struck.max_health, "과부하 strikes the first body")
	_check(beside.health < beside_before, "과부하's landing blast hits the body beside it")


## 팽팽한 사슬 is the 사슬 weapon's 속도 route, and what makes it one is that the
## pulse runs twice. A route whose delivery is identical to the other one is a
## stat preference wearing a route's name, so this measures the second pulse.
func _test_chain_double_pulse(main: Node) -> void:
	await _clear(main)
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(220, 0)
	var state: Dictionary = main._build_weapon_state(_character("chain"))
	Techs.apply_to_state(state, Techs.by_id("chain", "tether"))
	state["tier"] = Growth.TECH_UNLOCK_TIER
	main.weapon_loadouts[0] = [state]
	main.attack_timers[0] = [0.0]
	var target := _spawn(main, Vector2(110, 0))
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.05).timeout
	var after_first := target.health
	_check(after_first < target.max_health, "the first pulse lands")
	await create_timer(0.4).timeout
	_check(target.health < after_first, "the second pulse follows it (%.0f → %.0f)" % [after_first, target.health])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
