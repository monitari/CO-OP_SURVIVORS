extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WEAPON_IDENTITY_FAIL", 420.0)
	call_deferred("_run")


## Twelve weapons that play differently, not twelve damage numbers.
##
## Four of them — 궤도 파편, 관통 광선, 지뢰 결계, 중력 붕괴 — had no unique
## upgrades at all, so half the roster could only ever be handed "+25% damage"
## and "-12% cooldown" for a whole run. And 중력 붕괴 collapsed on the caster,
## which made a control weapon into a thing that only ever fired once the
## problem had already arrived.
##
## These checks pin the parts that a stat block cannot show: that every weapon
## has two specials which actually move something, that the recommendation
## scorer prices them, and that the three reworked deliveries deliver where
## they claim to.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WEAPON_IDENTITY_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	_test_every_weapon_has_specials(main)
	await _test_gravity_casts_at_the_crowd(main)
	await _test_chain_pulse_reads_the_leash(main)
	await _test_lance_splits_into_beams(main)
	_test_leash_upgrade_lengthens_the_chain(main)
	await _test_orbit_hits_once_per_shard(main)
	await _test_the_toy_carries_on_through(main)
	await _test_milk_lands_where_it_lands(main)

	if failures.is_empty():
		print("WEAPON_IDENTITY_PASS: twelve weapons, twenty-four working specials, four reworked deliveries")
		quit(0)
	else:
		for failure in failures:
			push_error("WEAPON_IDENTITY_FAIL: " + failure)
		quit(1)


## Every base weapon declares two specials, each one changes a real field, and
## each one prints something other than the fallback sentence. Driven off the
## catalog rather than a list here, so a survivor added later is covered without
## anyone remembering to come back.
func _test_every_weapon_has_specials(main: Node) -> void:
	for character in CharacterCatalog.all_characters():
		var name := String(character["name"])
		for key: String in ["a", "b"]:
			var state: Dictionary = main._build_weapon_state(character)
			var upgrade_id := "special_" + key
			for tech in main.WeaponTechs.for_weapon(String(character["weapon_id"])):
				if upgrade_id in (tech["upgrades"] as Array):
					main.WeaponTechs.apply_to_state(state, tech)
					break
			main.weapon_loadouts[0] = [state]
			main.attack_timers[0] = [0.0]
			# Resolved against the state: a route can replace a special its own
			# delivery would leave with nothing to do (WeaponTechCatalog.SPECIAL_OVERRIDES).
			var spec: Dictionary = main._special_spec(state, key)
			_check(not spec.is_empty(), "%s's weapon declares special %s" % [name, key])
			if spec.is_empty():
				continue
			_check(main._special_has_room(0, 0, key), "%s's special %s has somewhere to go" % [name, key])

			var option := {"id": upgrade_id, "weapon_slot": 0}
			var preview: String = main._upgrade_preview(0, option)
			_check(preview != "현재 능력을 강화합니다.",
				"%s's special %s previews what it changes (%s)" % [name, key, preview])
			_check(preview.contains("→"), "%s's special %s previews a before and after" % [name, key])

			# The upgrade has to actually land. Run-target specials change the
			# leash instead of the weapon, so they are measured on that.
			var before: float = main._special_current(spec, state)
			main._apply_upgrade(0, option)
			var after: float = main._special_current(spec, main.weapon_loadouts[0][0])
			_check(not is_equal_approx(before, after),
				"%s's special %s moves %s (%.2f)" % [name, key, String(spec["field"]), after])

			# And the card pool has to be able to offer it, or it is unreachable.
			# Fifteen draws rather than forty: each draw runs the whole scoring
			# pass, and at twenty-four specials the old count made this the slowest
			# test in the suite for no extra confidence.
			var offered := false
			for draw in 15:
				for candidate in main._get_upgrade_choices(1):
					if String(candidate["id"]) == upgrade_id and int(candidate["weapon_slot"]) == 0:
						offered = true
			_check(offered, "%s's special %s is reachable from the card pool" % [name, key])


