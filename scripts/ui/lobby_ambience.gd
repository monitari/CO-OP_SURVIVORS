extends Control

## Lightweight menu motion: title breathing, two cats floating in opposite
## phases, and a handful of deterministic stars.

var title_logo: TextureRect
var left_cat: TextureRect
var right_cat: TextureRect
var age := 0.0
var left_origin := Vector2(72.0, 204.0)
var right_origin := Vector2(882.0, 204.0)
var logo_origin := Vector2(190.0, 4.0)

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
	left_cat.pivot_offset = left_cat.size * 0.5
	right_cat.pivot_offset = right_cat.size * 0.5
	title_logo.pivot_offset = title_logo.size * 0.5
	queue_redraw()


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
	age += delta
	if not is_instance_valid(title_logo):
		return
	var breath := sin(age * 1.35)
	title_logo.position = logo_origin + Vector2(0.0, breath * 2.5)
	title_logo.scale = Vector2.ONE * (1.0 + breath * 0.006)
	left_cat.position = left_origin + Vector2(0.0, sin(age * 2.0) * 5.0)
	right_cat.position = right_origin + Vector2(0.0, sin(age * 2.0 + PI) * 5.0)
	left_cat.rotation = sin(age * 1.45) * 0.025
	right_cat.rotation = -sin(age * 1.45) * 0.025
	queue_redraw()


func _draw() -> void:
	# The moon used to be drawn on the full-screen backdrop at (screen - 82, 88),
	# which is exactly where every overlay panel has its top-right corner: it
	# came out as a beige sliver poking from behind the panel and cut by the HUD.
	# It lives inside the lobby panel now, clear of everything, where it is a
	# moon rather than an artefact.
	_draw_moon(Vector2(986.0, 74.0), 34.0)
	_draw_ellipse(Vector2(147.0, 335.0), Vector2(57.0, 10.0), Color(0.02, 0.05, 0.08, 0.20))
	_draw_ellipse(Vector2(957.0, 335.0), Vector2(57.0, 10.0), Color(0.02, 0.05, 0.08, 0.20))
	for index in STARS.size():
		var alpha := 0.22 + (sin(age * 2.2 + float(index) * 0.9) * 0.5 + 0.5) * 0.48
		var radius := 3.0 + float(index % 3)
		var at: Vector2 = STARS[index]
		var points := PackedVector2Array([
			at + Vector2(0, -radius), at + Vector2(radius, 0),
			at + Vector2(0, radius), at + Vector2(-radius, 0),
		])
		draw_colored_polygon(points, Color("ffd166", alpha))


## A crescent cut out of a disc, drawn as one polygon ring so nothing has to be
## painted over the panel behind it.
func _draw_moon(centre: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for index in 40:
		points.append(centre + Vector2.from_angle(TAU * float(index) / 40.0) * radius)
	var bite := centre + Vector2(radius * 0.42, -radius * 0.3)
	var inner := PackedVector2Array()
	for index in 40:
		inner.append(bite + Vector2.from_angle(-TAU * float(index) / 40.0) * radius * 0.86)
	draw_colored_polygon(points, Color("f2dcae"))
	draw_colored_polygon(inner, Color("f4efe2"))
	draw_circle(centre + Vector2(-radius * 0.34, radius * 0.12), radius * 0.15, Color("e2c894"))
	draw_circle(centre + Vector2(-radius * 0.06, radius * 0.46), radius * 0.10, Color("e2c894"))


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 32:
		var unit := Vector2.from_angle(TAU * float(index) / 32.0)
		points.append(center + unit * radius)
	draw_colored_polygon(points, color)
