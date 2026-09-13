class_name ChainFlow
extends Node2D
## The light running along the leash between the two cats.
##
## The chain is the one thing in this game nobody else has, so it should be the
## one thing you remember seeing. It was a coloured line that got wider and a
## soft line behind it that got more opaque — which says "something is wrong"
## only if you already knew to watch the line's width.
##
## What it says instead now is carried by *where the light is going and how
## fast*, because that is readable out of the corner of an eye while you are
## dodging. Calm: one slow drift, barely there. Overcharged: light running both
## ways between the pair, quickening. At the limit: the stream shivers taut and
## the two anchor points throw sparks. A resonance: light gathers from both
## cats into the middle and then floods outward along the whole span.
##
## It is deliberately a separate node from the chain itself. The chain body
## stays normally blended so it keeps a readable dark edge against a bright
## floor; only this layer adds light. See Moonlight and GlowLayer for why that
## split matters once several effects overlap.

## Cycles per second at each tension stage, and how much light each spends.
## The gap between stage 0 and stage 1 is deliberately large: the moment the
## pair starts pulling apart should be the moment something changes, not a
## ramp you have to have been watching to notice.
const FLOW_SPEED: Array[float] = [0.16, 0.46, 0.78, 1.18]
const DRIVE: Array[float] = [0.30, 0.68, 1.05, 1.55]
const STREAM_OFFSETS := [
	[0.08, 0.61],
	[0.05, 0.34, 0.79],
	[0.03, 0.23, 0.58, 0.87],
	[0.04, 0.19, 0.53, 0.81],
]
const SURGE_LIFE := 0.72
## Of that, the share spent gathering before the span floods.
const SURGE_GATHER := 0.45

var head_a := Vector2.ZERO
var head_b := Vector2.ZERO
var tint := Color("43d9ff")
var stage := 0
var warded := false
var overloaded := false
var phase := 0.0
var surge_age := SURGE_LIFE
## The path the light runs along, when the chain is not a straight segment.
## Empty in the run, where the chain is a Line2D between two points and this
## layer has nothing to follow but that line. A caller that hangs the chain —
## see ChainArc — hands over the sampled rope instead, and the beads then ride
## the sag rather than cutting the corner across it, which is the difference
## between light travelling *through* a rope and light drawn near one.
var curve := PackedVector2Array()


func _ready() -> void:
	material = Moonlight.additive()
	# Above the chain body and its halo, below the survivors.
	z_index = 0


## Called from the chain update each frame. `stage` is the tension band main.gd
## has already computed for the chain's colour, so the light and the colour can
## never disagree about what state the pair is in.
func set_state(a: Vector2, b: Vector2, color: Color, tension_stage: int, is_warded: bool, is_overloaded: bool) -> void:
	head_a = a
	head_b = b
	tint = color
	stage = clampi(tension_stage, 0, FLOW_SPEED.size() - 1)
	warded = is_warded
	overloaded = is_overloaded


## A resonance has fired. Light gathers out of both cats and floods the span.
func surge() -> void:
	surge_age = 0.0


## Where the chain is, a given fraction of the way along it. Falls back to the
## straight span whenever no curve has been handed over, so the run's chain is
## sampled exactly as it was before this existed.
func point_at(ratio: float) -> Vector2:
	if curve.size() < 2:
		return head_a.lerp(head_b, ratio)
	var step := clampf(ratio, 0.0, 1.0) * float(curve.size() - 1)
	var index := clampi(int(step), 0, curve.size() - 2)
	return curve[index].lerp(curve[index + 1], step - float(index))


## Which way the chain is running at that point, so a bead's trail and its
## sideways wave stay square to the rope through a bend.
func heading_at(ratio: float) -> Vector2:
	if curve.size() < 2:
		return (head_b - head_a).normalized()
	var ahead := point_at(minf(1.0, ratio + 0.04))
	var behind := point_at(maxf(0.0, ratio - 0.04))
	var run := ahead - behind
	return run.normalized() if run.length_squared() > 0.0001 else (head_b - head_a).normalized()


func _process(delta: float) -> void:
	# Nothing to advance before a run has placed the pair, and the node lives
	# for the whole session — the title screen should not be queueing a redraw
	# a frame for a chain that has no length yet.
	if not visible or head_a.distance_squared_to(head_b) <= 1.0:
		return
	phase += delta * (0.9 if warded else FLOW_SPEED[stage])
	if surge_age < SURGE_LIFE:
		surge_age += delta
	queue_redraw()


