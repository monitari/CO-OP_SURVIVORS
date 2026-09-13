extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, "PAUSE_FREEZE_FAIL", 30.0)
	call_deferred("_run")

func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	var enemy = main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false)
	enemy.position = main.players[0].position
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	# Actual delayed supernova damage plus persistent frost and projectile motion.
	main.weapon_controller._fire_supernova(0, {"radius": 180.0, "count": 3, "speed": 200.0}, 10.0, Color.WHITE)
	main._perform_character_attack(1)
	main._set_pause(true)
	await process_frame
	var health: float = enemy.health
	var world := main.rooftop_view.world as Node
	_check(not world.can_process(), "battlefield is paused")
	var children: Array[Node] = main.weapon_controller.get_children()
	var ages: Dictionary = {}
	for child in children:
		if child is WeaponField:
			ages[child] = child.age
	await create_timer(0.7, true).timeout
	_check(enemy.health == health, "no persistent or delayed damage while paused")
	for child in ages:
		_check(is_instance_valid(child) and child.age == ages[child], "weapon animation clock frozen")
	main._set_pause(false)
	await create_timer(0.65, true).timeout
	_check(enemy.health < health, "pending damage resumes after unpause")
	main._gain_shared_xp(main.progression.required_experience)
	await process_frame
	_check(paused and not world.can_process(), "level selection freezes battlefield")
	health = enemy.health
	await create_timer(0.5, true).timeout
	_check(enemy.health == health, "selection cannot deal weapon damage")
	paused = false
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PAUSE_FREEZE_PASS: persistent fields, delayed blasts and selection freeze")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
