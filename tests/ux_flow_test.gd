extends SceneTree

const MainScene := preload("res://scenes/main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	main._update_hud()
	_check(main.p1_status_label.text.contains("P1"), "split HUD identifies P1")
	_check(main.p2_status_label.text.contains("P2"), "split HUD identifies P2")
	_check(main.help_label.text.contains("공유 XP"), "shared XP is labeled at the XP bar")

	main.players[0].position = Vector2(-main.chain_max_length * 0.43, 0.0)
	main.players[1].position = Vector2(main.chain_max_length * 0.43, 0.0)
	main._update_chain_visual()
	main._update_hud()
	_check(main._tension_damage_multiplier() > 1.0, "gold overcharge stage grants the advertised bonus")
	_check(main.chain_status_label.text.contains("과충전"), "HUD names the beneficial chain stage")

	var charger := main.wave_director._acquire_enemy("charger", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	charger.position = main.players[0].position + Vector2(220.0, 0.0)
	charger.behavior_timer = 0.0
	charger.step(main.players, 0.016)
	_check(charger.charge_windup > 0.0 and charger.charge_timer <= 0.0, "charger displays a windup before moving fast")
	main.wave_director.release_enemy(charger)

	main._set_pause(true)
	_check(main.pause_active and main.pause_overlay.visible and paused, "pause opens persistent settings overlay")
	main._set_pause(false)
	_check(not main.pause_active and not paused, "pause overlay resumes combat")

	var boss := main.wave_director._acquire_enemy("brute", 3.0, Vector2.ZERO, true, true) as ChaserEnemy
	main._register_enemy(boss)
	_check(main.boss_bar.visible and main.boss_label.visible, "boss arrival exposes name and health bar")
	boss.take_damage(999999.0)
	_check(main.run_won and main.result_overlay.visible and paused, "boss defeat opens a persistent victory result")

	if failures.is_empty():
		print("UX_FLOW_PASS: HUD, chain states, telegraphs, pause/settings, boss victory")
		quit(0)
	else:
		for failure in failures:
			push_error("UX_FLOW_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
