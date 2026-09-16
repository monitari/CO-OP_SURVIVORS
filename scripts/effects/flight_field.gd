class_name FlightField
extends Node2D
## What an attack leaves on the floor it is travelling over.
##
## Once weapons have heights, two of them can be drawn in the same place on
## screen and mean completely different things — a puddle lying on the roof and
## a star passing above it are both a bright shape at the same pixel. What tells
## them apart is the floor: the star throws a small shadow that runs along under
## it and flashes the roof where it lands, and the puddle has neither because it
## is already on the ground.
##
## Both of those are per-frame, per-shot marks on a surface that the shots do
## not own, so they are drawn here rather than by each projectile. This is the
## third field node in the game built on the same reasoning as BurstField and
## ParticleField: at a few hundred simultaneous shots a node and a tween each is
## a stall, while one array and one `_draw` is not.
##
## Two canvases, and the split is the usual one. Shadows are dark and belong to
## the floor's own blending; the landing flash is light being *added* to the
## roof, so it rides on a GlowLayer above. Nothing here affects play.

## How long a landing mark stays on the roof. Short: it is punctuation for a hit
## that has already been resolved, not a field anybody has to read.
const FLASH_LIFE := 0.26
const MAX_FLASHES := 90

## Airborne things whose shadows this draws: {node, height, radius}.
var flyers: Array = []
var flashes: Array = []
var glow: GlowLayer

## Every shadow in one draw call. A shadow is footing()'s three stacked discs;
## drawn per shot that was three re-tessellated circles each frame, and with two
## thousand shots in the air those were most of the frame (see the projectile
## report). The discs are three channels of one small mask and the shader
## composites them exactly as the circles did, with each shot's own fade.
const SHADOW_STRENGTH := 0.85
const SHADOW_DISCS := [1.2, 0.86, 0.5]
const SHADOW_ALPHAS := [0.20, 0.28, 0.30]
static var _shadow_texture: ImageTexture
static var _shadow_material: ShaderMaterial
static var _quad: ArrayMesh
var _shadow_mesh: MultiMesh
var _shadow_data := PackedFloat32Array()
## Set false before _ready to draw each shadow with footing() again, for comparison.
var batched := true


func _ready() -> void:
	# Under the actors and over the paving. A shot's shadow is on the floor, and
	# a shadow drawn over a cat would read as the shot itself.
	z_index = -3
	glow = GlowLayer.attach(self, _draw_flashes, 1)
	if batched:
		_build_shadow_shared()
		material = _shadow_material
		_shadow_mesh = MultiMesh.new()
		_shadow_mesh.transform_format = MultiMesh.TRANSFORM_2D
		_shadow_mesh.use_colors = true
		_shadow_mesh.mesh = _quad
		# See CrowdRenderer.WORLD_BOUNDS: a stale cull rectangle hides the batch.
		_shadow_mesh.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))


## Starts drawing a shadow under `shot` until it stops being visible.
##
## Typed to the projectile rather than to any Node2D on purpose: what this needs
## is the point on the *roof* the thing is flying over, and a projectile is the
## one kind of node that carries that separately from where it is drawn. Working
## it back out of a drawn position stopped being possible the moment the floor
## gained a perspective.
## Where the next eviction writes once the mark list is full; see flash().
var _replace_at := 0


func track(shot: HomingProjectile) -> void:
	if shot == null or shot.flight_height <= 0.0 or not is_instance_valid(shot):
		return
	flyers.append({"shot": shot, "radius": shot.radius})


## A shot landed here. The mark goes on the roof at the floor point, never at
## the point the shot was drawn at — the whole job of this mark is to say which
## piece of floor the hit belongs to.
func flash(at: Vector2, color: Color, radius := 26.0) -> void:
	# Overwritten in place rather than shifted out of the front. A volley can
	# expire all at once -- every flame shot of a nova landing on the same tick
	# -- and pop_front made each of those marks cost the length of the list.
	if flashes.size() >= MAX_FLASHES:
		if _replace_at >= flashes.size():
			_replace_at = 0
		flashes[_replace_at] = {"at": at, "color": color, "radius": radius, "age": 0.0}
		_replace_at += 1
		return
	flashes.append({"at": at, "color": color, "radius": radius, "age": 0.0})


func step(delta: float) -> void:
	# Compacted in place: rebuilding the list every tick allocated a new array
	# the size of everything in the air.
	var kept := 0
	for flyer in flyers:
		# Deliberately untyped until it has been checked. A shot may be pooled
		# (retired by being hidden) or freed outright, and assigning a freed
		# instance to a typed local is an error rather than a null — so the
		# validity check has to come before the type does.
		var node = flyer["shot"]
		if is_instance_valid(node) and (node as Node2D).visible:
			flyers[kept] = flyer
			kept += 1
	flyers.resize(kept)
	var burning: Array = []
	for mark in flashes:
		mark["age"] = float(mark["age"]) + delta
		if float(mark["age"]) < FLASH_LIFE:
			burning.append(mark)
	flashes = burning
	_replace_at = 0
	queue_redraw()
	if glow != null:
		glow.queue_redraw()


