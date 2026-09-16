extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "RUN_SHAPE_FAIL", 120.0)
	call_deferred("_run")


## A run is twenty-five minutes and five bosses, not five minutes and one.
##
## The old shape handed out four weapon slots, four treasure slots, a seven-tier
## weapon track and twenty-one resonances inside a run that ended after about a
## dozen level-ups, so most of the game existed only on paper. The long run is
## structural rather than a bigger number on a timer: bosses arrive on a
## schedule and escalate, the four named encounters keep the stretches between
## them from being one flat slope, and the difficulty ramp is capped so minute
## twenty-five is hard rather than arithmetically impossible.
##
## coop_soak_test.gd plays the whole thing; this pins the rules it plays by.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "RUN_SHAPE_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_the_run_is_long()
	_test_bosses_arrive_on_schedule(main)
	_test_bosses_escalate()
	_test_encounters_have_distinct_shapes(main)
	_test_the_late_ramp_is_capped()
	_test_the_readout_tracks_the_schedule(main)

	if failures.is_empty():
		print("RUN_SHAPE_PASS: five bosses on schedule, four encounter shapes, a capped ramp")
		quit(0)
	else:
		for failure in failures:
			push_error("RUN_SHAPE_FAIL: " + failure)
		quit(1)


func _test_the_run_is_long() -> void:
	_check(WaveDirector.RUN_LENGTH >= 1200.0 and WaveDirector.RUN_LENGTH <= 1800.0,
		"a full run is twenty to thirty minutes (%.0fs)" % WaveDirector.RUN_LENGTH)
	_check(WaveDirector.BOSS_COUNT >= 3, "the run has several bosses in it (%d)" % WaveDirector.BOSS_COUNT)
	_check(is_equal_approx(WaveDirector.RUN_LENGTH, WaveDirector.BOSS_INTERVAL * WaveDirector.BOSS_COUNT),
		"the run length is the boss schedule rather than a separate number")


## The schedule is a queue, not a set of alarms: a boss that is still alive when
## the next one comes due has to hold the queue, or a slow fight snowballs into
## two health bars and then three.
func _test_bosses_arrive_on_schedule(main: Node) -> void:
	var director: WaveDirector = main.wave_director
	director.bosses_spawned = 0
	director.boss_active = false
	for expected in range(1, WaveDirector.BOSS_COUNT + 1):
		_check(is_equal_approx(director.next_boss_time(), WaveDirector.BOSS_INTERVAL * float(expected)),
			"boss %d is due at %.0fs" % [expected, WaveDirector.BOSS_INTERVAL * float(expected)])
		director.bosses_spawned = expected
	_check(director.bosses_remaining() == 0, "the schedule runs out after the last one")
	_check(is_equal_approx(director.next_boss_time(), WaveDirector.RUN_LENGTH),
		"and then points at the end of the run")

	# Held back while one is on the field.
	director.bosses_spawned = 1
	director.boss_active = true
	var spawned := director.step(1.0 / 60.0, WaveDirector.BOSS_INTERVAL * 2.5, Vector2.ZERO, 0)
	var arrived := 0
	for enemy in spawned:
		if (enemy as ChaserEnemy).boss:
			arrived += 1
	_check(arrived == 0, "no second boss arrives while the first is alive")
	_check(director.bosses_spawned == 1, "and the schedule does not advance past it")

	director.boss_active = false
	spawned = director.step(1.0 / 60.0, WaveDirector.BOSS_INTERVAL * 2.5, Vector2.ZERO, 0)
	arrived = 0
	for enemy in spawned:
		if (enemy as ChaserEnemy).boss:
			arrived += 1
	_check(arrived == 1, "the next boss arrives once the field is clear of one")
	_check(director.boss_active, "and the director marks the field as occupied")
	director.bosses_spawned = 0
	director.boss_active = false


