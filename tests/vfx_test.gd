extends SceneTree
## The motion pass: chest cards are thrown and turned over rather than slid into
## place, every cast gives its cat a beat, hits carry their weapon's colour, and
## the extra marks stay inside the budgets that keep a late wave affordable.
##
## `-- --capture` saves real-renderer frames to .godot_runtime/vfx-*.png.

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const ShowcaseScript := preload("res://scripts/effects/showcase.gd")
const ParticleScript := preload("res://scripts/systems/particle_field.gd")
var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "VFX", 120.0)
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/vfx-" + label + ".png")


func run() -> void:
	_check_budgets()
	_check_chest_motion()
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "VFX"):
		return
	main._begin_lobby()
	main._join_ai_companion()
	main._start_selected_run()
	await physics_frame
	main.set_physics_process(false)
	main.modal_dim.visible = false
	main.combat_hud.visible = true
	_check_cast_and_hits(main)
	await _capture_combat(main)
	await _capture_chest(main)
	for failure in failures:
		push_error("VFX: " + failure)
	if failures.is_empty():
		print("VFX_PASS")
	quit(0 if failures.is_empty() else 1)


## Events have their own allowance, so a tick already full of chip-damage sparks
## still draws the explosion; flares are held tighter still.
func _check_budgets() -> void:
	var field := ParticleScript.new() as ParticleField
	for index in 200:
		field.emit_sparks(Vector2.ZERO, Color.WHITE, 5)
	var texture := field.particles.size()
	check(texture <= ParticleField.MAX_EMITTED_PER_STEP, "Hit texture stays inside its allowance (%d)" % texture)
	field.emit_burst(Vector2.ZERO, Color.WHITE, 8)
	check(field.particles.size() == texture + 8, "An event still draws on a tick full of hits")
	for index in 50:
		field.emit_flare(Vector2.ZERO, Color.WHITE)
	var flares := field.particles.filter(func(p): return p["kind"] == "flare").size()
	check(flares == ParticleField.MAX_FLARES_PER_STEP, "Flares are capped per tick (%d)" % flares)
	field.step(1.0 / 60.0)
	field.emit_chips(Vector2.ZERO, Color.GRAY, 4)
	for index in 50:
		field.step(1.0 / 60.0)
	var landed := field.particles.filter(func(p): return p["kind"] == "chip" and float(p["height"]) == 0.0).size()
	check(landed == 4, "Debris thrown up comes down and lies on the roof (%d of 4)" % landed)
	field.free()


## Driven by `age` alone, so every moment of the throw can be checked directly.
func _check_chest_motion() -> void:
	var chest := ShowcaseScript.new() as Showcase
	chest.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chest.size = Vector2(1280, 720)
	chest.play_chest([{"label": "a", "icon": null, "slot": 0}, {"label": "b", "icon": null, "slot": 1}])
	root.add_child(chest)
	chest.set_process(false)
	var card: Control = chest.reward_cards[0]
	var back: Control = card.get_node("CardBack")
	var beat := chest._reward_beat(0)
	chest.age = beat + Showcase.REWARD_FLIGHT * 0.2
	chest._step_chest()
	check(back.visible, "A card leaves the box face down")
	check(not card.get_node("Owner").visible, "Whose it is stays hidden until it turns over")
	var early_y := card.position.y
	chest.age = beat + Showcase.REWARD_FLIGHT * 0.45
	chest._step_chest()
	check(card.position.y < chest._reward_target(0).y - card.size.y * 0.5 - 60.0,
		"It is thrown up over an arc, not slid along a line")
	check(card.scale.x < card.scale.y, "It is turning over at the top of the arc")
	chest.age = beat + Showcase.REWARD_FLIGHT * 0.9
	chest._step_chest()
	check(not back.visible and card.get_node("Owner").visible, "It lands face up")
	chest.age = chest._reward_landed(0) + 0.01
	chest._step_chest()
	var settle := chest.reward_scale()
	check(is_equal_approx(card.scale.x, settle) and is_equal_approx(card.scale.y, settle) and card.rotation == 0.0,
		"It settles square and at its row size")
	check(absf(card.position.y + card.size.y * 0.5 - chest._reward_target(0).y) <= 3.5, "It settles in its place in the row")
	chest.age = Showcase.CHEST_BURST_AT + 0.05
	chest._step_bits(0.05)
	check(chest.bits.size() >= 30, "The burst throws coins and confetti (%d)" % chest.bits.size())
	var coin: Dictionary = chest.bits[0]
	var first := (coin["velocity"] as Vector2).y
	chest._step_bits(0.05)
	check((coin["velocity"] as Vector2).y > first, "Everything thrown falls")
	check(early_y != card.position.y, "Still moving through the throw")
	chest.free()


