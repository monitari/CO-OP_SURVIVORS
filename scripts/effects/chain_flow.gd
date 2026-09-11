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
	var span := head_b - head_a
	var length := span.length()
	if length <= 1.0:
		return
	var along := span / length
	var normal := along.orthogonal()
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

	_draw_streams(span, normal, drive, shiver)
	if stage >= 3 and not overloaded:
		_draw_anchor_sparks()
	if surge_age < SURGE_LIFE:
		_draw_surge(span, along, length)


## Two counter-running streams of light. The reverse one only exists once the
## pair is actually pulling, so "light going both ways" is itself the signal
## that the chain has started to load.
func _draw_streams(span: Vector2, normal: Vector2, drive: float, shiver: float) -> void:
	var core := tint.lightened(0.45)
	var directions := [1.0] if stage < 1 and not warded else [1.0, -1.0]
	var count := 2 + stage * 2
	for direction: float in directions:
		for index in count:
			var ratio := fposmod(phase * direction + float(index) / float(count), 1.0)
			var wave := sin(ratio * TAU * 2.0 + phase * 6.0) * 3.0
			var vibration := sin(phase * 44.0 + float(index)) * shiver
			var at := head_a + span * ratio + normal * (wave + vibration)
			# Beads fade in and out of the anchors instead of popping at the
			# cats' feet, which is what made an earlier version look like a
			# string of lights switching on.
			var taper := sin(ratio * PI)
			draw_circle(at, 5.5 + drive * 5.0, Moonlight.glow(tint, 0.08 * drive * taper))
			draw_circle(at, 2.0 + drive * 1.5, Moonlight.glow(core, 0.30 * drive * taper))


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
func _draw_surge(span: Vector2, along: Vector2, length: float) -> void:
	var progress := surge_age / SURGE_LIFE
	if progress < SURGE_GATHER:
		var gather := ease(progress / SURGE_GATHER, 0.6)
		for end_index in 2:
			var from := head_a if end_index == 0 else head_b
			var to := head_b if end_index == 0 else head_a
			var at := from.lerp(to, gather * 0.5)
			draw_circle(at, 9.0 + gather * 8.0, Moonlight.glow(Color.WHITE, 0.40 * (0.35 + gather * 0.65)))
			draw_circle(at, 20.0 + gather * 16.0, Moonlight.glow(tint, 0.12 * gather))
		return
	var spread := (progress - SURGE_GATHER) / (1.0 - SURGE_GATHER)
	var fade := 1.0 - spread
	var mid := head_a + span * 0.5
	var half := along * length * 0.5 * ease(spread, 0.4)
	draw_line(mid - half, mid + half, Moonlight.glow(tint.lightened(0.4), 0.36 * fade), 6.0 + spread * 11.0, true)
	draw_circle(mid, 14.0 + spread * 42.0, Moonlight.glow(tint, 0.15 * fade))
