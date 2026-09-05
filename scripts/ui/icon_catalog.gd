class_name GameIconCatalog
extends RefCounted

## Cat-themed cartoon atlases cover the complete current roster, base/evolved
## weapons and treasures. Unknown future ids retain a deterministic fallback.

const SURVIVOR_ATLAS: Texture2D = preload("res://assets/ui/icons/survivor_atlas.png")
const WEAPON_ATLAS: Texture2D = preload("res://assets/ui/icons/weapon_atlas.png")
const UPGRADE_ATLAS: Texture2D = preload("res://assets/ui/icons/upgrade_atlas.png")

const SURVIVOR_ORDER := ["lyra", "volta", "ignis", "neve", "moro", "serin", "kael", "rian", "tera", "nova"]
const WEAPON_ORDER := [
	"homing", "lightning", "flame", "frost", "scythe",
	"chain", "orbit", "lance", "mine", "gravity",
	"starpiercer", "thunder_god", "supernova", "absolute_zero", "black_moon",
	"stigmata", "celestial", "judgement", "ruin_garden", "event_horizon",
]
const UPGRADE_ORDER := [
	"might", "area", "amount", "haste",
	"projectile_speed", "armor", "recovery", "magnet",
	"growth", "luck", "move", "vitality",
	"crit", "pierce", "thorns", "resolve", "overcharge", "greed",
]

const WEAPON_PASSTHROUGH := ["unlock_weapon", "weapon_power", "weapon_rate", "special_a", "special_b", "evolve_weapon"]
const UPGRADE_ALIASES := {
	"catnip": "recovery", "bounty_bell": "growth", "twin_charm": "overcharge",
	"dash_claw": "might", "lucky_paw": "luck", "nine_lives": "vitality",
}

const GLYPH_SIZE := 96
const GLYPH_SHAPES := 8

## Generated glyphs are built once per id and reused. Without this every card
## refresh on the level-up screen would rasterise several 96x96 images.
static var _generated: Dictionary = {}
static var _atlas_icons: Dictionary = {}


static func survivor(character_id: String) -> Texture2D:
	if character_id in ["mikan", "suzu"]: return load("res://assets/ui/icons/%s.svg" % character_id)
	var atlas_icon := _by_id(SURVIVOR_ATLAS, SURVIVOR_ORDER, character_id, 5, 2)
	return atlas_icon if atlas_icon != null else generated(character_id, "survivor")


static func weapon(weapon_id: String) -> Texture2D:
	if weapon_id in ["boomerang", "bell"]: return load("res://assets/ui/icons/%s.svg" % weapon_id)
	var atlas_icon := _by_id(WEAPON_ATLAS, WEAPON_ORDER, weapon_id, 5, 4)
	if atlas_icon != null:
		return atlas_icon
	return generated(weapon_id, "weapon")


static func upgrade(upgrade_id: String, weapon_id := "") -> Texture2D:
	if upgrade_id in WEAPON_PASSTHROUGH:
		return weapon(weapon_id)
	var atlas_id := String(UPGRADE_ALIASES.get(upgrade_id, upgrade_id))
	var atlas_icon := _by_id(UPGRADE_ATLAS, UPGRADE_ORDER, atlas_id, 6, 3)
	return atlas_icon if atlas_icon != null else generated(upgrade_id, "upgrade")


## Whether this id is covered by real art. Used by the icon test to report what
## still needs drawing rather than to fail the build over it.
static func has_atlas_art(id: String, kind: String) -> bool:
	if id in ["mikan", "suzu", "boomerang", "bell"]: return true
	match kind:
		"survivor":
			return SURVIVOR_ORDER.has(id)
		"weapon":
			return WEAPON_ORDER.has(id)
		_:
			return UPGRADE_ORDER.has(id) or UPGRADE_ALIASES.has(id)


## The mark the level-up screen puts beside a card that feeds a fusion.
##
## The screen used to spell the whole tech tree out along the bottom — "화염
## 성운 T1/7 + 확장의 렌즈 T0/4 → 초신성" — which is a spreadsheet, and it told
## a first-time pair the answer to something they were supposed to discover.
## The mark says only "this card is on a fusion path", and the bright version
## says "taking this opens one now". What it opens is still not named.
##
## Two chevrons closing on a diamond: converging, then a thing made.
static func fusion_seal(ready: bool) -> Texture2D:
	var key := "seal:%s" % ("ready" if ready else "step")
	if _generated.has(key):
		return _generated[key] as Texture2D
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(size * 0.5, size * 0.5)
	# Drawn onto a cream card, so both inks are darker than the palette colours
	# they stand for: a pale gold seal on a pale card is a smudge.
	var ink := Color("c8871b") if ready else Color("647c86")
	var glow := Color(ink, 0.30 if ready else 0.16)
	for y in size:
		for x in size:
			var offset := Vector2(float(x) + 0.5, float(y) + 0.5) - centre
			var distance := offset.length()
			if distance > 30.0:
				continue
			# Outer ring.
			if distance >= 25.0:
				image.set_pixel(x, y, Color(ink, 0.85 if ready else 0.5))
				continue
			if distance >= 22.0:
				image.set_pixel(x, y, glow)
				continue
			# Diamond core.
			if absf(offset.x) + absf(offset.y) <= 8.0:
				image.set_pixel(x, y, Color(ink.lightened(0.35) if ready else ink, 1.0))
				continue
			# Two chevrons pointing inward from left and right.
			var toward := absf(absf(offset.x) - 15.0) + absf(absf(offset.y) - absf(offset.x) + 15.0)
			if absf(offset.x) >= 9.0 and absf(offset.x) <= 20.0 and absf(offset.y) <= 13.0:
				if absf(absf(offset.y) - (20.0 - absf(offset.x))) <= 2.2:
					image.set_pixel(x, y, Color(ink, 0.95 if ready else 0.6))
					continue
			if distance <= 19.0 and toward < 0.0:
				image.set_pixel(x, y, glow)
	var texture := ImageTexture.create_from_image(image)
	_generated[key] = texture
	return texture


