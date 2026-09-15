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
	_test_one_route_weapon_assigns_itself(main)
	_test_chest_respects_the_route_gate(main)
	_test_evolution_keeps_growth(main)
	_test_treasures_escalate(main)
	_test_route_specials_are_never_dead(main)
	await _test_overload_blast(main)
	await _test_eclipse_afterimage(main)

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
	Techs.apply_to_state(routed, Techs.by_id("homing", "constellation"))
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
	var balanced: Dictionary = main._build_weapon_state(_character("homing"))
	Techs.apply_to_state(balanced, Techs.by_id("homing", "constellation"))
	for axis in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
		_check(is_equal_approx(Growth.focus(balanced, axis), 1.0), "a balanced route leans on nothing (%s)" % axis)
	main.weapon_loadouts[0] = [overload]
	var preview: String = main._upgrade_preview(0, {"id": "weapon_power", "weapon_slot": 0})
	_check(preview.contains("테크 특화"), "a focused card says so on its face (%s)" % preview)


func _test_one_route_weapon_assigns_itself(main: Node) -> void:
	var chain: Dictionary = main._build_weapon_state(_character("chain"))
	_check(String(chain.get("tech_id", "")).is_empty(), "a one-route weapon also arrives untyped")
	main.weapon_loadouts[0] = [chain]
	main.attack_timers[0] = [0.0]
	while int(main.weapon_loadouts[0][0]["tier"]) < Growth.TECH_UNLOCK_TIER:
		main._apply_upgrade(0, {"id": "weapon_rate", "weapon_slot": 0})
	_check(not String(main.weapon_loadouts[0][0].get("tech_id", "")).is_empty(),
		"reaching the unlock tier assigns a one-route weapon's only route")
	for option in main._get_upgrade_choices(1):
		_check(String(option["id"]) != "choose_tech", "and never asks the player to pick it")


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


func _test_eclipse_afterimage(main: Node) -> void:
	await _clear(main)
	main.players[0].position = Vector2.ZERO
	var state: Dictionary = main._build_weapon_state(_character("scythe"))
	Techs.apply_to_state(state, Techs.by_id("scythe", "eclipse"))
	state["tier"] = Growth.TECH_UNLOCK_TIER
	main.weapon_loadouts[0] = [state]
	main._apply_upgrade(0, {"id": "special_b", "weapon_slot": 0})
	_check(float(main.weapon_loadouts[0][0].get("afterimage", 0.0)) > 0.0, "월식 잔상 grows the afterimage")
	var target := _spawn(main, Vector2(90, 0))
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.22).timeout
	var after_sweep := target.health
	await create_timer(0.5).timeout
	_check(target.health < after_sweep, "the afterimage sweeps again after the first cut (%.0f → %.0f)" % [after_sweep, target.health])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
