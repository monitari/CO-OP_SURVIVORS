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
const EnemyIcons := preload("res://scripts/ui/enemy_icons.gd")
const RooftopTexture := preload("res://assets/environment/moonroof_slate_tile.png")
## The boxy props throw a hard-edged shadow the length of their own height.
## These used to be per-prop offsets that disagreed about direction as well as
## length; now only the length differs, which is the part that should.
const CRATE_HEIGHT := 7.0
const VENT_HEIGHT := 7.5
const GUTTER_SPACING := 768.0
const GUTTER_OFFSET := GUTTER_SPACING * 0.5
const TILE_OVERDRAW := 2.0

var draw_origin := Vector2.ZERO
var draw_margin := VIEW_MARGIN


## Shorthand for the grade every ground surface goes through, so the palette
## below reads as the colours the roof was painted in rather than as the
## colours it happens to be lit by tonight.
func _lit(color: Color, facing := 0.0) -> Color:
	return Moonlight.ground(color, facing)


func _ready() -> void:
	z_index = -20


## Called from the camera update. Snapping to REDRAW_STEP means the window is
## rebuilt a few times a minute rather than every frame.
func follow(focus: Vector2, coverage := VIEW_MARGIN) -> void:
	var margin := maxf(VIEW_MARGIN, ceilf(coverage / REDRAW_STEP) * REDRAW_STEP)
	var snapped_focus := (focus / REDRAW_STEP).floor() * REDRAW_STEP
	if snapped_focus.is_equal_approx(draw_origin) and is_equal_approx(margin, draw_margin):
		return
	draw_origin = snapped_focus
	draw_margin = margin
	queue_redraw()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:arena_floor", probe_started)


func _probed_draw() -> void:
	var low := draw_origin - Vector2(draw_margin, draw_margin)
	var high := draw_origin + Vector2(draw_margin, draw_margin)
	draw_rect(Rect2(low, high - low), _lit(Color("23383e")))
	_draw_rooftop_texture(low, high)

	# Keep the home terrace between gutters instead of bisecting it with a dark
	# line. The old gutter at x = 0 combined with the terrace edge and looked
	# like a full-screen debug cross during the opening fight.
	var first_gutter := int(floor((low.x - GUTTER_OFFSET) / GUTTER_SPACING)) * int(GUTTER_SPACING) + int(GUTTER_OFFSET)
	for x in range(first_gutter, int(high.x) + int(GUTTER_SPACING), int(GUTTER_SPACING)):
		draw_rect(Rect2(x - 5, low.y, 10, high.y - low.y), _lit(Color("1e333a", 0.65)))
		# A gutter is a channel, so its far wall is the one the moon reaches
		# and its near wall is the one in shade. Same rule, cheapest possible
		# case: two lines that used to be one colour are now two.
		draw_line(Vector2(x - 5, low.y), Vector2(x - 5, high.y), _lit(Color("53625d", 0.38), 0.12), 1.3)
		draw_line(Vector2(x + 5, low.y), Vector2(x + 5, high.y), _lit(Color("53625d", 0.4)).darkened(0.35), 1.3)
		for y in range(int(low.y) - posmod(int(low.y), 128), int(high.y), 128):
			draw_line(Vector2(x - 3, y), Vector2(x + 3, y), _lit(Color("405355", 0.4)), 1)

	# Solid furniture is now owned by RooftopPropField. Each prop needs its own
	# y-sort key so survivors can pass behind it; painting the same shapes into
	# this one background canvas would flatten them again.
	if _window_contains_origin(low, high):
		_draw_home_terrace()


