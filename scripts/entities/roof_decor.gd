class_name RoofDecor
extends Node2D
## One piece of furniture standing on the run's roof — the upright half of it.
##
## The floor half (shadow, the puddle under a tank, the conduit leaving an air
## conditioner) is painted by ArenaFloor from the same RoofLayout entry, so this
## node draws only what rises off the roof. That split is what lets it take part
## in the y-sorted stage properly: its origin is the middle of the near edge of
## its footprint, which is both the point it stands on and the key it is sorted
## by, so a cat walking up the roof passes *behind* it and a cat walking down
## passes in front, with nothing faded out of the way.
##
## **Tall things are open underneath; solid things are low.** None of this
## blocks movement — making scenery stop a cat is the one change on this roof
## that could lose a run — so everything a survivor can end up "inside" is built
## so that being inside it looks right: a water tank on stilts, a parasol, a
## tree whose crown is well above its trunk, laundry on a line. The solid pieces
## (crates, air conditioners, a chimney) have small footprints and walking
## through one reads as passing behind it.
##
## Drawing happens in "upright pixels": x across, `d` back into the roof in
## world units, `h` straight up in screen pixels. `_p(x, d, h)` is the whole
## convention. The stage keeps the node's basis equal to the battlefield's
## upright correction (the same one the cats get), so a water tower stands
## straight at the edge of the screen instead of leaning into the vanishing
## point, and depth drawn here is foreshortened by exactly as much as the floor
## it sits on.

## How much one world unit of depth shrinks on screen: the battlefield's tilt.
## Duplicated rather than read from EndlessRooftopView so the prototype scene,
## which never builds that view, still draws a lid the right shape.
const DEPTH := 0.86
## The edge ink. Deliberately softer and bluer than the survivors' and the
## enemies' black sticker outline: furniture drawn in the same language as the
## actors competes with them for the eye, and the first thing a player must read
## on this roof is who is standing on it, not what.
const INK := Color(0.05, 0.09, 0.12, 0.6)
## No painted surface on the roof gets brighter than this. The parasol canvas,
## the cardboard and the milk crate were the brightest things on screen, which
## on a night roof is the actors' and the drops' place, not the furniture's.
const VALUE_CAP := 0.7
## The painted props. Every kind shares one texture, so a crowded roof batches
## them and they share one mip chain; the individual PNGs stay in
## assets/environment/props for editing. Built by
## scripts/tools/normalize_roof_prop_sprites.gd from art/originals.
const PROP_ATLAS: Texture2D = preload("res://assets/environment/roof_props_atlas.png")
## Where each kind sits in the atlas, in game units. The atlas holds SPRITE_TEXELS
## texels per unit, so a sprite is sharp at the ~1.5 screen pixels per unit a
## 1080p window shows the roof at, and the mip chain handles zooming out.
const PROP_REGIONS := {
	"water_tower": Rect2(0, 0, 116, 222),
	"laundry": Rect2(118, 0, 224, 128),
	"lights": Rect2(344, 0, 268, 118),
	"antenna": Rect2(614, 0, 80, 204),
	"tree_pot": Rect2(696, 0, 112, 212),
	"parasol": Rect2(810, 0, 128, 186),
	"chimney": Rect2(0, 224, 62, 170),
	"ac_unit": Rect2(64, 224, 100, 100),
	"boxes": Rect2(166, 224, 88, 126),
	"milk_crate": Rect2(256, 224, 66, 84),
	"garden": Rect2(324, 224, 158, 104),
	"bench": Rect2(484, 224, 128, 104),
	"turbine": Rect2(614, 224, 56, 88),
	"cat_house": Rect2(672, 224, 80, 120),
	"fish_rack": Rect2(754, 224, 148, 102),
	"pots": Rect2(0, 396, 96, 98),
	"solar": Rect2(98, 396, 112, 96),
	"skylight": Rect2(212, 396, 118, 82),
	"dish": Rect2(332, 396, 76, 104),
}
const SPRITE_TEXELS := 2.0
## Transparent margin under every sprite, so its visible foot sits on the origin.
const SPRITE_BOTTOM_PAD := 4.0
## Painted sprites or the drawn shapes. The shapes stay as the fallback and for
## side-by-side comparison, the way the moonlight pass keeps its off switch.
static var painted := true
## Kinds that still redraw while on screen once painted: the parts of them that
## move or glow (smoke, a warning light, bulbs, fireflies) are drawn over the
## sprite each frame. Everything else is one texture quad drawn once.
const PAINTED_MOTION := ["chimney", "antenna", "lights", "tree_pot", "garden"]
## Constant lean in the shared wind, for the tall and leafy. Applied as a shear
## of the whole node, like a knock, so it costs no redraw.
const WIND_LEAN := {"tree_pot": 0.025, "antenna": 0.012}
## The colour a piece near string lights or a lit skylight takes on its lit
## edges, so the roof's two lights — cold moon, warm lamps — touch the same things.
const WARM_RIM := Color("ffc98a")
## How far the top of each kind sways when something knocks into it, per unit
## of jolt. Poles and lines give a lot; a brick chimney barely moves.
const WOBBLE := {
	"laundry": 0.1, "lights": 0.07, "antenna": 0.12, "tree_pot": 0.08, "parasol": 0.07,
	"fish_rack": 0.09, "dish": 0.08, "water_tower": 0.025, "water_tower_back": 0.025,
	"chimney": 0.015, "turbine": 0.06,
}
const WOOD := Color("8b6446")
const WOOD_DARK := Color("5e4432")
const METAL := Color("8a9796")
const METAL_DARK := Color("4f5e60")
const BRICK := Color("9a5a44")
const CARD := Color("b98d5f")
const TERRA := Color("b8674a")
const LEAF := Color("5b9a66")
const LEAF_DARK := Color("356349")
const CREAM := Color("efe2c6")
const TEAL := Color("4fa3a5")
const PINK := Color("e59aa8")
const LAVENDER := Color("a99ad8")
const BLUE := Color("3f7fb0")
const SOIL := Color("46372b")
const CANVAS := Color("c9b99a")
## Emissive colours. These are light, not surfaces, so they skip the night grade.
const WARM := [Color("ffd27f"), Color("ffb38a"), Color("fff0b5"), Color("ffc2d4")]
const EYE := Color("d8f56e")

var kind := ""
var variant := 0
## Where this piece stands on the flat roof. `position` is kept equal to it; the
## field rewrites the basis every frame and must not move the sort key.
var ground := Vector2.ZERO
var cover := Rect2()
var tall := false
var animated := false
## Animation inputs handed down by the field, so every piece on screen shares
## one wind and one clock — laundry and trees leaning together is most of what
## sells the wind.
var clock := 0.0
var wind := 0.0
var phase := 0.0
## How hard this piece has just been knocked, 0 to 1, decaying back to rest. A
## cat walking through raises it a little, a dash a lot, a shockwave by distance.
## Nothing here blocks anyone, so this is what says a body was there.
var jolt := 0.0
## Which way the knock came from, so a piece leans away from what hit it.
var jolt_side := 1.0
## 0 to 1: how near this piece stands to one of the roof's warm lights.
var warmth := 0.0
## Where a body counts as bumping this piece: its feet, grown by a cat's reach.
var bump_area := Rect2()
## The jolt the current drawing was made with, so the field redraws a knocked
## piece until it has visibly come to rest and not a frame longer.
var drawn_jolt := 0.0


func setup(piece_kind: String, at: Vector2, piece_variant := 0) -> void:
	kind = piece_kind
	variant = piece_variant
	ground = at
	position = at
	var info := RoofLayout.spec(kind)
	cover = info.get("cover", Rect2())
	tall = bool(info.get("tall", false))
	animated = bool(info.get("animated", false))
	if painted and (PROP_REGIONS.has(kind) or kind == "water_tower_back"):
		animated = kind in PAINTED_MOTION
	phase = float(variant % 997) * 0.173
	z_index = 0
	queue_redraw()


## Tall enough that a survivor behind it can disappear, which is what the
## see-through silhouette in RooftopOcclusion exists for.
func bulky() -> bool:
	return tall


## The part of the drawing that can hide something, in the stage's coordinates:
## the cover rectangle carried through the node's current upright basis.
func screen_rect() -> Rect2:
	var rect := Rect2(transform * cover.position, Vector2.ZERO)
	for corner: Vector2 in [Vector2(cover.end.x, cover.position.y), cover.end, Vector2(cover.position.x, cover.end.y)]:
		rect = rect.expand(transform * corner)
	return rect


