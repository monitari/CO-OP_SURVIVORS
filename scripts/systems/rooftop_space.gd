class_name RooftopSpace
extends RefCounted
## Where "up" is, on a rooftop that is still played in two dimensions.
##
## Nothing here changes how the game is played. Every actor still lives at a
## point on the ground plane, every hit is still resolved there, and the only
## coordinate any system reads is still the one it always read. What this file
## adds is a single agreed answer to "this thing is forty units tall — what does
## that look like from here", so that a planter, a cat, a vent and the chain all
## lean on one oblique view instead of each inventing its own fake height.
##
## The view is deliberately shallow, and that is the whole design. A steeper
## tilt reads as more three-dimensional and costs the thing this game cannot
## afford to lose: the pair has to be able to see where its own feet are and
## where the chain between them actually lies. So height only ever moves a
## drawing *up the screen*. It never moves the point that drawing is anchored
## to, and it never moves a hit box.
##
## Two conventions come with it, and everything that draws in this space obeys
## both.
##
## **A thing's origin is where it meets the floor.** For a prop that is the
## middle of the near edge of its footprint; for a cat it is the point under its
## feet. That is what makes the contact shadow land in the right place, and it
## is also the number that decides front from back — see `in_front_of`.
##
## **Only two faces are ever visible: the top and the front.** Height in this
## projection is a pure vertical offset, so a side wall has no width on screen
## and drawing one would be inventing an angle the camera does not have. A box
## is its footprint lifted, plus the band between the lifted footprint and the
## floor. Nothing else.

## How much of one unit of height becomes screen pixels of lift. This is the
## camera angle, expressed as the only number that matters: at 0.0 the roof is
## a flat plan view, at 1.0 it is a side-on platformer. 0.66 is the shallow
## look-down the pair can still read their own position out of.
const TILT := 0.66
## How far a solid throws its shadow across the roof per unit of height. Shorter
## than the lift on purpose — the moon sits high as well as off to the side, and
## a shadow as long as the prop is tall reads as late-afternoon sun.
const SHADOW_PER_HEIGHT := 0.42
## Above this height a prop is bulky enough to swallow a cat whole, which is
## what turns on the see-through silhouette rather than simply hiding the cat.
const BULKY_HEIGHT := 34.0
## Standing height of a survivor's body: how far its drawing floats above the
## point it stands on.
##
## Standing height of a survivor's body: how far its drawing floats above the
## point it stands on. Deliberately small — a cat is small, and a body lifted
## far enough to clear its own shadow entirely stops reading as standing and
## starts reading as hovering.
const CAT_STAND := 14.0
## Where the chain is tied on. A little above the body's own lift, so the rope
## leaves at the cat's shoulder rather than out of the floor at its feet.
const CHAIN_ANCHOR := 20.0
## How high off the roof each weapon works, and this is a design statement
## rather than a lookup table.
##
## A roster of eight weapons that all occupy the same slab of air is a roster
## where every weapon feels the same to stand next to. Splitting it in two gives
## each half a different relationship with the floor and with the furniture on
## it: milk, frost and mines *are* the ground for as long as they last, so they
## are read by where the pair chose to stand; stars, lightning, the boomerang
## and the flame nova pass over that ground, throw a shadow across it, and
## flash it where they land.
##
## The scythe sits deliberately between them — swung at knee height, low enough
## to belong to the floor and high enough to clear what is lying on it.
const WEAPON_HEIGHT := {
	"milk": 0.0,
	"frost": 0.0,
	"mine": 0.0,
	"scythe": 11.0,
	"flame": 20.0,
	"boomerang": 22.0,
	"homing": 26.0,
	"lightning": 30.0,
}


## The flying height of a weapon, or the floor for anything not listed — a new
## weapon is on the ground until someone decides otherwise, which is the safe
## default because a ground weapon is drawn exactly where it hits.
static func weapon_height(weapon_id: String) -> float:
	return float(WEAPON_HEIGHT.get(weapon_id, 0.0))


