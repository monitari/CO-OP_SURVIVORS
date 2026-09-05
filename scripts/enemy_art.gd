extends RefCounted
## Original, code-native top-down silhouettes. All noses face +X so existing
## steering transforms also communicate facing; no extra per-frame redraws.
const INK := Color("172530")
const NAMES := {
	"rat_runner": "지그재그 도둑쥐", "wasp": "옥상 말벌", "hedgehog": "가시 고슴도치", "mole": "돌진 두더지", "owl": "밤사냥 부엉이",
	"chaser": "간식 도둑 쥐", "swarm": "벼룩 떼", "charger": "성난 경비견",
	"shooter": "옥상 까마귀", "chain_hunter": "꼬리 도둑 너구리",
	"bulwark": "철통 너구리", "brute": "폭주 청소 로봇",
}


static func draw_body(canvas: Node2D, kind: String, radius: float, flash: float, enraged: bool) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * radius)
	canvas.draw_circle(Vector2(0, 0.15), 1.04, Color(0.02, 0.06, 0.07, 0.35))
	match kind:
		"charger":
			_dog(canvas, flash)
		"shooter":
			_crow(canvas, flash)
		"chain_hunter", "bulwark":
			_raccoon(canvas, flash, kind == "bulwark")
		"swarm":
			_flea(canvas, flash)
		"brute":
			_robot(canvas, flash, enraged)
		_:
			_mouse(canvas, flash)
	canvas.draw_set_transform(Vector2.ZERO)


static func _disc(c: Node2D, at: Vector2, r: float, tint: Color) -> void:
	c.draw_circle(at, r + 0.065, INK)
	c.draw_circle(at, r, tint)


static func _shape(c: Node2D, points: Array, tint: Color) -> void:
	var polygon := PackedVector2Array(points)
	c.draw_colored_polygon(polygon, tint)
	c.draw_polyline(polygon + PackedVector2Array([polygon[0]]), INK, 0.075, true)


static func _eyes(c: Node2D, x: float, y: float) -> void:
	for side in [-1.0, 1.0]:
		c.draw_circle(Vector2(x, y * side), 0.115, Color("fff7df"))
		c.draw_circle(Vector2(x + 0.035, y * side), 0.055, INK)


static func _mouse(c: Node2D, flash: float) -> void:
	var fur := Color("bba39e").lerp(Color.WHITE, flash)
	c.draw_polyline(PackedVector2Array([Vector2(-0.65, 0), Vector2(-1.12, -0.18), Vector2(-1.32, 0.14)]), Color("bf8286"), 0.13, true)
	_disc(c, Vector2(-0.1, 0), 0.72, fur)
	for side in [-1.0, 1.0]:
		_disc(c, Vector2(0.23, side * 0.62), 0.35, fur)
		c.draw_circle(Vector2(0.23, side * 0.62), 0.2, Color("db9e9b"))
	_shape(c, [Vector2(0.25, -0.45), Vector2(1.05, 0), Vector2(0.25, 0.45)], fur)
	_eyes(c, 0.5, 0.24)
	c.draw_circle(Vector2(1.0, 0), 0.1, Color("794d59"))
	for side in [-1.0, 1.0]:
		c.draw_line(Vector2(0.8, 0.12 * side), Vector2(1.05, 0.4 * side), Color("f1d3bb"), 0.04, true)


static func _dog(c: Node2D, flash: float) -> void:
	var fur := Color("c8955e").lerp(Color.WHITE, flash)
	_disc(c, Vector2(-0.18, 0), 0.75, fur)
	for side in [-1.0, 1.0]:
		_shape(c, [Vector2(0.25, side * 0.3), Vector2(-0.25, side * 0.95), Vector2(0.5, side * 0.78)], Color("82563f").lerp(Color.WHITE, flash))
	_disc(c, Vector2(0.43, 0), 0.58, fur)
	c.draw_circle(Vector2(0.76, 0), 0.29, Color("f3d8ac"))
	_eyes(c, 0.54, 0.32)
	c.draw_circle(Vector2(0.98, 0), 0.13, INK)
	c.draw_line(Vector2(-0.25, -0.66), Vector2(-0.25, 0.66), Color("bf5545"), 0.21, true)
	for side in [-1.0, 1.0]:
		c.draw_line(Vector2(0.35, side * 0.45), Vector2(0.66, side * 0.39), INK, 0.08, true)


