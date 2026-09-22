class_name RooftopSection
extends Node2D
## One roof of one building, with edges you can see the thickness of.
##
## The rooftop in a run is endless — it is generated around the camera so the
## pair can kite forever without finding a wall. That is the right call for the
## run and the wrong one for answering "does this read as a roof?", because a
## surface with no edge has no thickness to show: the whole idea of height is
## carried by the moment the floor stops and you can see how far down the next
## thing is. So this is a bounded plate, sized to a few screens, and it is what
## the height work is judged on before any of it is taken back to the endless
## floor.
##
## The plate is drawn across four depths, because a wall around a play field is
## never at one depth:
##
##   floor        this node: the paving and its gutters, cut into a grid and
##                projected quad by quad so the plate comes out as a trapezoid.
##                Cells are clipped to the plate before they are projected, so
##                nothing is ever drawn past the edge.
##   backdrop     the drop past the far parapet, the low buildings below and
##                their signs. Above the trim and below everything else, and the
##                only layer that moves at a different rate from the world.
##   walls        the far and side parapets. Behind the actors, because a cat
##                inside the plate is always in front of them, and they close
##                the seam between the trim and the city exactly.
##   near edge    the parapet along the bottom of the plate and this building's
##                own wall dropping away under it. In front of the actors, since
##                a cat at the south edge is standing behind that wall — which
##                is also the cheapest possible demonstration that the roof has
##                a front face at all.
##
## The parapet is the one piece of scenery on this roof that a cat genuinely
## cannot walk through. Everything else up here is decoration, and the prototype
## stage clamps the pair to `bounds` so the wall never lies about that.
##
## Every measurement in this file is in world coordinates on the flat ground
## plane. The trapezoid is entirely the projection's doing — nothing here knows
## how wide its own far edge ends up.

const SLATE := preload("res://assets/environment/moonroof_slate_tile_v2.png")
## How thick the parapet is on the ground, and how far it rises off the floor.
const PARAPET_DEPTH := 34.0
const PARAPET_HEIGHT := 54.0
const GUTTER_SPACING := 640.0
## How many times each slate tile is cut up before it is laid down. The grid
## has to be fine enough that one cell drawn at a flat texture rate is not
## visibly wrong under the perspective, and coarse enough that a plate is a few
## hundred quads rather than a few thousand.
const TILE_SUBDIVISIONS := 8
## How much of the camera's travel the distant city keeps, so it lags the roof
## instead of sliding with it. Horizontal only: the skyline has to stay tucked
## behind the far parapet, and a vertical lag is what breaks that seam.
const SKYLINE_LAG := 0.72
## And the row of roofs immediately below this one, which has to lag *less* than
## the far city or the two read as one flat painting. Two rates is the smallest
## number that makes a distance out of a backdrop.
const NEAR_LAG := 0.88
const NEAR_PERIOD := 1100.0
## The city repeats over this many world units. Long enough that the pair never
## catches it looping inside one plate, short enough to generate on demand.
const SKYLINE_PERIOD := 2600.0
const SKY := Color("070c16")
const PARAPET_COLOR := Color("36444a")
const WALL_COLOR := Color("1b2129")
## How far the building's own face drops below the near parapet, and how much
## wider it is at the bottom than at the top. The splay is the perspective of a
## wall seen from above its own top edge.
const WALL_DROP := 300.0
const WALL_SPLAY := 1.22

var bounds := Rect2(-750.0, -700.0, 1500.0, 1400.0)


func _ready() -> void:
	z_index = -26


## Where the far parapet's own top edge sits on screen. The stage keeps the
## camera from climbing past it, so the view never shows the plate floating in
## the middle of nothing.
## Where the far parapet's own top-back corner lands on screen. Everything the
## roof looks out over is drawn above this line, and the stage keeps the camera
## from climbing past it — so the view never shows the plate floating in the
## middle of nothing.
func far_limit() -> float:
	var back := Vector2(bounds.get_center().x, bounds.position.y - PARAPET_DEPTH)
	return RooftopSpace.raised(back, PARAPET_HEIGHT).y


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:rooftop_section", probe_started)


