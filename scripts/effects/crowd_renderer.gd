class_name CrowdRenderer
extends Node2D
## Draws the crowd — bodies, contact shadows, health bars, elite rings and
## attack warnings — in a few dozen batched draw calls instead of several per
## enemy.
##
## Every enemy used to draw itself: two untextured shadow discs and a health
## bar from its own _draw, and its painted body from a Sprite2D with a texture
## of its own. Each switch between an untextured shape and a texture, and
## between one archetype's texture and the next, is a new draw call, so a crowd
## of fifteen hundred cost nearly eight thousand calls a frame and the game fell
## to single-digit frame rates long before the simulation ran out of time.
##
## Here every archetype, the shadow and the warning shapes live in one texture
## and everything is a MultiMesh instance. Depth still works the way the rooftop
## needs it to: bodies are split into thin horizontal bands, each band one
## MultiMeshInstance2D standing at that band's row inside the y-sorted stage, so
## a cat or a planter still passes in front of or behind the crowd at the right
## row. Shadows lie on the floor under every actor and share one instance.
## Warnings (charge lines, aim lines, chain-bite rings) share another, drawn
## above the actors: a warning is the one thing on the roof that must never be
## hidden behind something else.
##
## Bosses are the fight rather than the crowd and keep drawing themselves.

const EnemyIcons := preload("res://scripts/ui/enemy_icons.gd")

## Height of one depth band in world units. The ordering error between two
## bodies in the same band is at most this, well under a body's own height.
const BAND := 24.0
## Slack around the visible rectangle: sprites and warning lines reach past a
## body's ground point, and a crowd popping in at the frame edge reads as spawning.
const CULL_MARGIN := 140.0
## Instance layout for TRANSFORM_2D + colours + custom data.
const STRIDE := 16
## Sparse depth bands used to allocate 128 instances on first use even when
## they held one body. That multiplied both upload size and GPU buffer memory by
## dozens of bands. These are capacities in instances, not floats.
const BAND_MIN_CAPACITY := 8
const SHADOW_MIN_CAPACITY := 256
const WARNING_MIN_CAPACITY := 16
const CELL := 256
const CELL_CONTENT := 236
const ATLAS_COLUMNS := 5
## Body sprites are sized by their longer edge, the same rule Sprite2D used.
const BODY_SPAN := 2.65
## Moonlight.ground_shadow's two discs: outer radius, inner share, alphas.
const SHADOW_OUTER := 1.14
const SHADOW_INNER_SHARE := 0.80 / 1.14
const SHADOW_OUTER_ALPHA := 0.12 * 0.95
const SHADOW_INNER_ALPHA := 0.16 * 0.95
const BAR_BACK := Color("351d3c")
const BAR_FILL := Color("80ed99")
const ELITE_RING := Color("e8c98a")
const RING_THICKNESS := 0.16
const DASH_COUNT := 16

## Keys of the shape cells packed next to the archetype art.
const SHAPES := ["_shadow", "_block", "_disc", "_ring", "_arc65", "_arc100", "_dash"]

## A 2D MultiMesh layer is culled against the rectangle its instances covered
## when its draw command was first built; uploading new instance data later does
## not refresh that rectangle. Instances that have since moved outside it — the
## crowd and its shots after the pair has walked across the endless roof — were
## culled with the whole layer: invisible, still moving, still hitting. Every
## batch layer therefore declares bounds covering the whole world.
const WORLD_BOUNDS := AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))

static var _atlas: ImageTexture
## key -> PackedFloat32Array(u, v, w, h)
static var _regions: Dictionary = {}
## archetype -> Vector2 size of the art, longer edge = 1.
static var _aspects: Dictionary = {}
static var _quad: ArrayMesh
static var _material: ShaderMaterial

