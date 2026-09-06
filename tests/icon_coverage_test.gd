extends SceneTree

const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "ICON_COVERAGE_FAIL", 30.0)
	call_deferred("_run")


## Every screen that matters is icon-led now, so an id with no icon is a blank
## card rather than a cosmetic gap. The atlases are fixed-size hand-drawn files
## and the roster has outgrown them, so the rule this asserts is "every id
## resolves to something drawable", and the report says which ones are still
## running on generated placeholders.
func _run() -> void:
	var placeholders: Array[String] = []
	var covered := 0

	for character in CharacterCatalog.all_characters():
		var character_id := String(character["id"])
		covered += _require(GameIconCatalog.survivor(character_id), "survivor " + character_id)
		if not GameIconCatalog.has_atlas_art(character_id, "survivor"):
			placeholders.append("survivor:" + character_id)
		var weapon_id := String(character["weapon_id"])
		covered += _require(GameIconCatalog.weapon(weapon_id), "weapon " + weapon_id)
		if not GameIconCatalog.has_atlas_art(weapon_id, "weapon"):
			placeholders.append("weapon:" + weapon_id)

	for evolution in EvolutionCatalog.all_fusions():
		var fused_id := String(evolution["weapon_id"])
		covered += _require(GameIconCatalog.weapon(fused_id), "fused weapon " + fused_id)
		if not GameIconCatalog.has_atlas_art(fused_id, "weapon"):
			placeholders.append("weapon:" + fused_id)

	for treasure in TreasureCatalog.all_treasures():
		var treasure_id := String(treasure["id"])
		covered += _require(GameIconCatalog.upgrade(treasure_id), "treasure " + treasure_id)
		if not GameIconCatalog.has_atlas_art(treasure_id, "upgrade"):
			placeholders.append("upgrade:" + treasure_id)

	# The same id must come back as the same texture, or the level-up screen
	# rasterises a fresh image on every card refresh.
	var first := GameIconCatalog.weapon("starpiercer")
	var second := GameIconCatalog.weapon("starpiercer")
	_check(first == second, "generated icons are cached rather than redrawn per lookup")

	# And two different ids must not collide onto the same placeholder, which
	# would make two cards indistinguishable.
	_check(GameIconCatalog.weapon("starpiercer") != GameIconCatalog.weapon("thunder_god"),
		"different ids generate different placeholders")

	print("ICON_METRICS: %d icons resolve, %d still on generated placeholders" % [covered, placeholders.size()])
	if not placeholders.is_empty():
		print("ICON_PLACEHOLDERS: " + ", ".join(placeholders))

	if failures.is_empty():
		print("ICON_COVERAGE_PASS: every catalog id resolves to a drawable icon")
		quit(0)
	else:
		for failure in failures:
			push_error("ICON_COVERAGE_FAIL: " + failure)
		quit(1)


func _require(texture: Texture2D, label: String) -> int:
	_check(texture != null, "%s resolves to an icon" % label)
	return 1 if texture != null else 0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