func _probed_draw() -> void:
	_draw_paving()
	_draw_gutters()


## Far and side walls, drawn from their own footprints on the roof rather than
## from screen rectangles. The far parapet is the piece of architecture the
## perspective is easiest to read on: its two long edges are at different depths,
## so the wall is a trapezoid and its lid is a shallower trapezoid above it.
func draw_walls(canvas: CanvasItem) -> void:
	var outer := bounds.grow(PARAPET_DEPTH)
	var near_left := Vector2(outer.position.x, bounds.position.y)
	var near_right := Vector2(outer.end.x, bounds.position.y)
	var back_left := Vector2(outer.position.x, outer.position.y)
	var back_right := Vector2(outer.end.x, outer.position.y)
	# The face turned toward the play field, then the lid over it. Drawn in that
	# order so the lit top sits on the shaded front the way it does on a box.
	canvas.draw_colored_polygon(PackedVector2Array([
		RooftopSpace.project(near_left), RooftopSpace.project(near_right),
		RooftopSpace.raised(near_right, PARAPET_HEIGHT), RooftopSpace.raised(near_left, PARAPET_HEIGHT),
	]), RooftopSpace.front_face(PARAPET_COLOR))
	canvas.draw_colored_polygon(PackedVector2Array([
		RooftopSpace.raised(back_left, PARAPET_HEIGHT), RooftopSpace.raised(back_right, PARAPET_HEIGHT),
		RooftopSpace.raised(near_right, PARAPET_HEIGHT), RooftopSpace.raised(near_left, PARAPET_HEIGHT),
	]), RooftopSpace.top_face(PARAPET_COLOR))
	if Moonlight.enabled:
		canvas.draw_line(RooftopSpace.raised(near_left, PARAPET_HEIGHT),
			RooftopSpace.raised(near_right, PARAPET_HEIGHT), RooftopSpace.lip(PARAPET_COLOR), 2.0)
	for side: float in [-1.0, 1.0]:
		# Seen from a camera with no yaw, a side wall has no face turned toward
		# the viewer — only its lid, which is a long thin trapezoid running from
		# the far end of the plate to the near one, and a dark seam where it
		# meets the floor.
		var inner_x := bounds.position.x if side < 0.0 else bounds.end.x
		var outer_x := outer.position.x if side < 0.0 else outer.end.x
		canvas.draw_colored_polygon(PackedVector2Array([
			RooftopSpace.raised(Vector2(outer_x, outer.position.y), PARAPET_HEIGHT),
			RooftopSpace.raised(Vector2(inner_x, outer.position.y), PARAPET_HEIGHT),
			RooftopSpace.raised(Vector2(inner_x, outer.end.y), PARAPET_HEIGHT),
			RooftopSpace.raised(Vector2(outer_x, outer.end.y), PARAPET_HEIGHT),
		]), RooftopSpace.top_face(PARAPET_COLOR))
		canvas.draw_polyline(RooftopSpace.project_all(PackedVector2Array([
			Vector2(inner_x, bounds.position.y), Vector2(inner_x, outer.end.y),
		])), RooftopSpace.front_face(PARAPET_COLOR).darkened(0.3), 3.0)


