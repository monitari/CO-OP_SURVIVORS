extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "DASH_FAIL", 60.0)
	call_deferred("_run")


## The pressure measurement showed the pair has no way to answer a telegraphed
## attack except to walk out of it, which is not fast enough. The dash is that
## answer, and these checks pin the three things that make it one rather than a
## free movement upgrade: it costs a cooldown, it grants real invulnerability,
## and a downed survivor cannot use it to escape a rescue.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "DASH_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_burst_and_cooldown(main)
	_test_invulnerability(main)
	_test_downed_cannot_dash(main)
	_test_chain_bounds_the_dash(main)
	_test_run_stats(main)

	if failures.is_empty():
		print("DASH_PASS: dash bursts, grants i-frames, respects cooldown, and stays inside the chain")
		quit(0)
	else:
		for failure in failures:
			push_error("DASH_FAIL: " + failure)
		quit(1)


func _fresh(main: Node, index: int) -> ChainPlayer:
	var player: ChainPlayer = main.players[index]
	player.dash_timer = 0.0
	player.dash_cooldown = 0.0
	player.invulnerability = 0.0
	player.downed = false
	player.health = player.max_health
	player.last_input = Vector2.RIGHT
	return player


func _test_burst_and_cooldown(main: Node) -> void:
	var player := _fresh(main, 0)
	player.position = Vector2.ZERO
	_check(player.dash_ready(), "a rested survivor can dash")
	_check(player.try_dash(), "the dash actually starts")
	_check(not player.dash_ready(), "a dash in progress is not another dash")
	_check(not player.try_dash(), "the dash cannot be re-triggered while it runs")

	# Cover the whole burst and compare against plain walking over the same time.
	var delta := 1.0 / 60.0
	var ticks := int(ceil(ChainPlayer.DASH_DURATION / delta))
	for tick in ticks:
		player.step_movement(delta)
	var dashed_distance := player.position.length()
	var walked := player.move_speed * float(ticks) * delta
	_check(dashed_distance > walked * 2.0,
		"the dash covers far more ground than walking (%.0fpx vs %.0fpx)" % [dashed_distance, walked])
	_check(player.dash_timer <= 0.0, "the burst ends on its own")
	_check(player.dash_cooldown > 0.0, "the dash leaves a cooldown behind")
	_check(not player.dash_ready(), "the cooldown blocks an immediate second dash")

	# Wind the cooldown down and confirm it clears rather than sticking.
	for tick in int(ChainPlayer.DASH_COOLDOWN / delta) + 2:
		player.step_movement(delta)
	_check(player.dash_ready(), "the dash comes back once the cooldown elapses")
	print("DASH_METRICS: burst=%.0fpx walk=%.0fpx cooldown=%.2fs iframes=%.2fs" % [
		dashed_distance, walked, ChainPlayer.DASH_COOLDOWN, ChainPlayer.DASH_INVULNERABILITY
	])


func _test_invulnerability(main: Node) -> void:
	var player := _fresh(main, 0)
	player.try_dash()
	_check(player.invulnerability > 0.0, "the dash grants invulnerability")
	var health_before := player.health
	_check(not player.hurt(25.0), "a hit during the dash is refused")
	_check(is_equal_approx(player.health, health_before), "a hit during the dash costs no health")

	# And it must actually run out — otherwise the dash is a permanent shield.
	player.invulnerability = 0.0
	player.dash_timer = 0.0
	_check(player.hurt(25.0), "damage lands again once the invulnerability ends")

	# The window has to outlast the burst, or the last frames of the dash are
	# spent unprotected inside whatever the player dashed through.
	_check(ChainPlayer.DASH_INVULNERABILITY > ChainPlayer.DASH_DURATION,
		"the invulnerability window covers the whole burst")


func _test_downed_cannot_dash(main: Node) -> void:
	var player := _fresh(main, 0)
	player.downed = true
	_check(not player.dash_ready(), "a downed survivor has no dash")
	_check(not player.try_dash(), "a downed survivor cannot dash out of a rescue")
	_check(player.dash_timer <= 0.0, "the refused dash left no burst behind")
	player.downed = false


func _test_chain_bounds_the_dash(main: Node) -> void:
	# A dash that outranges the chain would let one survivor break off alone,
	# which is the one thing the whole design is built to prevent. The burst is
	# deliberately shorter than the leash so the constraint catches it.
	var reach := 0.0
	var player := _fresh(main, 0)
	reach = player.move_speed * ChainPlayer.DASH_SPEED_MULTIPLIER * ChainPlayer.DASH_DURATION
	_check(reach < main.chain_max_length,
		"a dash cannot clear the chain on its own (%.0fpx reach vs %.0fpx chain)" % [reach, main.chain_max_length])

	# Dashing apart still ends with the pair inside the chain, because the
	# constraint runs after movement.
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(60.0, 0.0)
	_fresh(main, 0).last_input = Vector2.LEFT
	_fresh(main, 1).last_input = Vector2.RIGHT
	main.players[0].try_dash()
	main.players[1].try_dash()
	var delta := 1.0 / 60.0
	for tick in int(ceil(ChainPlayer.DASH_DURATION / delta)):
		main.players[0].step_movement(delta)
		main.players[1].step_movement(delta)
		main._apply_chain_constraint()
	var gap: float = main.players[0].position.distance_to(main.players[1].position)
	_check(gap <= main.chain_max_length + 1.0,
		"two survivors dashing apart still end inside the chain (%.0fpx of %.0fpx)" % [gap, main.chain_max_length])


func _test_run_stats(main: Node) -> void:
	# run_stats sat declared and unread for three sessions; the result screen now
	# prints it, so it has to actually count.
	var before: int = int(main.run_stats["dashes"])
	var player := _fresh(main, 0)
	player.try_dash()
	_check(int(main.run_stats["dashes"]) == before + 1, "a dash is tallied for the result screen")
	_check(not main.run_stats.has("pings"), "the never-built ping counter is gone")
	var summary: String = main._run_stats_summary()
	_check(summary.contains("대시"), "the result screen reports the dash count")
	_check(summary.contains("구조"), "the result screen still reports rescues")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
