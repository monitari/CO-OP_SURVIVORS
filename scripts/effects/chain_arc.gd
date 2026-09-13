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
var _slack := 0.0


func _ready() -> void:
	# Under the actors: the chain runs between the cats' shoulders, and a rope
	# drawn over the top of a cat reads as being in front of it.
	z_index = -1


## `a` and `b` are the cats' points on the floor, in world coordinates. The node
## moves itself to the projected middle of the rope, because that is the ground
## line the sorted layer has to order it by — everything it draws is then
## measured back off that anchor.
func set_state(a: Vector2, b: Vector2, color: Color, leash: float, is_overloaded := false) -> void:
	head_a = a
	head_b = b
	position = RooftopSpace.project((a + b) * 0.5)
	tint = color
	max_length = maxf(1.0, leash)
	overloaded = is_overloaded
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
	if head_a.distance_squared_to(head_b) <= 1.0:
		return
	var ground := ground_points()
	var drawn := local_points()
	_draw_shadow(ground)
	# Body first as a dark backing, then the coloured rope inside it. The dark
	# edge is what keeps the chain visible over a pale floor and inside a crowd,
	# and it is the reason nothing in this file is additively blended.
	var body := Color("0a1520") if not overloaded else Color("120a10")
	draw_polyline(drawn, Color(body, 0.85), 9.0 if not overloaded else 5.0, true)
	draw_polyline(drawn, Color(tint, 0.95 if not overloaded else 0.4), 5.0 if not overloaded else 2.5, true)
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


## Links, spaced along the rope rather than along the straight span, so they
## crowd where the chain bends. That crowding is the second readout of slack and
## it costs nothing: the points are already in hand.
func _draw_links(drawn: PackedVector2Array) -> void:
	if overloaded:
		return
	for step in range(1, drawn.size() - 1, 2):
		var along := (drawn[step + 1] - drawn[step - 1]).normalized()
		var across := along.orthogonal() * 3.4
		draw_line(drawn[step] - across, drawn[step] + across, Color(tint.lightened(0.35), 0.5), 2.0, true)
