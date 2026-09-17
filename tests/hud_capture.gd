extends SceneTree

## Windowed capture of the combat HUD: the top bar, the boss bar and both edge
## pointers, in one seeded frame. Not a pass/fail test — a look at the thing.
##
##   godot --path . --script tests/hud_capture.gd
const MainScene := preload("res://scenes/main.tscn")

var main: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	seed(20260917)
	await process_frame
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.elapsed = 452.0
	main.kills = 2899
	main.chain_integrity = 100.0
	main.progression.required_experience = 1 << 30
	# A boss on the field so the boss bar has something to report, hurt enough
	# that the lagging ghost and the enrage state are both visible.
	for frame in 260:
		main._physics_process(1.0 / 60.0)
		await process_frame
	var boss: ChaserEnemy = null
	for enemy in main.enemies:
		if enemy.boss:
			boss = enemy
	if boss == null:
		boss = main.wave_director._acquire_enemy("brute", 40.0, main.players[0].global_position + Vector2(900, 240), true, true)
		boss.boss = true
		boss.boss_rank = 2
		main._register_enemy(boss)
	boss.health = boss.max_health * 0.42
	boss.boss_enraged = true
	main.boss_enemy = boss
	main.boss_bar.reset(main.boss_name(boss.boss_rank), boss.boss_rank, 5, boss.max_health)
	main.boss_bar.visible = true
	main.boss_bar.report(boss.health, boss.max_health, true)
	# Push it off screen so the threat pointer has a bearing to draw.
	boss.global_position = main.players[0].global_position + Vector2(1500.0, 620.0)
	main.field_items.spawn_item(main.players[0].global_position + Vector2(-1350.0, -540.0), "chest")
	# One resonance lit and one core still in hand, so the third column of the
	# shared strip shows all three of its states in the one frame.
	if OS.get_environment("HUD_RESONANCE") != "off":
		main.resonance_system.activate(main.resonance_system.catalog[0])
		main.resonance_system.pending_cores = 1
	for frame in 8:
		main._physics_process(1.0 / 60.0)
		await process_frame
	await process_frame
	var shot := get_root().get_texture().get_image()
	var path := "res://docs/screenshots/hud-capture.png"
	shot.save_png(ProjectSettings.globalize_path(path))
	print("HUD_CAPTURE: wrote %s   boss_bar=%s threat=%s item=%s" % [
		path, main.boss_bar.visible, main.threat_edge_indicator.visible, main.item_edge_indicator.visible])
	quit()
