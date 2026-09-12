extends SceneTree
const MainScene := preload("res://scenes/main.tscn")
const Techs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Bot := preload("res://scripts/systems/companion_controller.gd")
const Enemy := preload("res://scripts/entities/enemy.gd")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, "COOP_REWORK", 45.0)
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/coop_rework_progress.cfg")
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "COOP_REWORK"): return
	main._begin_lobby()
	main.lobby_input_cooldown = 0.0
	main._join_ai_companion()
	check(main.ai_companion and main.character_select_active and main.character_confirmed[1], "AI lobby joins and readies P2")
	check(main.selected_character_indices[1] == Bot.choose_character(main, 0)
		and main.selected_character_indices[1] != main.selected_character_indices[0],
		"AI automatically chooses a complementary character")
	main._set_character_choice(0, 1, false)
	check(main.selected_character_indices[1] == Bot.choose_character(main, 0)
		and main.character_confirmed[1],
		"AI updates its character when P1 changes")
	check(main.character_overlay.get_node("CharacterPrevious1").disabled
		and main.character_overlay.get_node("CharacterConfirm1").disabled,
		"AI character controls are visibly locked")
	main._start_selected_run()
	main.set_physics_process(false)
	main.wave_director.set_physics_process(false)
	main.debug_run_tainted = true
	check(main.players[1].input_source == ChainPlayer.InputSource.AI, "run installs AI input")
	var p: ChainPlayer = main.players[1]
	var partner: ChainPlayer = main.players[0]
	partner.position = Vector2.ZERO
	p.position = Vector2(220, 0)
	main.set_physics_process(true)
	for frame in 35: await physics_frame
	main.set_physics_process(false)
	check(main.elapsed > 0.3 and p.position.x < 215, "live physics advances AI movement without player input")
	partner.position = Vector2.ZERO
	p.position = Vector2(220, 0)
	var command := Bot.command(p, partner, main.spatial_grid, [], 370)
	p.set_command(command["movement"], command["dash"])
	Input.action_press("p2_right")
	p.step_movement(0.1)
	Input.action_release("p2_right")
	check(p.position.x < 220, "AI follows partner and ignores local P2 keys")
	partner.downed = true
	p.position = Vector2(100, 0)
	command = Bot.command(p, partner, main.spatial_grid, [], 370)
	check(command["movement"].x < 0, "AI approaches a downed partner")
	p.position = Vector2(45, 0)
	for tick in 180:
		command = Bot.command(p, partner, main.spatial_grid, [], 370)
		p.set_command(command["movement"], command["dash"])
		p.step_movement(1.0 / 60.0)
		main._update_revives(1.0 / 60.0)
	check(not partner.downed, "AI stays close long enough to revive")
	var enemy := Enemy.new()
	main.add_child(enemy)
	enemy.setup(1.0)
	enemy.health = 1000000.0
	enemy.position = p.position + Vector2(35, 0)
	main.enemies.append(enemy)
	main.spatial_grid.rebuild(main.enemies)
	command = Bot.command(p, partner, main.spatial_grid, [], 370)
	check(command["movement"].x < 0 and command["dash"], "AI evades nearby enemy with dash")
	# Choosing a route must affect emitted attacks, not only catalog metadata.
	for character: Dictionary in main.character_catalog:
		main.weapon_loadouts[0] = [main._build_weapon_state(character)]
		main.p1_choices = main._get_upgrade_choices(1)
		main.level_overlay.visible = true
		main._refresh_level_up_ui()
		await process_frame
		for card: Label in main.level_card_labels[0]:
			if card.visible:
				check(card.get_line_count() <= card.get_visible_line_count(), "route descriptions fit for " + String(character["weapon_id"]))
		for tech: Dictionary in Techs.for_weapon(String(character["weapon_id"])):
			var state: Dictionary = main._build_weapon_state(character)
			Techs.apply_to_state(state, tech)
			check(not Techs.behavior(state).is_empty(), "every route has a delivery effect")
			check(Techs.allows(state, "weapon_power") and Techs.allows(state, "weapon_rate") and Techs.allows(state, "special_a") and Techs.allows(state, "special_b"), "all upgrade axes stay open")
			main.weapon_loadouts[0] = [state]
			main.weapon_controller.perform_attack(0, 0, 1.0)
			main.weapon_controller.clear_sustained_for_player(0)
	var homing: Dictionary = main._build_weapon_state(main.character_catalog[0])
	# Locate by weapon id rather than depending on the roster order.
	for character: Dictionary in main.character_catalog:
		if character["weapon_id"] == "homing": homing = main._build_weapon_state(character)
	Techs.apply_to_state(homing, Techs.by_id("homing", "comet"))
	main.weapon_loadouts[0] = [homing]
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var projectile = main.weapon_controller.active_projectiles.back()
	check(projectile.remaining_hits >= 3, "comet actually emits piercing projectiles")
	Techs.apply_to_state(homing, Techs.by_id("homing", "constellation"))
	var before: int = main.weapon_controller.active_projectiles.size()
	main.weapon_controller.perform_attack(0, 0, 1.0)
	check(main.weapon_controller.active_projectiles.size() >= before + 2, "co-op route fires from both players")
	check(main.weapon_controller.active_projectiles.back().source_player == 0, "ally echo keeps caster damage attribution")
	# Complete an actual shared level without requiring any P2 confirmation.
	main.weapon_loadouts[0] = [main._build_weapon_state(main.character_catalog[0])]
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0
	main._handle_level_up_input()
	check(main.selected_upgrade_indices[1] >= 0, "AI automatically locks a growth choice")
	check(not main.level_card_labels[1][0].visible and main.level_card_labels[0][0].visible, "only human choice cards are visible")
	main._select_upgrade(1, 0)
	check(not main.level_up_active or main.cinematic_active, "AI growth cannot block the run")
	# Local two-player focus handoff and reset back to a human P2.
	main.ai_companion = false
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main._select_upgrade(1, 0)
	check(main.focused_growth_slot() == 1 and main.level_card_labels[1][0].visible and not main.level_card_labels[0][0].visible, "local focus passes to P2")
	main.level_overlay.get_node("ReturnToFirst").pressed.emit()
	check(main.focused_growth_slot() == 0 and main.level_card_labels[0][0].visible, "local P1 can revise before P2 confirms")
	main._begin_lobby()
	check(not main.ai_companion, "lobby reset releases AI mode")
	main._start_selected_run()
	check(main.players[1].input_source == ChainPlayer.InputSource.LOCAL, "human mode restores P2 input")
	if failures.is_empty(): print("COOP_REWORK_PASS: AI movement/rescue/growth, local focus, route execution, caster ownership")
	for failure in failures: push_error("COOP_REWORK_FAIL: " + failure)
	paused = false
	await create_timer(0.8).timeout
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
