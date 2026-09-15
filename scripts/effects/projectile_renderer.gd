extends Node2D
## Draws every friendly projectile in two batches: one MultiMesh for the bodies
## and one additive MultiMesh for their glow.
##
## A star drew seven shapes from its own node and an ember four, plus a GlowLayer
## child each, so a thousand shots cost 7,500 draw calls and a frame took 17ms
## before the simulation had done anything (docs/projectile-performance-2026-09-15.md).
## CrowdRenderer already solved the same problem for enemies; this is that
## approach for the player's shots.
##
## The silhouettes are not redrawn by hand. HomingProjectile's own painters draw
## them once into an atlas through a SubViewport, split into mask layers by
## colour family (base, hot core, trailing flame; two glow discs). The shader
## puts each family's colour back from the instance colour, so a shot looks like
## the node drawing, keeps its per-shot seed variation (16 variants), rotation,
## scale, fade and height, and shots stay in their creation order — the order the
## nodes drew in. The glow instance sits one z-step below the bodies, where each
## node's GlowLayer used to sit.

const ProjectileScript := preload("res://scripts/entities/projectile.gd")

## World-space rectangle one atlas cell covers around a shot's origin, for the
## largest baked radius. Every star, ember and bolt part fits inside with margin.
const LEFT := -46.0
const RIGHT := 26.0
const HALF_HEIGHT := 19.0
const BAKE_SCALE := 2.0
const VARIANTS := 16
const BAKED_RADII := [8.0, 9.0]
## Rows per baked radius: star base/hot/glowA/glowB, ember base/hot/trail/glowA/glowB, bolt.
const ROWS_PER_RADIUS := 10
const STAR_ROW := 0
const EMBER_ROW := 4
const BOLT_ROW := 9
const STYLE_STAR := 0.0
const STYLE_EMBER := 1.0
const STYLE_BOLT := 2.0
const STRIDE := 16
const MIN_CAPACITY := 256
## A 2D MultiMesh layer is culled against the rectangle its instances covered
## when its draw command was first built; uploading new instance data later does
## not refresh that rectangle. Instances that have since moved outside it — the
## crowd and its shots after the pair has walked across the endless roof — were
## culled with the whole layer: invisible, still moving, still hitting. Every
## batch layer therefore declares bounds covering the whole world.
const WORLD_BOUNDS := AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))

static var _atlas: Texture2D
static var _atlas_ready := false
static var _quad: ArrayMesh
static var _body_material: ShaderMaterial
static var _glow_material: ShaderMaterial
static var _baker: SubViewport

var controller: Node
var _body: MultiMeshInstance2D
var _glow: MultiMeshInstance2D
var _body_data := PackedFloat32Array()
var _glow_data := PackedFloat32Array()
## Last frame's counts, for tests and the profiler.
var drawn_shots := 0
var drawn_glows := 0


static func cell_width() -> float:
	return RIGHT - LEFT


static func cell_height() -> float:
	return HALF_HEIGHT * 2.0


static func atlas_columns() -> int:
	return VARIANTS


static func atlas_rows() -> int:
	return ROWS_PER_RADIUS * BAKED_RADII.size()


func _ready() -> void:
	_build_shared()
	_ensure_baked(self)
	_body = _make_layer("ProjectileBodies", _body_material)
	add_child(_body)
	_glow = _make_layer("ProjectileGlow", _glow_material)
	# Where every shot's GlowLayer used to sit: one z-step under its body.
	_glow.z_index = -1
	add_child(_glow)


func _process(_delta: float) -> void:
	refresh()