## The painted slab is deliberately much larger than one gameplay tile. It
## carries material detail while the hashed props below keep the endless roof
## from reading as wallpaper. Alternating mirrors make opposite copies meet on
## the same source edge, hiding seams without baking a giant finite backdrop.
func _draw_rooftop_texture(low: Vector2, high: Vector2) -> void:
	var texture_size := RooftopTexture.get_size()
	var first_tile := Vector2i(int(floor(low.x / texture_size.x)), int(floor(low.y / texture_size.y)))
	var last_tile := Vector2i(int(ceil(high.x / texture_size.x)), int(ceil(high.y / texture_size.y)))
	for tile_y in range(first_tile.y, last_tile.y):
		for tile_x in range(first_tile.x, last_tile.x):
			var flip_x := posmod(tile_x, 2) != 0
			var flip_y := posmod(tile_y, 2) != 0
			var tile_origin := Vector2(tile_x * texture_size.x, tile_y * texture_size.y)
			var pivot := tile_origin + Vector2(texture_size.x if flip_x else 0.0, texture_size.y if flip_y else 0.0)
			var tile_scale := Vector2(-1.0 if flip_x else 1.0, -1.0 if flip_y else 1.0)
			draw_set_transform(pivot, 0.0, tile_scale)
			# A tiny overdraw hides the doubled dark edge produced where mirrored
			# copies meet. It is below every prop, so the overlap cannot cover any
			# gameplay information.
			draw_texture_rect(RooftopTexture,
				Rect2(Vector2.ONE * -TILE_OVERDRAW, texture_size + Vector2.ONE * TILE_OVERDRAW * 2.0),
				false, _lit(Color("d1dcda")))
	draw_set_transform(Vector2.ZERO)


func _window_contains_origin(low: Vector2, high: Vector2) -> bool:
	return low.x < 640.0 and high.x > -640.0 and low.y < 420.0 and high.y > -420.0


## The one unique place on an otherwise endless roof: where the pair starts.
func _draw_home_terrace() -> void:
	var mat := StyleBoxFlat.new()
	# The terrace is a remembered place, not a gameplay volume. Keep only a
	# faint wash under the bowls and paw prints so it cannot be mistaken for a
	# collision box or targeting guide once combat fills the screen.
	mat.bg_color = _lit(Color("384b48", 0.14))
	mat.border_color = _lit(Color("657066", 0.035), 0.10)
	mat.set_border_width_all(2)
	mat.set_corner_radius_all(16)
	draw_style_box(mat, Rect2(-230, -160, 460, 320))
	for side: float in [-1.0, 1.0]:
		draw_dashed_line(Vector2(-207, side * 139), Vector2(207, side * 139), _lit(Color("7d8171", 0.34), 0.28), 1.3, 12)
	_fish(Vector2.ZERO, _lit(Color("586659")))
	_bowls(Vector2(0, -230))
	var paw := _lit(Color("526058"))
	for index in 10:
		var at := Vector2(-340 + index * 53, 238 + sin(index * 0.5) * 24)
		draw_circle(at, 4, paw)
		for toe in [Vector2(-5, -5), Vector2(1, -8), Vector2(6, -4)]:
			draw_circle(at + toe, 2, paw)


## A stable hash of the cell coordinates. Godot's seed is 64-bit, so the two
## coordinates are mixed rather than added — otherwise (1, -1) and (-1, 1) would
## generate the same patch of roof.
func _cell_seed(cell_x: int, cell_y: int) -> int:
	var mixed := (cell_x * 73856093) ^ (cell_y * 19349663)
	return absi(mixed) + 20260905


func _box(at: Vector2) -> void:
	var drop := Moonlight.cast_offset(CRATE_HEIGHT)
	draw_rect(Rect2(at + drop, Vector2(68, 52)), _lit(Color("20343b")).darkened(0.25))
	draw_rect(Rect2(at, Vector2(68, 48)), _lit(Color("806044"), 0.08))
	draw_rect(Rect2(at + Vector2(6, 7), Vector2(56, 35)), _lit(Color("5d503d"), 0.04))
	# The two lids catch the moon at different angles; the near one is turned
	# into it, the far one away.
	draw_colored_polygon(PackedVector2Array([at, at + Vector2(24, -10), at + Vector2(27, 12), at + Vector2(0, 16)]), _lit(Color("a07852"), 0.52))
	draw_colored_polygon(PackedVector2Array([at + Vector2(68, 0), at + Vector2(76, -8), at + Vector2(82, 34), at + Vector2(68, 38)]), _lit(Color("8c6848"), 0.16))
	if Moonlight.enabled:
		var edge := Moonlight.rim(Color("9a744e"), 0.48)
		draw_line(at, at + Vector2(68, 0), edge, 1.6)
		draw_line(at, at + Vector2(0, 48), edge, 1.6)
	_fish(at + Vector2(35, 27), _lit(Color("727057")), 0.28)


