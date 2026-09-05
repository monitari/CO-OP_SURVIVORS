extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "VISUAL_CAPTURE_FAIL", 120.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "VISUAL_CAPTURE_FAIL"):
		return
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/lobby.png")

	main._finish_lobby()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/character-select.png")

	main.selected_character_indices[0] = 2
	main.selected_character_indices[1] = 3
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	await process_frame
	main.set_physics_process(false)
	main.players[0].position = Vector2(-120.0, 0.0)
	main.players[1].position = Vector2(120.0, 0.0)
	var archetypes := ["chaser", "charger", "shooter", "chain_hunter", "brute"]
	for index in archetypes.size():
		var enemy := main.wave_director._acquire_enemy(archetypes[index], 1.0, Vector2.ZERO, index == 4, false) as ChaserEnemy
		enemy.position = Vector2.from_angle(TAU * float(index) / float(archetypes.size())) * 265.0
		main._register_enemy(enemy)
	for grade in 4:
		main.experience_system.spawn_gem(Vector2(-66.0 + grade * 44.0, 115.0), [3, 8, 26, 150][grade], grade)
	# One of each field drop so the capture includes the distinct chest silhouette.
	var drop_ids := ["heal", "magnet", "chain_ward", "purge", "chest"]
	for drop_index in drop_ids.size():
		main.field_items.spawn_item(Vector2(-165.0 + drop_index * 110.0, 175.0), drop_ids[drop_index])
	main.spatial_grid.rebuild(main.enemies)
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/gameplay.png")

	# 대범람: the late-run encounter that is supposed to bury the screen. Run
	# through the real director so the shot shows what the schedule produces,
	# and let separation settle so it reads as a crowd rather than a stack.
	var deluge: Array[ChaserEnemy] = []
	main.wave_director._run_encounter("deluge", 1200.0 / WaveDirector.DIFFICULTY_SECONDS, Vector2.ZERO, 0, deluge)
	for enemy in deluge:
		main._register_enemy(enemy)
	for frame in 460:
		await physics_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/deluge.png")
	for enemy in main.enemies.duplicate():
		if is_instance_valid(enemy) and not (enemy as ChaserEnemy).boss:
			main._cull_enemy(enemy)
	await process_frame

	main._on_field_item_collected("chest")
	await _showcase_frame(main, 0.34, "res://.godot_runtime/chest-open.png")
	await _showcase_frame(main, 1.35, "res://.godot_runtime/chest-rewards.png")
	await _drain_showcase(main)

	# The two showcases that close the tech tree, driven straight rather than
	# played out through a whole run.
	var fusion := EvolutionCatalog.for_base(String(main.weapon_loadouts[0][0]["weapon_id"]))
	main._queue_showcase({
		"kind": "fusion",
		"base_weapon_id": String(main.weapon_loadouts[0][0]["weapon_id"]),
		"treasure_id": String(fusion["treasure_id"]),
		"weapon_id": String(fusion["weapon_id"]),
		"name": String(fusion["weapon_name"]),
	})
	main._play_showcase_queue()
	await _showcase_frame(main, 0.42, "res://.godot_runtime/fusion-converge.png")
	await _showcase_frame(main, 1.35, "res://.godot_runtime/fusion-showcase.png")
	await _drain_showcase(main)

	main._queue_showcase({
		"kind": "resonance", "weapon_a_id": "starpiercer", "weapon_b_id": "thunder_god",
		"name": "유도 뇌격",
	})
	main._play_showcase_queue()
	await _showcase_frame(main, 1.55, "res://.godot_runtime/resonance-showcase.png")
	await _drain_showcase(main)

	# Pin the pair in the beneficial tension band so the compact chain labels
	# and action text can be reviewed together rather than only as empty bars.
	var overcharge_half: float = main.chain_max_length * 0.43
	main.players[0].position = Vector2(-overcharge_half, 0.0)
	main.players[1].position = Vector2(overcharge_half, 0.0)
	main._update_chain_visual()
	main._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/chain-status.png")

	main.players[0].health = 1.0
	main.players[0].invulnerability = 0.0
	main.players[0].hurt(999.0)
	main.players[1].position = main.players[0].position + Vector2(75.0, 0.0)
	main._update_revives(1.0)
	main._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/downed-revive.png")
	main.players[0].revive()

	main.progression.add_experience(main.progression.required_experience)
	main._begin_level_up()
	main.level_up_input_delay = 0.0 # capture the interactive state, not the opening beat
	main._refresh_level_up_ui()
	# The modal backdrop is switched on inside _physics_process, so a capture
	# that never ticks physics shows the play field around the panel and the
	# shot reads as a layout bug that is not in the game.
	await _tick_physics(main, 4)
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/level-up.png")

	# A card carrying the fusion mark: P1 one weapon tier and one treasure tier
	# away, so the screen has something to hint about.
	var marked := EvolutionCatalog.for_base(String(main.weapon_loadouts[0][0]["weapon_id"]))
	main.weapon_loadouts[0][0]["tier"] = EvolutionCatalog.WEAPON_MAX_TIER
	main._apply_upgrade(0, {"id": "unlock_treasure", "weapon_slot": -1,
		"treasure": TreasureCatalog.by_id(String(marked["treasure_id"]))})
	while main._treasure_tier(0, String(marked["treasure_id"])) < EvolutionCatalog.REQUIRED_TREASURE_TIER - 1:
		main._apply_upgrade(0, {"id": "treasure_upgrade", "weapon_slot": -1,
			"treasure_slot": main.treasure_loadouts[0].size() - 1})
	main.p1_choices = main._get_upgrade_choices(1)
	main._refresh_level_up_ui()
	await _tick_physics(main, 2)
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/level-up-fusion-mark.png")

	# Give both survivors a few attributes so the build panel has something to
	# show, then capture the hold-to-peek overlay.
	main.players[0].might = 1.3
	main.players[0].area = 1.15
	main.players[0].amount = 2
	main.players[1].haste = 0.8
	main.players[1].armor = 4.0
	main.players[1].recovery = 1.6
	main.team_magnet = 1.5
	main.team_growth = 1.15
	main.team_luck = 2
	main.weapon_loadouts[0].append(main._build_weapon_state(main.character_catalog[4]))
	main.weapon_loadouts[1].append(main._build_weapon_state(main.character_catalog[5]))
	main._refresh_level_up_ui()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/build-inspect.png")
	main.ReviewUI.toggle_details(main)
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/build-details.png")
	main.details_overlay.hide()

	main.level_up_active = false
	main.level_overlay.visible = false
	paused = false

	main.selected_characters[0] = main.character_catalog[0].duplicate(true)
	main.selected_characters[1] = main.character_catalog[1].duplicate(true)
	main.weapon_loadouts[0] = [main._build_weapon_state(main.selected_characters[0])]
	main.weapon_loadouts[1] = [main._build_weapon_state(main.selected_characters[1])]
	# Resonance requires fused weapons now, not tier-3 starters.
	for slot in 2:
		var evolution: Dictionary = main.Evolutions.all_evolutions()[slot]
		main.weapon_loadouts[slot][0].merge(evolution, true)
		main.weapon_loadouts[slot][0]["tier"] = main.Evolutions.WEAPON_MAX_TIER
		main.weapon_loadouts[slot][0]["evolved"] = true
	main.resonance_system.active_resonances.clear()
	main.level_up_active = true
	paused = true
	main._after_personal_upgrade_choices()
	if not main.resonance_overlay.visible:
		push_error("VISUAL_CAPTURE_FAIL: resonance vote did not open")
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/resonance-vote.png")

	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	main.level_up_active = false
	paused = false
	main.weapon_controller.perform_resonance(main.resonance_system.catalog[3], 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/resonance-cast.png")

	for enemy in main.enemies.duplicate():
		main._cull_enemy(enemy)
	main.players[0].position = Vector2(-100, 40)
	main.players[1].position = Vector2(100, 40)
	# The last of the five, so the victory shot at the end of this sequence is a
	# real one: an earlier boss hands the run back rather than ending it.
	var boss := main.wave_director._acquire_enemy(
		"brute", 3.0, Vector2.ZERO, false, true, WaveDirector.BOSS_COUNT) as ChaserEnemy
	boss.position = Vector2(0.0, -170.0)
	main._register_enemy(boss)
	main.wave_director.boss_spawned = true
	main.wave_director.bosses_spawned = WaveDirector.BOSS_COUNT
	main.wave_director.boss_active = true
	for frame in 35:
		main._update_camera(1.0 / 60.0)
	main._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/boss-arrival.png")
	boss.health = boss.max_health * 0.4
	boss.step(main.players, 0.01)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/boss-enraged.png")

	main.players[0].position = Vector2(-80.0, 40.0)
	main.players[1].position = Vector2(80.0, 40.0)
	boss.position = Vector2(0.0, -140.0)
	boss.charge_windup = 0.0
	boss.boss_slam_point = Vector2.ZERO
	boss.boss_slam_windup = 0.7
	boss.queue_redraw()
	main._update_chain_visual()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/boss-chain-slam.png")

	boss.take_damage(999999.0)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/victory-result.png")
	await _capture_enemy_roster(main)
	print("VISUAL_CAPTURE_PASS")
	quit(0)


## Showcases run on wall-clock time and the capture renders far faster than the
## game does, so counting frames lands on a different moment every run. The
## clock is set explicitly instead, which is the only way these shots mean the
## same thing twice.
func _showcase_frame(main: Node, at: float, path: String) -> void:
	var node := _live_showcase(main)
	if node == null:
		return
	node.age = at
	match node.mode:
		Showcase.Mode.FUSION:
			node._step_fusion()
		Showcase.Mode.RESONANCE:
			node._step_resonance()
		Showcase.Mode.CHEST:
			node._step_chest()
	node.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport(path)


## Runs the real per-frame rules (modal backdrop, HUD visibility) before a shot,
## since main ticks on PROCESS_MODE_ALWAYS even while an overlay has paused the
## tree and several screens only look right once it has.
func _tick_physics(main: Node, frames: int) -> void:
	var was := main.is_physics_processing()
	main.set_physics_process(true)
	for frame in frames:
		await physics_frame
	main.set_physics_process(was)


func _live_showcase(main: Node) -> Showcase:
	for child in main.hud_layer.get_children():
		var node := child as Showcase
		if node != null:
			return node
	return null


func _drain_showcase(main: Node) -> void:
	for frame in 900:
		if not main.cinematic_active:
			break
		await process_frame


func _save_viewport(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Failed to save visual capture: " + path)


func _capture_weapon_reworks(main: Node) -> void:
	main.set_physics_process(false)
	main.level_up_active = false
	main.level_overlay.hide()
	paused = false
	main.weapon_controller.clear_transients()
	var previous: Array = [main.weapon_loadouts[0].duplicate(true), main.weapon_loadouts[1].duplicate(true)]
	main.weapon_loadouts[0] = [main._build_weapon_state(main.character_catalog[5]), main._build_weapon_state(main.character_catalog[6]), main._build_weapon_state(main.character_catalog[7]), main._build_weapon_state(main.character_catalog[8])]
	main.weapon_loadouts[1] = [main._build_weapon_state(main.character_catalog[3]), main._build_weapon_state(main.character_catalog[4]), main._build_weapon_state(main.character_catalog[9])]
	# Show that upgraded lances choose independent bearings in the same cast.
	main.weapon_loadouts[0][2]["beams"] = 3
	main.players[0].last_input = Vector2.RIGHT
	main.players[1].last_input = Vector2.LEFT
	main.spatial_grid.rebuild(main.enemies)
	for slot in main.weapon_loadouts[0].size(): main.weapon_controller.perform_attack(0, slot, 1.0)
	for slot in main.weapon_loadouts[1].size(): main.weapon_controller.perform_attack(1, slot, 1.0)
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/weapon-reworks-motion.png")
	for frame in 30: await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/weapon-reworks-sustain.png")
	main.weapon_controller.clear_transients()
	main.weapon_loadouts[0] = previous[0]
	main.weapon_loadouts[1] = previous[1]
	main.set_physics_process(true)


func _capture_enemy_roster(main: Node) -> void:
	# Render all silhouettes together, including types absent from the opening.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var screen := Control.new()
	screen.theme = main.hud_layer.get_node("ThemeHost").theme
	layer.add_child(screen)
	var backdrop := ColorRect.new()
	backdrop.color = Color("172c36")
	backdrop.size = Vector2(1280, 720)
	screen.add_child(backdrop)
	var ui = main.EditorialUI
	ui.label(screen, "옥상의 불청객", Rect2(40, 24, 1100, 44), 30, Color("fff9ea"))
	ui.label(screen, "실루엣 / 기본 상태 · 판정과 행동은 기존 전투 규칙 유지", Rect2(40, 77, 1100, 28), 16, Color("b9cbc8"))
	var kinds := ["chaser", "swarm", "charger", "shooter", "chain_hunter", "bulwark", "brute"]
	var roles := ["간식을 노리는 추적자", "빠르게 몰려드는 무리", "직선 돌진", "원거리 투척", "사슬 중앙 추적", "느리지만 튼튼한 방패", "사슬 강타 · 돌진 · 폭주"]
	for index in kinds.size():
		var at := Vector2(40 + (index % 4) * 306, 124 + (index / 4) * 282)
		var tile: Panel = ui.plate(screen, Rect2(at, Vector2(282, 260)))
		var enemy := ChaserEnemy.new()
		enemy.setup(0, kinds[index], false, index == 6)
		enemy.position = Vector2(141, 96)
		enemy.rotation = -PI * 0.5
		enemy.scale = Vector2.ONE * (0.95 if index == 6 else 1.9)
		tile.add_child(enemy)
		ui.label(tile, enemy.EnemyArt.NAMES[kinds[index]], Rect2(20, 176, 242, 30), 20)
		ui.label(tile, roles[index], Rect2(20, 215, 242, 24), 14, Color("66706c"))
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/enemy-roster.png")
	layer.queue_free()
