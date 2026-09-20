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
	seed(20260920)
	main._begin_lobby()
	main.lobby_input_cooldown = 0.0
	main._join_ai_companion()
	check(main.ai_companion and main.character_select_active and not main.character_confirmed[1], "AI considers its character before readying")
	main._step_ai_character(1.5)
	check(main.selected_character_indices[1] == Bot.choose_character(main, 0)
		and main.selected_character_indices[1] != main.selected_character_indices[0],
		"AI automatically chooses a complementary character")
	var varied_choices: Dictionary = {}
	for preference in 24:
		main.ai_character_preference = preference
		varied_choices[Bot.choose_character(main, 0)] = true
	check(varied_choices.size() >= 2, "AI personality produces more than one credible partner")
	check(not (varied_choices.size() == 1 and varied_choices.has(11)), "AI is not locked to Latte")
	for human_index in main.character_catalog.size():
		main.selected_character_indices[0] = human_index
		var choices_for_human: Dictionary = {}
		for preference in 12:
			main.ai_character_preference = preference
			var choice := Bot.choose_character(main, 0)
			check(choice != human_index, "AI never duplicates the human character")
			choices_for_human[choice] = true
		check(choices_for_human.size() >= 2, "every human character has multiple AI partners")
	main.selected_character_indices[0] = 0
	main.ai_character_preference = 0
	main.selected_character_indices[1] = Bot.choose_character(main, 0)
	main._set_character_choice(0, 1, false)
	check(not main.character_confirmed[1], "AI reconsiders a changed human selection")
	main._step_ai_character(1.5)
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
	p.commanded_dash = false
	p.set_command(Vector2.ZERO, true)
	p.set_command(Vector2.RIGHT, false)
	check(p.commanded_dash, "a later movement update cannot erase a queued dash edge")
	p.commanded_dash = false
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
		# Routes are chosen once a weapon reaches the unlock tier.
		var gated: Dictionary = main._build_weapon_state(character)
		gated["tier"] = main.WeaponGrowthScript.TECH_UNLOCK_TIER
		main.weapon_loadouts[0] = [gated]
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
	# 성좌 설계 — the balanced third homing route — is gone, so the echo that
	# fires a weapon from the partner's position is tested on a route that still
	# has it. 중력 폭풍 casts a second well at the other survivor's feet, and the
	# damage still belongs to the cat who cast it.
	var gravity: Dictionary = {}
	for character: Dictionary in main.character_catalog:
		if character["weapon_id"] == "gravity": gravity = main._build_weapon_state(character)
	Techs.apply_to_state(gravity, Techs.by_id("gravity", "maelstrom"))
	check(bool(Techs.BEHAVIORS["gravity"]["maelstrom"].get("echo", false)),
		"중력 폭풍 is still the route that echoes to the partner")
	main.players[0].global_position = Vector2(-600, 0)
	main.players[1].global_position = Vector2(600, 0)
	main.weapon_loadouts[0] = [gravity]
	# queue_free() is deferred, so wells from the roster sweep above are still
	# children of the controller this frame. Only the ones this cast adds count.
	var existing: Dictionary = {}
	for node in main.weapon_controller.get_children():
		existing[node.get_instance_id()] = true
	main.weapon_controller.perform_attack(0, 0, 1.0)
	# The echo is a second delivery, so one cast leaves two wells rather than
	# one. Counting them is what actually distinguishes 중력 폭풍 from 핵붕괴;
	# where each well lands depends on the bodies near each survivor, which is
	# not what this check is about.
	var wells := 0
	for node in main.weapon_controller.get_children():
		# Only the wells this cast made: the controller also parents the frost
		# auras and orbit rings left over from the roster sweep above, and those
		# belong to whoever cast them.
		if existing.has(node.get_instance_id()):
			continue
		if not (node is Node2D) or not node.has_method("configure_gravity") or int(node.kind) != 3:
			continue
		wells += 1
		check(int(node.source_player) == 0, "ally echo keeps caster damage attribution")
	check(wells == 2, "co-op route fires from both players (%d wells from one cast)" % wells)
	main.weapon_controller.clear_transients()
	# Complete an actual shared level without requiring any P2 confirmation.
	main.weapon_loadouts[0] = [main._build_weapon_state(main.character_catalog[0])]
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.level_up_input_delay = 0
	main._handle_level_up_input()
	check(main.selected_upgrade_indices[1] >= 0, "AI automatically locks a growth choice")
	# The active hand stays full size; the AI partner is represented by one
	# readable summary instead of a tiny overlapping hand.
	var picked: int = main.selected_upgrade_indices[1]
	var partner_title := String(main.level_overlay.get_node("PartnerChoice/Captions/Title").text)
	var picked_title := String(main.level_card_labels[1][picked].get_node("CardTitle").text)
	var partner_heading := partner_title.get_slice("\n", 0)
	check(partner_heading.ends_with(picked_title),
		"partner growth summary names its choice (%s vs %s)" % [partner_title, picked_title])
	check(main.level_card_labels[0][0].visible,
		"my active growth hand stays visible while the AI summary is shown")
	check(not main.level_card_labels[1][picked].visible,
		"the partner's full card does not overlap the active hand")
	main._select_upgrade(1, 0)
	check(not main.level_up_active or main.cinematic_active, "AI growth cannot block the run")
	# Local two-player focus handoff and reset back to a human P2.
	main.ai_companion = false
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main._select_upgrade(1, 0)
	check(main.focused_growth_slot() == 1
		and main.level_card_labels[1][0].visible and not main.level_card_labels[0][0].visible,
		"local focus passes to P2")
	main._cancel_growth_choice(0)
	check(main.focused_growth_slot() == 0
		and main.level_card_labels[0][0].visible and not main.level_card_labels[1][0].visible,
		"local P1 can revise before P2 confirms")
	# A multi-option resonance vote used to wait forever for local P2 input even
	# in solo mode. Feed two real enhanced weapons and verify that the companion
	# locks its ranked preference as soon as the core opens.
	main.level_up_active = false
	main.level_overlay.visible = false
	main.ai_companion = true
	var evolutions := EvolutionCatalog.all_fusions()
	main.weapon_loadouts[0] = [{
		"evolved": true, "tier": EvolutionCatalog.WEAPON_MAX_TIER,
		"tags": EvolutionCatalog.tags_of(evolutions[0]),
		"weapon_name": evolutions[0]["weapon_name"], "weapon_id": evolutions[0]["weapon_id"],
	}]
	main.weapon_loadouts[1] = [{
		"evolved": true, "tier": EvolutionCatalog.WEAPON_MAX_TIER,
		"tags": EvolutionCatalog.tags_of(evolutions[1]),
		"weapon_name": evolutions[1]["weapon_name"], "weapon_id": evolutions[1]["weapon_id"],
	}]
	main.resonance_system.grant_core()
	main._open_resonance_core_choice()
	check(main.resonance_candidates.size() > 1 and main.resonance_vote_active
		and main.resonance_votes[1] == 0,
		"AI companion automatically locks a ranked resonance vote")
	main.resonance_vote_active = false
	main.resonance_overlay.visible = false
	paused = false
	main._begin_lobby()
	check(not main.ai_companion, "lobby reset releases AI mode")
	main._start_selected_run()
	check(main.players[1].input_source == ChainPlayer.InputSource.LOCAL, "human mode restores P2 input")
	if failures.is_empty(): print("COOP_REWORK_PASS: AI movement/rescue/growth/resonance, dash latch, local focus and route ownership")
	for failure in failures: push_error("COOP_REWORK_FAIL: " + failure)
	paused = false
	await create_timer(0.8).timeout
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
