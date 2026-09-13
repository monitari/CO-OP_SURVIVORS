class_name FlightField
extends Node2D
## What an attack leaves on the floor it is travelling over.
##
## Once weapons have heights, two of them can be drawn in the same place on
## screen and mean completely different things — a puddle lying on the roof and
## a star passing above it are both a bright shape at the same pixel. What tells
## them apart is the floor: the star throws a small shadow that runs along under
## it and flashes the roof where it lands, and the puddle has neither because it
## is already on the ground.
##
## Both of those are per-frame, per-shot marks on a surface that the shots do
## not own, so they are drawn here rather than by each projectile. This is the
## third field node in the game built on the same reasoning as BurstField and
## ParticleField: at a few hundred simultaneous shots a node and a tween each is
## a stall, while one array and one `_draw` is not.
##
## Two canvases, and the split is the usual one. Shadows are dark and belong to
## the floor's own blending; the landing flash is light being *added* to the
## roof, so it rides on a GlowLayer above. Nothing here affects play.

## How long a landing mark stays on the roof. Short: it is punctuation for a hit
## that has already been resolved, not a field anybody has to read.
const FLASH_LIFE := 0.26
const MAX_FLASHES := 90

## Airborne things whose shadows this draws: {node, height, radius}.
var flyers: Array = []
var flashes: Array = []
var glow: GlowLayer


func _ready() -> void:
	# Under the actors and over the paving. A shot's shadow is on the floor, and
	# a shadow drawn over a cat would read as the shot itself.
	z_index = -3
	glow = GlowLayer.attach(self, _draw_flashes, 1)


## Starts drawing a shadow under `shot` until it stops being visible.
##
## Typed to the projectile rather than to any Node2D on purpose: what this needs
## is the point on the *roof* the thing is flying over, and a projectile is the
## one kind of node that carries that separately from where it is drawn. Working
## it back out of a drawn position stopped being possible the moment the floor
## gained a perspective.
func track(shot: HomingProjectile) -> void:
	if shot == null or shot.flight_height <= 0.0 or not is_instance_valid(shot):
		return
	flyers.append({"shot": shot, "radius": shot.radius})


## A shot landed here. The mark goes on the roof at the floor point, never at
## the point the shot was drawn at — the whole job of this mark is to say which
## piece of floor the hit belongs to.
func flash(at: Vector2, color: Color, radius := 26.0) -> void:
	if flashes.size() >= MAX_FLASHES:
		flashes.pop_front()
	flashes.append({"at": at, "color": color, "radius": radius, "age": 0.0})


func step(delta: float) -> void:
	var living: Array = []
	for flyer in flyers:
		# Deliberately untyped until it has been checked. A shot may be pooled
		# (retired by being hidden) or freed outright, and assigning a freed
		# instance to a typed local is an error rather than a null — so the
		# validity check has to come before the type does.
		var node = flyer["shot"]
		if is_instance_valid(node) and (node as Node2D).visible:
			living.append(flyer)
	flyers = living
	var burning: Array = []
	for mark in flashes:
		mark["age"] = float(mark["age"]) + delta
		if float(mark["age"]) < FLASH_LIFE:
			burning.append(mark)
	flashes = burning
	queue_redraw()
	if glow != null:
		glow.queue_redraw()


func clear_all() -> void:
	flyers.clear()
	flashes.clear()
	queue_redraw()
	if glow != null:
		glow.queue_redraw()


func _draw() -> void:
	for flyer in flyers:
		var node = flyer["shot"]
		if not is_instance_valid(node):
			continue
		var shot := node as HomingProjectile
		# The shadow is a mark on the floor, so it goes where the floor point
		# projects to and is sized by how far away that is — the same treatment
		# every other footprint on this roof gets.
		var scale := RooftopSpace.view_scale(shot.ground_position.y)
		RooftopSpace.footing(self, RooftopSpace.project(shot.ground_position),
			float(flyer["radius"]) * scale, shot.flight_height * scale, 0.85)


func _draw_flashes(canvas: CanvasItem) -> void:
	for mark in flashes:
		var progress := clampf(float(mark["age"]) / FLASH_LIFE, 0.0, 1.0)
		var fade := 1.0 - progress
		var ground: Vector2 = mark["at"]
		var at := RooftopSpace.project(ground)
		# Flattened along the light the same way every other footprint on this
		# roof is, so a landing reads as light thrown across the floor rather
		# than as a ball of light hanging over it.
		canvas.draw_set_transform(at, 0.0, Vector2(1.0, Moonlight.SHADOW_SQUASH))
		var reach := float(mark["radius"]) * (0.45 + progress * 0.85) * RooftopSpace.view_scale(ground.y)
		canvas.draw_circle(Vector2.ZERO, reach, Moonlight.glow(mark["color"] as Color, 0.22 * fade))
		canvas.draw_circle(Vector2.ZERO, reach * 0.45, Moonlight.glow(Color.WHITE, 0.2 * fade))
		canvas.draw_set_transform(Vector2.ZERO)