## The live enemy list main.gd owns. Read only.
var enemies: Array[ChaserEnemy] = []
## The live enemy-shot list main.gd owns. Read only.
var shots: Array = []
## The y-sorted stage the depth bands are placed into.
var stage: Node2D
## Rectangle of the world currently on screen; set by the owner each tick.
var view_rect := Rect2(-2000, -2000, 4000, 4000)
## Toggle for comparisons. Off hands every body back to its own node.
var enabled := true
## Enemy shots ride the warning layer, above the survivors, the roof furniture
## and every friendly effect. They used to be drawn on the floor layer under
## all of those, so a late fight's scythe sweeps, gravity wells and orbit rings
## painted over incoming shots and a player took hits from things they could
## not see. A shot is a threat to dodge, not part of the floor. False puts them
## back on the floor, for comparison.
var threats_on_top := true
## Set by the owner whenever the crowd or the camera moved.
var dirty := true
## The cull rectangle the batches on screen were actually built against.
##
## `dirty` covers the running game, where the owner sets it every physics tick.
## It cannot cover a frozen one: the growth screen, a chest and the pause menu
## all stop the tree and then *move the camera* — they pull in on the pair and
## lift the view — while no physics tick runs to raise the flag. Everything this
## renderer draws is hidden at its node, so a view that has travelled past the
## rectangle the last batch was culled against shows a band of nothing where
## those bodies are. Rebuilding whenever the view leaves that rectangle covers
## the frozen case without rebuilding for a camera that has merely drifted a
## pixel inside it.
var _built_cull := Rect2()

var _shadows: MultiMeshInstance2D
var _warnings: MultiMeshInstance2D
var _bands: Array[MultiMeshInstance2D] = []
var _band_data: Array[PackedFloat32Array] = []
var _band_used := PackedInt32Array()
var _shadow_data := PackedFloat32Array()
var _warning_data := PackedFloat32Array()
var _shadow_used := 0
var _warning_used := 0
## Last frame's counts, for tests and the profiler.
var drawn_bodies := 0
var drawn_instances := 0
var drawn_bands := 0
var drawn_warnings := 0


func _ready() -> void:
	_build_shared()
	_shadows = _make_layer("CrowdShadows")
	# On the floor, under the chain (ChainArc.BEHIND_ACTORS) and every actor.
	_shadows.z_index = ChainArc.BEHIND_ACTORS - 1
	stage.add_child(_shadows)
	_warnings = _make_layer("CrowdWarnings")
	_warnings.z_index = 2
	stage.add_child(_warnings)


func _process(_delta: float) -> void:
	# Only after a physics tick has moved something: on a high-refresh display
	# most rendered frames have nothing new to batch.
	if dirty and not get_tree().paused:
		dirty = false
		refresh()
		return
	if not _built_cull.encloses(view_rect):
		refresh()


