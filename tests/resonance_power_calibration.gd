extends SceneTree

## Measures what ResonancePowerCatalog prices the resonance trade from, and
## writes the tables back into that file.
##
##     godot --headless --path . --script res://tests/resonance_power_calibration.gd
##
## Not a test (the name does not end in _test, so the suite glob skips it): it
## changes a source file. Run it after changing a weapon's catalogue numbers, a
## route's delivery, or any resonance effect, then run resonance_trade_test to
## confirm the result.
##
## Every enhanced weapon on every route, and every resonance — each fused one
## with every carrier its behaviour tag can come from — is set loose on the same
## two reference fields and its damage summed:
##
##   crowd  three packs already on the pair and a scatter closing from every
##          side, plus one elite. What a late screen looks like.
##   boss   one big elite already close and walking in, and nothing else —
##          close enough that an effect cast around the pair reaches it.
##
## A weapon is fired on its own catalogue cadence for WEAPON_WINDOW seconds and
## reported per second; a resonance is cast once and reported per cast, with
## RESONANCE_WINDOW to let its ticks, shells and mines finish. The pair stand
## still and cannot be hurt, and every body has more health than anything here
## can take, so nothing dies and nothing about the field changes but where the
## effects push it.

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const CATALOGUE_PATH := "res://scripts/catalogs/resonance_power_catalog.gd"
const ResonancePower := preload("res://scripts/catalogs/resonance_power_catalog.gd")

const WEAPON_WINDOW := 8.0
const RESONANCE_WINDOW := 4.5
const PAIR := [Vector2(-90.0, 0.0), Vector2(90.0, 0.0)]
## Run the roof four times faster with four times the ticks, so every physics
## step is still the 1/60 s the game plays at while the whole sweep takes a
## quarter of the wall clock.
const SPEED := 4.0
const BODY_HEALTH := 1.0e9

var main: Node
var write_file := true
## `-- --only=fusion:stigmata` re-measures just the keys starting with that and
## keeps every other entry as it is, for iterating on one effect without paying
## for the whole sweep.
var only := ""


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_CALIBRATION_FAIL", 1500.0)
	write_file = not OS.get_cmdline_user_args().has("--dry-run")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.substr(7)
	call_deferred("_run")


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "RESONANCE_CALIBRATION_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.time_scale = SPEED
	for player in main.players:
		_neutralise(player)

	var weapons: Dictionary = ResonancePower.WEAPONS.duplicate() if not only.is_empty() else {}
	for evolution in Evolutions.all_evolutions():
		var base_id := String(evolution["base_weapon_id"])
		for tech in WeaponTechs.for_weapon(base_id):
			var state := _enhanced_state(evolution, tech)
			var key := "%s:%s" % [String(state["weapon_id"]), String(tech["id"])]
			if not _selected(key):
				continue
			var crowd := await _measure_weapon(state, false)
			var boss := await _measure_weapon(state, true)
			weapons[key] = [snappedf(crowd, 0.01), snappedf(boss, 0.01)]
			print("CALIBRATE weapon %-28s crowd %9.1f/s  boss %8.1f/s" % [key, crowd, boss])

	var resonances: Dictionary = ResonancePower.RESONANCES.duplicate() if not only.is_empty() else {}
	var measured := {}
	for resonance in main.resonance_system.catalog:
		for entry in _variants(resonance):
			var key := ResonancePower.resonance_key(entry)
			if measured.has(key) or not _selected(key):
				continue
			measured[key] = true
			var crowd := await _measure_resonance(entry, false)
			var boss := await _measure_resonance(entry, true)
			resonances[key] = [snappedf(crowd, 0.01), snappedf(boss, 0.01)]
			print("CALIBRATE resonance %-34s crowd %9.1f  boss %8.1f" % [key, crowd, boss])

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if write_file:
		_write(weapons, resonances)
	print("RESONANCE_CALIBRATION_DONE: %d weapon routes, %d resonance effects%s" % [
		weapons.size(), resonances.size(), "" if write_file else " (dry run)"])
	quit(0)