static func _crow(c: Node2D, flash: float) -> void:
	var feathers := Color("697c9a").lerp(Color.WHITE, flash)
	for side in [-1.0, 1.0]:
		_shape(c, [Vector2(0.16, 0), Vector2(-0.45, side * 1.08), Vector2(-0.9, side * 0.65), Vector2(-0.55, 0)], feathers)
	_disc(c, Vector2(0.02, 0), 0.49, feathers.darkened(0.14))
	_disc(c, Vector2(0.42, 0), 0.4, feathers)
	_shape(c, [Vector2(0.61, -0.18), Vector2(1.17, 0), Vector2(0.61, 0.18)], Color("e0b56c"))
	_eyes(c, 0.5, 0.25)


static func _raccoon(c: Node2D, flash: float, armored: bool) -> void:
	var fur := Color("a6ac9d").lerp(Color.WHITE, flash)
	c.draw_line(Vector2(-0.5, 0), Vector2(-1.2, 0.3), INK, 0.37, true)
	for stripe in 3:
		c.draw_circle(Vector2(-0.62 - stripe * 0.22, stripe * 0.1), 0.15, fur if stripe % 2 == 0 else INK)
	_disc(c, Vector2(-0.1, 0), 0.71, fur)
	if armored:
		_shape(c, [Vector2(-0.72, -0.71), Vector2(0.27, -0.71), Vector2(0.27, 0.71), Vector2(-0.72, 0.71)], Color("658b8e").lerp(Color.WHITE, flash))
		for rib in 3:
			c.draw_line(Vector2(-0.56 + rib * 0.26, -0.6), Vector2(-0.56 + rib * 0.26, 0.6), Color("b4ccc1"), 0.08, true)
	for side in [-1.0, 1.0]:
		_disc(c, Vector2(0.35, side * 0.55), 0.22, fur)
	_disc(c, Vector2(0.48, 0), 0.51, fur)
	for side in [-1.0, 1.0]:
		c.draw_circle(Vector2(0.63, side * 0.26), 0.23, INK)
	_eyes(c, 0.68, 0.26)
	c.draw_circle(Vector2(0.99, 0), 0.1, INK)


static func _flea(c: Node2D, flash: float) -> void:
	for side in [-1.0, 1.0]:
		for leg in 3:
			c.draw_line(Vector2(-0.55 + leg * 0.5, side * 0.32), Vector2(-0.85 + leg * 0.5, side * 0.95), Color("bc8c69"), 0.14, true)
	_disc(c, Vector2.ZERO, 0.63, Color("bc745b").lerp(Color.WHITE, flash))
	c.draw_line(Vector2(-0.15, -0.5), Vector2(-0.15, 0.5), INK, 0.07, true)
	_eyes(c, 0.35, 0.26)


static func _robot(c: Node2D, flash: float, enraged: bool) -> void:
	var shell := Color("ce6b54").lerp(Color.WHITE, flash)
	for side in [-1.0, 1.0]:
		c.draw_line(Vector2(0.2, side * 0.8), Vector2(0.7, side * 1.16), INK, 0.17, true)
		for bristle in 3:
			c.draw_line(Vector2(0.7, side * 1.16), Vector2(0.9 + bristle * 0.13, side * (1.0 + bristle * 0.13)), Color("bea98b"), 0.07, true)
	_disc(c, Vector2.ZERO, 0.97, Color("697778"))
	_disc(c, Vector2.ZERO, 0.83, shell)
	c.draw_arc(Vector2.ZERO, 0.88, -1.4, 1.4, 24, Color("f5d7a4"), 0.11, true)
	_disc(c, Vector2(-0.33, 0), 0.27, Color("344753"))
	c.draw_circle(Vector2(-0.33, 0), 0.1, Color("ffcf72"))
	_shape(c, [Vector2(0.12, -0.5), Vector2(0.63, -0.5), Vector2(0.63, 0.5), Vector2(0.12, 0.5)], INK)
	for side in [-1.0, 1.0]:
		c.draw_line(Vector2(0.31, side * 0.16), Vector2(0.49, side * 0.31), Color("ff4f53") if enraged else Color("ffc877"), 0.09, true)