## Rebuilds both batches from the controller's shots. Public so a paused capture
## or a test can force the picture to match the simulation.
func refresh() -> void:
	if controller == null:
		return
	if _body.texture != _atlas:
		_body.texture = _atlas
		_glow.texture = _atlas
	var shots: Array = controller.all_projectiles
	var needed := shots.size() * STRIDE
	if _body_data.size() < needed:
		var capacity := maxi(MIN_CAPACITY, nearest_po2(shots.size())) * STRIDE
		_body_data.resize(capacity)
		_glow_data.resize(capacity)
	var glowing := Moonlight.enabled
	var body := _body_data
	var glow := _glow_data
	var used := 0
	var glow_used := 0
	var width := cell_width()
	var height := cell_height()
	var centre_x := (LEFT + RIGHT) * 0.5
	var columns := float(VARIANTS)
	for candidate in shots:
		var shot: HomingProjectile = candidate
		if not shot.active or not shot.visible:
			continue
		var t := shot.transform
		var shot_radius := shot.radius
		var radius_index := 0 if shot_radius < 8.5 else 1
		var grow := shot_radius / float(BAKED_RADII[radius_index])
		var x_axis := t.x * (width * grow)
		var y_axis := t.y * (height * grow)
		var origin := t.origin + t.x * (centre_x * grow)
		var base_row := float(radius_index * ROWS_PER_RADIUS)
		var style_code := STYLE_BOLT
		var column := 0.0
		var row := base_row + BOLT_ROW
		match shot.style:
			"star":
				style_code = STYLE_STAR
				row = base_row + STAR_ROW
				column = _variant(shot.shape_seed)
			"ember":
				style_code = STYLE_EMBER
				row = base_row + EMBER_ROW
				column = _variant(shot.shape_seed)
		var color := shot.projectile_color
		var alpha := shot.modulate.a
		var i := used * STRIDE
		body[i] = x_axis.x; body[i + 1] = y_axis.x; body[i + 2] = 0.0; body[i + 3] = origin.x
		body[i + 4] = x_axis.y; body[i + 5] = y_axis.y; body[i + 6] = 0.0; body[i + 7] = origin.y
		body[i + 8] = color.r; body[i + 9] = color.g; body[i + 10] = color.b; body[i + 11] = alpha
		body[i + 12] = row * columns + column; body[i + 13] = style_code; body[i + 14] = 0.0; body[i + 15] = 0.0
		used += 1
		if glowing and style_code != STYLE_BOLT:
			var glow_row := row + (2.0 if style_code == STYLE_STAR else 3.0)
			var g := glow_used * STRIDE
			glow[g] = x_axis.x; glow[g + 1] = y_axis.x; glow[g + 2] = 0.0; glow[g + 3] = origin.x
			glow[g + 4] = x_axis.y; glow[g + 5] = y_axis.y; glow[g + 6] = 0.0; glow[g + 7] = origin.y
			glow[g + 8] = color.r; glow[g + 9] = color.g; glow[g + 10] = color.b; glow[g + 11] = alpha
			glow[g + 12] = glow_row * columns; glow[g + 13] = style_code; glow[g + 14] = 0.0; glow[g + 15] = 0.0
			glow_used += 1
	drawn_shots = used
	drawn_glows = glow_used
	_upload(_body, body, used)
	_upload(_glow, glow, glow_used)


static func _variant(shot_seed: float) -> float:
	return float(clampi(int(fposmod(shot_seed, TAU) / TAU * VARIANTS), 0, VARIANTS - 1))


## The seed a variant column was baked with: the middle of its slice.
static func variant_seed(column: int) -> float:
	return (float(column) + 0.5) / float(VARIANTS) * TAU


static func _upload(layer: MultiMeshInstance2D, data: PackedFloat32Array, used: int) -> void:
	layer.visible = used > 0
	if used <= 0:
		return
	var multimesh := layer.multimesh
	var capacity := data.size() >> 4 # STRIDE is 16 floats.
	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), data)
	multimesh.visible_instance_count = used


func _make_layer(layer_name: String, layer_material: ShaderMaterial) -> MultiMeshInstance2D:
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
	layer.material = layer_material
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	layer.visible = false
	return layer


static func _build_shared() -> void:
	if _quad != null:
		return
	_quad = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var common := """
uniform vec2 cells = vec2(%d.0, %d.0);
varying vec4 tint;
varying vec2 local_uv;
varying float cell;
varying float style_code;
void vertex() {
	tint = COLOR;
	local_uv = UV;
	cell = INSTANCE_CUSTOM.x;
	style_code = INSTANCE_CUSTOM.y;
}
vec2 layer_uv(float cell_index, vec2 inside, float row_offset) {
	vec2 slot = vec2(mod(cell_index, cells.x), floor(cell_index / cells.x) + row_offset);
	return (slot + inside) / cells;
}
vec3 lighten(vec3 c, float amount) {
	return c + (vec3(1.0) - c) * amount;
}
""" % [atlas_columns(), atlas_rows()]
	var body_shader := Shader.new()
	body_shader.code = "shader_type canvas_item;\n" + common + """
vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}
void fragment() {
	vec3 c = tint.rgb;
	vec4 result = vec4(c, texture(TEXTURE, layer_uv(cell, local_uv, 0.0)).r);
	if (style_code < 0.5) {
		result = over(vec4(lighten(c, 0.65), texture(TEXTURE, layer_uv(cell, local_uv, 1.0)).r), result);
	} else if (style_code < 1.5) {
		result = over(vec4(lighten(c, 0.2), texture(TEXTURE, layer_uv(cell, local_uv, 2.0)).r), result);
		result = over(vec4(lighten(c, 0.7), texture(TEXTURE, layer_uv(cell, local_uv, 1.0)).r), result);
	}
	COLOR = vec4(result.rgb, result.a * tint.a);
}"""
	_body_material = ShaderMaterial.new()
	_body_material.shader = body_shader
	var glow_shader := Shader.new()
	# The GlowLayer used Moonlight's additive CanvasItemMaterial: each disc added
	# its colour scaled by its strength. Same sum here, in one pass.
	glow_shader.code = "shader_type canvas_item;\nrender_mode blend_add;\n" + common + """
void fragment() {
	vec3 c = tint.rgb;
	float first = texture(TEXTURE, layer_uv(cell, local_uv, 0.0)).r;
	float second = texture(TEXTURE, layer_uv(cell, local_uv, 1.0)).r;
	vec3 light = style_code < 0.5
		? c * first * 0.16 + lighten(c, 0.7) * second * 0.32
		: lighten(c, 0.5) * first * 0.28 + c * second * 0.13;
	COLOR = vec4(light, tint.a);
}"""
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = glow_shader


