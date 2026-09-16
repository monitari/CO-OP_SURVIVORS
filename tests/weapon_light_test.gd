extends SceneTree

## Every weapon lights the roof it is fired over, and the roof still has a dark
## side afterwards.
##
## The two halves matter equally. A weapon with no entry in the cast table is a
## weapon whose magic does not exist as far as the paving is concerned, which is
## the thing this pass was for. And a table that hands every weapon a strong
## light is the failure the art direction rules out before anything else: the
## roof is meant to be cold with warm magic on it, and light — unlike a halo
## drawn on top of an effect — does not stop at the effect's own edges.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "WEAPON_LIGHT_FAIL", 120.0)
	call_deferred("_run")


func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "WEAPON_LIGHT_FAIL"):
		return
	_check_table(main)
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	var controller: WeaponController = main.weapon_controller
	var field: LightField = controller.light_field
	_check(field != null, "the controller owns a light field")
	if field == null:
		_finish()
		return

	# Every weapon in the roster, fired for real, must light something.
	for character in main.character_catalog:
		var weapon_id := String(character["weapon_id"])
		field.clear_all()
		main.weapon_loadouts[0] = [main._build_weapon_state(character)]
		controller.weapon_loadouts = main.weapon_loadouts
		var enemy: ChaserEnemy = main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false)
		enemy.position = main.players[0].position + Vector2(90.0, 0.0)
		enemy.max_health = 1e9
		enemy.health = 1e9
		main._register_enemy(enemy)
		main.spatial_grid.rebuild(main.enemies)
		controller.perform_attack(0, 0, 1.0)
		_check(field.burning > 0, "%s lights the roof when it fires" % weapon_id)
		main._cull_enemy(enemy)
		controller.clear_transients()

	# The budget, under more casts than it can hold.
	field.clear_all()
	for index in LightField.MAX_LIGHTS * 4:
		field.flash(Vector2(index * 40.0, 0.0), Color.WHITE, 120.0, 0.4, 0.2)
	_check(field.burning <= LightField.MAX_LIGHTS,
		"the ceiling holds under a burst (%d burning)" % field.burning)
	_check(field.get_child_count() <= LightField.MAX_LIGHTS,
		"no light is allocated past the pool (%d nodes)" % field.get_child_count())
	# A bright cast takes a dim one's place, never the other way round.
	field.clear_all()
	for index in LightField.MAX_LIGHTS:
		field.flash(Vector2(index * 40.0, 0.0), Color.WHITE, 120.0, 0.4, 0.05)
	field.flash(Vector2(9000.0, 0.0), Color.WHITE, 120.0, 0.4, 0.38)
	var brightest := 0.0
	for child in field.get_children():
		var light := child as PointLight2D
		if light != null and light.visible:
			brightest = maxf(brightest, light.energy)
	_check(is_equal_approx(brightest, 0.38), "a strong cast displaces a weak one (brightest %.2f)" % brightest)

	# The switch that the on/off capture depends on.
	field.clear_all()
	LightField.enabled = false
	field.flash(Vector2.ZERO, Color.WHITE, 120.0, 0.4, 0.3)
	_check(field.burning == 0, "the toggle puts the roof back in the dark")
	LightField.enabled = true
	_finish()


## The table itself, read without firing anything.
func _check_table(main: Node) -> void:
	var fast: Array[String] = ["homing", "boomerang", "skipping_stone", "orbit"]
	var fused: Array[String] = []
	for evolution in EvolutionCatalog.all_evolutions():
		fused.append(String(evolution["weapon_id"]))
	var roster: Array[String] = []
	for character in main.character_catalog:
		roster.append(String(character["weapon_id"]))
	for weapon_id in roster + fused:
		_check(WeaponController.CAST_LIGHT.has(weapon_id),
			"%s has a cast light entry" % weapon_id)
	# Named rather than derived from the evolution list, because not every fused
	# weapon is a heavy one: 물수제비 and 크림 조수 are fusions that stay fast
	# repeaters, and they belong at the quiet end of this table with the bolts
	# they came from, not with the ones that land once in a while.
	var heavy: Array[String] = ["starpiercer", "thunder_god", "supernova", "black_moon",
		"judgement", "event_horizon"]
	var dimmest_heavy := 1.0
	for weapon_id in heavy:
		var entry: Dictionary = WeaponController.CAST_LIGHT.get(weapon_id, {})
		if entry.has("energy"):
			dimmest_heavy = minf(dimmest_heavy, float(entry["energy"]))
	_check(dimmest_heavy < 1.0, "the heavy weapons are in the table at all")
	for weapon_id in fast:
		var entry: Dictionary = WeaponController.CAST_LIGHT.get(weapon_id, {})
		if not entry.has("energy"):
			continue
		# Not merely lower: an order of magnitude apart, because a repeater and a
		# heavy cast set to similar energies simply raise the roof to an even
		# brightness and neither of them reads as an event.
		_check(float(entry["energy"]) * 2.0 < dimmest_heavy,
			"%s fires several times a second, so its light is far below the heavy casts (%.2f vs %.2f)"
				% [weapon_id, float(entry["energy"]), dimmest_heavy])
	for weapon_id in WeaponController.CAST_LIGHT:
		var entry: Dictionary = WeaponController.CAST_LIGHT[weapon_id]
		_check(float(entry["energy"]) <= LightField.MAX_ENERGY,
			"%s stays inside the light ceiling" % weapon_id)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_LIGHT_PASS: every weapon casts light, the budget and the ordering hold")
		quit(0)
	else:
		for failure in failures:
			push_error("WEAPON_LIGHT_FAIL: " + failure)
		quit(1)


func _check(ok: bool, context: String) -> void:
	if not ok and context not in failures:
		failures.append(context)
