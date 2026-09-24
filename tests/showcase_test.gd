extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const CardVisual := preload("res://scripts/ui/growth_card_visual.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "SHOWCASE_FAIL", 180.0)
	call_deferred("_run")


## The three moments a run is actually about.
##
## A fusion, a resonance and a chest each used to resolve into one line of text
## in the message banner — identical in weight to "+25% 피해", which is the
## other forty cards. They now stop the run and take the screen, and each one
## is a different shape so a player can tell which happened without reading.
##
## What has to hold: the run really is frozen while one plays, it really does
## end by itself, and it hands back exactly the state it interrupted.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "SHOWCASE_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	await _test_fusion_takes_the_screen(main)
	await _test_the_run_is_frozen(main)
	_test_the_three_modes_are_different_shapes()
	await _test_chest_opens_before_what_it_contained(main)
	_test_chests_come_from_elites_and_bosses(main)

	if failures.is_empty():
		print("SHOWCASE_PASS: three shapes, a real freeze, and the run handed back")
		quit(0)
	else:
		for failure in failures:
			push_error("SHOWCASE_FAIL: " + failure)
		quit(1)


func _test_fusion_takes_the_screen(main: Node) -> void:
	var weapon: Dictionary = main.weapon_loadouts[0][0]
	var evolution := EvolutionCatalog.for_base(String(weapon["weapon_id"]))
	_check(not main.cinematic_active, "nothing is playing to begin with")

	main.WeaponTechs.apply_to_state(weapon, main.WeaponTechs.for_weapon(String(weapon["weapon_id"]))[0])
	weapon["tier"] = EvolutionCatalog.EVOLUTION_TIER
	var required_id := String(weapon["tech_synergy_treasure_id"])
	var material: Dictionary = main.Treasures.build_state(main.Treasures.by_id(required_id))
	material["tier"] = EvolutionCatalog.REQUIRED_TREASURE_TIER
	main.treasure_loadouts[0].append(material)
	main._apply_pending_evolutions(0)
	_check(main.showcase_queue.size() == 1, "an enhancement queues a showcase")
	_check(String(main.showcase_queue[0]["kind"]) == "fusion", "and it is the enhancement one")
	# The weapon it grew from and what it became both travel with it, or the
	# screen has nothing to put on screen.
	var queued: Dictionary = main.showcase_queue[0]
	_check(String(queued["base_weapon_id"]) == "homing", "the base weapon travels with it")
	_check(String(queued["weapon_id"]) == String(evolution["weapon_id"]), "and what it became")

	var resumed := [false]
	main._play_showcase_queue(func() -> void: resumed[0] = true)
	_check(main.cinematic_active, "playing it freezes the run")
	_check(paused, "and pauses the tree")
	_check(_live_showcase(main) != null, "and there is actually a node on screen")

	for frame in 900:
		if not main.cinematic_active:
			break
		await process_frame
	_check(not main.cinematic_active, "the showcase ends on its own")
	_check(resumed[0], "and runs the continuation it was given")
	_check(_live_showcase(main) == null, "and cleans itself up")
	_check(not paused, "and puts the tree back the way it found it")


## The freeze is the point of "몇 초간 멈춘다": if the run kept advancing under
## the veil, the pair would be taking damage during a cutscene.
func _test_the_run_is_frozen(main: Node) -> void:
	main._queue_showcase({
		"kind": "resonance", "weapon_a_id": "starpiercer", "weapon_b_id": "thunder_god",
		"name": "테스트 공명",
	})
	main._play_showcase_queue()
	main.set_physics_process(true)
	var elapsed_before: float = main.elapsed
	var kills_before: int = main.kills
	for frame in 20:
		await physics_frame
	_check(is_equal_approx(main.elapsed, elapsed_before),
		"run time does not advance under a showcase (%.3f)" % (main.elapsed - elapsed_before))
	_check(main.kills == kills_before, "and nothing dies under it either")
	for frame in 900:
		if not main.cinematic_active:
			break
		await process_frame
	# Physics frames explicitly, not whatever the drain loop happened to catch:
	# the claim is that the run resumes, and that is only observable on a tick.
	for frame in 5:
		await physics_frame
	main.set_physics_process(false)
	_check(main.elapsed > elapsed_before, "and the clock starts again afterwards")


## Same animation in three colours would be worse than no animation: the whole
## reason to spend two seconds is that the player learns which of three very
## different things happened.
func _test_the_three_modes_are_different_shapes() -> void:
	var fusion := Showcase.new()
	fusion.play_fusion(null, null, null, "A", Color.WHITE)
	var resonance := Showcase.new()
	resonance.play_resonance(null, null, "B", Color.WHITE)
	var chest := Showcase.new()
	chest.play_chest([{"label": "x", "detail": "피해 1 → 2", "advice": "recommended", "icon": null}])

	_check(fusion.mode != resonance.mode and resonance.mode != chest.mode, "three distinct modes")
	# An enhancement ends as one thing; a resonance ends as two. That is the
	# whole difference between them stated as data rather than as pixels.
	_check(fusion.result_icon != null, "an enhancement produces a single result")
	_check(resonance.result_icon == null, "a resonance does not — both weapons stay")
	# An enhancement starts from one weapon now rather than a weapon and the
	# treasure that unlocked it, because nothing unlocks it any more.
	_check(fusion.sources.size() == 1, "an enhancement starts from the one weapon it grew from")
	_check(resonance.sources.size() == 2, "a resonance starts from two")
	_check(chest.reward_icons.size() == 1, "a chest shows one icon per reward")
	_check(chest.reward_cards.size() == 1
		and chest.reward_cards[0].get_node("Recommendation").text.begins_with("👍"),
		"a rated chest card carries a thumbs-up recommendation")
	_check(chest.reward_cards[0].get_meta("growth_card_visual", false)
		and chest.reward_cards[0] is Label
		and chest.reward_cards[0].size == CardVisual.CARD_SIZE
		and chest.reward_cards[0].has_node("Category")
		and chest.reward_cards[0].has_node("Icon")
		and chest.reward_cards[0].has_node("CardTitle")
		and chest.reward_cards[0].has_node("Recommendation")
		and (chest.reward_cards[0] as Label).text == "피해 1 → 2",
		"a chest reward is the growth-choice card: same node, size, and body text")

	# A chest with more in it takes longer, because each reward is revealed
	# separately; a chest that dumped everything at once would be a list.
	var big := Showcase.new()
	big.play_chest([{"label": "x", "icon": null}, {"label": "y", "icon": null}, {"label": "z", "icon": null}])
	_check(big.duration > chest.duration,
		"a fuller chest takes longer to open (%.2f vs %.2f)" % [big.duration, chest.duration])
	var crowded := Showcase.new()
	crowded.set_anchors_preset(Control.PRESET_TOP_LEFT)
	crowded.size = Vector2(1280, 720)
	var eight_rewards: Array = []
	for index in 8:
		eight_rewards.append({"label": "reward %d" % index, "icon": null})
	crowded.play_chest(eight_rewards)
	crowded.age = crowded._reward_beat(7) + 0.5
	crowded._step_chest()
	_check(crowded.reward_cards.all(func(card: Control) -> bool:
		var drawn := Rect2(card.position + card.size * 0.5 * (Vector2.ONE - card.scale), card.size * card.scale)
		return Rect2(0, 0, 1280, 720).encloses(drawn)),
		"the maximum eight growth cards fit on screen in one row")
	for node: Showcase in [fusion, resonance, chest, big, crowded]:
		node.free()


## A chest can contain a fusion, so the two showcases have to queue in the order
## they happened: the box opens, then whatever came out of it gets its moment.
func _test_chest_opens_before_what_it_contained(main: Node) -> void:
	main.showcase_queue.clear()
	main.showcase_queue.clear()

	main._on_field_item_collected("chest")
	_check(not main.showcase_queue.is_empty() or main.cinematic_active, "a chest opens a showcase")
	var first := _live_showcase(main)
	_check(first != null and first.mode == Showcase.Mode.CHEST,
		"and the box itself is what plays first")
	for frame in 1200:
		if not main.cinematic_active:
			break
		await process_frame
	_check(not main.cinematic_active, "the chest sequence ends")


## The rarest thing in the game used to fall out of ordinary kills at 0.4%,
## which across six thousand kills a run is a slot machine running quietly in
## the background. It comes from fights the pair had to win, or not at all.
func _test_chests_come_from_elites_and_bosses(main: Node) -> void:
	main.field_items.clear_all()
	main.team_luck = 20
	main.team_greed = 2.0
	for index in 3000:
		main._try_drop_field_item(Vector2(index, 5000.0), false)
	var from_ordinary := 0
	for item in main.field_items.active_items:
		if String((item as FieldItem).item_id) == "chest":
			from_ordinary += 1
	_check(from_ordinary == 0,
		"no chest falls out of an ordinary kill, even at maximum luck and greed (%d)" % from_ordinary)

	main.field_items.clear_all()
	for index in 200:
		main._try_drop_field_item(Vector2(index, 5000.0), true)
	var from_elites := 0
	for item in main.field_items.active_items:
		if String((item as FieldItem).item_id) == "chest":
			from_elites += 1
	_check(from_elites > 0, "elites do drop them (%d of 200)" % from_elites)
	print("CHEST_METRICS: ordinary=%d/3000 elite=%d/200" % [from_ordinary, from_elites])
	main.team_luck = 0
	main.team_greed = 0.0
	main.field_items.clear_all()


func _live_showcase(main: Node) -> Showcase:
	for child in main.hud_layer.get_children():
		var node := child as Showcase
		if node != null:
			return node
	return null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
