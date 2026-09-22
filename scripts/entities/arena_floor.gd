class_name ArenaFloor
extends Node2D
## Moonroof: layered rooftop paving, gutters and a cat feeding terrace, plus the
## floor half of every piece of furniture — its shadow, and the puddles, moss,
## leaves, cracks and chalk that make the paving between pieces a lived-in roof
## rather than a repeating texture. Nothing drawn here blocks movement.
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
##
## What stands on the roof is RoofLayout's to decide. The standing half is
## RooftopPropField's; this draws the half that lies on the floor, from the same
## entries, so a shadow can never end up under the wrong water tower.

const VIEW_MARGIN := 1400.0 ## Half-width of the drawn window; comfortably past the screen corners.
const REDRAW_STEP := 384.0 ## How far the camera travels before the window is rebuilt.
const RooftopTexture := preload("res://assets/environment/moonroof_slate_tile_v2.png")
## How dark a piece's shadow is. One polygon per piece, merged, so the legs and
## the tank of a water tower do not darken each other where they overlap.
const SHADOW_ALPHA := 0.26
## The warm pool under string lights and a lit skylight. Additive, so this is a
## light budget, and it is kept well under what a weapon cast spends: the roof's
## own lights are ambience, and the art direction reserves bright for magic.
const CONTACT_ALPHA := 0.2
const POOL_TINT := Color(1.0, 0.78, 0.48)
const POOL_ALPHA := 0.16
## One soft radial falloff shared by every pool. Stacked discs were the first
## try and they band: three rings of flat alpha read as three rings.
static var _pool_texture: GradientTexture2D
const GUTTER_SPACING := RoofLayout.GUTTER_SPACING
const GUTTER_OFFSET := RoofLayout.GUTTER_OFFSET
const TILE_OVERDRAW := 2.0

var draw_origin := Vector2.ZERO
var draw_margin := VIEW_MARGIN
## The additive layer for the warm pools. A child, so it follows wherever the
## floor is adopted and sits one z-step above it, still below every actor.
var glow: GlowLayer


## Shorthand for the grade every ground surface goes through, so the palette
## below reads as the colours the roof was painted in rather than as the
## colours it happens to be lit by tonight.
func _lit(color: Color, facing := 0.0) -> Color:
	return Moonlight.ground(color, facing)


func _ready() -> void:
	z_index = -20
	glow = GlowLayer.new()
	glow.name = "RoofLightPools"
	glow.painter = _paint_light_pools
	glow.material = Moonlight.additive()
	glow.z_as_relative = true
	glow.z_index = 1
	add_child(glow)


## Redraws both halves: the floor and its light pools. The moonlight switch and
## anything else that changes how the roof is graded calls this.
func refresh() -> void:
	queue_redraw()
	if is_instance_valid(glow):
		glow.queue_redraw()


## Called from the camera update. Snapping to REDRAW_STEP means the window is
## rebuilt a few times a minute rather than every frame.
func follow(focus: Vector2, coverage := VIEW_MARGIN) -> void:
	var margin := maxf(VIEW_MARGIN, ceilf(coverage / REDRAW_STEP) * REDRAW_STEP)
	var snapped_focus := (focus / REDRAW_STEP).floor() * REDRAW_STEP
	if snapped_focus.is_equal_approx(draw_origin) and is_equal_approx(margin, draw_margin):
		return
	draw_origin = snapped_focus
	draw_margin = margin
	refresh()


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

	# The upright half of the furniture is owned by RooftopPropField, because
	# each piece needs its own y-sort key for survivors to pass behind it. What
	# lies flat on the roof is painted here, once per window.
	var window := Rect2(low, high - low)
	for decal in RoofLayout.decals_in(window.grow(120.0)):
		_draw_decal(decal)
	for piece in RoofLayout.pieces_in(window.grow(RoofLayout.SHADOW_REACH)):
		_draw_piece_shadow(piece)
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


# --- The floor half of the furniture --------------------------------------------

func _draw_piece_shadow(piece: Dictionary) -> void:
	var tone := Color(Moonlight.SHADOW_INK, SHADOW_ALPHA if Moonlight.enabled else SHADOW_ALPHA * 0.7)
	draw_set_transform(piece["at"])
	for polygon in _merged(RoofLayout.shadow_polygons(piece)):
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, tone)
	draw_set_transform(Vector2.ZERO)
	# Contact shade: a tight dark rim right where each foot meets the roof. The
	# long moon shadow says which way the light is; this is what says the thing
	# is standing on the floor and not hovering a pixel above it.
	var contact := Color(Moonlight.SHADOW_INK, CONTACT_ALPHA)
	for foot in RoofLayout.footprints(piece):
		var local := Rect2(foot.position - (piece["at"] as Vector2), foot.size)
		draw_set_transform(piece["at"])
		if foot.size.x <= 14.0:
			draw_set_transform(piece["at"] as Vector2 + local.get_center(), 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, foot.size.x * 0.9 + 2.0, contact)
		else:
			draw_rect(local.grow(3.0), contact)
		draw_set_transform(Vector2.ZERO)


