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
	# Spread out on purpose: drops landing within MERGE_RADIUS of each other now
	# join into one gem, which is what keeps a per-kill drop from burying the
	# roof. This check is about the value-to-grade inference, so it gives each
	# gem its own patch of floor.
	for index in 4:
		system.spawn_gem(Vector2(index * ExperienceSystem.MERGE_RADIUS * 3.0, 0.0), [3, 8, 26, 150][index])
	var spawned: Array[int] = []
	for gem in system.active_gems: spawned.append(gem.grade)
	check(spawned == [0, 1, 2, 3], "gem grade is inferred safely when a caller omits it")
	# All of these land on the first gem. Merged drops must not allocate hidden
	# child nodes; that leak used to grow with lifetime kill count despite the
	# visible gem cap and became expensive in late waves.
	var children_before := system.get_child_count()
	for index in 1000:
		system.spawn_gem(Vector2.ZERO, 3)
	check(system.get_child_count() == children_before, "1,000 merged drops allocate no hidden gem nodes")
	check(system.active_gems.size() == 4, "merged drops preserve the active gem count")
	if failures.is_empty(): print("XP_GRADE_PASS: four readable drops and stronger-enemy rewards")
	else:
		for failure in failures: push_error("XP_GRADE_FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
