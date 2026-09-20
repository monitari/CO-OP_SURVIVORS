extends SceneTree
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const Enemies := preload("res://scripts/ui/enemy_icons.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Request a new enemy first: it must not prevent the old atlas initializing.
	Enemies.textures.clear()
	_check_texture(Enemies.get_icon("wasp"), "wasp")
	for id in ["swarm", "charger", "shooter", "chain_hunter", "bulwark", "brute"]:
		if Enemies.get_icon(id) == null: failures.append("Missing original " + id)
	for id in ["echo", "latte"]: _check_texture(Icons.survivor(id), id)
	for id in ["boomerang", "milk", "skipping_stone", "cream_tide"]: _check_texture(Icons.weapon(id), id)
	for id in ["chaser", "rat_runner", "hedgehog", "mole", "owl"]: _check_texture(Enemies.get_icon(id), id)
	for id in ["chaser", "rat_runner", "hedgehog", "wasp", "mole"]:
		if Enemies.source_facing(id) != Enemies.FACING_RIGHT:
			failures.append("Wrong side-facing metadata for " + id)
	for id in ["swarm", "charger", "shooter", "chain_hunter", "bulwark", "brute", "owl", "planter"]:
		if Enemies.source_facing(id) != Enemies.FACING_FRONT:
			failures.append("Wrong front-facing metadata for " + id)
	var enemy := ChaserEnemy.new()
	root.add_child(enemy)
	enemy.setup(2, "mole")
	enemy.rotation = PI
	# Facing is refreshed by step() rather than by a transform notification, so
	# the drive is explicit here too — the invariant under test is that a heading
	# to the left mirrors the art, not which callback noticed the heading.
	enemy._update_body_facing()
	if not enemy.body_sprite.flip_h: failures.append("New enemy does not face left")
	enemy.setup(2, "chaser")
	enemy._update_body_facing()
	if enemy.body_sprite.flip_h: failures.append("Pooled original retains mirrored state")
	enemy.position = Vector2(100.0, 0.0)
	enemy.face_toward(Vector2.ZERO)
	if not enemy.body_sprite.flip_h: failures.append("Fresh spawn does not face the play centre")
	enemy.face_toward(Vector2(200.0, 0.0))
	if enemy.body_sprite.flip_h: failures.append("Spawn facing does not reset toward the right")
	enemy.setup(2, "charger")
	enemy.position = Vector2.ZERO
	enemy.behavior_timer = 0.0
	enemy._step_charger(Vector2(-100.0, 0.0), 1.0, 0.016)
	enemy._update_body_facing()
	if enemy.faces_along_heading or enemy.body_sprite.flip_h or not is_equal_approx(absf(enemy.rotation), PI):
		failures.append("Front-facing charger was mirrored instead of aiming its warning")
	enemy.setup(2, "shooter")
	enemy.shooter_windup = 0.4
	enemy.telegraph_direction = Vector2.LEFT
	enemy._step_shooter(Vector2.RIGHT * 100.0, 1.0, 0.016)
	enemy._update_body_facing()
	if enemy.faces_along_heading or enemy.body_sprite.flip_h or not is_equal_approx(absf(enemy.rotation), PI):
		failures.append("Front-facing shooter was mirrored instead of aiming its shot")
	enemy.setup(2, "brute", false, true, 1)
	enemy.boss_slam_windup = 0.4
	enemy.telegraph_direction = Vector2.LEFT
	enemy._step_boss([], Vector2.RIGHT * 100.0, 1.0, 0.016)
	enemy._update_body_facing()
	if enemy.faces_along_heading or enemy.body_sprite.flip_h or not is_equal_approx(absf(enemy.rotation), PI):
		failures.append("Front-facing boss was mirrored during its committed slam")
	enemy.setup(2, "chaser")
	enemy.rotation = PI
	enemy._update_body_facing()
	if not enemy.faces_along_heading or not enemy.body_sprite.flip_h:
		failures.append("Remade chaser does not face left")
	enemy.queue_free()
	for failure in failures: push_error("UNIFIED_ART_FAIL: " + failure)
	print("UNIFIED_ART_PASS: 12 enemy assets load, normalized additions fit, pooled facing" if failures.is_empty() else "UNIFIED_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_texture(texture: Texture2D, id: String) -> void:
	if texture == null:
		failures.append("Missing " + id)
		return
	var pixels := texture.get_image()
	if pixels.is_compressed(): pixels.decompress()
	if pixels.get_size() != Vector2i(512, 512): failures.append("Wrong size " + id)
	var used := pixels.get_used_rect()
	if used.position.x < 28 or used.position.y < 28 or used.end.x > 484 or used.end.y > 484:
		failures.append("Unsafe padding " + id)
	if pixels.get_pixel(0, 0).a > 0: failures.append("Opaque background " + id)
	if maxi(used.size.x, used.size.y) < 440: failures.append("Inconsistent content scale " + id)
