extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "MULTI_WEAPON_FAIL", 60.0)
	call_deferred("_run")


## Weapons used to be one-per-character; a player can now carry up to
## WEAPON_LOADOUT_CAP, picked up via level-up choices. Verifies the cap is
## actually enforced, that each owned weapon fires on its own independent
## cooldown instead of sharing the single old attack_timers[i] float, and
## that resonance can be reached through a picked-up weapon even when the
## player's own starting weapon shares no tags with the partner at all.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "MULTI_WEAPON_FAIL"):
		return

	main.selected_character_indices[0] = 4 # moro
	main.selected_character_indices[1] = 0 # lyra
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_tag_translations(main)
	await _test_weapon_cap(main)
	await _test_independent_cooldowns(main)
	_test_loadout_resonance(main)

	if failures.is_empty():
		print("MULTI_WEAPON_PASS: cap enforced, independent cooldowns, resonance reaches through a picked-up weapon")
		quit(0)
	else:
		for failure in failures:
			push_error("MULTI_WEAPON_FAIL: " + failure)
		quit(1)



## Unlock cards print a weapon's tags to explain what it can resonate with, so
## an untranslated tag leaks raw English into that card. _tag_name() falls back
## to returning the key itself, which fails silently — this catches a tag added
## to the catalog without a matching translation.
func _test_tag_translations(main: Node) -> void:
	var untranslated: Array[String] = []
	for character in main.character_catalog:
		for tag in (character["tags"] as Array):
			var tag_name := String(main._tag_name(String(tag)))
			if tag_name == String(tag) and not (String(tag) in untranslated):
				untranslated.append(String(tag))
	_check(untranslated.is_empty(), "every catalog tag has a display name: " + ", ".join(untranslated))

func _test_weapon_cap(main: Node) -> void:
	_check(main.weapon_loadouts[0].size() == 1, "a run starts with exactly one weapon")

	# Derived from the cap rather than hard-coded, so raising the cap moves
	# this test with it instead of failing it.
	for i in main.WEAPON_LOADOUT_CAP - 1:
		var candidates: Array = main._pick_unowned_characters(0, 1)
		_check(not candidates.is_empty(), "an unowned character is available to unlock (iteration %d)" % i)
		main._apply_upgrade(0, {"id": "unlock_weapon", "weapon_slot": -1, "character": candidates[0]})

	_check(main.weapon_loadouts[0].size() == main.WEAPON_LOADOUT_CAP, "unlock picks bring a player to the weapon cap (%d of %d)" % [main.weapon_loadouts[0].size(), main.WEAPON_LOADOUT_CAP])
	_check(main.attack_timers[0].size() == main.weapon_loadouts[0].size(), "attack_timers stays 1:1 with weapon_loadouts")

	# Each draw shuffles a ~16-option pool down to 3, so a single draw missing an
	# unlock card proves nothing. Sample repeatedly: if the cap guard were gone,
	# 20 draws would surface one with ~99.98% probability.
	var unlock_sightings := 0
	for draw in 20:
		for option in main._get_upgrade_choices(1):
			if String(option["id"]) == "unlock_weapon":
				unlock_sightings += 1
	_check(unlock_sightings == 0, "no unlock candidate appears in 20 draws once the cap is reached (saw %d)" % unlock_sightings)
	await process_frame


func _test_independent_cooldowns(main: Node) -> void:
	# player 0 is at the weapon cap from the test above. Give the first a
	# very short cooldown and the rest very long ones, then step the same
	# decrement-then-fire shape the physics loop uses and confirm only the
	# fast weapon's timer (and the damage it deals) moves.
	for weapon_slot in main.weapon_loadouts[0].size():
		main.weapon_loadouts[0][weapon_slot]["cooldown"] = 0.05 if weapon_slot == 0 else 30.0
	var timers: Array = [0.0]
	for extra in main.weapon_loadouts[0].size() - 1:
		timers.append(30.0)
	main.attack_timers[0] = timers

	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	enemy.position = main.players[0].position + Vector2(105.0, 0.0)
	main.add_child(enemy)
	main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)

	var delta := 1.0 / 60.0
	var health_before := enemy.health
	for tick in 10:
		for weapon_slot in main.weapon_loadouts[0].size():
			main.attack_timers[0][weapon_slot] -= delta
			if main.attack_timers[0][weapon_slot] <= 0.0:
				main.weapon_controller.perform_attack(0, weapon_slot, 1.0)
				main.attack_timers[0][weapon_slot] = float(main.weapon_loadouts[0][weapon_slot]["cooldown"])
	await create_timer(0.3).timeout # let any spawned projectiles travel and land

	_check(is_instance_valid(enemy) and enemy.health < health_before, "the fast weapon fired repeatedly on its own short cooldown")
	_check(main.attack_timers[0][1] > 25.0, "a slow weapon's independent timer is untouched by the fast weapon firing")
	_check(main.attack_timers[0][2] > 25.0, "the third weapon's timer is likewise untouched")


func _test_loadout_resonance(main: Node) -> void:
	main.resonance_system.active_resonances.clear()
	var moro: Dictionary = main.character_catalog[4]
	var lyra: Dictionary = main.character_catalog[0]
	var volta: Dictionary = main.character_catalog[1]

	var moro_weapon: Dictionary = main._build_weapon_state(moro)
	moro_weapon = _fuse(main, moro_weapon)
	var lyra_weapon: Dictionary = main._build_weapon_state(lyra)
	lyra_weapon = _fuse(main, lyra_weapon)
	var volta_weapon: Dictionary = main._build_weapon_state(volta)
	volta_weapon = _fuse(main, volta_weapon)

	# Every character pair already resolves to at least one resonance (that was
	# the point of the catalog coverage pass), so the property worth proving
	# here is not "zero becomes one" but "a bigger loadout strictly widens the
	# reachable set": guided_thunder needs lightning, which moro simply does
	# not have until volta's weapon is picked up.
	var solo_ids := _candidate_ids(main, [moro_weapon], [lyra_weapon])
	var loadout_ids := _candidate_ids(main, [moro_weapon, volta_weapon], [lyra_weapon])

	_check(not solo_ids.is_empty(), "two fused weapons resonate")
	_check(not ("guided_thunder" in solo_ids), "moro's own weapon cannot reach guided_thunder — it needs a lightning tag")
	_check("guided_thunder" in loadout_ids, "picking up volta's lightning weapon opens guided_thunder")
	_check(loadout_ids.size() > solo_ids.size(), "a three-weapon-capable loadout strictly widens the candidate set (%d -> %d)" % [solo_ids.size(), loadout_ids.size()])


## Resonance is fusion-only, so a loadout that wants to reach it has to be
## fused first. This is the shortcut the tests use in place of playing out five
## weapon upgrades and three treasure tiers.
func _fuse(main: Node, weapon: Dictionary) -> Dictionary:
	var evolution := EvolutionCatalog.for_base(String(weapon["weapon_id"]))
	return EvolutionCatalog.build_state(evolution, weapon)


func _candidate_ids(main: Node, loadout_a: Array, loadout_b: Array) -> Array[String]:
	var candidates: Array = main.resonance_system.get_candidates_for_loadouts(loadout_a, loadout_b)
	var ids: Array[String] = []
	for candidate in candidates:
		ids.append(String(candidate["id"]))
	return ids


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
