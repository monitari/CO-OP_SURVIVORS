class_name RooftopProp
extends Node2D
## A thing on the roof that has a top and a front.
##
## The rooftop already had crates, vents and yarn on it, but they were painted
## flat into the floor: a decal the cats walked over rather than an object they
## walked *around*. This is the same furniture given the one property that makes
## a roof read as a place with thickness — a height, and therefore a lid you see
## the top of, a face you see the front of, and a shadow whose length says how
## far off the floor the lid is.
##
## Each prop is its own node so the stage can sort it against the actors by
## ground contact. That is the entire reason this is not one more `_draw` inside
## the floor: front-to-back order is a per-object question and a single canvas
## can only answer it once.
##
## Its origin is the middle of the near edge of its footprint, which is the
## convention in RooftopSpace. Everything below is drawn in local coordinates
## going up and back from there, so `position.y` is both where the prop touches
## the floor and the key it is sorted by.
##
## Nothing here blocks movement. These are scenery in the same sense the painted
## props always were — the breakable supply planter is still a ChaserEnemy, and
## making a cosmetic prop stop a cat would be the one change on this roof that
## could lose a run.

const PALETTE := {
	"planter": Color("6a5442"),
	"vent": Color("52625f"),
	"crate": Color("806044"),
	"duct": Color("475a5c"),
	"pipe": Color("5c6a6b"),
}
## Footprint and height per kind: width across, depth back, rise up.
const SHAPE := {
	"planter": Vector3(78.0, 50.0, 44.0),
	"vent": Vector3(84.0, 56.0, 38.0),
	"crate": Vector3(66.0, 46.0, 32.0),
	"duct": Vector3(150.0, 40.0, 26.0),
	"pipe": Vector3(46.0, 40.0, 104.0),
}

var kind := "planter"
var variant := 0 ## Stable per-prop randomness: leaf angles, plank counts, rust.


func setup(prop_kind: String, at: Vector2, prop_variant := 0) -> void:
	kind = prop_kind if SHAPE.has(prop_kind) else "crate"
	variant = prop_variant
	position = at
	z_index = 0
	queue_redraw()


func height() -> float:
	return (SHAPE[kind] as Vector3).z


func width() -> float:
	return (SHAPE[kind] as Vector3).x


func depth() -> float:
	return (SHAPE[kind] as Vector3).y


## Tall enough that a cat behind it disappears rather than merely being clipped,
## which is the case the see-through silhouette exists for.
func bulky() -> bool:
	return height() >= RooftopSpace.BULKY_HEIGHT


## What this prop covers on screen, in world coordinates: from the lifted lid
## down to the floor. The stage tests actors against this to decide whether
## anyone is actually hidden, so it is the drawn extent and not the footprint.
func screen_rect() -> Rect2:
	var top := position.y - depth() - height() * RooftopSpace.tilt()
	return Rect2(position.x - width() * 0.5, top, width(), position.y - top)


func _draw() -> void:
	var shape := SHAPE[kind] as Vector3
	var color := PALETTE[kind] as Color
	RooftopSpace.cast_shadow(self, RooftopSpace.box_footprint(Vector2.ZERO, shape.x, shape.y), shape.z)
	match kind:
		"planter":
			_draw_planter(shape, color)
		"vent":
			_draw_vent(shape, color)
		"duct":
			_draw_duct(shape, color)
		"pipe":
			_draw_pipe(shape, color)
		_:
			_draw_crate(shape, color)


## A pot with soil and a plant in it. The plant is drawn from the top face
## upward rather than from the origin, because a leaf growing out of the floor
## behind the pot is exactly the mistake the height convention exists to stop.
func _draw_planter(shape: Vector3, color: Color) -> void:
	# The pot tapers: a planter with parallel sides is a crate with a bush on it.
	var half := shape.x * 0.5
	var rise := RooftopSpace.lift(shape.z)
	var foot := half * 0.82
	draw_colored_polygon(PackedVector2Array([
		Vector2(-foot, 0.0), Vector2(foot, 0.0), Vector2(half, 0.0) + rise, Vector2(-half, 0.0) + rise,
	]), RooftopSpace.front_face(color))
	var soil_rect := Rect2(Vector2(-half, -shape.y) + rise, Vector2(shape.x, shape.y))
	draw_rect(soil_rect, RooftopSpace.top_face(color))
	# The rim of the pot, then the soil sunk inside it.
	draw_rect(soil_rect.grow(-6.0), RooftopSpace.top_face(Color("3a2f26")))
	if Moonlight.enabled:
		draw_line(Vector2(-half, 0.0) + rise, Vector2(half, 0.0) + rise, RooftopSpace.lip(color), 2.0)
	var centre := soil_rect.get_center()
	var leaf_tint := Moonlight.ground(Color("44705a"), 0.18)
	for leaf in 7:
		var angle := -PI * 0.5 + (float(leaf) - 3.0) * 0.36 + float(variant) * 0.11
		var reach := 26.0 + float((leaf * 7 + variant) % 5) * 4.0
		var tip := centre + Vector2.from_angle(angle) * Vector2(1.0, 0.72) * reach
		draw_line(centre, tip, leaf_tint, 4.0, true)
		draw_circle(tip, 3.4, leaf_tint.lightened(0.12))
	if Moonlight.enabled:
		# The one place on a planter the moon reaches cleanly: the near-left
		# leaves, which are the ones tilted into it.
		draw_arc(centre, 20.0, PI * 1.05, PI * 1.7, 12, Moonlight.rim(leaf_tint, 0.35), 2.0, true)


