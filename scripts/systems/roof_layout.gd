class_name RoofLayout
extends RefCounted
## What stands where on the endless roof, as a pure function of world position.
##
## The roof used to be scattered with single props — one crate here, one vent
## there — chosen per cell with no relation to each other. That reads as noise
## rather than as a place, and the pieces were small and dim enough that the
## roof looked empty anyway. This file places *vignettes* instead: a laundry
## line with its basket, a parasol café with pots beside it, a knot of air
## conditioners and a turbine vent tied together by conduit on the floor. Each
## one is a small story somebody who lives in the building left behind, and the
## difference between a cluster and a scatter is what makes the eye read "a
## roof people use" instead of "random boxes".
##
## Two consumers read the same answer and must never disagree: ArenaFloor paints
## the floor half of every piece (its shadow, the puddle under a water tower,
## the conduit leaving an air conditioner) into the background canvas, and
## RooftopPropField stands the upright half up as sortable nodes. Both call
## `cell()`, which is deterministic and cached, so the shadow is always under
## the thing that casts it.
##
## Nothing placed here blocks movement or drops anything. The breakable supply
## planter is still WaveDirector's, placed on its own grid.

## One layout cell. Large enough that a vignette plus clear floor around it fits
## inside, small enough that a screen still holds three or four of them.
const CELL := 640
## A vignette's centre stays this far inside its cell. Offsets inside a
## vignette reach about 200 either way, so two neighbouring vignettes are always
## separated by walkable roof rather than merging into one wall.
const CLUSTER_MARGIN := 240.0
const CLUSTER_CHANCE := 0.72
## Random vignettes keep out of the opening. The home layout below owns it, and
## the first movement lesson needs the terrace clear.
const HOME_KEEP_OUT := Rect2(-900.0, -660.0, 1800.0, 1320.0)
## The painted terrace under the food bowls. No random floor clutter on it.
const TERRACE := Rect2(-260.0, -190.0, 520.0, 380.0)
## How far a shadow may reach from the piece that casts it, so the floor knows
## how far outside its window it still has to look.
const SHADOW_REACH := 260.0
## Shadow length per pixel of height. The moon is high as well as off to the
## side, so a shadow is well short of the height that throws it.
const SHADOW_K := 0.42
## The roof's drainage channels, which ArenaFloor paints. Owned here because the
## layout has to keep furniture off them: a crate standing astride a gutter reads
## as dropped there by a generator rather than put there by somebody.
const GUTTER_SPACING := 768.0
const GUTTER_OFFSET := GUTTER_SPACING * 0.5
const GUTTER_CLEAR := 12.0
## How far a vignette may slide sideways to get its feet off a gutter. Past this
## it would crowd its neighbour, so the cell is left empty instead.
const GUTTER_SHIFT := 120.0
## A floor-standing round thing (a pot, a stool) is listed as a low blob; above
## this height a blob is held up off the floor and has no footprint.
const BLOB_ON_FLOOR := 30.0
## Upright pixels to world rows. A piece's drawing is corrected to stand upright,
## which stretches it vertically by the inverse of the battlefield's tilt.
const UPRIGHT_STRETCH := 1.0 / 0.86

