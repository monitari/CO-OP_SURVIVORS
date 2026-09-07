extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "ATTRIBUTE_FAIL", 90.0)
	call_deferred("_run")


## Attributes apply across a player's whole loadout instead of to one weapon.
## The failure mode worth guarding is a stat that exists as a field and shows
## up on a card but never actually reaches the thing it claims to change, so
## every check here measures an observable effect rather than a field value.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "ATTRIBUTE_FAIL"):
		return

	main.selected_character_indices[0] = 0 # lyra, homing projectiles
	main.selected_character_indices[1] = 3 # neve, frost ring
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_might(main)
	await _test_area(main)
	await _test_amount(main)
	await _test_projectile_speed_and_duration(main)
	_test_haste(main)
	_test_armor_and_recovery(main)
	_test_shared_attributes(main)
	_test_lifesteal(main)
	_test_card_rules(main)

	if failures.is_empty():
		print("ATTRIBUTE_PASS: combat stats apply, lifesteal uses actual damage and a shared cap, weapon card guaranteed")
		quit(0)
	else:
		for failure in failures:
			push_error("ATTRIBUTE_FAIL: " + failure)
		quit(1)


func _spawn_dummy(main: Node, position: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.position = position
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	return enemy


func _clear_enemies(main: Node) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	await process_frame


func _test_might(main: Node) -> void:
	await _clear_enemies(main)
	main.players[0].might = 1.0
	# This test isolates might. A critical baseline followed by a normal boosted
	# hit produces the same number and makes a deterministic multiplier look
	# broken.
	main.players[0].crit_chance = 0.0
	var enemy := _spawn_dummy(main, main.players[0].position + Vector2(105.0, 0.0))
	var before := enemy.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.4).timeout
	var base_damage := before - enemy.health
	_check(base_damage > 0.0, "the baseline attack lands at all")

	await _clear_enemies(main)
	main.players[0].might = 2.0
	var boosted := _spawn_dummy(main, main.players[0].position + Vector2(105.0, 0.0))
	var boosted_before := boosted.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.4).timeout
	var boosted_damage := boosted_before - boosted.health
	_check(boosted_damage > base_damage * 1.5, "might multiplies weapon damage (%.1f -> %.1f)" % [base_damage, boosted_damage])
	print("ATTRIBUTE_METRICS: might x1=%.1f x2=%.1f" % [base_damage, boosted_damage])
	main.players[0].might = 1.0


func _test_area(main: Node) -> void:
	# The frost ring has a fixed base radius, so parking an enemy just outside
	# it means only a widened area attribute can possibly reach.
	await _clear_enemies(main)
	var base_radius: float = float(main.weapon_loadouts[1][0]["radius"])
	var enemy := _spawn_dummy(main, main.players[1].position + Vector2(base_radius + 60.0, 0.0))
	var before := enemy.health

	main.players[1].area = 1.0
	main.weapon_controller.perform_attack(1, 0, 1.0)
	await create_timer(0.36).timeout
	_check(is_equal_approx(enemy.health, before), "an enemy outside the base ring takes nothing at normal area")

	main.players[1].area = 1.8
	main.weapon_controller.perform_attack(1, 0, 1.0)
	await create_timer(0.36).timeout
	_check(enemy.health < before, "a widened area attribute reaches an enemy the base radius could not")
	main.players[1].area = 1.0
	await _clear_enemies(main)


func _test_amount(main: Node) -> void:
	await _clear_enemies(main)
	_spawn_dummy(main, main.players[0].position + Vector2(105.0, 0.0))

	main.players[0].amount = 0
	main.weapon_controller.clear_transients()
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var base_shots: int = main.weapon_controller.active_projectiles.size()

	main.weapon_controller.clear_transients()
	main.players[0].amount = 3
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var boosted_shots: int = main.weapon_controller.active_projectiles.size()

	_check(boosted_shots == base_shots + 3, "amount adds projectiles to a volley (%d -> %d)" % [base_shots, boosted_shots])
	main.players[0].amount = 0
	main.weapon_controller.clear_transients()
	await _clear_enemies(main)


