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
##   floor        this node: the paving and its gutters, and the mask that
##                trims the paving back to the plate. The slate tile is over a
##                thousand pixels square, so a plate is only two or three tiles
##                and the last of them overruns the edge by most of a tile —
##                which is why the trim exists and why it has to be under the
##                city rather than over it.
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

const SLATE := preload("res://assets/environment/moonroof_slate_tile.png")
## How thick the parapet is on the ground, and how far it rises off the floor.
const PARAPET_DEPTH := 34.0
const PARAPET_HEIGHT := 54.0
const GUTTER_SPACING := 640.0
## How far the mirrored paving is allowed to reach past its own cell, to hide
## the doubled dark edge where two opposite copies meet.
const TILE_OVERDRAW := 2.0
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

var bounds := Rect2(-880.0, -600.0, 1760.0, 1200.0)


func _ready() -> void:
	z_index = -26


## Where the far parapet's own top edge sits on screen. The stage keeps the
## camera from climbing past it, so the view never shows the plate floating in
## the middle of nothing.
func far_limit() -> float:
	return bounds.position.y - PARAPET_DEPTH - PARAPET_HEIGHT * RooftopSpace.tilt()


func _draw() -> void:
	_draw_paving()
	_draw_gutters()


## Far and side walls. Each is a box in RooftopSpace, so the same top/front
## split the props use is what draws the architecture — there is only one rule
## on this roof for what a lifted surface looks like.
func draw_walls(canvas: CanvasItem) -> void:
	RooftopSpace.draw_box(canvas, Vector2(bounds.get_center().x, bounds.position.y),
		bounds.size.x + PARAPET_DEPTH * 2.0, PARAPET_DEPTH, PARAPET_HEIGHT, PARAPET_COLOR)
	for side: float in [-1.0, 1.0]:
		var x := bounds.get_center().x + side * (bounds.size.x * 0.5 + PARAPET_DEPTH * 0.5)
		# Seen from almost above, a side wall is its lid plus the thin dark seam
		# where it meets the floor. There is no face turned toward the camera,
		# so drawing one would be inventing an angle this view does not have.
		var lid := Rect2(x - PARAPET_DEPTH * 0.5, bounds.position.y, PARAPET_DEPTH, bounds.size.y)
		canvas.draw_rect(lid.grow_individual(0.0, 0.0, 0.0, PARAPET_DEPTH), RooftopSpace.top_face(PARAPET_COLOR))
		canvas.draw_line(Vector2(x - side * PARAPET_DEPTH * 0.5, bounds.position.y),
			Vector2(x - side * PARAPET_DEPTH * 0.5, bounds.end.y + PARAPET_DEPTH),
			RooftopSpace.front_face(PARAPET_COLOR).darkened(0.3), 3.0)


## The slate the run already uses, mirrored in alternating cells so opposite
## copies meet on the same source edge and the seams disappear. Clipped to the
## plate rather than windowed around a camera: this floor has an end.
func _draw_paving() -> void:
	draw_rect(bounds, Moonlight.ground(Color("23383e")))
	var tile := SLATE.get_size()
	var first := Vector2i(int(floor(bounds.position.x / tile.x)), int(floor(bounds.position.y / tile.y)))
	var last := Vector2i(int(ceil(bounds.end.x / tile.x)), int(ceil(bounds.end.y / tile.y)))
	for tile_y in range(first.y, last.y):
		for tile_x in range(first.x, last.x):
			var flip_x := posmod(tile_x, 2) != 0
			var flip_y := posmod(tile_y, 2) != 0
			var corner := Vector2(tile_x * tile.x, tile_y * tile.y)
			var pivot := corner + Vector2(tile.x if flip_x else 0.0, tile.y if flip_y else 0.0)
			draw_set_transform(pivot, 0.0, Vector2(-1.0 if flip_x else 1.0, -1.0 if flip_y else 1.0))
			draw_texture_rect(SLATE, Rect2(Vector2.ONE * -TILE_OVERDRAW, tile + Vector2.ONE * TILE_OVERDRAW * 2.0), false,
				Moonlight.ground(Color("d1dcda")))
	draw_set_transform(Vector2.ZERO)
	# Trim the paving back to the plate. The mask has to be a full tile deep,
	# because that is how far the last row of a tile this size can hang past the
	# edge, and the city is drawn in a layer *above* this one precisely so that
	# a mask this wide cannot paint over it.
	var trim := SLATE.get_size()
	draw_rect(Rect2(bounds.position - trim, Vector2(bounds.size.x + trim.x * 2.0, trim.y)), SKY)
	draw_rect(Rect2(Vector2(bounds.position.x - trim.x, bounds.end.y), Vector2(bounds.size.x + trim.x * 2.0, trim.y)), SKY)
	for side: float in [-1.0, 1.0]:
		var x := bounds.position.x - trim.x if side < 0.0 else bounds.end.x
		draw_rect(Rect2(Vector2(x, bounds.position.y - trim.y), Vector2(trim.x, bounds.size.y + trim.y * 2.0)), SKY)


