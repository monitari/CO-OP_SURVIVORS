extends SceneTree
const Scene := preload("res://scenes/main.tscn")
const Bot := preload("res://scripts/systems/companion_controller.gd")
const Harness := preload("res://tests/test_harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("CHAINBOUND_PROGRESSION_PATH", "res://.godot_runtime/growth-rework.cfg")
	Harness.arm_watchdog(self, "GROWTH_REWORK", 55.0)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func shot(label: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot_runtime/rework-" + label + ".png")

func run() -> void:
	var main := Scene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "GROWTH_REWORK"): return
	var meta: MetaProgression = main.meta_progression
	meta.ranks.clear()
	meta.points = 10000
	meta.mark_discovered("test-discovery")
	for entry in MetaProgression.UPGRADES:
		check(meta.purchase(entry.id), "purchase " + entry.id)
	var spent := 10000 - meta.points
	check(meta.refund_value() == spent, "refund equals all actual costs")
	check(meta.reset_upgrades() and meta.points == 10000, "full refund")
	check(meta.is_discovered("test-discovery"), "reset retains discoveries")
	var loaded := MetaProgression.new()
	loaded.save_path = meta.save_path
	loaded.load_progress()
	check(loaded.points == 10000 and loaded.rank("armor") == 0, "reset persists")
	var failing := MetaProgression.new()
	failing.save_path = "res://.godot_runtime/missing-directory/reset.cfg"
	failing.ranks["might"] = 2
	failing.points = 7
	check(not failing.reset_upgrades() and failing.rank("might") == 2 and failing.points == 7, "failed reset rolls back")
	main.title_mode = "meta"
	main._refresh_title_ui()
	await shot("meta")
	main._activate_title_item(6)
	check(main.meta_page == 1, "second growth page")
	main._activate_title_item(0)
	check(meta.rank("armor") == 1, "second page purchase")
	main._activate_title_item(7)
	main._activate_title_item(0)
	check(meta.rank("armor") == 1, "reset cancel preserves rank")
	main._activate_title_item(7)
	main._activate_title_item(1)
	check(meta.rank("armor") == 0, "confirmed reset")
	main.title_mode = "modes"
	main._activate_title_item(0)
	main._start_selected_run()
	main.set_physics_process(false)
	main.team_luck = 0
	var low := 0
	var low_chest := 0
	seed(135)
	for draw in 3000:
		low += main._growth_choice_count()
		low_chest += main._roll_chest_reward_count()
	main.team_luck = 20
	var high := 0
	var high_chest := 0
	var largest := 0
	seed(135)
	for draw in 3000:
		var count: int = main._growth_choice_count()
		high += count
		largest = maxi(largest, count)
		high_chest += main._roll_chest_reward_count()
	check(high > low and largest == 6, "luck grants up to six cards")
	check(high_chest > low_chest, "luck improves chest count")
	var item_system := FieldItemSystem.new()
	var rares := [0, 0]
	for sample in 2:
		seed(821)
		for draw in 5000:
			if item_system.roll_item_id(sample * 20) in ["guard", "frenzy", "time_stop", "purge"]:
				rares[sample] += 1
	check(rares[1] > rares[0], "luck increases special field items")
	item_system.free()
	var hand: Array = [{"id": "weapon_power", "weapon_slot": 0}, {"id": "weapon_rate", "weapon_slot": 0}, {"id": "special_a", "weapon_slot": 0}]
	var counts := [0, 0, 0]
	for draw in 2000:
		counts[Bot.choose(main, 0, hand)] += 1
	check(counts.all(func(value: int) -> bool: return value > 0), "AI sometimes chooses lower ranked options")
	print("LUCK_COUNTS ", low, " -> ", high, "; CHEST ", low_chest, " -> ", high_chest, "; AI ", counts)
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	main.p1_choices.clear()
	for index in 6:
		main.p1_choices.append({"id": "weapon_power", "weapon_slot": 0, "title": "무기 성장", "description": "무기 피해 증가"})
	main._annotate_recommendations(0, main.p1_choices)
	main._refresh_level_up_ui()
	await shot("growth")
	check(main.level_card_labels[0][5].visible, "sixth card visible")
	check(main.level_card_labels[0][0].position.x > 0 and main.level_card_labels[0][5].position.x < 1120, "six cards fit")
	main.online.session.role = NetworkSession.Role.CLIENT
	main.p2_choices = main.p1_choices.duplicate(true)
	main._refresh_level_up_ui()
	check(main.level_card_labels[1][0].position.x == main.level_card_labels[0][0].position.x or main.level_card_labels[1][0].position.x < 200, "client own cards centered")
	await shot("client-growth")
	main.online.session.role = NetworkSession.Role.OFFLINE
	main.level_overlay.hide()
	main.ReviewUI.toggle_details(main)
	await shot("details")
	check(main.details_overlay.get_node("DetailHeader%d" % main.local_view_slot()).visible
		and not main.details_overlay.get_node("DetailHeader%d" % (1 - main.local_view_slot())).visible
		and main.details_overlay.get_node_or_null("PartnerSummary") == null,
		"details show only this player's own sheet")
	main.details_overlay.hide()
	var showcase := Showcase.new()
	var rewards: Array = []
	for index in 8:
		rewards.append({"label": ("나" if index % 2 == 0 else "동료") + " · 체력 성장", "detail": "최대 체력 120 → 132\n현재 체력 +12", "advice": "recommended", "advice_reason": "생존력 보강"})
	showcase.play_chest(rewards)
	main.level_overlay.get_parent().add_child(showcase)
	showcase.age = showcase.duration - 1.0
	showcase._step_chest()
	check(showcase.reward_cards.size() == 8 and showcase.reward_summary == null, "eight reward cards without redundant summary")
	await shot("chest")
	paused = false
	main.free()
	for failure in failures: push_error(failure)
	print("GROWTH_REWORK_PASS" if failures.is_empty() else "GROWTH_REWORK_FAIL")
	quit(0 if failures.is_empty() else 1)
