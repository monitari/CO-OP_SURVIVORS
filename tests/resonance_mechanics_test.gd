extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []
var main: Node


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RESONANCE_MECHANICS_FAIL", 120.0)
	call_deferred("_run")


## resonance_effects_test proves every resonance hurts something. This proves
## each one does the thing its card says: a field that keeps striking keeps
## striking, a guided strike picks the body worth hitting, a volley bursts where
## it lands, a well pulls, frost holds, and a restart cancels what was pending.
func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "RESONANCE_MECHANICS_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_sustained("storm_field", Vector2(0, 120))
	await _test_sustained("arcane_circuit", Vector2.ZERO)
	await _test_sustained("frozen_tether", Vector2.ZERO)
	await _test_sustained("storm_core", Vector2(0, 200))
	await _test_sustained("inferno_crescent", Vector2(140, 0))
	await _test_guided_targets("guided_thunder")
	await _test_guided_targets("twilight_pursuit")
	await _test_impact_lightning()
	await _test_bombardment_bursts()
	await _test_thermal_shock()
	await _test_singularity_pulls()
	await _test_comet_shower_slows()
	await _test_storm_core_quadrants()
	await _test_restart_cancels_ticks()

	if failures.is_empty():
		print("RESONANCE_MECHANICS_PASS: sustained fields, guided marks, impacts, pulls, frost and cancellation")
		quit(0)
	else:
		for failure in failures:
			push_error("RESONANCE_MECHANICS_FAIL: " + failure)
		quit(1)


func _resonance(id: String) -> Dictionary:
	for entry in main.resonance_system.catalog:
		if String(entry["id"]) == id:
			return entry
	return {}


func _spawn(at: Vector2, elite := false, radius := 24.0) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "brute")
	enemy.radius = radius
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.elite = elite
	enemy.position = at
	main.add_child(enemy)
	main._register_enemy(enemy)
	return enemy


func _reset(p0 := Vector2(-60, 0), p1 := Vector2(60, 0)) -> void:
	main.weapon_controller.clear_transients()
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	main.enemies.clear()
	await process_frame
	main.players[0].position = p0
	main.players[1].position = p1
	main.players[0].last_input = Vector2.RIGHT
	main.players[1].last_input = Vector2.LEFT


func _fire(id: String) -> void:
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_resonance(_resonance(id), 1.0)


func _lost(enemy: ChaserEnemy) -> float:
	return enemy.max_health - enemy.health


func _test_sustained(id: String, at: Vector2) -> void:
	await _reset()
	var enemy := _spawn(at, false, 40.0)
	_fire(id)
	await create_timer(0.9).timeout
	var early := _lost(enemy)
	await create_timer(1.1).timeout
	_check(early > 0.0, "%s lands its first strike" % id)
	_check(_lost(enemy) > early, "%s keeps working after its first second (%.0f → %.0f)" % [id, early, _lost(enemy)])


func _test_guided_targets(id: String) -> void:
	await _reset()
	# A weak body right between the survivors and an elite much further out: a
	# nearest-first strike would never reach the elite.
	var near := _spawn(Vector2(0, 40))
	near.health = 50.0
	near.max_health = 50.0
	var elite := _spawn(Vector2(0, 560), true)
	_fire(id)
	await create_timer(0.6).timeout
	_check(_lost(elite) > 0.0, "%s marks the elite before the nearer weak body" % id)


func _test_impact_lightning() -> void:
	await _reset()
	# Only the first body is in seeker range; the second is reachable only by the
	# lightning that falls where the star lands.
	var first := _spawn(Vector2(600, 0))
	var second := _spawn(Vector2(780, 0))
	_fire("starbound_trajectory")
	await create_timer(1.6).timeout
	_check(_lost(first) > 0.0, "성혼 궤적's stars reach their mark")
	_check(_lost(second) > 0.0, "성혼 궤적's landing lightning jumps on from the impact")


func _test_bombardment_bursts() -> void:
	await _reset()
	var target := _spawn(Vector2(0, 360))
	var behind := _spawn(Vector2(0, 420))
	_fire("guided_bombardment")
	await create_timer(1.4).timeout
	_check(_lost(target) > 0.0, "유도 폭격 lands on the crowd")
	_check(_lost(behind) > 0.0, "유도 폭격 bursts where it lands and catches the body behind")


func _test_thermal_shock() -> void:
	await _reset()
	var enemy := _spawn(Vector2(0, 150))
	_fire("thermal_fracture")
	await create_timer(0.1).timeout
	var frost := _lost(enemy)
	_check(enemy.slow_timer > 0.0, "열충격 붕괴 freezes before it bursts")
	await create_timer(0.6).timeout
	# Without the shock bonus the burst would be 36/14 of the frost hit.
	_check(_lost(enemy) - frost > frost * 3.0, "the burst hits a frozen body with the shock bonus (%.0f after %.0f)" % [_lost(enemy) - frost, frost])


func _test_singularity_pulls() -> void:
	await _reset()
	var enemy := _spawn(Vector2(320, 0))
	var before := enemy.global_position.length()
	_fire("singularity")
	await create_timer(0.7).timeout
	_check(enemy.global_position.length() < before - 100.0, "특이점 drags bodies toward the centre (%.0f → %.0f)" % [before, enemy.global_position.length()])
	_check(_lost(enemy) > 0.0, "and crushes them")


func _test_comet_shower_slows() -> void:
	await _reset()
	var enemy := _spawn(Vector2(0, 160), false, 60.0)
	_fire("comet_shower")
	await create_timer(0.6).timeout
	_check(_lost(enemy) > 0.0 and enemy.slow_timer > 0.0, "혜성우's ice shards slow what they hit")


func _test_storm_core_quadrants() -> void:
	await _reset(Vector2(-20, 0), Vector2(20, 0))
	var bodies: Array[ChaserEnemy] = []
	for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		bodies.append(_spawn(Vector2.from_angle(angle) * 400.0))
	_fire("storm_core")
	await process_frame
	var reached := 0
	for body in bodies:
		if _lost(body) > 0.0:
			reached += 1
	_check(reached == 4, "폭풍의 핵 chains out into all four quarters at once (%d/4)" % reached)


func _test_restart_cancels_ticks() -> void:
	await _reset()
	var enemy := _spawn(Vector2(0, 120), false, 40.0)
	_fire("storm_field")
	await create_timer(0.1).timeout
	main.weapon_controller.clear_transients()
	await process_frame
	var frozen := enemy.health
	await create_timer(0.8).timeout
	_check(is_equal_approx(enemy.health, frozen), "clearing transients cancels a resonance's remaining ticks")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
