class_name RooftopSpace
extends RefCounted
## Where "up" is, on a rooftop that is still played in two dimensions.
##
## Nothing here changes how the game is played. Every actor still lives at a
## point on a flat ground plane, every hit is still resolved there in ordinary
## world coordinates, and no system that decides anything ever reads this file.
## What it adds is one agreed answer to "where on screen does this piece of
## floor, and this thing standing on it, actually appear".
##
## **The roof is drawn in one-point perspective, so the plate is a trapezoid.**
## The far edge is narrower and sits closer to the middle of the screen; the
## near edge is wider and further down. That is the whole difference from the
## plan view the run draws, and it is what makes a floor read as a surface
## receding away from the viewer rather than as a rectangle seen from overhead.
##
## The projection is a pinhole reduced to its two useful numbers. Both are
## measured from `focus`, the ground point the camera is centred on:
##
##   scale  how much bigger a thing on this row is than one on the focus row.
##          1 / (1 - toward * FORESHORTEN), where `toward` counts world units
##          from the focus row down the screen toward the viewer.
##   row    where that depth lands vertically. A ground point's screen row is
##          its own scale measured down from the horizon, which is the pinhole
##          result and is what draws the tile rows together as they recede.
##
## Both fall out of one number per point, so the whole view is `project` plus
## `view_scale` and nothing else has to know how either of them works.
##
## Three conventions come with it, and everything drawn in this space obeys all
## three.
##
## **A thing's origin is where it meets the floor.** For a prop that is the
## middle of the near edge of its footprint; for a cat it is the point under its
## feet. That is what makes the contact shadow land in the right place, it is
## the point that gets projected, and it is also the number that decides front
## from back — see `in_front_of`.
##
## **Ground geometry is projected; things standing on the ground are not.** A
## floor tile, a gutter, a prop's footprint and the chain's path are all shapes
## lying on the plane, so every corner of them goes through `project` and they
## come out as trapezoids. A cat, an enemy or a flying star is drawn upright at
## its projected floor point and simply scaled — a body sheared along with the
## perspective would read as the cat falling over, not as the cat standing
## further away.
##
## **Only two faces of a solid are ever visible: the top and the front.** The
## camera has no yaw, so a side wall has no width on screen, and drawing one
## would be inventing an angle this view does not have.

## How much of one unit of height becomes screen pixels of lift at the focus
## row. At 0.0 the roof is a flat plan view, at 1.0 it is a side-on platformer.
## 0.66 is the shallow look-down the pair can still read their own position out
## of. Away from the focus it is scaled along with everything else.
const TILT := 0.66
## How fast the world closes toward the vanishing point, per world unit measured
## from the focus row toward the viewer.
##
## This is the strength of the perspective and the one number to turn when the
## trapezoid is too much or too little. At this value a plate reaching six
## hundred units either side of the focus is about a fifth narrower at its far
## edge than at the middle and a quarter wider at its near edge — a taper that
## is unmistakable while still leaving a survivor near enough the same size at
## both ends of the roof to be judged by eye.
const FORESHORTEN := 0.0003
## Screen pixels from the focus row up to the horizon. Larger spreads the far
## field out and flattens the taper; smaller crushes the distance together.
const HORIZON_RISE := 2000.0
## A ground point may not be scaled past these. The far clamp keeps anything at
## or behind the vanishing point off the screen rather than inside out; the near
## one stops a body that walks under the camera from filling it.
const SCALE_MIN := 0.42
const SCALE_MAX := 2.1
## How far a solid throws its shadow across the roof per unit of height. Shorter
## than the lift on purpose — the moon sits high as well as off to the side, and
## a shadow as long as the prop is tall reads as late-afternoon sun.
const SHADOW_PER_HEIGHT := 0.42
## Above this height a prop is bulky enough to swallow a cat whole, which is
## what turns on the see-through silhouette rather than simply hiding the cat.
const BULKY_HEIGHT := 34.0
## Standing height of a survivor's body: how far its drawing floats above the
## point it stands on. Deliberately small — a cat is small, and a body lifted
## far enough to clear its own shadow entirely stops reading as standing and
## starts reading as hovering.
const CAT_STAND := 14.0
## Where the chain is tied on. A little above the body's own lift, so the rope
## leaves at the cat's shoulder rather than out of the floor at its feet.
const CHAIN_ANCHOR := 20.0
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
## How high off the roof each weapon works, and this is a design statement
## rather than a lookup table.
##
## A roster of eight weapons that all occupy the same slab of air is a roster
## where every weapon feels the same to stand next to. Splitting it in two gives
## each half a different relationship with the floor and with the furniture on
## it: milk, frost and mines *are* the ground for as long as they last, so they
## are read by where the pair chose to stand; stars, lightning, the boomerang
## and the flame nova pass over that ground, throw a shadow across it, and flash
## it where they land.
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

