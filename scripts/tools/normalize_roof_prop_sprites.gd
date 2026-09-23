extends SceneTree

## One-shot normalizer for the ImageGen rooftop prop pass.
##
## ImageGen returned a neutral checker/paper field instead of alpha.  The field
## is deliberately achromatic and bright, while every prop has a dark navy
## silhouette, so a conservative neutral-key removes the canvas without
## touching the painted object.  We keep a cropped high-resolution archive and
## write a small runtime sprite whose visible bounds match RoofLayout's cover
## dimensions.  Four transparent pixels below the object preserve the shared
## "middle of the near edge" origin used by RoofDecor.

const SOURCE_DIR := "res://art/originals/environment/props/"
const RUNTIME_DIR := "res://assets/environment/props/"
const ARCHIVE_MARGIN := 24
const RUNTIME_MARGIN := 4
## Texels per game unit in the runtime sprites. The battlefield is shown at
## about 1.5 screen pixels per unit on a 1080p window, so sprites authored at
## one texel per unit were being magnified and went soft. Two gives headroom;
## the mip chain covers zooming out. Every size and rectangle below is in game
## units and multiplied by this when pixels are written.
const TEXELS := 2
const ATLAS_SIZE := Vector2i(1024, 512) * TEXELS
## Broad antialiased glass on the low skylight falls below the atlas test's
## opaque-foot threshold. Seat that one sprite three units lower without
## changing the authored silhouette or any shared origin math.
const GROUND_NUDGE := {'skylight': 3}

## Stable shelf packing used by RoofDecor. Individual PNGs remain available;
## the game samples these rectangles from one texture to keep batching cheap.
const ATLAS_RECTS := {
	'water_tower': Rect2i(0, 0, 116, 222),
	'laundry': Rect2i(118, 0, 224, 128),
	'lights': Rect2i(344, 0, 268, 118),
	'antenna': Rect2i(614, 0, 80, 204),
	'tree_pot': Rect2i(696, 0, 112, 212),
	'parasol': Rect2i(810, 0, 128, 186),
	'chimney': Rect2i(0, 224, 62, 170),
	'ac_unit': Rect2i(64, 224, 100, 100),
	'boxes': Rect2i(166, 224, 88, 126),
	'milk_crate': Rect2i(256, 224, 66, 84),
	'garden': Rect2i(324, 224, 158, 104),
	'bench': Rect2i(484, 224, 128, 104),
	'turbine': Rect2i(614, 224, 56, 88),
	'cat_house': Rect2i(672, 224, 80, 120),
	'fish_rack': Rect2i(754, 224, 148, 102),
	'pots': Rect2i(0, 396, 96, 98),
	'solar': Rect2i(98, 396, 112, 96),
	'skylight': Rect2i(212, 396, 118, 82),
	'dish': Rect2i(332, 396, 76, 104),
}

## Maximum visible bounds in runtime pixels, taken from RoofLayout.KINDS.  A
## couple of silhouettes extend a few pixels past their cover rectangle (feet,
## braces, or an open box flap), so those widths include that intentional lip.
const TARGETS := {
	"water_tower": Vector2i(108, 214),
	"laundry": Vector2i(216, 120),
	"lights": Vector2i(260, 110),
	"antenna": Vector2i(72, 196),
	"tree_pot": Vector2i(104, 204),
	"parasol": Vector2i(120, 178),
	"chimney": Vector2i(54, 162),
	"ac_unit": Vector2i(92, 92),
	"boxes": Vector2i(80, 118),
	"milk_crate": Vector2i(58, 76),
	"garden": Vector2i(150, 96),
	"bench": Vector2i(120, 96),
	"turbine": Vector2i(48, 80),
	"cat_house": Vector2i(72, 112),
	"fish_rack": Vector2i(140, 94),
	"pots": Vector2i(88, 90),
	"solar": Vector2i(104, 88),
	"skylight": Vector2i(110, 74),
	"dish": Vector2i(68, 96),
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME_DIR))
	for prop_name: String in TARGETS:
		if not _normalize(prop_name, TARGETS[prop_name] * TEXELS):
			quit(1)
			return
	print("ROOF_PROP_NORMALIZE_OK %d sprites" % TARGETS.size())
	if not _build_atlas():
		quit(1)
		return
	quit()