## The slate the run already uses, laid down one quad at a time.
##
## A projected floor cannot be a stretched texture rectangle: the four corners
## of a patch of roof do not make a rectangle on screen any more, and the rate
## the texture runs at has to change across the patch. So the plate is cut into
## a grid, every corner is projected, and each cell is drawn as its own quad
## with the slice of slate that belongs to it.
##
## The grid is aligned to the tile and subdivided a fixed number of times, which
## matters for two reasons: no cell ever straddles a tile boundary, so the
## alternating mirror stays exact; and the cells are small enough that drawing
## each one with a flat texture rate is not visibly wrong. Cells are clipped to
## the plate in world coordinates before projecting, which is also what retired
## the mask this used to need — nothing is drawn past the edge in the first
## place.
func _draw_paving() -> void:
	var tile := SLATE.get_size()
	var step := tile / float(TILE_SUBDIVISIONS)
	_draw_plate_fill()
	var first := Vector2i(int(floor(bounds.position.x / step.x)), int(floor(bounds.position.y / step.y)))
	var last := Vector2i(int(ceil(bounds.end.x / step.x)), int(ceil(bounds.end.y / step.y)))
	for cell_y in range(first.y, last.y):
		for cell_x in range(first.x, last.x):
			var cell := Rect2(Vector2(cell_x, cell_y) * step, step)
			var clipped := cell.intersection(bounds)
			if clipped.size.x <= 0.01 or clipped.size.y <= 0.01:
				continue
			draw_colored_polygon(RooftopSpace.floor_quad(clipped),
				Moonlight.ground(Color("d1dcda")), _slate_uvs(clipped, tile), SLATE)


## The plate's own silhouette, under the paving, so a seam between two quads can
## never show the sky through the floor.
func _draw_plate_fill() -> void:
	draw_colored_polygon(RooftopSpace.floor_quad(bounds), Moonlight.ground(Color("23383e")))


## Where a patch of roof sits inside the slate, with the alternating mirror
## folded into the coordinates rather than into a transform — a projected quad
## has no transform left to spend on flipping.
func _slate_uvs(patch: Rect2, tile: Vector2) -> PackedVector2Array:
	var tile_x := int(floor(patch.get_center().x / tile.x))
	var tile_y := int(floor(patch.get_center().y / tile.y))
	var flip_x := posmod(tile_x, 2) != 0
	var flip_y := posmod(tile_y, 2) != 0
	var low := Vector2(
		(patch.position.x - float(tile_x) * tile.x) / tile.x,
		(patch.position.y - float(tile_y) * tile.y) / tile.y)
	var high := Vector2(
		(patch.end.x - float(tile_x) * tile.x) / tile.x,
		(patch.end.y - float(tile_y) * tile.y) / tile.y)
	if flip_x:
		var swap_x := low.x
		low.x = 1.0 - high.x
		high.x = 1.0 - swap_x
	if flip_y:
		var swap_y := low.y
		low.y = 1.0 - high.y
		high.y = 1.0 - swap_y
	return PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])


## Gutters fall on half-spacings rather than on multiples, which keeps one of
## them off the plate's centre line. A dark channel straight down the middle of
## the opening view reads as a debug overlay, not as drainage — the endless
## floor in the run learned the same lesson about the terrace.
func _draw_gutters() -> void:
	var at := (floorf(bounds.position.x / GUTTER_SPACING) + 0.5) * GUTTER_SPACING
	while at < bounds.end.x:
		if at > bounds.position.x:
			var channel := Rect2(at - 7.0, bounds.position.y, 14.0, bounds.size.y)
			draw_colored_polygon(RooftopSpace.floor_quad(channel), Moonlight.ground(Color("1e333a")))
			# A gutter is a channel, so its far wall is the one the moon reaches
			# and its near wall is the one in shade — the same two-face rule as a
			# box, on a surface that goes down instead of up. In perspective both
			# walls converge toward the vanishing point, which is the clearest
			# single statement of depth anywhere on the plate.
			_drain_edge(channel.position.x, Moonlight.ground(Color("53625d"), 0.26))
			_drain_edge(channel.end.x, Moonlight.ground(Color("53625d")).darkened(0.35))
		at += GUTTER_SPACING


func _drain_edge(x: float, tint: Color) -> void:
	draw_polyline(RooftopSpace.project_all(PackedVector2Array([
		Vector2(x, bounds.position.y), Vector2(x, bounds.end.y),
	])), tint, 2.0)