## Draws the atlas once through a SubViewport with the projectile's own painters,
## then, where a GPU read-back is available, swaps in a mipmapped single-channel
## copy so shots stay smooth when the camera zooms out. Headless runs keep the
## viewport texture; nothing is drawn there anyway.
static func _ensure_baked(host: Node) -> void:
	if _atlas != null:
		return
	var cell := Vector2i(roundi(cell_width() * BAKE_SCALE), roundi(cell_height() * BAKE_SCALE))
	_baker = SubViewport.new()
	_baker.name = "ProjectileAtlasBaker"
	_baker.size = Vector2i(cell.x * atlas_columns(), cell.y * atlas_rows())
	_baker.transparent_bg = true
	_baker.disable_3d = true
	_baker.render_target_update_mode = SubViewport.UPDATE_ONCE
	_baker.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var painter := AtlasPainter.new()
	painter.cell = Vector2(cell)
	painter.paint = _paint_atlas
	_baker.add_child(painter)
	# Parked on the root rather than on this renderer: a renderer can be freed
	# (a restart, a test) before the read-back finishes, and the atlas must not
	# go with it.
	host.get_tree().root.add_child.call_deferred(_baker)
	_atlas = _baker.get_texture()
	_read_back.call_deferred()


static func _read_back() -> void:
	if not is_instance_valid(_baker):
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_baker):
		return
	var image := _baker.get_texture().get_image()
	if image != null and not image.is_empty():
		image.convert(Image.FORMAT_R8)
		image.generate_mipmaps()
		_atlas = ImageTexture.create_from_image(image)
		_atlas_ready = true
		_baker.queue_free()
		_baker = null


static func is_atlas_ready() -> bool:
	return _atlas_ready


static func _paint_atlas(canvas: Node2D, cell: Vector2) -> void:
	var layers_per_style := {
		STAR_ROW: ["star", [0, 1], [0, 1]],
		EMBER_ROW: ["ember", [0, 1, 2], [0, 1]],
		BOLT_ROW: ["bolt", [0], []],
	}
	for radius_index in BAKED_RADII.size():
		var shot_radius: float = BAKED_RADII[radius_index]
		for style_row: int in layers_per_style:
			var entry: Array = layers_per_style[style_row]
			var shape: String = entry[0]
			var row := radius_index * ROWS_PER_RADIUS + style_row
			var variants := VARIANTS if shape != "bolt" else 1
			for column in variants:
				for layer: int in entry[1]:
					_cell_origin(canvas, cell, column, row + layer)
					ProjectileScript.paint_body(canvas, shape, shot_radius, Color.WHITE, variant_seed(column), layer)
			for glow_layer: int in entry[2]:
				_cell_origin(canvas, cell, 0, row + (entry[1] as Array).size() + glow_layer)
				ProjectileScript.paint_glow(canvas, shape, shot_radius, Color.WHITE, glow_layer)
	canvas.draw_set_transform(Vector2.ZERO)


static func _cell_origin(canvas: Node2D, cell: Vector2, column: int, row: int) -> void:
	var corner := Vector2(float(column) * cell.x, float(row) * cell.y)
	# The shot's own origin sits -LEFT across and half the height down the cell.
	canvas.draw_set_transform(corner + Vector2(-LEFT, HALF_HEIGHT) * BAKE_SCALE, 0.0, Vector2.ONE * BAKE_SCALE)


class AtlasPainter extends Node2D:
	var cell := Vector2.ZERO
	var paint := Callable()

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self, cell)