## Unions a piece's shadow primitives so overlaps are not darker than the rest.
## Holes are dropped: a shadow with a gap between two stilts is the one case
## that would keep one, and at this alpha the gap is not worth a second pass.
func _merged(polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var shapes: Array[PackedVector2Array] = []
	for polygon in polygons:
		var current := polygon
		var index := 0
		while index < shapes.size():
			if Geometry2D.intersect_polygons(shapes[index], current).is_empty():
				index += 1
				continue
			current = _outer(Geometry2D.merge_polygons(shapes[index], current))
			shapes.remove_at(index)
			# The grown shape may now reach one that was already passed over.
			index = 0
		shapes.append(current)
	return shapes


func _outer(pieces: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for piece in pieces:
		var area := 0.0
		for index in piece.size():
			var a := piece[index]
			var b := piece[(index + 1) % piece.size()]
			area += a.x * b.y - b.x * a.y
		if absf(area) > best_area:
			best_area = absf(area)
			best = piece
	return best


func _draw_decal(decal: Dictionary) -> void:
	var at: Vector2 = decal["at"]
	var size := float(decal["size"])
	var variant := int(decal["variant"])
	match String(decal["kind"]):
		"puddle":
			_puddle(at, size, variant)
		"moss":
			_moss(at, size, variant)
		"leaves":
			_leaves(at, size, variant)
		"crack":
			_crack(at, size, variant)
		"chalk":
			_chalk(at, size, variant)
		"drain":
			_drain(at, size)
		"stain":
			_stain(at, size, variant)
		"fishbone":
			_fishbone(at, size, variant)
		"paws":
			_paw_trail(at, size, variant)
		"conduit":
			_conduit(at, size)


func _blob(centre: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(centre, 0.0, radius / maxf(0.001, radius.x))
	draw_circle(Vector2.ZERO, radius.x, color)
	draw_set_transform(Vector2.ZERO)


## Standing water, which on a night roof is a mirror: the sky's colour a shade
## lighter than the paving around it, and the moon in it as one pale fleck.
func _puddle(at: Vector2, size: float, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	var lobes: Array[Vector3] = [Vector3(0, 0, size)]
	for lobe in 2:
		lobes.append(Vector3(rng.randf_range(-0.6, 0.6) * size, rng.randf_range(-0.2, 0.25) * size, size * rng.randf_range(0.45, 0.7)))
	for lobe in lobes:
		_blob(at + Vector2(lobe.x, lobe.y), Vector2(lobe.z + 3.0, (lobe.z + 3.0) * 0.5), _lit(Color("16252d", 0.55)))
	for lobe in lobes:
		_blob(at + Vector2(lobe.x, lobe.y), Vector2(lobe.z, lobe.z * 0.5), _lit(Color("2a4453", 0.85)))
	for lobe in lobes:
		_blob(at + Vector2(lobe.x, lobe.y + lobe.z * 0.08), Vector2(lobe.z * 0.8, lobe.z * 0.36), _lit(Color("365666", 0.7)))
	if Moonlight.enabled:
		var moon := at + Vector2(-size * 0.25, -size * 0.1)
		_blob(moon, Vector2(size * 0.16, size * 0.09), Color(Moonlight.MOON, 0.42))
		draw_line(moon + Vector2(-size * 0.3, size * 0.12), moon + Vector2(size * 0.35, size * 0.12), Color(Moonlight.MOON, 0.12), 1.6)
		draw_arc(at, size * 0.92, PI * 1.12, PI * 1.62, 10, Color(Moonlight.MOON, 0.18), 1.4, true)


func _moss(at: Vector2, size: float, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	for patch in 7:
		var spot := at + Vector2(rng.randf_range(-1.0, 1.0) * size, rng.randf_range(-0.5, 0.5) * size)
		var radius := rng.randf_range(0.12, 0.3) * size
		_blob(spot, Vector2(radius, radius * 0.6), _lit(Color("3b5a42", 0.7)))
		_blob(spot + Vector2(-radius * 0.2, -radius * 0.15), Vector2(radius * 0.6, radius * 0.35), _lit(Color("557a55", 0.6), 0.1))
	for tuft in 4:
		var base := at + Vector2(rng.randf_range(-0.8, 0.8) * size, rng.randf_range(-0.3, 0.4) * size)
		for blade in 3:
			var lean := (float(blade) - 1.0) * 0.45 + rng.randf_range(-0.15, 0.15)
			draw_line(base, base + Vector2(sin(lean) * 7.0, -cos(lean) * 8.0), _lit(Color("6f9161"), 0.12), 1.4, true)


func _leaves(at: Vector2, size: float, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	var tones := [Color("8a6a3a"), Color("9a5a3a"), Color("6f7a44"), Color("a4803f")]
	for leaf in rng.randi_range(6, 10):
		var spot := at + Vector2(rng.randf_range(-1.0, 1.0) * size, rng.randf_range(-0.5, 0.5) * size)
		var turn := rng.randf() * TAU
		var tone: Color = tones[rng.randi() % tones.size()]
		draw_set_transform(spot, turn, Vector2(1.0, 0.45))
		draw_circle(Vector2(1.5, 1.5), 6.0, Color(Moonlight.SHADOW_INK, 0.25))
		draw_circle(Vector2.ZERO, 6.0, _lit(tone, 0.12))
		draw_set_transform(Vector2.ZERO)
		draw_line(spot - Vector2.from_angle(turn) * 6.0, spot + Vector2.from_angle(turn) * 6.0, _lit(tone).darkened(0.3), 1.0, true)


## A crack in the screed: a dark channel with its far lip catching the moon.
func _crack(at: Vector2, size: float, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	var heading := rng.randf() * TAU
	var points := PackedVector2Array([at])
	var cursor := at
	for step in 6:
		heading += rng.randf_range(-0.7, 0.7)
		cursor += Vector2.from_angle(heading) * size / 6.0
		points.append(cursor)
	draw_polyline(points, _lit(Color("0f1b20", 0.8)), 2.0, true)
	var lip := PackedVector2Array()
	for point in points:
		lip.append(point + Vector2(0, -1.4))
	draw_polyline(lip, _lit(Color("55676a", 0.35), 0.2), 1.0, true)
	var fork := points[3]
	draw_polyline(PackedVector2Array([fork, fork + Vector2.from_angle(heading + 1.2) * size * 0.2,
		fork + Vector2.from_angle(heading + 0.8) * size * 0.34]), _lit(Color("0f1b20", 0.7)), 1.4, true)


## Somebody's chalk drawing, half worn away by rain.
func _chalk(at: Vector2, size: float, variant: int) -> void:
	var chalk := Color(0.92, 0.94, 0.98, 0.13)
	var s := size / 40.0
	match variant % 4:
		0:
			draw_arc(at, 20.0 * s, 0.0, TAU, 24, chalk, 2.4, true)
			for side: float in [-1.0, 1.0]:
				draw_polyline(PackedVector2Array([at + Vector2(side * 8.0, -18.0) * s, at + Vector2(side * 17.0, -30.0) * s,
					at + Vector2(side * 19.0, -10.0) * s]), chalk, 2.4, true)
				draw_circle(at + Vector2(side * 7.0, -3.0) * s, 2.4 * s, chalk)
				for whisker in 2:
					draw_line(at + Vector2(side * 10.0, 4.0 + whisker * 4.0) * s, at + Vector2(side * 28.0, 1.0 + whisker * 7.0) * s, chalk, 1.6, true)
		1:
			_fish(at, chalk, 0.9 * s)
		2:
			# Hopscotch: single, single, double, single.
			var cells := [Vector2(0, 0), Vector2(0, -1), Vector2(-0.5, -2), Vector2(0.5, -2), Vector2(0, -3)]
			for cell: Vector2 in cells:
				draw_rect(Rect2(at + Vector2(cell.x * 28.0 - 14.0, cell.y * 20.0) * s, Vector2(28, 20) * s), chalk, false, 2.0)
		_:
			# Filled shapes are triangulated about their own anchor; see
			# RoofLayout.shadow_polygons for why absolute coordinates fail far out.
			draw_set_transform(at, 0.0, Vector2.ONE * s)
			draw_circle(Vector2(-6, -4), 7.0, chalk)
			draw_circle(Vector2(6, -4), 7.0, chalk)
			draw_colored_polygon(PackedVector2Array([Vector2(-13, -1), Vector2(13, -1), Vector2(0, 14)]), chalk)
			draw_set_transform(Vector2.ZERO)


func _drain(at: Vector2, size: float) -> void:
	_blob(at, Vector2(size + 4.0, (size + 4.0) * 0.62), _lit(Color("5a6966"), 0.1))
	_blob(at, Vector2(size, size * 0.62), _lit(Color("0e171b")))
	for slot in 5:
		var x := (float(slot) - 2.0) * size * 0.34
		var reach := sqrt(maxf(0.0, 1.0 - pow(x / size, 2.0))) * size * 0.5
		draw_line(at + Vector2(x, -reach), at + Vector2(x, reach), _lit(Color("5a6966"), 0.15), 1.8)


func _stain(at: Vector2, size: float, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	for spot in 4:
		var offset := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3)) * size
		var radius := rng.randf_range(0.35, 0.7) * size
		_blob(at + offset, Vector2(radius, radius * 0.55), Color(Moonlight.SHADOW_INK, 0.16))


## The remains of somebody's dinner. On this roof, a fish.
func _fishbone(at: Vector2, size: float, variant: int) -> void:
	var bone := _lit(Color("d8d2c0", 0.7), 0.2)
	var turn := float(variant % 628) * 0.01
	draw_set_transform(at, turn, Vector2(1.0, 0.6))
	draw_line(Vector2(-size, 0), Vector2(size, 0), bone, 1.6, true)
	for rib in 4:
		var x := -size * 0.55 + float(rib) * size * 0.3
		draw_line(Vector2(x, -size * 0.35), Vector2(x + size * 0.12, size * 0.35), bone, 1.2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(size, 0), Vector2(size * 1.5, -size * 0.3), Vector2(size * 1.5, size * 0.3)]), bone)
	draw_polyline(PackedVector2Array([Vector2(-size * 1.35, -size * 0.35), Vector2(-size, 0), Vector2(-size * 1.35, size * 0.35)]), bone, 1.6, true)
	draw_set_transform(Vector2.ZERO)


func _paw_trail(at: Vector2, size: float, variant: int) -> void:
	var paw := _lit(Color("58675f", 0.8))
	var heading := float(variant % 628) * 0.01
	for step in 6:
		var along := Vector2.from_angle(heading) * (float(step) - 2.5) * size / 5.0
		var side := Vector2.from_angle(heading + PI * 0.5) * (6.0 if step % 2 == 0 else -6.0)
		var spot := at + along + side
		draw_circle(spot, 3.4, paw)
		for toe in 3:
			draw_circle(spot + Vector2.from_angle(heading + (float(toe) - 1.0) * 0.6) * 6.0, 1.7, paw)


## Low conduit running along the roof. Barely off the floor, so it belongs to
## the floor layer: a cat stepping over it is always in front of it.
func _conduit(at: Vector2, length: float) -> void:
	var start := at - Vector2(length * 0.5, 0.0)
	for lane in 2:
		var y := float(lane) * 11.0
		var a := start + Vector2(0.0, y)
		var b := a + Vector2(length, 0.0)
		draw_line(a + Vector2(2, 4), b + Vector2(2, 4), Color(Moonlight.SHADOW_INK, 0.3), 7.0)
		draw_line(a, b, _lit(Color("6d7c7c")).darkened(0.25), 6.0)
		draw_line(a + Vector2(0, -2), b + Vector2(0, -2), _lit(Color("8e9d9b"), 0.35), 1.6)
	var brackets := int(length / 60.0)
	for bracket in brackets + 1:
		var x := start.x + float(bracket) * length / maxf(1.0, float(brackets))
		draw_rect(Rect2(Vector2(x - 3.0, start.y - 5.0), Vector2(6.0, 21.0)), _lit(Color("4a5758")))


## The warm pools thrown on the roof by its own lights. Drawn by the child
## GlowLayer, additively, and only while the moonlight pass is on — with it off
## the roof is flat-lit and a pool would be a yellow stain.
func _paint_light_pools(layer: CanvasItem) -> void:
	if not Moonlight.enabled:
		return
	var window := Rect2(draw_origin - Vector2(draw_margin, draw_margin), Vector2(draw_margin, draw_margin) * 2.0)
	for piece in RoofLayout.pieces_in(window.grow(200.0)):
		var info := RoofLayout.spec(String(piece["kind"]))
		for pool in info.get("glow", []):
			var centre: Vector2 = piece["at"] + Vector2(float(pool[0]), -float(pool[1]))
			var radius := float(pool[2])
			var size := Vector2(radius * 2.0, radius * 1.1)
			layer.draw_texture_rect(_pool(), Rect2(centre - size * 0.5, size), false, Color(POOL_TINT, POOL_ALPHA))


static func _pool() -> GradientTexture2D:
	if _pool_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.45))
		_pool_texture = GradientTexture2D.new()
		_pool_texture.gradient = gradient
		_pool_texture.fill = GradientTexture2D.FILL_RADIAL
		_pool_texture.fill_from = Vector2(0.5, 0.5)
		_pool_texture.fill_to = Vector2(1.0, 0.5)
		_pool_texture.width = 128
		_pool_texture.height = 128
	return _pool_texture
