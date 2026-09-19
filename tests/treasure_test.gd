extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "TREASURE_FAIL", 90.0)
	call_deferred("_run")


## Attributes used to be twelve free-floating cards that all stacked forever, so
## a build was a record of what came up rather than a set of decisions. They are
## now treasures behind a four-slot inventory. These checks pin the part that
## makes that a system rather than a rename: the cap, the fact that only carried
## treasures can be deepened, and that a maxed one leaves the pool.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "TREASURE_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	for slot in 2:
		main.WeaponTechs.apply_to_state(main.weapon_loadouts[slot][0],
			main.WeaponTechs.for_weapon(String(main.weapon_loadouts[slot][0]["weapon_id"]))[0])
	main.set_physics_process(false)
	await process_frame

	_test_starts_empty(main)
	_test_one_slot_per_treasure(main)
	_test_cap(main)
	_test_only_carried_are_offered(main)
	_test_tier_cap(main)
	_test_effects_apply(main)
	_test_shared_treasures(main)
	_test_gimmick_treasures(main)
	_test_catalog_has_icons(main)

	if failures.is_empty():
		print("TREASURE_PASS: one slot per treasure, the cap, deepening only what you carry, effects and shared effects land")
		quit(0)
	else:
		for failure in failures:
			push_error("TREASURE_FAIL: " + failure)
		quit(1)


func _unlock(main: Node, slot: int, treasure_id: String) -> void:
	var treasure: Dictionary = TreasureCatalog.by_id(treasure_id)
	main._apply_upgrade(slot, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})


func _draw_ids(main: Node, player_index: int, draws: int) -> Dictionary:
	var seen: Dictionary = {}
	for draw in draws:
		for option in main._get_upgrade_choices(player_index):
			seen[main._option_key(option)] = true
	return seen


