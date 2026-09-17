extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const EnemyProjectileScript := preload("res://scripts/entities/enemy_projectile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FEATURE_TEST_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "FEATURE_TEST_FAIL"):
		return
	await _test_selection_and_movement_input(main)
	main.set_physics_process(false)
	await process_frame

	_test_experience_pickup(main)
	_test_downed_revive(main)
	_test_downed_tow(main)
	_test_enemy_pool_and_archetypes(main)
	await _test_automatic_resonance(main)

	if failures.is_empty():
		print("FEATURE_TEST_PASS: XP gems, enemy pool/archetypes, revive/tow, boss-core resonance")
		quit(0)
	else:
		for failure in failures:
			push_error("FEATURE_TEST_FAIL: " + failure)
		quit(1)


func _test_selection_and_movement_input(main: Node) -> void:
	var first_index: int = main.selected_character_indices[0]
	Input.action_press("p1_select_next")
	main._handle_character_select_input()
	Input.action_release("p1_select_next")
	_check(main.selected_character_indices[0] != first_index, "P1 selection input changes character")
	await process_frame
	Input.action_press("p1_select_confirm")
	Input.action_press("p2_select_confirm")
	main._handle_character_select_input()
	Input.action_release("p1_select_confirm")
	Input.action_release("p2_select_confirm")
	_check(not main.character_select_active, "both mapped confirm inputs start the run")

	var p1_before: Vector2 = main.players[0].position
	var p2_before: Vector2 = main.players[1].position
	Input.action_press("p1_right")
	Input.action_press("p2_left")
	main.players[0].step_movement(0.25)
	main.players[1].step_movement(0.25)
	Input.action_release("p1_right")
	Input.action_release("p2_left")
	_check(main.players[0].position.x > p1_before.x and main.players[1].position.x < p2_before.x, "both local movement maps move independently")
	main.players[0].position = Vector2(-500.0, 0.0)
	main.players[1].position = Vector2(500.0, 0.0)
	main._apply_chain_constraint()
	_check(main.players[0].position.distance_to(main.players[1].position) <= main.chain_max_length + 0.01, "chain hard limit constrains both players")


func _test_experience_pickup(main: Node) -> void:
	var before: int = main.progression.experience
	main.experience_system.spawn_gem(main.players[0].global_position, 11)
	main.experience_system.step(main.players, 0.016)
	_check(main.progression.experience == before + 11, "nearby XP gem is shared immediately on pickup")
	_check(main.experience_system.gem_pool.size() == 1, "collected XP gem returns to pool")


func _test_downed_revive(main: Node) -> void:
	var player := main.players[0] as ChainPlayer
	player.health = 1.0
	player.invulnerability = 0.0
	player.hurt(50.0)
	_check(player.downed, "lethal damage downs instead of immediately ending the run")
	main.players[1].position = player.position + Vector2(50.0, 0.0)
	for index in 3:
		main._update_revives(1.0)
	_check(not player.downed, "nearby partner revives a downed player")
	_check(player.health > 0.0, "revived player returns with health")


## Drags one survivor away from the other for a second of frames and reports
## how far each of them actually travelled.
func _tow_run(main: Node, downed_slot: int) -> Dictionary:
	var downed := main.players[downed_slot] as ChainPlayer
	var rescuer := main.players[1 - downed_slot] as ChainPlayer
	var away := Vector2.RIGHT if downed_slot == 0 else Vector2.LEFT
	downed.position = Vector2.ZERO
	rescuer.position = away * main.chain_max_length
	downed.current_input = Vector2.ZERO
	rescuer.current_input = away
	var downed_start := downed.position
	var rescuer_start := rescuer.position
	var delta := 1.0 / 60.0
	for frame in 60:
		rescuer.position += away * rescuer.move_speed * delta
		main._apply_chain_constraint()
	return {
		"towed": downed.position.distance_to(downed_start),
		"advanced": rescuer.position.distance_to(rescuer_start),
		"distance": downed.position.distance_to(rescuer.position)
	}


func _test_downed_tow(main: Node) -> void:
	var downed := main.players[0] as ChainPlayer
	var partner := main.players[1] as ChainPlayer
	downed.downed = true
	partner.downed = false

	var run := _tow_run(main, 0)
	_check(float(run["towed"]) > 150.0, "a downed survivor is towed along the chain")
	_check(float(run["advanced"]) > 150.0, "towing does not anchor the standing partner")
	_check(float(run["distance"]) <= main.chain_max_length + 1.0, "towing still respects the chain limit")
	print("TOW_METRICS: p1_down towed=%.0f advanced=%.0f" % [run["towed"], run["advanced"]])

	downed.downed = false
	partner.downed = true
	var mirrored := _tow_run(main, 1)
	_check(float(mirrored["towed"]) > 150.0, "towing works symmetrically for either slot")
	print("TOW_METRICS: p2_down towed=%.0f advanced=%.0f" % [mirrored["towed"], mirrored["advanced"]])

	downed.downed = true
	partner.downed = true
	var both := _tow_run(main, 0)
	_check(float(both["towed"]) < 100.0, "with both survivors down the chain resists instead of towing")
	print("TOW_METRICS: both_down towed=%.0f advanced=%.0f" % [both["towed"], both["advanced"]])

	downed.downed = false
	partner.downed = false
	downed.revive()
	partner.revive()

func _test_enemy_pool_and_archetypes(main: Node) -> void:
	var center := Vector2.ZERO
	var enemy := main.wave_director._acquire_enemy("charger", 0.0, center, false, false) as ChaserEnemy
	main._register_enemy(enemy)
	var original_id := enemy.get_instance_id()
	_check(enemy.active and enemy.archetype == "charger", "charger archetype activates")
	enemy.take_damage(99999.0)
	_check(main.wave_director.enemy_pool.size() >= 1, "dead enemy returns to pool")
	# Every kill drops its own gem, and the gem's grade says what died and how
	# late. A charger at the opening is a shard; the same charger deep into a
	# run is a prism, and only elites and bosses ever reach the top grade.
	_check(main.experience_system.active_gems.size() == 1,
		"an ordinary kill drops its own gem (%d)" % main.experience_system.active_gems.size())
	var first := main.experience_system.active_gems[0] as ExperienceGem
	_check(first.value > 0, "and the gem carries the kill's experience (%d)" % first.value)
	
	var early := ChaserEnemy.new()
	early.setup(0.0, "charger")
	var late := ChaserEnemy.new()
	late.setup(20.0, "charger")
	var elite_late := ChaserEnemy.new()
	elite_late.setup(20.0, "charger", true)
	var swarm_late := ChaserEnemy.new()
	swarm_late.setup(20.0, "swarm")
	_check(late.xp_grade > early.xp_grade,
		"the same enemy drops a better gem later (%d then %d)" % [early.xp_grade, late.xp_grade])
	_check(swarm_late.xp_grade < late.xp_grade,
		"a flea still drops under a charger at the same depth (%d vs %d)" % [swarm_late.xp_grade, late.xp_grade])
	_check(late.xp_grade < 3 and elite_late.xp_grade == 3,
		"and the top grade stays an elite/boss silhouette (%d vs %d)" % [late.xp_grade, elite_late.xp_grade])
	_check(late.xp_value > early.xp_value,
		"a late kill is still worth more experience (%d then %d)" % [early.xp_value, late.xp_value])
	for spare in [early, late, elite_late, swarm_late]: spare.free()
	var reused := main.wave_director._acquire_enemy("shooter", 1.0, center, true, false) as ChaserEnemy
	_check(reused.get_instance_id() == original_id, "enemy instance is reused from pool")
	_check(reused.archetype == "shooter" and reused.elite, "pooled enemy resets as elite shooter")
	main._register_enemy(reused)
	reused.position = main.players[0].position + Vector2(300.0, 0.0)
	reused.attack_timer = 0.0
	reused.step(main.players, 0.016)
	_check(reused.shooter_windup > 0.0, "shooter telegraphs before firing")
	reused.step(main.players, 0.25)
	reused.step(main.players, 0.25)
	# Shots live under the rooftop world, not under main; enemy_shots is the list
	# the crowd renderer draws from and the knock-down weapons read.
	var ranged_projectiles := 0
	for shot in main.enemy_shots:
		if is_instance_valid(shot) and shot.get_script() == EnemyProjectileScript:
			ranged_projectiles += 1
	_check(ranged_projectiles > 0, "shooter emits a hostile projectile")
	main.spatial_grid.rebuild(main.enemies)
	_check(main.spatial_grid.nearest(reused.global_position, 50.0) == reused, "spatial grid returns nearby enemy")

	for archetype in ["chaser", "charger", "shooter", "chain_hunter", "brute"]:
		var sample := main.wave_director._acquire_enemy(archetype, 2.0, center, false, archetype == "brute") as ChaserEnemy
		_check(sample.active and sample.archetype == archetype, "%s archetype configures" % archetype)
		main.wave_director.release_enemy(sample)


## Tags make a resonance possible; a boss core makes it real. This used to
## activate the top-ranked candidate the moment the tags lined up, which meant
## the run's climactic mechanic arrived as a banner in the middle of a menu.
func _test_automatic_resonance(main: Node) -> void:
	main.selected_characters[0] = main.character_catalog[0].duplicate(true)
	main.selected_characters[1] = main.character_catalog[1].duplicate(true)
	main.weapon_loadouts[0] = [main._build_weapon_state(main.selected_characters[0])]
	main.weapon_loadouts[1] = [main._build_weapon_state(main.selected_characters[1])]
	# Fused on both sides: resonance is the top of the tech tree now and a
	# tier-3 base weapon no longer reaches it.
	for slot in 2:
		var base: Dictionary = main.weapon_loadouts[slot][0]
		main.weapon_loadouts[slot][0] = EvolutionCatalog.build_state(
			EvolutionCatalog.for_base(String(base["weapon_id"])), base
		)
	main.resonance_system.active_resonances.clear()
	main.resonance_system.pending_cores = 0
	main.announced_resonance_ids.clear()
	main.showcase_queue.clear()
	main.level_up_active = true
	paused = true
	main._after_personal_upgrade_choices()
	_check(main.resonance_system.active_resonances.is_empty(),
		"a matching pair does not switch a resonance on by levelling up")
	_check(not main.announced_resonance_ids.is_empty(),
		"but the pair is told the resonance is now possible")
	_check(not main.resonance_vote_active and not main.resonance_overlay.visible,
		"and no screen is opened for it")

	# The boss core is what turns one on.
	var reachable: Array = main.resonance_system.get_candidates_for_loadouts(
		main.weapon_loadouts[0], main.weapon_loadouts[1])
	_check(not reachable.is_empty(), "resonance candidates are generated")
	main._award_resonance_core()
	if main.resonance_vote_active:
		# More than one candidate, so the pair is asked; agree on the first.
		_check(main.resonance_overlay.visible, "a contested core opens the selection screen")
		main._commit_resonance_choice(main.resonance_candidates[0])
	_check(main.resonance_system.active_resonances.size() == 1, "spending the core activates exactly one resonance")
	_check(main.resonance_system.pending_cores == 0, "and consumes the core")
	_check(main.cinematic_active, "an activated resonance opens its showcase")
	for frame in 400:
		if not main.cinematic_active:
			break
		await process_frame
	_check(not main.cinematic_active, "the showcase ends on its own")
	_check(not main.resonance_vote_active and not paused, "activating a resonance returns to combat")
	for resonance in main.resonance_system.catalog:
		main.weapon_controller.perform_resonance(resonance, 1.0)
	main.weapon_controller.clear_transients()


## is_action_just_pressed stays true for the rest of the frame, so consecutive
## taps without a frame between them all read as the same press.
func _tap(main: Node, action: String) -> void:
	Input.action_press(action)
	main._handle_resonance_vote_input()
	Input.action_release(action)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
