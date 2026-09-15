extends SceneTree

## Windowed capture, not a headless test: can the player see what hits them?
##
## A crowded late fight — shooters and owls firing at the pair while both cats
## carry the effects that cover the most floor (흑월참 sweeps, gravity wells,
## frost auras, orbit rings) — with the camera travelling across the roof. Every
## few frames the screenshot is sampled at each on-screen enemy shot's true
## position. Run twice, with the threat layering on and off (THREAT_LAYER=off),
## to compare the same seeded scene.
##
##   godot --path . --script tests/threat_visibility_capture.gd
const MainScene := preload("res://scenes/main.tscn")
const Growth := preload("res://scripts/systems/weapon_growth.gd")

var main: Node


func _initialize() -> void:
	call_deferred("_run")


func _screen_offset(world_point: Vector2) -> Vector2:
	var camera: Camera2D = main.world_camera
	return main.rooftop_view.project_offset((world_point - camera.get_screen_center_position()) * camera.zoom)


func _run() -> void:
	var layered := OS.get_environment("THREAT_LAYER") != "off"
	seed(20260916)
	main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 4 # scythe
	main.selected_character_indices[1] = 9 # gravity
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.progression.required_experience = 1 << 30
	main.elapsed = 900.0
	if not layered:
		main.world_stage.z_index = 4
		main.crowd_renderer.threats_on_top = false
	# Heavy floor-covering loadouts on both cats.
	var catalog: Array = main.character_catalog
	for slot in 2:
		for weapon_id in ["scythe", "gravity", "frost", "orbit"]:
			var character: Dictionary = {}
			for entry: Dictionary in catalog:
				if String(entry["weapon_id"]) == weapon_id:
					character = entry
			var state: Dictionary = main._build_weapon_state(character)
			var routes: Array = main.WeaponTechs.for_weapon(weapon_id)
			main.WeaponTechs.apply_to_state(state, routes[0])
			state["tier"] = EvolutionCatalog.EVOLUTION_TIER
			var evolution: Dictionary = main._selected_evolution_for_state(state)
			var fused: Dictionary = EvolutionCatalog.build_state(evolution, state)
			fused["cooldown"] = float(fused["cooldown"]) * 0.45
			if slot < main.weapon_loadouts.size() and main.weapon_loadouts[slot].size() < 6:
				main.weapon_loadouts[slot].append(fused)
				main.attack_timers[slot].append(0.1)
	for player in main.players:
		player.max_health = 1e9
		player.health = 1e9
		player.area = 1.6
	var center: Vector2 = (main.players[0].position + main.players[1].position) * 0.5
	for index in 140:
		var kind: String = ["shooter", "owl", "chaser", "shooter"][index % 4]
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy(kind, 12.0, center, false, false)
		enemy.position = center + Vector2.from_angle(TAU * index / 140.0) * randf_range(220, 620)
		enemy.max_health = 1e9
		enemy.health = 1e9
		main._register_enemy(enemy)
	var checked := 0
	var missing := 0
	for frame in 1200:
		var angle := float(frame) * 0.01
		var drift := Vector2(cos(angle * 0.7), sin(angle)) * 700.0
		main.players[0].position = center + drift + Vector2(-70, 0)
		main.players[1].position = center + drift + Vector2(70, 0)
		if frame % 120 == 0:
			for enemy: ChaserEnemy in main.enemies:
				if is_instance_valid(enemy) and not enemy.boss and randf() < 0.6:
					enemy.position = main.players[0].position + Vector2.from_angle(randf() * TAU) * randf_range(260, 600)
		await process_frame
		if main.get_tree().paused or frame < 60 or frame % 15 != 0:
			continue
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var view_size: Vector2 = main.rooftop_view.view_size
		var to_window: Vector2 = Vector2(root.size) / view_size
		for candidate in main.enemy_shots:
			if not is_instance_valid(candidate):
				continue
			var shot := candidate as EnemyProjectile
			# Skip shots still inside the body that fired them: a shooter's own
			# sprite covers its muzzle by design.
			if shot.lifetime > 3.75:
				continue
			var offset := _screen_offset(shot.global_position)
			if absf(offset.x) > view_size.x * 0.5 - 30.0 or absf(offset.y) > view_size.y * 0.5 - 30.0:
				continue
			var pixel: Vector2 = ((offset + view_size * 0.5) * to_window).round()
			if pixel.y < 170 or pixel.y > root.size.y - 60:
				continue
			checked += 1
			var seen := false
			for dy in range(-6, 7, 2):
				for dx in range(-6, 7, 2):
					var at := Vector2i(clampi(int(pixel.x) + dx, 0, root.size.x - 1), clampi(int(pixel.y) + dy, 0, root.size.y - 1))
					var c := image.get_pixelv(at)
					if c.r > 0.75 and c.g < 0.62 and c.b > 0.3:
						seen = true
			if not seen:
				missing += 1
		if frame == 600:
			image.save_png("res://tests/tmp/threat_visibility_%s.png" % ("layered" if layered else "floor"))
	print("THREAT_VISIBILITY layered=%s shots_checked=%d hidden=%d hidden_share=%.3f" % [
		str(layered), checked, missing, float(missing) / maxf(1.0, checked)])
	quit()
