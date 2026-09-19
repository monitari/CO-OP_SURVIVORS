class_name ChainArc
extends Node2D
## The leash between the two cats, hung in space instead of ruled between them.
##
## In the run the chain is a Line2D: two points, one straight segment. That is
## the correct shape for the thing it damages along, and it is the wrong shape
## for a rope. A rope between two cats standing a metre apart lies slack on the
## floor; pulled taut it leaves the floor and goes straight. Those are two
## different pictures and the pair can read the difference across the room,
## which makes the chain's own state legible without anyone watching a line's
## width change.
##
## The sag is modelled in two parts, because in this shallow view only one of
## them is actually visible.
##
## **Height.** The chain is tied on at shoulder height and its middle falls
## toward the floor as the slack grows. In RooftopSpace that is worth about ten
## pixels of screen movement, which is far too little to read on its own — but
## it is what drives the shadow, and a chain whose shadow slides in to meet it
## in the middle is a chain the eye understands is lying down.
##
## **Bow.** The length a slack rope cannot spend going down, it spends lying
## across the floor. That is the part with real curvature on screen, and it
## bows toward the viewer because that is the direction gravity points once the
## rope has landed.
##
## What matters for play is that both parts are computed on the ground plane
## first. `ground_points` is the actual path the chain occupies on the floor, so
## a sweep along the drawn chain and a sweep along the damaged chain can be the
## same sweep — see the note in the prototype about the hit geometry the run
## still uses.

## The depth the leash is drawn at, and a rule rather than a tuning value: the
## chain is always behind both cats, at every tension, from every camera angle.
##
## It has to be a rule because the alternative cannot be made to work. The rope
## spans the pair, so no single row on the roof is honestly "where the chain
## is" — sorted by its own middle it passes in front of whichever cat is
## further back, and sorted by either end it passes in front of the other. And
## a rope drawn over a cat does not read as a rope in front of a cat; it reads
## as the cat having been cut in half, because the two are the same colour and
## the rope is the thing the eye tracks. Behind is the only order that is right
## from both sides, so it is fixed here rather than left to the sort.
##
## The actors it sits behind share the stage's own depth; one step under that is
## still above the floor, the shadows and the architecture.
const BEHIND_ACTORS := -1
## How far behind the rear cat's row the rope anchors itself. Small, because the
## anchor is only the frame the rope is drawn in — BEHIND_ACTORS is what decides
## the order — but it keeps the two consistent if the layer is ever flattened.
const BEHIND_BIAS := 1.0
const SEGMENTS := 26
## How far a fully slack chain bows toward the viewer, in floor units. Tuned
## against the shortest leash in the roster: at 275px of chain the belly has to
## be obvious without the rope appearing to reach past either cat.
const BOW_MAX := 52.0
## Where the chain sits when there is no slack left at all: shoulder height,
## dead straight, off the floor.
const TAUT_HEIGHT := RooftopSpace.CHAIN_ANCHOR
## And where its middle ends up when the pair is standing on top of each other.
## Not zero — a rope resting on a roof still has a thickness.
const SLACK_HEIGHT := 2.0

var head_a := Vector2.ZERO
var head_b := Vector2.ZERO
var tint := Color("43d9ff")
var max_length := 360.0
var overloaded := false
var warded := false
var _slack := 0.0


func _ready() -> void:
	z_index = BEHIND_ACTORS


## `a` and `b` are the cats' points on the floor, in world coordinates. The node
## anchors itself on the floor just behind whichever cat is further back —
## everything it draws is measured off that anchor, so the anchor's own position
## never moves the rope, only the row the sorted layer files it under.
##
## Behind the rear cat rather than at the pair's middle, and on the floor rather
## than through the projection, because those are the two things that make the
## row comparable with the cats it has to stay behind: an actor is sorted by the
## ground point it stands on, so a rope sorted by a projected midpoint was being
## measured in the wrong units against a row between the two cats rather than
## behind them both.
func set_state(a: Vector2, b: Vector2, color: Color, leash: float,
		is_overloaded := false, is_warded := false) -> void:
	head_a = a
	head_b = b
	position = Vector2((a.x + b.x) * 0.5, minf(a.y, b.y) - BEHIND_BIAS)
	tint = color
	max_length = maxf(1.0, leash)
	overloaded = is_overloaded
	warded = is_warded
	# Slack is eased rather than taken raw so the belly lifts steadily as the
	# pair separates instead of snapping straight over the last few pixels.
	var ratio := clampf(a.distance_to(b) / max_length, 0.0, 1.0)
	_slack = ease(clampf(1.0 - ratio, 0.0, 1.0), 0.62)
	queue_redraw()


