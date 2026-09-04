class_name GameIconCatalog
extends RefCounted

## The three atlases are hand-made art with a fixed number of cells, so every id
## added after they were drawn — new survivors, evolved weapons, new treasures —
## would otherwise render as a blank card on screens that are now icon-led.
##
## Anything the atlases do not cover falls back to a generated glyph: a coloured
## disc with a shape derived from the id. It is deterministic (the same id always
## draws the same icon), cached, and visibly a placeholder rather than a pretend
## painting. Move an id into an atlas and the fallback stops being used for it.

const SURVIVOR_ATLAS: Texture2D = preload("res://assets/ui/icons/survivor_atlas.png")
const WEAPON_ATLAS: Texture2D = preload("res://assets/ui/icons/weapon_atlas.png")
const UPGRADE_ATLAS: Texture2D = preload("res://assets/ui/icons/upgrade_atlas.png")

const SURVIVOR_ORDER := ["lyra", "volta", "ignis", "neve", "moro", "serin"]
const WEAPON_ORDER := ["homing", "lightning", "flame", "frost", "scythe", "chain"]
const UPGRADE_ORDER := [
	"might", "area", "amount", "haste",
	"projectile_speed", "armor", "recovery", "magnet",
	"growth", "luck", "move", "vitality",
]

const WEAPON_PASSTHROUGH := ["unlock_weapon", "weapon_power", "weapon_rate", "special_a", "special_b", "evolve_weapon"]

const GLYPH_SIZE := 96
const GLYPH_SHAPES := 8

## Generated glyphs are built once per id and reused. Without this every card
## refresh on the level-up screen would rasterise several 96x96 images.
static var _generated: Dictionary = {}


static func survivor(character_id: String) -> Texture2D:
	var atlas_icon := _by_id(SURVIVOR_ATLAS, SURVIVOR_ORDER, character_id, 3, 2)
	return atlas_icon if atlas_icon != null else generated(character_id, "survivor")


static func weapon(weapon_id: String) -> Texture2D:
	var atlas_icon := _by_id(WEAPON_ATLAS, WEAPON_ORDER, weapon_id, 3, 2)
	if atlas_icon != null:
		return atlas_icon
	# An evolved weapon borrows its base form's glyph family so the tech tree
	# reads as one line rather than two unrelated icons.
	return generated(weapon_id, "weapon")


static func upgrade(upgrade_id: String, weapon_id := "") -> Texture2D:
	if upgrade_id in WEAPON_PASSTHROUGH:
		return weapon(weapon_id)
	var atlas_icon := _by_id(UPGRADE_ATLAS, UPGRADE_ORDER, upgrade_id, 4, 3)
	return atlas_icon if atlas_icon != null else generated(upgrade_id, "upgrade")


## Whether this id is covered by real art. Used by the icon test to report what
## still needs drawing rather than to fail the build over it.
static func has_atlas_art(id: String, kind: String) -> bool:
	match kind:
		"survivor":
			return SURVIVOR_ORDER.has(id)
		"weapon":
			return WEAPON_ORDER.has(id)
		_:
			return UPGRADE_ORDER.has(id)


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
	var cell := Vector2(float(atlas.get_width()) / float(columns), float(atlas.get_height()) / float(rows))
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(Vector2(index % columns, index / columns) * cell, cell)
	texture.filter_clip = true
	return texture