## The three ways this roof can be looked at, kept on one switch so that the
## same scene can be compared in all of them rather than remembered between
## builds.
##
##   FLAT         the plan view the run draws today. No lift, no taper. The
##                furniture keeps its place and its shadow and stops standing up.
##   LIFTED       height as a pure vertical offset. The floor is a rectangle.
##   PERSPECTIVE  the floor is a trapezoid and everything on it is placed and
##                sized by how far away it is.
##
## An instrument rather than a setting: nothing saves it, and the run leaves it
## alone, which is why the default is the view the run already has.
enum View { FLAT, LIFTED, PERSPECTIVE }
static var view_mode := View.LIFTED
## The ground point the camera is centred on, and therefore the point the whole
## perspective is measured from: `project(focus) == focus`, always. Whoever owns
## the camera sets this once a frame before anything draws — a projection
## measured from a stale centre slides the floor out from under the actors
## standing on it.
static var focus := Vector2.ZERO

## Counteract the battlefield projection for upright bodies only. Ground
## shadows and attack areas continue to use the original floor projection.
static func upright_basis(item: Node2D, offset := Vector2.ZERO) -> Transform2D:
	var snapshot := view_snapshot(item)
	if not snapshot.valid:
		return Transform2D(0.0, offset)
	return snapshot.basis_at(item.global_position, offset)


## The camera the upright correction is measured against, read once per frame
## per viewport. Looking the viewport, its camera and the camera's screen centre
## up again for every body was a real share of a crowded tick — thousands of
## engine calls a frame to recover the same four numbers.
class ViewSnapshot:
	var valid := false
	var centre := Vector2.ZERO
	var zoom := Vector2.ONE
	var view_size := Vector2(1280, 720)

	func basis_at(ground: Vector2, offset := Vector2.ZERO) -> Transform2D:
		if not valid:
			return Transform2D(0.0, offset)
		var p := (ground - centre) * zoom / view_size
		var k := 1.0 - EndlessRooftopView.PERSPECTIVE * p.y
		var shear := -EndlessRooftopView.PERSPECTIVE * p.x * view_size.x / view_size.y / EndlessRooftopView.TILT
		return Transform2D(Vector2.RIGHT, Vector2(shear, k / EndlessRooftopView.TILT), offset)


static var _snapshot := ViewSnapshot.new()
static var _snapshot_viewport := 0
static var _snapshot_frame := -1


static func view_snapshot(item: Node) -> ViewSnapshot:
	var viewport := item.get_viewport()
	var frame := Engine.get_process_frames() * 8192 + Engine.get_physics_frames()
	if viewport != null and viewport.get_instance_id() == _snapshot_viewport and frame == _snapshot_frame:
		return _snapshot
	_snapshot_frame = frame
	_snapshot_viewport = viewport.get_instance_id() if viewport != null else 0
	_snapshot.valid = false
	if not viewport is SubViewport:
		return _snapshot
	var camera := viewport.get_camera_2d()
	var view := viewport.get_parent()
	if camera == null or not view is EndlessRooftopView:
		return _snapshot
	_snapshot.valid = true
	_snapshot.centre = camera.get_screen_center_position()
	_snapshot.zoom = camera.zoom
	_snapshot.view_size = view.view_size
	return _snapshot


## The flying height of a weapon, or the floor for anything not listed — a new
## weapon is on the ground until someone decides otherwise, which is the safe
## default because a ground weapon is drawn exactly where it hits.
static func weapon_height(weapon_id: String) -> float:
	return float(WEAPON_HEIGHT.get(weapon_id, 0.0))


## The camera angle as it currently stands. Anything measuring how tall a
## drawing ended up asks for this rather than reading TILT, so that flattening
## the view flattens it everywhere — a collapsed roof whose props still reserved
## their old screen space would hide cats behind furniture that is no longer
## standing there.
static func tilt() -> float:
	return 0.0 if view_mode == View.FLAT else TILT


