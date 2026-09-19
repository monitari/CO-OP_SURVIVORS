extends Control

## One line of text set along a gentle arc, the way the growth hand's cards are
## fanned beneath it: the middle of the line is highest and each glyph leans
## outward with the card under it. A Label can only set a straight line, so this
## draws the glyphs itself, each one rotated to the arc's tangent at its centre.
##
## The arc is a circle whose centre lies `radius` below `apex` (local
## coordinates). A glyph at distance s along the line from the middle sits at
## angle s / radius.

var text := "":
	set(value):
		if text != value:
			text = value
			queue_redraw()
var font_size := 20:
	set(value):
		font_size = value
		queue_redraw()
var color := Color("d9ecff"):
	set(value):
		if color != value:
			color = value
			queue_redraw()
var outline_color := Color(0.02, 0.04, 0.08, 0.92)
var outline_size := 6
## Top-centre of the arc, where the middle glyph's baseline sits.
var apex := Vector2.ZERO:
	set(value):
		if apex != value:
			apex = value
			queue_redraw()
## Wider is flatter. The growth hand's fan works out to a circle about 2,000px
## across; this is a little tighter so the curve reads at a glance on one line.
var radius := 1300.0
## Length of the fading rules either side of the text, along the same arc.
var flourish := 70.0
var accent := Color("35dbff")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if text.is_empty():
		return
	var font := get_theme_default_font()
	var advances: Array[float] = []
	var total := 0.0
	for index in text.length():
		var advance := font.get_char_size(text.unicode_at(index), font_size).x
		advances.append(advance)
		total += advance
	var centre := apex + Vector2(0, radius)
	var ascent := font.get_ascent(font_size)
	# Outline first for every glyph, then the fills, so a glyph's outline never
	# lands on top of its neighbour's fill where they lean together.
	for pass_index in 2:
		var along := -total * 0.5
		for index in text.length():
			var advance := advances[index]
			var angle := (along + advance * 0.5) / radius
			var baseline := centre + Vector2(sin(angle), -cos(angle)) * radius
			draw_set_transform(baseline, angle)
			# The glyph is drawn from its baseline-left corner; centre it on the
			# arc point so the rotation pivots through the middle of the glyph.
			var origin := Vector2(-advance * 0.5, 0)
			var codepoint := text.unicode_at(index)
			if pass_index == 0:
				if outline_size > 0:
					font.draw_char_outline(get_canvas_item(), origin, codepoint, font_size, outline_size, outline_color)
			else:
				font.draw_char(get_canvas_item(), origin, codepoint, font_size, color)
			along += advance
	draw_set_transform(Vector2.ZERO, 0.0)
	if flourish <= 0.0:
		return
	# Rules either side, following the arc a glyph's height above the baseline's
	# middle, fading out as they leave the text.
	var lift := ascent * 0.38
	for side in [-1.0, 1.0]:
		var start := total * 0.5 + 12.0
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var steps := 10
		for step in steps + 1:
			var along: float = side * (start + flourish * float(step) / steps)
			var angle := along / radius
			points.append(centre + Vector2(sin(angle), -cos(angle)) * (radius + lift))
			colors.append(Color(accent, 0.7 * (1.0 - float(step) / steps)))
		draw_polyline_colors(points, colors, 1.5, true)
		var tip_angle: float = side * (start - 5.0) / radius
		var tip := centre + Vector2(sin(tip_angle), -cos(tip_angle)) * (radius + lift)
		draw_circle(tip, 2.5, Color(accent, 0.85), true, -1.0, true)