## 중력 붕괴 used to collapse on the caster, so it could only ever hit things
## that had already closed to within its own radius. It now picks the nearest
## enemy inside cast_range and collapses there. The discriminator: an enemy
## further away than the collapse radius but inside the cast range has to be
## damaged, which the old version could never do.
func _test_gravity_casts_at_the_crowd(main: Node) -> void:
	await _clear_enemies(main)
	main.players[0].area = 1.0
	var gravity: Dictionary = main._build_weapon_state(CharacterCatalog.all_characters()[9])
	_check(String(gravity["weapon_id"]) == "gravity", "the fixture picked the gravity survivor")
	main.weapon_loadouts[0] = [gravity]
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 90.0)

	var radius := float(gravity["radius"])
	var neighbour := _spawn(main, Vector2(radius + 180.0, 0.0))
	var anchor := _spawn(main, Vector2(radius + 260.0, 0.0))
	main.spatial_grid.rebuild(main.enemies)
	_check(main.players[0].global_position.distance_to(anchor.global_position) > radius,
		"the fixture puts the crowd outside the collapse radius")

	# Measured on the outer body. The well is placed by scoring where it would
	# catch the most at a useful stand-off, and with two bodies in a line that is
	# the inner one — so the inner one is the centre and does not travel at all.
	# The outer one is what has to be seen closing on it.
	var centre: Vector2 = main.weapon_controller._gravity_centre(0, gravity)
	_check(centre.distance_to(neighbour.global_position) < 1.0,
		"the well opens on the near half of the crowd rather than behind it")
	var anchor_before := anchor.global_position.x
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.16).timeout
	_check(anchor.global_position.x < anchor_before and anchor.global_position.x > centre.x,
		"the pull travels over time instead of teleporting the crowd")
	await create_timer(0.7).timeout
	print("GRAVITY_METRICS: anchor=%.1f neighbour=%.1f moved=%.1f" % [anchor.max_health - anchor.health, neighbour.max_health - neighbour.health, anchor_before - anchor.global_position.x])
	_check(anchor.health < anchor.max_health, "the collapse lands on the crowd, not on the caster")
	_check(neighbour.health < neighbour.max_health, "and catches what is standing with it")
	_check(anchor.global_position.x < anchor_before,
		"and finishes drawn in toward the well rather than left where it stood")

	# Planters share the hostile spatial grid so gravity used to treat them like
	# mobile enemies even though every other crowd rule considers them rooted.
	await _clear_enemies(main)
	var planter := EnemyScript.new() as ChaserEnemy
	planter.setup(0.0, "planter")
	planter.health = 4000.0
	planter.max_health = 4000.0
	planter.position = Vector2(120.0, 0.0)
	main.add_child(planter)
	main.enemies.append(planter)
	var movable := _spawn(main, Vector2(150.0, 0.0))
	main.spatial_grid.rebuild(main.enemies)
	var field := WeaponField.new()
	main.add_child(field)
	field.configure_gravity(Vector2.ZERO, main.spatial_grid, 10.0, 240.0, 100.0, Color.WHITE)
	var planter_before := planter.global_position
	var movable_before := movable.global_position
	field._physics_process(0.24)
	_check(planter.global_position.is_equal_approx(planter_before),
		"a rooted planter is never pulled by gravity")
	_check(movable.global_position.distance_to(Vector2.ZERO) < movable_before.distance_to(Vector2.ZERO),
		"ordinary enemies in the same field are still pulled")
	field._finish_gravity()
	_check(planter.health < planter.max_health,
		"the stationary planter still takes the gravity collapse damage")
	field.queue_free()

	# With nothing in range it must not silently revert to the old behaviour of
	# detonating on top of the pair.
	await _clear_enemies(main)
	var underfoot := _spawn(main, Vector2(20.0, 0.0))
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	await create_timer(0.55).timeout
	_check(underfoot.health < underfoot.max_health, "something already on top of the pair is still hit")

	# ...and the well that hit it did not open on anybody.
	#
	# This is the weapon's worst failure and the hardest to see in code: the
	# placement scores a candidate on how many bodies it would catch, and in a
	# survivors game the densest cluster on the field is the one standing on the
	# pair. So the well opened underfoot and dragged the rest of the crowd in
	# after it — a pull weapon reliably pulling the fight onto its own owners.
	# The crowd underfoot is still the right thing to answer, so the centre is
	# pushed out to a ring rather than the candidate being discarded; what has to
	# hold is that the centre is never on a survivor, whatever the crowd does.
	await _clear_enemies(main)
	for offset in [Vector2(6.0, 0.0), Vector2(-14.0, 9.0), Vector2(0.0, -20.0), Vector2(18.0, 22.0)]:
		_spawn(main, main.players[0].global_position + offset)
	for offset in [Vector2(0.0, 8.0), Vector2(11.0, -6.0), Vector2(-9.0, 14.0)]:
		_spawn(main, main.players[1].global_position + offset)
	main.spatial_grid.rebuild(main.enemies)
	var swarmed: Vector2 = main.weapon_controller._gravity_centre(0, gravity)
	var nearest := INF
	for player in main.players:
		nearest = minf(nearest, swarmed.distance_to(player.global_position))
	_check(nearest >= main.weapon_controller.GRAVITY_MIN_STAND_OFF - 1.0,
		"a crowd standing on both survivors still opens the well clear of them (%.0fpx from the nearer)" % nearest)
	# And the ring is close enough that the well's own radius still reaches back
	# over the bodies it was placed for — otherwise "clear of them" would just be
	# a weapon that refuses to fire when it is needed.
	_check(main.weapon_controller.GRAVITY_MIN_STAND_OFF < float(gravity["radius"]),
		"the stand-off ring sits inside the collapse radius, so the crowd underfoot is still caught")
	await _clear_enemies(main)


