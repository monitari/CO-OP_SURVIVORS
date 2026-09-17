class_name GameIconCatalog
extends RefCounted

## Every icon is its own file under assets/sprites/, named by the id that asks
## for it. Unknown future ids retain a deterministic generated fallback.
##
## These used to be three grid atlases sliced at load time — cell arithmetic,
## a 6% overscan for ears crossing a cell edge, and a connected-component crop
## to find the silhouette inside the cell, all so a filename could be avoided.
## The art it produced is now checked in directly, one PNG per id, so an icon is
## looked up rather than computed and a new one is added by dropping a file in.

## Which folder answers each kind of lookup.
const SPRITE_FOLDERS := {"survivor": "cats", "weapon": "weapons", "upgrade": "upgrades"}

const WEAPON_PASSTHROUGH := ["unlock_weapon", "choose_tech", "weapon_power", "weapon_rate", "special_a", "special_b"]
const UPGRADE_ALIASES := {
	"catnip": "recovery", "bounty_bell": "growth", "twin_charm": "overcharge",
	"dash_claw": "might", "lucky_paw": "luck", "nine_lives": "vitality",
	# Keep the checked-in bell art while the former curse treasure becomes the
	# crimson lifesteal bell. The gameplay/catalog id contains no curse semantics.
	"lifesteal": "curse",
}

const GLYPH_SIZE := 96
const GLYPH_SHAPES := 8

## Generated glyphs are built once per id and reused. Without this every card
## refresh on the level-up screen would rasterise several 96x96 images.
static var _generated: Dictionary = {}
## Misses are cached as null too, so an id with no art is not re-probed on
## every card refresh.
static var _sprites: Dictionary = {}


## The drawn art for one id, or null when no file answers to it.
static func _sprite(kind: String, id: String) -> Texture2D:
	var key := kind + ":" + id
	if _sprites.has(key):
		return _sprites[key] as Texture2D
	var path := "res://assets/sprites/%s/%s.png" % [String(SPRITE_FOLDERS[kind]), id]
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_sprites[key] = texture
	return texture


static func survivor(character_id: String) -> Texture2D:
	var art := _sprite("survivor", character_id)
	return art if art != null else generated(character_id, "survivor")


static func weapon(weapon_id: String) -> Texture2D:
	var art := _sprite("weapon", weapon_id)
	return art if art != null else generated(weapon_id, "weapon")


static func upgrade(upgrade_id: String, weapon_id := "") -> Texture2D:
	if upgrade_id in WEAPON_PASSTHROUGH:
		return weapon(weapon_id)
	var art := _sprite("upgrade", String(UPGRADE_ALIASES.get(upgrade_id, upgrade_id)))
	return art if art != null else generated(upgrade_id, "upgrade")


## Whether this id is covered by real art. Used by the icon test to report what
## still needs drawing rather than to fail the build over it. It now answers by
## looking for the file instead of consulting a hand-kept list, so the list and
## the folder cannot drift apart.
static func has_atlas_art(id: String, kind: String) -> bool:
	if kind == "survivor" or kind == "weapon":
		return _sprite(kind, id) != null
	return _sprite("upgrade", String(UPGRADE_ALIASES.get(id, id))) != null


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
	var shape := int(float(seed_value) / 360.0) % GLYPH_SHAPES
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
