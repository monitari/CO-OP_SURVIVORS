extends SceneTree
const Main := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
var downs := 0
var first_down := -1.0
var main: Node

func _initialize() -> void:
	Harness.arm_watchdog(self, "NORMAL_SPEED_FAIL", 240.0)
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 1.0
	main = Main.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "NORMAL_SPEED_FAIL"): return
	var pair := int(OS.get_environment("CHAINBOUND_TEST_PAIR"))
	var run_seed := int(OS.get_environment("CHAINBOUND_TEST_SEED")) if OS.has_environment("CHAINBOUND_TEST_SEED") else 20260905
	seed(run_seed)
	main.selected_character_indices[0] = 0 if pair == 0 else 2
	main.selected_character_indices[1] = 1 if pair == 0 else 3
	main._start_selected_run()
	for p in main.players:
		p.downed_started.connect(func(_p: Node) -> void:
			downs += 1
			if first_down < 0.0: first_down = main.elapsed)
	var peak := 0
	var max_step := 0.0
	# No teleportation, health override or giant XP magnet. Only movement input,
	# dodge, revive approach and the displayed recommendation are automated.
	for frame in 14000:
		if main.game_over or main.elapsed >= 90.0: break
		if main.level_up_active or main.resonance_vote_active:
			_release()
			if main.resonance_vote_active:
				main.resonance_votes = [0, 0]
			elif main.level_up_input_delay <= 0.0:
				for slot in 2:
					if not main.level_up_active: break
					var options: Array = main.p1_choices if slot == 0 else main.p2_choices
					var pick := -1
					var best := -INF
					for index in options.size():
						var score := float(options[index].get("recommendation_score", 0))
						if score > best:
							best = score
							pick = index
					# A neutral hand is valid: don't wait forever for a star badge.
					if pick >= 0: main._select_upgrade(slot + 1, pick)
		else:
			var t: float = main.elapsed
			var center := Vector2(cos(t * 0.32), sin(t * 0.32)) * 280.0
			for slot in 2:
				var p: Node = main.players[slot]
				var other: Node = main.players[1 - slot]
				var goal: Vector2 = center + Vector2(-95 if slot == 0 else 95, 0)
				if other.downed: goal = other.position + Vector2(45 if slot == 0 else -45, 0)
				var direction: Vector2 = p.position.direction_to(goal) if p.position.distance_to(goal) > 10 else Vector2.ZERO
				var prefix := "p%d_" % (slot + 1)
				for axis in ["left", "right", "up", "down"]: Input.action_release(prefix + axis)
				if direction.x < -0.05: Input.action_press(prefix + "left", -direction.x)
				if direction.x > 0.05: Input.action_press(prefix + "right", direction.x)
				if direction.y < -0.05: Input.action_press(prefix + "up", -direction.y)
				if direction.y > 0.05: Input.action_press(prefix + "down", direction.y)
				var enemy: ChaserEnemy = main.spatial_grid.nearest(p.position, 75.0)
				if is_instance_valid(enemy) and p.dash_ready() and not other.downed:
					p.last_input = enemy.position.direction_to(p.position)
					p.try_dash()
		peak = maxi(peak, main.enemies.size())
		max_step = maxf(max_step, main.get_physics_process_delta_time())
		await physics_frame
	_release()
	print("NORMAL_SPEED_METRICS: seed=%d pair=%s+%s survived=%.1f first_down=%.1f downs=%d kills=%d level=%d hp=%.0f/%.0f peak=%d max_delta=%.4f" % [run_seed, main.players[0].character_name, main.players[1].character_name, main.elapsed, first_down, downs, main.kills, main.progression.level, main.players[0].health, main.players[1].health, peak, max_step])
	var ok: bool = main.elapsed >= 90 and (first_down < 0 or first_down >= 30) and main.kills >= 20 and max_step < 0.018
	print("NORMAL_SPEED_PASS" if ok else "NORMAL_SPEED_FAIL")
	quit(0 if ok else 1)

func _release() -> void:
	for slot in 2:
		for axis in ["left", "right", "up", "down"]: Input.action_release("p%d_%s" % [slot + 1, axis])
