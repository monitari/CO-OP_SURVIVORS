class_name MilkPoolRenderer
extends Node2D

## Every milk puddle on the roof, in one draw call.
##
## A puddle was a node that drew itself: a filled 26-point rim, an antialiased
## outline over it, a core disc and five droplets. That is eight canvas commands
## a puddle, and because a polygon, an antialiased line and a circle cannot share
## a batch, most of them were separate draw calls — thirty puddles in a late run
## accounted for a large share of the six hundred draw calls the weapon layer was
## issuing (tests/perf_bench_capture.gd, BENCH_LAYERS=1).
##
## The shape is simple enough to describe in a fragment shader, so it is: each
## puddle is one instance of a quad in a MultiMesh, and the shader finds the
## wobbling rim, the fill, the core and the droplets per pixel, antialiased with
## its own derivatives. The puddle nodes still exist — they own the damage, the
## lifetime and the light — but they no longer draw; this reads them each frame
## the way ProjectileRenderer reads the shots.

## The quad reaches this far past the nominal radius, so the rim's widest wobble
## (+14%) and its outline stay inside it.
const MARGIN := 1.18
const STRIDE := 16
const MIN_CAPACITY := 32
const WORLD_BOUNDS := AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
## The puddle's outline, in world units, as MilkPool drew it.
const RIM_WIDTH := 3.0

static var _quad: ArrayMesh
static var _material: ShaderMaterial

var controller: Node
var _layer: MultiMeshInstance2D
var _data := PackedFloat32Array()
## Last frame's count, for tests and the profiler.
var drawn := 0


func _ready() -> void:
	_build_shared()
	# Where every puddle node used to sit: on the floor, under the cats.
	z_index = -1
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad
	multimesh.custom_aabb = WORLD_BOUNDS
	_layer = MultiMeshInstance2D.new()
	_layer.name = "Puddles"
	_layer.multimesh = multimesh
	_layer.material = _material
	_layer.visible = false
	add_child(_layer)


func _process(_delta: float) -> void:
	var probe_started := FrameProbe.mark()
	refresh()
	FrameProbe.add(&"render_milk", probe_started)


## Rebuilds the batch from the controller's live puddles.
func refresh() -> void:
	if controller == null:
		return
	var used := 0
	for child in controller.get_children():
		var pool := child as MilkPool
		if pool == null or not pool.batched or pool.is_queued_for_deletion() or not pool.visible:
			continue
		if _data.size() < (used + 1) * STRIDE:
			_data.resize(maxi(MIN_CAPACITY, nearest_po2(used + 1)) * STRIDE)
		var reach := pool.pool_radius * pool.scale.x
		var half := reach * MARGIN
		# Siblings under the same controller, so local positions share a space.
		var at := pool.position
		var tint := pool.tint
		var i := used * STRIDE
		_data[i] = half * 2.0; _data[i + 1] = 0.0; _data[i + 2] = 0.0; _data[i + 3] = at.x
		_data[i + 4] = 0.0; _data[i + 5] = half * 2.0; _data[i + 6] = 0.0; _data[i + 7] = at.y
		_data[i + 8] = tint.r; _data[i + 9] = tint.g; _data[i + 10] = tint.b; _data[i + 11] = pool.modulate.a
		_data[i + 12] = pool.splash_seed; _data[i + 13] = RIM_WIDTH / maxf(1.0, reach); _data[i + 14] = 0.0; _data[i + 15] = 0.0
		used += 1
	drawn = used
	_layer.visible = used > 0
	if used <= 0:
		return
	var multimesh := _layer.multimesh
	var capacity := _data.size() >> 4 # STRIDE is 16 floats.
	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _data)
	multimesh.visible_instance_count = used


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
	var shader := Shader.new()
	# The layers and their order are MilkPool's: a pale fill, a brighter core, five
	# droplets, and the outline over the fill's edge. Every alpha below is the
	# one MilkPool drew with, and the instance alpha is its fade.
	shader.code = """
shader_type canvas_item;
varying vec4 tint;
varying float splash_seed;
varying float rim_half;
const float MARGIN = %f;

void vertex() {
	tint = COLOR;
	splash_seed = INSTANCE_CUSTOM.x;
	rim_half = INSTANCE_CUSTOM.y * 0.5;
}

vec3 lighten(vec3 c, float amount) {
	return c + (vec3(1.0) - c) * amount;
}

vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	return vec4((top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / a, a);
}

// Every shape here is a distance field whose gradient is about one, so they all
// share the antialiasing width of r itself. Taking fwidth per shape instead
// broke at the droplet band's edge, where the droplet distance is computed
// on one side and bounded on the other and the derivative across the seam is
// meaningless; r is continuous everywhere.
float coverage(float signed_distance, float aa) {
	return 1.0 - smoothstep(-aa, aa, signed_distance);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * MARGIN;
	float r = length(p);
	// A fifth of every quad is corner the puddle never reaches (the rim wobbles
	// out to 1.14 at most). Thirty large puddles overlap a great deal, so the
	// cheapest pixel is the one that leaves before any trigonometry.
	if (r > 1.14 + rim_half + 0.02) {
		discard;
	}
	float aa = max(fwidth(r), 1e-4);
	float angle = atan(p.y, p.x);
	float wobble = 1.0 + sin(angle * 3.0 + splash_seed) * 0.09 + sin(angle * 5.0 - splash_seed) * 0.05;
	float rim_distance = r - wobble;
	vec4 colour = vec4(tint.rgb, 0.30 * coverage(rim_distance, aa));
	colour = over(vec4(lighten(tint.rgb, 0.25), 0.22 * coverage(r - 0.46, aa)), colour);
	// Droplets sit on a ring at 0.72 with radius 0.09, so nothing outside 0.82
	// or inside 0.62 can be one — skip the loop there. The fallback is the
	// distance to that ring, a continuous lower bound, so the derivative the
	// antialiasing takes does not jump at the edge of the band.
	float droplet = abs(r - 0.72) - 0.09;
	if (abs(r - 0.72) < 0.1) {
		droplet = 1e6;
		for (int index = 0; index < 5; index++) {
			float a = splash_seed + TAU * float(index) / 5.0;
			droplet = min(droplet, length(p - vec2(cos(a), sin(a)) * 0.72) - 0.09);
		}
	}
	colour = over(vec4(lighten(tint.rgb, 0.4), 0.45 * coverage(droplet, aa)), colour);
	colour = over(vec4(lighten(tint.rgb, 0.35), 0.7 * coverage(abs(rim_distance) - rim_half, aa)), colour);
	COLOR = vec4(colour.rgb, colour.a * tint.a);
}
""" % MARGIN
	_material = ShaderMaterial.new()
	_material.shader = shader
