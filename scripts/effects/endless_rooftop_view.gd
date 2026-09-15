class_name EndlessRooftopView
extends Node
## A gently tilted battlefield, rendered with overscan. Simulation nodes retain
## their original ground coordinates; HUD and menus stay on the main viewport.
##
## The whole battlefield is drawn into an off-screen buffer and then read back
## through the perspective mapping, which means every pixel on screen has been
## resampled once. Three separate things decide whether that resample looks
## like a tilted roof or like a smeared, crawling one, and all three live here.
##
## **Resolution.** The source buffer has to be measured in the window's real
## pixels, not in the project's authored 1280x720 units. With the canvas_items
## stretch mode those units are the same number on a small window and on a
## maximised one, so a buffer sized from them is magnified by the difference
## before it ever reaches the screen — the single largest source of softness
## this view had, and invisible at the authored size where it is developed.
##
## **Density.** SUPERSAMPLE is how many source texels the sparsest point on
## screen gets per output pixel. Below one the mapping is inventing detail it
## was never given and the picture goes soft; the shader's own filter can clean
## up an excess but it cannot recover a shortfall, so this number's job is to
## make sure there is never a shortfall anywhere.
##
## **Filtering.** A SubViewport texture has no mip chain and Godot cannot build
## one for it, so there is no cheaper level for the minified half of the screen
## to fall back on. The shader measures its own footprint instead and filters
## across exactly that — see endless_rooftop.gdshader.
##
## And one thing that does not live here: the camera. A resample is stable only
## if the thing being resampled holds still against the source texel grid, so
## whoever drives the camera rounds it onto that grid — snap_to_source_texels.

## How much floor, measured in screens, the source buffer has to hold for the
## projection to find something to read at every corner.
##
## Both numbers fall straight out of the mapping in the shader, with a little
## over for the filter's taps to reach into. Horizontally the widest row is the
## far one, 0.5 / (1 - PERSPECTIVE * 0.5 / TILT) of a screen either side of the
## middle; vertically the reach is 0.5 / (TILT - PERSPECTIVE * 0.5), the far
## edge again, which is the further of the two because the taper lifts it.
## Anything larger than this is not extra safety — it is source resolution spent
## on floor the shader will never sample. Guarded by endless_rooftop_test.
const OVERSCAN := Vector2(1.14, 1.33)
## Source texels per output pixel where the projection is at its sparsest, which
## is the near edge on both axes. The rest of the screen gets more than this and
## the shader filters the excess back down; the point of the number is that
## nothing anywhere gets less than one.
const SUPERSAMPLE := 1.15
## A ceiling on the source buffer, because SUPERSAMPLE multiplies a window size
## and a window can be very large. Sized so a 1080p window still gets its full
## density and only larger ones start trading it away.
const MAX_SOURCE_PIXELS := 5_000_000
const TILT := 0.86
const PERSPECTIVE := 0.18
const ViewShader := preload("res://scripts/effects/endless_rooftop.gdshader")
var surface: SubViewport
var world: Node2D
var display: TextureRect
var view_size := Vector2(1280, 720)


func _ready() -> void:
	surface = SubViewport.new()
	surface.disable_3d = true
	# Mipmapped, and this is the battlefield's single biggest readability
	# setting. The art is authored at four hundred to twelve hundred pixels and
	# a swarm rat is drawn about twenty-four pixels across — a minification of
	# fifteen or twenty to one. Without a mip chain each of those pixels is one
	# arbitrarily chosen texel out of hundreds, and a different one every frame
	# the rat moves, which is a crawling shimmer that no amount of work on the
	# projection downstream can undo. With one, the same rat is a filtered
	# average that holds still. See the mipmaps/generate flags on the imports.
	surface.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.handle_input_locally = false
	add_child(surface)
	world = Node2D.new()
	world.name = "Battlefield"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	surface.add_child(world)
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	display = TextureRect.new()
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# The mapping keeps every tap inside the overscan, but the filter's taps
	# reach a fraction of a texel past it right at the corners. Clamping is what
	# they land on there; a repeating sampler would wrap the far edge of the
	# roof back onto the near one.
	display.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	display.texture = surface.get_texture()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = ViewShader
	# Pushed rather than left to the shader's own defaults, so the projection
	# the picture is drawn with and the one project_offset inverts can never
	# drift into being two different projections.
	shader_material.set_shader_parameter("overscan", OVERSCAN)
	shader_material.set_shader_parameter("tilt", TILT)
	shader_material.set_shader_parameter("perspective", PERSPECTIVE)
	display.material = shader_material
	layer.add_child(display)
	get_viewport().size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	view_size = get_viewport().get_visible_rect().size
	surface.size = source_size(view_size, content_pixels())
	# The buffer is measured in real pixels but has to keep *thinking* in the
	# authored ones, or the camera would show a maximised window more of the
	# roof than a small one and the framing would depend on the window. The
	# override is the split: everything inside the battlefield — the camera's
	# zoom above all — goes on working in authored units while the buffer under
	# it is as dense as the display can actually use.
	surface.size_2d_override = Vector2i((view_size * OVERSCAN).ceil())
	surface.size_2d_override_stretch = true
	display.size = view_size


