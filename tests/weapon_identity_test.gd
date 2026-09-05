extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WEAPON_IDENTITY_FAIL", 240.0)
	call_deferred("_run")


## Ten weapons that play differently, not ten damage numbers.
##
## Four of them — 궤도 파편, 관통 광선, 지뢰 결계, 중력 붕괴 — had no unique
## upgrades at all, so half the roster could only ever be handed "+25% damage"
## and "-12% cooldown" for a whole run. And 중력 붕괴 collapsed on the caster,
## which made a control weapon into a thing that only ever fired once the
## problem had already arrived.
##
## These checks pin the parts that a stat block cannot show: that every weapon
## has two specials which actually move something, that the recommendation
## scorer prices them, and that the three reworked deliveries deliver where
## they claim to.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WEAPON_IDENTITY_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_every_weapon_has_specials(main)
	await _test_gravity_casts_at_the_crowd(main)
	await _test_chain_pulse_reads_the_leash(main)
	await _test_lance_splits_into_beams(main)
	_test_leash_upgrade_lengthens_the_chain(main)
	await _test_orbit_hits_once_per_shard(main)

	if failures.is_empty():
		print("WEAPON_IDENTITY_PASS: ten weapons, twenty working specials, four reworked deliveries")
		quit(0)
	else:
		for failure in failures:
			push_error("WEAPON_IDENTITY_FAIL: " + failure)
		quit(1)


## Every base weapon declares two specials, each one changes a real field, and
## each one prints something other than the fallback sentence. Driven off the
## catalog rather than a list here, so a survivor added later is covered without
## anyone remembering to come back.
func _test_every_weapon_has_specials(main: Node) -> void:
	for character in CharacterCatalog.all_characters():
		var name := String(character["name"])
		var state: Dictionary = main._build_weapon_state(character)
		main.weapon_loadouts[0] = [state]
		main.attack_timers[0] = [0.0]
		for key: String in ["a", "b"]:
			var spec: Dictionary = main._special_spec(String(character["weapon_id"]), key)
			_check(not spec.is_empty(), "%s's weapon declares special %s" % [name, key])
			if spec.is_empty():
				continue
			_check(main._special_has_room(0, 0, key), "%s's special %s has somewhere to go" % [name, key])

			var option := {"id": "special_" + key, "weapon_slot": 0}
			var preview: String = main._upgrade_preview(0, option)
			_check(preview != "현재 능력을 강화합니다.",
				"%s's special %s previews what it changes (%s)" % [name, key, preview])
			_check(preview.contains("→"), "%s's special %s previews a before and after" % [name, key])

			# The upgrade has to actually land. Run-target specials change the
			# leash instead of the weapon, so they are measured on that.
			var before: float = main._special_current(spec, state)
			main._apply_upgrade(0, option)
			var after: float = main._special_current(spec, main.weapon_loadouts[0][0])
			_check(not is_equal_approx(before, after),
				"%s's special %s moves %s (%.2f)" % [name, key, String(spec["field"]), after])

			# And the card pool has to be able to offer it, or it is unreachable.
			# Fifteen draws rather than forty: each draw runs the whole scoring
			# pass, and at twenty specials the old count made this the slowest
			# test in the suite for no extra confidence.
			var offered := false
			for draw in 15:
				for candidate in main._get_upgrade_choices(1):
					if String(candidate["id"]) == "special_" + key and int(candidate["weapon_slot"]) == 0:
						offered = true
			_check(offered, "%s's special %s is reachable from the card pool" % [name, key])
			main.weapon_loadouts[0] = [main._build_weapon_state(character)]