## The camera's upright correction, plus the sway of a recent knock as a shear
## about the base: the foot stays planted and the top swings, which is exactly
## how a post or a pot reacts, and it costs a transform rather than a redraw.
func stand_upright(basis: Transform2D) -> void:
	var lean := jolt * float(WOBBLE.get(kind, 0.035)) * sin(clock * 17.0 + phase) * jolt_side
	if painted:
		lean += wind * float(WIND_LEAN.get(kind, 0.0))
	transform = Transform2D(basis.x, basis.y + Vector2(lean * basis.y.y, 0.0), ground)


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:roof_decor", probe_started)


func _probed_draw() -> void:
	drawn_jolt = jolt
	if painted and _draw_painted():
		return
	match kind:
		"water_tower":
			_draw_water_tower()
		"water_tower_back":
			_draw_tower_legs()
		"laundry":
			_draw_laundry()
		"lights":
			_draw_lights()
		"antenna":
			_draw_antenna()
		"tree_pot":
			_draw_tree_pot()
		"parasol":
			_draw_parasol()
		"chimney":
			_draw_chimney()
		"ac_unit":
			_draw_ac_unit()
		"boxes":
			_draw_boxes()
		"milk_crate":
			_draw_milk_crate()
		"garden":
			_draw_garden()
		"bench":
			_draw_bench()
		"turbine":
			_draw_turbine()
		"cat_house":
			_draw_cat_house()
		"fish_rack":
			_draw_fish_rack()
		"pots":
			_draw_pots()
		"solar":
			_draw_solar()
		"skylight":
			_draw_skylight()
		"dish":
			_draw_dish()


# --- Painted sprites ------------------------------------------------------------

## Draws the painted version of this kind, and anything on it that moves. False
## when there is no sprite for it, so the drawn shapes take over.
func _draw_painted() -> bool:
	# The painted water tower has all four stilts in one picture; its back-stilt
	# node has nothing left to draw.
	if kind == "water_tower_back":
		return true
	if not PROP_REGIONS.has(kind):
		return false
	var region: Rect2 = PROP_REGIONS[kind]
	var source := Rect2(region.position * SPRITE_TEXELS, region.size * SPRITE_TEXELS)
	var place := Rect2(Vector2(-region.size.x * 0.5, -region.size.y + SPRITE_BOTTOM_PAD), region.size)
	draw_texture_rect_region(PROP_ATLAS, place, source, _sprite_tint())
	match kind:
		"chimney":
			_smoke(Vector2(0.0, -region.size.y + SPRITE_BOTTOM_PAD - 2.0))
		"antenna":
			_warning_light(Vector2(0.0, -region.size.y + SPRITE_BOTTOM_PAD + 6.0))
		"lights":
			_bulb_glow(region.size)
		"tree_pot":
			var crown := Vector2(0.0, -region.size.y * 0.66)
			_fireflies(crown, 60.0, 3)
			_shaken_leaves([crown + Vector2(-24, -20), crown + Vector2(18, -8), crown + Vector2(0, 26)])
		"garden":
			_fireflies(Vector2(0.0, -region.size.y * 0.55), 70.0, 2)
	return true


## The sprites are painted for the moonlit roof already, so the only grade they
## take is the lamp warmth of pieces standing near the roof's warm lights.
func _sprite_tint() -> Color:
	return Color.WHITE.lerp(WARM_RIM, warmth * 0.14)


func _smoke(flue: Vector2) -> void:
	for puff in 5:
		var life := fmod(clock * 0.3 + float(puff) * 0.2 + phase, 1.0)
		var at := flue + Vector2((wind * 38.0 + 16.0 + jolt * jolt_side * 40.0) * life + sin(life * 6.0 + float(puff)) * 4.0, -78.0 * life)
		var alpha := 0.2 * (1.0 - life) * smoothstep(0.0, 0.12, life)
		draw_circle(at, 7.0 + 16.0 * life, Color(0.74, 0.8, 0.88, alpha))


func _warning_light(tip: Vector2) -> void:
	if fmod(clock * 0.8 + phase, 1.0) < 0.18:
		draw_circle(tip, 12.0, Color("ff4d5e", 0.2))
		draw_circle(tip, 6.0, Color("ff4d5e", 0.35))
		draw_circle(tip, 2.6, Color("ffb3ba"))


## The painted bulbs are lit already; this is the breath on top of them — a soft
## halo along the sag of the cable that swells and dims bulb by bulb, and two
## moths. Kept faint, because it is laid over the painting rather than on the
## bulbs' exact pixels.
func _bulb_glow(size: Vector2) -> void:
	var left := Vector2(-size.x * 0.4, -size.y * 0.8)
	var right := Vector2(size.x * 0.4, -size.y * 0.8)
	var sag := size.y * 0.16 + _knock(8.0) * 6.0
	for bulb in 9:
		var t := (float(bulb) + 0.5) / 9.0
		var at := left.lerp(right, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t) + 8.0)
		var tone: Color = WARM[(bulb + variant) % WARM.size()]
		var bright := 0.6 + 0.4 * sin(clock * 2.4 + float(bulb) * 1.9 + phase)
		draw_circle(at, 12.0, Color(tone, 0.07 * bright))
		draw_circle(at, 6.0, Color(tone, 0.12 * bright))
	for moth in 2:
		var t := (2.5 + float(moth) * 4.0) / 9.0
		var home := left.lerp(right, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t) + 8.0)
		var loop := clock * (3.1 + float(moth)) + phase + float(moth) * 2.0
		var at := home + Vector2(cos(loop) * 11.0, sin(loop * 1.7) * 7.0) * (1.0 + jolt * 3.0)
		draw_circle(at, 1.7, Color(0.95, 0.92, 0.84, 0.85))
		draw_line(at + Vector2(-2.6, -1.0), at + Vector2(2.6, -1.0), Color(0.95, 0.92, 0.84, 0.6), 1.0)