## Per kind: whether it is tall enough to swallow a cat standing behind it (the
## condition for the see-through silhouette), whether it moves, its local cover
## rectangle (upright pixels, origin at the middle of the near edge of the
## footprint, y up is negative), its shadow primitives, and the warm light it
## throws on the floor, if any.
##
## Shadow primitives, all in the piece's own ground frame (x across, d back into
## the roof, h up):
##   ["box",  x, d, width, depth, height]   a solid; the hull of its footprint
##                                           and that footprint slid along the light
##   ["pole", x, d, height, thickness]       a post: a strip from its foot
##   ["blob", x, d, height, radius]          something round held up off the floor
const KINDS := {
	"water_tower": {"tall": true, "animated": false, "cover": Rect2(-54, -214, 108, 128),
		"shadow": [["pole", -42, 0, 84, 7], ["pole", 42, 0, 84, 7], ["pole", -42, 76, 84, 7],
			["pole", 42, 76, 84, 7], ["blob", 0, 38, 140, 54]]},
	"laundry": {"tall": true, "animated": true, "cover": Rect2(-104, -120, 208, 64),
		"shadow": [["pole", -108, 0, 118, 5], ["pole", 108, 0, 118, 5], ["blob", -50, 0, 96, 22],
			["blob", 10, 0, 92, 20], ["blob", 60, 0, 96, 16]]},
	"lights": {"tall": false, "animated": true, "cover": Rect2(-130, -110, 260, 30),
		"shadow": [["pole", -130, 0, 106, 5], ["pole", 130, 0, 106, 5]],
		"glow": [[0, 0, 180]]},
	"antenna": {"tall": false, "animated": true, "cover": Rect2(-36, -196, 72, 60),
		"shadow": [["pole", 0, 10, 180, 4]]},
	"tree_pot": {"tall": true, "animated": true, "cover": Rect2(-52, -204, 104, 100),
		"shadow": [["box", 0, 0, 64, 50, 38], ["pole", 0, 25, 96, 7], ["blob", 0, 25, 130, 46]]},
	"parasol": {"tall": true, "animated": false, "cover": Rect2(-60, -178, 120, 84),
		"shadow": [["pole", 0, 20, 128, 4], ["blob", 0, 20, 118, 56], ["blob", -44, 20, 24, 12],
			["blob", 44, 20, 24, 12]]},
	"chimney": {"tall": true, "animated": true, "cover": Rect2(-27, -162, 54, 162),
		"shadow": [["box", 0, 0, 44, 40, 124]]},
	"ac_unit": {"tall": false, "animated": true, "cover": Rect2(-42, -92, 84, 92),
		"shadow": [["box", 0, 0, 84, 42, 56]]},
	"boxes": {"tall": true, "animated": false, "cover": Rect2(-33, -118, 66, 118),
		"shadow": [["box", 0, 0, 66, 50, 42], ["box", 4, 6, 54, 40, 76]]},
	"milk_crate": {"tall": false, "animated": false, "cover": Rect2(-29, -76, 58, 76),
		"shadow": [["box", 0, 0, 58, 42, 40]]},
	"garden": {"tall": false, "animated": true, "cover": Rect2(-75, -96, 150, 96),
		"shadow": [["box", 0, 0, 150, 56, 30]]},
	"bench": {"tall": false, "animated": false, "cover": Rect2(-60, -96, 120, 96),
		"shadow": [["box", 0, 8, 120, 30, 32], ["box", 0, 36, 120, 6, 62]]},
	"turbine": {"tall": false, "animated": true, "cover": Rect2(-24, -80, 48, 80),
		"shadow": [["pole", 0, 0, 30, 24], ["blob", 0, 0, 52, 22]]},
	"cat_house": {"tall": true, "animated": true, "cover": Rect2(-33, -112, 66, 112),
		"shadow": [["box", 0, 0, 66, 54, 52]]},
	"fish_rack": {"tall": false, "animated": true, "cover": Rect2(-66, -94, 132, 46),
		"shadow": [["pole", -62, 0, 92, 5], ["pole", 62, 0, 92, 5], ["blob", 0, 0, 70, 40]]},
	"pots": {"tall": false, "animated": true, "cover": Rect2(-44, -90, 88, 90),
		"shadow": [["blob", -26, 4, 20, 17], ["blob", 10, 14, 16, 13], ["blob", 32, -4, 14, 11]]},
	"solar": {"tall": false, "animated": false, "cover": Rect2(-52, -88, 104, 88),
		"shadow": [["box", 0, 0, 100, 50, 30]]},
	"skylight": {"tall": false, "animated": false, "cover": Rect2(-55, -74, 110, 74),
		"shadow": [["box", 0, 0, 110, 70, 14]], "glow": [[0, 35, 110]]},
	"dish": {"tall": false, "animated": false, "cover": Rect2(-34, -96, 68, 60),
		"shadow": [["pole", 0, 10, 58, 5], ["blob", 0, 10, 66, 24]]},
}