func _draw_vent(shape: Vector3, color: Color) -> void:
	RooftopSpace.draw_box(self, Vector2.ZERO, shape.x, shape.y, shape.z, color)
	var rise := RooftopSpace.lift(shape.z)
	var half := shape.x * 0.5
	# Slats belong on the front face, where a real vent puts them, and that is
	# also where they do the most work: horizontal lines across the thickness
	# are what make the eye believe the band is a wall rather than a shadow.
	for slat in 3:
		var y := -shape.z * RooftopSpace.tilt() * (0.28 + float(slat) * 0.24)
		draw_line(Vector2(-half + 7.0, y), Vector2(half - 7.0, y), Moonlight.ground(color).darkened(0.52), 2.4)
	# A fan housing on the lid, seen from almost directly above.
	var lid := rise + Vector2(0.0, -shape.y * 0.5)
	draw_circle(lid, 15.0, RooftopSpace.top_face(Color("3c5355")))
	for blade in 4:
		var angle := float(blade) * PI * 0.5 + float(variant) * 0.3
		draw_line(lid, lid + Vector2.from_angle(angle) * Vector2(13.0, 9.0), RooftopSpace.top_face(color).lightened(0.1), 3.0, true)
	if Moonlight.enabled:
		draw_arc(lid, 15.0, PI * 1.02, PI * 1.72, 12, Moonlight.rim(color, 0.55), 2.0, true)


func _draw_crate(shape: Vector3, color: Color) -> void:
	RooftopSpace.draw_box(self, Vector2.ZERO, shape.x, shape.y, shape.z, color)
	var half := shape.x * 0.5
	var band := -shape.z * RooftopSpace.tilt()
	draw_line(Vector2(-half + 5.0, band * 0.5), Vector2(half - 5.0, band * 0.5), Moonlight.ground(color).darkened(0.5), 2.0)
	var lid := RooftopSpace.lift(shape.z) + Vector2(0.0, -shape.y * 0.5)
	for plank in 2:
		var offset := (float(plank) - 0.5) * shape.y * 0.42
		draw_line(lid + Vector2(-half + 6.0, offset), lid + Vector2(half - 6.0, offset),
			RooftopSpace.top_face(color).darkened(0.22), 1.6)


## A low run of ducting. Wide and flat: it never hides a cat, it only proves the
## floor has a surface things can sit on.
func _draw_duct(shape: Vector3, color: Color) -> void:
	RooftopSpace.draw_box(self, Vector2.ZERO, shape.x, shape.y, shape.z, color)
	var half := shape.x * 0.5
	var lid := RooftopSpace.lift(shape.z) + Vector2(0.0, -shape.y * 0.5)
	for rib in 5:
		var x := -half + 18.0 + float(rib) * (shape.x - 36.0) / 4.0
		draw_line(lid + Vector2(x, -shape.y * 0.42), lid + Vector2(x, shape.y * 0.42),
			RooftopSpace.top_face(color).darkened(0.2), 2.0)


## The tall one. A pipe is the clearest possible statement that this roof has a
## vertical axis, and the one prop a cat can stand completely behind.
func _draw_pipe(shape: Vector3, color: Color) -> void:
	var radius := shape.x * 0.5
	var rise := RooftopSpace.lift(shape.z)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-radius, 0.0), Vector2(radius, 0.0), Vector2(radius, 0.0) + rise, Vector2(-radius, 0.0) + rise,
	]), RooftopSpace.front_face(color))
	# A cylinder is a flat band plus one lit stripe down the side facing the
	# moon; without the stripe the same drawing is a rectangular post.
	if Moonlight.enabled:
		draw_line(Vector2(-radius * 0.55, 0.0), Vector2(-radius * 0.55, 0.0) + rise,
			Moonlight.rim(color, 0.3), radius * 0.5)
	draw_set_transform(rise + Vector2(0.0, -shape.y * 0.5), 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, radius, RooftopSpace.top_face(color))
	draw_circle(Vector2.ZERO, radius * 0.62, RooftopSpace.front_face(Color("1d2b2f")))
	draw_set_transform(Vector2.ZERO)
