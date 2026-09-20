extends SceneTree

const Harness := preload("res://tests/test_harness.gd")
const Enemy := preload("res://scripts/entities/enemy.gd")
const Experience := preload("res://scripts/systems/experience_system.gd")
var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "XP_GRADE_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	var values: Array[int] = []
	var grades: Array[int] = []
	for kind in ["swarm", "charger", "bulwark"]:
		var enemy := Enemy.new() as ChaserEnemy
		enemy.setup(0.0, kind)
		values.append(enemy.xp_value)
		grades.append(enemy.xp_grade)
		enemy.free()
	var boss := Enemy.new() as ChaserEnemy
	boss.setup(0.0, "brute", false, true)
	values.append(boss.xp_value)
	grades.append(boss.xp_grade)
	boss.free()
	check(values[0] < values[1] and values[1] < values[2] and values[2] < values[3], "harder enemies award progressively more XP")
	check(grades == [0, 1, 2, 3], "enemy tiers map to four distinct gem grades")

	var system := Experience.new() as ExperienceSystem
	root.add_child(system)
	# Spread out so this first check only measures value-to-grade inference.
	for index in 4:
		system.spawn_gem(Vector2(index * 150.0, 0.0), [3, 8, 26, 150][index])
	var spawned: Array[int] = []
	for gem in system.active_gems: spawned.append(gem.grade)
	check(spawned == [0, 1, 2, 3], "gem grade is inferred safely when a caller omits it")
	var cluster_start := system.active_gems.size()
	for index in 4:
		system.spawn_gem(Vector2(800.0, 100.0), 3)
	var cluster_positions: Dictionary = {}
	for index in range(cluster_start, system.active_gems.size()):
		cluster_positions[str((system.active_gems[index] as ExperienceGem).position.round())] = true
	check(system.active_gems.size() == cluster_start + 4,
		"overlapping kills each create a visible experience gem")
	check(cluster_positions.size() == 4,
		"overlapping experience drops fan out instead of hiding on one pixel")
	while system.active_gems.size() < ExperienceSystem.MAX_ACTIVE:
		var index := system.active_gems.size()
		system.spawn_gem(Vector2(float(index % 20) * 80.0, 300.0 + float(index / 20) * 80.0), 1)
	# Once capped, later kills add value without allocating hidden nodes.
	var children_before := system.get_child_count()
	var value_before := 0
	for gem: ExperienceGem in system.active_gems:
		value_before += gem.value
	for index in 1000:
		system.spawn_gem(Vector2.ZERO, 3)
	var value_after := 0
	for gem: ExperienceGem in system.active_gems:
		value_after += gem.value
	check(system.get_child_count() == children_before, "1,000 capped drops allocate no hidden gem nodes")
	check(system.active_gems.size() == ExperienceSystem.MAX_ACTIVE,
		"the visible experience field stays at its hard cap")
	check(value_after == value_before + 3000, "capped drops preserve every point of experience")
	if failures.is_empty(): print("XP_GRADE_PASS: four readable drops and stronger-enemy rewards")
	else:
		for failure in failures: push_error("XP_GRADE_FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
