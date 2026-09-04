class_name GameIconCatalog
extends RefCounted

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


static func survivor(character_id: String) -> Texture2D:
	return _by_id(SURVIVOR_ATLAS, SURVIVOR_ORDER, character_id, 3, 2)


static func weapon(weapon_id: String) -> Texture2D:
	return _by_id(WEAPON_ATLAS, WEAPON_ORDER, weapon_id, 3, 2)


static func upgrade(upgrade_id: String, weapon_id := "") -> Texture2D:
	if upgrade_id in ["unlock_weapon", "weapon_power", "weapon_rate", "special_a", "special_b"]:
		return weapon(weapon_id)
	return _by_id(UPGRADE_ATLAS, UPGRADE_ORDER, upgrade_id, 4, 3)


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