## 결속 파동 is the one weapon that reads how the pair is standing. A slack
## chain is a weak pulse; a stretched one is the pair spending safety for damage.
func _test_chain_pulse_reads_the_leash(main: Node) -> void:
	await _clear_enemies(main)
	main.weapon_loadouts[0] = [main._build_weapon_state(CharacterCatalog.all_characters()[5])]
	_check(String(main.weapon_loadouts[0][0]["weapon_id"]) == "chain", "the fixture picked the tether survivor")
	main.players[0].position = Vector2(-100.0, 0.0)
	main.players[1].position = Vector2(100.0, 0.0)
	# Player 0 is 라이라, who carries a 30% crit chance. Left alone, each of the
	# two casts below independently rolls a crit and can invert the comparison
	# about one time in five — this is what makes it a tension measurement
	# rather than a coin flip.
	var crit_backup: float = main.players[0].crit_chance
	main.players[0].crit_chance = 0.0

	var slack := _measure_chain_hit(main, 0.0)
	var stretched := _measure_chain_hit(main, 1.0)
	_check(slack > 0.0, "the tether damages what stands on it (%.1f)" % slack)
	_check(stretched > slack * 1.2,
		"a stretched chain hits harder than a slack one (%.1f vs %.1f)" % [stretched, slack])
	main.players[0].crit_chance = crit_backup
	await _clear_enemies(main)


func _measure_chain_hit(main: Node, tension: float) -> float:
	var victim := _spawn(main, Vector2.ZERO)
	victim.health = 100000.0
	victim.max_health = 100000.0
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.chain_tension = tension
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var dealt := victim.max_health - victim.health
	victim.dead = true
	main.enemies.erase(victim)
	victim.queue_free()
	return dealt


