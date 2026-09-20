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
	_check(main.p1_status_label.text.contains("나"), "split HUD identifies P1")
	_check(main.p2_status_label.text.contains("동료"), "split HUD identifies P2")
	_check(main.p1_health_text_label.text.contains("/"), "P1 health value is written inside its bar")
	_check(main.p2_health_text_label.text.contains("/"), "P2 health value is written inside its bar")
	_check(not main.help_label.visible, "the permanent controls strip stays off the play field")
	_check(main.xp_bar.max_value == main.progression.required_experience, "the XP bar tracks the shared requirement on its own")
	# What the meter has to say, not where it sits. It used to be a 6px strip
	# along the top of the play field and is now a full-width bar on the bottom
	# edge; layout_test owns that geometry, and this pinning the old numbers made
	# the two tests assert opposite things about the same bar. The part worth
	# keeping is that the bar is readable as a number and not only as a colour —
	# the pair share one level, and how far it is to the next one is a thing they
	# plan around.
	_check(main.xp_text_label.text.contains("LV.") and main.xp_text_label.text.contains("XP"),
		"the shared meter names the level and the experience (%s)" % main.xp_text_label.text)
	_check(main.xp_text_label.text.contains("/"),
		"and how far it is to the next one (%s)" % main.xp_text_label.text)
	for slot in 2:
		var frame: Panel = main.combat_hud.get_node("P%dFrame" % (slot + 1))
		var surface := frame.get_theme_stylebox("panel") as StyleBoxFlat
		_check(surface.bg_color.get_luminance() > 0.75 and surface.bg_color.a >= 0.94
			and frame.size.y <= 152,
			"player HUD uses a readable scrapbook surface with compact geometry")
		_check(not main.combat_hud.get_node("PlayerIdentity%d" % slot).text.contains("개인 Lv."),
			"player identity omits the redundant personal level")
	_check(main.chain_distance_text_label.text.contains("거리"), "the distance bar names what it measures")
	_check(main.chain_integrity_text_label.text.contains("내구도"), "the integrity bar names what it measures")

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

	# A run is five bosses now, so "a boss died" and "the run is over" are no
	# longer the same event, and both halves of that need pinning: an early
	# boss has to hand the run back, and only the last one may end it.
	var first_boss := main.wave_director._acquire_enemy("brute", 3.0, Vector2.ZERO, false, true, 1) as ChaserEnemy
	main._register_enemy(first_boss)
	# The bar paints its own name, rank pips and numbers now (see BossHealthBar),
	# so what has to be true is that the bar carries them — not that three
	# separate Labels are visible beside it.
	_check(main.boss_bar.visible, "boss arrival exposes the health bar")
	_check(String(main.boss_bar.boss_name) == main.boss_name(1),
		"the bar carries the boss's name (%s)" % main.boss_bar.boss_name)
	_check(int(main.boss_bar.rank) == 1 and int(main.boss_bar.rank_total) == WaveDirector.BOSS_COUNT,
		"and which of the five this is, as pips (%d/%d)" % [main.boss_bar.rank, main.boss_bar.rank_total])
	_check(String(main.boss_bar.health_text).contains("/"),
		"boss health is written above its bar (%s)" % main.boss_bar.health_text)
	_check(is_equal_approx(float(main.boss_bar.ratio), 1.0), "a fresh boss opens at a full bar")
	first_boss.take_damage(999999.0)
	_check(not main.run_won and not main.result_overlay.visible,
		"defeating an early boss returns the pair to the run")
	_check(not main.boss_bar.visible, "and takes the boss bar back down")

	var final_boss := main.wave_director._acquire_enemy(
		"brute", 3.0, Vector2.ZERO, false, true, WaveDirector.BOSS_COUNT) as ChaserEnemy
	main._register_enemy(final_boss)
	final_boss.take_damage(999999.0)
	_check(main.run_won and main.result_overlay.visible and paused, "the final boss opens a persistent victory result")
	_check(main.result_overlay.has_node("ResultRetry") and main.result_overlay.has_node("ResultMenu"),
		"the result offers direct retry and main-menu actions")
	_check((main.result_overlay.get_node("ResultRetry") as Button).text.contains("ENTER")
		and (main.result_overlay.get_node("ResultMenu") as Button).text.contains("ESC"),
		"result actions advertise their keyboard controls")

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