## A knocked tree lets a few leaves go; they drift down as the knock fades.
func _shaken_leaves(crown: Array) -> void:
	if jolt <= 0.02:
		return
	var fall := 1.0 - jolt
	for leaf in 5:
		var loose: Vector2 = crown[leaf % crown.size()] + Vector2((float(leaf) - 2.0) * 10.0, 8.0)
		var at := loose + Vector2(sin(fall * 6.0 + float(leaf)) * 10.0, fall * 100.0)
		draw_set_transform(at, fall * 5.0 + float(leaf), Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 4.0, Color(_g(LEAF, 0.1), clampf(jolt * 1.6, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO)


# --- Shared vocabulary ---------------------------------------------------------

func _p(x: float, d: float, h: float) -> Vector2:
	return Vector2(x, -d * DEPTH - h)


## The night grade, with the value cap and the lamp warmth applied on top.
func _g(color: Color, lit := 0.0) -> Color:
	var graded := Moonlight.ground(color, lit)
	if graded.v > VALUE_CAP:
		graded.v = VALUE_CAP + (graded.v - VALUE_CAP) * 0.3
	graded.s *= 0.92
	if warmth > 0.0:
		graded = graded.lerp(Color(WARM_RIM, graded.a), warmth * 0.08)
	return graded


func _front(color: Color) -> Color:
	return _g(color).darkened(0.3)


func _top(color: Color) -> Color:
	return _g(color, 0.22)


func _flat(color: Color) -> Color:
	return _g(color, 0.1)


func _rim(color: Color, strength := 0.5) -> Color:
	if not Moonlight.enabled:
		return color.lightened(0.25)
	return Moonlight.rim(color, strength).lerp(WARM_RIM, warmth * 0.5)


## A sway term driven by the last knock: zero at rest, a decaying wobble after.
func _knock(speed: float, offset := 0.0) -> float:
	return jolt * sin(clock * speed + phase + offset)


## Where a face meets the floor it is darker: the roof and the thing standing on
## it block each other's light. Two soft bands rather than a gradient, because
## this is a vector drawing and two steps already read as a falloff.
func _ground_shade(left: float, right: float, d: float, h0: float, h1: float) -> void:
	for band in [[0.45, 18.0, 0.13], [0.2, 7.0, 0.15]]:
		var top := h0 + minf(float(band[1]), (h1 - h0) * float(band[0]))
		draw_colored_polygon(PackedVector2Array([_p(left, d, h0), _p(right, d, h0), _p(right, d, top), _p(left, d, top)]),
			Color(Moonlight.SHADOW_INK, float(band[2])))


func _outline(points: PackedVector2Array, width := 1.5) -> void:
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, INK, width, true)


## A solid block: front face, lid, the lit lip between them and an ink edge
## around the silhouette. Every crate, cabinet and slab on the roof is this.
func _box(x: float, d: float, w: float, depth: float, h0: float, h1: float, color: Color) -> void:
	var left := x - w * 0.5
	var right := x + w * 0.5
	if h1 > h0:
		draw_colored_polygon(PackedVector2Array([_p(left, d, h0), _p(right, d, h0), _p(right, d, h1), _p(left, d, h1)]), _front(color))
		if h0 <= 1.0:
			_ground_shade(left, right, d, h0, h1)
	if depth > 0.0:
		draw_colored_polygon(PackedVector2Array([_p(left, d, h1), _p(right, d, h1), _p(right, d + depth, h1), _p(left, d + depth, h1)]), _top(color))
	_outline(PackedVector2Array([_p(left, d, h0), _p(right, d, h0), _p(right, d + depth, h1), _p(left, d + depth, h1)]))
	draw_line(_p(left, d, h1), _p(right, d, h1), _rim(color), 1.6, true)
	if h1 > h0:
		# The left wall is turned into the moon; its edge is the second place a
		# box catches light.
		draw_line(_p(left + 1.0, d, h0), _p(left + 1.0, d, h1), _rim(color, 0.3), 1.2, true)


func _ellipse(centre: Vector2, rx: float, ry: float, start := 0.0, stop := TAU, steps := 20) -> PackedVector2Array:
	var points := PackedVector2Array()
	# A closed ring must not repeat its first point: the triangulator rejects a
	# polygon with two coincident vertices.
	var count := steps if absf(stop - start) >= TAU - 0.001 else steps + 1
	for step in count:
		var angle := lerpf(start, stop, float(step) / float(steps))
		points.append(centre + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


## An upright cylinder standing on the floor: a round tank, a pot, a stool.
func _cylinder(x: float, d: float, radius: float, h0: float, h1: float, color: Color, lid := Color(0, 0, 0, 0)) -> void:
	var ry := radius * DEPTH
	var bottom := _p(x, d, h0)
	var top := _p(x, d, h1)
	var body := _ellipse(bottom, radius, ry, 0.0, PI, 12)
	body.append_array(_ellipse(top, radius, ry, PI, 0.0, 12))
	draw_colored_polygon(body, _front(color))
	# The moon is up and to the left, so the left third of a drum is its bright
	# side. One band of lighter paint is all a cylinder needs to stop reading as
	# a flat plate.
	var lit := _ellipse(bottom, radius, ry, PI * 0.62, PI * 0.9, 5)
	lit.append_array(_ellipse(top, radius, ry, PI * 0.9, PI * 0.62, 5))
	draw_colored_polygon(lit, _g(color, 0.18))
	if h0 <= 1.0:
		for band in [[0.45, 16.0, 0.13], [0.2, 6.0, 0.15]]:
			var rise := h0 + minf(float(band[1]), (h1 - h0) * float(band[0]))
			var shade := _ellipse(bottom, radius, ry, 0.0, PI, 10)
			shade.append_array(_ellipse(_p(x, d, rise), radius, ry, PI, 0.0, 10))
			draw_colored_polygon(shade, Color(Moonlight.SHADOW_INK, float(band[2])))
	var cap := _ellipse(top, radius, ry, 0.0, TAU, 20)
	draw_colored_polygon(cap, _top(color) if lid.a == 0.0 else lid)
	var silhouette := _ellipse(bottom, radius, ry, 0.0, PI, 12)
	silhouette.append_array(_ellipse(top, radius, ry, PI, TAU, 12))
	_outline(silhouette)
	draw_arc(top, radius - 1.0, PI * 1.02, PI * 1.72, 10, _rim(color), 1.6, true)


## A post or pole: ink under, paint over, a hairline of moon down its left edge.
func _post(start: Vector2, stop: Vector2, width: float, color: Color) -> void:
	draw_line(start, stop, INK, width + 2.0, true)
	draw_line(start, stop, _front(color).lightened(0.12), width, true)
	if width >= 3.0:
		draw_line(start + Vector2(-width * 0.25, 0.0), stop + Vector2(-width * 0.25, 0.0), _rim(color, 0.35), 1.0, true)


## `frame` is the transform already in force, for a fish drawn inside something
## that is itself rotated (a towel on the line). Setting a transform replaces the
## current one rather than stacking on it, so the caller's has to be carried in
## and put back.
func _fish(centre: Vector2, size: float, color: Color, angle := 0.0, width := 1.6,
		frame := Transform2D.IDENTITY) -> void:
	draw_set_transform_matrix(frame * Transform2D(angle, Vector2.ONE * size / 10.0, 0.0, centre))
	draw_arc(Vector2.ZERO, 7.0, -1.1, 1.1, 10, color, width * 10.0 / size, true)
	draw_arc(Vector2(5.5, 0.0), 7.0, PI - 1.1, PI + 1.1, 10, color, width * 10.0 / size, true)
	draw_polyline(PackedVector2Array([Vector2(-1.0, -3.0), Vector2(-6.0, -6.0), Vector2(-6.0, 6.0), Vector2(-1.0, 3.0)]),
		color, width * 10.0 / size, true)
	draw_set_transform_matrix(frame)


func _sway(speed: float, amount: float, offset := 0.0) -> float:
	return sin(clock * speed + phase + offset) * amount


# --- Landmarks -----------------------------------------------------------------

## The back pair of stilts, as its own node sorted at the back of the footprint,
## so a cat standing under the tank is in front of these and behind the front pair.
func _draw_tower_legs() -> void:
	for x: float in [-42.0, 42.0]:
		_post(_p(x, 0, 0), _p(x, 0, 86), 6.0, METAL_DARK)
	draw_line(_p(-42, 0, 14), _p(42, 0, 62), Color(INK, 0.7), 3.0, true)
	draw_line(_p(42, 0, 14), _p(-42, 0, 62), Color(INK, 0.7), 3.0, true)


func _draw_water_tower() -> void:
	# Front stilts and their cross brace. The back pair belongs to the other node.
	for x: float in [-42.0, 42.0]:
		_post(_p(x, 0, 0), _p(x, 0, 86), 7.0, METAL_DARK)
		draw_colored_polygon(_ellipse(_p(x, 0, 0), 7.0, 3.0), _front(METAL_DARK))
	draw_line(_p(-42, 0, 14), _p(42, 0, 62), _front(METAL), 3.0, true)
	draw_line(_p(42, 0, 14), _p(-42, 0, 62), _front(METAL), 3.0, true)
	_box(0, -8, 118, 90, 84, 90, WOOD_DARK)
	# The tank: vertical staves held by two iron hoops.
	_cylinder(0, 38, 50, 90, 152, WOOD)
	var ry := 50.0 * DEPTH
	for stave in 7:
		var angle := PI * (0.12 + float(stave) * 0.126)
		var x := cos(angle) * 50.0
		var drop := sin(angle) * ry
		draw_line(_p(x, 38, 90) + Vector2(0, drop), _p(x, 38, 152) + Vector2(0, drop),
			Color(_front(WOOD).darkened(0.35), 0.8), 1.4, true)
	for hoop: float in [104.0, 140.0]:
		draw_polyline(_ellipse(_p(0, 38, hoop), 50.5, ry, 0.0, PI, 14), _front(METAL_DARK), 2.6, true)
	# A fish painted on the tank by someone who clearly feeds the cats up here.
	_fish(_p(-8, 38, 122) + Vector2(0, ry * 0.92), 13.0, Color(_flat(CREAM), 0.7), 0.0, 2.0)
	# The conical roof. The far half of its rim is drawn first as the shaded
	# side, then the near half as a fan that is lit on the left.
	var rim_centre := _p(0, 38, 152)
	var apex := _p(0, 38, 196)
	draw_colored_polygon(_ellipse(rim_centre, 55.0, ry + 3.0), _front(METAL_DARK))
	var fan_steps := 10
	for step in fan_steps:
		var a0 := PI - PI * float(step) / float(fan_steps)
		var a1 := PI - PI * float(step + 1) / float(fan_steps)
		var share := float(step) / float(fan_steps)
		var shade := _g(METAL, lerpf(0.42, 0.0, share)).darkened(share * 0.28)
		draw_colored_polygon(PackedVector2Array([apex,
			rim_centre + Vector2(cos(a0) * 55.0, sin(a0) * (ry + 3.0)),
			rim_centre + Vector2(cos(a1) * 55.0, sin(a1) * (ry + 3.0))]), shade)
	var roof_outline := _ellipse(rim_centre, 55.0, ry + 3.0, 0.0, PI, 12)
	roof_outline.append(apex)
	_outline(roof_outline)
	draw_circle(apex + Vector2(0, -3), 4.0, _top(METAL_DARK))
	# A ladder up the near stilt to the tank's rim.
	for rail: float in [22.0, 32.0]:
		draw_line(_p(rail, -12, 0), _p(rail, -12, 150), INK, 3.2, true)
		draw_line(_p(rail, -12, 0), _p(rail, -12, 150), _flat(METAL), 1.6, true)
	for rung in 14:
		var h := 8.0 + float(rung) * 10.0
		draw_line(_p(22, -12, h), _p(32, -12, h), _flat(METAL), 1.6, true)


## Laundry on a line between two T-posts, moving in the one wind the whole roof
## shares. The clothes are the cover: a cat walking behind the line is hidden
## from the waist up, which is the everyday version of passing behind something.
func _draw_laundry() -> void:
	for x: float in [-108.0, 108.0]:
		draw_colored_polygon(_ellipse(_p(x, 0, 0), 9.0, 4.0), _front(METAL_DARK))
		_post(_p(x, 0, 0), _p(x, 0, 118), 5.0, METAL)
		_post(_p(x - 12.0, 0, 118), _p(x + 12.0, 0, 118), 3.0, METAL)
	var line := _line_points(_p(-108, 0, 114), _p(108, 0, 114), 16.0 + wind * 2.0, 18)
	draw_polyline(line, INK, 3.0, true)
	draw_polyline(line, _flat(CREAM), 1.4, true)
	var palettes := [[PINK, TEAL, CREAM, LAVENDER], [TEAL, CREAM, PINK, Color("f2c46d")], [LAVENDER, PINK, TEAL, CREAM]]
	var colours: Array = palettes[variant % palettes.size()]
	var items := [[0.18, "shirt"], [0.43, "towel"], [0.63, "sock"], [0.71, "sock"], [0.87, "kerchief"]]
	for index in items.size():
		var t := float(items[index][0])
		var anchor := _line_at(_p(-108, 0, 114), _p(108, 0, 114), 16.0 + wind * 2.0, t)
		var swing := wind * 0.16 + _sway(2.3, 0.07, t * 6.0) + _knock(9.0, t * 6.0) * 0.4
		var frame := Transform2D(swing, anchor)
		draw_set_transform_matrix(frame)
		_draw_garment(String(items[index][1]), colours[index % colours.size()], frame)
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(anchor + Vector2(-1.5, -3.0), Vector2(3.0, 6.0)), _flat(WOOD))


func _draw_garment(shape: String, color: Color, frame: Transform2D) -> void:
	var fill := _flat(color)
	var shade := fill.darkened(0.22)
	match shape:
		"shirt":
			var body := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0), Vector2(19, 7), Vector2(14, 13),
				Vector2(10, 10), Vector2(10, 32), Vector2(-10, 32), Vector2(-10, 10), Vector2(-14, 13), Vector2(-19, 7)])
			draw_colored_polygon(body, fill)
			draw_colored_polygon(PackedVector2Array([Vector2(2, 10), Vector2(10, 10), Vector2(10, 32), Vector2(2, 32)]), shade)
			_outline(body, 1.6)
			draw_arc(Vector2(0, 0), 4.0, 0.2, PI - 0.2, 8, shade.darkened(0.2), 1.6, true)
			# A paw print, because of course it has one.
			var paw := fill.lightened(0.35)
			draw_circle(Vector2(-2, 20), 3.0, paw)
			for toe: Vector2 in [Vector2(-6, 15), Vector2(-2, 13.5), Vector2(2, 15)]:
				draw_circle(toe, 1.4, paw)
		"towel":
			var cloth := PackedVector2Array([Vector2(-13, 0), Vector2(13, 0), Vector2(13, 42), Vector2(-13, 42)])
			draw_colored_polygon(cloth, fill)
			draw_rect(Rect2(-13, 8, 26, 5), shade)
			draw_rect(Rect2(-13, 30, 26, 5), shade)
			_fish(Vector2(0, 21), 9.0, fill.lightened(0.3), 0.0, 1.6, frame)
			_outline(cloth, 1.6)
			for tassel in 6:
				var x := -11.0 + float(tassel) * 4.4
				draw_line(Vector2(x, 42), Vector2(x, 46), shade, 1.2, true)
		"sock":
			var sock := PackedVector2Array([Vector2(-4, 0), Vector2(4, 0), Vector2(4, 16), Vector2(11, 20),
				Vector2(9, 26), Vector2(-3, 24), Vector2(-4, 16)])
			draw_colored_polygon(sock, fill)
			draw_rect(Rect2(-4, 0, 8, 4), shade)
			_outline(sock, 1.4)
		_:
			var cloth := PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(0, 19)])
			draw_colored_polygon(cloth, fill)
			draw_circle(Vector2(-3, 5), 1.5, fill.lightened(0.4))
			draw_circle(Vector2(4, 4), 1.5, fill.lightened(0.4))
			_outline(cloth, 1.4)


