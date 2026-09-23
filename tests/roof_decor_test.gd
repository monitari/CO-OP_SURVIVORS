extends SceneTree
## The run's rooftop furniture: where it goes, that it really stands in front of
## and behind the survivors, and that the two exceptions to "stays solid" — a
## hidden cat and a hidden drop — are the only ones.
##
## `-- --capture` also saves real-renderer captures to .godot_runtime/decor-*.png.

const MainScene := preload("res://scenes/main.tscn")
const Harness := preload("res://tests/test_harness.gd")
const DecorScript := preload("res://scripts/entities/roof_decor.gd")
var failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, "ROOF_DECOR", 120.0)
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/decor-" + label + ".png")


func run() -> void:
	_check_layout()
	_check_painted_atlas()
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not Harness.require_loaded(self, main, "ROOF_DECOR"):
		return
	main._begin_lobby()
	main._join_ai_companion()
	main._start_selected_run()
	await physics_frame
	main.set_physics_process(false)
	main.modal_dim.visible = false
	main.combat_hud.visible = true
	await _check_every_kind_draws(main)
	await _check_opening(main)
	await _check_occlusion(main)
	_check_loot(main)
	await _crowd(main)
	await _tour(main)
	for failure in failures:
		push_error("ROOF_DECOR: " + failure)
	if failures.is_empty():
		print("ROOF_DECOR_PASS")
	quit(0 if failures.is_empty() else 1)


## The layout is a pure function of position, keeps out of the opening, and
## never stacks two pieces on top of each other.
func _check_layout() -> void:
	var sample := Vector2i(17, -9)
	var first: Dictionary = RoofLayout.cell(sample).duplicate(true)
	RoofLayout._cache.clear()
	check(str(RoofLayout.cell(sample)) == str(first), "The same cell always lays out the same")

	var used: Dictionary = {}
	for home in RoofLayout.HOME_PIECES:
		used[home[0]] = true
	for vignette in RoofLayout.VIGNETTES:
		for entry in vignette["pieces"]:
			used[entry[0]] = true
	for kind in RoofLayout.KINDS.keys():
		check(used.has(kind), "%s is placed somewhere on the roof" % kind)
		check(not RoofLayout.shadow_polygons({"kind": kind, "at": Vector2.ZERO}).is_empty(),
			"%s throws a shadow" % kind)

	var pieces := RoofLayout.pieces_in(Rect2(-6400, -6400, 12800, 12800))
	var clustered := 0
	var crowded := 0
	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		var at: Vector2 = piece["at"]
		if not String(piece["id"]).begins_with("home:") and RoofLayout.HOME_KEEP_OUT.grow(-220.0).has_point(at):
			clustered += 1
		for other_index in range(index + 1, pieces.size()):
			var other: Vector2 = pieces[other_index]["at"]
			if absf(other.x - at.x) < 50.0 and absf(other.y - at.y) < 24.0:
				crowded += 1
	# Nothing stands astride a drainage gutter, home layout included.
	var astride := 0
	for piece in pieces:
		for foot in RoofLayout.footprints(piece):
			if RoofLayout._on_gutter(foot.position.x, foot.end.x):
				astride += 1
	check(astride == 0, "No furniture stands on a gutter (%d feet did)" % astride)
	# Anything a player wants is moved out from inside and from behind furniture.
	var buried := 0
	for piece in pieces.slice(0, 60):
		var keep: Rect2 = piece["keep"]
		for probe: Vector2 in [keep.get_center(), keep.position + keep.size * 0.2, keep.end - keep.size * 0.2]:
			var moved := RoofLayout.clear_spot(probe)
			for other in RoofLayout.pieces_in(Rect2(moved - Vector2(400, 400), Vector2(800, 800))):
				if (other["keep"] as Rect2).grow(15.0).has_point(moved):
					buried += 1
			if moved.distance_to(probe) > 320.0:
				buried += 1
	check(buried == 0, "clear_spot always finds open roof close by (%d misses)" % buried)
	check(clustered == 0, "No random vignette lands on the opening (%d did)" % clustered)
	check(crowded == 0, "No two pieces stand in the same spot (%d pairs)" % crowded)
	# Roughly 0.34 vignettes of ~2.2 pieces per 640 cell. The painted silhouettes
	# stay readable because the roof now gives each cluster more negative space.
	var per_cell := float(pieces.size()) / 400.0
	check(per_cell > 0.45 and per_cell < 1.25, "Furniture density stays in its band (%.2f per cell)" % per_cell)


