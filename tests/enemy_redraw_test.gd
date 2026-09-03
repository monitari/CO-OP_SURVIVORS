extends SceneTree

const EnemyScript := preload("res://scripts/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []
var players: Array[ChainPlayer] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "ENEMY_REDRAW_FAIL", 30.0)
	call_deferred("_run")


## enemy.step() used to call queue_redraw() unconditionally every physics tick
## for every active enemy. Position/rotation move via the node transform and
## never need a redraw; the only per-frame state _draw() actually reads is the
## telegraph windup timers. This locks in that idle enemies stop redrawing
## every tick, and — the part that is easy to get subtly wrong — that a
## telegraph still redraws on its exact entry and exit frame instead of
## leaving a stale line on screen for however long it takes something else to
## trigger a redraw.
func _run() -> void:
	var far_player := ChainPlayer.new()
	far_player.position = Vector2(5000.0, 5000.0)
	root.add_child(far_player)
	players = [far_player, far_player]

	await _test_idle_enemy_stops_redrawing()
	await _test_charger_telegraph_redraws_every_relevant_frame()
	await _test_damage_still_redraws_an_idle_enemy()

	if failures.is_empty():
		print("ENEMY_REDRAW_PASS: idle enemies stop redrawing, telegraphs still redraw exactly when needed")
		quit(0)
	else:
		for failure in failures:
			push_error("ENEMY_REDRAW_FAIL: " + failure)
		quit(1)


func _test_idle_enemy_stops_redrawing() -> void:
	var enemy := EnemyScript.new() as ChaserEnemy
	root.add_child(enemy)
	enemy.setup(0.0, "chaser")
	enemy.position = Vector2.ZERO
	await process_frame
	var baseline := enemy.redraw_count

	var delta := 1.0 / 60.0
	for frame in 60:
		enemy.step(players, delta)
	await process_frame

	_check(enemy.redraw_count == baseline, "an idle chaser with no telegraph does not redraw across 60 physics ticks (count stayed at %d)" % baseline)
	enemy.queue_free()


func _test_charger_telegraph_redraws_every_relevant_frame() -> void:
	var enemy := EnemyScript.new() as ChaserEnemy
	root.add_child(enemy)
	enemy.setup(0.0, "charger")
	enemy.position = Vector2.ZERO
	enemy.behavior_timer = 0.0 # force the windup to start on the next step
	await process_frame

	var delta := 1.0 / 60.0
	var before_count := enemy.redraw_count
	enemy.step(players, delta) # entry frame: charge_windup goes 0 -> 0.55
	await process_frame
	_check(enemy.redraw_count > before_count, "the windup's entry frame redraws so the telegraph line actually appears")
	_check(enemy.charge_windup > 0.0, "setup left enough windup duration to observe a mid-windup frame")

	before_count = enemy.redraw_count
	enemy.step(players, delta) # mid-windup: still active on both sides of the step
	await process_frame
	_check(enemy.redraw_count > before_count, "a mid-windup frame keeps redrawing for the pulsing telegraph alpha")

	# Godot coalesces multiple queue_redraw() calls made before the next render
	# into a single _draw() dispatch, so isolating one specific call's effect
	# needs a flush (await process_frame) after every step — otherwise an
	# earlier iteration's redraw can mask a missing one on the exact exit frame.
	while enemy.charge_windup > 0.0:
		before_count = enemy.redraw_count
		enemy.step(players, delta)
		await process_frame
		if enemy.charge_windup <= 0.0:
			_check(enemy.redraw_count > before_count, "the windup's exit frame redraws so the telegraph line actually clears")

	before_count = enemy.redraw_count
	enemy.charge_timer = 0.0
	enemy.step(players, delta) # back to idle patrol, no telegraph on either side
	await process_frame
	_check(enemy.redraw_count == before_count, "once the telegraph is gone the charger stops redrawing again")
	enemy.queue_free()


func _test_damage_still_redraws_an_idle_enemy() -> void:
	var enemy := EnemyScript.new() as ChaserEnemy
	root.add_child(enemy)
	enemy.setup(0.0, "chaser")
	await process_frame
	var before_count := enemy.redraw_count
	enemy.take_damage(5.0)
	await process_frame
	_check(enemy.redraw_count > before_count, "take_damage() still redraws directly so the health bar updates on hit")
	enemy.queue_free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
