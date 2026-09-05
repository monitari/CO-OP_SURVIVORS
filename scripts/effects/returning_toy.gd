extends Node2D

var anchor: ChainPlayer
var grid: EnemySpatialGrid
var heading := Vector2.RIGHT
var reach := 260.0
var damage := 30.0
var tint := Color("ffc67b")
var age := 0.0
var struck: Dictionary = {}
var ring := false
const TOY_TEXTURE := preload("res://assets/ui/icons/boomerang.svg")
const LIFETIME := 1.25

func _physics_process(delta: float) -> void:
	if not is_instance_valid(anchor) or anchor.downed:
		queue_free()
		return
	age += delta
	var progress := minf(1.0, age / LIFETIME)
	var distance := sin(progress * PI) * reach
	var old_position := global_position
	global_position = anchor.global_position if ring else anchor.global_position + heading * distance
	var hit_radius := progress * reach if ring else 20.0
	var phase := 0 if progress < 0.5 or ring else 1
	var travel := old_position.distance_to(global_position)
	for enemy in grid.query_radius(global_position, hit_radius + 48.0 + (0.0 if ring else travel)):
		var separation := global_position.distance_to(enemy.global_position)
		if ring and absf(separation - hit_radius) > enemy.radius + 12.0 + reach * delta / LIFETIME: continue
		if not ring and Geometry2D.get_closest_point_to_segment(enemy.global_position, old_position, global_position).distance_to(enemy.global_position) > enemy.radius + hit_radius: continue
		var key := "%d:%d" % [enemy.get_instance_id(), phase]
		if struck.has(key): continue
		struck[key] = true
		enemy.take_damage(damage)
	queue_redraw()
	if progress >= 1.0: queue_free()

func _draw() -> void:
	var progress := age / LIFETIME
	var alpha := minf(1.0, (1.0 - progress) * 5.0)
	if ring:
		draw_arc(Vector2.ZERO, maxf(1.0, progress * reach), 0, TAU, 64, Color(tint, alpha * 0.7), 15.0, true)
	else:
		draw_set_transform(Vector2.ZERO, age * 8.0)
		draw_texture_rect(TOY_TEXTURE, Rect2(-24, -24, 48, 48), false, Color(1, 1, 1, alpha))