## Every kind has a painted sprite, inside the atlas, whose feet actually reach
## the ground point. A sprite floating a few texels above its origin would stand
## a few units above its own shadow.
func _check_painted_atlas() -> void:
	var atlas: Image = RoofDecor.PROP_ATLAS.get_image()
	check(atlas.get_size() == Vector2i(1024, 512) * int(RoofDecor.SPRITE_TEXELS),
		"The atlas holds the sprites at their authored density (%s)" % str(atlas.get_size()))
	for kind in RoofLayout.KINDS.keys():
		check(RoofDecor.PROP_REGIONS.has(kind), "%s has a painted sprite" % kind)
		if not RoofDecor.PROP_REGIONS.has(kind):
			continue
		var region: Rect2 = RoofDecor.PROP_REGIONS[kind]
		var texels := Rect2i(Vector2i(region.position * RoofDecor.SPRITE_TEXELS), Vector2i(region.size * RoofDecor.SPRITE_TEXELS))
		check(Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(texels), "%s lies inside the atlas" % kind)
		var lowest := -1
		for y in range(texels.end.y - 1, texels.position.y, -1):
			for x in range(texels.position.x, texels.end.x, 2):
				if atlas.get_pixel(x, y).a > 0.5:
					lowest = y
					break
			if lowest >= 0:
				break
		var gap := float(texels.end.y - 1 - lowest) / RoofDecor.SPRITE_TEXELS
		check(lowest >= 0 and absf(gap - RoofDecor.SPRITE_BOTTOM_PAD) <= 2.0,
			"%s stands on its origin (feet %.1f units above the pad)" % [kind, gap - RoofDecor.SPRITE_BOTTOM_PAD])


func _check_every_kind_draws(main) -> void:
	var probes: Array[RoofDecor] = []
	var kinds: Array = RoofLayout.KINDS.keys()
	kinds.append("water_tower_back")
	for index in kinds.size():
		var decor := DecorScript.new() as RoofDecor
		decor.setup(String(kinds[index]), Vector2(90000 + index * 300, 90000), 1234 + index)
		main.world_stage.add_child(decor)
		probes.append(decor)
	await process_frame
	await process_frame
	for decor in probes:
		check(decor.get_parent() == main.world_stage, "%s stands in the sorted stage" % decor.kind)
		decor.queue_free()
	await process_frame


func _settle(main, frames := 45) -> void:
	for i in frames:
		main._update_camera(1.0 / 60.0)


func _check_opening(main) -> void:
	main.players[0].position = Vector2(-105, 0)
	main.players[1].position = Vector2(105, 0)
	main._update_chain_visual()
	_settle(main)
	var props: Array[RoofDecor] = main.rooftop_props.living_props()
	var on_screen := 0
	var view: Rect2 = main._visible_world_rect()
	for prop in props:
		if view.intersects(prop.screen_rect()):
			on_screen += 1
		check(prop.get_parent() == main.world_stage, "Every piece shares the survivors' sorted stage")
	check(main.world_stage.y_sort_enabled, "The stage sorts by ground contact")
	check(on_screen >= 5, "The opening screen is furnished (%d pieces in view)" % on_screen)
	# Solid, not the old tenth-opacity ghost furniture.
	for prop in props:
		check(prop.modulate.a > 0.95, "%s stands solid when nobody is behind it" % prop.kind)
	# Upright: the node carries the same correction the cats get, so a tall
	# piece does not lean into the vanishing point at the edge of the screen.
	var tower := _find(main, "water_tower")
	check(tower != null, "The opening has its water tower")
	if tower != null:
		# Compared once the camera has reported where it now is; within the
		# frame that moved it, the engine's own answer is still the old one.
		await process_frame
		main._update_camera(0.0)
		var basis: Transform2D = RooftopSpace.upright_basis(tower)
		check(tower.transform.y.is_equal_approx(basis.y) and tower.position == tower.ground,
			"Furniture stands upright without moving its sort key")
	await capture("opening")


