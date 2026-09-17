extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const Editorial := preload("res://scripts/ui/editorial_ui.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)

	_check(EvolutionCatalog.all_hybrid_evolutions().is_empty(), "weapon + weapon recipes are retired")
	_check(EvolutionCatalog.all_fusions().size() == EvolutionCatalog.all_evolutions().size(),
		"the enhancement catalogue holds exactly one entry per base weapon")

	var base: Dictionary = main.weapon_loadouts[0][0]
	var base_id := String(base["weapon_id"])
	main.WeaponTechs.apply_to_state(base, main.WeaponTechs.for_weapon(base_id)[0])
	base["tier"] = EvolutionCatalog.EVOLUTION_TIER
	var ready: Dictionary = main._available_evolution(0, 0)
	_check(not ready.is_empty(), "reaching Lv.%d alone unlocks the enhancement" % EvolutionCatalog.EVOLUTION_TIER)
	main.run_stats["weapon_damage"][0][base_id] = 420.0
	var weapons_before: int = main.weapon_loadouts[0].size()
	var treasures_before: int = main.treasure_loadouts[0].size()
	main._apply_pending_evolutions(0)
	var enhanced: Dictionary = main.weapon_loadouts[0][0]
	_check(main.weapon_loadouts[0].size() == weapons_before, "enhancement keeps the weapon slot")
	_check(main.treasure_loadouts[0].size() == treasures_before, "enhancement keeps the treasure")
	_check(bool(enhanced.get("evolved", false)), "the resulting weapon is marked enhanced")
	_check(float(main.run_stats["weapon_damage"][0].get(String(enhanced["weapon_id"]), 0.0)) == 420.0,
		"damage history follows a weapon through enhancement")

	var first_requirement := SharedProgression.requirement_for_level(1)
	main._gain_shared_xp(first_requirement, 0)
	_check(int(main.run_stats["personal_levels"][0]) == 2 and int(main.run_stats["personal_levels"][1]) == 1,
		"shared XP also records a collector-side rivalry level")

	var directional := EnemyScript.new() as ChaserEnemy
	directional.setup(0.0, "bulwark")
	directional.rotation = PI
	directional._update_body_facing()
	_check(directional.faces_along_heading and directional.body_sprite.flip_h,
		"non-chaser enemy art mirrors when it changes direction")
	var remade := EnemyScript.new() as ChaserEnemy
	remade.setup(0.0, "chaser")
	remade.rotation = PI
	remade._update_body_facing()
	_check(remade.faces_along_heading and remade.body_sprite.flip_h,
		"the remade chaser follows the same left-facing mirror rule")
	directional.queue_free()
	remade.queue_free()

	for sample in 200:
		_check(main._roll_chest_reward_count() >= 2, "every chest contains at least two rewards")

	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.max_health = 100.0
	enemy.health = 100.0
	main.add_child(enemy)
	main._register_enemy(enemy)
	enemy.take_damage(25.0, 0, String(enhanced["weapon_id"]))
	_check(main._weapon_dps(0, String(enhanced["weapon_id"])) > 0.0,
		"actual removed health is recorded for per-weapon DPS")

	main.elapsed = 10.0
	Editorial.refresh_result(main, false)
	_check(main.result_overlay.get_node("ResultPlayerStats0").text.contains("개인 LV.2"),
		"result screen exposes the personal level comparison")
	_check(main.result_overlay.get_node("ResultWeaponDps0_0").text.contains("DPS"),
		"result screen exposes weapon DPS")

	if failures.is_empty():
		print("GAMEPLAY_REWORK_PASS: treasure enhancement, resonance gate, enemy facing, chest floor, rivalry levels, result DPS")
		quit(0)
	else:
		for failure in failures:
			push_error("GAMEPLAY_REWORK_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