## Every key when no --only was given; otherwise the keys starting with any of
## its comma-separated prefixes.
func _selected(key: String) -> bool:
	if only.is_empty():
		return true
	for prefix in only.split(","):
		if key.begins_with(prefix):
			return true
	return false


## Catalogue numbers, not whatever the character's passives make of them: the
## reference is what a weapon does before anyone has grown anything, and the
## trade multiplies it back up by everything that has been (main._weapon_growth).
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


func _enhanced_state(evolution: Dictionary, tech: Dictionary) -> Dictionary:
	var character := {}
	for candidate in CharacterCatalog.all_characters():
		if String(candidate["weapon_id"]) == String(evolution["base_weapon_id"]):
			character = candidate
	var base: Dictionary = main._build_weapon_state(character)
	WeaponTechs.apply_to_state(base, tech)
	base["tier"] = Evolutions.EVOLUTION_TIER
	return Evolutions.build_state(evolution, base)


## A fused resonance once per carrier its behaviour can come from: 절대영도 and
## 천구 의식 both carry `aura`, and they are two different attacks.
func _variants(resonance: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if String(resonance.get("kind", "")) != "template":
		result.append(resonance)
		return result
	for evolution in Evolutions.all_evolutions():
		if String(evolution["behavior_tag"]) != String(resonance["behavior"]):
			continue
		var entry: Dictionary = resonance.duplicate(true)
		ResonanceScript._name_fusion(entry, String(evolution["weapon_id"]))
		result.append(entry)
	return result


func _measure_weapon(state: Dictionary, boss: bool) -> float:
	await _reset(boss)
	main.weapon_loadouts[0] = [state]
	main.weapon_loadouts[1] = []
	main.attack_timers[0] = [0.0]
	main.attack_timers[1] = []
	var clock := 0.0
	var timer := 0.0
	while clock < WEAPON_WINDOW:
		if timer <= 0.0:
			main.weapon_controller.perform_attack(0, 0, 1.0)
			timer = main._weapon_interval(0, 0)
		var delta := await _tick()
		clock += delta
		timer -= delta
	return _damage_dealt() / WEAPON_WINDOW


func _measure_resonance(entry: Dictionary, boss: bool) -> float:
	await _reset(boss)
	main.weapon_loadouts[0] = []
	main.weapon_loadouts[1] = []
	main.weapon_controller.perform_resonance(entry, 1.0)
	var clock := 0.0
	while clock < RESONANCE_WINDOW:
		clock += await _tick()
	return _damage_dealt()


## One physics step of the reference roof: the bodies walk in, the grid follows
## them, and the pair stay where they are and cannot be hurt.
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


func _write(weapons: Dictionary, resonances: Dictionary) -> void:
	var source := FileAccess.get_file_as_string(CATALOGUE_PATH)
	var begin := source.find("## GENERATED:BEGIN")
	var end := source.find("## GENERATED:END")
	if begin < 0 or end < 0:
		push_error("RESONANCE_CALIBRATION_FAIL: generated markers missing from " + CATALOGUE_PATH)
		quit(1)
		return
	var header_end := source.find("\n", begin) + 1
	var block := "const WEAPONS := {\n%s}\nconst RESONANCES := {\n%s}\n" % [_table(weapons), _table(resonances)]
	var file := FileAccess.open(CATALOGUE_PATH, FileAccess.WRITE)
	file.store_string(source.substr(0, header_end) + block + source.substr(end))
	file.close()


func _table(values: Dictionary) -> String:
	var keys: Array = values.keys()
	keys.sort()
	var lines := ""
	for key: String in keys:
		var pair: Array = values[key]
		lines += "\t\"%s\": [%s, %s],\n" % [key, String.num(float(pair[0]), 2), String.num(float(pair[1]), 2)]
	return lines