## How high off the floor the chain is at `ratio` along its span.
func height_at(ratio: float) -> float:
	var belly := 4.0 * ratio * (1.0 - ratio)
	return lerpf(TAUT_HEIGHT, lerpf(TAUT_HEIGHT, SLACK_HEIGHT, _slack), belly)


## The path the chain takes across the floor — what it would damage along, and
## what its shadow is drawn from. Straight when taut, bowed toward the viewer
## when slack.
func ground_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var bow := BOW_MAX * _slack
	for step in SEGMENTS + 1:
		var ratio := float(step) / float(SEGMENTS)
		var belly := 4.0 * ratio * (1.0 - ratio)
		points.append(head_a.lerp(head_b, ratio) + Vector2(0.0, bow * belly))
	return points


## The same path seen at the height the chain actually hangs at, projected: the
## drawn rope, in world coordinates. A hung chain is a curve in the air over a
## curve on the floor, so both have to go through the view one point at a time —
## a rope projected from its two ends alone would cut straight across its own
## belly.
func drawn_points() -> PackedVector2Array:
	var ground := ground_points()
	var points := PackedVector2Array()
	for step in ground.size():
		var ratio := float(step) / float(SEGMENTS)
		points.append(RooftopSpace.raised(ground[step], height_at(ratio)))
	return points


## The rope in this node's own frame, which is what actually gets drawn and what
## the running light is handed.
func local_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in drawn_points():
		points.append(point - position)
	return points


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:chain_arc", probe_started)


func _probed_draw() -> void:
	if head_a.distance_squared_to(head_b) <= 1.0:
		return
	var ground := ground_points()
	var drawn := local_points()
	_draw_shadow(ground)
	_draw_links(drawn)


## A faint shadow directly under the rope. Without it a chain drawn ten pixels
## above the floor is simply a chain drawn ten pixels further up — the shadow is
## the only thing that says the gap is height and not position.
func _draw_shadow(ground: PackedVector2Array) -> void:
	if not Moonlight.enabled:
		return
	var shadow := PackedVector2Array()
	for step in ground.size():
		var ratio := float(step) / float(SEGMENTS)
		# The shadow is a mark on the floor, so it is projected as floor rather
		# than lifted like the rope that casts it.
		var at := ground[step] + Moonlight.SHADOW_DIRECTION * height_at(ratio) * RooftopSpace.SHADOW_PER_HEIGHT
		shadow.append(RooftopSpace.project(at) - position)
	draw_polyline(shadow, Color(Moonlight.SHADOW_INK, 0.22), 6.0, true)


## Interlocking links, measured out along the rope's length so they follow the
## sag. Every other link is seen face-on — an oval ring with a hole through it —
## and the ones between are turned ninety degrees and seen edge-on as a short
## bar threaded through both neighbours, which is what makes it read as a chain
## rather than as a dotted line.
##
## Each link is inked the way everything else on the roof is: a dark outline,
## a metal body, and a thin highlight on its upper edge. The metal is tinted
## toward the tension colour rather than replaced by it, so the chain still
## says calm / straining / at the limit, and none of it is additive.
const LINK_PITCH := 12.5
const LINK_HALF_LENGTH := 8.0
const LINK_HALF_WIDTH := 5.0
const LINK_WIRE := 2.6
const STEEL := Color("aebccb")
const LINK_INK := Color("09121c")