func _process(_delta: float) -> void:
	# Freeze the rendered battlefield too, including shader TIME animations.
	surface.render_target_update_mode = SubViewport.UPDATE_DISABLED if get_tree().paused else SubViewport.UPDATE_ALWAYS
	# Planters used to be re-faced here by walking every node in the "enemies"
	# group each frame. CrowdRenderer computes every body's upright correction
	# as it batches the crowd, so there is nothing left to do per body here.


## The window's real pixels behind one screen's worth of authored units. One to
## one on a window opened at the authored size, and the ratio the stretch is
## applying on any other — which is the number the source buffer has to be
## measured in if the picture is not to be magnified on its way to the screen.
func content_pixels() -> Vector2:
	var window := get_window()
	if window == null or view_size.x <= 0.0 or view_size.y <= 0.0:
		return view_size
	var content := Vector2(window.size)
	if content.x <= 0.0 or content.y <= 0.0:
		return view_size
	# The authored aspect is kept, so the stretch is one factor rather than two
	# and it is the smaller of the pair — the other axis is letterboxed away.
	return view_size * minf(content.x / view_size.x, content.y / view_size.y)


## How large the source buffer has to be to hold `pixels` worth of screen at the
## density the projection needs, clamped to the budget. Split out from _resize
## because it is the one piece of this file worth checking without a window.
static func source_size(logical: Vector2, pixels: Vector2) -> Vector2i:
	var wanted := (pixels * OVERSCAN * SUPERSAMPLE).max(logical * OVERSCAN)
	var budget := float(MAX_SOURCE_PIXELS) / maxf(1.0, wanted.x * wanted.y)
	if budget < 1.0:
		wanted *= sqrt(budget)
	return Vector2i(wanted.ceil())


## Source texels per world unit at this zoom. The camera works in authored units
## and the buffer is denser than that by whatever the override is hiding, so the
## two have to be multiplied together to get at the grid that actually exists.
func texel_density(zoom: Vector2) -> Vector2:
	var logical := Vector2(surface.size_2d_override)
	if logical.x <= 0.0 or logical.y <= 0.0:
		return zoom
	return zoom * Vector2(surface.size) / logical


## Where a camera may sit without dragging the source texel grid out from under
## the projection.
##
## The mapping from source texel to screen pixel is fixed — it depends on where
## on the screen a pixel is and on nothing else. So the only thing that can make
## a still picture crawl is the world sliding across the source grid by
## fractions of a texel, and rounding the camera onto whole texels stops that
## dead. One texel is a fraction of a world unit at these zooms, which is why
## the rounding is invisible: the step it quantises movement to is the same one
## pixel the movement was going to be drawn at anyway.
func snap_to_source_texels(at: Vector2, zoom: Vector2) -> Vector2:
	var texels := texel_density(zoom)
	if texels.x <= 0.0 or texels.y <= 0.0:
		return at
	return (at * texels).round() / texels


func adopt(node: Node) -> void:
	node.reparent(world, true)


## Forward/inverse of the shader mapping, in logical screen pixels.
func project_offset(offset: Vector2) -> Vector2:
	var p := offset / view_size
	var scale_at_depth := 1.0 / (1.0 - PERSPECTIVE * p.y)
	return Vector2(p.x, p.y * TILT) * scale_at_depth * view_size


func unproject_offset(offset: Vector2) -> Vector2:
	var p := offset / view_size
	return Vector2(p.x / (1.0 + PERSPECTIVE * p.y / TILT),
		p.y / (TILT + PERSPECTIVE * p.y)) * view_size


func visible_bounds(centre: Vector2, zoom: Vector2) -> Rect2:
	var half := view_size * 0.5
	var bounds := Rect2(centre + unproject_offset(-half) / zoom, Vector2.ZERO)
	for corner in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		bounds = bounds.expand(centre + unproject_offset(corner) / zoom)
	return bounds