func _line_at(start: Vector2, stop: Vector2, sag: float, t: float) -> Vector2:
	return start.lerp(stop, t) + Vector2(wind * 2.0 * sin(PI * t), sag * 4.0 * t * (1.0 - t))


func _line_points(start: Vector2, stop: Vector2, sag: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in steps + 1:
		points.append(_line_at(start, stop, sag, float(step) / float(steps)))
	return points


## Café string lights. The bulbs are the only warm light the roof owns, so they
## are kept small and few; the floor pool under them is ArenaFloor's glow.
func _draw_lights() -> void:
	for x: float in [-130.0, 130.0]:
		draw_colored_polygon(_ellipse(_p(x, 0, 0), 8.0, 3.5), _front(METAL_DARK))
		_post(_p(x, 0, 0), _p(x, 0, 106), 4.0, METAL_DARK)
		draw_circle(_p(x, 0, 108), 3.5, _top(METAL_DARK))
	var start := _p(-130, 0, 102)
	var stop := _p(130, 0, 102)
	var sag := 22.0 + wind * 2.5 + _knock(8.0) * 7.0
	var wire := _line_points(start, stop, sag, 20)
	draw_polyline(wire, INK, 2.4, true)
	draw_polyline(wire, _front(METAL_DARK), 1.2, true)
	var count := 9
	for bulb in count:
		var t := (float(bulb) + 0.5) / float(count)
		var at := _line_at(start, stop, sag, t) + Vector2(0, 5)
		var tone: Color = WARM[(bulb + variant) % WARM.size()]
		var bright := 0.8 + 0.2 * sin(clock * 2.4 + float(bulb) * 1.9 + phase)
		# Now and then one bulb stutters. Just one, just briefly — a whole string
		# flickering is a horror film, one loose bulb is a real roof.
		if int(clock * 5.0 + phase) % 41 == bulb:
			bright *= 0.35
		draw_rect(Rect2(at + Vector2(-1.5, -5.0), Vector2(3.0, 3.5)), INK)
		draw_circle(at, 13.0, Color(tone, 0.10 * bright))
		draw_circle(at, 8.0, Color(tone, 0.20 * bright))
		draw_circle(at, 4.2, Color(tone.lerp(Color.WHITE, 0.25 * bright), 0.95))
	# Two moths that have found the warmest bulbs.
	for moth in 2:
		var bulb := 2 + moth * 4
		var home := _line_at(start, stop, sag, (float(bulb) + 0.5) / float(count)) + Vector2(0, 5)
		var loop := clock * (3.1 + float(moth)) + phase + float(moth) * 2.0
		# A knock sends them wide for a moment before they settle back in.
		var at := home + Vector2(cos(loop) * 11.0, sin(loop * 1.7) * 7.0) * (1.0 + jolt * 3.0)
		draw_circle(at, 1.7, Color(0.95, 0.92, 0.84, 0.85))
		draw_line(at + Vector2(-2.6, -1.0), at + Vector2(2.6, -1.0), Color(0.95, 0.92, 0.84, 0.6), 1.0)


func _draw_antenna() -> void:
	var base := _p(0, 10, 0)
	for foot: Vector2 in [_p(-16, 0, 0), _p(16, 0, 0), _p(0, 22, 0)]:
		draw_line(foot, _p(0, 10, 30), INK, 3.5, true)
		draw_line(foot, _p(0, 10, 30), _front(METAL_DARK), 2.0, true)
	# Guy wires, pale and thin, so the mast reads as held up rather than stuck in.
	for anchor: Vector2 in [_p(-58, -6, 0), _p(58, -6, 0)]:
		draw_line(_p(0, 10, 150), anchor, Color(_flat(METAL), 0.45), 1.0, true)
	_post(base, _p(0, 10, 182), 3.5, METAL)
	# Receiving elements, shortening toward the tip. From the front the array is
	# a fish skeleton, which on this roof is not a coincidence anybody minds.
	var rods := [[172.0, 12.0], [161.0, 20.0], [150.0, 27.0], [139.0, 32.0]]
	for rod in rods:
		var h := float(rod[0])
		var reach := float(rod[1])
		_post(_p(-reach, 10, h), _p(reach, 10, h), 2.0, METAL)
	draw_line(_p(0, 10, 132), _p(0, 10, 178), _rim(METAL, 0.4), 1.0, true)
	var tip := _p(0, 10, 188)
	var blink := fmod(clock * 0.8 + phase, 1.0) < 0.18
	if blink:
		draw_circle(tip, 12.0, Color("ff4d5e", 0.18))
		draw_circle(tip, 6.0, Color("ff4d5e", 0.32))
		draw_circle(tip, 3.4, Color("ff8a94"))
	else:
		draw_circle(tip, 3.2, Color("6b2d35"))
	draw_arc(tip, 3.6, 0.0, TAU, 10, INK, 1.2, true)


# --- Greenery ------------------------------------------------------------------

func _draw_tree_pot() -> void:
	_box(0, 0, 64, 50, 0, 38, WOOD)
	for h: float in [13.0, 26.0]:
		draw_line(_p(-31, 0, h), _p(31, 0, h), _front(WOOD).darkened(0.3), 1.4, true)
	draw_colored_polygon(PackedVector2Array([_p(-26, 5, 38), _p(26, 5, 38), _p(26, 45, 38), _p(-26, 45, 38)]), _flat(SOIL))
	var lean := wind * 3.5 + _sway(1.4, 1.4) + _knock(13.0) * 7.0
	var trunk := PackedVector2Array([_p(0, 25, 38), _p(3, 25, 66), _p(-2 + lean * 0.3, 25, 92), _p(lean * 0.5, 25, 112)])
	draw_polyline(trunk, INK, 9.5, true)
	draw_polyline(trunk, _g(Color("6b4a36")), 7.0, true)
	draw_line(_p(2, 25, 80), _p(-18 + lean * 0.4, 25, 104), INK, 5.0, true)
	draw_line(_p(2, 25, 80), _p(-18 + lean * 0.4, 25, 104), _g(Color("6b4a36")), 3.0, true)
	var crown := [[-20.0, 112.0, 24.0], [18.0, 116.0, 26.0], [-26.0, 136.0, 20.0], [26.0, 140.0, 20.0],
		[0.0, 138.0, 30.0], [-10.0, 156.0, 19.0], [8.0, 160.0, 22.0]]
	var centres: Array[Vector2] = []
	for blob in crown:
		var h := float(blob[1])
		var give := lean * (h - 100.0) / 60.0
		centres.append(_p(float(blob[0]) + give, 25, h))
	for index in crown.size():
		draw_circle(centres[index], float(crown[index][2]) + 2.5, INK)
	for index in crown.size():
		draw_circle(centres[index], float(crown[index][2]), _g(LEAF_DARK))
	for index in crown.size():
		var radius := float(crown[index][2])
		draw_circle(centres[index] + Vector2(-radius * 0.22, -radius * 0.24), radius * 0.68, _g(LEAF, 0.12))
	if Moonlight.enabled:
		for index in [2, 5, 6]:
			var radius := float(crown[index][2])
			draw_arc(centres[index], radius - 2.0, PI * 1.05, PI * 1.6, 10, Moonlight.rim(LEAF, 0.45), 2.0, true)
	# A few paler leaves so the crown has texture rather than being six discs.
	for speck in 9:
		var angle := float(speck) * 2.4 + phase
		var at := centres[4] + Vector2(cos(angle) * 28.0, sin(angle) * 20.0 - 6.0)
		draw_circle(at, 2.6, _g(LEAF.lightened(0.25), 0.15))
	_fireflies(_p(0, 25, 120), 60.0, 3)
	# Shaken leaves: a few let go of the crown and drift down as the knock fades.
	if jolt > 0.02:
		var fall := 1.0 - jolt
		for leaf in 5:
			var loose := centres[(leaf * 2) % centres.size()] + Vector2((float(leaf) - 2.0) * 10.0, 8.0)
			var at := loose + Vector2(sin(fall * 6.0 + float(leaf)) * 10.0, fall * 100.0)
			draw_set_transform(at, fall * 5.0 + float(leaf), Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 4.0, Color(_g(LEAF, 0.1), clampf(jolt * 1.6, 0.0, 1.0)))
			draw_set_transform(Vector2.ZERO)


## A few fireflies drifting around greenery, each pulsing on its own slow beat.
## Emissive, and tiny: they are there to be noticed on a quiet screen, not to
## compete with anything on a busy one.
func _fireflies(centre: Vector2, spread: float, count: int) -> void:
	for fly in count:
		var offset := phase + float(fly) * 2.3
		var reach := spread * (1.0 + jolt * 1.5)
		var drift := Vector2(sin(clock * 0.43 + offset) * reach, sin(clock * 0.31 + offset * 1.7) * reach * 0.5)
		var pulse := clampf(sin(clock * 1.6 + offset * 3.0) * 1.4 - 0.2, 0.0, 1.0)
		if pulse <= 0.0:
			continue
		draw_circle(centre + drift, 7.0, Color(EYE, 0.12 * pulse))
		draw_circle(centre + drift, 2.0, Color(EYE.lightened(0.3), 0.9 * pulse))


func _draw_garden() -> void:
	_box(0, 0, 150, 56, 0, 24, WOOD)
	for h: float in [8.0, 16.0]:
		draw_line(_p(-74, 0, h), _p(74, 0, h), _front(WOOD).darkened(0.3), 1.3, true)
	draw_colored_polygon(PackedVector2Array([_p(-69, 5, 24), _p(69, 5, 24), _p(69, 51, 24), _p(-69, 51, 24)]), _flat(SOIL))
	# Two rows, back row first so the front row overlaps it.
	for row: float in [40.0, 16.0]:
		for column in 7:
			var x := -60.0 + float(column) * 20.0 + (6.0 if row > 20.0 else 0.0)
			if x > 66.0:
				continue
			var at := _p(x, row, 24)
			var bend := wind * 2.5 + _sway(2.0, 1.2, x * 0.07) + _knock(11.0, x * 0.2) * 5.0
			if (column + int(row)) % 3 == 0:
				_catnip(at, bend)
			else:
				_lettuce(at, bend)
	_fireflies(_p(0, 28, 60), 70.0, 2)
	# A little marker stake with a paw on it.
	_post(_p(62, 50, 20), _p(62, 50, 46), 2.6, WOOD_DARK)
	var plate := Rect2(_p(62, 50, 50) + Vector2(-10, -7), Vector2(20, 13))
	draw_rect(plate, _flat(CREAM))
	draw_rect(plate, INK, false, 1.4)
	draw_circle(plate.get_center() + Vector2(0, 1.5), 2.4, _front(WOOD))
	for toe: Vector2 in [Vector2(-3, -2), Vector2(0, -3.5), Vector2(3, -2)]:
		draw_circle(plate.get_center() + toe, 1.1, _front(WOOD))


func _lettuce(at: Vector2, bend: float) -> void:
	for leaf in 5:
		var angle := -PI * 0.5 + (float(leaf) - 2.0) * 0.55
		var tip := at + Vector2(cos(angle) * 9.0 + bend * 0.5, sin(angle) * 8.0 - 4.0)
		draw_circle(tip, 5.4, INK)
	for leaf in 5:
		var angle := -PI * 0.5 + (float(leaf) - 2.0) * 0.55
		var tip := at + Vector2(cos(angle) * 9.0 + bend * 0.5, sin(angle) * 8.0 - 4.0)
		draw_circle(tip, 4.2, _g(LEAF.lightened(0.12), 0.1))
	draw_circle(at + Vector2(0, -6), 3.6, _g(LEAF.lightened(0.3), 0.2))


func _catnip(at: Vector2, bend: float) -> void:
	for stem in 3:
		var tip := at + Vector2((float(stem) - 1.0) * 6.0 + bend, -18.0 - float(stem % 2) * 5.0)
		draw_line(at, tip, INK, 3.0, true)
		draw_line(at, tip, _g(LEAF_DARK.lightened(0.1)), 1.6, true)
		draw_circle(tip, 2.4, _g(LAVENDER, 0.2))
		draw_circle(at.lerp(tip, 0.55) + Vector2(3, 0), 2.6, _g(LEAF, 0.1))
		draw_circle(at.lerp(tip, 0.4) + Vector2(-3, 0), 2.6, _g(LEAF, 0.1))


func _draw_pots() -> void:
	# Back to front: the middle pot is the furthest back.
	_pot(10, 14, 12, 22)
	_flowers(_p(10, 14, 22))
	_pot(-26, 4, 16, 30)
	_snake_plant(_p(-26, 4, 30))
	_pot(32, -4, 10, 18)
	_cactus(_p(32, -4, 18))


func _pot(x: float, d: float, radius: float, height: float) -> void:
	_cylinder(x, d, radius, 0, height, TERRA, _flat(SOIL))
	var rim := _p(x, d, height)
	draw_polyline(_ellipse(rim, radius + 1.0, radius * DEPTH + 0.5, 0.0, PI, 10), _top(TERRA), 3.0, true)


func _snake_plant(at: Vector2) -> void:
	var leaves := [[-8.0, 44.0], [-3.0, 56.0], [3.0, 50.0], [8.0, 38.0], [0.0, 30.0]]
	for leaf in leaves:
		var x := float(leaf[0])
		var height := float(leaf[1])
		var tip := at + Vector2(x * 1.4 + wind * 2.0 * height / 50.0, -height)
		var blade := PackedVector2Array([at + Vector2(x - 3.5, 0), at + Vector2(x + 3.5, 0), tip])
		draw_colored_polygon(blade, _g(LEAF_DARK.lightened(0.05), 0.08))
		draw_polyline(PackedVector2Array([at + Vector2(x - 3.5, 0), tip, at + Vector2(x + 3.5, 0)]),
			_g(Color("c9c46a"), 0.1), 1.2, true)


func _flowers(at: Vector2) -> void:
	var heads := [Vector2(-6, -22), Vector2(4, -27), Vector2(9, -17)]
	for index in heads.size():
		var head: Vector2 = at + heads[index] + Vector2(wind * 1.5 + _sway(2.6, 0.8, float(index)) + _knock(12.0, float(index)) * 3.0, 0)
		draw_line(at, head, _g(LEAF_DARK), 1.6, true)
		for petal in 5:
			var angle := float(petal) * TAU / 5.0 + phase
			draw_circle(head + Vector2.from_angle(angle) * 3.4, 2.7, _g(PINK if index != 1 else CREAM, 0.15))
		draw_circle(head, 1.8, _g(Color("f2c46d")))


func _cactus(at: Vector2) -> void:
	var body := Rect2(at + Vector2(-6, -26), Vector2(12, 26))
	var green := _g(Color("5f9a70"), 0.1)
	draw_rect(body.grow(1.6), INK)
	draw_circle(body.position + Vector2(6, 0), 7.6, INK)
	draw_rect(body, green)
	draw_circle(body.position + Vector2(6, 0), 6.0, green)
	draw_line(at + Vector2(6, -12), at + Vector2(11, -12), INK, 5.5, true)
	draw_line(at + Vector2(11, -12), at + Vector2(11, -20), INK, 5.5, true)
	draw_line(at + Vector2(6, -12), at + Vector2(11, -12), green, 3.6, true)
	draw_line(at + Vector2(11, -12), at + Vector2(11, -20), green, 3.6, true)
	for dot in 5:
		draw_circle(at + Vector2(-2.0 + float(dot % 2) * 4.0, -5.0 - float(dot) * 4.0), 0.8, Color(1, 1, 1, 0.55))
	draw_circle(body.position + Vector2(6, -5), 2.6, _g(PINK, 0.2))


# --- Furniture -----------------------------------------------------------------

func _draw_parasol() -> void:
	var cushion: Color = [PINK, TEAL, Color("f2c46d")][variant % 3]
	for x: float in [-44.0, 44.0]:
		_cylinder(x, 20, 11, 0, 24, WOOD, _g(cushion, 0.25))
	_post(_p(0, 20, 0), _p(0, 20, 42), 4.0, METAL_DARK)
	_cylinder(0, 20, 30, 40, 44, WOOD)
	# Supper for two: a plate with a fish on it and a cup.
	draw_colored_polygon(_ellipse(_p(-8, 22, 44), 10.0, 7.0), _flat(CREAM))
	_fish(_p(-8, 22, 44), 7.0, _front(WOOD), 0.0, 1.8)
	_cylinder(12, 16, 4.5, 44, 52, CREAM)
	_post(_p(0, 20, 44), _p(0, 20, 132), 3.0, CREAM)
	var centre := _p(0, 20, 110)
	var apex := _p(0, 20, 134)
	var rx := 60.0
	var ry := 60.0 * DEPTH * 0.8
	# Canvas under a night sky, not bleached linen: the pale stripe is kept a
	# step below white so the canopy does not become the brightest thing on
	# screen and compete with the drops.
	var stripes: Array = [[CANVAS, TEAL], [CANVAS, PINK], [Color("d9a94e"), CANVAS]][variant % 3]
	var segments := 8
	# Far segments first, then the near ones over them, so the apex sits on the
	# fabric rather than being overdrawn by the back of the canopy.
	var order: Array[int] = []
	for index in segments:
		order.append(index)
	order.sort_custom(func(a, b): return sin((float(a) + 0.5) * TAU / segments) < sin((float(b) + 0.5) * TAU / segments))
	for index in order:
		var a0 := float(index) * TAU / float(segments)
		var a1 := float(index + 1) * TAU / float(segments)
		var middle := (a0 + a1) * 0.5
		var cloth: Color = stripes[index % 2]
		# Lit toward the moon (up and left), shaded toward the viewer's right.
		var lit := clampf(0.12 - cos(middle) * 0.1 - sin(middle) * 0.12, 0.0, 0.24)
		var fill := _g(cloth, lit).darkened(clampf(0.08 + sin(middle) * 0.2 + cos(middle) * 0.1, 0.0, 0.36))
		var points := PackedVector2Array([apex])
		for step in 5:
			var angle := lerpf(a0, a1, float(step) / 4.0)
			var scallop := 1.0 - 0.05 * sin(PI * float(step) / 4.0)
			points.append(centre + Vector2(cos(angle) * rx, sin(angle) * ry) * scallop)
		draw_colored_polygon(points, fill)
	var rim := _ellipse(centre, rx, ry, 0.0, TAU, 32)
	_outline(rim, 2.2)
	for index in segments:
		var angle := float(index) * TAU / float(segments)
		draw_line(apex, centre + Vector2(cos(angle) * rx, sin(angle) * ry), Color(INK, 0.35), 1.0, true)
	draw_circle(apex + Vector2(0, -2), 3.4, _top(CREAM))


func _draw_bench() -> void:
	for x: float in [-50.0, 50.0]:
		_post(_p(x, 38, 0), _p(x, 38, 62), 4.0, WOOD_DARK)
	_box(0, 36, 116, 5, 42, 49, WOOD)
	_box(0, 36, 116, 5, 53, 60, WOOD)
	for x: float in [-50.0, 50.0]:
		_post(_p(x, 8, 0), _p(x, 8, 26), 4.0, WOOD_DARK)
	_box(0, 8, 120, 30, 26, 32, WOOD)
	for slat in 3:
		var d := 14.0 + float(slat) * 8.0
		draw_line(_p(-58, d, 32), _p(58, d, 32), _front(WOOD).darkened(0.2), 1.2, true)
	# A folded blanket someone left for whoever naps here.
	var fold: Color = [LAVENDER, TEAL, PINK][variant % 3]
	_box(30, 14, 30, 16, 32, 37, fold)


func _draw_cat_house() -> void:
	_box(0, 0, 66, 54, 0, 40, CARD)
	# A pitched roof whose ridge runs back into the roof: left slope lit, right
	# slope in shade, and the gable facing the viewer.
	var left := PackedVector2Array([_p(-36, 0, 40), _p(0, 0, 66), _p(0, 56, 66), _p(-36, 56, 40)])
	var right := PackedVector2Array([_p(0, 0, 66), _p(36, 0, 40), _p(36, 56, 40), _p(0, 56, 66)])
	draw_colored_polygon(left, _g(Color("c9956a"), 0.35))
	draw_colored_polygon(right, _front(Color("a97a52")))
	var gable := PackedVector2Array([_p(-36, 0, 40), _p(36, 0, 40), _p(0, 0, 66)])
	draw_colored_polygon(gable, _front(CARD).lightened(0.05))
	_outline(PackedVector2Array([_p(-36, 0, 40), _p(-36, 56, 40), _p(0, 56, 66), _p(36, 56, 40), _p(36, 0, 40), _p(0, 0, 66)]))
	draw_line(_p(-36, 0, 40), _p(0, 0, 66), _rim(CARD), 1.6, true)
	# The door, and — on some houses — somebody at home.
	var door := _ellipse(_p(0, 0, 16), 12.0, 12.0, PI, TAU, 10)
	door.append(_p(12, 0, 2))
	door.append(_p(-12, 0, 2))
	draw_colored_polygon(door, Color("16110d"))
	_outline(door, 1.6)
	draw_colored_polygon(_ellipse(_p(0, 0, 3), 11.0, 3.0, PI, TAU, 8), _g(PINK, 0.1))
	# Somebody knocked on the house: whoever lives in it ducks out of sight.
	if variant % 2 == 0 and jolt < 0.08:
		var cycle := fmod(clock * 0.21 + phase, 1.0)
		var closed := cycle < 0.035 or (cycle > 0.07 and cycle < 0.1)
		var look := sin(clock * 0.5 + phase) * 2.0
		for side: float in [-1.0, 1.0]:
			var eye := _p(side * 5.0 + look, 0, 12)
			if closed:
				draw_line(eye + Vector2(-2.4, 0), eye + Vector2(2.4, 0), EYE, 1.4, true)
			else:
				draw_circle(eye, 3.6, Color(EYE, 0.22))
				draw_circle(eye, 2.4, EYE)
				draw_line(eye + Vector2(0, -1.8), eye + Vector2(0, 1.8), Color("1b2410"), 1.0, true)
	var heart := _p(0, 0, 52)
	draw_circle(heart + Vector2(-2.2, 0), 2.6, _g(PINK, 0.2))
	draw_circle(heart + Vector2(2.2, 0), 2.6, _g(PINK, 0.2))
	draw_colored_polygon(PackedVector2Array([heart + Vector2(-4.6, 0.8), heart + Vector2(4.6, 0.8), heart + Vector2(0, 5.5)]),
		_g(PINK, 0.2))


func _draw_fish_rack() -> void:
	for x: float in [-62.0, 62.0]:
		_post(_p(x - 10.0, 0, 0), _p(x, 0, 30), 3.0, WOOD_DARK)
		_post(_p(x + 10.0, 0, 0), _p(x, 0, 30), 3.0, WOOD_DARK)
		_post(_p(x, 0, 0), _p(x, 0, 92), 4.5, WOOD_DARK)
	_post(_p(-70, 0, 88), _p(70, 0, 88), 4.0, WOOD)
	for index in 4:
		var x := -40.0 + float(index) * 26.0
		var anchor := _p(x, 0, 88)
		var swing := wind * 0.12 + _sway(2.0, 0.09, x * 0.1) + _knock(8.0, x * 0.1) * 0.45
		draw_set_transform(anchor, swing)
		draw_line(Vector2.ZERO, Vector2(0, 7), Color(_flat(CREAM), 0.8), 1.0, true)
		var body := _ellipse(Vector2(0, 21), 6.0, 13.0, 0.0, TAU, 14)
		var silver := _g(Color("c2bda6"), 0.2)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 8), Vector2(-6, 3), Vector2(6, 3)]), silver.darkened(0.15))
		draw_colored_polygon(body, silver)
		draw_colored_polygon(_ellipse(Vector2(1.8, 21), 3.0, 11.0, -PI * 0.5, PI * 0.5, 8), silver.darkened(0.2))
		_outline(body, 1.4)
		for stripe in 3:
			draw_line(Vector2(-4, 15 + stripe * 5), Vector2(4, 16 + stripe * 5), silver.darkened(0.3), 1.0, true)
		draw_circle(Vector2(-1.5, 29), 1.3, INK)
		draw_set_transform(Vector2.ZERO)


