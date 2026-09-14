extends SceneTree

## One-shot normalizer for generated title characters. Image generation is
## asked for alpha first; when it returns a chroma field, this removes only the
## strongly green pixels, decontaminates the anti-aliased edge, crops to the
## visible silhouette, and writes both archive and runtime-sized PNGs.

const JOBS := [
	{
		"source": "res://art/originals/ui/title_lyra_fullbody_v1_raw.png",
		"archive": "res://art/originals/ui/title_lyra_fullbody_v1.png",
		"runtime": "res://assets/ui/title_lyra_fullbody_v1.png",
	},
	{
		"source": "res://art/originals/ui/title_volta_fullbody_v1_raw.png",
		"archive": "res://art/originals/ui/title_volta_fullbody_v1.png",
		"runtime": "res://assets/ui/title_volta_fullbody_v1.png",
	},
]


func _init() -> void:
	for job: Dictionary in JOBS:
		var image := Image.load_from_file(String(job["source"]))
		if image == null or image.is_empty():
			push_error("Cannot load %s" % job["source"])
			quit(1)
			return
		_remove_green(image)
		image = _crop_visible(image, 32)
		var error := image.save_png(String(job["archive"]))
		if error != OK:
			push_error("Cannot save %s" % job["archive"])
			quit(1)
			return
		var runtime := image.duplicate()
		var target_height := 768
		var target_width := maxi(1, roundi(float(runtime.get_width()) * target_height / runtime.get_height()))
		runtime.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
		error = runtime.save_png(String(job["runtime"]))
		if error != OK:
			push_error("Cannot save %s" % job["runtime"])
			quit(1)
			return
		print("CHROMA_KEY_OK %s %dx%d" % [job["runtime"], target_width, target_height])
	var backdrop := Image.load_from_file("res://art/originals/ui/moonroof_backdrop_v4.png")
	if backdrop == null or backdrop.is_empty():
		push_error("Cannot load generated title backdrop")
		quit(1)
		return
	backdrop.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	if backdrop.save_png("res://assets/ui/moonroof_backdrop_v4.png") != OK:
		push_error("Cannot save runtime title backdrop")
		quit(1)
		return
	print("BACKDROP_OK res://assets/ui/moonroof_backdrop_v4.png 1280x720")
	quit()


func _remove_green(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var other := maxf(color.r, color.b)
			var spill := color.g - other
			if color.g < 0.52 or spill <= 0.055:
				continue
			var keep := clampf(1.0 - (spill - 0.055) / 0.30, 0.0, 1.0)
			if keep <= 0.02:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# Pull green spill down to the strongest neighbouring channel so the
				# alpha fringe stays navy/gray rather than neon green in Godot.
				color.g = minf(color.g, other)
				color.a = keep
				image.set_pixel(x, y, color)


func _crop_visible(image: Image, margin: int) -> Image:
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
		return image
	min_x = maxi(0, min_x - margin)
	min_y = maxi(0, min_y - margin)
	max_x = mini(image.get_width() - 1, max_x + margin)
	max_y = mini(image.get_height() - 1, max_y + margin)
	return image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