## Everything past the far parapet: the night, the drop, the low buildings this
## roof looks down on, and their signs. Drawn by whichever node owns the lag, so
## the city trails the roof when the camera moves.
##
## The band stops dead at the horizon. Below that line is the parapet's own
## business, and a city drawn one pixel past it would be a city painted across
## the floor the fight happens on.
func draw_backdrop(canvas: CanvasItem) -> void:
	var horizon := far_limit()
	var span := bounds.size.x + SKYLINE_PERIOD * 2.0
	var left := bounds.get_center().x - span * 0.5
	canvas.draw_rect(Rect2(left, horizon - 1400.0, span, 1400.0), SKY)
	# The lamps in the streets between the blocks, laid down before the blocks
	# so the buildings cut into the glow instead of sitting on top of it. This
	# is the only warm thing in the backdrop and it is kept to a smear: the roof
	# is the lit place in this picture and the city below it is not.
	canvas.draw_rect(Rect2(left, horizon - 30.0, span, 30.0), Color(Color("ffb26b"), 0.05))
	_draw_skyline(canvas, left, span, horizon)


func _draw_skyline(canvas: CanvasItem, left: float, span: float, horizon: float) -> void:
	var first := int(floor(left / 120.0))
	var count := int(span / 120.0)
	for index in count:
		var slot := first + index
		var rng := RandomNumberGenerator.new()
		# Seeded from the slot, wrapped to the period, so the city is the same
		# city every time the pair looks at it and still repeats forever.
		rng.seed = posmod(slot, int(SKYLINE_PERIOD / 120.0)) * 2654435761 + 20260913
		var at := float(slot) * 120.0 + rng.randf_range(0.0, 22.0)
		# Narrower than their slot, so there are gaps to see the streets through.
		# A solid wall of blocks reads as a cliff face standing behind the roof,
		# which is the opposite of the thing this backdrop exists to say.
		var block_width := rng.randf_range(52.0, 96.0)
		# Low. The pair is meant to be looking *down* on these, so the tallest of
		# them clears the parapet by about a cat's height and most do not.
		var block_height := rng.randf_range(26.0, 118.0)
		var top := horizon - block_height
		# Distant buildings are further from the moon than the roof is and are
		# meant to sit behind the fight, so they are painted near the value of
		# the sky itself. A skyline with real contrast pulls the eye off the
		# floor, which is where the whole fight happens.
		var block := Color("121b2b").lerp(SKY, clampf(block_height / 320.0, 0.0, 0.6))
		canvas.draw_rect(Rect2(at, top, block_width, block_height + 60.0), block)
		# The lid of a building below is the one face of it the moon reaches,
		# and it is the whole reason the city says "you are above this".
		canvas.draw_rect(Rect2(at, top, block_width, 7.0), block.lightened(0.22))
		_draw_windows(canvas, rng, Rect2(at, top + 7.0, block_width, block_height))
		if rng.randf() < 0.3 and block_height > 62.0:
			_draw_sign(canvas, rng, Vector2(at + block_width * 0.5, top - 4.0))


## The roofs directly below this one. Nearer, wider and flatter than the city
## behind them, and drawn almost in silhouette: their job is to be the middle
## distance the far skyline is measured against, not to be looked at.
func draw_near_city(canvas: CanvasItem) -> void:
	var horizon := far_limit()
	var span := bounds.size.x + NEAR_PERIOD * 2.0
	var left := bounds.get_center().x - span * 0.5
	var first := int(floor(left / 210.0))
	for index in int(span / 210.0):
		var slot := first + index
		var rng := RandomNumberGenerator.new()
		rng.seed = posmod(slot, int(NEAR_PERIOD / 210.0)) * 40503 + 20260914
		var at := float(slot) * 210.0 + rng.randf_range(0.0, 40.0)
		var width := rng.randf_range(150.0, 205.0)
		# Low enough that most of them clear the parapet by a hair. A near roof
		# that stood tall would be a wall, and the pair is meant to be above all
		# of this.
		var rise := rng.randf_range(10.0, 46.0)
		var top := horizon - rise
		canvas.draw_rect(Rect2(at, top, width, rise + 90.0), Color("0c1421"))
		canvas.draw_rect(Rect2(at, top, width, 5.0), Color("1b2740"))
		# One water tank or vent housing per roof, which is the detail that says
		# these are roofs and not blocks.
		if rng.randf() < 0.55:
			var box := Vector2(rng.randf_range(22.0, 40.0), rng.randf_range(14.0, 26.0))
			var spot := Vector2(at + rng.randf_range(16.0, width - box.x - 16.0), top - box.y)
			canvas.draw_rect(Rect2(spot, box), Color("0c1421"))
			canvas.draw_rect(Rect2(spot, Vector2(box.x, 4.0)), Color("1b2740"))