func _draw_links(drawn: PackedVector2Array) -> void:
	var lengths := PackedFloat32Array([0.0])
	for index in range(1, drawn.size()):
		lengths.append(lengths[index - 1] + drawn[index].distance_to(drawn[index - 1]))
	var total := lengths[lengths.size() - 1]
	if total <= LINK_PITCH:
		return
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.016) * 0.12 if warded else 1.0
	var size_scale := (1.18 * pulse) if warded else (0.82 if overloaded else 1.0)
	var metal := STEEL.lerp(tint, 0.55 if warded else 0.42)
	if overloaded:
		metal = Color("4a3038")
	var shade := metal.darkened(0.38)
	var shine := metal.lightened(0.55)
	var count := int(total / LINK_PITCH)
	# Centred on the span, so both ends lose the same fraction of a link.
	var start := (total - float(count - 1) * LINK_PITCH) * 0.5
	var edge_on: Array[Transform2D] = []
	var face_on: Array[Transform2D] = []
	var cursor := 0
	for link in count:
		var distance := start + float(link) * LINK_PITCH
		while cursor < lengths.size() - 2 and lengths[cursor + 1] < distance:
			cursor += 1
		var span := maxf(0.001, lengths[cursor + 1] - lengths[cursor])
		var at := drawn[cursor].lerp(drawn[cursor + 1], (distance - lengths[cursor]) / span)
		var along := (drawn[cursor + 1] - drawn[cursor]).normalized()
		var frame := Transform2D(along * size_scale, along.orthogonal() * size_scale, at)
		(face_on if link % 2 == 0 else edge_on).append(frame)
	# Rings first, then the bars over them: each bar ends inside the hole of the
	# ring on either side, so it reads as threaded through both.
	#
	# Eight commands for the whole chain, one per layer per kind of link. Each
	# link used to stroke its own four layers, so a taut chain of thirty links
	# was a hundred and twenty antialiased strokes and over a hundred draw calls
	# every tick (tests/perf_bench_capture.gd). The widths are the same for every
	# link — the size scale is the chain's, not the link's — so a layer can be
	# one multiline, and neighbouring rings never overlap, so painting all the
	# inks before all the shades looks exactly like painting link by link.
	var s := size_scale
	var face := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	for frame in face_on:
		_face_link_segments(frame, face)
	_stroke(face, [LINK_INK, shade, metal, Color(shine, 0.7)],
		[(LINK_WIRE + 2.4) * s, LINK_WIRE * s, LINK_WIRE * 0.62 * s, 0.9 * s])
	var edge := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	for frame in edge_on:
		_edge_link_segments(frame, edge)
	_stroke(edge, [LINK_INK, shade, metal, Color(shine, 0.65)],
		[(LINK_WIRE + 3.4) * s, (LINK_WIRE + 1.0) * s, LINK_WIRE * 0.55 * s, 0.8 * s])


func _stroke(layers: Array, colours: Array, widths: Array) -> void:
	for index in layers.size():
		var segments: PackedVector2Array = layers[index]
		if not segments.is_empty():
			draw_multiline(segments, colours[index], widths[index], true)


## A ring seen from above: an outlined oval with the floor showing through it.
## One face-on ring's four layers, appended as segments to `layers` (ink, shade,
## metal, shine) for _stroke.
func _face_link_segments(frame: Transform2D, layers: Array) -> void:
	var ring := PackedVector2Array()
	for step in 17:
		var angle := TAU * float(step) / 16.0
		ring.append(frame * Vector2(cos(angle) * LINK_HALF_LENGTH, sin(angle) * LINK_HALF_WIDTH))
	# The half of the ring facing up the screen catches the moonlight. The first
	# half of the loop runs along the frame's +y side.
	var top := ring.slice(0, 9) if frame.y.y < 0.0 else ring.slice(8, 17)
	_path(layers[0], ring)
	_path(layers[1], ring)
	_path(layers[2], top)
	_path(layers[3], top.slice(2, 7))


## An open path as consecutive segments.
static func _path(out: PackedVector2Array, path: PackedVector2Array) -> void:
	for index in range(1, path.size()):
		out.append(path[index - 1])
		out.append(path[index])


## A ring turned side-on: a short rounded bar along the rope.
func _edge_link_segments(frame: Transform2D, layers: Array) -> void:
	var scale_factor := frame.x.length()
	var from := frame * Vector2(-LINK_HALF_LENGTH, 0.0)
	var to := frame * Vector2(LINK_HALF_LENGTH, 0.0)
	var lift := frame.y.normalized() * (0.8 * scale_factor)
	if lift.y > 0.0:
		lift = -lift
	layers[0].append_array(PackedVector2Array([from, to]))
	layers[1].append_array(PackedVector2Array([from, to]))
	layers[2].append_array(PackedVector2Array([from + lift, to + lift]))
	layers[3].append_array(PackedVector2Array([from * 0.8 + to * 0.2 + lift * 1.6, from * 0.2 + to * 0.8 + lift * 1.6]))
