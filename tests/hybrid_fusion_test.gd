extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const SAVE := "res://tests/tmp/hybrid_fusion_test.cfg"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.meta_progression.save_path = SAVE
	main.meta_progression.discoveries.clear()
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)

	var volta: Dictionary = main.character_catalog[1]
	main._apply_upgrade(0, {"id": "unlock_weapon", "weapon_slot": -1, "character": volta})
	for weapon in main.weapon_loadouts[0]:
		weapon["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
	var ready: Array[Dictionary] = main._available_hybrid_evolutions(0)
	var comet := {}
	for entry in ready:
		if String(entry["evolution"]["weapon_id"]) == "comet_storm": comet = entry
	_check(not comet.is_empty(), "two matching maxed weapons unlock their hybrid")

	var option := {"id": "evolve_weapon", "weapon_slot": int(comet["weapon_slot"]),
		"consume_weapon_slot": int(comet["consume_weapon_slot"]), "evolution": comet["evolution"]}
	_check(main._upgrade_preview(0, option).contains("완성 후 공개"), "an undiscovered result stays hidden")
	var before: int = main.weapon_loadouts[0].size()
	main._apply_upgrade(0, option)
	_check(main.weapon_loadouts[0].size() == before - 1, "weapon+weapon fusion consumes two slots into one")
	_check(String(main.weapon_loadouts[0][0]["weapon_id"]) == "comet_storm", "the hybrid replaces the recipe in place")
	_check(main.meta_progression.is_discovered("comet_storm"), "completion reveals and records the result")
	_check(GameIconCatalog.has_atlas_art("comet_storm", "weapon"), "the completed hybrid has dedicated art")
	await _test_all_hybrids_deal_damage(main)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if failures.is_empty():
		print("HYBRID_FUSION_PASS: six hybrids attack, two maxed weapons combine, stay secret, then reveal art")
		quit(0)
	else:
		for failure in failures:
			push_error("HYBRID_FUSION_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _test_all_hybrids_deal_damage(main: Node) -> void:
	main.players[0].position = Vector2(-90.0, 0.0)
	main.players[1].position = Vector2(90.0, 0.0)
	main.players[0].last_input = Vector2.RIGHT
	main.players[0].crit_chance = 0.0
	var base_state: Dictionary = main._build_weapon_state(main.character_catalog[0])
	for evolution in EvolutionCatalog.all_hybrid_evolutions():
		main.weapon_controller.clear_transients()
		for old_enemy in main.enemies:
			if is_instance_valid(old_enemy):
				old_enemy.queue_free()
		main.enemies.clear()
		await process_frame
		var enemy := EnemyScript.new() as ChaserEnemy
		enemy.setup(0.0, "chaser")
		enemy.max_health = 10000.0
		enemy.health = enemy.max_health
		enemy.position = Vector2(-20.0, 0.0)
		main.add_child(enemy)
		main._register_enemy(enemy)
		main.spatial_grid.rebuild(main.enemies)
		main.weapon_loadouts[0] = [EvolutionCatalog.build_state(evolution, base_state)]
		main.attack_timers[0] = [0.0]
		var before := enemy.health
		main.weapon_controller.perform_attack(0, 0, 1.0)
		await create_timer(0.9).timeout
		_check(enemy.health < before, "%s delivers real damage" % String(evolution["weapon_id"]))
