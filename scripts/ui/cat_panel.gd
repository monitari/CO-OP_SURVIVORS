extends ColorRect
## Code-native decorations: no bitmap scaling, input interception or per-frame work.
const CatStyle := preload("res://scripts/ui/cat_theme.gd")
var backdrop := false


func _ready() -> void:
	color = Color.TRANSPARENT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if backdrop:
		_draw_backdrop()
		return
	var compact := size.y < 150.0
	var style := CatStyle.surface(CatStyle.INK if compact else CatStyle.PANEL, 12 if compact else 20)
	style.border_color = Color("42565d") if compact else CatStyle.OUTLINE
	style.shadow_color = Color(0.02, 0.01, 0.04, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	if compact:
		return
	# One quiet brand seal; chrome never competes with the icon artwork.
	draw_line(Vector2(24, 10), Vector2(76, 10), CatStyle.GOLD, 3, true)
	_paw(Vector2(size.x - 23, 24), 0.48, Color(CatStyle.GOLD, 0.3))


func _paw(at: Vector2, scale_factor: float, tint: Color) -> void:
	draw_circle(at, 7 * scale_factor, tint)
	for toe in [Vector2(-9, -6), Vector2(-4, -13), Vector2(5, -13), Vector2(11, -5)]:
		draw_circle(at + toe * scale_factor, 3.4 * scale_factor, tint)


func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("172c36"))
	# Deterministic stars, with no flashing behind paused menus.
	for index in 32:
		var spot := Vector2(fmod(index * 173.0 + 28, size.x), fmod(index * 79.0 + 22, size.y))
		draw_circle(spot, 1.4 if index % 3 else 2.2, Color(CatStyle.CREAM, 0.22))
	for index in 12:
		var x := index * 116.0 - 30
		var top := size.y - 46 - (index % 3) * 17
		draw_rect(Rect2(x, top, 100, size.y - top), Color("203d44"))
		draw_line(Vector2(x - 5, top), Vector2(x + 105, top), Color("42615d"), 3, true)
		for window in 3:
			draw_rect(Rect2(x + 13 + window * 27, top + 17, 9, 14), Color("9c9065"))
	for index in 6:
		_paw(Vector2(32 + index * 13, size.y * 0.42 + index * 35), 0.8, Color(CatStyle.GOLD, 0.12))