# --- Machinery -----------------------------------------------------------------

func _draw_chimney() -> void:
	_box(0, 0, 44, 40, 0, 118, BRICK)
	var mortar := Color(_front(BRICK).darkened(0.35), 0.9)
	for course in 10:
		var h := 11.0 + float(course) * 11.0
		draw_line(_p(-22, 0, h), _p(22, 0, h), mortar, 1.2, true)
		var shift := 7.0 if course % 2 == 0 else 0.0
		for joint in 3:
			var x := -15.0 + shift + float(joint) * 14.0
			if x < 21.0:
				draw_line(_p(x, 0, h - 11.0), _p(x, 0, h), mortar, 1.0, true)
	_box(0, -3, 52, 46, 118, 126, Color("707674"))
	draw_colored_polygon(PackedVector2Array([_p(-12, 10, 126), _p(12, 10, 126), _p(12, 30, 126), _p(-12, 30, 126)]), Color("15181a"))
	# Smoke: puffs born at the flue, drifting with the shared wind and fading
	# out as they spread. Faint on purpose — it is weather, not an effect.
	for puff in 5:
		var life := fmod(clock * 0.3 + float(puff) * 0.2 + phase, 1.0)
		var rise := _p(0, 20, 132) + Vector2((wind * 38.0 + 16.0 + jolt * jolt_side * 40.0) * life + sin(life * 6.0 + float(puff)) * 4.0, -78.0 * life)
		var alpha := 0.2 * (1.0 - life) * smoothstep(0.0, 0.12, life)
		draw_circle(rise, 7.0 + 16.0 * life, Color(0.74, 0.8, 0.88, alpha))


