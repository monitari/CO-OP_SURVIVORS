class_name ArenaFloor
extends Node2D
## Moonroof: layered rooftop paving, gutters and a cat feeding terrace.
## All props are cosmetic decals, not misleading movement-blocking obstacles.
## One static draw, deterministic placement, below the chain and every actor.
const EXTENT := 2400
const EnemyIcons := preload("res://scripts/ui/enemy_icons.gd")


func _ready() -> void:
	z_index = -20


func _draw() -> void:
	draw_rect(Rect2(-EXTENT, -EXTENT, EXTENT * 2, EXTENT * 2), Color("23383e"))
	# Staggered, gently varied paving replaces the high-contrast debug grid.
	for row in range(-38, 38):
		for column in range(-20, 20):
			var at := Vector2(column * 128 + (64 if row % 2 else 0), row * 64)
			var shade := posmod(row * 7 + column * 13, 4)
			var tint := Color("2c4246").lightened(shade * 0.006)
			draw_rect(Rect2(at + Vector2(2, 2), Vector2(124, 60)), tint)
			draw_line(at + Vector2(4, 3), at + Vector2(122, 3), Color("33494c"), 1, true)
	# Broad gutters make distances legible without creating a wall.
	for x in range(-2304, 2400, 768):
		draw_rect(Rect2(x - 8, -EXTENT, 16, EXTENT * 2), Color("1e333a"))
		draw_line(Vector2(x - 8, -EXTENT), Vector2(x - 8, EXTENT), Color("53625d"), 2)
		for y in range(-EXTENT, EXTENT, 128):
			draw_line(Vector2(x - 5, y), Vector2(x + 5, y), Color("405355"), 2)
	# Start terrace: a worn square mat, not a circular attack indicator.
	var mat := StyleBoxFlat.new()
	mat.bg_color = Color("384b48")
	mat.border_color = Color("526158")
	mat.set_border_width_all(3)
	mat.set_corner_radius_all(16)
	draw_style_box(mat, Rect2(-230, -160, 460, 320))
	for side in [-1.0, 1.0]:
		draw_dashed_line(Vector2(-207, side * 139), Vector2(207, side * 139), Color("697060"), 1.5, 9)
	_fish(Vector2.ZERO, Color("586659"))
	_planter(Vector2(-450, -170))
	_planter(Vector2(390, 180))
	_box(Vector2(-360, 165))
	_bowls(Vector2(0, -230))
	# Sparse districts: plants, folded cartons, roof vents and discarded yarn.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260905
	for index in 100:
		var at := Vector2(rng.randf_range(-2250, 2250), rng.randf_range(-2250, 2250))
		if absf(at.x) < 560 and absf(at.y) < 350:
			continue
		match index % 4:
			0: _planter(at)
			1: _box(at)
			2: _vent(at)
			3: _yarn(at)
	for index in 10:
		var at := Vector2(-340 + index * 53, 238 + sin(index * 0.5) * 24)
		draw_circle(at, 4, Color("526058"))
		for toe in [Vector2(-5, -5), Vector2(1, -8), Vector2(6, -4)]:
			draw_circle(at + toe, 2, Color("526058"))


func _planter(at: Vector2) -> void:
	draw_set_transform(at + Vector2(38, 25), 0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 42, Color(0.05, 0.12, 0.14, 0.3))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(EnemyIcons.get_icon("planter"), Rect2(at + Vector2(-2, -47), Vector2(86, 86)), false, Color("829589"))


func _box(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(3, 6), Vector2(68, 52)), Color("20343b"))
	draw_rect(Rect2(at, Vector2(68, 48)), Color("73614d"))
	draw_rect(Rect2(at + Vector2(6, 7), Vector2(56, 35)), Color("4f5043"))
	draw_colored_polygon(PackedVector2Array([at, at + Vector2(24, -10), at + Vector2(27, 12), at + Vector2(0, 16)]), Color("8a7257"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(68, 0), at + Vector2(76, -8), at + Vector2(82, 34), at + Vector2(68, 38)]), Color("806c51"))
	_fish(at + Vector2(35, 27), Color("727057"), 0.28)


func _vent(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(4, 6), Vector2(70, 54)), Color("20343b"))
	draw_rect(Rect2(at, Vector2(70, 50)), Color("52625f"))
	draw_rect(Rect2(at + Vector2(4, 4), Vector2(62, 42)), Color("3c5355"))
	for slat in 5:
		draw_line(at + Vector2(10, 10 + slat * 7), at + Vector2(60, 10 + slat * 7), Color("71817a"), 2)


func _yarn(at: Vector2) -> void:
	draw_circle(at + Vector2(3, 5), 18, Color("20343b"))
	draw_circle(at, 16, Color("665d63"))
	for strand in 4:
		draw_arc(at + Vector2(strand * 3 - 4, 0), 12, -1.8, 1.8, 16, Color("897578"), 1.3, true)
	draw_polyline(PackedVector2Array([at + Vector2(16, 0), at + Vector2(31, 14), at + Vector2(49, 10)]), Color("897578"), 1.5, true)


func _bowls(at: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var spot := at + Vector2(side * 34, 0)
		draw_circle(spot + Vector2(0, 4), 22, Color("20343b"))
		draw_circle(spot, 21, Color("697a73"))
		draw_circle(spot, 16, Color("31494e"))
		if side < 0:
			for pellet in 5:
				draw_circle(spot + Vector2.from_angle(pellet * 1.25) * 7, 4, Color("968164"))
		else:
			draw_arc(spot, 11, -2.6, -0.7, 12, Color("698e92"), 2, true)


func _fish(at: Vector2, tint: Color, factor := 1.0) -> void:
	draw_set_transform(at, 0, Vector2.ONE * factor)
	draw_arc(Vector2.ZERO, 32, -1.15, 1.15, 24, tint, 5, true)
	draw_arc(Vector2(25, 0), 32, PI - 1.15, PI + 1.15, 24, tint, 5, true)
	draw_polyline(PackedVector2Array([Vector2(-6, -13), Vector2(-28, -28), Vector2(-28, 28), Vector2(-6, 13)]), tint, 5, true)
	draw_circle(Vector2(21, -4), 3, tint)
	draw_set_transform(Vector2.ZERO)
