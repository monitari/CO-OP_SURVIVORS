extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "UX_FLOW_FAIL", 60.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "UX_FLOW_FAIL"):
		return
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	main._update_hud()
	_check(main.p1_status_label.text.contains("P1"), "split HUD identifies P1")
	_check(main.p2_status_label.text.contains("P2"), "split HUD identifies P2")
	_check(not main.help_label.visible, "the permanent controls strip stays off the play field")
	_check(main.xp_bar.max_value == main.progression.required_experience, "the XP bar tracks the shared requirement on its own")

	main.players[0].position = Vector2(-main.chain_max_length * 0.43, 0.0)
	main.players[1].position = Vector2(main.chain_max_length * 0.43, 0.0)
	main._update_chain_visual()
	main._update_hud()
	_check(main._tension_damage_multiplier() > 1.0, "gold overcharge stage grants the advertised bonus")
	_check(main.chain_status_label.text.contains("과충전"), "HUD names the beneficial chain stage")
	_check(main.chain_status_label.visible, "a chain state worth acting on is shown")
	main.players[0].position = Vector2(-20.0, 0.0)
	main.players[1].position = Vector2(20.0, 0.0)
	main._update_hud()
	_check(not main.chain_status_label.visible, "a neutral chain says nothing at all")

	await _test_chain_integrity(main)

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
		print("UX_FLOW_PASS: HUD, chain states, overcharge cost, telegraphs, pause/settings, boss victory")
		quit(0)
	else:
		for failure in failures:
			push_error("UX_FLOW_FAIL: " + failure)
		quit(1)


## Places the pair at a given fraction of the chain limit and runs the integrity
## step for a stretch of simulated frames.
func _hold_chain(main: Node, tension: float, seconds: float) -> void:
	var half: float = main.chain_max_length * tension * 0.5
	main.players[0].position = Vector2(-half, 0.0)
	main.players[1].position = Vector2(half, 0.0)
	var delta := 1.0 / 60.0
	for frame in int(seconds / delta):
		main._update_chain_integrity(delta)


func _test_chain_integrity(main: Node) -> void:
	main.chain_integrity = main.CHAIN_INTEGRITY_MAX
	main.chain_overloaded = false
	for player in main.players:
		player.invulnerability = 0.0
		player.health = player.max_health

	# Overcharging is a loan: it has to visibly cost something per second.
	_hold_chain(main, 0.86, 2.0)
	var after_overcharge: float = main.chain_integrity
	_check(after_overcharge < main.CHAIN_INTEGRITY_MAX, "holding overcharge drains chain integrity")
	_check(main._tension_damage_multiplier() > 1.0, "the bonus still applies while integrity remains")

	# The band between the resist and warning ratios must be genuinely neutral.
	_hold_chain(main, 0.76, 2.0)
	_check(is_equal_approx(main.chain_integrity, after_overcharge), "the neutral band neither drains nor repays")

	# Running the bar out must invert the reward, not merely remove it.
	var health_before: float = main.players[0].health
	_hold_chain(main, 1.0, 12.0)
	_check(main.chain_overloaded, "sustained overcharge overloads the chain")
	_check(main.chain_integrity <= 0.0, "overload empties the integrity bar")
	_check(main.players[0].health < health_before, "overload jolts both survivors")
	_check(main._tension_damage_multiplier() < 1.0, "an overloaded chain penalises damage instead of boosting it")
	main._update_hud()
	_check(main.chain_status_label.text.contains("과부하"), "HUD names the overload state")
	_check(main.chain_integrity_bar.value <= 0.0, "the integrity bar bottoms out rather than repeating the number in text")

	# Closing up is the only way back, and it must actually clear the penalty.
	_hold_chain(main, 0.5, 4.0)
	_check(main.chain_integrity > 0.0, "closing up repairs the chain")
	_check(not main.chain_overloaded, "repairing past the clear threshold ends the penalty")
	print("CHAIN_METRICS: overcharge_2s=%.0f%% repaired=%.0f%%" % [after_overcharge, main.chain_integrity])

	main.chain_integrity = main.CHAIN_INTEGRITY_MAX
	main.chain_overloaded = false
	for player in main.players:
		player.health = player.max_health
		player.invulnerability = 0.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