func _draw() -> void:
	if head_a.distance_squared_to(head_b) <= 1.0:
		return
	var drive := DRIVE[stage]
	if overloaded:
		# A blown chain is dark. The light coming back is how the pair knows
		# they have it again, so there has to be almost nothing here first.
		drive *= 0.22
	elif warded:
		drive = 1.3
	# Slack below the warning band, taut above it: past stage 2 the stream stops
	# waving and starts vibrating, at a frequency nothing else on screen uses.
	var shiver := 0.0 if stage < 2 else float(stage - 1) * 1.7

	_draw_streams(drive, shiver)
	if stage >= 3 and not overloaded:
		_draw_anchor_sparks()
	if surge_age < SURGE_LIFE:
		_draw_surge()


## Two counter-running streams of light. The reverse one only exists once the
## pair is actually pulling, so "light going both ways" is itself the signal
## that the chain has started to load.
func _draw_streams(drive: float, shiver: float) -> void:
	var core := tint.lightened(0.45)
	var directions := [1.0] if stage < 1 and not warded else [1.0, -1.0]
	var offsets: Array = STREAM_OFFSETS[stage]
	for direction: float in directions:
		for index in offsets.size():
			# Uneven packets read as charge travelling through a tether. Evenly
			# spaced circles read as bulbs mounted on one.
			var offset := float(offsets[index])
			var ratio := fposmod(phase * direction + offset + (0.11 if direction < 0.0 else 0.0), 1.0)
			var wave := sin(ratio * TAU * 2.0 + phase * 6.0) * 3.0
			var vibration := sin(phase * 44.0 + float(index)) * shiver
			var run := heading_at(ratio)
			var at := point_at(ratio) + run.orthogonal() * (wave + vibration)
			# Beads fade in and out of the anchors instead of popping at the
			# cats' feet, which is what made an earlier version look like a
			# string of lights switching on.
			var taper := sin(ratio * PI)
			var pulse := 0.82 + 0.18 * sin(phase * 13.0 + float(index) * 2.3)
			var trail := run * direction * (7.0 + drive * 8.0)
			draw_line(at - trail, at, Moonlight.glow(tint, 0.075 * drive * taper), 5.0 + drive * 3.0, true)
			draw_circle(at, (4.5 + drive * 4.0) * pulse, Moonlight.glow(tint, 0.08 * drive * taper))
			draw_circle(at, (1.8 + drive * 1.25) * pulse, Moonlight.glow(core, 0.28 * drive * taper))


## At the limit the connection points are where the strain is, so that is where
## it shows.
func _draw_anchor_sparks() -> void:
	for end_index in 2:
		var anchor := head_a if end_index == 0 else head_b
		for spark in 3:
			var angle := phase * 11.0 + float(spark) * TAU / 3.0 + float(end_index) * 1.7
			var reach := 7.0 + sin(phase * 34.0 + float(spark)) * 5.0
			draw_line(anchor, anchor + Vector2.from_angle(angle) * reach,
				Moonlight.glow(Color.WHITE, 0.28), 1.6, true)


## Both cats give up their light, it meets in the middle, and the middle throws
## it back down the whole chain. A resonance is the one moment the pair being
## tied together pays off, so it is the one moment the chain is the brightest
## thing on the roof.
func _draw_surge() -> void:
	var progress := surge_age / SURGE_LIFE
	if progress < SURGE_GATHER:
		var gather := ease(progress / SURGE_GATHER, 0.6)
		for end_index in 2:
			var from_ratio := 0.0 if end_index == 0 else 1.0
			var at := point_at(lerpf(from_ratio, 0.5, gather))
			draw_circle(at, 9.0 + gather * 8.0, Moonlight.glow(Color.WHITE, 0.40 * (0.35 + gather * 0.65)))
			draw_circle(at, 20.0 + gather * 16.0, Moonlight.glow(tint, 0.12 * gather))
		return
	var spread := (progress - SURGE_GATHER) / (1.0 - SURGE_GATHER)
	var fade := 1.0 - spread
	var mid := point_at(0.5)
	# The flood is sampled along the chain rather than drawn as one straight
	# segment through it, so on a hung rope the light follows the belly out to
	# both cats instead of cutting the chord.
	var reach := 0.5 * ease(spread, 0.4)
	var flood := PackedVector2Array()
	for step in 13:
		flood.append(point_at(0.5 + (float(step) / 6.0 - 1.0) * reach))
	draw_polyline(flood, Moonlight.glow(tint.lightened(0.4), 0.36 * fade), 6.0 + spread * 11.0, true)
	draw_circle(mid, 14.0 + spread * 42.0, Moonlight.glow(tint, 0.15 * fade))
