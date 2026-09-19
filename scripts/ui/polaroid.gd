extends Control
## One instant photograph taped into the scrapbook: a white print with the thick
## bottom margin a polaroid has, a night-sky photograph with a moon glow behind
## the subject, a handwritten caption in the margin, and a strip of tape.
##
## The subject is a real child TextureRect (`subject`), so a shader can treat it
## and the whole print — photo, subject, caption, tape — moves and tilts as one
## piece instead of a frame being kept in step with a picture by hand.

const Palette := preload("res://scripts/ui/cat_theme.gd")

## White border around the photograph, and the deeper caption margin under it.
const BORDER := 12.0
const CAPTION_MARGIN := 54.0
var caption_margin := CAPTION_MARGIN

var subject: TextureRect
var caption: Label
var tape: Panel
## Hue of the moon glow behind the subject: the owner's colour, faintly.
var glow := Color("ffe6a6")
## Seed for where the stars fall, so the two prints do not share a sky.
var sky_seed := 0


func setup(texture: Texture2D, caption_text: String, caption_ink: Color) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	subject = TextureRect.new()
	subject.name = "Subject"
	subject.texture = texture
	subject.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	subject.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	subject.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subject)
	caption = Label.new()
	caption.name = "Caption"
	caption.text = caption_text
	caption.visible = not caption_text.is_empty()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", caption_ink)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.rotation = -0.02
	add_child(caption)
	tape = Panel.new()
	tape.name = "Tape"
	# Tape holds the print to the page, so it runs over the top edge.
	tape.set_meta("decorative_overhang", true)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(Palette.TAPE.lightened(0.12), 0.8)
	strip.border_color = Color(Palette.TAPE.darkened(0.25), 0.35)
	strip.set_border_width_all(1)
	tape.add_theme_stylebox_override("panel", strip)
	add_child(tape)
	resized.connect(_layout)
	_layout()


func photo_rect() -> Rect2:
	return Rect2(BORDER, BORDER, size.x - BORDER * 2.0, size.y - BORDER - caption_margin)


func _layout() -> void:
	pivot_offset = size * 0.5
	var photo := photo_rect()
	if subject != null:
		subject.position = photo.position + Vector2(8, 8)
		subject.size = photo.size - Vector2(16, 16)
	if caption != null:
		caption.position = Vector2(BORDER, size.y - caption_margin + 2.0)
		caption.size = Vector2(size.x - BORDER * 2.0, maxf(0.0, caption_margin - 8.0))
		caption.pivot_offset = caption.size * 0.5
	if tape != null:
		tape.size = Vector2(minf(92.0, size.x * 0.42), 24.0)
		tape.position = Vector2((size.x - tape.size.x) * 0.5, -12.0)
		tape.pivot_offset = tape.size * 0.5
		tape.rotation = 0.05 if sky_seed % 2 == 0 else -0.06
	queue_redraw()


func _draw() -> void:
	# Hard cast shadow, then the print, then the photograph on it.
	draw_rect(Rect2(Vector2(7, 9), size), Palette.PAPER_SHADOW)
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PHOTO_BORDER)
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK_LINE, 0.5), false, 1.5)
	var photo := photo_rect()
	# Night sky, lighter towards the horizon, drawn as one gradient quad.
	var top := Palette.PHOTO_NIGHT.darkened(0.12)
	var bottom := Palette.PHOTO_NIGHT.lightened(0.14)
	draw_polygon(PackedVector2Array([photo.position, photo.position + Vector2(photo.size.x, 0),
		photo.end, photo.position + Vector2(0, photo.size.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	# Moon glow behind the subject's head, in rings rather than a shader.
	var centre := photo.position + Vector2(photo.size.x * 0.5, photo.size.y * 0.42)
	for ring in range(5, 0, -1):
		draw_circle(centre, photo.size.x * (0.12 + 0.07 * float(ring)), Color(glow, 0.05), true, -1.0, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + sky_seed * 104729
	for index in 9:
		var at := photo.position + Vector2(rng.randf_range(8.0, photo.size.x - 8.0), rng.randf_range(8.0, photo.size.y * 0.45))
		draw_circle(at, rng.randf_range(0.8, 1.8), Color(1, 0.96, 0.85, rng.randf_range(0.35, 0.8)), true, -1.0, true)
	# A roof line along the bottom of the shot, so the cats stand on something.
	draw_rect(Rect2(photo.position + Vector2(0, photo.size.y - 20.0), Vector2(photo.size.x, 20.0)),
		Color(Palette.PHOTO_NIGHT.darkened(0.35), 0.9))
	draw_rect(photo, Color(Palette.INK_LINE, 0.45), false, 1.0)
