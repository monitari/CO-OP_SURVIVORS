extends SceneTree

## Live damage check on the same 45-enemy roof and boss-sized elite used by the
## resonance calibration. Run with -- --report-only while tuning catalogue,
## or -- --growth-cards-only for matched Power/Rate investment measurements.

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const Techs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")

const WINDOW := 8.0
const GROWTH_WINDOW := 24.0
const SPEED := 6.0
const BODY_HEALTH := 1.0e9
const PAIR := [Vector2(-90.0, 0.0), Vector2(90.0, 0.0)]

var main: Node
var failures: Array[String] = []
var report_only := false
var growth_cards_only := false


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WEAPON_BALANCE_FAIL", 900.0)
	report_only = OS.get_cmdline_user_args().has("--report-only")
	growth_cards_only = OS.get_cmdline_user_args().has("--growth-cards-only")
	call_deferred("_run")


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WEAPON_BALANCE_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame
	for player in main.players:
		_neutralise(player)
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.time_scale = SPEED
	if growth_cards_only:
		await _measure_growth_cards()
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		main.queue_free()
		await process_frame
		if failures.is_empty():
			print("WEAPON_GROWTH_CARDS_PASS: matched live Power/Rate card stacks and cooldown floors")
			quit(0)
		else:
			for failure in failures:
				push_error("WEAPON_GROWTH_CARDS_FAIL: " + failure)
			quit(1)
		return
	var base_scores: Dictionary = {}
	var tech_scores: Dictionary = {}
	var evolved_scores: Dictionary = {}
	for character in CharacterCatalog.all_characters():
		var weapon_id := String(character["weapon_id"])
		var base: Dictionary = main._build_weapon_state(character)
		base_scores[weapon_id] = await _measure_pair(base)
		for tech in Techs.for_weapon(weapon_id):
			var routed := base.duplicate(true)
			Techs.apply_to_state(routed, tech)
			routed["tier"] = 3
			tech_scores["%s:%s" % [weapon_id, String(tech["id"])]] = await _measure_pair(routed)
			var evolution := Evolutions.for_base(weapon_id)
			if not evolution.is_empty():
				var enhanced := Evolutions.build_state(evolution, routed)
				evolved_scores["%s:%s" % [weapon_id, String(tech["id"])]] = await _measure_pair(enhanced)

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if base_scores.size() != 12 or tech_scores.size() != 24 or evolved_scores.size() != 24:
		failures.append("the measurement must cover all 12 weapons and both routes")
	_report("base", base_scores)
	_report("tech", tech_scores)
	_report("evolved", evolved_scores)
	_check_power("base", base_scores, 3.0)
	_check_power("base crowd", base_scores, 3.0, true)
	_check_power("evolved", evolved_scores, 3.0)
	_check_boss_damage(base_scores, evolved_scores)
	if report_only or failures.is_empty():
		print("WEAPON_BALANCE_PASS: measured %d base, %d tech and %d evolved routes%s" % [
			base_scores.size(), tech_scores.size(), evolved_scores.size(), " (report only)" if report_only else ""])
		quit(0)
	else:
		for failure in failures:
			push_error("WEAPON_BALANCE_FAIL: " + failure)
		quit(1)


## Run the same live weapon against the same enemy field after matched numbers
## of power and rate cards. Route selection itself is included, since its lead
## axis is part of what a real run invests before later cards are dealt.
func _measure_growth_cards() -> void:
	var lightning_character: Dictionary = {}
	var orbit_character: Dictionary = {}
	for character in CharacterCatalog.all_characters():
		match String(character["weapon_id"]):
			"lightning": lightning_character = character
			"orbit": orbit_character = character
	if lightning_character.is_empty() or orbit_character.is_empty():
		failures.append("growth comparison could not find lightning and orbit characters")
		return
	var lightning_base: Dictionary = main._build_weapon_state(lightning_character)
	await _measure_growth_context("lightning:opening", lightning_base, [1, 2], true)
	var lightning_routes: Dictionary = {}
	for tech in Techs.for_weapon("lightning"):
		var routed := _choose_route(lightning_base, tech)
		lightning_routes[String(tech["id"])] = routed
		await _measure_growth_context("lightning:" + String(tech["id"]), routed, [1, 2, 3, 5, 8], true)
	var evolved := Evolutions.build_state(Evolutions.for_base("lightning"), lightning_routes["conductor"])
	evolved["tier"] = Evolutions.EVOLUTION_TIER
	await _measure_growth_context("thunder_god:conductor", evolved, [1, 3, 5], true)

	var orbit_base: Dictionary = main._build_weapon_state(orbit_character)
	var ritual := Techs.by_id("orbit", "ritual")
	var orbit_routed := _choose_route(orbit_base, ritual)
	await _measure_growth_context("orbit:ritual", orbit_routed, [1, 3, 5, 7, 8], false)