## How much bigger something on this row is than something on the focus row.
## Flat 1.0 in every view but the perspective one, which is what lets every
## caller multiply by it without first asking which view is on.
static func view_scale(ground_y: float) -> float:
	if view_mode != View.PERSPECTIVE:
		return 1.0
	var toward := ground_y - focus.y
	return clampf(1.0 / (1.0 - toward * FORESHORTEN), SCALE_MIN, SCALE_MAX)


## Where a point on the floor appears. The one function that makes the plate a
## trapezoid: a row closes toward the focus column as it recedes, and rides up
## toward the horizon as its scale falls.
static func project(ground: Vector2) -> Vector2:
	if view_mode != View.PERSPECTIVE:
		return ground
	var scale := view_scale(ground.y)
	return Vector2(focus.x + (ground.x - focus.x) * scale, focus.y + HORIZON_RISE * (scale - 1.0))


## The screen offset for something this far off the roof, in the local frame of
## a body that has already been placed and scaled by the view. Callers drawing
## inside a billboard use this; callers placing world geometry want `raised`.
static func lift(height: float) -> Vector2:
	return Vector2(0.0, -height * tilt())


## A point at a height above the floor, projected. This pair of calls is the
## entire view, and nearly everything that draws wants this one rather than
## either half of it on its own.
static func raised(at: Vector2, height: float) -> Vector2:
	return project(at) + lift(height) * view_scale(at.y)


## How much a shape *lying on the floor* is squashed vertically compared with
## how much it is stretched horizontally.
##
## A body standing on the roof is scaled evenly, because it faces the camera. A
## puddle, a scorch mark or a pool of light does not — it lies in the plane, and
## the plane is being looked at edge-on enough that a world circle comes out as
## an ellipse. Anything that is a decal rather than a body multiplies its
## vertical scale by this, which is the same foreshortening the floor tiles get
## for free by having their corners projected one at a time.
static func floor_squash(ground_y: float) -> float:
	if view_mode != View.PERSPECTIVE:
		return 1.0
	return clampf(HORIZON_RISE * FORESHORTEN * view_scale(ground_y), 0.25, 1.0)


## Front-to-back order. `base` belongs to the thing being drawn and `other` to
## whatever might be behind it; both are the ground-contact Y described above.
## A prop is in front of an actor when its footprint reaches further down the
## roof — that is the whole of the depth rule, and deliberately the whole of it.
## Projection preserves the order, so the answer is the same whichever of the
## two spaces it is asked in.
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
## Where footing() puts a shadow's centre. Shared with FlightField's batched
## shadows so the two can never drift apart.
static func footing_centre(at: Vector2, radius: float, height: float) -> Vector2:
	return at + Vector2(0.0, radius * CONTACT_DROP) \
		+ Moonlight.SHADOW_DIRECTION * radius * Moonlight.SHADOW_REACH \
		+ Moonlight.SHADOW_DIRECTION * height * SHADOW_PER_HEIGHT


static func footing(canvas: CanvasItem, at: Vector2, radius: float, height := 0.0,
		strength := 1.0, stretch := 0.0, along := Vector2.RIGHT) -> void:
	if not Moonlight.enabled or radius <= 0.0:
		return
	var spin := along.angle() if stretch > 0.001 else 0.0
	var centre := footing_centre(at, radius, height)
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


## A box standing on the roof, drawn from its floor footprint upward in a body's
## own frame — so this is for props, which are billboards, and not for the
## architecture, whose footprints are large enough to need projecting corner by
## corner.
##
## `origin` is the middle of the footprint's near edge, the convention every
## prop in this space uses, so a caller never has to work out where the bottom
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


## A flat shape lying on the roof, projected corner by corner. Anything whose
## outline is on the ground plane — a plate, a gutter, a parapet's footprint —
## goes through this rather than being billboarded, because its shape is the
## part that carries the perspective.
static func project_all(points: PackedVector2Array) -> PackedVector2Array:
	if view_mode != View.PERSPECTIVE:
		return points
	var out := PackedVector2Array()
	for point in points:
		out.append(project(point))
	return out


## A stretch of floor as a projected quad, from a rectangle given in world
## coordinates. The workhorse for the architecture: a plate, a gutter, a
## parapet's lid and a prop's footprint are all this shape.
static func floor_quad(rect: Rect2) -> PackedVector2Array:
	return project_all(PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	]))