## Pieces standing on the roof, as [kind, offset from the vignette's centre].
## Decals lying on it, as [kind, offset, size]. `weight` is how common the
## vignette is; the landmarks (water tower, chimney, antenna) are rarer so they
## stay landmarks.
const VIGNETTES := [
	{"weight": 1.1, "pieces": [["laundry", Vector2(0, 0)], ["milk_crate", Vector2(150, 26)]],
		"decals": [["puddle", Vector2(-40, 60), 34.0], ["leaves", Vector2(90, -40), 60.0]]},
	{"weight": 1.0, "pieces": [["parasol", Vector2(0, 0)], ["pots", Vector2(-128, 34)]],
		"decals": [["chalk", Vector2(20, 90), 40.0], ["leaves", Vector2(-120, -40), 50.0]]},
	{"weight": 1.1, "pieces": [["garden", Vector2(-30, 10)], ["tree_pot", Vector2(120, -40)], ["pots", Vector2(-150, -36)]],
		"decals": [["leaves", Vector2(130, 20), 70.0], ["moss", Vector2(-60, 70), 46.0]]},
	{"weight": 1.0, "pieces": [["ac_unit", Vector2(-70, 0)], ["ac_unit", Vector2(40, 10)], ["turbine", Vector2(150, -50)]],
		"decals": [["conduit", Vector2(-20, 44), 230.0], ["stain", Vector2(-60, 40), 28.0]]},
	{"weight": 0.6, "pieces": [["water_tower", Vector2(0, 0)]],
		"decals": [["puddle", Vector2(24, 36), 52.0], ["moss", Vector2(-50, 50), 40.0]]},
	{"weight": 0.9, "pieces": [["lights", Vector2(0, 0)], ["bench", Vector2(0, -60)]],
		"decals": [["chalk", Vector2(-60, 70), 44.0], ["leaves", Vector2(110, 40), 44.0]]},
	{"weight": 1.0, "pieces": [["boxes", Vector2(-50, 0)], ["milk_crate", Vector2(40, 22)], ["cat_house", Vector2(140, -30)]],
		"decals": [["stain", Vector2(0, 50), 24.0], ["paws", Vector2(150, 50), 90.0]]},
	{"weight": 0.9, "pieces": [["fish_rack", Vector2(0, 0)], ["milk_crate", Vector2(-120, 24)]],
		"decals": [["fishbone", Vector2(40, 50), 20.0], ["puddle", Vector2(-40, 58), 28.0]]},
	{"weight": 0.7, "pieces": [["antenna", Vector2(0, -20)], ["solar", Vector2(120, 30)], ["dish", Vector2(-110, 16)]],
		"decals": [["conduit", Vector2(0, 60), 180.0], ["drain", Vector2(-60, 70), 16.0]]},
	{"weight": 0.7, "pieces": [["chimney", Vector2(0, 0)], ["boxes", Vector2(90, 40)]],
		"decals": [["stain", Vector2(10, 40), 40.0], ["crack", Vector2(-80, 50), 70.0]]},
	{"weight": 0.8, "pieces": [["skylight", Vector2(0, 0)], ["pots", Vector2(118, -10)]],
		"decals": [["moss", Vector2(-80, 40), 36.0]]},
	{"weight": 0.8, "pieces": [["cat_house", Vector2(0, 0)], ["pots", Vector2(-90, 24)]],
		"decals": [["paws", Vector2(60, 60), 100.0], ["fishbone", Vector2(-40, 60), 18.0]]},
]

## The opening. Placed by hand so the first screen already says where the pair
## is — a lived-in roof around the feeding terrace — while leaving the middle
## open for the first movement lesson. The string lights hang behind the bowls
## on purpose: warm light over the snacks is the image the game is named for.
## Placed against the opening frame, which shows about 600 either side and from
## -330 (under the HUD) to +290 (above the experience strip) down the roof.
const HOME_PIECES := [
	["lights", Vector2(0, -262)],
	["water_tower", Vector2(-470, -40)],
	["laundry", Vector2(440, -200)],
	["garden", Vector2(285, 250)],
	["tree_pot", Vector2(470, 240)],
	["parasol", Vector2(-400, 250)],
	["pots", Vector2(-555, 230)],
	["ac_unit", Vector2(600, -60)],
	["cat_house", Vector2(-430, -290)],
]
const HOME_DECALS := [
	["puddle", Vector2(-440, 10), 44.0],
	["leaves", Vector2(470, 300), 70.0],
	["chalk", Vector2(-230, 250), 40.0],
	["moss", Vector2(330, -170), 40.0],
	["conduit", Vector2(660, -10), 160.0],
	["crack", Vector2(140, 200), 80.0],
	["paws", Vector2(-300, -250), 90.0],
]

## Loose floor detail, independent of the vignettes, so the paving between them
## is not bare either. Weights, not percentages.
const SCATTER := {
	"puddle": 1.6, "moss": 2.0, "leaves": 1.8, "crack": 1.8, "chalk": 0.45,
	"drain": 0.8, "stain": 0.9, "fishbone": 0.35,
}

static var _cache: Dictionary = {}


static func cell_of(at: Vector2) -> Vector2i:
	return Vector2i(int(floor(at.x / CELL)), int(floor(at.y / CELL)))


static func spec(kind: String) -> Dictionary:
	return KINDS.get(kind, {})


