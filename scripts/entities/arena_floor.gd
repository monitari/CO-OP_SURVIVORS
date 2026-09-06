class_name ArenaFloor
extends Node2D
## Moonroof: layered rooftop paving, gutters and a cat feeding terrace.
## All props are cosmetic decals, not misleading movement-blocking obstacles.
## Drawn below the chain and every actor.
##
## The rooftop is endless. It used to be one static slab from -2400 to +2400,
## which is only about four screens wide — a pair that kited in one direction
## ran off the world and fought over a void. Instead of making the slab bigger
## (which only moves the edge), the floor now redraws a window around the camera
## and generates its contents from world position, so there is no edge at all.
##
## Two grids do that work. Paving is a pure function of tile coordinates, so it
## repeats without needing to be stored. Props are placed per PROP_CELL from a
## hash of that cell's coordinates, which means the same patch of roof always
## has the same crates and vents on it however many times the pair crosses it —
## an endless roof that is still a place rather than noise.

const VIEW_MARGIN := 1400.0 ## Half-width of the drawn window; comfortably past the screen corners.
const REDRAW_STEP := 384.0 ## How far the camera travels before the window is rebuilt.
const PROP_CELL := 512
const TILE := Vector2(128, 64)
const EnemyIcons := preload("res://scripts/ui/enemy_icons.gd")

var draw_origin := Vector2.ZERO


func _ready() -> void:
	z_index = -20


## Called from the camera update. Snapping to REDRAW_STEP means the window is
## rebuilt a few times a minute rather than every frame.
func follow(focus: Vector2) -> void:
	var snapped_focus := (focus / REDRAW_STEP).floor() * REDRAW_STEP
	if snapped_focus.is_equal_approx(draw_origin):
		return
	draw_origin = snapped_focus
	queue_redraw()


func _draw() -> void:
	var low := draw_origin - Vector2(VIEW_MARGIN, VIEW_MARGIN)
	var high := draw_origin + Vector2(VIEW_MARGIN, VIEW_MARGIN)
	draw_rect(Rect2(low, high - low), Color("23383e"))

	# Staggered paving. Row and column are world tile indices rather than a
	# bounded range, so the pattern continues in every direction.
	var first_row := int(floor(low.y / TILE.y))
	var last_row := int(ceil(high.y / TILE.y))
	var first_column := int(floor(low.x / TILE.x)) - 1
	var last_column := int(ceil(high.x / TILE.x))
	for row in range(first_row, last_row):
		for column in range(first_column, last_column):
			var at := Vector2(column * TILE.x + (TILE.x * 0.5 if posmod(row, 2) else 0.0), row * TILE.y)
			var shade := posmod(row * 7 + column * 13, 4)
			var tint := Color("2c4246").lightened(shade * 0.006)
			draw_rect(Rect2(at + Vector2(2, 2), TILE - Vector2(4, 4)), tint)
			draw_line(at + Vector2(4, 3), at + Vector2(TILE.x - 6, 3), Color("33494c"), 1, true)

	# Gutters every 768px, again indexed off world position.
	var first_gutter := int(floor(low.x / 768.0)) * 768
	for x in range(first_gutter, int(high.x) + 768, 768):
		draw_rect(Rect2(x - 8, low.y, 16, high.y - low.y), Color("1e333a"))
		draw_line(Vector2(x - 8, low.y), Vector2(x - 8, high.y), Color("53625d"), 2)
		for y in range(int(low.y) - posmod(int(low.y), 128), int(high.y), 128):
			draw_line(Vector2(x - 5, y), Vector2(x + 5, y), Color("405355"), 2)

	_draw_props(low, high)
	if _window_contains_origin(low, high):
		_draw_home_terrace()


func _window_contains_origin(low: Vector2, high: Vector2) -> bool:
	return low.x < 640.0 and high.x > -640.0 and low.y < 420.0 and high.y > -420.0


## The one unique place on an otherwise endless roof: where the pair starts.
func _draw_home_terrace() -> void:
	var mat := StyleBoxFlat.new()
	mat.bg_color = Color("384b48")
	mat.border_color = Color("526158")
	mat.set_border_width_all(3)
	mat.set_corner_radius_all(16)
	draw_style_box(mat, Rect2(-230, -160, 460, 320))
	for side: float in [-1.0, 1.0]:
		draw_dashed_line(Vector2(-207, side * 139), Vector2(207, side * 139), Color("697060"), 1.5, 9)
	_fish(Vector2.ZERO, Color("586659"))
	_bowls(Vector2(0, -230))
	for index in 10:
		var at := Vector2(-340 + index * 53, 238 + sin(index * 0.5) * 24)
		draw_circle(at, 4, Color("526058"))
		for toe in [Vector2(-5, -5), Vector2(1, -8), Vector2(6, -4)]:
			draw_circle(at + toe, 2, Color("526058"))


## Props come from the cell they sit in, not from a run-wide seed, so the roof
## can be generated in any order and still look the same every time.
func _draw_props(low: Vector2, high: Vector2) -> void:
	var first_cell := Vector2i(int(floor(low.x / PROP_CELL)), int(floor(low.y / PROP_CELL)))
	var last_cell := Vector2i(int(ceil(high.x / PROP_CELL)), int(ceil(high.y / PROP_CELL)))
	for cell_x in range(first_cell.x, last_cell.x):
		for cell_y in range(first_cell.y, last_cell.y):
			var rng := RandomNumberGenerator.new()
			rng.seed = _cell_seed(cell_x, cell_y)
			# Not every cell gets something; an evenly littered roof reads as
			# wallpaper rather than as a place.
			if rng.randf() > 0.62:
				continue
			var at := Vector2(
				cell_x * PROP_CELL + rng.randf_range(60.0, PROP_CELL - 140.0),
				cell_y * PROP_CELL + rng.randf_range(60.0, PROP_CELL - 140.0)
			)
			# The starting terrace stays clear so the opening seconds are readable.
			if absf(at.x) < 560.0 and absf(at.y) < 350.0:
				continue
			match rng.randi() % 4:
				0: _planter(at)
				1: _box(at)
				2: _vent(at)
				_: _yarn(at)


## A stable hash of the cell coordinates. Godot's seed is 64-bit, so the two
## coordinates are mixed rather than added — otherwise (1, -1) and (-1, 1) would
## generate the same patch of roof.
func _cell_seed(cell_x: int, cell_y: int) -> int:
	var mixed := (cell_x * 73856093) ^ (cell_y * 19349663)
	return absi(mixed) + 20260905


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
