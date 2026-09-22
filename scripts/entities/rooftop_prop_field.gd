class_name RooftopPropField
extends Node
## Stands the endless roof's furniture up as sortable nodes around the camera.
##
## RoofLayout decides what is where; this keeps the pieces near the view alive
## in the shared y-sorted stage, so a survivor or an enemy passes in front of or
## behind each one by where they stand. It used to do the opposite as well —
## fade every prop to a tenth of its opacity whenever a cat came near — which
## kept the fight clear but meant nothing ever visibly stood in front of
## anything, and the roof read as a flat floor with faint stickers on it.
##
## Now the furniture stays solid and the depth is allowed to show. Two narrow
## exceptions keep that from costing a run:
##
## - A tall piece that is actually hiding a survivor thins only slightly
##   (COVERED_ALPHA), and RooftopOcclusion draws the survivor's outline over it.
##   The piece still visibly stands in front; the player still knows where
##   their cat is.
## - A piece standing over a dropped item thins further (LOOT_ALPHA). Drops are
##   drawn below the stage, so any furniture overlapping one hides it however
##   the two are sorted, and a chest nobody can see is a chest nobody walks to.

const DecorScript := preload("res://scripts/entities/roof_decor.gd")
## Default half-extent of the roof to keep furnished around the camera, used
## until the owner reports the real view. Roughly one screen at the widest zoom.
const REACH := Vector2(1900.0, 1300.0)
## Extra roof kept furnished past the view: tall pieces rise up into the frame
## from anchors below its bottom edge, and pieces popping in at the edge read as
## the roof being built in front of you.
const SPAWN_SLACK := 280.0
## Pieces are only removed well past where they were added, so a camera sitting
## on the boundary does not build and free the same crate every few frames.
const RETIRE_SLACK := 700.0
## How far the camera travels before the set of pieces is reconsidered.
const REFRESH_STEP := 160.0
const COVERED_ALPHA := 0.8
const LOOT_ALPHA := 0.45
## The back stilts of a water tower are their own node, this far behind the
## front pair, so a cat standing under the tank sorts between them.
const TOWER_BACK := 76.0
## A knock from a cat walking through a piece, and from one dashing through it.
## Nothing on the roof blocks movement, so this is the whole of the collision:
## the piece answers the body instead of stopping it.
const WALK_JOLT := 0.45
const DASH_JOLT := 1.0
## Jolt lost per second. A full knock settles in a little under a second.
const JOLT_DECAY := 1.15
## How far outside its feet a piece still feels a cat brushing past.
const BUMP_REACH := 18.0

var stage: Node2D
var props: Dictionary = {} ## piece id -> RoofDecor
var loot: FieldItemSystem
var last_centre := Vector2(INF, INF)
var last_reach := Vector2.ZERO
var view_rect := Rect2(-2000.0, -2000.0, 4000.0, 4000.0)
## Where the camera was just put. The upright correction is measured from here
## rather than from the engine's per-frame view snapshot, which is taken once a
## frame and can predate this tick's camera move: after a jump (a run restarting, a test moving the view)
## that one stale frame measured every piece from the far side of the roof and
## sheared them into streaks across the screen.
var view_centre := Vector2.ZERO
var _upright := RooftopSpace.ViewSnapshot.new()
## The roof's shared weather. One clock and one gust for every piece, so the
## laundry, the trees and the chimney smoke all lean the same way at once.
var clock := 0.0
var wind := 0.0


func configure(sorted_stage: Node2D, drops: FieldItemSystem = null) -> void:
	stage = sorted_stage
	loot = drops


func follow(centre: Vector2, reach := REACH) -> void:
	if not is_instance_valid(stage):
		return
	view_rect = Rect2(centre - reach, reach * 2.0)
	view_centre = centre
	if centre.distance_to(last_centre) < REFRESH_STEP and reach.is_equal_approx(last_reach):
		return
	last_centre = centre
	last_reach = reach
	var wanted := view_rect.grow(SPAWN_SLACK)
	var keep := wanted.grow(RETIRE_SLACK)
	for piece in RoofLayout.pieces_in(wanted):
		var id := String(piece["id"])
		if props.has(id) and is_instance_valid(props[id]):
			continue
		var kind := String(piece["kind"])
		var at: Vector2 = piece["at"]
		_spawn(id, kind, at, int(piece["variant"]))
		if kind == "water_tower":
			_spawn(id + ":back", "water_tower_back", at - Vector2(0.0, TOWER_BACK), int(piece["variant"]))
	for id in props.keys():
		var prop = props[id]
		if not is_instance_valid(prop):
			props.erase(id)
			continue
		if not keep.has_point((prop as RoofDecor).ground):
			(prop as RoofDecor).queue_free()
			props.erase(id)


