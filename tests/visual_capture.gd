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
	main.players[0].position = Vector2(-120.0, 0.0)
	main.players[1].position = Vector2(120.0, 0.0)
	var archetypes := ["chaser", "charger", "shooter", "chain_hunter", "brute"]
	for index in archetypes.size():
		var enemy := main.wave_director._acquire_enemy(archetypes[index], 1.0, Vector2.ZERO, index == 4, false) as ChaserEnemy
		enemy.position = Vector2.from_angle(TAU * float(index) / float(archetypes.size())) * 265.0
		main._register_enemy(enemy)
	main.experience_system.spawn_gem(Vector2(0.0, 115.0), 5)
	# One of each field drop so the capture shows all four icons.
	var drop_ids := ["heal", "magnet", "chain_repair", "purge"]
	for drop_index in drop_ids.size():
		main.field_items.spawn_item(Vector2(-165.0 + drop_index * 110.0, 175.0), drop_ids[drop_index])
	main.spatial_grid.rebuild(main.enemies)
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/gameplay.png")
	main._set_pause(true)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/pause.png")
	main._set_pause(false)

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
	await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport("res://.godot_runtime/level-up.png")

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

	var boss := main.wave_director._acquire_enemy("brute", 3.0, Vector2.ZERO, true, true) as ChaserEnemy
	boss.position = Vector2(0.0, -170.0)
	main._register_enemy(boss)
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


func _save_viewport(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Failed to save visual capture: " + path)


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