## Gutters fall on half-spacings rather than on multiples, which keeps one of
## them off the plate's centre line. A dark channel straight down the middle of
## the opening view reads as a debug overlay, not as drainage — the endless
## floor in the run learned the same lesson about the terrace.
func _draw_gutters() -> void:
	var at := (floorf(bounds.position.x / GUTTER_SPACING) + 0.5) * GUTTER_SPACING
	while at < bounds.end.x:
		draw_rect(Rect2(at - 7.0, bounds.position.y, 14.0, bounds.size.y), Moonlight.ground(Color("1e333a")))
		# A gutter is a channel, so its far wall is the one the moon reaches and
		# its near wall is the one in shade — the same two-face rule as a box,
		# on a surface that goes down instead of up.
		draw_line(Vector2(at - 7.0, bounds.position.y), Vector2(at - 7.0, bounds.end.y),
			Moonlight.ground(Color("53625d"), 0.26), 2.0)
		draw_line(Vector2(at + 7.0, bounds.position.y), Vector2(at + 7.0, bounds.end.y),
			Moonlight.ground(Color("53625d")).darkened(0.35), 2.0)
		at += GUTTER_SPACING


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
## building dropping away under it, and the street it drops toward. Drawn in
## front of the actors, so walking down to the edge puts a cat behind it.
func draw_near_edge(canvas: CanvasItem) -> void:
	var base := Vector2(bounds.get_center().x, bounds.end.y + PARAPET_DEPTH)
	var width := bounds.size.x + PARAPET_DEPTH * 2.0
	RooftopSpace.draw_box(canvas, base, width, PARAPET_DEPTH, PARAPET_HEIGHT, PARAPET_COLOR)
	# Below the parapet the camera finally sees an outside wall face-on. This is
	# the single most useful surface on the whole plate: it is the only place the
	# viewer is told, in one unambiguous picture, how thick the roof is and how
	# far off the ground it sits.
	var wall := Rect2(base.x - width * 0.5, base.y, width, 460.0)
	canvas.draw_rect(wall, Moonlight.ground(WALL_COLOR))
	canvas.draw_line(Vector2(wall.position.x, wall.position.y), Vector2(wall.end.x, wall.position.y),
		RooftopSpace.lip(WALL_COLOR).darkened(0.4), 2.0)
	# Windows on our own wall are the one piece of this scene that sits directly
	# under the fight, so they are kept nearly as dark as the wall and only a
	# few of them are lit. An evenly lit grid here pulled the eye straight off
	# the roof and read as a spreadsheet parked below the play field.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	for row in 3:
		for column in int(width / 108.0):
			var at := Vector2(wall.position.x + 34.0 + float(column) * 108.0, wall.position.y + 62.0 + float(row) * 124.0)
			canvas.draw_rect(Rect2(at, Vector2(42.0, 56.0)), Moonlight.ground(WALL_COLOR).darkened(0.5))
			if rng.randf() < 0.24:
				canvas.draw_rect(Rect2(at + Vector2(3.0, 3.0), Vector2(36.0, 50.0)), Color("ffd9a0", 0.09))
	# The wall does not end, it falls away. Stepping the shade down the face is
	# what turns a flat rectangle under the roof into a drop the roof is
	# standing over, and it starts almost immediately — the moon is up here, and
	# nothing four floors down is catching any of it.
	for step in 6:
		var band := Rect2(wall.position.x, wall.position.y + 60.0 + float(step) * 68.0, wall.size.x, 68.0)
		canvas.draw_rect(band, Color(Color("07060d"), 0.12 + float(step) * 0.14))