func living_props() -> Array[RoofDecor]:
	var living: Array[RoofDecor] = []
	for value in props.values():
		if is_instance_valid(value):
			living.append(value as RoofDecor)
	return living


func clear_all() -> void:
	for prop in props.values():
		if is_instance_valid(prop):
			(prop as RoofDecor).queue_free()
	props.clear()
	last_centre = Vector2(INF, INF)


## Everything drawn once is stale after the moonlight switch changes the grade.
func redraw_all() -> void:
	for prop in living_props():
		prop.queue_redraw()


func _spawn(id: String, kind: String, at: Vector2, variant: int) -> void:
	var prop := DecorScript.new() as RoofDecor
	prop.setup(kind, at, variant)
	prop.warmth = RoofLayout.warmth_at(at)
	var feet := RoofLayout.footprints({"kind": kind, "at": at})
	if not feet.is_empty():
		var area := feet[0]
		for foot in feet:
			area = area.merge(foot)
		prop.bump_area = area.grow(BUMP_REACH)
	stage.add_child(prop)
	props[id] = prop


## A big moment on the roof — a shockwave, a boss slamming its chain down —
## knocks every piece within reach, harder the closer it stood.
func shake_at(point: Vector2, radius: float, strength := 1.0) -> void:
	if radius <= 0.0:
		return
	for prop in living_props():
		var distance := prop.ground.distance_to(point)
		if distance >= radius:
			continue
		var knock := strength * (1.0 - distance / radius * 0.7)
		if knock > prop.jolt:
			prop.jolt = knock
			prop.jolt_side = 1.0 if prop.ground.x >= point.x else -1.0


## Called once per tick after the camera moves: keeps every piece upright for the
## current camera, advances the ones that move, and thins the few that are
## hiding something the player needs to see.
func update_visibility(players: Array[ChainPlayer], delta: float) -> void:
	clock += delta
	# Three incommensurate swells, so the wind never visibly loops.
	wind = sin(clock * 0.37) * 0.6 + sin(clock * 1.13 + 1.7) * 0.3 + sin(clock * 2.9 + 0.4) * 0.1
	var snapshot: RooftopSpace.ViewSnapshot = null
	if is_instance_valid(stage) and stage.is_inside_tree():
		var engine_view := RooftopSpace.view_snapshot(stage)
		if engine_view.valid:
			_upright.valid = true
			# Zoom read from the camera itself for the same reason as the centre:
			# the engine's per-frame snapshot may predate this tick's change.
			var camera := stage.get_viewport().get_camera_2d()
			_upright.zoom = camera.zoom if camera != null else engine_view.zoom
			_upright.view_size = engine_view.view_size
			_upright.centre = view_centre
			snapshot = _upright
	var drops := _drop_points()
	var bodies: Array[Rect2] = []
	var feet := PackedFloat32Array()
	for player in players:
		if is_instance_valid(player):
			bodies.append(RooftopOcclusion.body_rect(player))
			feet.append(player.global_position.y)
	var culling := view_rect.grow(260.0)
	for prop in living_props():
		prop.jolt = maxf(0.0, prop.jolt - delta * JOLT_DECAY)
		for player in players:
			if not is_instance_valid(player) or not prop.bump_area.has_point(player.global_position):
				continue
			var dashing := player.dash_timer > 0.0
			if not dashing and player.current_input.length() < 0.2:
				continue
			var knock := DASH_JOLT if dashing else WALK_JOLT
			if knock > prop.jolt:
				prop.jolt = knock
				var heading := player.dash_direction.x if dashing else player.current_input.x
				prop.jolt_side = -1.0 if heading < 0.0 else 1.0
		prop.clock = clock
		prop.wind = wind
		if snapshot != null and snapshot.valid:
			prop.stand_upright(snapshot.basis_at(prop.ground))
		var rect := prop.screen_rect()
		var on_screen := culling.intersects(rect) or culling.has_point(prop.ground)
		var settling := absf(prop.jolt - prop.drawn_jolt) > 0.001
		if on_screen and (prop.animated or settling):
			prop.queue_redraw()
		var target := 1.0
		if prop.tall:
			for index in bodies.size():
				if RooftopSpace.in_front_of(prop.ground.y, feet[index]) \
						and RooftopOcclusion.covered_share(bodies[index], rect) >= RooftopOcclusion.THIN_SHARE:
					target = COVERED_ALPHA
					break
		for point in drops:
			if rect.has_point(point):
				target = minf(target, LOOT_ALPHA)
				break
		prop.modulate.a = lerpf(prop.modulate.a, target, 1.0 - exp(-delta * 10.0))


func _drop_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(loot):
		return points
	for item in loot.active_items:
		if is_instance_valid(item) and item.active:
			points.append(item.global_position)
	return points
