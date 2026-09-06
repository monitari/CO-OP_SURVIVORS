extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []
var downs := 0
var first_down_time := -1.0
var active_main: Node


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
	# High acceleration is convenient for broad system soaks, but fast straight
	# projectiles can jump across a small enemy between physics frames. Allow a
	# slower balance pass so projectile and melee loadouts are compared fairly.
	# Seeded, like normal_speed_balance_test. An unseeded instrument measured
	# 28s, 51s, 66s and 46s of survival on four runs of the same build — a
	# hundred-percent swing, which makes it useless for the one job it has
	# (comparing before and after a change) and makes its assertions flaky
	# around any threshold worth setting. Seeding narrows it to roughly 52-63s
	# rather than removing it — the run is accelerated, so physics deltas still
	# depend on how fast the frames actually come — but that is inside the band
	# instead of straddling it.
	var run_seed := int(OS.get_environment("CHAINBOUND_TEST_SEED")) if OS.has_environment("CHAINBOUND_TEST_SEED") else 20260905
	seed(run_seed)
	var simulation_speed := float(OS.get_environment("CHAINBOUND_TEST_SPEED")) if OS.has_environment("CHAINBOUND_TEST_SPEED") else 20.0
	Engine.time_scale = maxf(1.0, simulation_speed)
	var active_controls := OS.get_environment("CHAINBOUND_TEST_ACTIVE") == "1"
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "PRESSURE_SOAK_FAIL"):
		Engine.time_scale = 1.0
		return

	var p1_index := int(OS.get_environment("CHAINBOUND_TEST_P1")) if OS.has_environment("CHAINBOUND_TEST_P1") else 0
	var p2_index := int(OS.get_environment("CHAINBOUND_TEST_P2")) if OS.has_environment("CHAINBOUND_TEST_P2") else 1
	main.selected_character_indices[0] = clampi(p1_index, 0, main.character_catalog.size() - 1)
	main.selected_character_indices[1] = clampi(p2_index, 0, main.character_catalog.size() - 1)
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	active_main = main
	for player in main.players:
		player.downed_started.connect(_on_downed)
	main.experience_system.magnet_radius = 3000.0 # the bot cannot chase gems

	var peak_active := 0
	var reached_boss := false
	var frame_budget := 1800 if active_controls else 900
	for frame in frame_budget:
		if main.game_over:
			break
		var angle := float(frame) * 0.025
		var center := Vector2(cos(angle * 0.22), sin(angle * 0.22)) * 220.0
		var next_positions := [
			center + Vector2.from_angle(angle) * 145.0,
			center - Vector2.from_angle(angle) * 145.0,
		]
		if active_controls:
			if main.players[0].downed and not main.players[1].downed:
				next_positions[0] = main.players[0].position
				next_positions[1] = main.players[0].position + Vector2(70.0, 0.0)
			elif main.players[1].downed and not main.players[0].downed:
				next_positions[1] = main.players[1].position
				next_positions[0] = main.players[1].position - Vector2(70.0, 0.0)
		for player_index in 2:
			var travel: Vector2 = next_positions[player_index] - main.players[player_index].position
			if travel.length_squared() > 0.01:
				main.players[player_index].last_input = travel.normalized()
				main.players[player_index].current_input = travel.normalized()
			main.players[player_index].position = next_positions[player_index]
			# Directly placing the bot means Input.get_vector() cannot express the
			# short facing corrections a person makes before a directional swing.
			# Aim at the nearest threat while keeping current_input as the travel
			# direction used by the chain constraint.
			var target: ChaserEnemy = main.spatial_grid.nearest(main.players[player_index].position, 700.0)
			if is_instance_valid(target):
				main.players[player_index].last_input = main.players[player_index].position.direction_to(target.position)
				if active_controls and target.position.distance_to(main.players[player_index].position) < 135.0 and main.players[player_index].dash_ready():
					main.players[player_index].last_input = target.position.direction_to(main.players[player_index].position)
					main.players[player_index].try_dash()
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
	print("PRESSURE_METRICS: pair=%s+%s survived=%.1fs first_down=%.1fs won=%s kills=%d kps=%.2f level=%d downs=%d peak_active=%d reached_boss=%s" % [
		main.players[0].character_name, main.players[1].character_name, survived, first_down_time,
		str(main.run_won), main.kills, kills_per_second, main.progression.level, downs, peak_active, str(reached_boss)
	])
	print("PRESSURE_HEALTH: p1=%.0f/%.0f p2=%.0f/%.0f" % [
		main.players[0].health, main.players[0].max_health,
		main.players[1].health, main.players[1].max_health
	])

	# This bot circles at a fixed radius and walks straight into contact
	# damage, so it is a floor on difficulty rather than a verdict on it: a
	# real pair dodges. After the opening-pacing pass the standard pair holds
	# for roughly 50-65 seconds and earns 34+ kills across repeated runs. Keep
	# the guard band below that distribution while still catching a return to
	# the old 25-second collapse.
	_check(survived >= 40.0, "the pair survives the learning window (survived %.1fs)" % survived)
	_check(first_down_time < 0.0 or first_down_time >= 35.0,
		"the first down comes after the opening lessons (%.1fs)" % first_down_time)
	# Lowered from 25 when two things moved underneath it at once: a starting
	# weapon is now about three quarters of what it was, and the opening spawn
	# stream was eased to match, so there is both less killing power and less to
	# kill. What this guard is actually for — a pair that cannot fight at all —
	# is measured by the two checks above it, and those did not move: survival
	# held at 56s against the old 57s and the down count is unchanged. Only the
	# clear rate fell, which is the trade the rebalance was asking for.
	_check(main.kills >= 15, "the automated pair is actually clearing enemies (%d kills)" % main.kills)
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
	if first_down_time < 0.0 and is_instance_valid(active_main):
		first_down_time = active_main.elapsed


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
