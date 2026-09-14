extends ColorRect
## Generated illustration and nine-slice chrome; labels stay live controls.
const BACKDROP_ART := preload("res://assets/ui/moonroof_backdrop_v4.png")
const CatStyle := preload("res://scripts/ui/cat_theme.gd")
var backdrop := false
## A backdrop can either replace what is behind it (lobby, character select,
## results — screens with no run to look at) or veil it (the growth screen,
## which interrupts a fight the pair is in the middle of). Painting the night
## sky over a level-up hid the very thing the choice is about.
var veil_only := false
## Panels the run shows through rather than sits behind.
var translucent := false
## A screen that is a place to put controls rather than a box to look at. The
## growth band uses it: the fight it interrupts stays fully visible, and its own
## children carry whatever plate they need.
var chromeless := false


func _ready() -> void:
	color = Color.TRANSPARENT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if backdrop:
		if veil_only:
			# Lighter than it was: the growth screen no longer covers the roof, and
			# the camera pulling in on the pair is what frames the moment now, so
			# the veil only has to separate the cards from the fight behind them.
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.22))
			return
		_draw_backdrop()
		return
	if chromeless:
		return
	var style := CatStyle.image_surface()
	if translucent:
		style.modulate_color.a = 0.88
	draw_style_box(style, Rect2(Vector2.ZERO, size))


func _paw(at: Vector2, scale_factor: float, tint: Color) -> void:
	draw_circle(at, 7 * scale_factor, tint)
	for toe in [Vector2(-9, -6), Vector2(-4, -13), Vector2(5, -13), Vector2(11, -5)]:
		draw_circle(at + toe * scale_factor, 3.4 * scale_factor, tint)


func _draw_backdrop() -> void:
	draw_texture_rect(BACKDROP_ART, Rect2(Vector2.ZERO, size), false)