func _draw_ac_unit() -> void:
	for x: float in [-34.0, 34.0]:
		draw_rect(Rect2(_p(x - 5, 2, 4), Vector2(10, 4)), _front(METAL_DARK))
	_box(0, 0, 84, 42, 4, 56, Color("a6b0ad"))
	var fan := _p(-14, 0, 30)
	draw_circle(fan, 20.0, INK)
	draw_circle(fan, 18.5, Color("20282b"))
	var spin := clock * 9.0 + phase
	for blade in 3:
		var angle := spin + float(blade) * TAU / 3.0
		var blade_shape := PackedVector2Array([fan,
			fan + Vector2(9, -6).rotated(angle), fan + Vector2(16, -1).rotated(angle), fan + Vector2(9, 5).rotated(angle)])
		draw_colored_polygon(blade_shape, _flat(METAL).darkened(0.1))
	draw_circle(fan, 3.4, _top(METAL))
	# The guard over the fan: rings and a cross, pale against the dark well.
	for ring: float in [7.0, 12.5, 18.0]:
		draw_arc(fan, ring, 0.0, TAU, 24, Color(_flat(METAL), 0.55), 1.0, true)
	draw_line(fan + Vector2(-18, 0), fan + Vector2(18, 0), Color(_flat(METAL), 0.55), 1.0)
	draw_line(fan + Vector2(0, -18), fan + Vector2(0, 18), Color(_flat(METAL), 0.55), 1.0)
	for vent in 7:
		var h := 14.0 + float(vent) * 5.0
		draw_line(_p(14, 0, h), _p(36, 0, h), _front(Color("a6b0ad")).darkened(0.25), 1.6)
	var pipe := PackedVector2Array([_p(42, 16, 22), _p(50, 16, 22), _p(54, 16, 16), _p(54, 16, 2)])
	draw_polyline(pipe, INK, 7.5, true)
	draw_polyline(pipe, _flat(CREAM), 5.0, true)


