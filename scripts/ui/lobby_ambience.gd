extends Control

## Lightweight menu motion: title breathing, two cats floating in opposite
## phases, and a handful of deterministic stars.

const Polaroid := preload("res://scripts/ui/polaroid.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")

var title_logo: TextureRect
var left_cat: TextureRect
var right_cat: TextureRect
var scrapbook_backdrop: TextureRect
## The two prints the cats are photographed in (scrapbook mode only). The cats
## are their subjects, so a print and its cat move as one piece.
var left_frame: Polaroid
var right_frame: Polaroid
var age := 0.0
var left_origin := Vector2(72.0, 204.0)
var right_origin := Vector2(882.0, 204.0)
var logo_origin := Vector2(190.0, 4.0)
## The tilt each print rests at; the sway is added on top.
var left_tilt := -0.06
var right_tilt := 0.07
var motion_enabled := true
var starfield_enabled := true
var shadows_enabled := true
var scrapbook_enabled := false
var backdrop_origin := Vector2(-48.0, -40.0)

const FILM_SHADER := preload("res://scripts/ui/scrapbook_film.gdshader")
const PRINT_SHADER := preload("res://scripts/ui/scrapbook_print.gdshader")
const FILM_HEIGHT := 22.0

const STARS := [
	Vector2(72, 84), Vector2(164, 52), Vector2(929, 75), Vector2(1017, 132),
	Vector2(44, 306), Vector2(1050, 292), Vector2(332, 324), Vector2(781, 337),
]


func setup(logo_texture: Texture2D, first_cat: Texture2D, second_cat: Texture2D) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_logo = _texture(logo_texture, logo_origin, Vector2(720.0, 330.0))
	title_logo.name = "TitleLogo"
	left_cat = _texture(first_cat, left_origin, Vector2(150.0, 150.0))
	right_cat = _texture(second_cat, right_origin, Vector2(150.0, 150.0))
	left_cat.name = "LeftCat"
	right_cat.name = "RightCat"
	left_cat.pivot_offset = left_cat.size * 0.5
	right_cat.pivot_offset = right_cat.size * 0.5
	title_logo.pivot_offset = title_logo.size * 0.5
	queue_redraw()


## A clean, full-screen scene shared by the title pages and the LAN lobby.
## The overlay itself is inset by (90, 55), so the negative origin aligns the
## art with the authored 1280x720 viewport instead of scaling an inset image.
func setup_backdrop(backdrop_texture: Texture2D) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	motion_enabled = false
	scrapbook_enabled = true
	backdrop_origin = Vector2(-90.0, -55.0)
	scrapbook_backdrop = _texture(backdrop_texture, backdrop_origin, Vector2(1280.0, 720.0))
	scrapbook_backdrop.name = "SceneBackdrop"
	scrapbook_backdrop.set_meta("decorative_overhang", true)
	scrapbook_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	move_child(scrapbook_backdrop, 0)


## Turns the ordinary lobby ornament into the title's layered scrapbook page:
## the collage backdrop, two slow film edges, and the two cats as polaroids
## taped over the night. Every layer is its own CanvasItem, so none of the
## motion has to be baked into a video or one heavyweight texture.
##
## `print_size` is each polaroid's size; `names` their handwritten captions.
func enable_scrapbook(backdrop_texture: Texture2D, print_size: Vector2, names: Array) -> void:
	scrapbook_enabled = true
	scrapbook_backdrop = _texture(backdrop_texture, backdrop_origin, Vector2(1280.0, 720.0))
	scrapbook_backdrop.name = "ScrapbookBackdrop"
	# Bleeds past the page margins to the screen edge (see layout_test).
	scrapbook_backdrop.set_meta("decorative_overhang", true)
	scrapbook_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	move_child(scrapbook_backdrop, 0)
	_add_film_strip("FilmTop", Vector2(-48, -40), Vector2(1280, FILM_HEIGHT))
	_add_film_strip("FilmBottom", Vector2(-48, 680 - FILM_HEIGHT), Vector2(1280, FILM_HEIGHT))
	left_frame = _print("LeftPhotoFrame", left_cat, String(names[0]), Palette.P1_INK, 0, print_size)
	right_frame = _print("RightPhotoFrame", right_cat, String(names[1]), Palette.P2_INK, 1, print_size)
	left_cat = left_frame.subject
	right_cat = right_frame.subject
	left_cat.material = _print_material()
	right_cat.material = _print_material()
	_place_prints()