func _vent(at: Vector2) -> void:
	var drop := Moonlight.cast_offset(VENT_HEIGHT)
	draw_rect(Rect2(at + drop, Vector2(70, 54)), _lit(Color("20343b")).darkened(0.25))
	draw_rect(Rect2(at, Vector2(70, 50)), _lit(Color("52625f"), 0.18))
	draw_rect(Rect2(at + Vector2(4, 4), Vector2(62, 42)), _lit(Color("3c5355")))
	for slat in 5:
		draw_line(at + Vector2(10, 10 + slat * 7), at + Vector2(60, 10 + slat * 7), _lit(Color("71817a")), 2)
	if Moonlight.enabled:
		# Painted metal is the one thing up here with a hard edge, so it gets
		# the only true specular on the roof: a thin, bright top lip.
		var edge := Moonlight.rim(Color("71817a"), 0.7)
		draw_line(at, at + Vector2(70, 0), edge, 2.0)
		draw_line(at, at + Vector2(0, 50), Moonlight.rim(Color("52625f"), 0.4), 1.4)
		for slat in 5:
			draw_line(at + Vector2(10, 9 + slat * 7), at + Vector2(60, 9 + slat * 7), Color(edge, 0.28), 1.0)


func _yarn(at: Vector2) -> void:
	# A ball resting on the roof has one shadow, not a hard disc and a soft
	# one on top of each other, so the common footing rule replaces the flat
	# offset disc rather than joining it.
	if Moonlight.enabled:
		Moonlight.ground_shadow(self, at, 19.0, 1.5)
	else:
		draw_circle(at + Vector2(3, 5), 18, Color("20343b"))
	draw_circle(at, 16, _lit(Color("665d63")))
	for strand in 4:
		draw_arc(at + Vector2(strand * 3 - 4, 0), 12, -1.8, 1.8, 16, _lit(Color("897578")), 1.3, true)
	if Moonlight.enabled:
		# A ball is the clearest place on the roof to state where the moon is.
		draw_arc(at, 14.5, PI * 1.05, PI * 1.72, 14, Moonlight.rim(Color("897578"), 0.5), 2.0, true)
	draw_polyline(PackedVector2Array([at + Vector2(16, 0), at + Vector2(31, 14), at + Vector2(49, 10)]), _lit(Color("897578")), 1.5, true)


func _bowls(at: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var spot := at + Vector2(side * 34, 0)
		if Moonlight.enabled:
			Moonlight.ground_shadow(self, spot, 23.0, 1.3)
		else:
			draw_circle(spot + Vector2(0, 4), 22, Color("20343b"))
		draw_circle(spot, 21, _lit(Color("697a73"), 0.12))
		# The inside of a bowl is shaded from the same moon that lights its rim.
		draw_circle(spot, 16, _lit(Color("31494e")).darkened(0.18))
		if Moonlight.enabled:
			draw_arc(spot, 19.5, PI * 1.02, PI * 1.78, 14, Moonlight.rim(Color("697a73"), 0.52), 2.2, true)
		if side < 0:
			for pellet in 5:
				draw_circle(spot + Vector2.from_angle(pellet * 1.25) * 7, 4, _lit(Color("968164"), 0.2))
		else:
			draw_arc(spot, 11, -2.6, -0.7, 12, _lit(Color("698e92"), 0.35), 2, true)


func _fish(at: Vector2, tint: Color, factor := 1.0) -> void:
	draw_set_transform(at, 0, Vector2.ONE * factor)
	draw_arc(Vector2.ZERO, 32, -1.15, 1.15, 24, tint, 5, true)
	draw_arc(Vector2(25, 0), 32, PI - 1.15, PI + 1.15, 24, tint, 5, true)
	draw_polyline(PackedVector2Array([Vector2(-6, -13), Vector2(-28, -28), Vector2(-28, 28), Vector2(-6, 13)]), tint, 5, true)
	draw_circle(Vector2(21, -4), 3, tint)
	draw_set_transform(Vector2.ZERO)