func _choose_route(base_state: Dictionary, tech: Dictionary) -> Dictionary:
	main.weapon_loadouts[0] = [base_state.duplicate(true)]
	main.weapon_loadouts[1] = []
	# Every weapon reaches Lv.3 before route choice. Apply one opening Power and
	# Rate card, then let the route pay its own focused lead card as in a real run.
	main._apply_upgrade(0, {"id": "weapon_power", "weapon_slot": 0})
	main._apply_upgrade(0, {"id": "weapon_rate", "weapon_slot": 0})
	main._apply_upgrade(0, {"id": "choose_tech", "weapon_slot": 0, "tech": tech})
	var routed: Dictionary = main.weapon_loadouts[0][0]
	return routed.duplicate(true)


func _measure_growth_context(label: String, source: Dictionary, counts: Array[int], include_boss: bool) -> void:
	var baseline_state := source.duplicate(true)
	main.weapon_loadouts[0] = [baseline_state]
	var baseline: Array[float]
	if include_boss:
		baseline = await _measure_pair(baseline_state, GROWTH_WINDOW)
	else:
		baseline = [snappedf(await _measure(baseline_state, false, GROWTH_WINDOW), 0.01), 0.0]
	print("WEAPON_GROWTH_BASE %-28s crowd %8.1f/s boss %8.1f/s tier %d cd %.3f floor %.3f" % [
		label, baseline[0], baseline[1], int(baseline_state.get("tier", 1)),
		float(baseline_state.get("cooldown", 0.0)), Growth.cooldown_floor(baseline_state)])
	for axis in ["weapon_power", "weapon_rate"]:
		for count in counts:
			var grown := source.duplicate(true)
			main.weapon_loadouts[0] = [grown]
			for _card in count:
				main._apply_upgrade(0, {"id": axis, "weapon_slot": 0})
			var crowd := await _measure(grown, false, GROWTH_WINDOW)
			var boss := await _measure(grown, true, GROWTH_WINDOW) if include_boss else 0.0
			var interval: float = main._weapon_interval(0, 0)
			print("WEAPON_GROWTH %-28s %-12s cards %d crowd %8.1f/s (%5.1f%%) boss %8.1f/s (%5.1f%%) tier %2d cd %.3f floor %.3f interval %.3f" % [
				label, axis, count, crowd, 100.0 * crowd / maxf(baseline[0], 0.001),
				boss, 100.0 * boss / maxf(baseline[1], 0.001) if include_boss else 0.0,
				int(grown.get("tier", 1)), float(grown.get("cooldown", 0.0)),
				Growth.cooldown_floor(grown), interval])

func _measure_pair(state: Dictionary, window_seconds := WINDOW) -> Array[float]:
	var crowd := await _measure(state, false, window_seconds)
	var boss := await _measure(state, true, window_seconds)
	return [snappedf(crowd, 0.01), snappedf(boss, 0.01)]


func _measure(state: Dictionary, boss: bool, window_seconds := WINDOW) -> float:
	await _reset(boss)
	main.weapon_loadouts[0] = [state]
	main.weapon_loadouts[1] = []
	main.attack_timers[0] = [0.0]
	main.attack_timers[1] = []
	var clock := 0.0
	var timer := 0.0
	while clock < window_seconds:
		if timer <= 0.0:
			main.weapon_controller.perform_attack(0, 0, 1.0)
			timer = main._weapon_interval(0, 0)
		var delta := await _tick()
		clock += delta
		timer -= delta
	return _damage_dealt() / window_seconds