## How far below a round actor's centre its contact ellipse is drawn, as a share
## of its radius.
##
## This is the one honest cheat in the file, and it is worth stating plainly. A
## survivor is a ball, and the shadow of a ball resting on a floor is genuinely
## underneath the ball — from this camera angle almost all of it is behind the
## body and none of it can be seen. That is physically right and useless: the
## contact shadow exists to be read. So it is pushed down to where the eye
## already thinks the floor under the cat is, the bottom of the body, while the
## point that actually decides collisions, sorting and chain anchoring stays at
## the centre where every other system has always expected it.
const CONTACT_DROP := 0.62

## The whole projection on one dial, so the same scene can be looked at with the
## height and without it. At 0 every lift collapses and the roof is the flat
## plan view the run draws today — the furniture stays exactly where it is and
## keeps its shadow, it simply stops standing up. That is the comparison the
## tilt has to win to be worth having, and it is not a comparison anyone can
## make from memory of an earlier build.
##
## An instrument rather than a setting: nothing saves it and nothing in the run
## reads it.
static var depth_scale := 1.0


## The camera angle as it currently stands, with the comparison dial applied.
## Anything measuring how tall a drawing ended up asks for this rather than
## reading TILT, so that turning the height off turns it off everywhere — a
## collapsed roof whose props still reserve their old screen space would hide
## cats behind furniture that is no longer there.
static func tilt() -> float:
	return TILT * depth_scale


## The screen offset for something this far off the roof.
static func lift(height: float) -> Vector2:
	return Vector2(0.0, -height * tilt())


## A ground point seen at a height. The pair of these is the entire projection.
static func raised(at: Vector2, height: float) -> Vector2:
	return at + lift(height)


## Front-to-back order. `base` belongs to the thing being drawn and `other` to
## whatever might be behind it; both are the ground-contact Y described above.
## A prop is in front of an actor when its footprint reaches further down the
## screen — that is the whole of the depth rule, and deliberately the whole of
## it, because anything cleverer stops agreeing with what the shadows say.
static func in_front_of(base: float, other: float) -> bool:
	return base > other


## The top of a solid: the face turned into the moon, so it carries the colour
## the surface was actually painted in.
static func top_face(color: Color) -> Color:
	return Moonlight.ground(color, 0.42)


## The face turned toward the viewer, which on this roof is the face turned away
## from a moon sitting off the upper left. It is the darker of the two by a wide
## margin — the contrast between the two faces is what says "thickness", and a
## front face only slightly darker than its top reads as a printed decal.
static func front_face(color: Color) -> Color:
	return Moonlight.ground(color).darkened(0.34)


## The seam where the top meets the front. Drawn as its own line rather than
## left to the two fills, because a hard lip is what stops a lifted box from
## dissolving once the roof behind it lands on a similar value.
static func lip(color: Color) -> Color:
	if not Moonlight.enabled:
		return color.lightened(0.2)
	return Moonlight.rim(color, 0.5)


## The shadow of a solid standing on the roof.
##
## `footprint` is the outline the thing occupies on the floor, in the canvas's
## own coordinates. It is offset along the light by the thing's height and laid
## down in two passes so its edge fades rather than ending in a rim — a hard
## shadow reads as a second, darker object lying on the floor.
static func cast_shadow(canvas: CanvasItem, footprint: PackedVector2Array, height: float, strength := 1.0) -> void:
	if not Moonlight.enabled or footprint.size() < 3:
		return
	var drop := Moonlight.SHADOW_DIRECTION * height * SHADOW_PER_HEIGHT
	var centre := Vector2.ZERO
	for point in footprint:
		centre += point
	centre /= float(footprint.size())
	for pass_index in 2:
		# The wide pass is the penumbra and the tight one the core. Scaling
		# about the footprint's own centre keeps both passes registered to the
		# shape instead of sliding it sideways.
		var spread := 1.12 if pass_index == 0 else 0.88
		var smeared := PackedVector2Array()
		for point in footprint:
			smeared.append(centre + (point - centre) * spread + drop)
		canvas.draw_colored_polygon(smeared, Color(Moonlight.SHADOW_INK, (0.11 if pass_index == 0 else 0.15) * strength))