## A treasure takes exactly one of the six slots, no matter how it arrives.
##
## Every path that offers a treasure filters out the ones a survivor already
## carries, so a repeat should be unreachable — but the inventory is six slots
## and the cost of being wrong is that one treasure eats two of them, which is a
## build decision the player silently loses. The guard lives where the slot is
## actually taken, and a repeat deepens the copy they have instead.
func _test_one_slot_per_treasure(main: Node) -> void:
	main.treasure_loadouts[0] = []
	var treasure := TreasureCatalog.by_id("might")
	main._apply_upgrade(0, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	_check(main.treasure_loadouts[0].size() == 1, "the first copy takes a slot")
	var might_after_first: float = main.players[0].might

	main._apply_upgrade(0, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	_check(main.treasure_loadouts[0].size() == 1,
		"a second copy does not take another slot (%d slots)" % main.treasure_loadouts[0].size())
	_check(int(main.treasure_loadouts[0][0]["tier"]) == 2, "it deepens the copy already carried instead")
	_check(main.players[0].might > might_after_first, "and the deepening actually applies its step")

	# A maxed treasure absorbs the repeat without going past its own ceiling.
	main.treasure_loadouts[0][0]["tier"] = TreasureCatalog.MAX_TIER
	main._apply_upgrade(0, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure})
	_check(main.treasure_loadouts[0].size() == 1 and int(main.treasure_loadouts[0][0]["tier"]) == TreasureCatalog.MAX_TIER,
		"a repeat on a maxed treasure changes nothing")
	main.treasure_loadouts[0] = []


func _test_starts_empty(main: Node) -> void:
	_check(main.treasure_loadouts[0].is_empty(), "a run starts with no treasures")
	_check(main.treasure_loadouts[1].is_empty(), "both survivors start empty")
	# Twenty draws with four slots open: an unlock card has to be reachable.
	var seen := _draw_ids(main, 1, 20)
	var offered := false
	for key in seen:
		if String(key).begins_with("unlock_treasure:"):
			offered = true
	_check(offered, "treasure unlocks appear in the pool while slots are open")


func _test_cap(main: Node) -> void:
	for treasure_id in ["might", "armor", "recovery", "area", "haste", "move"]:
		_unlock(main, 0, treasure_id)
	_check(main.treasure_loadouts[0].size() == main.TREASURE_LOADOUT_CAP,
		"unlocks fill the inventory and stop at the cap (%d of %d)"
			% [main.treasure_loadouts[0].size(), main.TREASURE_LOADOUT_CAP])

	# A repeated unlock is a stale card — dealt against a loadout that has since
	# changed, or arriving from a chest that already granted this treasure — and
	# it must never take a second slot. It deepens the copy on hand instead, so
	# the card is not simply thrown away either.
	var carried: Dictionary = main.treasure_loadouts[0][0]
	var repeated_id := String(carried["id"])
	var tier_before := int(carried["tier"])
	var size_before: int = main.treasure_loadouts[0].size()
	_unlock(main, 0, repeated_id)
	_check(main.treasure_loadouts[0].size() == size_before,
		"unlocking a carried treasure again takes no second slot (%d then %d)"
			% [size_before, main.treasure_loadouts[0].size()])
	_check(int(main.treasure_loadouts[0][0]["tier"]) == tier_before + 1,
		"and pays a tier on the copy already held (Lv.%d then Lv.%d)"
			% [tier_before, int(main.treasure_loadouts[0][0]["tier"])])
	var ids: Dictionary = {}
	for treasure in main.treasure_loadouts[0]:
		var treasure_id := String((treasure as Dictionary)["id"])
		_check(not ids.has(treasure_id), "no treasure appears twice in one inventory (%s)" % treasure_id)
		ids[treasure_id] = true

	# Sampled rather than drawn once: a single draw missing an unlock card
	# proves nothing about whether the cap is enforced.
	var seen := _draw_ids(main, 1, 20)
	var leaked := 0
	for key in seen:
		if String(key).begins_with("unlock_treasure:"):
			leaked += 1
	_check(leaked == 0, "no unlock card appears in 20 draws once the inventory is full (saw %d)" % leaked)


func _test_only_carried_are_offered(main: Node) -> void:
	# The carried four are might/armor/recovery/area. Nothing else may show up
	# as an upgrade — that restriction is the entire point of the inventory.
	var carried: Dictionary = {}
	for treasure in main.treasure_loadouts[0]:
		carried[String(treasure["id"])] = true
	var upgrade_targets: Dictionary = {}
	for draw in 25:
		for option in main._get_upgrade_choices(1):
			if String(option["id"]) != "treasure_upgrade":
				continue
			upgrade_targets[main._option_icon_id(0, option)] = true
	_check(not upgrade_targets.is_empty(), "carried treasures are offered for deepening")
	for target in upgrade_targets:
		_check(carried.has(String(target)), "%s is offered only because it is carried" % target)


func _test_tier_cap(main: Node) -> void:
	var treasure: Dictionary = main.treasure_loadouts[0][0]
	var treasure_id := String(treasure["id"])
	# Stepped from wherever this treasure actually stands rather than from an
	# assumed Lv.1: an earlier check in this file deepens it, and counting
	# MAX_TIER-1 steps from there walked it straight past the cap.
	while int(treasure["tier"]) < TreasureCatalog.MAX_TIER:
		main._apply_upgrade(0, {"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": 0})
	_check(int(treasure["tier"]) == TreasureCatalog.MAX_TIER,
		"a treasure reaches its final tier (%d)" % int(treasure["tier"]))

	var still_offered := 0
	for draw in 25:
		for option in main._get_upgrade_choices(1):
			if String(option["id"]) == "treasure_upgrade" and main._option_icon_id(0, option) == treasure_id:
				still_offered += 1
	_check(still_offered == 0, "a maxed treasure leaves the pool (%s seen %d times)" % [treasure_id, still_offered])


func _test_effects_apply(main: Node) -> void:
	var player: ChainPlayer = main.players[1]
	var before := {
		"might": player.might,
		"armor": player.armor,
		"speed": player.move_speed,
		"max_health": player.max_health,
	}
	_unlock(main, 1, "might")
	_check(player.might > float(before["might"]), "taking 격노의 인장 raises might")
	_unlock(main, 1, "armor")
	_check(player.armor > float(before["armor"]), "taking 수호의 갑주 raises armor")
	_unlock(main, 1, "move")
	_check(player.move_speed > float(before["speed"]), "taking 경보의 장화 raises move speed")
	_unlock(main, 1, "vitality")
	_check(player.max_health > float(before["max_health"]), "taking 생명의 결정 raises max health")

	# Deepening has to keep paying, or a treasure is worth one card and no more.
	var might_after_first := player.might
	main._apply_upgrade(1, {"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": 0})
	_check(player.might > might_after_first, "deepening a treasure applies its effect again")


func _test_shared_treasures(main: Node) -> void:
	# The three shared treasures spend a personal slot on a team resource. That
	# trade only exists if they actually reach the team.
	var magnet_before: float = main.team_magnet
	var luck_before: int = main.team_luck
	var lifesteal_before: float = main.team_lifesteal
	main.treasure_loadouts[0] = []
	_unlock(main, 0, "magnet")
	_check(main.team_magnet > magnet_before, "인력의 나침반 raises the shared magnet")
	_check(is_equal_approx(main.experience_system.magnet_radius, main.EXPERIENCE_MAGNET_BASE * main.team_magnet),
		"the shared magnet reaches the experience system")
	_unlock(main, 0, "luck")
	_check(main.team_luck > luck_before, "행운의 주사위 raises shared luck")
	_unlock(main, 0, "lifesteal")
	_check(main.team_lifesteal > lifesteal_before, "진홍 목방울 grants shared lifesteal")


func _test_gimmick_treasures(main: Node) -> void:
	main.treasure_loadouts[0] = []
	main.treasure_loadouts[1] = []
	_unlock(main, 0, "catnip")
	main.players[0].health = main.players[0].max_health * 0.25
	var hurt_health: float = main.players[0].health
	main._finish_level_up()
	_check(main.players[0].health > hurt_health, "별빛 캣닢 heals on level completion")
	_unlock(main, 0, "bounty_bell")
	_check(is_equal_approx(main.team_hunt_bonus, TreasureCatalog.increment("bounty_bell", 1)) and main.team_hunt_bonus > 0.0,
		"사냥꾼 방울 raises elite and boss XP")
	_unlock(main, 0, "twin_charm")
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(20, 0)
	_check(main._tension_damage_multiplier() > 1.0, "쌍둥이 부적 rewards close formation")
	_unlock(main, 0, "dash_claw")
	_check(is_equal_approx(main.team_dash_burst, TreasureCatalog.increment("dash_claw", 1)) and main.team_dash_burst > 0.0,
		"질주 발톱 arms a dash shockwave")
	_unlock(main, 1, "lucky_paw")
	_check(main.players[1].dodge_chance >= TreasureCatalog.increment("lucky_paw", 1) - 0.0001, "행운의 앞발 grants dodge")
	_unlock(main, 1, "nine_lives")
	main.players[1].invulnerability = 0.0
	main.players[1].dodge_chance = 0.0
	main.players[1].health = 1.0
	main.players[1].hurt(9999.0)
	_check(not main.players[1].downed and main.players[1].health > 1.0, "아홉 목숨 리본 prevents a fatal hit")


func _test_catalog_has_icons(main: Node) -> void:
	# Treasure ids double as upgrade-atlas keys. A typo would silently produce a
	# card with no icon, which on an icon-led screen is a blank card.
	for treasure in TreasureCatalog.all_treasures():
		var treasure_id := String(treasure["id"])
		_check(GameIconCatalog.upgrade(treasure_id) != null, "%s has an icon" % treasure_id)
		_check(not String(treasure["name"]).is_empty(), "%s has a name" % treasure_id)
		_check(not String(treasure["per_tier"]).is_empty(), "%s says what a tier gives" % treasure_id)
	_check(TreasureCatalog.all_treasures().size() >= main.TREASURE_LOADOUT_CAP * 2,
		"the catalog is deep enough that four slots are a real choice")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