func _draw_windows(canvas: CanvasItem, rng: RandomNumberGenerator, block: Rect2) -> void:
	var columns := maxi(1, int(block.size.x / 22.0))
	var rows := maxi(1, int(block.size.y / 26.0))
	for row in rows:
		for column in columns:
			if rng.randf() > 0.28:
				continue
			var at := block.position + Vector2(7.0 + float(column) * 22.0, 9.0 + float(row) * 26.0)
			if at.x > block.end.x - 8.0 or at.y > block.end.y - 6.0:
				continue
			# Lit windows are the only warm thing down there and they are still
			# kept faint. They are texture for the drop, not a light source the
			# roof is supposed to answer to.
			canvas.draw_rect(Rect2(at, Vector2(6.0, 8.0)), Color("ffd9a0", 0.14 + rng.randf() * 0.14))


## A rooftop sign on one of the buildings below. Two layers, the way every other
## emitting thing in this game is built: a body that stays normally blended so
## it keeps an edge, and a separate halo that adds light.
func _draw_sign(canvas: CanvasItem, rng: RandomNumberGenerator, at: Vector2) -> void:
	var tint: Color = [Color("ff5d8f"), Color("43d9ff"), Color("fff275")][rng.randi() % 3]
	var size := Vector2(rng.randf_range(34.0, 58.0), rng.randf_range(16.0, 26.0))
	var frame := Rect2(at - Vector2(size.x * 0.5, size.y), size)
	canvas.draw_rect(frame, Color("0d1422"))
	canvas.draw_rect(frame, Color(tint, 0.5), false, 2.0)
	for stroke in 3:
		var y := frame.position.y + 5.0 + float(stroke) * (size.y - 10.0) * 0.5
		canvas.draw_line(Vector2(frame.position.x + 6.0, y), Vector2(frame.end.x - 6.0, y), Color(tint, 0.34), 1.6)
	canvas.draw_line(Vector2(at.x, at.y), Vector2(at.x, at.y + 14.0), Color("1b2432"), 3.0)


