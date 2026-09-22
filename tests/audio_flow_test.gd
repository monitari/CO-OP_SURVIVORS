extends SceneTree

const TestHarness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	TestHarness.arm_watchdog(self, "AUDIO_FLOW_TEST_FAIL", 30.0)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	main.set_process(false)
	var feedback: FeedbackSystem = main.feedback
	feedback.sound_enabled = true
	feedback.music_enabled = true
	feedback.sound_volume = 0.75
	feedback.music_volume = 0.7
	feedback.refresh_sound()
	feedback.refresh_music()
	_check(feedback._current_track == "title", "title entry starts its theme")
	main._start_selected_run()
	main.set_physics_process(false)
	main.set_process(false)
	_check(feedback._current_track == "field", "starting a run selects the field theme")
	feedback._tone_cache.clear()
	for player in main.players:
		player.health = player.max_health
	main._trigger_chain_overload()
	_check(feedback._tone_cache.has("chain_overload") and not feedback._tone_cache.has("down"),
		"chain overload is distinct from a downed partner")
	main.players[1].position = main.players[0].position
	main.chain_integrity = main.CHAIN_INTEGRITY_MAX
	main._update_chain_integrity(0.1)
	_check(feedback._tone_cache.has("chain_repaired") and not feedback._tone_cache.has("revive"),
		"chain recovery is distinct from partner revival")
	main._on_player_downed(main.players[0])
	_check(feedback._tone_cache.has("down"), "partner down retains its dedicated signal")

	var enemy := ChaserEnemy.new()
	main.world_stage.add_child(enemy)
	enemy.setup(1.0, "chaser", false, true, 1)
	main._register_enemy(enemy)
	_check(feedback._current_track == "boss", "boss arrival changes the music")
	enemy.boss_attack_timer = 0.0
	enemy._step_boss(main.players, main.players[0].position, 1.0, 0.01)
	_check(feedback._tone_cache.has("danger") and enemy.boss_slam_windup > 0.0,
		"boss attack warning sounds before the slam lands")
	main._on_boss_enraged(enemy)
	_check(feedback._current_track == "boss_enraged", "enrage changes the arrangement")

	enemy.boss_rank = 2
	main._on_enemy_died(enemy)
	_check(feedback._current_track == "field_late", "second boss defeat selects the late field arrangement")
	main._end_run(false, false)
	_check(feedback._current_track == "result_loss", "defeat has its own music")
	main.game_over = false
	main._end_run(true, false)
	_check(feedback._current_track == "result_win", "victory has its own music")
	main._begin_title()
	_check(feedback._current_track == "title", "returning to title restores the menu theme")
	paused = false
	main.queue_free()
	await process_frame
	# Allow AudioServer and deferred scene resources to finish releasing.
	await create_timer(0.15).timeout
	if failures.is_empty():
		print("AUDIO_FLOW_TEST_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("AUDIO_FLOW_TEST_FAIL: " + failure)
		quit(1)