func _draw_turbine() -> void:
	_cylinder(0, 0, 12, 0, 30, METAL)
	_cylinder(0, 0, 15, 28, 32, METAL_DARK)
	var head := _p(0, 0, 52)
	var radius := 22.0
	draw_circle(head, radius + 2.2, INK)
	draw_circle(head, radius, _front(METAL))
	var turn := clock * 3.2 + phase
	for rib in 10:
		var longitude := float(rib) * TAU / 10.0 + turn
		if cos(longitude) < -0.1:
			continue
		var across := sin(longitude)
		var points := PackedVector2Array()
		for step in 9:
			var latitude := -PI * 0.5 + PI * float(step) / 8.0
			points.append(head + Vector2(radius * cos(latitude) * across, radius * sin(latitude) * 0.96))
		var light := clampf(0.5 - across * 0.4, 0.0, 0.9)
		draw_polyline(points, _g(METAL, light * 0.5).darkened(0.1 + (1.0 - cos(longitude)) * 0.2), 2.0, true)
	if Moonlight.enabled:
		draw_arc(head, radius - 2.0, PI * 1.05, PI * 1.6, 10, Moonlight.rim(METAL, 0.55), 2.0, true)
	draw_colored_polygon(_ellipse(head + Vector2(0, -radius + 2.0), 7.0, 3.0), _top(METAL_DARK))
	draw_circle(head + Vector2(0, -radius - 1.0), 2.6, _top(METAL))


