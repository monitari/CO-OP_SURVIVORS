extends SceneTree
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const Enemies := preload("res://scripts/ui/enemy_icons.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Request a new enemy first: it must not prevent the old atlas initializing.
	Enemies.textures.clear()
	_check_texture(Enemies.get_icon("wasp"), "wasp", true)
	for id in ["swarm", "charger", "shooter", "chain_hunter", "bulwark", "brute"]:
		_check_texture(Enemies.get_icon(id), id, true)
	for id in ["echo", "latte"]: _check_texture(Icons.survivor(id), id)
	for id in ["boomerang", "milk", "skipping_stone", "cream_tide"]: _check_texture(Icons.weapon(id), id)
	for id in ["chaser", "rat_runner", "hedgehog", "mole", "owl", "planter"]: _check_texture(Enemies.get_icon(id), id, true)
	for id in ["chaser", "rat_runner", "hedgehog", "wasp", "mole", "swarm",
			"charger", "shooter", "chain_hunter", "bulwark", "brute", "owl"]:
		if Enemies.source_facing(id) != Enemies.FACING_RIGHT:
			failures.append("Wrong side-facing metadata for " + id)
	for id in ["planter"]:
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
	if not enemy.faces_along_heading or not enemy.body_sprite.flip_h or not is_equal_approx(absf(enemy.rotation), PI):
		failures.append("Remade charger does not face its committed warning")
	enemy.setup(2, "shooter")
	enemy.shooter_windup = 0.4
	enemy.telegraph_direction = Vector2.LEFT
	enemy._step_shooter(Vector2.RIGHT * 100.0, 1.0, 0.016)
	enemy._update_body_facing()
	if not enemy.faces_along_heading or not enemy.body_sprite.flip_h or not is_equal_approx(absf(enemy.rotation), PI):
		failures.append("Remade shooter does not face its committed shot")
	enemy.setup(2, "brute", false, true, 1)
	enemy.boss_slam_windup = 0.4
	enemy.telegraph_direction = Vector2.LEFT
	enemy._step_boss([], Vector2.RIGHT * 100.0, 1.0, 0.016)
	enemy._update_body_facing()
	if not enemy.faces_along_heading or not enemy.body_sprite.flip_h or not is_equal_approx(absf(enemy.rotation), PI):
		failures.append("Remade boss does not face its committed slam")
	enemy.setup(2, "chaser")
	enemy.rotation = PI
	enemy._update_body_facing()
	if not enemy.faces_along_heading or not enemy.body_sprite.flip_h:
		failures.append("Remade chaser does not face left")
	enemy.queue_free()
	for failure in failures: push_error("UNIFIED_ART_FAIL: " + failure)
	print("UNIFIED_ART_PASS: 12 enemy assets load, normalized additions fit, pooled facing" if failures.is_empty() else "UNIFIED_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_texture(texture: Texture2D, id: String, tight := false) -> void:
	if texture == null:
		failures.append("Missing " + id)
		return
	var pixels := texture.get_image()
	if pixels.is_compressed(): pixels.decompress()
	var used := pixels.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		failures.append("Empty image " + id)
	if tight:
		if used != Rect2i(Vector2i.ZERO, pixels.get_size()):
			failures.append("Enemy padding changes field scale " + id)
	else:
		if pixels.get_width() != pixels.get_height():
			failures.append("UI icon is not square " + id)
		if absi(pixels.get_width() - roundi(maxi(used.size.x, used.size.y) * 1.1)) > 1:
			failures.append("Wrong UI padding " + id)
	if pixels.get_pixel(0, 0).a > 0: failures.append("Opaque background " + id)
	if maxi(used.size.x, used.size.y) < 128 or maxi(used.size.x, used.size.y) > 320:
		failures.append("Unexpected source resolution " + id)
