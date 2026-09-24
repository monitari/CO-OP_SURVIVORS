extends SceneTree

## The promise a resonance makes when it absorbs two weapons: the pair get more
## than they gave up. Checked four ways —
##
##   coverage  every enhanced weapon route and every resonance (each fused one
##             with each carrier it can come from) has a measured reference, so
##             nothing is priced from the fallback average by accident
##   silence   a bound weapon stops firing, its aura is taken down, and the HUD
##             ring shows the resonance's charge in its place
##   growth    the resonance follows the weapons: growing one of them grows it
##   trade     live, on the same crowd and boss fields the tables came from, one
##             resonance's damage per second against the two weapons it absorbed
##
## And the smaller promises that ride on it: a fused candidate names the weapon
## that actually carries it, the card states the trade, and an upgraded weapon
## is visibly bigger than it was.

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const ResonancePower := preload("res://scripts/catalogs/resonance_power_catalog.gd")

const PAIR := [Vector2(-90.0, 0.0), Vector2(90.0, 0.0)]
const WINDOW := 8.0
const SPEED := 4.0
const BODY_HEALTH := 1.0e9
## Live runs roll aim and spread; the reference was one seeded run. A trade that
## comes in this close to the promise is the promise kept.
const NOISE := 0.8

## Pairs checked live: two fusions, two hand-made ones, spread across carriers
## that land very differently (a fish, a wave, an area, a line).
const LIVE_PAIRS := [
	["supernova", "sun", "skipping_stone", "ricochet"],
	["thunder_god", "conductor", "cream_tide", "tide"],
	["supernova", "wildfire", "absolute_zero", "shatter"],
	["judgement", "judgement", "starpiercer", "comet"],
]

var failures: Array[String] = []
var main: Node


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_TRADE_FAIL", 600.0)
	call_deferred("_run")


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "RESONANCE_TRADE_FAIL"):
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

	_test_coverage()
	_test_fusion_binding()
	_test_presence()
	await _test_silence()
	_test_growth_follows()
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.time_scale = SPEED
	for pair in LIVE_PAIRS:
		await _test_trade(pair)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60

	if failures.is_empty():
		print("RESONANCE_TRADE_PASS: absorbed weapons stop, the resonance follows their growth and outdeals them")
		quit(0)
	else:
		for failure in failures:
			push_error("RESONANCE_TRADE_FAIL: " + failure)
		quit(1)


func _test_coverage() -> void:
	for evolution in Evolutions.all_evolutions():
		for tech in WeaponTechs.for_weapon(String(evolution["base_weapon_id"])):
			var key := "%s:%s" % [String(evolution["weapon_id"]), String(tech["id"])]
			_check(ResonancePower.WEAPONS.has(key), "no measured reference for weapon route %s — run resonance_power_calibration" % key)
	for resonance in main.resonance_system.catalog:
		if String(resonance.get("kind", "")) != "template":
			_check(ResonancePower.RESONANCES.has(String(resonance["id"])),
				"no measured reference for resonance %s" % resonance["id"])
			continue
		for evolution in Evolutions.all_evolutions():
			if String(evolution["behavior_tag"]) != String(resonance["behavior"]):
				continue
			var key := "fusion:%s:%s" % [String(evolution["weapon_id"]), String(resonance["element"])]
			_check(ResonancePower.RESONANCES.has(key), "no measured reference for fused resonance %s" % key)
	for entry: Array in ResonancePower.WEAPONS.values() + ResonancePower.RESONANCES.values():
		_check(float(entry[0]) > 0.0 and float(entry[1]) > 0.0, "a reference measured zero damage: %s" % [entry])


## 초신성(화염·폭발) + 물수제비 물고기(냉기·유도): the 화염 × 유도 fusion is
## carried by the fish, and says so.
func _test_fusion_binding() -> void:
	var fire := _enhanced("supernova", "sun")
	var fish := _enhanced("skipping_stone", "ricochet")
	var found := {}
	for candidate in main.resonance_system.get_candidates_for_loadouts([fire], [fish]):
		found[String(candidate["id"])] = candidate
	_check(found.has("fire_tracking"), "화염 + 유도 is a candidate for 초신성 + 물수제비 물고기")
	if found.has("fire_tracking"):
		var candidate: Dictionary = found["fire_tracking"]
		_check(String(candidate["carrier"]) == "skipping_stone", "the fish carries 화염 × 유도 (got %s)" % candidate["carrier"])
		_check(ResonanceScript.display_name(candidate) == "업화 물수제비",
			"the fused name names its carrier (got %s)" % ResonanceScript.display_name(candidate))
		var body := String(main._resonance_card_model(candidate, "", Color.WHITE)["body"])
		_check(body.contains("흡수"), "the resonance card states the trade")
	# Two weapons that share the behaviour tag: the one not lending the element
	# carries, so both of them are in the attack.
	var zero := _enhanced("absolute_zero", "shatter")
	var rite := _enhanced("celestial", "ritual")
	for candidate in main.resonance_system.get_candidates_for_loadouts([zero], [rite]):
		if String(candidate["id"]) == "frost_aura":
			_check(String(candidate["carrier"]) == "celestial", "냉기 × 오라 from 절대영도 + 천구 is carried by 천구 (got %s)" % candidate["carrier"])


