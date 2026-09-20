extends SceneTree

const EnemyScript := preload("res://scripts/entities/enemy.gd")
const WaveDirectorScript := preload("res://scripts/systems/wave_director.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "ENCOUNTER_FAIL", 45.0)
	call_deferred("_run")


## What the field throws at the pair, and how much warning it gives them.
## Two things are being pinned here: that the roster has both a farming wave and
## a wall in it rather than one undifferentiated stream, and that the boss's
## circle attack is something you can actually get out of.
func _run() -> void:
	_test_swarm_is_farmable()
	_test_bulwark_is_a_wall()
	_test_swarms_arrive_as_packs()
	_test_archetype_unlock_order()
	_test_wave_openers_are_one_colony()
	_test_boss_cordon_is_a_durable_ring()
	_test_boss_telegraph_is_dodgeable()
	_test_road_to_fusion_is_long()

	if failures.is_empty():
		print("ENCOUNTER_PASS: staged roster, colony waves, durable boss cordon, dodgeable slam")
		quit(0)
	else:
		for failure in failures:
			push_error("ENCOUNTER_FAIL: " + failure)
		quit(1)


func _stats(archetype: String, difficulty := 2.0) -> Dictionary:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(difficulty, archetype)
	var stats := {
		"health": enemy.max_health,
		"damage": enemy.contact_damage,
		"speed": enemy.move_speed,
		"xp": enemy.xp_value,
		"radius": enemy.radius,
	}
	enemy.free()
	return stats


func _test_swarm_is_farmable() -> void:
	var swarm := _stats("swarm")
	var chaser := _stats("chaser")
	# The whole point is that one of them is nothing. If a swarm member takes as
	# long to kill as a chaser then a pack of ten is a disaster, not a payday.
	_check(float(swarm["health"]) < float(chaser["health"]) * 0.5,
		"a swarm member dies far faster than a chaser (%.0f vs %.0f)" % [swarm["health"], chaser["health"]])
	_check(float(swarm["damage"]) < float(chaser["damage"]),
		"and hits softer (%.1f vs %.1f)" % [swarm["damage"], chaser["damage"]])
	_check(float(swarm["speed"]) > float(chaser["speed"]),
		"but arrives faster, so the pack actually reaches you (%.0f vs %.0f)" % [swarm["speed"], chaser["speed"]])

	# XP per point of health is what makes it farming rather than chores.
	var swarm_rate := float(swarm["xp"]) / float(swarm["health"])
	var chaser_rate := float(chaser["xp"]) / float(chaser["health"])
	_check(swarm_rate > chaser_rate,
		"a swarm pays better per point of health than a chaser (%.3f vs %.3f)" % [swarm_rate, chaser_rate])


func _test_bulwark_is_a_wall() -> void:
	var bulwark := _stats("bulwark")
	var chaser := _stats("chaser")
	_check(float(bulwark["health"]) > float(chaser["health"]) * 3.0,
		"a bulwark takes real commitment to kill (%.0f vs %.0f)" % [bulwark["health"], chaser["health"]])
	_check(float(bulwark["speed"]) < float(chaser["speed"]),
		"and is slow enough to be walked away from (%.0f vs %.0f)" % [bulwark["speed"], chaser["speed"]])
	_check(int(bulwark["xp"]) > int(chaser["xp"]) * 3,
		"and pays for the commitment (%d vs %d)" % [bulwark["xp"], chaser["xp"]])
	_check(float(bulwark["radius"]) > float(chaser["radius"]),
		"and is visibly the bigger thing on screen")


func _test_swarms_arrive_as_packs() -> void:
	var director := WaveDirectorScript.new() as WaveDirector
	root.add_child(director)
	director.swarm_timer = 0.0
	director.spawn_timer = 999.0
	director.elite_timer = 999.0
	var spawned := director.step(1.0 / 60.0, WaveDirector.SWARM_UNLOCK_TIME + 1.0, Vector2.ZERO, 0)
	var swarm_count := 0
	for enemy in spawned:
		if (enemy as ChaserEnemy).archetype == "swarm":
			swarm_count += 1
	_check(swarm_count >= 5, "a swarm event spawns a pack rather than one enemy (%d)" % swarm_count)

	# And it must not fire every tick, or the field is nothing but swarm.
	var immediate := director.step(1.0 / 60.0, WaveDirector.SWARM_UNLOCK_TIME + 1.1, Vector2.ZERO, 0)
	var immediate_swarm := 0
	for enemy in immediate:
		if (enemy as ChaserEnemy).archetype == "swarm":
			immediate_swarm += 1
	_check(immediate_swarm == 0, "packs are on a cooldown, not per-tick (%d)" % immediate_swarm)

	# Before the unlock time nothing should arrive at all.
	director.swarm_timer = 0.0
	var early := director.step(1.0 / 60.0, WaveDirector.SWARM_UNLOCK_TIME - 5.0, Vector2.ZERO, 0)
	var early_swarm := 0
	for enemy in early:
		if (enemy as ChaserEnemy).archetype == "swarm":
			early_swarm += 1
	_check(early_swarm == 0, "swarms do not appear before their unlock time (%d)" % early_swarm)
	director.free()


func _test_archetype_unlock_order() -> void:
	var director := WaveDirectorScript.new() as WaveDirector
	root.add_child(director)
	# New behaviours enter one at a time rather than all appearing in the first
	# minute. Sample just before every gate so randomness cannot hide a leak.
	var opening: Dictionary = {}
	for roll in 400:
		opening[director._pick_archetype(WaveDirector.CHARGER_UNLOCK_TIME - 0.1)] = true
	_check(opening.size() == 1 and opening.has("chaser"), "the opening is chasers only (%s)" % str(opening.keys()))

	var second_stage: Dictionary = {}
	for roll in 2000:
		second_stage[director._pick_archetype(WaveDirector.SHOOTER_UNLOCK_TIME + 1.0)] = true
	_check(not second_stage.has("chain_hunter") and not second_stage.has("bulwark"),
		"later specialists stay locked during the charger/shooter stage (%s)" % str(second_stage.keys()))

	var late: Dictionary = {}
	for roll in 3000:
		late[director._pick_archetype(WaveDirector.BULWARK_UNLOCK_TIME + 1.0)] = true
	for expected in ["chaser", "charger", "shooter", "chain_hunter", "bulwark"]:
		_check(late.has(expected), "%s appears in the late mix" % expected)
	_check(not late.has("rat_runner"), "exotic enemies wait until after the first boss window")
	director.free()


func _test_wave_openers_are_one_colony() -> void:
	var director := WaveDirectorScript.new() as WaveDirector
	root.add_child(director)
	director.wave_index = 5
	director.wave_elapsed = WaveDirector.WAVE_DURATION
	director.spawn_timer = 999.0
	director.elite_timer = 999.0
	director.swarm_timer = 999.0
	director.encounter_timer = 999.0
	var spawned := director.step(1.0 / 60.0, 240.0, Vector2.ZERO, 0)
	var colony: Dictionary = {}
	for enemy: ChaserEnemy in spawned:
		if not enemy.scenery:
			colony[enemy.archetype] = true
	_check(colony.size() == 1 and spawned.size() >= 4,
		"a wave opener arrives as one readable species colony (%s)" % str(colony.keys()))
	director.free()


func _test_boss_cordon_is_a_durable_ring() -> void:
	var director := WaveDirectorScript.new() as WaveDirector
	root.add_child(director)
	director.bosses_spawned = 1
	var spawned: Array[ChaserEnemy] = []
	director._run_encounter("boss_cordon", 5.0, Vector2.ZERO, 0, spawned)
	_check(spawned.size() == WaveDirector.BOSS_CORDON_COUNT,
		"a boss cordon closes every bearing (%d bodies)" % spawned.size())
	var baseline := _stats("bulwark", 5.0)
	for enemy in spawned:
		_check(enemy.archetype == "bulwark" and enemy.immovable,
			"every cordon body is a hard-to-displace bulwark")
		_check(enemy.max_health > float(baseline["health"]) * 1.4,
			"cordon bulwarks have boss-fight health (%.0f)" % enemy.max_health)
		_check(absf(enemy.position.length() - WaveDirector.BOSS_CORDON_RADIUS) < 40.0,
			"cordon body is placed on the surrounding ring")
	director.free()


## The circle attack was 0.7s of warning against a 95px radius while both
## survivors are tied together. This checks the window is long enough that
## walking out of it is a decision rather than a reflex.
func _test_boss_telegraph_is_dodgeable() -> void:
	var slowest := INF
	for character in CharacterCatalog.all_characters():
		slowest = minf(slowest, float(character["speed"]))
	var reachable := slowest * ChaserEnemy.BOSS_SLAM_WINDUP
	_check(reachable > ChaserEnemy.BOSS_SLAM_RADIUS * 2.0,
		"the slowest survivor can clear the blast twice over in the windup (%.0fpx vs %.0fpx radius)" % [
			reachable, ChaserEnemy.BOSS_SLAM_RADIUS])

	# Even enraged it has to stay escapable, just tighter.
	var enraged_reach := slowest * ChaserEnemy.BOSS_SLAM_WINDUP_ENRAGED
	_check(enraged_reach > ChaserEnemy.BOSS_SLAM_RADIUS,
		"an enraged slam is still escapable (%.0fpx vs %.0fpx)" % [enraged_reach, ChaserEnemy.BOSS_SLAM_RADIUS])
	_check(ChaserEnemy.BOSS_SLAM_WINDUP_ENRAGED < ChaserEnemy.BOSS_SLAM_WINDUP,
		"enrage still tightens the window")

	# A charge is a line rather than a circle, so it gets less warning — but it
	# must still be warned about.
	_check(ChaserEnemy.BOSS_CHARGE_WINDUP >= 0.7, "the charge telegraph is readable too")


## An enhancement is supposed to be the middle of a run, not the opening. The
## cost is split across a weapon and its route treasure, and the pair also has to
## survive to the first boss before the resonance above it can be turned on.
func _test_road_to_fusion_is_long() -> void:
	var picks := EvolutionCatalog.EVOLUTION_TIER - 1 + EvolutionCatalog.REQUIRED_TREASURE_TIER
	_check(picks >= 10, "an enhancement costs at least ten level-up picks (%d)" % picks)
	_check(EvolutionCatalog.WEAPON_MAX_TIER > EvolutionCatalog.EVOLUTION_TIER,
		"and the weapon still has somewhere to climb afterwards")
	print("ENCOUNTER_METRICS: enhancement costs %d picks (weapon T%d + treasure T%d), ceiling T%d" % [
		picks, EvolutionCatalog.EVOLUTION_TIER, EvolutionCatalog.REQUIRED_TREASURE_TIER, EvolutionCatalog.WEAPON_MAX_TIER
	])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