func _tick() -> float:
	await physics_frame
	var delta := 1.0 / 60.0
	for index in 2:
		var player: ChainPlayer = main.players[index]
		player.global_position = PAIR[index]
		player.invulnerability = 10.0
		player.health = BODY_HEALTH
	for enemy in main.enemies:
		if is_instance_valid(enemy):
			enemy.step(main.players, delta)
	main.spatial_grid.rebuild(main.enemies)
	return delta


func _reset(boss: bool) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	main.enemy_shots.clear()
	await process_frame
	await process_frame
	main.spatial_grid.rebuild(main.enemies)
	# Delayed blasts can fire after clear_transients; drain them on an empty field.
	await create_timer(0.7).timeout
	seed(20260923)
	for index in 2:
		main.players[index].global_position = PAIR[index]
		main.players[index].last_input = Vector2.RIGHT if index == 0 else Vector2.LEFT
		main.players[index].downed = false
	if boss:
		_spawn(Vector2(0.0, 170.0), true, 56.0)
	else:
		for pack in 3:
			var centre := Vector2.from_angle(deg_to_rad(20.0 + 120.0 * pack)) * 210.0
			for body in 8:
				_spawn(centre + Vector2.from_angle(TAU * body / 8.0) * randf_range(10.0, 50.0), false, 17.0)
		for body in 20:
			_spawn(Vector2.from_angle(randf() * TAU) * randf_range(90.0, 400.0), false, 17.0)
		_spawn(Vector2(0.0, 250.0), true, 40.0)
	main.spatial_grid.rebuild(main.enemies)


func _spawn(at: Vector2, elite: bool, radius: float) -> void:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "brute" if elite else "chaser", elite)
	enemy.radius = radius
	enemy.health = BODY_HEALTH
	enemy.max_health = BODY_HEALTH
	enemy.position = at
	main.add_child(enemy)
	main._register_enemy(enemy)


func _damage_dealt() -> float:
	var total := 0.0
	for enemy in main.enemies:
		if is_instance_valid(enemy):
			total += enemy.max_health - enemy.health
	return total


func _neutralise(player: ChainPlayer) -> void:
	player.might = 1.0
	player.amount = 0.0
	player.haste = 1.0
	player.area = 1.0
	player.duration = 1.0
	player.projectile_speed = 1.0
	player.crit_chance = 0.0
	player.pierce = 0
	player.thorns = 0.0
	player.max_health = BODY_HEALTH
	player.health = BODY_HEALTH


func _report(label: String, scores: Dictionary) -> void:
	var keys := scores.keys()
	keys.sort()
	for key in keys:
		var pair: Array = scores[key]
		print("WEAPON_BALANCE %-8s %-24s crowd %9.1f/s boss %8.1f/s" % [label, key, pair[0], pair[1]])


## Crowd damage is the primary survival pressure; boss damage gets triple
## weight so area-only builds cannot pass with nearly no single-target damage.
func _score(pair: Array) -> float:
	return float(pair[0]) + 3.0 * float(pair[1])


func _check_power(label: String, scores: Dictionary, max_ratio: float, crowd_only := false) -> void:
	var low := INF
	var high := 0.0
	var low_key := ""
	var high_key := ""
	for key in scores:
		var score := float((scores[key] as Array)[0]) if crowd_only else _score(scores[key])
		if score < low:
			low = score
			low_key = key
		if score > high:
			high = score
			high_key = key
	print("WEAPON_BALANCE_RATIO %s %.2f (%s %.1f, %s %.1f)" % [label, high / maxf(low, 0.001), high_key, high, low_key, low])
	if low <= 0.0 or high > low * max_ratio:
		failures.append("%s damage exceeds %.1fx: %s / %s" % [label, max_ratio, high_key, low_key])


func _check_boss_damage(base_scores: Dictionary, evolved_scores: Dictionary) -> void:
	if float((base_scores["milk"] as Array)[1]) <= 0.0:
		failures.append("milk must hit the lone boss")
	for key in evolved_scores:
		if float((evolved_scores[key] as Array)[1]) < 35.0:
			failures.append("%s has less than 35 boss DPS" % key)