## Rebuilds every batch from the current crowd. Public so a paused capture or a
## test can force the picture to match the simulation.
func refresh() -> void:
	var snapshot := RooftopSpace.view_snapshot(stage)
	var cull := view_rect.grow(CULL_MARGIN)
	_built_cull = cull
	var first_band := floori(cull.position.y / BAND)
	var band_total := maxi(1, ceili(cull.size.y / BAND) + 1)
	_ensure_bands(band_total)
	_band_used.fill(0)
	_shadow_used = 0
	_warning_used = 0
	var shadowed := Moonlight.enabled
	var tilt := RooftopSpace.tilt()
	var centre_view := snapshot.centre
	var zoom := snapshot.zoom
	var view_size := snapshot.view_size
	var perspective := snapshot.valid
	var shear_scale := -EndlessRooftopView.PERSPECTIVE * view_size.x / view_size.y / EndlessRooftopView.TILT
	var shadow_uv: PackedFloat32Array = _regions["_shadow"]
	var block_uv: PackedFloat32Array = _regions["_block"]
	var fallback_uv: PackedFloat32Array = _regions.get(EnemyIcons.FALLBACK, block_uv)
	var shadow_grow := SHADOW_OUTER * (CELL_CONTENT * 0.5) / (CELL_CONTENT * 0.5 - 2.0)
	var shadow_offset := Moonlight.SHADOW_DIRECTION * Moonlight.SHADOW_REACH
	var shadow_capacity := _shadow_data.size()
	var shadow_ink := Moonlight.SHADOW_INK
	var shadow_squash := Moonlight.SHADOW_SQUASH
	var body_count := 0
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or not enemy.active:
			continue
		var own := not enabled or enemy.boss
		if own != enemy.visible:
			enemy.visible = own
			if own:
				enemy._update_body_facing()
				enemy.queue_redraw()
		if own:
			continue
		var at := enemy.position
		if not cull.has_point(at):
			enemy.on_screen = false
			continue
		enemy.on_screen = true
		body_count += 1
		if enemy.render_stamp != 1:
			# Resolved once per setup rather than looked up by archetype name for
			# every body every frame.
			enemy.render_uv = _regions.get(enemy.archetype, fallback_uv)
			enemy.render_aspect = _aspects.get(enemy.archetype, Vector2.ONE)
			enemy.render_stamp = 1
		var band := floori(at.y / BAND) - first_band
		var grow := enemy.scale.x
		var radius := enemy.radius
		var origin_y := at.y - enemy.stand_height * tilt * grow
		var local_y := origin_y - (float(first_band + band) * BAND + BAND * 0.5)
		# The upright correction is RooftopSpace.ViewSnapshot.basis_at, inlined:
		# this runs for every body on screen every frame.
		var k := 1.0
		var shear := 0.0
		if perspective:
			k = (1.0 - EndlessRooftopView.PERSPECTIVE * (at.y - centre_view.y) * zoom.y / view_size.y) / EndlessRooftopView.TILT
			shear = shear_scale * (at.x - centre_view.x) * zoom.x / view_size.x
		var aspect := enemy.render_aspect
		var span := radius * BODY_SPAN * grow
		var width := span * aspect.x
		if enemy.faces_along_heading and cos(enemy.rotation) < 0.0:
			width = -width
		var height := span * aspect.y
		var uv := enemy.render_uv
		var health_ratio := enemy.health / enemy.max_health
		var elite := enemy.elite
		var barred := health_ratio < 0.99 or elite
		var extra := (2 if barred else 0) + (2 if elite else 0)
		var data := _band_data[band]
		var used := _band_used[band]
		if (used + 1 + extra) * STRIDE > data.size():
			data.resize(maxi(BAND_MIN_CAPACITY, nearest_po2(used + 1 + extra)) * STRIDE)
			_band_data[band] = data
		var i := used * STRIDE
		data[i] = width; data[i + 1] = shear * height; data[i + 2] = 0.0; data[i + 3] = at.x
		data[i + 4] = 0.0; data[i + 5] = k * height; data[i + 6] = 0.0; data[i + 7] = local_y
		if enemy.slow_timer > 0.0 or enemy.hit_flash > 0.0 or enemy.boss_enraged:
			var tint := enemy.modulate * enemy.body_sprite.modulate
			data[i + 8] = tint.r; data[i + 9] = tint.g; data[i + 10] = tint.b; data[i + 11] = tint.a
		else:
			data[i + 8] = 1.0; data[i + 9] = 1.0; data[i + 10] = 1.0; data[i + 11] = 1.0
		data[i + 12] = uv[0]; data[i + 13] = uv[1]; data[i + 14] = uv[2]; data[i + 15] = uv[3]
		used += 1
		if shadowed:
			if (_shadow_used + 1) * STRIDE > shadow_capacity:
				_shadow_data.resize(maxi(SHADOW_MIN_CAPACITY, nearest_po2(_shadow_used + 1)) * STRIDE)
				shadow_capacity = _shadow_data.size()
			var reach := radius * shadow_grow * grow * 2.0
			var s := _shadow_used * STRIDE
			_shadow_data[s] = reach; _shadow_data[s + 1] = 0.0; _shadow_data[s + 2] = 0.0
			_shadow_data[s + 3] = at.x + shadow_offset.x * radius * grow
			_shadow_data[s + 4] = 0.0; _shadow_data[s + 5] = reach * shadow_squash; _shadow_data[s + 6] = 0.0
			_shadow_data[s + 7] = at.y + shadow_offset.y * radius * grow
			_shadow_data[s + 8] = shadow_ink.r; _shadow_data[s + 9] = shadow_ink.g
			_shadow_data[s + 10] = shadow_ink.b; _shadow_data[s + 11] = 1.0
			_shadow_data[s + 12] = shadow_uv[0]; _shadow_data[s + 13] = shadow_uv[1]
			_shadow_data[s + 14] = shadow_uv[2]; _shadow_data[s + 15] = shadow_uv[3]
			_shadow_used += 1
		if not barred and not enemy.telegraphing:
			_band_used[band] = used
			continue
		var origin := Vector2(at.x, origin_y)
		var local := Vector2(at.x, local_y)
		if barred:
			health_ratio = clampf(health_ratio, 0.0, 1.0)
			var bar := local + Vector2(0.0, (-radius - 8.0) * grow)
			var bar_width := radius * 2.0 * grow
			_put(data, used, Vector2(bar_width, 0.0), Vector2(0.0, 4.0 * grow), bar, BAR_BACK, block_uv)
			_put(data, used + 1, Vector2(bar_width * health_ratio, 0.0), Vector2(0.0, 4.0 * grow),
				bar + Vector2(-bar_width * 0.5 * (1.0 - health_ratio), 0.0), BAR_FILL, block_uv)
			used += 2
		if enemy.elite:
			var ring := (radius + 7.0) * 2.0 * grow
			for side in 2:
				var facing := Vector2.from_angle(enemy.rotation + PI * side)
				_put(data, used, facing * ring, facing.orthogonal() * ring, local, ELITE_RING, _regions["_arc65"])
				used += 1
		_band_used[band] = used
		if enemy.telegraphing:
			_warn(enemy, origin, grow)
	_draw_shots(cull)
	drawn_bodies = body_count
	drawn_instances = 0
	drawn_bands = 0
	for band in _bands.size():
		var layer := _bands[band]
		var used := _band_used[band] if band < band_total else 0
		layer.visible = used > 0
		if used <= 0:
			continue
		drawn_instances += used
		drawn_bands += 1
		layer.position = Vector2(0.0, float(first_band + band) * BAND + BAND * 0.5)
		_upload(layer, _band_data[band], used)
	drawn_warnings = _warning_used
	_shadows.visible = _shadow_used > 0
	if _shadow_used > 0:
		_upload(_shadows, _shadow_data, _shadow_used)
	_warnings.visible = _warning_used > 0
	if _warning_used > 0:
		_upload(_warnings, _warning_data, _warning_used)


