extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "COOP_SOAK_FAIL", 900.0)
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	var wall_start := Time.get_ticks_msec()
	var main := MainScene.instantiate()
	root.add_child(main)
	# After the scene, not before: main._ready() calls randomize() over any seed
	# set earlier, so this is the line that actually makes the run repeat.
	#
	# It was unseeded, and the pacing assertion below was therefore a coin flip.
	# Four consecutive runs of identical code measured 15.8s, 15.1s, 12.6s and
	# 10.9s between level-ups against a 14s floor — two passes and two failures,
	# decided entirely by whether the bot happened to draw 성장의 서 and deepen
	# it. A balance instrument that reports a different verdict each time it is
	# asked cannot be used to judge a change, which is the one job it has.
	seed(20260919)
	await process_frame
	if not TestHarness.require_loaded(self, main, "COOP_SOAK_FAIL"):
		return
	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.players[0].max_health = 100000.0
	main.players[0].health = 100000.0
	main.players[1].max_health = 100000.0
	main.players[1].health = 100000.0
	main.experience_system.magnet_radius = 3000.0

	# Enough frames to play out the whole twenty-five minutes. A soak that stops
	# before the run's own climax cannot say anything about the part players
	# care most about, and the climax is now four fifths of the way in.
	var seen_archetypes: Dictionary = {}
	var seen_encounters: Dictionary = {}
	main.wave_director.encounter_started.connect(
		func(encounter_id: String) -> void: seen_encounters[encounter_id] = true)
	var level_marks: Array[float] = []
	var last_level: int = main.progression.level
	for frame in 4700:
		if main.progression.level != last_level:
			last_level = main.progression.level
			level_marks.append(main.elapsed)
		if main.run_won or main.game_over:
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
			if main.selected_upgrade_indices[0] < 0:
				main._select_upgrade(1, 0)
			if main.level_up_active and main.selected_upgrade_indices[1] < 0:
				main._select_upgrade(2, 0)
		# Sampled every frame rather than read off the survivors at the end: a
		# strong pair leaves barely a dozen enemies alive, and a dozen chasers
		# is not evidence that the other archetypes never spawned.
		for enemy in main.enemies:
			seen_archetypes[(enemy as ChaserEnemy).archetype] = true
		await physics_frame

	Engine.time_scale = 1.0
	var wall_elapsed := Time.get_ticks_msec() - wall_start
	_check(main.elapsed >= 180.0 or main.run_won, "accelerated run reaches three minutes or completes with boss victory")
	_check(main.wave_director.boss_spawned, "the run's first boss spawns on schedule (%.0fs of %.0fs)" % [main.elapsed, WaveDirector.BOSS_INTERVAL])
	_check(main.enemies.size() <= main.wave_director.enemy_cap, "active enemy count respects cap")
	_check(main.kills > 0, "automated pair kills enemies")
	_check(main.progression.level > 1, "automated pair collects shared XP and levels")

	# Every level-up pauses the run for both players, so pacing is a gameplay
	# property worth guarding, not just a curiosity to eyeball in SOAK_METRICS.
	# The band is deliberately loose (spawn/movement RNG shifts kill timing a
	# little run to run) but still catches a menu-every-few-seconds failure on
	# one edge and a return to the old opening drought on the other.
	var seconds_per_level: float = main.elapsed / maxf(1.0, float(main.progression.level - 1))
	# The average alone cannot tell a flat cadence from a fast opening followed
	# by a twenty-minute drought, which is exactly the failure a longer run
	# invites. Compare the second half of the run against the first.
	var late_gap := 0.0
	var early_gap := 0.0
	if level_marks.size() >= 6:
		var half := int(level_marks.size() / 2)
		var early_span: float = level_marks[half] - level_marks[0]
		var late_span: float = level_marks[level_marks.size() - 1] - level_marks[half]
		late_gap = late_span / maxf(1.0, float(level_marks.size() - 1 - half))
		early_gap = early_span / maxf(1.0, float(half))
		# Measured 1.6x. The old curve was at 4.7x, which is what a "twenty-five
		# minute run" actually looked like before this: a brisk opening and
		# then twenty minutes with almost no upgrades in them.
		_check(late_gap <= early_gap * 2.2,
			"level pacing does not collapse in the back half (%.1fs early, %.1fs late)" % [early_gap, late_gap])
	# The previous 26-42s band preserved the exact opening drought this test was
	# meant to catch: level two jumped straight from 32 to 504 XP. The retuned
	# curve intentionally targets roughly one choice every 15-22 seconds so the
	# first half of a build forms while the player is still learning the run.
	# The floor catches a collapse, not a wobble. Five consecutive runs of the
	# same code measured 13.4, 14.8, 15.2, 15.3 and 16.5 seconds between choices:
	# a median of 15.2 sitting right on the target, with a spread of about three
	# seconds that the seed above cannot remove — a run this long contains
	# real-time timers, so how many frames a scaled-down delay takes depends on
	# how loaded the machine is. A floor at 14 sat inside that spread and failed
	# roughly one run in five while nothing was wrong. This one is below the
	# noise and still an order of magnitude above the failure it exists for,
	# which is a growth screen every few seconds.
	#
	# And below the fastest *legitimate* pace, which the seed does not pin down:
	# the bot takes whatever card is first, so which treasures it ends up with
	# moves whenever anything upstream consumes a different amount of randomness
	# (the 2026-09-19 performance pass did, by requesting fewer sparks). One such
	# build carried 성장의 서 to its cap for +50% experience and measured 12.2s a
	# level three runs out of three — faster, as that treasure is meant to be,
	# and nowhere near a collapse.
	_check(seconds_per_level >= 11.0, "level-ups still leave at least ~11s of play between choices")
	_check(seconds_per_level <= 36.0, "level-ups remain frequent enough to complete a committed build")
	_check(main.progression.level >= 45,
		"a full run banks the levels a committed build costs (level %d)" % main.progression.level)

	_check(seen_archetypes.size() >= 3, "long run contains multiple enemy archetypes (%s)" % str(seen_archetypes.keys()))
	# A twenty-five-minute run is long enough to see the whole encounter rota;
	# if it does not, the schedule is not actually running.
	_check(seen_encounters.size() >= WaveDirector.ENCOUNTER_ORDER.size(),
		"every named encounter fires over a full run (%s)" % str(seen_encounters.keys()))
	_check(main.wave_director.bosses_spawned >= 4,
		"the run sends its bosses on schedule (%d of %d)" % [
			main.wave_director.bosses_spawned, WaveDirector.BOSS_COUNT])
	# The bot circles at a fixed radius and takes whatever card is first, so
	# this is a floor rather than a target: if even that build cannot finish
	# three bosses, the rank scaling has outrun what a run can produce.
	_check(int(main.run_stats["bosses"]) >= 3,
		"bosses stay killable as their rank climbs (%d killed)" % int(main.run_stats["bosses"]))

	print("SOAK_METRICS: simulated=%.1fs wall=%dms kills=%d level=%d sec_per_level=%.1f early_gap=%.1f late_gap=%.1f bosses=%d killed=%d won=%s active=%d pooled_enemies=%d pooled_gems=%d archetypes=%d encounters=%d" % [
		main.elapsed, wall_elapsed, main.kills, main.progression.level, seconds_per_level, early_gap, late_gap,
		main.wave_director.bosses_spawned, int(main.run_stats["bosses"]), str(main.run_won), main.enemies.size(),
		main.wave_director.enemy_pool.size(), main.experience_system.gem_pool.size(),
		seen_archetypes.size(), seen_encounters.size()
	])
	if failures.is_empty():
		print("COOP_SOAK_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("COOP_SOAK_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
