class_name ArenaFloor
extends Node2D

## The arena: a moonlit rooftop the two cats are chained across.
##
## Everything here is drawn once into a static world-space canvas and then only
## panned over, so the cost is a single _draw() for the whole run. It is built
## from three layers with deliberately different scales — wide roof panels, the
## tile grid, and small scattered props — because a single grid gives the eye
## nothing to measure movement against, and a chained pair mostly needs to judge
## how far they have actually travelled.
##
## Every colour here stays dark and low-contrast on purpose. The field has to
## stay the quietest thing on screen or the enemies stop reading against it.
##
## It lives on its own node at a deep negative z rather than on main, because
## main draws at z 0 and the chain that ties the pair together sits at -1: an
## opaque floor painted from main covered the one line the whole game is about.


func _ready() -> void:
	z_index = -20


func _draw() -> void:
	var extent := 2400
	var panel_size := 384
	# Layer 1: roof panels. Slabs large enough that crossing one is a
	# recognisable amount of ground.
	for x in range(-extent, extent, panel_size):
		for y in range(-extent, extent, panel_size):
			var checker := int(abs(x / panel_size + y / panel_size)) % 2
			var shade := 0.030 if checker == 0 else 0.046
			draw_rect(Rect2(x, y, panel_size, panel_size), Color(shade, shade * 1.35, shade * 2.3, 1.0))

	# Layer 2: the tile grid, brighter along panel seams so the two scales stay
	# distinguishable instead of blurring into one texture.
	var tile_color := Color(0.15, 0.22, 0.35, 0.16)
	var seam_color := Color(0.24, 0.36, 0.56, 0.30)
	for coordinate in range(-extent, extent + 1, 96):
		var seam := coordinate % panel_size == 0
		var line_color := seam_color if seam else tile_color
		var width := 2.0 if seam else 1.0
		draw_line(Vector2(coordinate, -extent), Vector2(coordinate, extent), line_color, width)
		draw_line(Vector2(-extent, coordinate), Vector2(extent, coordinate), line_color, width)

	# Layer 3: props. Placed from a fixed seed so the rooftop is the same
	# rooftop every run and the pair can actually learn it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260905
	for index in 90:
		var spot := Vector2(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent))
		match index % 3:
			0: # vent block
				var block := Vector2(rng.randf_range(46.0, 84.0), rng.randf_range(34.0, 58.0))
				draw_rect(Rect2(spot - block * 0.5, block), Color(0.07, 0.10, 0.17, 1.0))
				draw_rect(Rect2(spot - block * 0.5, Vector2(block.x, 5.0)), Color(0.13, 0.19, 0.30, 1.0))
			1: # skylight, catching the moon
				var pane := rng.randf_range(26.0, 44.0)
				draw_rect(Rect2(spot - Vector2(pane, pane) * 0.5, Vector2(pane, pane)), Color(0.10, 0.15, 0.26, 1.0))
				draw_rect(
					Rect2(spot - Vector2(pane, pane) * 0.42, Vector2(pane, pane) * 0.84),
					Color(0.16, 0.26, 0.42, 0.75)
				)
			_: # puddle
				draw_circle(spot, rng.randf_range(16.0, 34.0), Color(0.09, 0.16, 0.28, 0.7))

	# The moon, far off and fixed, so the arena has an up.
	draw_circle(Vector2(-1750.0, -1980.0), 210.0, Color(0.16, 0.20, 0.30, 0.55))
	draw_circle(Vector2(-1750.0, -1980.0), 178.0, Color(0.86, 0.90, 0.98, 0.42))
