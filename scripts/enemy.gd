class_name ChaserEnemy
extends Node2D

signal died(enemy: ChaserEnemy)
signal ranged_attack(origin: Vector2, direction: Vector2, damage: float)
signal damage_taken(enemy: ChaserEnemy, amount: float)

var archetype := "chaser"
var active := false
var elite := false
var boss := false
var move_speed := 78.0
var radius := 17.0
var health := 32.0
var max_health := 32.0
var contact_damage := 12.0
var xp_value := 5
var contact_cooldown := 0.0
var enemy_color := Color("ef476f")
var dead := false
var slow_timer := 0.0
var slow_multiplier := 1.0
var behavior_timer := 0.0
var charge_timer := 0.0
var charge_direction := Vector2.ZERO
var attack_timer := 1.5
var charge_windup := 0.0
var shooter_windup := 0.0
var chain_windup := 0.0
var telegraph_direction := Vector2.RIGHT


func setup(difficulty: float, new_archetype: String = "chaser", is_elite: bool = false, is_boss: bool = false) -> void:
	archetype = new_archetype
	elite = is_elite
	boss = is_boss
	active = true
	dead = false
	visible = true
	modulate = Color.WHITE
	scale = Vector2.ONE
	rotation = 0.0
	contact_cooldown = 0.0
	slow_timer = 0.0
	slow_multiplier = 1.0
	behavior_timer = randf_range(0.7, 1.5)
	charge_timer = 0.0
	charge_windup = 0.0
	shooter_windup = 0.0
	chain_windup = 0.0
	telegraph_direction = Vector2.RIGHT
	attack_timer = randf_range(0.8, 1.8)

	match archetype:
		"charger":
			move_speed = 68.0
			radius = 20.0
			max_health = 52.0
			contact_damage = 20.0
			xp_value = 7
			enemy_color = Color("ff8c42")
		"shooter":
			move_speed = 58.0
			radius = 16.0
			max_health = 42.0
			contact_damage = 8.0
			xp_value = 8
			enemy_color = Color("ffd166")
		"chain_hunter":
			move_speed = 102.0
			radius = 18.0
			max_health = 48.0
			contact_damage = 10.0
			xp_value = 9
			enemy_color = Color("06d6a0")
		"brute":
			move_speed = 48.0
			radius = 32.0
			max_health = 260.0
			contact_damage = 26.0
			xp_value = 28
			enemy_color = Color("9b5de5")
		_:
			move_speed = 78.0
			radius = randf_range(14.0, 22.0)
			max_health = 32.0
			contact_damage = 12.0
			xp_value = 5
			enemy_color = Color("ef476f")

	move_speed += difficulty * 2.6 + randf_range(-7.0, 9.0)
	max_health += difficulty * 5.0 + radius * 0.3
	if elite:
		max_health *= 2.7
		move_speed *= 1.08
		radius *= 1.3
		contact_damage *= 1.4
		xp_value *= 4
	if boss:
		max_health *= 4.0
		radius *= 1.45
		contact_damage *= 1.35
		xp_value = 150
	health = max_health
	add_to_group("enemies")
	queue_redraw()


func deactivate() -> void:
	active = false
	dead = true
	visible = false
	if is_in_group("enemies"):
		remove_from_group("enemies")


func step(players: Array[ChainPlayer], delta: float) -> void:
	if dead or not active:
		return
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	var was_slowed := slow_timer > 0.0
	slow_timer = maxf(0.0, slow_timer - delta)
	if was_slowed and slow_timer <= 0.0:
		slow_multiplier = 1.0
	var target := _nearest_living_player(players)
	var target_position := target.global_position
	if archetype == "chain_hunter" or archetype == "brute":
		target_position = (players[0].global_position + players[1].global_position) * 0.5
	var speed_scale := slow_multiplier if slow_timer > 0.0 else 1.0

	match archetype:
		"charger":
			_step_charger(target_position, speed_scale, delta)
		"shooter":
			_step_shooter(target_position, speed_scale, delta)
		_:
			var direction := global_position.direction_to(target_position)
			position += direction * move_speed * speed_scale * delta
			rotation = direction.angle()

	if archetype == "chain_hunter":
		_try_damage_chain(players, delta)
	else:
		_try_contact_damage(players)
	queue_redraw()


func _step_charger(target_position: Vector2, speed_scale: float, delta: float) -> void:
	if charge_timer > 0.0:
		charge_timer -= delta
		position += charge_direction * move_speed * 3.4 * speed_scale * delta
		rotation = charge_direction.angle()
		return
	if charge_windup > 0.0:
		charge_windup -= delta
		if charge_windup <= 0.0:
			charge_timer = 0.55
		return
	behavior_timer -= delta
	var direction := global_position.direction_to(target_position)
	if behavior_timer <= 0.0:
		charge_direction = direction
		telegraph_direction = direction
		charge_windup = 0.55
		behavior_timer = 2.95
	else:
		position += direction * move_speed * 0.42 * speed_scale * delta
		rotation = direction.angle()