func _test_presence() -> void:
	var early := _base_state("flame")
	var late := early.duplicate(true)
	late["tier"] = 6
	_check(Growth.presence(late) > Growth.presence(early), "a weapon grows with its level")
	var sun := late.duplicate(true)
	WeaponTechs.apply_to_state(sun, WeaponTechs.by_id("flame", "sun"))
	var wildfire := late.duplicate(true)
	WeaponTechs.apply_to_state(wildfire, WeaponTechs.by_id("flame", "wildfire"))
	_check(Growth.presence(sun) > Growth.presence(wildfire), "a 화력 route grows bigger shots than a 속도 route")
	var nova := _enhanced("supernova", "sun")
	nova["tier"] = 12
	_check(Growth.presence(nova) >= 2.5, "a Lv.12 enhanced 작은 태양 is at least two and a half times its opening size (%.2f)" % Growth.presence(nova))
	# And the ember it fires is that size.
	main.weapon_loadouts[0] = [nova]
	main.attack_timers[0] = [0.0]
	main.weapon_controller.clear_transients()
	_spawn(Vector2(0.0, 200.0), false, 17.0)
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var biggest := 0.0
	for shot in main.weapon_controller.active_projectiles:
		biggest = maxf(biggest, shot.radius)
	_check(biggest >= 9.0 * 2.5, "the enhanced ember is drawn and hits at its grown size (%.1f)" % biggest)


func _test_silence() -> void:
	await _reset(false)
	var nova := _enhanced("supernova", "sun")
	var zero := _enhanced("absolute_zero", "shatter")
	main.weapon_loadouts[0] = [nova]
	main.weapon_loadouts[1] = [zero]
	main.attack_timers[0] = [0.0]
	main.attack_timers[1] = [0.0]
	# The aura is up before the resonance, the way it would be in a run.
	main.weapon_controller.perform_attack(1, 0, 1.0)
	_check(not main.weapon_controller.sustained_fields.is_empty(), "절대영도 holds a sustained aura before it is absorbed")
	var candidates: Array[Dictionary] = main.resonance_system.get_candidates_for_loadouts(main.weapon_loadouts[0], main.weapon_loadouts[1])
	_check(not candidates.is_empty(), "two enhanced weapons produce a resonance candidate")
	if candidates.is_empty():
		return
	main.resonance_system.pending_cores = 1
	main._activate_resonance(candidates[0])
	_check(main.resonance_system.is_bound(0, 0) and main.resonance_system.is_bound(1, 0), "both weapons are bound to the resonance")
	await process_frame
	_check(main.weapon_controller.sustained_fields.is_empty(), "the absorbed 절대영도 takes its aura down with it")
	var before: int = main.weapon_controller.active_projectiles.size()
	main._perform_character_attack(0)
	main._perform_character_attack(1)
	_check(main.weapon_controller.active_projectiles.size() == before, "absorbed weapons do not fire")
	_check(main.weapon_controller.sustained_fields.is_empty(), "an absorbed aura is not rebuilt by a cast")
	var entry: Dictionary = main.resonance_system.bound_entry(0, 0)
	_check(not entry.is_empty() and String(entry["id"]) == String(candidates[0]["id"]), "the slot reports the resonance it feeds")
	main.resonance_system.active_resonances.clear()


## One 화력 card's worth on one absorbed weapon moves the resonance with it.
func _test_growth_follows() -> void:
	var nova := _enhanced("supernova", "sun")
	var fish := _enhanced("skipping_stone", "ricochet")
	main.weapon_loadouts[0] = [nova]
	main.weapon_loadouts[1] = [fish]
	main.attack_timers[0] = [0.0]
	main.attack_timers[1] = [0.0]
	var entry := _candidate("fire_tracking")
	if entry.is_empty():
		_check(false, "화염 + 유도 is available for the growth check")
		return
	var opening: float = main._resonance_power(entry)
	nova["damage"] = float(nova["damage"]) * 3.0
	var grown: float = main._resonance_power(entry)
	_check(grown > opening * 1.4, "tripling one absorbed weapon's damage grows the resonance (%.2f → %.2f)" % [opening, grown])
	main.players[1].might = 2.0
	_check(main._resonance_power(entry) > grown, "the owners' 공격력 feeds the resonance")
	main.players[1].might = 1.0


