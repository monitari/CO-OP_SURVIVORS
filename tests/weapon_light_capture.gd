extends SceneTree

## Shoots the same four scenes twice, with the weapons' cast lights on and off.
##
## Drawing a halo over an attack and having the attack *light the roof* are two
## different techniques, and only the second one can be judged by looking at
## what is around the attack rather than at the attack itself. So these pairs are
## framed on things that are not the effect: paving and crates beside a cast, the
## span of roof under a chain at its limit, the floor a frost ring is standing
## on, and a screen packed with bodies that all still have to be readable.
##
## The crowd pair is the one that decides it. Real light does not stop at the
## effect's own edges, so a budget set too high does not merely look bright — it
## raises the whole frame until an enemy no longer reads against the roof, which
## is the failure the art direction rules out before anything else.
##
## Windowed, not headless: --headless has no rendering device and every frame it
## saved would come back empty.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const OUT := "res://.godot_runtime/"


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WEAPON_LIGHT_CAPTURE_FAIL", 240.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WEAPON_LIGHT_CAPTURE_FAIL"):
		return
	main._begin_lobby()
	main._finish_lobby()
	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	await process_frame
	main.set_physics_process(false)

	await _pair(main, "casts", _build_casts)
	await _pair(main, "chain-limit", _build_chain_limit)
	await _pair(main, "fields", _build_fields)
	await _pair(main, "crowd", _build_crowd)

	print("WEAPON_LIGHT_CAPTURE_DONE: 4 scenes x on/off in %s" % OUT)
	quit()


## Rebuilt per state rather than built once and switched, because a sustained
## light is created with the field that owns it: a frost ring that already
## exists cannot grow one afterwards.
func _pair(main: Node, scene_name: String, builder: Callable) -> void:
	for lit in [true, false]:
		LightField.enabled = lit
		_clear(main)
		await process_frame
		seed(20260916)
		await builder.call(main)
		await RenderingServer.frame_post_draw
		_save("%sweapon-light-%s-%s.png" % [OUT, scene_name, "on" if lit else "off"])
	LightField.enabled = true


func _clear(main: Node) -> void:
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy):
			main._cull_enemy(enemy)
	main.weapon_controller.clear_transients()
	main.bursts.clear_all()
	main.particles.clear_all()
	main.players[0].position = Vector2(-120.0, 0.0)
	main.players[1].position = Vector2(120.0, 0.0)
	_look_at(main, Vector2.ZERO)
	main._update_chain_visual()


## Out where the hashed props stand, so the light has crates, vents and paving
## to fall on rather than empty floor.
func _build_casts(main: Node) -> void:
	var out := Vector2(1780.0, 1180.0)
	main.players[0].position = out + Vector2(-140.0, 40.0)
	main.players[1].position = out + Vector2(140.0, -40.0)
	_look_at(main, out)
	main._update_chain_visual()
	var controller: WeaponController = main.weapon_controller
	for index in 4:
		var enemy := main.wave_director._acquire_enemy("chaser", 2.0, out, false, false) as ChaserEnemy
		enemy.position = out + Vector2.from_angle(-0.8 + index * 0.5) * 250.0
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	controller._fire_lightning(main.players[0].global_position, 4, 20.0, 520.0, Color("ffe066"))
	controller._light_the_cast("lightning", main.players[0].global_position, Color("ffe066"), 120.0)
	controller._draw_beam(main.players[1].global_position, main.players[1].global_position + Vector2(330.0, -210.0), Color("caffbf"), 40.0)
	controller._light_the_cast("lance", main.players[1].global_position, Color("caffbf"), 140.0)
	for frame in 4:
		await process_frame


## The pair at the edge of the leash: overcharge, and the span of roof it lights.
func _build_chain_limit(main: Node) -> void:
	var reach: float = main.chain_max_length * 0.97
	main.players[0].position = Vector2(-reach * 0.5, 20.0)
	main.players[1].position = Vector2(reach * 0.5, -20.0)
	main._update_chain_visual()
	for frame in 40:
		await process_frame


## The three weapons that are conditions rather than events, together: the cold
## ring, the spilt pool and the well that takes light out of the floor.
func _build_fields(main: Node) -> void:
	var controller: WeaponController = main.weapon_controller
	for index in 6:
		var enemy := main.wave_director._acquire_enemy("chaser", 2.0, Vector2.ZERO, false, false) as ChaserEnemy
		enemy.position = Vector2.from_angle(TAU * float(index) / 6.0) * 210.0
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	var frost := WeaponField.new()
	frost.configure_frost(main.players[0], main.spatial_grid, 10.0, 150.0, 0.6, Color("9bf6ff"))
	controller.add_child(frost)
	var milk := MilkPool.new()
	milk.configure(Vector2(220.0, 140.0), main.spatial_grid, 10.0, 110.0, 0.55, Color("f2e2c4"), 4.6)
	controller.add_child(milk)
	var well := WeaponField.new()
	well.configure_gravity(Vector2(-230.0, -120.0), main.spatial_grid, 12.0, 150.0, 60.0, Color("c77dff"))
	controller.add_child(well)
	for frame in 18:
		await physics_frame


## Minute twenty, with casts going off in it. If a body stops reading against
## the roof here, the budget is too high whatever it does to an empty rooftop.
func _build_crowd(main: Node) -> void:
	var deluge: Array[ChaserEnemy] = []
	main.wave_director._run_encounter("deluge", 1200.0 / WaveDirector.DIFFICULTY_SECONDS, Vector2.ZERO, 0, deluge)
	for enemy in deluge:
		enemy.position = Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 430.0
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	for frame in 460:
		await physics_frame
	var controller: WeaponController = main.weapon_controller
	controller._fire_lightning(main.players[0].global_position, 4, 20.0, 520.0, Color("ffe066"))
	controller._light_the_cast("thunder_god", main.players[0].global_position, Color("ffe066"), 150.0)
	controller._light_the_cast("supernova", main.players[1].global_position, Color("ff8c42"), 160.0)
	controller._spawn_combat_flare(Vector2(40.0, 150.0), Color("ff8c42"), Color("fff275"), 165.0, 0.5)
	for frame in 4:
		await process_frame


func _look_at(main: Node, at: Vector2) -> void:
	main.world_camera.position = at
	main.arena_floor.follow(at)


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("WEAPON_LIGHT_CAPTURE_FAIL: could not write " + path)
