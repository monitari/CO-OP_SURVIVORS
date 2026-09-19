extends SceneTree

## Windowed capture of the equipment sockets under each health bar, with a full
## loadout mid-fight so every cooldown ring is somewhere different. Not a
## pass/fail test — a look at the thing, at the window's real pixels.
##
##   godot --path . --script res://tests/equipment_slot_capture.gd
const MainScene := preload("res://scenes/main.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	seed(20260919)
	await process_frame
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.progression.required_experience = 1 << 30
	for slot in 2:
		for character in main.character_catalog:
			if main.weapon_loadouts[slot].size() >= 4:
				break
			main._apply_upgrade(slot, {"id": "unlock_weapon", "character": character})
		for treasure in main.Treasures.all_treasures().slice(0, 4):
			main._apply_upgrade(slot, {"id": "unlock_treasure", "treasure": treasure})
		for tier in 5:
			main._apply_upgrade(slot, {"id": "treasure_upgrade", "treasure_slot": tier % 4})
	for frame in 97:
		main._physics_process(1.0 / 60.0)
		await process_frame
	await process_frame
	var shot := get_root().get_texture().get_image()
	shot.save_png(ProjectSettings.globalize_path("res://.godot_runtime/equipment-slots.png"))
	var scale := shot.get_width() / 1280.0
	var crop := shot.get_region(Rect2i(0, 0, int(640 * scale), int(110 * scale)))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path("res://.godot_runtime/equipment-slots-zoom.png"))
	print("EQUIPMENT_CAPTURE: wrote .godot_runtime/equipment-slots.png")
	quit()
