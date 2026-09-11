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