## 분광 rolls separate targets instead of cloning one parallel line. Measured
## by headings and actual victims so a cosmetic spread cannot satisfy it.
func _test_lance_splits_into_beams(main: Node) -> void:
	await _clear_enemies(main)
	main.players[0].area = 1.0
	var lance: Dictionary = main._build_weapon_state(CharacterCatalog.all_characters()[7])
	_check(String(lance["weapon_id"]) == "lance", "the fixture picked the lance survivor")
	main.weapon_loadouts[0] = [lance]
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 200.0)

	var targets: Array[ChaserEnemy] = []
	for position in [Vector2(300, 0), Vector2(0, 300), Vector2(-300, 0), Vector2(0, -300)]:
		targets.append(_spawn(main, position))
	main.spatial_grid.rebuild(main.enemies)
	seed(1197)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var single_hits := targets.filter(func(enemy: ChaserEnemy) -> bool: return enemy.health < enemy.max_health).size()
	_check(single_hits == 1, "one lance selects and pierces one random bearing (%d bearings hit)" % single_hits)

	for enemy in targets:
		enemy.health = enemy.max_health
	main._apply_upgrade(0, {"id": "special_b", "weapon_slot": 0})
	_check(int(main.weapon_loadouts[0][0]["beams"]) == 2, "분광 adds a beam")
	main.spatial_grid.rebuild(main.enemies)
	seed(1197)
	var headings: Array[Vector2] = main.weapon_controller._lance_headings(0, float(lance["range"]), 2)
	_check(headings.size() == 2 and absf(headings[0].angle_to(headings[1])) > 0.1,
		"multiple lances choose visibly different random directions")
	seed(1197)
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var multi_hits := targets.filter(func(enemy: ChaserEnemy) -> bool: return enemy.health < enemy.max_health).size()
	_check(multi_hits >= 2, "two lances reach at least two target bearings (%d)" % multi_hits)
	await _clear_enemies(main)


## The tether survivor's second special is the one upgrade that changes the run
## rather than the weapon, and it is worth its own check because it writes to a
## different place than every other special does.
func _test_leash_upgrade_lengthens_the_chain(main: Node) -> void:
	main.weapon_loadouts[0] = [main._build_weapon_state(CharacterCatalog.all_characters()[5])]
	var before: float = main.chain_max_length
	main._apply_upgrade(0, {"id": "special_b", "weapon_slot": 0})
	_check(main.chain_max_length > before,
		"느슨한 족쇄 lengthens the pair's leash (%.0f → %.0f)" % [before, main.chain_max_length])
	_check(not main.weapon_loadouts[0][0].has("chain_length"),
		"and does not smuggle a stray field onto the weapon")


## 궤도 파편 checked the whole ring five times a second and let one enemy be hit
## only once per check, so every shard past the first was decoration: a boss
## standing in the ring took the same damage from five shards as from one, and
## 파편 증식 — the weapon's own signature upgrade — did nothing at all to a
## single target.
##
## Measured against a stationary dummy parked on the ring, because that is the
## exact case the old model got wrong.
func _test_orbit_hits_once_per_shard(main: Node) -> void:
	await _clear_enemies(main)
	var orbit: Dictionary = main._build_weapon_state(CharacterCatalog.all_characters()[6])
	_check(String(orbit["weapon_id"]) == "orbit", "the fixture picked the orbit survivor")
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 260.0)

	var three := await _measure_orbit(main, orbit, 3)
	var six := await _measure_orbit(main, orbit, 6)
	print("ORBIT_METRICS: 3 shards hit %d times, 6 shards hit %d times" % [three, six])
	_check(three >= 2, "a single enemy is hit more than once per revolution (%d)" % three)
	_check(six > three,
		"doubling the shards lands more hits on that one enemy (%d vs %d)" % [six, three])
	# A shard that stays on top of something must not machine-gun it. The bound
	# is the rule itself — one hit per shard per re-hit window, for as long as
	# the field lives — so a per-frame regression (about 230 hits here) fails
	# even though the honest number sits far below the cap.
	var ceiling := int(ceil(last_orbit_duration / WeaponField.ORBIT_REHIT)) * 6
	_check(six <= ceiling, "and the ring still cannot machine-gun it (%d, ceiling %d)" % [six, ceiling])
	await _clear_enemies(main)


## Runs one orbit field to completion against a dummy on the ring and reports
## how many separate hits it took.
var last_orbit_duration := 0.0