func _test_trade(pair: Array) -> void:
	var first := _enhanced(String(pair[0]), String(pair[1]))
	var second := _enhanced(String(pair[2]), String(pair[3]))
	main.weapon_loadouts[0] = [first]
	main.weapon_loadouts[1] = [second]
	var candidates: Array[Dictionary] = main.resonance_system.get_candidates_for_loadouts([first], [second])
	var ratios := {}
	for field in ["crowd", "boss"]:
		var boss: bool = field == "boss"
		var weapons := await _weapons_per_second(first, second, boss)
		for candidate in candidates:
			var id := String(candidate["id"])
			main.weapon_loadouts[0] = [first]
			main.weapon_loadouts[1] = [second]
			var power: float = main._resonance_power(candidate)
			var per_second := await _resonance_per_cast(candidate, power, boss) / float(candidate["cooldown"])
			var ratio := per_second / maxf(0.001, weapons)
			if not ratios.has(id):
				ratios[id] = {}
			ratios[id][field] = ratio
			print("RESONANCE_TRADE: %-5s %s + %s → %-22s ×%.2f of the two weapons" % [field, pair[0], pair[2], id, ratio])
			_check(ratio >= ResonanceScript.RESONANCE_FLOOR * NOISE,
				"%s beats the two weapons it absorbed on the %s field (×%.2f)" % [id, field, ratio])
	for id: String in ratios:
		var both: Dictionary = ratios[id]
		if both.has("crowd") and both.has("boss"):
			var mean := sqrt(float(both["crowd"]) * float(both["boss"]))
			_check(mean >= ResonanceScript.RESONANCE_PREMIUM * NOISE,
				"%s is worth the premium across both fields (×%.2f)" % [id, mean])


func _weapons_per_second(first: Dictionary, second: Dictionary, boss: bool) -> float:
	await _reset(boss)
	main.weapon_loadouts[0] = [first]
	main.weapon_loadouts[1] = [second]
	main.attack_timers[0] = [0.0]
	main.attack_timers[1] = [0.0]
	var clock := 0.0
	var timers := [0.0, 0.0]
	while clock < WINDOW:
		for index in 2:
			if float(timers[index]) <= 0.0:
				main.weapon_controller.perform_attack(index, 0, 1.0)
				timers[index] = main._weapon_interval(index, 0)
		var delta := await _tick()
		clock += delta
		for index in 2:
			timers[index] = float(timers[index]) - delta
	return _damage_dealt() / WINDOW


func _resonance_per_cast(entry: Dictionary, power: float, boss: bool) -> float:
	await _reset(boss)
	main.weapon_controller.perform_resonance(entry, power)
	var clock := 0.0
	while clock < 4.5:
		clock += await _tick()
	return _damage_dealt()


func _candidate(id: String) -> Dictionary:
	for candidate in main.resonance_system.get_candidates_for_loadouts(main.weapon_loadouts[0], main.weapon_loadouts[1]):
		if String(candidate["id"]) == id:
			return candidate
	return {}


func _base_state(base_id: String) -> Dictionary:
	for character in CharacterCatalog.all_characters():
		if String(character["weapon_id"]) == base_id:
			return main._build_weapon_state(character)
	return {}


func _enhanced(weapon_id: String, tech_id: String) -> Dictionary:
	var evolution := Evolutions.by_weapon_id(weapon_id)
	var base := _base_state(String(evolution["base_weapon_id"]))
	WeaponTechs.apply_to_state(base, WeaponTechs.by_id(String(evolution["base_weapon_id"]), tech_id))
	base["tier"] = Evolutions.EVOLUTION_TIER
	return Evolutions.build_state(evolution, base)


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


## The same two fields resonance_power_calibration measures on.
func _reset(boss: bool) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	main.enemy_shots.clear()
	await process_frame
	await process_frame
	seed(20260923)
	for index in 2:
		main.players[index].global_position = PAIR[index]
		main.players[index].last_input = Vector2.RIGHT if index == 0 else Vector2.LEFT
		main.players[index].downed = false
	if boss:
		_spawn(Vector2(0.0, 170.0), true, 56.0)
	else:
		# Already surrounded, the way a late screen is: the packs are on the pair
		# and the scatter is closing. Starting them far out favoured the weapons,
		# which fire all window long into a crowd that keeps tightening, over a
		# resonance cast once into the loose field at the start of it.
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


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
