extends RefCounted
static var sources: Dictionary = {}
## Locate the central connected silhouette rather than trusting generated atlas
## cell margins. Filtering and a square margin prevent neighbouring art bleed.
static func region(atlas: Texture2D, cell: Rect2) -> AtlasTexture:
	if not sources.has(atlas.resource_path): sources[atlas.resource_path] = atlas.get_image()
	var pixels: Image = sources[atlas.resource_path].get_region(Rect2i(cell))
	var original := pixels.get_size()
	pixels.resize(96, 96, Image.INTERPOLATE_NEAREST)
	var seen := PackedByteArray()
	seen.resize(96 * 96)
	var best := Rect2i(0, 0, 96, 96)
	var best_score := -1.0
	for y in 96:
		for x in 96:
			var offset := y * 96 + x
			if seen[offset] or pixels.get_pixel(x, y).a < 0.15: continue
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			seen[offset] = 1
			var lo := Vector2i(x, y)
			var hi := lo
			var cursor := 0
			while cursor < queue.size():
				var point := queue[cursor]
				cursor += 1
				lo = lo.min(point)
				hi = hi.max(point)
				for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = point + direction
					if next.x < 0 or next.y < 0 or next.x >= 96 or next.y >= 96: continue
					var at := next.y * 96 + next.x
					if seen[at] or pixels.get_pixelv(next).a < 0.15: continue
					seen[at] = 1
					queue.append(next)
			var centre := Vector2(lo + hi) * 0.5
			var score := float(queue.size()) / (1.0 + centre.distance_to(Vector2(48, 48)) * 0.02)
			if score > best_score:
				best_score = score
				best = Rect2i(lo, hi - lo + Vector2i.ONE)
	best = best.grow(2).intersection(Rect2i(0, 0, 96, 96))
	var scale := Vector2(original) / 96.0
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(cell.position + Vector2(best.position) * scale, Vector2(best.size) * scale)
	var extent := maxf(texture.region.size.x, texture.region.size.y) * 1.1
	texture.margin = Rect2((Vector2.ONE * extent - texture.region.size) * 0.5, Vector2.ONE * extent - texture.region.size)
	texture.filter_clip = true
	return texture