func _step_shooter(target_position: Vector2, speed_scale: float, delta: float) -> void:
	var distance := global_position.distance_to(target_position)
	var direction := global_position.direction_to(target_position)
	if distance > 390.0:
		position += direction * move_speed * speed_scale * delta
	elif distance < 245.0:
		position -= direction * move_speed * speed_scale * delta
	rotation = direction.angle()
	if shooter_windup > 0.0:
		shooter_windup -= delta
		if shooter_windup <= 0.0:
			ranged_attack.emit(global_position, telegraph_direction, 10.0 if not elite else 16.0)
		return
	attack_timer -= delta
	if attack_timer <= 0.0 and distance <= 520.0:
		attack_timer = maxf(0.65, 1.8 - max_health / 500.0)
		telegraph_direction = direction
		shooter_windup = 0.48


func _try_contact_damage(players: Array[ChainPlayer]) -> void:
	if contact_cooldown > 0.0:
		return
	for player in players:
		if global_position.distance_to(player.global_position) <= radius + player.radius:
			if player.hurt(contact_damage):
				contact_cooldown = 0.75
			break


func _try_damage_chain(players: Array[ChainPlayer], delta: float) -> void:
	if contact_cooldown > 0.0:
		return
	var distance := _distance_to_segment(global_position, players[0].global_position, players[1].global_position)
	if distance <= radius + 12.0:
		if chain_windup <= 0.0:
			chain_windup = 0.45
			return
		chain_windup -= delta
		if chain_windup > 0.0:
			return
		var damaged := false
		for player in players:
			damaged = player.hurt(contact_damage) or damaged
		if damaged:
			contact_cooldown = 0.9
	else:
		chain_windup = 0.0


func _nearest_living_player(players: Array[ChainPlayer]) -> ChainPlayer:
	if players[0].downed and not players[1].downed:
		return players[1]
	if players[1].downed and not players[0].downed:
		return players[0]
	if global_position.distance_squared_to(players[1].global_position) < global_position.distance_squared_to(players[0].global_position):
		return players[1]
	return players[0]


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * ratio)


func take_damage(amount: float) -> bool:
	if dead or not active:
		return false
	health -= amount
	damage_taken.emit(self, amount)
	scale = Vector2(1.22, 1.22)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	if health <= 0.0:
		dead = true
		died.emit(self)
		return true
	queue_redraw()
	return false


func apply_slow(duration: float, multiplier: float) -> void:
	if dead:
		return
	slow_timer = maxf(slow_timer, duration)
	slow_multiplier = minf(slow_multiplier, multiplier)
	modulate = Color("bde0fe")
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)


func _draw() -> void:
	if charge_windup > 0.0:
		var charge_alpha := 0.25 + sin(charge_windup * 34.0) * 0.12
		draw_line(Vector2.ZERO, telegraph_direction.rotated(-rotation) * 240.0, Color(1.0, 0.25, 0.2, charge_alpha), 12.0, true)
	if shooter_windup > 0.0:
		draw_dashed_line(Vector2.ZERO, telegraph_direction.rotated(-rotation) * 320.0, Color(1.0, 0.35, 0.42, 0.8), 3.0, 10.0, true)
	if chain_windup > 0.0:
		draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU, 28, Color("ff5d8f"), 6.0, true)
	draw_circle(Vector2.ZERO, radius + 6.0, Color(enemy_color, 0.13))
	match archetype:
		"charger":
			draw_colored_polygon(PackedVector2Array([Vector2(radius, 0), Vector2(-radius * 0.75, radius * 0.72), Vector2(-radius * 0.75, -radius * 0.72)]), enemy_color)
		"shooter":
			draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), enemy_color)
		"chain_hunter":
			draw_circle(Vector2.ZERO, radius, enemy_color, false, 7.0)
			draw_line(Vector2(-radius, 0), Vector2(radius, 0), enemy_color, 4.0)
		_:
			draw_circle(Vector2.ZERO, radius, enemy_color)
	if elite:
		draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 24, Color("fff275"), 3.0, true)
	if boss:
		draw_colored_polygon(PackedVector2Array([Vector2(-14, -radius - 6), Vector2(-8, -radius - 19), Vector2(0, -radius - 9), Vector2(8, -radius - 19), Vector2(14, -radius - 6)]), Color("fff275"))
	draw_circle(Vector2(radius * 0.35, -radius * 0.27), 3.0, Color.WHITE)
	var health_ratio := clampf(health / max_health, 0.0, 1.0)
	if health_ratio < 0.99 or elite:
		draw_rect(Rect2(-radius, -radius - 10.0, radius * 2.0, 4.0), Color("351d3c"))
		draw_rect(Rect2(-radius, -radius - 10.0, radius * 2.0 * health_ratio, 4.0), Color("80ed99"))