## Enemy shots, which EnemyProjectile._draw used to paint as three shapes each —
## a late field keeps several hundred in the air. Appended after the telegraphs
## on the warning layer (see threats_on_top), so a shot also reads over the aim
## line that announced it.
const SHOT_GLOW := Color(1.0, 0.25, 0.35, 0.2)
const SHOT_CORE := Color("ff5d8f")
const SHOT_PEBBLE := Color("f5c995")


func _draw_shots(cull: Rect2) -> void:
	var disc: PackedFloat32Array = _regions["_disc"]
	for candidate in shots:
		if not is_instance_valid(candidate):
			continue
		var shot := candidate as Node2D
		if shot == null or shot.is_queued_for_deletion():
			continue
		if shot.visible == enabled:
			shot.visible = not enabled
		if not enabled:
			continue
		var at := shot.position
		if not cull.has_point(at):
			continue
		var facing := Vector2.from_angle(shot.rotation)
		if threats_on_top:
			_warning_used = _grow_put(false, Vector2(20.0, 0.0), Vector2(0.0, 20.0), at, SHOT_GLOW, disc)
			_warning_used = _grow_put(false, Vector2(12.0, 0.0), Vector2(0.0, 12.0), at, SHOT_CORE, disc)
			_warning_used = _grow_put(false, facing * 9.0, facing.orthogonal() * 8.0, at + facing * 0.5, SHOT_PEBBLE, disc)
		else:
			_shadow_used = _grow_put(true, Vector2(20.0, 0.0), Vector2(0.0, 20.0), at, SHOT_GLOW, disc)
			_shadow_used = _grow_put(true, Vector2(12.0, 0.0), Vector2(0.0, 12.0), at, SHOT_CORE, disc)
			_shadow_used = _grow_put(true, facing * 9.0, facing.orthogonal() * 8.0, at + facing * 0.5, SHOT_PEBBLE, disc)


## The warnings enemy._draw used to paint, as instances on the overlay.
func _warn(enemy: ChaserEnemy, origin: Vector2, grow: float) -> void:
	var radius := enemy.radius
	var heading := Vector2.from_angle(enemy.rotation)
	if enemy.charge_windup > 0.0:
		var alpha := 0.25 + sin(enemy.charge_windup * 34.0) * 0.12
		if enemy.archetype == "rat_runner":
			var disc := (radius + 12.0) * 2.0 * grow
			_warning_used = _grow_put(false, Vector2(disc, 0.0), Vector2(0.0, disc), origin, Color(1.0, 0.55, 0.15, alpha), _regions["_disc"])
			var arc := (radius + 16.0) * 2.0 * grow
			_warning_used = _grow_put(false, heading * arc, heading.orthogonal() * arc, origin, Color("ffbf69"), _regions["_arc100"])
		else:
			_line(origin, origin + enemy.telegraph_direction * 240.0 * grow, 12.0 * grow, Color(1.0, 0.25, 0.2, alpha), _regions["_block"])
	if enemy.shooter_windup > 0.0:
		_line(origin, origin + enemy.telegraph_direction * 320.0 * grow, 3.0 * grow, Color(1.0, 0.35, 0.42, 0.8), _regions["_dash"])
		if enemy.archetype == "owl":
			for angle: float in [-0.32, 0.32]:
				_line(origin, origin + enemy.telegraph_direction.rotated(angle) * 320.0 * grow, 2.0 * grow,
					Color(1.0, 0.55, 0.25, 0.6), _regions["_dash"])
	if enemy.chain_windup > 0.0:
		var ring := (radius + 14.0) * 2.0 * grow
		_warning_used = _grow_put(false, Vector2(ring, 0.0), Vector2(0.0, ring), origin, Color("ff5d8f"), _regions["_ring"])


