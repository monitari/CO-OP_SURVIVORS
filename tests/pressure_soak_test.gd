extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []
var downs := 0


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "PRESSURE_SOAK_FAIL", 180.0)
	call_deferred("_run")


## coop_soak_test hands the pair 100000 health so it can exercise systems for
## three minutes without dying — which means it can say nothing at all about
## whether the fight is winnable. This run is the same automation at normal
## health: it measures how long a pair actually lasts, how often they go down,
## and how fast they clear. The numbers printed here are the input for tuning
## enemy scaling; the assertions are only a wide regression band around them.
func _run() -> void:
	Engine.time_scale = 20.0
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "PRESSURE_SOAK_FAIL"):
		Engine.time_scale = 1.0
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	for player in main.players:
		player.downed_started.connect(_on_downed)
	main.experience_system.magnet_radius = 3000.0 # the bot cannot chase gems

	var peak_active := 0
	var reached_boss := false
	for frame in 900:
		if main.game_over:
			break
		var angle := float(frame) * 0.025
		var center := Vector2(cos(angle * 0.22), sin(angle * 0.22)) * 220.0
		main.players[0].position = center + Vector2.from_angle(angle) * 145.0
		main.players[1].position = center - Vector2.from_angle(angle) * 145.0
		if main.resonance_vote_active:
			main.resonance_votes[0] = 0
			main.resonance_votes[1] = 0
			main._handle_resonance_vote_input()
		elif main.level_up_active:
			main.level_up_input_delay = 0.0
			if main.selected_upgrade_indices[0] < 0:
				main._select_upgrade(1, 0)
			if main.level_up_active and main.selected_upgrade_indices[1] < 0:
				main._select_upgrade(2, 0)
		peak_active = maxi(peak_active, main.enemies.size())
		reached_boss = reached_boss or main.wave_director.boss_spawned
		await physics_frame
	Engine.time_scale = 1.0

	var survived: float = main.elapsed
	var kills_per_second := float(main.kills) / maxf(1.0, survived)
	print("PRESSURE_METRICS: survived=%.1fs won=%s kills=%d kps=%.2f level=%d downs=%d peak_active=%d reached_boss=%s" % [
		survived, str(main.run_won), main.kills, kills_per_second, main.progression.level, downs, peak_active, str(reached_boss)
	])
	print("PRESSURE_HEALTH: p1=%.0f/%.0f p2=%.0f/%.0f" % [
		main.players[0].health, main.players[0].max_health,
		main.players[1].health, main.players[1].max_health
	])

	# This bot circles at a fixed radius and walks straight into contact
	# damage, so it is a floor on difficulty rather than a verdict on it: a
	# real pair dodges. The thresholds are set well under the measured
	# baseline (~40s, ~39 kills) so they only fire when something has broken
	# badly — the numbers printed above are what tuning actually reads.
	_check(survived >= 25.0, "the pair is not wiped out almost immediately (survived %.1fs)" % survived)
	_check(main.kills > 20, "the automated pair is actually clearing enemies (%d kills)" % main.kills)
	_check(peak_active < main.wave_director.enemy_cap, "culling keeps the active count under the cap (peak %d)" % peak_active)
	_check(downs > 0 or survived < 240.0 or not main.run_won,
		"an unattended pair does not sail through a full run untouched")

	if failures.is_empty():
		print("PRESSURE_SOAK_PASS: normal-health run measured end to end")
		quit(0)
	else:
		for failure in failures:
			push_error("PRESSURE_SOAK_FAIL: " + failure)
		quit(1)


func _on_downed(_player: ChainPlayer) -> void:
	downs += 1


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