## The contact shadow under something round — a cat, a ball, a pot.
##
## `stretch` is what a dash spends: the shadow lengthens along the direction of
## travel while the body leans into it, so the burst reads as a body throwing
## itself forward rather than as a sprite sliding. At rest it is 0, and this is
## then exactly the flattened ellipse Moonlight already puts under every actor.
static func footing(canvas: CanvasItem, at: Vector2, radius: float, height := 0.0,
		strength := 1.0, stretch := 0.0, along := Vector2.RIGHT) -> void:
	if not Moonlight.enabled or radius <= 0.0:
		return
	var drop := Moonlight.SHADOW_DIRECTION * height * SHADOW_PER_HEIGHT
	var spin := along.angle() if stretch > 0.001 else 0.0
	var centre := at + Vector2(0.0, radius * CONTACT_DROP) 		+ Moonlight.SHADOW_DIRECTION * radius * Moonlight.SHADOW_REACH + drop
	# A body up in the air throws a shadow that is both wider and weaker; a body
	# on the floor throws a tight dark one. That difference is most of what lets
	# a hop read as leaving the ground at all.
	var spread := 1.0 + height * 0.008
	var fade := strength / (1.0 + height * 0.008)
	canvas.draw_set_transform(centre, spin, Vector2(spread * (1.0 + stretch), Moonlight.SHADOW_SQUASH * spread))
	# Darker than the shadows the flat roof used, and the reason is the roof
	# itself: graded for a night, the paving already sits near the shadow ink,
	# so the tenth of an alpha that reads on a pale floor reads as nothing here.
	# This shadow is not atmosphere — with the body lifted off its own feet, it
	# is the only thing on screen saying where the cat is standing, so it is
	# drawn at the strength that job needs.
	canvas.draw_circle(Vector2.ZERO, radius * 1.2, Color(Moonlight.SHADOW_INK, 0.20 * fade))
	canvas.draw_circle(Vector2.ZERO, radius * 0.86, Color(Moonlight.SHADOW_INK, 0.28 * fade))
	canvas.draw_circle(Vector2.ZERO, radius * 0.5, Color(Moonlight.SHADOW_INK, 0.3 * fade))
	canvas.draw_set_transform(Vector2.ZERO)


## A box standing on the roof, drawn from its floor footprint upward.
##
## `origin` is the middle of the footprint's near edge — the convention every
## prop in this space uses — so a caller never has to work out where the bottom
## of the drawing ended up.
static func draw_box(canvas: CanvasItem, origin: Vector2, width: float, depth: float,
		height: float, color: Color, lit_top := true) -> void:
	var half := width * 0.5
	var rise := lift(height)
	var top_near_left := origin + Vector2(-half, 0.0) + rise
	var top_near_right := origin + Vector2(half, 0.0) + rise
	# The front band: the gap between where the box meets the floor and where
	# its lid now sits. This is the thickness, and it is the only part of the
	# drawing that was not there when the roof was flat.
	canvas.draw_colored_polygon(PackedVector2Array([
		origin + Vector2(-half, 0.0), origin + Vector2(half, 0.0), top_near_right, top_near_left,
	]), front_face(color))
	canvas.draw_rect(Rect2(top_near_left - Vector2(0.0, depth), Vector2(width, depth)),
		top_face(color) if lit_top else front_face(color).lightened(0.06))
	if Moonlight.enabled:
		canvas.draw_line(top_near_left, top_near_right, lip(color), 1.8)
		# The left wall is the one turned into the moon, so its vertical seam is
		# the second place on a box the light actually reaches.
		canvas.draw_line(origin + Vector2(-half, 0.0), top_near_left, lip(color).darkened(0.25), 1.4)


## The floor outline of a box placed by `draw_box`, for the shadow pass.
static func box_footprint(origin: Vector2, width: float, depth: float) -> PackedVector2Array:
	var half := width * 0.5
	return PackedVector2Array([
		origin + Vector2(-half, -depth), origin + Vector2(half, -depth),
		origin + Vector2(half, 0.0), origin + Vector2(-half, 0.0),
	])