## Every piece and decal whose anchor lies in this cell. Pure: the same cell
## always answers the same, which is what lets the floor and the prop field
## build their halves independently and still meet.
static func cell(key: Vector2i) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	# The cache only has to cover what is on and around the screen. Clearing it
	# outright rather than evicting one entry keeps this a few lines, and a
	# rebuild is a handful of random draws per cell.
	if _cache.size() > 600:
		_cache.clear()
	var built := _build(key)
	_cache[key] = built
	return built


static func _build(key: Vector2i) -> Dictionary:
	var pieces: Array = []
	var decals: Array = []
	var origin := Vector2(key) * float(CELL)
	var bounds := Rect2(origin, Vector2.ONE * CELL)
	for index in HOME_PIECES.size():
		var home: Array = HOME_PIECES[index]
		if bounds.has_point(home[1]):
			pieces.append(_piece(String(home[0]), home[1], 7000 + index * 131, "home:%d" % index))
	for home in HOME_DECALS:
		if bounds.has_point(home[1]):
			decals.append(_decal(String(home[0]), home[1], float(home[2]), hash(home[1])))

	var rng := RandomNumberGenerator.new()
	rng.seed = absi((key.x * 73856093) ^ (key.y * 19349663)) + 20260922
	var centre := origin + Vector2(
		rng.randf_range(CLUSTER_MARGIN, CELL - CLUSTER_MARGIN),
		rng.randf_range(CLUSTER_MARGIN, CELL - CLUSTER_MARGIN))
	var wants_cluster := rng.randf() < CLUSTER_CHANCE
	var pick := _weighted_vignette(rng.randf())
	# Mirroring the arrangement, not the drawings: a mirrored drawing would put
	# the moon on the wrong side of every rim light.
	var mirror := -1.0 if rng.randf() < 0.5 else 1.0
	if wants_cluster and not HOME_KEEP_OUT.has_point(centre):
		var vignette: Dictionary = VIGNETTES[pick]
		var shift := _gutter_shift(vignette, centre, mirror)
		# A vignette that cannot get its feet off a gutter is left out; the
		# cell still gets its loose floor detail below.
		if not is_nan(shift):
			centre.x += shift
			var serial := 0
			for entry in vignette["pieces"]:
				var offset: Vector2 = entry[1]
				var at: Vector2 = centre + Vector2(offset.x * mirror, offset.y)
				pieces.append(_piece(String(entry[0]), at, rng.randi(), "%d:%d:%d" % [key.x, key.y, serial]))
				serial += 1
			for entry in vignette["decals"]:
				var offset: Vector2 = entry[1]
				decals.append(_decal(String(entry[0]), centre + Vector2(offset.x * mirror, offset.y),
					float(entry[2]), rng.randi()))

	var loose := rng.randi_range(2, 4)
	for index in loose:
		var at := origin + Vector2(rng.randf() * CELL, rng.randf() * CELL)
		var kind := _weighted_scatter(rng.randf())
		var size := rng.randf_range(0.7, 1.3)
		var variant := rng.randi()
		if TERRACE.grow(40.0).has_point(at):
			continue
		decals.append(_decal(kind, at, _scatter_size(kind) * size, variant))
	# Back to front, so where two shadows meet the nearer one is painted last.
	pieces.sort_custom(func(a, b): return (a["at"] as Vector2).y < (b["at"] as Vector2).y)
	return {"pieces": pieces, "decals": decals}


static func _piece(kind: String, at: Vector2, variant: int, id: String) -> Dictionary:
	var piece := {"kind": kind, "at": at, "variant": absi(variant), "id": id}
	piece["keep"] = _keep_out(piece)
	return piece


## The smallest sideways slide that takes every foot of a vignette off the
## gutters, trying the nearest first. NAN when none within GUTTER_SHIFT works.
static func _gutter_shift(vignette: Dictionary, centre: Vector2, mirror: float) -> float:
	var feet: Array[Rect2] = []
	for entry in vignette["pieces"]:
		var offset: Vector2 = entry[1]
		var probe := {"kind": String(entry[0]), "at": centre + Vector2(offset.x * mirror, offset.y)}
		feet.append_array(footprints(probe))
	var step := 0.0
	while step <= GUTTER_SHIFT:
		for shift: float in ([step] if step == 0.0 else [step, -step]):
			var clear := true
			for foot in feet:
				if _on_gutter(foot.position.x + shift, foot.end.x + shift):
					clear = false
					break
			if clear:
				return shift
		step += 20.0
	return NAN


