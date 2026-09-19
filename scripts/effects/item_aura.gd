extends Node2D
## One shared draw node; no per-enemy effects or unbounded particle emitters.
var game: Node
var phase := 0.0
var was_active := false

func step(delta: float) -> void:
	var active: bool = game.guard_remaining > 0 or game.frenzy_remaining > 0 or game.time_stop_remaining > 0
	for player in game.players:
		active = active or player.contact_pressure > 1.05
	if active or was_active:
		phase += delta
		queue_redraw()
	was_active = active

func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:item_aura", probe_started)


func _probed_draw() -> void:
	if not is_instance_valid(game): return
	for player in game.players:
		if player.downed: continue
		var at: Vector2 = to_local(player.global_position)
		if game.guard_remaining > 0:
			var alpha := minf(1.0, game.guard_remaining)
			var hex := PackedVector2Array()
			for index in 6:
				hex.append(at + Vector2.from_angle(index * TAU / 6.0 - PI / 6) * 43)
			draw_colored_polygon(hex, Color(0.45, 0.94, 1.0, 0.10 * alpha))
			hex.append(hex[0])
			draw_polyline(hex, Color(0.6, 0.98, 1.0, 0.85 * alpha), 3, true)
			draw_arc(at, 48, -PI / 2, -PI / 2 + TAU * game.guard_remaining / game.GUARD_DURATION, 48, Color(0.8, 1.0, 1.0, alpha), 3, true)
		if game.frenzy_remaining > 0:
			var alpha := minf(1.0, game.frenzy_remaining)
			for index in 7:
				var angle := index * TAU / 7.0 + phase * 1.5
				var tip := 46 + sin(phase * 8 + index) * 7
				draw_colored_polygon(PackedVector2Array([
					at + Vector2.from_angle(angle - 0.13) * 29,
					at + Vector2.from_angle(angle + 0.17) * tip,
					at + Vector2.from_angle(angle + 0.13) * 34]), Color(1.0, 0.45, 0.19, 0.65 * alpha))
			var ratio: float = game.frenzy_remaining / game.FRENZY_DURATION
			draw_arc(at, 36, -PI / 2, -PI / 2 + TAU * ratio, 40, Color(1.0, 0.78, 0.32, alpha), 2, true)
		if player.contact_pressure > 1.05 and game.guard_remaining <= 0:
			draw_arc(at, 30, 0, TAU, 24, Color(1.0, 0.25, 0.2, 0.6), 3, true)
	if game.time_stop_remaining > 0:
		var center: Vector2 = to_local((game.players[0].global_position + game.players[1].global_position) * 0.5)
		var alpha := minf(1.0, game.time_stop_remaining)
		var tint := Color(0.58, 0.83, 1.0, 0.65 * alpha)
		draw_circle(center, 112, Color(0.34, 0.56, 0.9, 0.045 * alpha))
		for index in 12:
			var direction := Vector2.from_angle(index * TAU / 12)
			draw_line(center + direction * 99, center + direction * 108, tint, 3, true)
		draw_line(center, center + Vector2(0, -73), tint, 4, true)
		draw_line(center, center + Vector2(44, -25), tint, 4, true)
		draw_arc(center, 116, -PI / 2, -PI / 2 + TAU * game.time_stop_remaining / game.TIME_STOP_DURATION, 64, tint, 3, true)
		var marked := 0
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or enemy.dead: continue
			var at: Vector2 = to_local(enemy.global_position)
			if at.distance_squared_to(center) > 620 * 620: continue
			for side in [-1, 1]:
				draw_rect(Rect2(at + Vector2(side * 4 - 1.5, -enemy.radius - 12), Vector2(3, 9)), tint)
			marked += 1
			if marked >= 24: break