func _normalize(prop_name: String, target: Vector2i) -> bool:
	var raw_path := SOURCE_DIR + prop_name + "_raw.png"
	var image := Image.load_from_file(raw_path)
	if image == null or image.is_empty():
		push_error("Cannot load %s" % raw_path)
		return false
	image.convert(Image.FORMAT_RGBA8)
	# Current ImageGen outputs already carry real alpha. Keep their pale painted
	# highlights intact; only key the canvas on legacy opaque checker/paper files.
	if not _has_transparent_edge(image):
		_remove_generated_canvas(image)
	var visible := _visible_rect(image)
	if visible.size.x <= 0 or visible.size.y <= 0:
		push_error("No visible pixels remain in %s" % raw_path)
		return false

	var archive_rect := visible.grow(ARCHIVE_MARGIN).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var archive := image.get_region(archive_rect)
	var archive_path := SOURCE_DIR + prop_name + ".png"
	if archive.save_png(archive_path) != OK:
		push_error("Cannot save %s" % archive_path)
		return false

	var sprite := image.get_region(visible)
	var fit := minf(float(target.x) / sprite.get_width(), float(target.y) / sprite.get_height())
	var scaled := Vector2i(
		maxi(1, roundi(sprite.get_width() * fit)),
		maxi(1, roundi(sprite.get_height() * fit))
	)
	sprite.resize(scaled.x, scaled.y, Image.INTERPOLATE_LANCZOS)
	var canvas_size := target + Vector2i.ONE * RUNTIME_MARGIN * TEXELS * 2
	var canvas := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var at := Vector2i((canvas_size.x - scaled.x) / 2, canvas_size.y - RUNTIME_MARGIN * TEXELS - scaled.y)
	at.y += int(GROUND_NUDGE.get(prop_name, 0)) * TEXELS
	canvas.blit_rect(sprite, Rect2i(Vector2i.ZERO, scaled), at)
	var runtime_path := RUNTIME_DIR + prop_name + ".png"
	if canvas.save_png(runtime_path) != OK:
		push_error("Cannot save %s" % runtime_path)
		return false
	print("ROOF_PROP %s archive=%dx%d runtime=%dx%d visible=%dx%d" % [
		prop_name, archive.get_width(), archive.get_height(), canvas_size.x, canvas_size.y,
		scaled.x, scaled.y,
	])
	return true


func _has_transparent_edge(image: Image) -> bool:
	var last := image.get_size() - Vector2i.ONE
	for point: Vector2i in [Vector2i.ZERO, Vector2i(last.x, 0), last, Vector2i(0, last.y)]:
		if image.get_pixelv(point).a < 0.1:
			return true
	return false


func _build_atlas() -> bool:
	var atlas := Image.create(ATLAS_SIZE.x, ATLAS_SIZE.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for prop_name: String in ATLAS_RECTS:
		var unit: Rect2i = ATLAS_RECTS[prop_name]
		var region := Rect2i(unit.position * TEXELS, unit.size * TEXELS)
		var sprite := Image.load_from_file(RUNTIME_DIR + prop_name + '.png')
		if sprite == null or sprite.is_empty():
			return false
		if sprite.get_size() != region.size:
			return false
		sprite.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(sprite, Rect2i(Vector2i.ZERO, region.size), region.position)
	var path := 'res://assets/environment/roof_props_atlas.png'
	if atlas.save_png(path) != OK:
		return false
	return true


## Remove only the bright, nearly neutral canvas.  Generated prop highlights
## are blue or warm and retain enough channel separation to stay opaque.  A
## narrow transition band feathers the antialiased edge without producing a
## pale checker halo after downscaling.
func _remove_generated_canvas(image: Image) -> void:
	_remove_connected_canvas(image)
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var high := maxf(color.r, maxf(color.g, color.b))
			var low := minf(color.r, minf(color.g, color.b))
			var chroma := high - low
			if low > 0.72 and chroma < 0.038:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif low > 0.82 and chroma < 0.09:
				var keep := clampf((chroma - 0.038) / 0.052, 0.0, 1.0)
				color.a = keep
				image.set_pixel(x, y, color)


## Paper wrinkles can be darker than the global neutral key.  Starting at the
## canvas edge removes that connected paper safely: every real sprite has a
## dark blue outline that stops the flood before it reaches painted surfaces.
func _remove_connected_canvas(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var seen := PackedByteArray()
	seen.resize(width * height)
	var pending := PackedInt32Array()
	for x in width:
		_seed_canvas(image, x, 0, seen, pending)
		_seed_canvas(image, x, height - 1, seen, pending)
	for y in height:
		_seed_canvas(image, 0, y, seen, pending)
		_seed_canvas(image, width - 1, y, seen, pending)
	var head := 0
	while head < pending.size():
		var index := pending[head]
		head += 1
		var x := index % width
		var y := index / width
		image.set_pixel(x, y, Color.TRANSPARENT)
		if x > 0:
			_seed_canvas(image, x - 1, y, seen, pending)
		if x + 1 < width:
			_seed_canvas(image, x + 1, y, seen, pending)
		if y > 0:
			_seed_canvas(image, x, y - 1, seen, pending)
		if y + 1 < height:
			_seed_canvas(image, x, y + 1, seen, pending)


func _seed_canvas(image: Image, x: int, y: int, seen: PackedByteArray, pending: PackedInt32Array) -> void:
	var index := y * image.get_width() + x
	if seen[index] != 0:
		return
	seen[index] = 1
	var color := image.get_pixel(x, y)
	var high := maxf(color.r, maxf(color.g, color.b))
	var low := minf(color.r, minf(color.g, color.b))
	if low > 0.46 and high - low < 0.12:
		pending.append(index)


func _visible_rect(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.02:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
