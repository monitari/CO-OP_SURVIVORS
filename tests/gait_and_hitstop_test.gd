extends SceneTree
## The crowd's walk cycle and the hit stop behind a heavy blow.
##
## Both are presentation, so both are easy to break without anything failing:
## the gait lives inside a transform the batch renderer was already writing, and
## the stop is a delta scale on a loop that has a dozen other reasons to change.
## What is checked here is what each one is *for* — bodies move while the things
## a player reads off them hold still, and a stop lands on the blows that earned
## it and never on an online run.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "GAIT_FAIL", 90.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	seed(20260923)
	await process_frame
	if not TestHarness.require_loaded(self, main, "GAIT_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await process_frame
	main.set_physics_process(false)

	_test_gait(main)
	_test_hit_stop(main)

	if failures.is_empty():
		print("GAIT_PASS: the crowd walks, its bars hold still, heavy blows stop the roof")
		quit(0)
	else:
		for failure in failures:
			push_error("GAIT_FAIL: " + failure)
		quit(1)


## Places one body and returns the instances its depth band holds, as an array
## of transform origins in band-local space. Instance 0 is always the body; a
## wounded one adds its two health-bar quads after it.
func _band_origins(renderer: CrowdRenderer) -> Array:
	renderer.refresh()
	for band in renderer._bands.size():
		var used: int = renderer._band_used[band]
		if used <= 0:
			continue
		var data: PackedFloat32Array = renderer._band_data[band]
		var origins := []
		for slot in used:
			var i := slot * CrowdRenderer.STRIDE
			origins.append(Vector2(data[i + 3], data[i + 7]))
		return origins
	return []


func _solo(main: Node, archetype: String) -> ChaserEnemy:
	for enemy in main.enemies:
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	var enemy: ChaserEnemy = main.wave_director._acquire_enemy(archetype, 14.0, center, false, false)
	enemy.position = center + Vector2(0.0, -120.0)
	main._register_enemy(enemy)
	main.crowd_renderer.view_rect = Rect2(center - Vector2(640, 360), Vector2(1280, 720))
	return enemy


func _test_gait(main: Node) -> void:
	var renderer: CrowdRenderer = main.crowd_renderer

	# A walker rises and falls without its ground position moving. The gait is
	# drawn, not simulated: anything that reads the enemy's position — contact,
	# targeting, the spatial grid — must see a body standing perfectly still.
	var walker := _solo(main, "chaser")
	var held := walker.position
	var lows := INF
	var highs := -INF
	for step in 16:
		renderer._gait_clock = float(step) * 0.037
		var origins := _band_origins(renderer)
		if origins.is_empty():
			_check(false, "a visible body is batched at all")
			return
		lows = minf(lows, origins[0].y)
		highs = maxf(highs, origins[0].y)
	_check(highs - lows > 0.5, "a walking body rises and falls (%.2fpx of travel)" % (highs - lows))
	_check(walker.position == held, "the gait never moves the body's ground position")

	# Rooftop planters are furniture. They are modelled as enemies and would
	# otherwise have picked up the walk with everything else.
	var _planter := _solo(main, "planter")
	var planted := []
	for step in 8:
		renderer._gait_clock = float(step) * 0.05
		var origins := _band_origins(renderer)
		planted.append(origins[0].y if not origins.is_empty() else INF)
	_check(planted.min() == planted.max(), "scenery holds still while the crowd walks")

	# A wounded body carries its health bar, and the bar is information. The
	# whole point of splitting `body_y` from `local_y` is that it does not bob.
	var wounded := _solo(main, "chaser")
	wounded.health = wounded.max_health * 0.5
	var bar_heights := []
	var body_heights := []
	for step in 12:
		renderer._gait_clock = float(step) * 0.041
		var origins := _band_origins(renderer)
		if origins.size() < 3:
			_check(false, "a wounded body batches its two health-bar quads")
			return
		body_heights.append(origins[0].y)
		bar_heights.append(origins[1].y)
	_check(body_heights.max() - body_heights.min() > 0.5, "a wounded body still walks")
	_check(bar_heights.min() == bar_heights.max(), "the health bar does not bob with its owner")

	# One clock drives every gait, so the phase handed out at setup is the only
	# thing keeping a wave of rats from rising and falling as one object.
	for enemy in main.enemies:
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	var phases := {}
	for index in 24:
		var rat: ChaserEnemy = main.wave_director._acquire_enemy("chaser", 14.0, center, false, false)
		rat.position = center + Vector2(float(index) * 6.0 - 72.0, -120.0)
		main._register_enemy(rat)
		phases[snappedf(rat.anim_phase, 0.01)] = true
	_check(phases.size() > 12, "bodies are handed distinct gait phases (%d of 24 distinct)" % phases.size())


func _test_hit_stop(main: Node) -> void:
	main.hit_stop_remaining = 0.0

	# The stop is owed, not restarted: two blows inside one window add up.
	main._ask_hit_stop(main.HIT_STOP_HEAVY)
	var one: float = main.hit_stop_remaining
	main._ask_hit_stop(main.HIT_STOP_HEAVY)
	_check(one > 0.0, "a heavy blow asks for a stop")
	_check(main.hit_stop_remaining > one, "a second blow extends the stop rather than restarting it")

	# However the events pile up, the roof comes back.
	for _repeat in 40:
		main._ask_hit_stop(main.HIT_STOP_BOSS_DEATH)
	_check(main.hit_stop_remaining <= main.HIT_STOP_CEILING,
		"no pile-up holds the world longer than the ceiling (%.3fs)" % main.hit_stop_remaining)

	# Turning screen shake off is the switch a player reaches for when the
	# feedback is too much, and it takes the stop with it.
	main.hit_stop_remaining = 0.0
	main.screen_shake_enabled = false
	main._ask_hit_stop(main.HIT_STOP_BOSS_DEATH)
	_check(main.hit_stop_remaining == 0.0, "the screen-shake setting also governs the hit stop")
	main.screen_shake_enabled = true

	# A stop slows the shared clock, so the two machines in an online run would
	# no longer agree on what a tick is worth. This harness runs a local game,
	# which is the case the stop is written for.
	main.hit_stop_remaining = 0.0
	_check(not main.online.is_online(), "this harness is the local run the stop is written for")
	main._ask_hit_stop(main.HIT_STOP_HEAVY)
	_check(main.hit_stop_remaining > 0.0, "a local run stops on a heavy blow")

	main.hit_stop_remaining = 0.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
