extends SceneTree

## Every growth card, at every width the hand deals, keeps each phrase of its
## body on one line and the whole body inside the card.
##
## The body is a block of short phrases (a stat row, the effect, the tags, the
## small print), and it reads as one only while none of them wraps. The dealt
## hand in cat_theme_test checks the three cards a seed happens to give; this
## paints all of them: every treasure, every new weapon, and every axis and route
## of the weapons one survivor can carry, at 224, 208 and 182 wide.

const MainScene := preload("res://scenes/main.tscn")
const CardVisual := preload("res://scripts/ui/growth_card_visual.gd")
const NeonGrowthUI := preload("res://scripts/ui/neon_growth_ui.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	var options: Array = []
	for treasure in main.Treasures.all_treasures():
		options.append({"id": "unlock_treasure", "treasure": treasure, "title": "새 보물: " + String(treasure["name"])})
	for character in main.character_catalog:
		options.append({"id": "unlock_weapon", "character": character, "title": "신규 무기: " + String(character["weapon_name"])})
	# Every weapon owned, then every axis and route on each.
	for character in main.character_catalog:
		if main.weapon_loadouts[0].size() >= 4:
			break
		main._apply_upgrade(0, {"id": "unlock_weapon", "character": character})
	for weapon_slot in main.weapon_loadouts[0].size():
		var state: Dictionary = main.weapon_loadouts[0][weapon_slot]
		for id in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
			options.append({"id": id, "weapon_slot": weapon_slot, "title": "x"})
		for tech in main.WeaponTechs.for_weapon(String(state["weapon_id"])):
			options.append({"id": "choose_tech", "weapon_slot": weapon_slot, "tech": tech, "title": String(tech["name"])})
	var card := CardVisual.create_card()
	root.add_child(card)
	var wraps := 0
	var worst := 0
	for size in [Vector2(224, 348), Vector2(208, 348), Vector2(182, 322)]:
		for option in options:
			var model: Dictionary = NeonGrowthUI.card_model(main, 0, option)
			card.size = size
			CardVisual.paint(card, model, CardVisual.CYAN, false, size.x, size.y)
			await process_frame
			var body: RichTextLabel = card.get_node("Body")
			var phrases := body.get_parsed_text().count("\n") + 1
			var over := body.get_content_height() > body.size.y + 1.0
			if body.get_line_count() != phrases or over:
				wraps += 1
				print("%s %s: %d lines / %d phrases%s  | %s" % [size, option["id"], body.get_line_count(), phrases,
					" OVERFLOW" if over else "", body.get_parsed_text().replace("\n", " / ")])
			worst = maxi(worst, body.get_line_count())
	print("%d cards, %d wrapped or overflowed, tallest %d lines" % [options.size() * 3, wraps, worst])
	print("CARD_WRAP_PASS" if wraps == 0 else "CARD_WRAP_FAIL")
	quit(0 if wraps == 0 else 1)