## 중력 붕괴 used to collapse on the caster, so it could only ever hit things
## that had already closed to within its own radius. It now picks the nearest
## enemy inside cast_range and collapses there. The discriminator: an enemy
## further away than the collapse radius but inside the cast range has to be
## damaged, which the old version could never do.
func _test_gravity_casts_at_the_crowd(main: Node) -> void:
	await _clear_enemies(main)
	main.players[0].area = 1.0
	var gravity: Dictionary = main._build_weapon_state(CharacterCatalog.all_characters()[9])
	_check(String(gravity["weapon_id"]) == "gravity", "the fixture picked the gravity survivor")
	main.weapon_loadouts[0] = [gravity]
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 90.0)

	var radius := float(gravity["radius"])
	var neighbour := _spawn(main, Vector2(radius + 180.0, 0.0))
	var anchor := _spawn(main, Vector2(radius + 260.0, 0.0))
	main.spatial_grid.rebuild(main.enemies)
	_check(main.players[0].global_position.distance_to(anchor.global_position) > radius,
		"the fixture puts the crowd outside the collapse radius")

	var neighbour_before := neighbour.global_position.x
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.16).timeout
	_check(neighbour.global_position.x > neighbour_before and neighbour.global_position.x < anchor.global_position.x,
		"the pull travels over time instead of teleporting the crowd")
	await create_timer(0.7).timeout
	print("GRAVITY_METRICS: anchor=%.1f neighbour=%.1f moved=%.1f" % [anchor.max_health - anchor.health, neighbour.max_health - neighbour.health, neighbour.global_position.x - neighbour_before])
	_check(anchor.health < anchor.max_health, "the collapse lands on the crowd, not on the caster")
	_check(neighbour.health < neighbour.max_health, "and catches what is standing with it")
	_check(neighbour.global_position.x > neighbour_before,
		"and finishes closer to the anchor rather than the survivors")

	# With nothing in range it must not silently revert to the old behaviour of
	# detonating on top of the pair.
	await _clear_enemies(main)
	var underfoot := _spawn(main, Vector2(20.0, 0.0))
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.55).timeout
	_check(underfoot.health < underfoot.max_health, "something already on top of the pair is still hit")
	await _clear_enemies(main)


## 결속 파동 is the one weapon that reads how the pair is standing. A slack
## chain is a weak pulse; a stretched one is the pair spending safety for damage.
func _test_chain_pulse_reads_the_leash(main: Node) -> void:
	await _clear_enemies(main)
	main.weapon_loadouts[0] = [main._build_weapon_state(CharacterCatalog.all_characters()[5])]
	_check(String(main.weapon_loadouts[0][0]["weapon_id"]) == "chain", "the fixture picked the tether survivor")
	main.players[0].position = Vector2(-100.0, 0.0)
	main.players[1].position = Vector2(100.0, 0.0)

	var slack := _measure_chain_hit(main, 0.0)
	var stretched := _measure_chain_hit(main, 1.0)
	_check(slack > 0.0, "the tether damages what stands on it (%.1f)" % slack)
	_check(stretched > slack * 1.2,
		"a stretched chain hits harder than a slack one (%.1f vs %.1f)" % [stretched, slack])
	await _clear_enemies(main)


func _measure_chain_hit(main: Node, tension: float) -> float:
	var victim := _spawn(main, Vector2.ZERO)
	victim.health = 100000.0
	victim.max_health = 100000.0
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.chain_tension = tension
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var dealt := victim.max_health - victim.health
	victim.dead = true
	main.enemies.erase(victim)
	victim.queue_free()
	return dealt


## 분광 rolls separate targets instead of cloning one parallel line. Measured
## by headings and actual victims so a cosmetic spread cannot satisfy it.
func _test_lance_splits_into_beams(main: Node) -> void:
	await _clear_enemies(main)
	main.players[0].area = 1.0
	var lance: Dictionary = main._build_weapon_state(CharacterCatalog.all_characters()[7])
	_check(String(lance["weapon_id"]) == "lance", "the fixture picked the lance survivor")
	main.weapon_loadouts[0] = [lance]
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 200.0)

	var targets: Array[ChaserEnemy] = []
	for position in [Vector2(300, 0), Vector2(0, 300), Vector2(-300, 0), Vector2(0, -300)]:
		targets.append(_spawn(main, position))
	main.spatial_grid.rebuild(main.enemies)
	seed(1197)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var single_hits := targets.filter(func(enemy: ChaserEnemy) -> bool: return enemy.health < enemy.max_health).size()
	_check(single_hits == 1, "one lance selects and pierces one random bearing (%d bearings hit)" % single_hits)

	for enemy in targets:
		enemy.health = enemy.max_health
	main._apply_upgrade(0, {"id": "special_b", "weapon_slot": 0})
	_check(int(main.weapon_loadouts[0][0]["beams"]) == 2, "분광 adds a beam")
	main.spatial_grid.rebuild(main.enemies)
	seed(1197)
	var headings: Array[Vector2] = main.weapon_controller._lance_headings(0, float(lance["range"]), 2)
	_check(headings.size() == 2 and absf(headings[0].angle_to(headings[1])) > 0.1,
		"multiple lances choose visibly different random directions")
	seed(1197)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var multi_hits := targets.filter(func(enemy: ChaserEnemy) -> bool: return enemy.health < enemy.max_health).size()
	_check(multi_hits >= 2, "two lances reach at least two target bearings (%d)" % multi_hits)
	await _clear_enemies(main)