func _draw_boxes() -> void:
	_box(0, 0, 66, 50, 0, 42, CARD)
	draw_colored_polygon(PackedVector2Array([_p(-5, 0, 42), _p(5, 0, 42), _p(5, 0, 30), _p(-5, 0, 30)]), _flat(Color("d8c4a0")))
	_fish(_p(-16, 0, 17), 10.0, _front(CARD).darkened(0.35), 0.0, 1.8)
	for arrow in 2:
		var at := _p(16 + float(arrow) * 9.0, 0, 18)
		draw_line(at + Vector2(0, 6), at + Vector2(0, -5), _front(CARD).darkened(0.35), 1.6, true)
		draw_polyline(PackedVector2Array([at + Vector2(-3, -2), at + Vector2(0, -5), at + Vector2(3, -2)]),
			_front(CARD).darkened(0.35), 1.6, true)
	var shift := 5.0 if variant % 2 == 0 else -5.0
	var upper := CARD.lightened(0.06)
	_box(shift, 6, 54, 40, 42, 74, upper)
	if variant % 3 == 0:
		# Opened: flaps folded out and a ball of yarn inside, which is the only
		# reason anyone on this roof opens a box.
		draw_colored_polygon(PackedVector2Array([_p(shift - 23, 10, 74), _p(shift + 23, 10, 74), _p(shift + 23, 42, 74), _p(shift - 23, 42, 74)]), Color("2b2119"))
		draw_colored_polygon(PackedVector2Array([_p(shift - 27, 6, 74), _p(shift - 27, 46, 74), _p(shift - 40, 40, 80), _p(shift - 40, 12, 80)]), _top(upper))
		draw_colored_polygon(PackedVector2Array([_p(shift + 27, 6, 74), _p(shift + 27, 46, 74), _p(shift + 40, 40, 80), _p(shift + 40, 12, 80)]), _front(upper))
		var yarn := _p(shift + 4, 24, 80)
		draw_circle(yarn, 9.5, INK)
		draw_circle(yarn, 8.0, _g(Color("d4596b"), 0.15))
		for strand in 3:
			draw_arc(yarn + Vector2(float(strand) * 2.5 - 2.5, 0), 6.0, -1.8, 1.8, 10, _g(Color("f08a98"), 0.2), 1.1, true)
	else:
		draw_colored_polygon(PackedVector2Array([_p(shift - 4, 6, 74), _p(shift + 4, 6, 74), _p(shift + 4, 46, 74), _p(shift - 4, 46, 74)]), _flat(Color("d8c4a0")))


func _draw_milk_crate() -> void:
	_box(0, 0, 58, 42, 0, 30, BLUE)
	for column in 3:
		for row in 2:
			var cell := Rect2(_p(-24 + float(column) * 17.0, 0, 26 - float(row) * 11.0), Vector2(13, 7))
			draw_rect(cell, Color("15283a"))
	var missing := variant % 6
	for row: float in [30.0, 12.0]:
		for column in 3:
			if int(row) % 7 + column == missing:
				continue
			# Bottles rattle in the crate when it is knocked.
			var x := -17.0 + float(column) * 17.0 + _knock(38.0, float(column) + row) * 1.6
			_cylinder(x, row, 6.0, 26, 42, Color("eef2f0"))
			_cylinder(x, row, 3.6, 42, 48, Color("eef2f0"))
			_cylinder(x, row, 3.8, 48, 51, Color("4d8fd6"))


func _draw_solar() -> void:
	for x: float in [-46.0, 46.0]:
		_post(_p(x, 48, 0), _p(x, 48, 42), 3.0, METAL_DARK)
		_post(_p(x, 2, 0), _p(x, 2, 13), 3.0, METAL_DARK)
	var panel := PackedVector2Array([_p(-50, 0, 14), _p(50, 0, 14), _p(50, 50, 44), _p(-50, 50, 44)])
	draw_colored_polygon(panel, _g(Color("26446a"), 0.12))
	var grid := Color(_g(Color("5d86b5")), 0.7)
	for column in range(1, 4):
		var t := float(column) / 4.0
		draw_line(panel[0].lerp(panel[1], t), panel[3].lerp(panel[2], t), grid, 1.0, true)
	for row in range(1, 3):
		var t := float(row) / 3.0
		draw_line(panel[0].lerp(panel[3], t), panel[1].lerp(panel[2], t), grid, 1.0, true)
	# The moon, caught in the glass as one soft diagonal sheen.
	var sheen := PackedVector2Array([panel[0].lerp(panel[1], 0.15), panel[0].lerp(panel[1], 0.32),
		panel[3].lerp(panel[2], 0.52), panel[3].lerp(panel[2], 0.35)])
	draw_colored_polygon(sheen, Color(Moonlight.MOON, 0.16 if Moonlight.enabled else 0.08))
	draw_colored_polygon(PackedVector2Array([_p(-50, 0, 14), _p(50, 0, 14), _p(50, 0, 10), _p(-50, 0, 10)]), _front(METAL))
	_outline(PackedVector2Array([_p(-50, 0, 10), _p(50, 0, 10), _p(50, 50, 44), _p(-50, 50, 44)]))


## A skylight with the flat below still awake. The glass is emissive: a window
## lit from inside is the one warm surface a night roof really has.
func _draw_skylight() -> void:
	_box(0, 0, 110, 70, 0, 14, METAL_DARK)
	var glass := PackedVector2Array([_p(-50, 5, 14), _p(50, 5, 14), _p(50, 65, 14), _p(-50, 65, 14)])
	draw_colored_polygon(glass, Color("e8b778"))
	draw_colored_polygon(PackedVector2Array([_p(-50, 5, 14), _p(50, 5, 14), _p(50, 22, 14), _p(-50, 22, 14)]), Color("f4cf8e"))
	var frame := _flat(METAL_DARK)
	draw_line(_p(0, 5, 14), _p(0, 65, 14), frame, 3.0, true)
	draw_line(_p(-50, 35, 14), _p(50, 35, 14), frame, 3.0, true)
	for x: float in [-25.0, 25.0]:
		draw_line(_p(x, 5, 14), _p(x, 65, 14), Color(frame, 0.6), 1.4, true)
	# A potted plant silhouetted on the sill below, just visible through the glass.
	draw_circle(_p(-30, 50, 14), 7.0, Color("8a6a3e"))
	draw_circle(_p(-34, 52, 14), 5.0, Color("8a6a3e"))
	var sheen := PackedVector2Array([_p(12, 5, 14), _p(26, 5, 14), _p(4, 65, 14), _p(-10, 65, 14)])
	draw_colored_polygon(sheen, Color(1, 1, 1, 0.12))


func _draw_dish() -> void:
	draw_colored_polygon(_ellipse(_p(0, 10, 0), 12.0, 5.0), _front(METAL_DARK))
	_post(_p(0, 10, 0), _p(0, 10, 58), 4.0, METAL_DARK)
	var centre := _p(0, 10, 68)
	draw_set_transform(centre, -0.45)
	draw_colored_polygon(_ellipse(Vector2.ZERO, 28.0, 19.0), INK)
	draw_colored_polygon(_ellipse(Vector2.ZERO, 26.0, 17.0), _g(Color("d7dcd8"), 0.3))
	draw_colored_polygon(_ellipse(Vector2(2, 2), 19.0, 11.0), _g(Color("aab3b0")))
	if Moonlight.enabled:
		draw_arc(Vector2.ZERO, 24.0, PI * 1.05, PI * 1.6, 10, Moonlight.rim(Color("d7dcd8"), 0.6), 2.0, true)
	draw_line(Vector2(2, 2), Vector2(18, -18), INK, 3.0, true)
	draw_line(Vector2(2, 2), Vector2(18, -18), _flat(METAL), 1.6, true)
	draw_circle(Vector2(18, -18), 3.5, _top(METAL_DARK))
	draw_set_transform(Vector2.ZERO)