func _test_projectile_speed_and_duration(main: Node) -> void:
	await _clear_enemies(main)
	_spawn_dummy(main, main.players[0].position + Vector2(500.0, 0.0))
	main.players[0].projectile_speed = 1.0
	main.players[0].duration = 1.0
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var normal = main.weapon_controller.active_projectiles[0]
	var base_speed: float = normal.speed
	var base_lifetime: float = normal.lifetime
	main.weapon_controller.clear_transients()
	main.players[0].projectile_speed = 1.5
	main.players[0].duration = 1.8
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var extended = main.weapon_controller.active_projectiles[0]
	_check(extended.speed > base_speed * 1.4, "projectile speed reaches the launched projectile")
	_check(extended.lifetime > base_lifetime * 1.7, "duration extends projectile lifetime")
	main.players[0].projectile_speed = 1.0
	main.players[0].duration = 1.0
	await _clear_enemies(main)


func _test_haste(main: Node) -> void:
	main.players[0].haste = 1.0
	var base_interval: float = main._weapon_interval(0, 0)
	main.players[0].haste = 0.5
	var hasted_interval: float = main._weapon_interval(0, 0)
	_check(hasted_interval < base_interval, "haste shortens the firing interval (%.2f -> %.2f)" % [base_interval, hasted_interval])

	main.players[0].haste = 0.0001
	_check(main._weapon_interval(0, 0) >= 0.12, "the interval floor prevents a zero cooldown firing every frame")
	main.players[0].haste = 1.0


func _test_armor_and_recovery(main: Node) -> void:
	var player := main.players[0] as ChainPlayer
	player.downed = false
	player.max_health = 200.0
	player.health = 100.0
	player.armor = 0.0
	player.invulnerability = 0.0
	# Earlier sub-tests hand out 행운의 앞발 and 아홉 목숨. Either will eat the
	# baseline hit at random and make an unarmoured survivor look armoured —
	# which is how this measured 0 damage before armour and 12 after it.
	player.dodge_chance = 0.0
	player.second_chances = 0
	player.hurt(20.0)
	var unarmored_loss := 100.0 - player.health

	player.health = 100.0
	player.armor = 8.0
	player.invulnerability = 0.0
	player.hurt(20.0)
	var armored_loss := 100.0 - player.health
	_check(armored_loss < unarmored_loss, "armor reduces incoming damage (%.0f -> %.0f)" % [unarmored_loss, armored_loss])

	player.health = 100.0
	player.armor = 500.0
	player.invulnerability = 0.0
	player.hurt(20.0)
	_check(player.health < 100.0, "armor never fully negates a hit — a chip minimum still lands")

	player.armor = 0.0
	player.health = 100.0
	player.recovery = 0.0
	player.step_recovery(1.0)
	_check(is_equal_approx(player.health, 100.0), "no recovery attribute means no regeneration")
	player.recovery = 5.0
	player.step_recovery(1.0)
	_check(player.health > 100.0, "recovery regenerates health over time")
	player.recovery = 0.0


func _test_shared_attributes(main: Node) -> void:
	main.team_growth = 1.0
	var before: int = main.progression.experience
	main._gain_shared_xp(100)
	var normal_gain: int = main.progression.experience - before

	main.team_growth = 2.0
	before = main.progression.experience
	main._gain_shared_xp(100)
	var grown_gain: int = main.progression.experience - before
	_check(grown_gain > normal_gain, "growth multiplies shared experience (%d -> %d)" % [normal_gain, grown_gain])
	main.team_growth = 1.0

	main.team_magnet = 1.0
	main._apply_team_magnet()
	var base_magnet: float = main.experience_system.magnet_radius
	main.team_magnet = 2.0
	main._apply_team_magnet()
	_check(main.experience_system.magnet_radius > base_magnet, "magnet widens the shared pickup radius (%.0f -> %.0f)" % [base_magnet, main.experience_system.magnet_radius])
	main.team_magnet = 1.0
	main._apply_team_magnet()

	# Level-ups opened by the XP above would leave the screen up for later checks.
	main.level_up_active = false
	main.resonance_vote_active = false
	main.level_overlay.visible = false
	main.resonance_overlay.visible = false
	paused = false