static func generated(id: String, kind: String) -> Texture2D:
	var key := kind + ":" + id
	if _generated.has(key):
		return _generated[key] as Texture2D
	var texture := _draw_glyph(id, kind)
	_generated[key] = texture
	return texture


## A stable non-negative hash of the id, so the same weapon keeps the same
## placeholder across runs and across machines.
static func _id_hash(id: String) -> int:
	var value := 2166136261
	for index in id.length():
		value = (value ^ id.unicode_at(index)) * 16777619
		value = value & 0x7FFFFFFF
	return value


static func _draw_glyph(id: String, kind: String) -> Texture2D:
	var seed_value := _id_hash(id)
	var hue := float(seed_value % 360) / 360.0
	var shape := (seed_value / 360) % GLYPH_SHAPES
	# Each kind keeps its own saturation/value band so a treasure placeholder
	# never reads as a weapon placeholder at a glance.
	var saturation := 0.55
	var value := 0.95
	match kind:
		"survivor":
			saturation = 0.42
			value = 1.0
		"weapon":
			saturation = 0.70
			value = 0.95
		_:
			saturation = 0.55
			value = 0.80
	var accent := Color.from_hsv(hue, saturation, value)
	var deep := Color.from_hsv(hue, minf(1.0, saturation + 0.22), value * 0.32)

	var image := Image.create(GLYPH_SIZE, GLYPH_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(GLYPH_SIZE, GLYPH_SIZE) * 0.5
	var outer := float(GLYPH_SIZE) * 0.46
	for y in GLYPH_SIZE:
		for x in GLYPH_SIZE:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var offset := point - centre
			var distance := offset.length()
			if distance > outer:
				continue
			var pixel := deep
			if distance > outer - 5.0:
				pixel = accent
			elif _in_glyph(offset, outer, shape):
				pixel = accent.lightened(0.25)
			else:
				# A soft radial falloff so the disc does not read as flat.
				pixel = deep.lerp(deep.lightened(0.18), 1.0 - distance / outer)
			image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)


## The eight placeholder shapes. They only need to be distinguishable from each
## other at 38px, which is the smallest the build ribbon draws them.
static func _in_glyph(offset: Vector2, outer: float, shape: int) -> bool:
	var unit := offset / outer
	var distance := unit.length()
	var angle := unit.angle()
	match shape:
		0: # ring
			return distance > 0.38 and distance < 0.62
		1: # bar cross
			return absf(unit.x) < 0.18 or absf(unit.y) < 0.18
		2: # diamond
			return absf(unit.x) + absf(unit.y) < 0.62
		3: # three spokes
			return absf(sin(angle * 1.5)) < 0.26 and distance < 0.68
		4: # upward triangle
			return unit.y < 0.36 and unit.y > -0.62 and absf(unit.x) < (0.36 - unit.y) * 0.62
		5: # dotted orbit
			return distance > 0.42 and distance < 0.64 and absf(sin(angle * 4.0)) > 0.55
		6: # solid core
			return distance < 0.34
		7: # chevrons
			return absf(absf(unit.x) - absf(unit.y)) < 0.16 and distance < 0.7
	return false


static func _by_id(atlas: Texture2D, order: Array, id: String, columns: int, rows: int) -> Texture2D:
	var index := order.find(id)
	if index < 0:
		return null
	var cache_key := atlas.resource_path + ":" + id
	if _atlas_icons.has(cache_key):
		return _atlas_icons[cache_key] as Texture2D
	var cell := Vector2(float(atlas.get_width()) / float(columns), float(atlas.get_height()) / float(rows))
	# Permit small atlas-layout drift so ears/tips crossing a nominal cell edge
	# are recovered; the central-component crop rejects adjacent silhouettes.
	var bounds := Rect2(Vector2(index % columns, index / columns) * cell, cell)
	bounds = bounds.grow(minf(cell.x, cell.y) * 0.06).intersection(Rect2(Vector2.ZERO, atlas.get_size()))
	var texture := preload("res://scripts/ui/icon_crop.gd").region(atlas, bounds)
	_atlas_icons[cache_key] = texture
	return texture