## True when some gutter centre lies within GUTTER_CLEAR of [left, right].
static func _on_gutter(left: float, right: float) -> bool:
	var lowest := ceilf((left - GUTTER_CLEAR - GUTTER_OFFSET) / GUTTER_SPACING)
	var highest := floorf((right + GUTTER_CLEAR - GUTTER_OFFSET) / GUTTER_SPACING)
	return lowest <= highest


## Where a piece actually touches the roof, as world rectangles: the base of every
## solid, the foot of every post, and every round thing standing on the floor.
## Derived from the shadow primitives, so a new kind needs no second list.
static func footprints(piece: Dictionary) -> Array[Rect2]:
	var feet: Array[Rect2] = []
	var ground: Vector2 = piece["at"]
	for primitive in spec(String(piece["kind"])).get("shadow", []):
		var foot := ground + Vector2(float(primitive[1]), -float(primitive[2]))
		match String(primitive[0]):
			"box":
				var width := float(primitive[3])
				var depth := float(primitive[4])
				feet.append(Rect2(foot.x - width * 0.5, foot.y - depth, width, depth))
			"pole":
				var half := maxf(3.0, float(primitive[4]) * 0.5)
				feet.append(Rect2(foot.x - half, foot.y - half, half * 2.0, half * 2.0))
			"blob":
				if float(primitive[3]) <= BLOB_ON_FLOOR:
					var radius := float(primitive[4])
					feet.append(Rect2(foot.x - radius, foot.y - radius * 0.6, radius * 2.0, radius * 1.2))
	return feet


## Everything a piece covers on the floor or on screen, in world coordinates:
## its feet, plus the area its upright drawing stands over. A drop anywhere in
## here is either inside a crate or hidden behind a water tank.
static func _keep_out(piece: Dictionary) -> Rect2:
	var ground: Vector2 = piece["at"]
	var cover: Rect2 = spec(String(piece["kind"])).get("cover", Rect2())
	var area := Rect2(ground + Vector2(cover.position.x, cover.position.y * UPRIGHT_STRETCH),
		Vector2(cover.size.x, cover.size.y * UPRIGHT_STRETCH))
	for foot in footprints(piece):
		area = area.merge(foot)
	return area


## How close a point stands to one of the roof's warm lights, 0 to 1. Pieces
## near the string lights or a lit skylight take a little of that warmth on
## their lit edges, so the lamps light the things around them and not only the
## floor.
static func warmth_at(at: Vector2) -> float:
	var warmest := 0.0
	for piece in pieces_in(Rect2(at - Vector2(420.0, 420.0), Vector2(840.0, 840.0))):
		for pool in spec(String(piece["kind"])).get("glow", []):
			var centre: Vector2 = piece["at"] + Vector2(float(pool[0]), -float(pool[1]))
			var reach := float(pool[2]) * 1.6
			warmest = maxf(warmest, clampf(1.0 - at.distance_to(centre) / reach, 0.0, 1.0))
	return warmest


## A point moved just far enough that nothing on the roof stands on it or in
## front of it: out through the nearest side of whatever keep-out area holds it.
## Drops, gems and supply planters go through this, so nothing a player wants
## ever spawns inside a crate or behind the laundry.
static func clear_spot(at: Vector2, margin := 16.0) -> Vector2:
	var areas: Array[Rect2] = []
	for piece in pieces_in(Rect2(at - Vector2(480.0, 480.0), Vector2(960.0, 960.0))):
		areas.append((piece["keep"] as Rect2).grow(margin))
	if _open(at, areas):
		return at
	# Straight out through a side of whatever holds the point, nearest first.
	# The pieces of one vignette stand close, so an exit is only taken if it is
	# clear of every area and not merely of the one it leaves.
	var best := at
	var best_distance := INF
	for area in areas:
		if not area.has_point(at):
			continue
		for exit: Vector2 in [Vector2(area.position.x - 1.0, at.y), Vector2(area.end.x + 1.0, at.y),
				Vector2(at.x, area.position.y - 1.0), Vector2(at.x, area.end.y + 1.0)]:
			var distance := exit.distance_squared_to(at)
			if distance < best_distance and _open(exit, areas):
				best = exit
				best_distance = distance
	if best_distance < INF:
		return best
	# Boxed in by overlapping areas: the nearest open roof on widening rings.
	for ring in range(1, 16):
		for step in 16:
			var probe := at + Vector2.from_angle(TAU * float(step) / 16.0) * 20.0 * float(ring)
			if _open(probe, areas):
				return probe
	return at