func _check_occlusion(main) -> void:
	var tower := _find(main, "water_tower")
	if tower == null:
		return
	var cat: ChainPlayer = main.players[0]
	# Walk the cat up the roof behind the tank until it is as hidden as it gets.
	var best_share := 0.0
	var best_y := tower.ground.y
	for step in 60:
		var y: float = tower.ground.y - 4.0 * float(step)
		cat.position = Vector2(tower.ground.x, y)
		var share := RooftopOcclusion.covered_share(RooftopOcclusion.body_rect(cat), tower.screen_rect())
		if share > best_share:
			best_share = share
			best_y = y
	check(best_share >= RooftopOcclusion.HIDDEN_SHARE, "A cat can stand fully behind the water tank (%.2f)" % best_share)
	cat.position = Vector2(tower.ground.x, best_y)
	main.players[1].position = cat.position + Vector2(160, 0)
	main._update_chain_visual()
	_settle(main, 60)
	check(cat.position.y < tower.position.y, "Behind means earlier in the sort: the tank draws over the cat")
	check(tower.modulate.a > 0.7 and tower.modulate.a < 0.9,
		"A tank hiding a cat eases off but still stands in front (%.2f)" % tower.modulate.a)
	check(main.rooftop_occlusion.hidden(cat, main.rooftop_props.living_props()), "The hidden cat gets its outline")
	main.rooftop_occlusion.step()
	await capture("behind")

	cat.position = Vector2(tower.ground.x - 10, tower.ground.y + 40)
	main.players[1].position = cat.position + Vector2(160, 0)
	main._update_chain_visual()
	_settle(main, 60)
	check(cat.position.y > tower.position.y, "In front means later in the sort: the cat draws over the tank")
	check(tower.modulate.a > 0.97, "A cat in front never thins the tank (%.2f)" % tower.modulate.a)
	check(not main.rooftop_occlusion.hidden(cat, main.rooftop_props.living_props()), "A cat in front has no outline")
	main.rooftop_occlusion.step()
	await capture("front")

	# Under the tank, between its stilts: in front of the back pair, behind the front.
	var back: RoofDecor = null
	for prop in main.rooftop_props.living_props():
		if prop.kind == "water_tower_back" and prop.ground.distance_to(tower.ground) < 100.0:
			back = prop
	check(back != null, "The tank's back stilts are their own node")
	if back != null:
		cat.position = tower.ground - Vector2(0, 38)
		check(cat.position.y > back.position.y and cat.position.y < tower.position.y,
			"A cat under the tank sorts between its back and front stilts")


func _check_loot(main) -> void:
	var tower := _find(main, "water_tower")
	if tower == null:
		return
	main.players[0].position = tower.ground + Vector2(0, 260)
	main.players[1].position = tower.ground + Vector2(160, 260)
	var rect := tower.screen_rect()
	var keep := RoofLayout._keep_out({"kind": "water_tower", "at": tower.ground})
	# A drop landing behind the tank is moved out to where it can be seen...
	var item: FieldItem = main.field_items.spawn_item(rect.get_center(), "heal")
	check(not keep.has_point(item.global_position), "A drop never spawns behind or inside furniture")
	main.experience_system.spawn_gem(rect.get_center(), 3)
	var gem: ExperienceGem = main.experience_system.active_gems.back()
	check(not keep.has_point(gem.global_position), "Nor does an experience gem")
	# ...and if one ends up there anyway, the tank still gets out of its way.
	item.global_position = rect.get_center()
	_settle(main, 60)
	check(tower.modulate.a < 0.5, "Furniture standing over a drop thins so the drop can be seen (%.2f)" % tower.modulate.a)
	main.field_items.clear_all()
	_settle(main, 60)
	check(tower.modulate.a > 0.97, "It stands solid again once the drop is gone")
	_check_knocks(main)


