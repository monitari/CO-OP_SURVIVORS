extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "BOSS_PATTERN_FAIL", 60.0)
	call_deferred("_run")


## No existing test actually exercises _step_boss(): the UX/visual tests only
## register the boss and one-shot it with take_damage(999999.0). This drives
## the boss through step() directly so the Chain Slam telegraph, its signal
## wiring into main.gd's chain-integrity drain, the speed-up over the old
## brute stat block, and the enrage charge dash are all verified against
## actual behavior rather than just "the branch compiles".
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "BOSS_PATTERN_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	main.players[0].position = Vector2(-80.0, 0.0)
	main.players[1].position = Vector2(80.0, 0.0)
	main.chain_integrity = main.CHAIN_INTEGRITY_MAX

	var boss := main.wave_director._acquire_enemy("brute", 4.0, Vector2(0.0, 150.0), true, true) as ChaserEnemy
	var effects_before: int = main.weapon_controller.get_child_count()
	main._register_enemy(boss) # wires chain_slam into main._on_boss_chain_slam
	_check(main.weapon_controller.get_child_count() > effects_before, "boss arrival creates a ceremonial combat flare")

	_check(boss.move_speed > 120.0, "the boss moves well above the old ~63px/s brute crawl (got %.1f)" % boss.move_speed)
	_check(boss.move_speed < 210.0, "the boss is still not as fast as a player before it enrages (got %.1f)" % boss.move_speed)

	var delta := 1.0 / 60.0

	# --- Chain Slam: deterministic before enrage, since the enrage-only dash
	# roll never applies yet — the else branch always fires.
	boss.boss_attack_timer = 0.0
	boss.step(main.players, delta)
	_check(boss.boss_slam_windup > 0.0, "an attack decision below 50%% HP always starts a Chain Slam windup")
	var impact: Vector2 = boss.boss_slam_point
	_check(impact.x >= -80.0 - 0.01 and impact.x <= 80.0 + 0.01 and absf(impact.y) < 0.01, "the slam targets a point on the actual chain segment (got %s)" % impact)

	# Player 0 stands in the blast, player 1 stays well clear of it.
	main.players[0].position = impact
	main.players[1].position = impact + Vector2(500.0, 500.0)
	# This test measures slam geometry, not the character's passive dodge roll.
	main.players[0].dodge_chance = 0.0
	main.players[1].dodge_chance = 0.0
	var p1_health_before: float = main.players[0].health
	var p2_health_before: float = main.players[1].health
	var integrity_before: float = main.chain_integrity

	while boss.boss_slam_windup > 0.0:
		boss.step(main.players, delta)
	await process_frame

	_check(main.players[0].health < p1_health_before, "a survivor standing in the impact radius takes damage")
	_check(main.players[1].health == p2_health_before, "a survivor well outside the impact radius is untouched")
	_check(is_equal_approx(main.chain_integrity, integrity_before - main.BOSS_SLAM_INTEGRITY_DRAIN), "the slam drains chain integrity by exactly BOSS_SLAM_INTEGRITY_DRAIN (got %.1f -> %.1f)" % [integrity_before, main.chain_integrity])

	# --- Enrage: crossing the 50% threshold should fire exactly once and
	# noticeably speed the boss up.
	var pre_enrage_speed: float = boss.move_speed
	boss.health = boss.max_health * 0.4
	boss.step(main.players, delta)
	_check(boss.boss_enraged, "dropping below half health enrages the boss")
	_check(boss.move_speed > pre_enrage_speed * 1.3, "enrage meaningfully speeds the boss up (%.1f -> %.1f)" % [pre_enrage_speed, boss.move_speed])

	boss.health = boss.max_health * 0.35 # stays enraged; re-triggering must not stack the speed boost again
	boss.step(main.players, delta)
	_check(absf(boss.move_speed - (pre_enrage_speed * 1.4)) < 1.0, "enrage's speed multiplier applies exactly once, not on every step (got %.2f)" % boss.move_speed)

	# --- Enraged charge dash: force an attack decision repeatedly until the
	# 50/50 roll picks the dash instead of another slam. Bounded by actual
	# decision points (12 genuine coin flips, ~1-in-4096 flake chance), not by
	# physics frames — a single slam's 0.7s windup alone is ~42 ticks, so
	# counting frames instead of decisions let one unlucky roll silently eat
	# the whole budget before a second coin flip ever happened.
	var dash_seen := false
	for decision in 12:
		boss.boss_attack_timer = 0.0
		boss.step(main.players, delta)
		if boss.charge_windup > 0.0:
			dash_seen = true
			break
		while boss.boss_slam_windup > 0.0:
			boss.step(main.players, delta)
	_check(dash_seen, "the enraged boss eventually rolls its charge dash instead of only ever slamming")

	if dash_seen:
		var position_before_dash: Vector2 = boss.position
		while boss.charge_windup > 0.0:
			boss.step(main.players, delta)
		var dash_speed: float = boss.move_speed # captured post-enrage, pre-dash
		var dash_start: Vector2 = boss.position
		var dash_ticks := 10
		for frame in dash_ticks:
			boss.step(main.players, delta) # charge_timer (0.5s) easily covers 10 ticks, so every one of them is full-speed dash, not a partial frame trailing off the end of it
		var dash_distance := dash_start.distance_to(boss.position)
		var expected_distance := dash_speed * 2.6 * delta * dash_ticks
		_check(absf(dash_distance - expected_distance) < expected_distance * 0.15, "the dash covers roughly move_speed*2.6 per tick (expected ~%.0f, got %.0f)" % [expected_distance, dash_distance])
		_check(boss.position != position_before_dash, "the boss moved during the windup->dash sequence")

	main.wave_director.release_enemy(boss)

	if failures.is_empty():
		print("BOSS_PATTERN_PASS: chain slam damages/drains correctly, speed raised, enrage triggers once, charge dash covers distance")
		quit(0)
	else:
		for failure in failures:
			push_error("BOSS_PATTERN_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