## The tether survivor's second special is the one upgrade that changes the run
## rather than the weapon, and it is worth its own check because it writes to a
## different place than every other special does.
func _test_leash_upgrade_lengthens_the_chain(main: Node) -> void:
	main.weapon_loadouts[0] = [main._build_weapon_state(CharacterCatalog.all_characters()[5])]
	var before: float = main.chain_max_length
	main._apply_upgrade(0, {"id": "special_b", "weapon_slot": 0})
	_check(main.chain_max_length > before,
		"느슨한 족쇄 lengthens the pair's leash (%.0f → %.0f)" % [before, main.chain_max_length])
	_check(not main.weapon_loadouts[0][0].has("chain_length"),
		"and does not smuggle a stray field onto the weapon")


## 궤도 파편 checked the whole ring five times a second and let one enemy be hit
## only once per check, so every shard past the first was decoration: a boss
## standing in the ring took the same damage from five shards as from one, and
## 파편 증식 — the weapon's own signature upgrade — did nothing at all to a
## single target.
##
## Measured against a stationary dummy parked on the ring, because that is the
## exact case the old model got wrong.
func _test_orbit_hits_once_per_shard(main: Node) -> void:
	await _clear_enemies(main)
	var orbit: Dictionary = main._build_weapon_state(CharacterCatalog.all_characters()[6])
	_check(String(orbit["weapon_id"]) == "orbit", "the fixture picked the orbit survivor")
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 260.0)

	var three := await _measure_orbit(main, orbit, 3)
	var six := await _measure_orbit(main, orbit, 6)
	print("ORBIT_METRICS: 3 shards hit %d times, 6 shards hit %d times" % [three, six])
	_check(three >= 2, "a single enemy is hit more than once per revolution (%d)" % three)
	_check(six > three,
		"doubling the shards lands more hits on that one enemy (%d vs %d)" % [six, three])
	# A shard that stays on top of something must not machine-gun it. The bound
	# is the rule itself — one hit per shard per re-hit window, for as long as
	# the field lives — so a per-frame regression (about 230 hits here) fails
	# even though the honest number sits far below the cap.
	var ceiling := int(ceil(last_orbit_duration / WeaponField.ORBIT_REHIT)) * 6
	_check(six <= ceiling, "and the ring still cannot machine-gun it (%d, ceiling %d)" % [six, ceiling])
	await _clear_enemies(main)


## Runs one orbit field to completion against a dummy on the ring and reports
## how many separate hits it took.
var last_orbit_duration := 0.0


func _measure_orbit(main: Node, base: Dictionary, shards: int) -> int:
	var state := base.duplicate(true)
	state["count"] = shards
	main.weapon_loadouts[0] = [state]
	var victim := _spawn(main, Vector2(float(state["radius"]), 0.0))
	victim.health = 1000000.0
	victim.max_health = 1000000.0
	main.spatial_grid.rebuild(main.enemies)

	var hits := 0
	var previous := victim.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var field: WeaponField = null
	for child in main.weapon_controller.get_children():
		var candidate := child as WeaponField
		if candidate != null:
			field = candidate
	_check(field != null, "the cast actually created an orbit field")
	if field == null:
		return 0
	last_orbit_duration = field.duration
	for step in 300:
		if not is_instance_valid(field):
			break
		field._physics_process(1.0 / 60.0)
		if victim.health < previous:
			hits += 1
			previous = victim.health
	if is_instance_valid(field):
		field.queue_free()
	victim.dead = true
	main.enemies.erase(victim)
	victim.queue_free()
	await process_frame
	return hits


func _spawn(main: Node, at: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 4000.0
	enemy.max_health = 4000.0
	enemy.position = at
	main.add_child(enemy)
	main.enemies.append(enemy)
	return enemy


func _clear_enemies(main: Node) -> void:
	for candidate in main.enemies.duplicate():
		var enemy := candidate as ChaserEnemy
		if is_instance_valid(enemy):
			enemy.dead = true
			enemy.queue_free()
	main.enemies.clear()
	main.spatial_grid.rebuild(main.enemies)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
