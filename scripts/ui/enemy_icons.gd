extends RefCounted
const ATLAS := preload("res://assets/ui/icons/enemy_atlas.png")
const IDS := ["chaser", "swarm", "charger", "shooter", "chain_hunter", "bulwark", "brute", "planter"]
static var textures: Dictionary = {}

static func get_icon(id: String) -> Texture2D:
	if textures.is_empty():
		var pixels := ATLAS.get_image()
		# Generated silhouettes do not obey exact cell boundaries (crow wings
		# cross the nominal third cell). Explicit normalized cutouts avoid bleed.
		var regions := [Rect2(0.035, 0.10, 0.20, 0.38), Rect2(0.28, 0.19, 0.18, 0.27),
			Rect2(0.51, 0.10, 0.19, 0.39), Rect2(0.72, 0.10, 0.26, 0.40),
			Rect2(0.035, 0.55, 0.205, 0.38), Rect2(0.275, 0.53, 0.185, 0.40),
			Rect2(0.49, 0.53, 0.205, 0.40), Rect2(0.75, 0.53, 0.19, 0.40)]
		for index in IDS.size():
			var region: Rect2 = regions[index]
			var origin := Vector2i(region.position * Vector2(pixels.get_size()))
			var cell := Vector2i(region.size * Vector2(pixels.get_size()))
			var used := pixels.get_region(Rect2i(origin, cell)).get_used_rect()
			var texture := AtlasTexture.new()
			texture.atlas = ATLAS
			texture.region = Rect2(origin + used.position, used.size)
			texture.filter_clip = true
			textures[IDS[index]] = texture
	return textures.get(id, textures["chaser"])