func _line(from: Vector2, to: Vector2, thickness: float, color: Color, uv: PackedFloat32Array) -> void:
	var along := to - from
	var across := along.orthogonal().normalized() * thickness
	_warning_used = _grow_put(false, along, across, (from + to) * 0.5, color, uv)


## Appends to the shadow (true) or warning (false) buffer, growing it as needed.
func _grow_put(shadow: bool, x_axis: Vector2, y_axis: Vector2, origin: Vector2, color: Color, uv: PackedFloat32Array) -> int:
	var data := _shadow_data if shadow else _warning_data
	var used := _shadow_used if shadow else _warning_used
	if (used + 1) * STRIDE > data.size():
		var minimum := SHADOW_MIN_CAPACITY if shadow else WARNING_MIN_CAPACITY
		data.resize(maxi(minimum, nearest_po2(used + 1)) * STRIDE)
		if shadow:
			_shadow_data = data
		else:
			_warning_data = data
	_put(data, used, x_axis, y_axis, origin, color, uv)
	return used + 1


static func _put(data: PackedFloat32Array, index: int, x_axis: Vector2, y_axis: Vector2, origin: Vector2, color: Color, uv: PackedFloat32Array) -> void:
	var i := index * STRIDE
	data[i] = x_axis.x; data[i + 1] = y_axis.x; data[i + 2] = 0.0; data[i + 3] = origin.x
	data[i + 4] = x_axis.y; data[i + 5] = y_axis.y; data[i + 6] = 0.0; data[i + 7] = origin.y
	data[i + 8] = color.r; data[i + 9] = color.g; data[i + 10] = color.b; data[i + 11] = color.a
	data[i + 12] = uv[0]; data[i + 13] = uv[1]; data[i + 14] = uv[2]; data[i + 15] = uv[3]


## Sends `used` instances. The buffer is sized in whole capacities, so the
## instance count only changes when a layer outgrows the one it had.
static func _upload(layer: MultiMeshInstance2D, data: PackedFloat32Array, used: int) -> void:
	var multimesh := layer.multimesh
	var capacity := data.size() >> 4 # STRIDE is 16 floats.
	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), data)
	multimesh.visible_instance_count = used


## Hands every body back to its own node — used when the renderer is switched
## off, so nothing is left hidden with no one drawing it.
func release_all() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active and not enemy.dead and not enemy.visible:
			enemy.visible = true
			enemy._update_body_facing()
			enemy.queue_redraw()
	for shot in shots:
		if is_instance_valid(shot):
			(shot as Node2D).visible = true
	for layer in _bands:
		layer.visible = false
	for layer in [_shadows, _warnings]:
		if is_instance_valid(layer):
			layer.visible = false


func _ensure_bands(total: int) -> void:
	while _bands.size() < total:
		var layer := _make_layer("CrowdBand%d" % _bands.size())
		stage.add_child(layer)
		_bands.append(layer)
		_band_data.append(PackedFloat32Array())
	_band_used.resize(_bands.size())


func _make_layer(layer_name: String) -> MultiMeshInstance2D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad
	multimesh.custom_aabb = WORLD_BOUNDS
	var layer := MultiMeshInstance2D.new()
	layer.name = layer_name
	layer.multimesh = multimesh
	layer.texture = _atlas
	layer.material = _material
	# The project default is nearest-with-mipmaps. A moving enemy repeatedly
	# crossed mip levels in the runtime atlas and appeared to blink between two
	# silhouettes. Crowd art stays at a stable pixel level instead.
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	layer.visible = false
	return layer


