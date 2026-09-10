extends SceneTree
const Main := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, "CRITIQUE_FAIL", 60)
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	seed(620)
	var main := Main.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "CRITIQUE_FAIL"): return
	main._start_selected_run()
	main.set_physics_process(false)
	var director: WaveDirector = main.wave_director
	for index in 620:
		var enemy := director._acquire_enemy("chaser", 5, Vector2.ZERO, false, false)
		enemy.position = Vector2.from_angle(index * TAU / 620) * 900
		main._register_enemy(enemy)
	for rank in range(1, 6):
		director.boss_active = false
		director.elite_timer = 0
		director.encounter_timer = 0
		director.encounters_run = rank - 1
		var elapsed := rank * 300.0
		var expected := director.encounter_size(elapsed) + 2 + director.PLANTER_MAX_ALIVE
		var spawned := director.step(1.0 / 60, elapsed, Vector2.ZERO, main.enemies.size())
		check(spawned.size() == expected, "full scheduled encounter at cap, rank %d (%d/%d)" % [rank, spawned.size(), expected])
		for enemy in spawned: main._register_enemy(enemy)
		check(main.enemies.size() == 620, "hard cap preserved for rank %d" % rank)
		check(director.bosses_spawned == rank, "boss rank %d is not skipped" % rank)
		check(director.encounters_run == rank, "encounter clock progresses")
		var boss: ChaserEnemy = main.boss_enemy
		main._cull_enemy(boss)
		main.boss_enemy = null
		var filler := director._acquire_enemy("chaser", 5, Vector2.ZERO, false, false)
		main._register_enemy(filler)
	print("CRITIQUE_CAP: all five bosses + complete encounters + elites at 620")
	var player: ChainPlayer = main.players[0]
	var close: Array[ChaserEnemy] = []
	for index in 6:
		var enemy: ChaserEnemy = main.enemies[index]
		enemy.position = player.position + Vector2.from_angle(index * TAU / 6) * 35
		close.append(enemy)
	main.spatial_grid.rebuild(close)
	main.elapsed = 40
	main._update_contact_pressure()
	check(is_equal_approx(player.contact_pressure, 1), "no opening pack penalty")
	main.elapsed = 240
	main._update_contact_pressure()
	check(is_equal_approx(player.contact_pressure, 1.6), "six enemies increase contact threat by 60 percent")
	player.invulnerability = 2
	check(not player.hurt(50 * player.contact_pressure), "guard immunity still wins over pressure")
	var runner := ChaserEnemy.new()
	main.add_child(runner)
	runner.setup(4, "rat_runner")
	runner.position = player.position + Vector2(400, 0)
	runner.behavior_timer = 0
	runner.step(main.players, 0.016)
	check(runner.charge_windup > 0.7 and runner.charge_timer == 0, "runner telegraphs before sprint")
	runner.charge_windup = 0.001
	runner.step(main.players, 0.016)
	var before := runner.position
	runner.step(main.players, 0.1)
	check(runner.position.distance_to(before) >= 33, "warned sprint overtakes unboosted cats")
	var recommended := 0
	var discouraged := 0
	main.WeaponTechs.apply_to_state(main.weapon_loadouts[0][0], main.WeaponTechs.for_weapon(String(main.weapon_loadouts[0][0]["weapon_id"]))[0])
	for iteration in 120:
		var choices: Array = main._get_upgrade_choices(1)
		for option in choices:
			recommended += int(option.get("recommended", false))
			discouraged += int(option.get("discouraged", false))
			check(not (option.get("recommended", false) and option.get("discouraged", false)), "advice bands never overlap")
	print("CRITIQUE_ADVICE: recommended=%d discouraged=%d / 360 cards" % [recommended, discouraged])
	check(discouraged > 0, "discouraged band actually occurs on real choices")
	check(main.boss_label.position.y + main.boss_label.size.y <= 160, "boss HUD stays above the protected play field")
	for id in ["echo", "latte"]:
		var art: Texture2D = GameIconCatalog.survivor(id)
		check(art.get_image().get_pixel(0, 0).a < 0.01, id + " has true transparent padding")
	main.guard_remaining = 3
	main.frenzy_remaining = 3
	main.time_stop_remaining = 3
	main.item_aura.step(0.016)
	await process_frame
	main.guard_remaining = 0
	main.frenzy_remaining = 0
	main.time_stop_remaining = 0
	player.contact_pressure = 1
	main.players[1].contact_pressure = 1
	main.item_aura.step(0.016)
	check(not main.item_aura.was_active, "all item effects clear on expiry")
	var plain_loss := circle_damage("chaser")
	var runner_loss := circle_damage("rat_runner")
	print("CRITIQUE_KITING: 60s fixed circle at speed 288, chaser_damage=%.1f runner_damage=%.1f" % [plain_loss, runner_loss])
	check(runner_loss > plain_loss, "telegraphed runners threaten a fixed circle more than plain chase")
	for failure in failures: push_error("CRITIQUE_FAIL: " + failure)
	print("CRITIQUE_PASS" if failures.is_empty() else "CRITIQUE_FAIL")
	quit(0 if failures.is_empty() else 1)

func circle_damage(kind: String) -> float:
	var arena := Node2D.new()
	root.add_child(arena)
	var players: Array[ChainPlayer] = [ChainPlayer.new(), ChainPlayer.new()]
	for player in players: arena.add_child(player)
	players[0].health = 10000
	players[0].max_health = 10000
	players[0].move_speed = 288
	players[1].downed = true
	var enemies: Array[ChaserEnemy] = []
	seed(7741)
	for index in 6:
		var enemy := ChaserEnemy.new()
		arena.add_child(enemy)
		enemy.setup(8, kind)
		enemy.position = Vector2.from_angle(index * TAU / 6) * 640
		enemies.append(enemy)
	for frame in 3600:
		var angle := frame / 60.0 * 288.0 / 340.0
		players[0].position = Vector2.from_angle(angle) * 340
		players[0].current_input = Vector2.from_angle(angle).orthogonal()
		players[0].invulnerability = maxf(0, players[0].invulnerability - 1.0 / 60)
		for enemy in enemies: enemy.step(players, 1.0 / 60)
	var lost := 10000 - players[0].health
	arena.free()
	return lost