func _test_lifesteal(main: Node) -> void:
	_check(TreasureCatalog.by_id("curse").is_empty(), "the old curse treasure is gone")
	_check(not TreasureCatalog.by_id("lifesteal").is_empty(), "a lifesteal treasure replaces it")
	main.lifesteal_charge = 0.0
	for slot in 2:
		main.treasure_loadouts[slot] = []
	# Put the bell in a loadout before applying it. Shared treasures are worked
	# out from what the pair is actually carrying now, because what one copy is
	# worth depends on whether the other survivor holds one too — so applying the
	# effect without the treasure existing anywhere is asking for nothing.
	main.treasure_loadouts[0].append(TreasureCatalog.build_state(TreasureCatalog.by_id("lifesteal")))
	main._apply_attribute(0, "lifesteal")
	_check(is_equal_approx(main.team_lifesteal, main.LIFESTEAL_PER_TIER),
		"one tier grants the advertised shared lifesteal rate")
	for player in main.players:
		player.health = player.max_health * 0.5
	var enemy: ChaserEnemy = main.wave_director._acquire_enemy("bulwark", 0.0, Vector2.ZERO, false, false)
	enemy.health = 1000.0
	enemy.max_health = 1000.0
	main._register_enemy(enemy)
	var before: float = main.players[0].health + main.players[1].health
	enemy.take_damage(100.0)
	var healed: float = main.players[0].health + main.players[1].health - before
	_check(absf(healed - 100.0 * main.LIFESTEAL_PER_TIER) < 0.01,
		"actual attack damage returns health to the team (%.2f)" % healed)
	main._cull_enemy(enemy)

	var tiny: ChaserEnemy = main.wave_director._acquire_enemy("swarm", 0.0, Vector2.ZERO, false, false)
	tiny.health = 10.0
	tiny.max_health = 10.0
	main._register_enemy(tiny)
	before = main.players[0].health + main.players[1].health
	tiny.take_damage(999999.0)
	healed = main.players[0].health + main.players[1].health - before
	_check(healed <= 10.0 * main.LIFESTEAL_PER_TIER + 0.001,
		"overkill cannot be converted into fake lifesteal (%.3f)" % healed)


func _test_card_rules(main: Node) -> void:
	# Attribute cards dilute the pool, and weapon tier is the only route to
	# resonance, so every draw must still contain a weapon upgrade.
	var draws_without_weapon := 0
	for draw in 30:
		var choices: Array = main._get_upgrade_choices(1)
		var has_weapon := false
		for option in choices:
			if int(option.get("weapon_slot", -1)) >= 0:
				has_weapon = true
		if not has_weapon:
			draws_without_weapon += 1
	_check(draws_without_weapon == 0, "every level-up still offers at least one weapon upgrade (%d draws missed)" % draws_without_weapon)

	# Measured against a filled-out build on purpose. With one weapon and no
	# treasures nearly every option in the pool is already build-defining, so
	# luck has nothing to shift and the comparison reads as noise.
	for character in main._pick_unowned_characters(0, 2):
		main._apply_upgrade(0, {"id": "unlock_weapon", "weapon_slot": -1, "character": character})
	for treasure in main._pick_unowned_treasures(0, 3):
		main._apply_upgrade(0, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	main.team_luck = 0
	var unlucky := _count_interesting(main, 40)
	main.team_luck = 4
	var lucky := _count_interesting(main, 40)
	_check(lucky > unlucky, "luck raises how often build-defining cards show up (%d -> %d over 40 draws)" % [unlucky, lucky])
	print("ATTRIBUTE_METRICS: interesting cards luck0=%d luck4=%d" % [unlucky, lucky])
	main.team_luck = 0


func _count_interesting(main: Node, draws: int) -> int:
	var total := 0
	for draw in draws:
		for option in main._get_upgrade_choices(1):
			var option_id := String(option["id"])
			# Must match the set main.gd actually weights, or the measurement
			# counts three of the four categories luck moves and reads as noise.
			if option_id in ["unlock_weapon", "unlock_treasure", "special_a", "special_b"]:
				total += 1
	return total


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