## Five copies of one fight is a longer run, not a bigger one. Each rank has to
## be a real step up, and the last one has to be the hardest thing in the game.
func _test_bosses_escalate() -> void:
	var previous_health := 0.0
	var previous_damage := 0.0
	for rank in range(1, WaveDirector.BOSS_COUNT + 1):
		var boss := EnemyScript.new() as ChaserEnemy
		boss.setup(4.0, "brute", false, true, rank)
		_check(boss.boss_rank == rank, "boss %d carries its rank" % rank)
		_check(boss.max_health > previous_health,
			"boss %d is tougher than boss %d (%.0f vs %.0f)" % [rank, rank - 1, boss.max_health, previous_health])
		_check(boss.contact_damage > previous_damage,
			"boss %d hits harder than boss %d" % [rank, rank - 1])
		# Tougher, but not on a curve nobody can answer: the pair roughly
		# doubles its output between two boss fights, so a boss may not.
		if previous_health > 0.0:
			_check(boss.max_health < previous_health * 2.0,
				"boss %d is not more than twice boss %d (%.2fx)" % [rank, rank - 1, boss.max_health / previous_health])
		previous_health = boss.max_health
		previous_damage = boss.contact_damage
		boss.free()

	# An ordinary brute is not a boss, so the rank multiplier must not leak.
	var plain := EnemyScript.new() as ChaserEnemy
	plain.setup(4.0, "brute", false, false)
	_check(plain.boss_rank == 0, "a non-boss carries no rank")
	_check(plain.max_health < previous_health * 0.2, "and none of the boss scaling")
	plain.free()


## Four encounters that pose four different questions. Checked by where the
## enemies actually appear, because "spawns twelve chargers" and "spawns twelve
## chargers in a line from one bearing" are the same code path until they are not.
func _test_encounters_have_distinct_shapes(main: Node) -> void:
	var director: WaveDirector = main.wave_director
	var centre := Vector2(400.0, -250.0)

	var tide: Array[ChaserEnemy] = []
	director._run_encounter("swarm_tide", 6.0, centre, 0, tide)
	_check(tide.size() >= 14, "a tide arrives as a crowd (%d)" % tide.size())
	var all_swarm := true
	for enemy in tide:
		all_swarm = all_swarm and enemy.archetype == "swarm"
	_check(all_swarm, "and all of it is the cheap kind worth farming")

	var siege: Array[ChaserEnemy] = []
	director._run_encounter("ring_siege", 6.0, centre, 0, siege)
	_check(siege.size() >= 12, "a siege arrives in numbers (%d)" % siege.size())
	# One radius, whatever it is, and far enough out that the ring closes off
	# screen and walks in. The number used to be written here as 640, which is
	# inside the visible field — a siege that materialised in view rather than
	# arriving. It is 920 now, in line with every other spawn distance, and
	# pinning the literal made the test fail for the encounter being placed
	# correctly.
	var bearings: Array[float] = []
	var radii_match := true
	var siege_radius := (siege[0].global_position - centre).length()
	for enemy in siege:
		var offset := enemy.global_position - centre
		bearings.append(offset.angle())
		radii_match = radii_match and absf(offset.length() - siege_radius) < 1.0
	_check(radii_match, "a siege forms a circle at one radius (%.0f)" % siege_radius)
	_check(siege_radius > 700.0,
		"and closes it out of sight rather than in the pair's faces (%.0f)" % siege_radius)
	_check(_angular_spread(bearings) > TAU * 0.9, "with no gap to walk out of")

	var stampede: Array[ChaserEnemy] = []
	director._run_encounter("stampede", 6.0, centre, 0, stampede)
	_check(stampede.size() >= 8, "a stampede arrives in numbers (%d)" % stampede.size())
	var charge_bearings: Array[float] = []
	for enemy in stampede:
		charge_bearings.append((enemy.global_position - centre).angle())
	_check(_angular_spread(charge_bearings) < TAU * 0.5,
		"a stampede comes from one bearing (%.2f rad wide)" % _angular_spread(charge_bearings))

	var squad: Array[ChaserEnemy] = []
	director._run_encounter("elite_squad", 6.0, centre, 0, squad)
	var all_elite := squad.size() > 0
	for enemy in squad:
		all_elite = all_elite and enemy.elite
	_check(all_elite, "a squad is entirely elites (%d)" % squad.size())

	# Every id in the rota has to produce something, and every one has a name
	# the announcement can use.
	for encounter_id: String in WaveDirector.ENCOUNTER_ORDER:
		var produced: Array[ChaserEnemy] = []
		director._run_encounter(encounter_id, 6.0, centre, 0, produced)
		_check(not produced.is_empty(), "%s actually spawns something" % encounter_id)
		_check(director.encounter_name(encounter_id) != encounter_id,
			"%s has a name to announce" % encounter_id)

	for pool: Array[ChaserEnemy] in [tide, siege, stampede, squad]:
		for enemy in pool:
			director.release_enemy(enemy)