## Nothing blocks, so bumping is shown instead: a cat dashing through a piece
## knocks it, the top sways about a planted base, and it comes back to rest.
func _check_knocks(main) -> void:
	var line: RoofDecor = _find(main, "laundry")
	check(line != null, "The opening has its laundry line")
	if line == null:
		return
	var cat: ChainPlayer = main.players[0]
	cat.position = line.ground + Vector2(-30, 4)
	main.players[1].position = cat.position + Vector2(0, 150)
	cat.dash_timer = 0.1
	cat.dash_direction = Vector2.RIGHT
	main.rooftop_props.update_visibility(main.players, 1.0 / 60.0)
	check(line.jolt > 0.9, "Dashing through the laundry knocks it (%.2f)" % line.jolt)
	# The camera holds still through this loop, so any change in the lean is
	# the sway itself.
	var least := INF
	var most := -INF
	for i in 12:
		main.rooftop_props.update_visibility(main.players, 1.0 / 60.0)
		least = minf(least, line.transform.y.x)
		most = maxf(most, line.transform.y.x)
	check(most - least > 0.02, "A knocked piece sways (%.3f)" % (most - least))
	check(line.position == line.ground, "Swaying never moves the sort key")
	cat.dash_timer = 0.0
	cat.current_input = Vector2.ZERO
	for i in 120:
		main.rooftop_props.update_visibility(main.players, 1.0 / 60.0)
	check(line.jolt == 0.0, "It comes back to rest")
	var tower: RoofDecor = _find(main, "water_tower")
	main.rooftop_props.shake_at(tower.ground + Vector2(80, 0), 400.0, 1.0)
	check(tower.jolt > 0.6, "A shockwave nearby knocks the tank (%.2f)" % tower.jolt)
	main.rooftop_props.shake_at(tower.ground + Vector2(2000, 0), 400.0, 1.0)
	for i in 120:
		main.rooftop_props.update_visibility(main.players, 1.0 / 60.0)


## The opening with a crowd on it, for judging whether the furniture ever makes
## a fight harder to read. Enemies sort against it exactly as the cats do.
func _crowd(main) -> void:
	main.players[0].position = Vector2(-105, 0)
	main.players[1].position = Vector2(105, 0)
	var spawned: Array = []
	for i in 48:
		var enemy = main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false)
		var angle := float(i) * 0.61
		var reach := 260.0 + float(i % 6) * 70.0
		enemy.position = Vector2(cos(angle) * reach * 1.25, sin(angle) * reach * 0.62)
		main._register_enemy(enemy)
		spawned.append(enemy)
	main._update_chain_visual()
	_settle(main, 45)
	main.crowd_renderer.view_rect = main._visible_world_rect()
	main.crowd_renderer.dirty = true
	var stage_children: Array = main.world_stage.get_children()
	check(stage_children.any(func(node): return node is RoofDecor), "Furniture and the crowd share one sorted stage")
	await capture("crowd")
	for enemy in spawned:
		main.wave_director.release_enemy(enemy)
	main.enemies.clear()
	main.crowd_renderer.dirty = true


## A walk across the roof, for looking at. Also the far-travel bound.
func _tour(main) -> void:
	var spots := [Vector2(2600, -1400), Vector2(-3900, 2300), Vector2(5200, 3100), Vector2(-1900, -4400)]
	for index in spots.size():
		var at: Vector2 = spots[index]
		main.players[0].position = at - Vector2(100, 0)
		main.players[1].position = at + Vector2(100, 0)
		main.world_camera.position = at
		main._update_chain_visual()
		# The camera reports its new centre from the next frame; settle across it
		# so the furniture is based on where the view actually is.
		_settle(main, 30)
		await process_frame
		_settle(main, 2)
		await capture("tour-%d" % index)
	check(main.rooftop_props.living_props().size() < 100, "Furniture count stays bounded while travelling")
	# A jump across the roof, and one tick, and nothing else: the camera has not
	# yet reported its new centre. Furniture measured from the old one was sheared
	# into streaks across the whole screen.
	var far := Vector2(120000, -90000)
	main.players[0].position = far - Vector2(100, 0)
	main.players[1].position = far + Vector2(100, 0)
	main.world_camera.position = far
	main.world_camera.zoom = Vector2.ONE * 0.45
	main._update_camera(0.0)
	# Only what is on screen: pieces kept alive past the edge are correctly
	# corrected by more, since the correction grows with distance from centre.
	var worst := 0.0
	var view: Rect2 = main.rooftop_view.visible_bounds(far, main.world_camera.zoom)
	for prop in main.rooftop_props.living_props():
		if view.has_point(prop.ground):
			worst = maxf(worst, absf(prop.transform.y.x))
	check(worst < 0.3, "Furniture stays upright on the tick the camera jumps (shear %.2f)" % worst)
	await capture("jump")


func _find(main, kind: String) -> RoofDecor:
	var best: RoofDecor = null
	for prop in main.rooftop_props.living_props():
		if prop.kind == kind and (best == null or prop.ground.length() < best.ground.length()):
			best = prop
	return best