func _measure_orbit(main: Node, base: Dictionary, shards: int) -> int:
	var state := base.duplicate(true)
	state["count"] = shards
	main.weapon_loadouts[0] = [state]
	var victim := _spawn(main, Vector2(float(state["radius"]), 0.0))
	victim.health = 1000000.0
	victim.max_health = 1000000.0
	main.spatial_grid.rebuild(main.enemies)

	var hits := 0
	var previous := victim.health
	main.weapon_controller.perform_attack(0, 0, 1.0)
	var field: WeaponField = null
	for child in main.weapon_controller.get_children():
		var candidate := child as WeaponField
		if candidate != null:
			field = candidate
	_check(field != null, "the cast actually created an orbit field")
	if field == null:
		return 0
	last_orbit_duration = field.duration
	for step in 300:
		if not is_instance_valid(field):
			break
		field._physics_process(1.0 / 60.0)
		if victim.health < previous:
			hits += 1
			previous = victim.health
	if is_instance_valid(field):
		field.queue_free()
	victim.dead = true
	main.enemies.erase(victim)
	victim.queue_free()
	await process_frame
	return hits


## 생선 부메랑 used to stop dead the instant it got home, which made the return
## half of the throw a formality — the pair already knew that path was clear.
## It now carries straight on out the far side, so the throw is a line the
## survivor stands in the middle of and the cast is about which way you face.
func _test_the_toy_carries_on_through(main: Node) -> void:
	await _clear_enemies(main)
	var toy_weapon: Dictionary = main._build_weapon_state(_character_by_id("echo"))
	_check(String(toy_weapon["weapon_id"]) == "boomerang", "the fixture picked the toy survivor")
	main.weapon_loadouts[0] = [toy_weapon]
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 240.0)
	main.players[0].facing = Vector2.RIGHT
	main.players[0].last_input = Vector2.RIGHT

	var reach := float(toy_weapon["range"])
	# One body on each side of the thrower. The near one is deliberately nearer,
	# because the weapon aims at whatever is closest and two bodies at equal
	# range would make which way it is thrown a coin flip.
	var ahead := _spawn(main, Vector2(reach * 0.55, 0.0))
	var behind := _spawn(main, Vector2(-reach * 0.8, 0.0))
	for victim in [ahead, behind]:
		victim.health = 100000.0
		victim.max_health = 100000.0
	main.spatial_grid.rebuild(main.enemies)
	main.weapon_controller.perform_attack(0, 0, 1.0)

	var toy: Node2D = null
	for child in main.weapon_controller.get_children():
		if child.get_script() != null and child.has_method("_physics_process") and "heading" in child:
			toy = child
	_check(toy != null, "the cast actually threw something")
	if toy == null:
		return
	var furthest_out := 0.0
	var furthest_back := 0.0
	for step in 200:
		if not is_instance_valid(toy):
			break
		toy._physics_process(1.0 / 60.0)
		var along: float = toy.global_position.x
		furthest_out = maxf(furthest_out, along)
		furthest_back = minf(furthest_back, along)
	_check(furthest_out > reach * 0.9, "the toy goes out (%.0f of %.0f)" % [furthest_out, reach])
	_check(furthest_back < -reach * 0.9,
		"and carries on past the thrower rather than stopping there (%.0f)" % furthest_back)
	_check(behind.health < behind.max_health, "so it hits what is behind the survivor too")
	# Three passes over the same spot, one hit each: out, home, and away.
	var hits_ahead := (ahead.max_health - ahead.health) / maxf(1.0, float(toy_weapon["damage"]))
	_check(hits_ahead >= 1.9,
		"a body on the outbound line is hit on the way back as well (%.1f hits)" % hits_ahead)
	print("TOY_METRICS: out %.0f back %.0f, %.1f hits on the near side" % [furthest_out, furthest_back, hits_ahead])
	await _clear_enemies(main)


