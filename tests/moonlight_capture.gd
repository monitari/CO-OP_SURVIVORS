extends SceneTree

## Shoots the same four scenes twice, with the moonlight pass on and off, so
## the lighting work can be judged on a comparison rather than on a memory of
## what the roof used to look like.
##
## The last two scenes are the ones that decide it. A night grade that flatters
## an empty rooftop and then loses an enemy inside a late-run crowd, or turns
## four overlapping casts into one white shape, is a night grade that has to be
## thrown away — so the pairs it produces are a quiet scene, the chain at its
## limit, a volley of light-heavy attacks, and a screen buried in bodies.
##
## Windowed, not headless: --headless has no rendering device, so every frame
## it saved would come back empty.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const OUT := "res://.godot_runtime/"


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "MOONLIGHT_CAPTURE_FAIL", 180.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "MOONLIGHT_CAPTURE_FAIL"):
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
	# The run itself never advances during a capture. Left running, the pair
	# walk over the gems the quiet scene puts down, level, and the growth
	# overlay covers the rooftop these shots exist to show. The enemies still
	# separate on their own physics, which is all the crowd shot needs.
	main.set_physics_process(false)

	await _pair(main, "quiet", _build_quiet)
	await _pair(main, "props", _build_props)
	await _pair(main, "chain-limit", _build_chain_limit)
	await _pair(main, "effects", _build_effects)
	await _pair(main, "crowd", _build_crowd)

	print("MOONLIGHT_CAPTURE_DONE: 4 scenes x on/off in %s" % OUT)
	quit()


## Builds the scene once per lighting state rather than building it once and
## flipping the switch, because the effects capture whether the pass is on when
## they spawn — a flare that already exists cannot grow a glow layer.
func _pair(main: Node, name: String, builder: Callable) -> void:
	for lit in [true, false]:
		Moonlight.enabled = lit
		main._apply_moonlight()
		_clear(main)
		await process_frame
		# Reseeded per shot: the crowd, the lightning's jags and the prop hashes
		# are all random, and a pair of images that differ in their contents as
		# well as their lighting compares nothing.
		seed(20260911)
		await builder.call(main)
		await RenderingServer.frame_post_draw
		_save("%smoonlight-%s-%s.png" % [OUT, name, "on" if lit else "off"])
	Moonlight.enabled = true
	main._apply_moonlight()


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


## The roof itself: props, paving, a handful of enemies and the pickups, with
## nothing on fire. This is where the grade and the footing shadows are read.
func _build_quiet(main: Node) -> void:
	var archetypes := ["chaser", "charger", "shooter", "chain_hunter", "brute"]
	for index in archetypes.size():
		var enemy := main.wave_director._acquire_enemy(archetypes[index], 1.0, Vector2.ZERO, index == 4, false) as ChaserEnemy
		enemy.position = Vector2.from_angle(TAU * float(index) / float(archetypes.size())) * 250.0
		main._register_enemy(enemy)
	for grade in 4:
		main.experience_system.spawn_gem(Vector2(-66.0 + grade * 44.0, 120.0), [3, 8, 26, 150][grade], grade)
	main.spatial_grid.rebuild(main.enemies)
	for frame in 24:
		await process_frame


## Somewhere out on the endless roof, where the hashed props actually appear —
## the starting terrace is deliberately kept clear of them, so the crates,
## vents and yarn the rim lighting is for never show up in a shot of the
## opening. This is the one that reads the light direction.
func _build_props(main: Node) -> void:
	var out := Vector2(1780.0, 1180.0)
	main.players[0].position = out + Vector2(-90.0, 40.0)
	main.players[1].position = out + Vector2(90.0, -40.0)
	_look_at(main, out)
	main._update_chain_visual()
	for frame in 4:
		await process_frame


## The pair pulled to the edge of the leash, which is the state the chain's
## light exists to announce.
func _build_chain_limit(main: Node) -> void:
	var reach: float = main.chain_max_length * 0.97
	main.players[0].position = Vector2(-reach * 0.5, 20.0)
	main.players[1].position = Vector2(reach * 0.5, -20.0)
	main._update_chain_visual()
	# Long enough for the streams to be mid-span rather than stacked on a cat.
	for frame in 40:
		await process_frame


## Four light-heavy casts overlapping, which is the case that decides whether
## the additive split was worth doing or whether it just makes a white slab.
func _build_effects(main: Node) -> void:
	var controller: WeaponController = main.weapon_controller
	for index in 4:
		var enemy := main.wave_director._acquire_enemy("chaser", 2.0, Vector2.ZERO, false, false) as ChaserEnemy
		enemy.position = Vector2.from_angle(-0.8 + index * 0.5) * 250.0
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	controller._fire_lightning(main.players[0].global_position, 4, 20.0, 520.0, Color("ffe066"))
	controller._draw_beam(main.players[1].global_position, main.players[1].global_position + Vector2(330.0, -210.0), Color("caffbf"), 40.0)
	controller._draw_chain_pulse(main.players[0].global_position, main.players[1].global_position, 44.0)
	controller._spawn_combat_flare(Vector2(40.0, 150.0), Color("ff8c42"), Color("fff275"), 165.0, 0.5)
	for index in 9:
		var direction := Vector2.from_angle(TAU * float(index) / 9.0)
		var ember: HomingProjectile = controller._acquire_projectile()
		ember.global_position = main.players[0].global_position + direction * 40.0
		ember.setup(direction, null)
		ember.spatial_grid = main.spatial_grid
		ember.homing_enabled = false
		ember.speed = 150.0
		ember.style = "ember"
		ember.projectile_color = Color("ff8c42")
	for frame in 8:
		await process_frame


## Minute twenty. If an enemy or a telegraph is lost in here, the grade is too
## strong whatever it does to the empty roof.
func _build_crowd(main: Node) -> void:
	var deluge: Array[ChaserEnemy] = []
	main.wave_director._run_encounter("deluge", 1200.0 / WaveDirector.DIFFICULTY_SECONDS, Vector2.ZERO, 0, deluge)
	# The director spawns them in a ring off-screen and lets the run walk them
	# in. With the run frozen nothing walks, so they are dropped on top of the
	# pair instead and separation does the rest — which arrives at the same
	# packed screen without letting the clock or the XP advance.
	for enemy in deluge:
		enemy.position = Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 430.0
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	for frame in 460:
		await physics_frame


## The camera only tracks the pair while the run is advancing, and the roof
## only redraws its window when the camera moves, so a frozen capture has to
## move both by hand.
func _look_at(main: Node, at: Vector2) -> void:
	main.world_camera.position = at
	main.arena_floor.follow(at)


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("MOONLIGHT_CAPTURE_FAIL: could not write " + path)