## The near wall: the parapet along the bottom of the plate, the outside of this
## building dropping away under it, and the dark the street is in. Drawn in
## front of the actors, so walking down to the edge puts a cat behind it.
##
## This is the one surface the camera sees face-on, and it is where the whole
## plate is finally told on: it is the only place the viewer is shown, in one
## unambiguous picture, how thick the roof is and how far off the ground it
## sits. In perspective it is also the widest thing on screen — the near edge is
## the closest row of the world — so it splays outward as it drops rather than
## dropping straight, the way the sides of a box do when you look down into it.
func draw_near_edge(canvas: CanvasItem) -> void:
	var outer := bounds.grow(PARAPET_DEPTH)
	var near_left := Vector2(outer.position.x, outer.end.y)
	var near_right := Vector2(outer.end.x, outer.end.y)
	var back_left := Vector2(outer.position.x, bounds.end.y)
	var back_right := Vector2(outer.end.x, bounds.end.y)
	# The lid first, then the face under it: on the near side the front band is
	# what the cat stands behind, so it is drawn last and wins the overlap.
	canvas.draw_colored_polygon(PackedVector2Array([
		RooftopSpace.raised(back_left, PARAPET_HEIGHT), RooftopSpace.raised(back_right, PARAPET_HEIGHT),
		RooftopSpace.raised(near_right, PARAPET_HEIGHT), RooftopSpace.raised(near_left, PARAPET_HEIGHT),
	]), RooftopSpace.top_face(PARAPET_COLOR))
	var foot_left := RooftopSpace.project(near_left)
	var foot_right := RooftopSpace.project(near_right)
	canvas.draw_colored_polygon(PackedVector2Array([
		foot_left, foot_right,
		RooftopSpace.raised(near_right, PARAPET_HEIGHT), RooftopSpace.raised(near_left, PARAPET_HEIGHT),
	]), RooftopSpace.front_face(PARAPET_COLOR))
	if Moonlight.enabled:
		canvas.draw_line(RooftopSpace.raised(near_left, PARAPET_HEIGHT),
			RooftopSpace.raised(near_right, PARAPET_HEIGHT), RooftopSpace.lip(PARAPET_COLOR), 2.0)

	var scale := RooftopSpace.view_scale(near_left.y)
	var drop := WALL_DROP * scale
	var splay := (foot_right.x - foot_left.x) * (WALL_SPLAY - 1.0) * 0.5
	var bottom_left := Vector2(foot_left.x - splay, foot_left.y + drop)
	var bottom_right := Vector2(foot_right.x + splay, foot_right.y + drop)
	canvas.draw_colored_polygon(PackedVector2Array([foot_left, foot_right, bottom_right, bottom_left]),
		Moonlight.ground(WALL_COLOR))
	canvas.draw_line(foot_left, foot_right, RooftopSpace.lip(WALL_COLOR).darkened(0.4), 2.0)
	_draw_wall_windows(canvas, foot_left, foot_right, bottom_left, bottom_right)
	# The wall does not end, it falls away. Stepping the shade down the face is
	# what turns a flat band under the roof into a drop the roof is standing
	# over, and it starts almost immediately — the moon is up here, and nothing
	# four floors down is catching any of it.
	for step in 6:
		var low := float(step) / 6.0
		var high := float(step + 1) / 6.0
		canvas.draw_colored_polygon(PackedVector2Array([
			foot_left.lerp(bottom_left, low), foot_right.lerp(bottom_right, low),
			foot_right.lerp(bottom_right, high), foot_left.lerp(bottom_left, high),
		]), Color(Color("07060d"), 0.1 + float(step) * 0.15))


## Windows on our own wall are the one piece of this scene sitting directly
## under the fight, so they are kept nearly as dark as the wall and only a few
## of them are lit. An evenly lit grid here pulled the eye straight off the roof
## and read as a spreadsheet parked below the play field.
##
## Each one is placed by how far across and how far down the wall it is rather
## than in pixels, so they splay with the wall instead of sliding off it.
func _draw_wall_windows(canvas: CanvasItem, top_left: Vector2, top_right: Vector2,
		bottom_left: Vector2, bottom_right: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	var columns := maxi(4, int((top_right.x - top_left.x) / 108.0))
	for row in 3:
		var near := 0.14 + float(row) * 0.26
		var far := near + 0.13
		for column in columns:
			var across := (float(column) + 0.5) / float(columns)
			var pane := PackedVector2Array()
			for corner: Vector2 in [Vector2(-0.02, 0.0), Vector2(0.02, 0.0), Vector2(0.02, 1.0), Vector2(-0.02, 1.0)]:
				var depth := near if corner.y < 0.5 else far
				var left := top_left.lerp(bottom_left, depth)
				var right := top_right.lerp(bottom_right, depth)
				pane.append(left.lerp(right, clampf(across + corner.x, 0.0, 1.0)))
			canvas.draw_colored_polygon(pane, Moonlight.ground(WALL_COLOR).darkened(0.5))
			if rng.randf() < 0.24:
				canvas.draw_colored_polygon(pane, Color("ffd9a0", 0.09))