func _check_cast_and_hits(main) -> void:
	var cat: ChainPlayer = main.players[0]
	cat.cast_kick = 0.0
	main._on_player_attack_visual(0, "homing", cat.global_position, Color("43d9ff"), 60.0)
	check(is_equal_approx(cat.cast_kick, 0.6), "A cast gives its cat a beat")
	check(main.weapon_tints.get("homing") == Color("43d9ff"), "A weapon's colour is remembered for its hits")
	cat.cast_kick = 0.0
	main.particles.step(1.0 / 60.0)
	main._on_player_attack_visual(0, "supernova", cat.global_position, Color("ff9770"), 60.0)
	check(is_equal_approx(cat.cast_kick, 1.0), "An evolved weapon gives a bigger one")
	check(main.particles.particles.any(func(p): return p["kind"] == "flare"), "And a flare")
	for i in 30:
		cat.step_movement(1.0 / 60.0)
	check(cat.cast_kick == 0.0, "The beat passes")


func _capture_combat(main) -> void:
	main.players[0].position = Vector2(-120, 20)
	main.players[1].position = Vector2(120, 20)
	main._update_chain_visual()
	for i in 30:
		main._update_camera(1.0 / 60.0)
	var wc = main.weapon_controller
	main.particles.step(1.0 / 60.0)
	main.cast_flourish(0, "supernova", main.players[0].global_position, Color("ff9770"))
	main.cast_flourish(1, "lightning", main.players[1].global_position, Color("c77dff"))
	wc._draw_lightning(Vector2(120, 20), Vector2(330, -120), Color("c77dff"), 5.0)
	wc._on_mine_detonated(Vector2(-300, 160), 1.0, 90.0, Color("ffd166"), 0, "mine")
	wc._draw_beam(Vector2(-120, 20), Vector2(-420, -160), Color("9bf6ff"), 18.0)
	for index in 6:
		var at := Vector2(-60 + index * 40, 190 + (index % 2) * 20)
		main.bursts.spawn(at, Color("b9a7c9"), 1.0)
		main.particles.emit_chips(at, Color("8d8196"), 2, 120.0)
	await process_frame
	await process_frame
	for i in 4:
		main.particles.step(1.0 / 60.0)
		main.bursts.step(1.0 / 60.0)
	await capture("combat")


func _capture_chest(main) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	var chest := ShowcaseScript.new() as Showcase
	chest.play_chest([{"label": "번개 강화", "detail": "피해 +20%", "icon": null, "slot": 0},
		{"label": "우유 강화", "detail": "범위 +15%", "icon": null, "slot": 1},
		{"label": "털실 시계", "detail": "시간 정지", "icon": null, "slot": 0}])
	main.hud_layer.add_child(chest)
	chest.set_process(false)
	for moment: Array in [["windup", 0.62], ["burst", Showcase.CHEST_BURST_AT + 0.12],
			["flight", chest._reward_beat(0) + Showcase.REWARD_FLIGHT * 0.5],
			["landing", chest._reward_landed(1) + 0.12], ["settled", chest._reward_landed(2) + 0.6]]:
		var target: float = moment[1]
		while chest.age < target:
			var step := minf(1.0 / 60.0, target - chest.age)
			chest.age += step
			chest._step_chest()
			chest._step_bits(step)
		chest.queue_redraw()
		chest.overlay.queue_redraw()
		await capture("chest-" + String(moment[0]))
	chest.queue_free()