static func _open(point: Vector2, areas: Array[Rect2]) -> bool:
	for area in areas:
		if area.has_point(point):
			return false
	return true


static func _decal(kind: String, at: Vector2, size: float, variant: int) -> Dictionary:
	return {"kind": kind, "at": at, "size": size, "variant": absi(variant)}


static func _weighted_vignette(roll: float) -> int:
	var total := 0.0
	for vignette in VIGNETTES:
		total += float(vignette["weight"])
	var mark := roll * total
	for index in VIGNETTES.size():
		mark -= float(VIGNETTES[index]["weight"])
		if mark <= 0.0:
			return index
	return VIGNETTES.size() - 1


static func _weighted_scatter(roll: float) -> String:
	var total := 0.0
	for weight in SCATTER.values():
		total += float(weight)
	var mark := roll * total
	for kind in SCATTER.keys():
		mark -= float(SCATTER[kind])
		if mark <= 0.0:
			return String(kind)
	return "crack"


static func _scatter_size(kind: String) -> float:
	match kind:
		"puddle":
			return 34.0
		"moss":
			return 34.0
		"leaves":
			return 48.0
		"crack":
			return 64.0
		"chalk":
			return 38.0
		"drain":
			return 15.0
		"stain":
			return 26.0
		_:
			return 18.0


## Every piece whose anchor is inside `rect`, over however many cells that is.
static func pieces_in(rect: Rect2) -> Array:
	var found: Array = []
	var first := cell_of(rect.position)
	var last := cell_of(rect.end)
	for cell_y in range(first.y, last.y + 1):
		for cell_x in range(first.x, last.x + 1):
			for piece in cell(Vector2i(cell_x, cell_y))["pieces"]:
				if rect.has_point(piece["at"]):
					found.append(piece)
	return found


static func decals_in(rect: Rect2) -> Array:
	var found: Array = []
	var first := cell_of(rect.position)
	var last := cell_of(rect.end)
	for cell_y in range(first.y, last.y + 1):
		for cell_x in range(first.x, last.x + 1):
			for decal in cell(Vector2i(cell_x, cell_y))["decals"]:
				if rect.has_point(decal["at"]):
					found.append(decal)
	return found


## The shadow a piece throws, as floor polygons relative to the piece's ground
## point. Worked out from the kind's primitives, so a new kind gets a correct
## shadow by listing what it is made of rather than by drawing one.
##
## Relative rather than world coordinates on purpose: the roof is endless, and
## a hundred thousand units out the triangulator no longer has the precision to
## fill a small polygon given in absolute terms.
static func shadow_polygons(piece: Dictionary) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	var ground := Vector2.ZERO
	var info := spec(String(piece["kind"]))
	for primitive in info.get("shadow", []):
		var kind := String(primitive[0])
		var foot := ground + Vector2(float(primitive[1]), -float(primitive[2]))
		match kind:
			"box":
				var half := float(primitive[3]) * 0.5
				var depth := float(primitive[4])
				var drop := Moonlight.SHADOW_DIRECTION * float(primitive[5]) * SHADOW_K
				var corners := PackedVector2Array([
					foot + Vector2(-half, -depth), foot + Vector2(half, -depth),
					foot + Vector2(half, 0.0), foot + Vector2(-half, 0.0),
				])
				var all := PackedVector2Array(corners)
				for corner in corners:
					all.append(corner + drop)
				# convex_hull closes its ring by repeating the first point, and the
				# triangulator rejects a coincident pair once coordinates are large
				# (a long way down the endless roof), so the repeat is dropped.
				var hull := Geometry2D.convex_hull(all)
				if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
					hull.remove_at(hull.size() - 1)
				polygons.append(hull)
			"pole":
				var drop := Moonlight.SHADOW_DIRECTION * float(primitive[3]) * SHADOW_K
				var side := drop.orthogonal().normalized() * float(primitive[4]) * 0.5
				polygons.append(PackedVector2Array([foot - side, foot + side, foot + drop + side, foot + drop - side]))
			"blob":
				var centre := foot + Moonlight.SHADOW_DIRECTION * float(primitive[3]) * SHADOW_K
				var radius := float(primitive[4])
				var ring := PackedVector2Array()
				for step in 14:
					var angle := TAU * float(step) / 14.0
					ring.append(centre + Vector2(cos(angle) * radius, sin(angle) * radius * 0.62))
				polygons.append(ring)
	return polygons