## Replaces a loose cat with a polaroid of it. The loose TextureRect is freed:
## the print's own subject shows the same texture.
func _print(node_name: String, loose: TextureRect, caption: String, ink: Color, sky: int, print_size: Vector2) -> Polaroid:
	var photo := Polaroid.new()
	photo.name = node_name
	photo.sky_seed = sky
	photo.glow = Palette.P1.lerp(Color("ffe6a6"), 0.55) if sky == 0 else Palette.P2.lerp(Color("ffe6a6"), 0.55)
	photo.size = print_size
	add_child(photo)
	photo.setup(loose.texture, caption, ink)
	loose.queue_free()
	return photo


func _add_film_strip(node_name: String, at: Vector2, bounds: Vector2) -> void:
	var strip := ColorRect.new()
	strip.name = node_name
	strip.position = at
	strip.size = bounds
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_meta("decorative_overhang", true)
	var material := ShaderMaterial.new()
	material.shader = FILM_SHADER
	# Quieter than the shader's defaults: the edge frames the page and should
	# not compete with the menu for the eye.
	material.set_shader_parameter("ink", Color(0.05, 0.05, 0.08, 0.82))
	material.set_shader_parameter("paper", Color(0.78, 0.72, 0.60, 0.55))
	material.set_shader_parameter("speed", 0.25)
	strip.material = material
	add_child(strip)


func _print_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PRINT_SHADER
	return material


func _texture(texture: Texture2D, at: Vector2, bounds: Vector2) -> TextureRect:
	var item := TextureRect.new()
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.texture = texture
	item.position = at
	item.size = bounds
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item)
	return item


func _process(delta: float) -> void:
	if not motion_enabled:
		return
	age += delta
	if not is_instance_valid(title_logo):
		return
	var breath := sin(age * 1.35)
	title_logo.position = logo_origin + Vector2(0.0, breath * 2.5)
	title_logo.scale = Vector2.ONE * (1.0 + breath * 0.006)
	if scrapbook_enabled:
		# Slow paper drift, quicker independent snapshots: the depth reads without
		# making a menu item difficult to point at or text difficult to read.
		scrapbook_backdrop.position = backdrop_origin + Vector2(sin(age * 0.13) * 3.0, cos(age * 0.11) * 2.0)
		_place_prints()
		return
	left_cat.position = left_origin + Vector2(0.0, sin(age * 2.0) * 5.0)
	right_cat.position = right_origin + Vector2(0.0, sin(age * 2.0 + PI) * 5.0)
	left_cat.rotation = sin(age * 1.45) * 0.025
	right_cat.rotation = -sin(age * 1.45) * 0.025
	queue_redraw()


## The two prints bob and sway out of phase, each around its resting tilt.
func _place_prints() -> void:
	if not is_instance_valid(left_frame):
		return
	left_frame.position = left_origin + Vector2(0.0, sin(age * 0.83) * 4.0)
	right_frame.position = right_origin + Vector2(0.0, sin(age * 0.71 + 1.8) * 5.0)
	left_frame.rotation = left_tilt + sin(age * 0.61) * 0.01
	right_frame.rotation = right_tilt - sin(age * 0.57 + 0.8) * 0.012


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:lobby_ambience", probe_started)


func _probed_draw() -> void:
	# The moon used to be drawn on the full-screen backdrop at (screen - 82, 88),
	# which is exactly where every overlay panel has its top-right corner: it
	# came out as a beige sliver poking from behind the panel and cut by the HUD.
	# It lives inside the lobby panel now, clear of everything, where it is a
	# moon rather than an artefact.
	if scrapbook_enabled:
		return
	if shadows_enabled and is_instance_valid(left_cat):
		_draw_ellipse(left_origin + Vector2(left_cat.size.x * 0.5, left_cat.size.y * 0.88),
			Vector2(left_cat.size.x * 0.38, 10.0), Color(0.02, 0.05, 0.08, 0.20))
		_draw_ellipse(right_origin + Vector2(right_cat.size.x * 0.5, right_cat.size.y * 0.88),
			Vector2(right_cat.size.x * 0.38, 10.0), Color(0.02, 0.05, 0.08, 0.20))
	if not starfield_enabled:
		return
	for index in STARS.size():
		var alpha := 0.22 + (sin(age * 2.2 + float(index) * 0.9) * 0.5 + 0.5) * 0.48
		var radius := 3.0 + float(index % 3)
		var at: Vector2 = STARS[index]
		if name == "TitleAmbience" and at.x < 488:
			continue
		var points := PackedVector2Array([
			at + Vector2(0, -radius), at + Vector2(radius, 0),
			at + Vector2(0, radius), at + Vector2(-radius, 0),
		])
		draw_colored_polygon(points, Color("ffd166", alpha))


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 32:
		var unit := Vector2.from_angle(TAU * float(index) / 32.0)
		points.append(center + unit * radius)
	draw_colored_polygon(points, color)