## An uncapped linear ramp over twenty-five minutes reaches a basic chaser that
## one-shots any build. Health may keep climbing because the pair's output does
## too; a one-shot is the thing no build answers.
func _test_the_late_ramp_is_capped() -> void:
	var endgame := WaveDirector.RUN_LENGTH / WaveDirector.DIFFICULTY_SECONDS
	# Baselined at the end of the opening softener rather than at difficulty
	# zero: the first thirty seconds deliberately hit for 75%, so measuring the
	# ramp against that would report the softener as part of the late curve.
	var baseline := EnemyScript.new() as ChaserEnemy
	baseline.setup(ChaserEnemy.EARLY_GAME_DIFFICULTY, "chaser")
	var late := EnemyScript.new() as ChaserEnemy
	late.setup(endgame, "chaser")

	var damage_ratio := late.contact_damage / baseline.contact_damage
	_check(damage_ratio <= ChaserEnemy.LATE_DAMAGE_CAP + 0.05,
		"contact damage stops climbing at the cap (%.2fx)" % damage_ratio)
	_check(damage_ratio > 1.5, "but it does still climb (%.2fx)" % damage_ratio)
	_check(late.max_health > baseline.max_health * 3.0,
		"health keeps climbing (%.1fx)" % (late.max_health / baseline.max_health))
	_check(late.move_speed < 200.0,
		"a late chaser cannot simply outrun the survivors (%.0f)" % late.move_speed)
	_check(late.xp_value > baseline.xp_value,
		"and a late kill is worth more than an early one (%d vs %d)" % [late.xp_value, baseline.xp_value])
	baseline.free()
	late.free()


## The objective readout is the only place the schedule is visible during play.
func _test_the_readout_tracks_the_schedule(main: Node) -> void:
	var director: WaveDirector = main.wave_director
	director.bosses_spawned = 0
	director.boss_active = false
	main.elapsed = 30.0
	main.EditorialUI.refresh_hud(main)
	var readout: String = main.combat_hud.get_node("ObjectiveReadout").text
	_check(readout.contains("1"), "the readout counts down to the first boss (%s)" % readout)

	director.bosses_spawned = 3
	director.boss_active = true
	main.EditorialUI.refresh_hud(main)
	readout = main.combat_hud.get_node("ObjectiveReadout").text
	_check(readout.contains("3/%d" % WaveDirector.BOSS_COUNT),
		"and says which boss is on the field during a fight (%s)" % readout)

	director.boss_active = false
	director.bosses_spawned = WaveDirector.BOSS_COUNT
	main.EditorialUI.refresh_hud(main)
	readout = main.combat_hud.get_node("ObjectiveReadout").text
	_check(not readout.contains("00:00"), "and does not keep counting down once they are all sent (%s)" % readout)
	director.bosses_spawned = 0


## Width of the smallest arc containing every bearing, which is what separates
## "surrounded" from "coming from over there".
func _angular_spread(bearings: Array[float]) -> float:
	if bearings.size() < 2:
		return 0.0
	var sorted := bearings.duplicate()
	sorted.sort()
	var widest_gap: float = sorted[0] + TAU - sorted[sorted.size() - 1]
	for index in range(1, sorted.size()):
		widest_gap = maxf(widest_gap, float(sorted[index]) - float(sorted[index - 1]))
	return TAU - widest_gap


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