func clear_all() -> void:
	flyers.clear()
	flashes.clear()
	_replace_at = 0
	queue_redraw()
	if glow != null:
		glow.queue_redraw()


func _draw() -> void:
	if batched and _shadow_mesh != null:
		_draw_shadow_batch()
		return
	for flyer in flyers:
		var node = flyer["shot"]
		if not is_instance_valid(node):
			continue
		var shot := node as HomingProjectile
		# The shadow is a mark on the floor, so it goes where the floor point
		# projects to and is sized by how far away that is — the same treatment
		# every other footprint on this roof gets.
		var scale := RooftopSpace.view_scale(shot.ground_position.y)
		RooftopSpace.footing(self, RooftopSpace.project(shot.ground_position),
			float(flyer["radius"]) * scale, shot.flight_height * scale, 0.85)


func _draw_shadow_batch() -> void:
	if not Moonlight.enabled or flyers.is_empty():
		return
	if _shadow_data.size() < flyers.size() * 12:
		_shadow_data.resize(maxi(64, nearest_po2(flyers.size())) * 12)
	var data := _shadow_data
	var ink := Moonlight.SHADOW_INK
	var squash := Moonlight.SHADOW_SQUASH
	var span := float(SHADOW_DISCS[0]) * 2.0
	var used := 0
	for flyer in flyers:
		var node = flyer["shot"]
		if not is_instance_valid(node):
			continue
		var shot := node as HomingProjectile
		# The same numbers RooftopSpace.footing() works out for this shadow.
		var ground := shot.ground_position
		var view := RooftopSpace.view_scale(ground.y)
		var radius := float(flyer["radius"]) * view
		var height := shot.flight_height * view
		var spread := 1.0 + height * 0.008
		var fade := SHADOW_STRENGTH / (1.0 + height * 0.008)
		var centre := RooftopSpace.footing_centre(RooftopSpace.project(ground), radius, height)
		var i := used * 12
		data[i] = radius * span * spread; data[i + 1] = 0.0; data[i + 2] = 0.0; data[i + 3] = centre.x
		data[i + 4] = 0.0; data[i + 5] = radius * span * squash * spread; data[i + 6] = 0.0; data[i + 7] = centre.y
		data[i + 8] = ink.r; data[i + 9] = ink.g; data[i + 10] = ink.b; data[i + 11] = fade
		used += 1
	var capacity := data.size() / 12
	if _shadow_mesh.instance_count != capacity:
		_shadow_mesh.instance_count = capacity
	RenderingServer.multimesh_set_buffer(_shadow_mesh.get_rid(), data)
	_shadow_mesh.visible_instance_count = used
	draw_multimesh(_shadow_mesh, _shadow_texture)


static func _build_shadow_shared() -> void:
	if _shadow_texture != null:
		return
	_quad = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var size := 96
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var middle := Vector2(size, size) * 0.5
	var per_unit := (float(size) * 0.5 - 1.0) / float(SHADOW_DISCS[0])
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(middle) / per_unit
			image.set_pixel(x, y, Color(
				clampf((float(SHADOW_DISCS[0]) - distance) * per_unit + 0.5, 0.0, 1.0),
				clampf((float(SHADOW_DISCS[1]) - distance) * per_unit + 0.5, 0.0, 1.0),
				clampf((float(SHADOW_DISCS[2]) - distance) * per_unit + 0.5, 0.0, 1.0)))
	image.generate_mipmaps()
	_shadow_texture = ImageTexture.create_from_image(image)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec3 discs = texture(TEXTURE, UV).rgb;
	float f = tint.a;
	float clear = (1.0 - %f * f * discs.r) * (1.0 - %f * f * discs.g) * (1.0 - %f * f * discs.b);
	COLOR = vec4(tint.rgb, 1.0 - clear);
}""" % [SHADOW_ALPHAS[0], SHADOW_ALPHAS[1], SHADOW_ALPHAS[2]]
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = shader


func _draw_flashes(canvas: CanvasItem) -> void:
	for mark in flashes:
		var progress := clampf(float(mark["age"]) / FLASH_LIFE, 0.0, 1.0)
		var fade := 1.0 - progress
		var ground: Vector2 = mark["at"]
		var at := RooftopSpace.project(ground)
		# Flattened along the light the same way every other footprint on this
		# roof is, so a landing reads as light thrown across the floor rather
		# than as a ball of light hanging over it.
		canvas.draw_set_transform(at, 0.0, Vector2(1.0, Moonlight.SHADOW_SQUASH))
		var reach := float(mark["radius"]) * (0.45 + progress * 0.85) * RooftopSpace.view_scale(ground.y)
		canvas.draw_circle(Vector2.ZERO, reach, Moonlight.glow(mark["color"] as Color, 0.22 * fade))
		canvas.draw_circle(Vector2.ZERO, reach * 0.45, Moonlight.glow(Color.WHITE, 0.2 * fade))
		canvas.draw_set_transform(Vector2.ZERO)