## One texture for the whole crowd, packed at runtime from the same PNGs the
## enemy nodes use, so an archetype's art is still just a file in its folder.
static func _build_shared() -> void:
	if _atlas != null:
		return
	var keys: Array[String] = []
	var directory := DirAccess.open("res://assets/sprites/enemies")
	if directory != null:
		for file in directory.get_files():
			var clean := file.trim_suffix(".import").trim_suffix(".remap")
			if clean.ends_with(".png") and not keys.has(clean.get_basename()):
				keys.append(clean.get_basename())
	keys.sort()
	for shape in SHAPES:
		keys.append(shape)
	var rows := ceili(float(keys.size()) / ATLAS_COLUMNS)
	var atlas_size := Vector2i(CELL * ATLAS_COLUMNS, CELL * rows)
	var image := Image.create_empty(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	for index in keys.size():
		var key := keys[index]
		var art: Image = _shape_image(key) if key.begins_with("_") else _art_image(key)
		if art == null:
			continue
		var cell := Vector2i(index % ATLAS_COLUMNS, floori(float(index) / ATLAS_COLUMNS)) * CELL
		var free := Vector2i(CELL, CELL) - art.get_size()
		var inset := Vector2i(floori(float(free.x) * 0.5), floori(float(free.y) * 0.5))
		image.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), cell + inset)
		var region := Rect2(Vector2(cell + inset) / Vector2(atlas_size), Vector2(art.get_size()) / Vector2(atlas_size))
		# The white block is sampled from its middle only, so mip filtering never
		# reaches the transparent gutter around it.
		if key == "_block":
			region = region.grow(-region.size.x * 0.3)
		_regions[key] = PackedFloat32Array([region.position.x, region.position.y, region.size.x, region.size.y])
	# Do not generate mipmaps for the runtime atlas. With the project's nearest
	# mip filter, perspective scale and camera zoom caused abrupt mip-level swaps
	# that read as whole enemies flickering.
	_atlas = ImageTexture.create_from_image(image)
	_quad = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}"""
	_material = ShaderMaterial.new()
	_material.shader = shader


static func _art_image(key: String) -> Image:
	var texture := EnemyIcons.get_icon(key)
	if texture == null:
		return null
	var art := texture.get_image()
	if art.is_compressed():
		art.decompress()
	art.clear_mipmaps()
	art.convert(Image.FORMAT_RGBA8)
	var longest := maxf(art.get_width(), art.get_height())
	_aspects[key] = Vector2(art.get_width(), art.get_height()) / longest
	var fitted := (Vector2(art.get_width(), art.get_height()) * (CELL_CONTENT / longest)).round()
	art.resize(maxi(1, int(fitted.x)), maxi(1, int(fitted.y)), Image.INTERPOLATE_LANCZOS)
	return art


## The flat shapes: shadow disc, white block, solid disc, ring, two arcs facing
## +X and a dashed strip. Alpha only; colour comes from the instance.
static func _shape_image(key: String) -> Image:
	var size := Vector2i(CELL_CONTENT, 24 if key == "_dash" else CELL_CONTENT)
	var art := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size) * 0.5
	var outer := CELL_CONTENT * 0.5 - 2.0
	for y in size.y:
		for x in size.x:
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := point.distance_to(centre)
			var edge := clampf(outer + 1.0 - distance, 0.0, 1.0)
			var alpha := 0.0
			match key:
				"_shadow":
					var both := 1.0 - (1.0 - SHADOW_OUTER_ALPHA) * (1.0 - SHADOW_INNER_ALPHA)
					alpha = (both if distance <= outer * SHADOW_INNER_SHARE else SHADOW_OUTER_ALPHA) * edge
				"_block":
					alpha = 1.0
				"_disc":
					alpha = edge
				"_ring", "_arc65", "_arc100":
					var inner := outer * (1.0 - RING_THICKNESS)
					alpha = edge * clampf(distance - inner + 1.0, 0.0, 1.0)
					if key != "_ring":
						var half := 0.65 if key == "_arc65" else 1.0
						alpha *= clampf((half - absf((point - centre).angle())) * outer, 0.0, 1.0)
				"_dash":
					var phase := fmod(point.x / float(size.x) * DASH_COUNT, 1.0)
					alpha = 1.0 if phase < 0.5 and absf(point.y - centre.y) < size.y * 0.5 - 2.0 else 0.0
			art.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return art