## 우유 흩뿌리기 is the one weapon that does not aim. It scatters across the
## visible roof away from both cats, and what stands in a pool keeps taking
## damage and keeps being slowed.
func _test_milk_lands_where_it_lands(main: Node) -> void:
	await _clear_enemies(main)
	var milk: Dictionary = main._build_weapon_state(_character_by_id("latte"))
	_check(String(milk["weapon_id"]) == "milk", "the fixture picked the milk survivor")
	main.weapon_loadouts[0] = [milk]
	main.players[0].position = Vector2.ZERO
	main.players[1].position = Vector2(0.0, 260.0)

	var underfoot := _spawn(main, Vector2(10.0, 0.0))
	underfoot.health = 100000.0
	underfoot.max_health = 100000.0
	main.spatial_grid.rebuild(main.enemies)
	# 우유 흩뿌리기 opens with a single pool now, like every other weapon that
	# throws more than one thing. The scatter is what 개수 buys, so the fixture
	# asks for four to check that the scatter still works — and asserts the
	# catalogue really does hand out one, which is the part that changed.
	_check(int(CharacterCatalog.all_characters()[11]["weapon"]["count"]) == 1,
		"the catalogue starts 라떼 on a single pool")
	milk["count"] = 4
	main.weapon_controller.perform_attack(0, 0, 1.0)

	var pools: Array[MilkPool] = []
	for child in main.weapon_controller.get_children():
		var pool := child as MilkPool
		if pool != null:
			pools.append(pool)
	_check(pools.size() == int(milk["count"]),
		"a cast spills every pool it says it does (%d of %d)" % [pools.size(), int(milk["count"])])
	var nearest_player := INF
	var all_inside_view := true
	var viewport: Viewport = main.weapon_controller.get_viewport()
	var visible: Rect2 = viewport.get_visible_rect()
	var canvas: Transform2D = viewport.get_canvas_transform()
	for pool in pools:
		for player in main.players:
			nearest_player = minf(nearest_player,
				pool.global_position.distance_to(player.global_position))
		var screen_point: Vector2 = canvas * pool.global_position
		all_inside_view = all_inside_view and visible.has_point(screen_point)
	_check(nearest_player >= WeaponController.MILK_PLAYER_CLEARANCE - 1.0,
		"milk never lands directly under either player (nearest %.0fpx)" % nearest_player)
	_check(all_inside_view, "every milk pool lands inside the current camera view")

	# It is a place, not a hit: standing in it costs more the longer you stand.
	underfoot.global_position = pools[0].global_position
	main.spatial_grid.rebuild(main.enemies)
	var after_one := 0.0
	for step in 120:
		for pool in pools:
			if is_instance_valid(pool):
				pool._physics_process(1.0 / 60.0)
		if step == 40:
			after_one = underfoot.max_health - underfoot.health
	var total := underfoot.max_health - underfoot.health
	_check(after_one > 0.0, "a pool damages what stands in it (%.0f)" % after_one)
	_check(total > after_one, "and keeps doing it (%.0f then %.0f)" % [after_one, total])
	_check(underfoot.slow_timer > 0.0 or underfoot.slow_multiplier < 1.0, "and slows it")
	print("MILK_METRICS: %d pools, nearest player %.0fpx, %.0f damage over 2s" % [
		pools.size(), nearest_player, total])
	for pool in pools:
		if is_instance_valid(pool):
			pool.queue_free()
	await _clear_enemies(main)


func _character_by_id(id: String) -> Dictionary:
	for character in CharacterCatalog.all_characters():
		if String(character["id"]) == id:
			return character
	return {}


func _spawn(main: Node, at: Vector2) -> ChaserEnemy:
	var enemy := EnemyScript.new() as ChaserEnemy
	enemy.setup(0.0, "chaser")
	enemy.health = 4000.0
	enemy.max_health = 4000.0
	enemy.position = at
	main.add_child(enemy)
	main.enemies.append(enemy)
	return enemy


func _clear_enemies(main: Node) -> void:
	for candidate in main.enemies.duplicate():
		var enemy := candidate as ChaserEnemy
		if is_instance_valid(enemy):
			enemy.dead = true
			enemy.queue_free()
	main.enemies.clear()
	main.spatial_grid.rebuild(main.enemies)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
