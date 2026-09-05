class_name ChaserEnemy
extends Node2D
const EnemyArt := preload("res://scripts/enemy_art.gd")
const EnemyIcons := preload("res://scripts/ui/enemy_icons.gd")
var body_sprite: Sprite2D

func _ready() -> void:
	if is_instance_valid(body_sprite):
		body_sprite.rotation = -rotation

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and is_instance_valid(body_sprite):
		body_sprite.rotation = -rotation

signal died(enemy: ChaserEnemy)
signal ranged_attack(origin: Vector2, direction: Vector2, damage: float)
signal damage_taken(enemy: ChaserEnemy, amount: float)
signal chain_slam(impact_point: Vector2, damage: float, radius: float)
signal enraged(enemy: ChaserEnemy)

## Difficulty is elapsed/30, so 4.0 is the boss timer. Past that point a
## pair can be carrying three weapons each, stacked personal attributes and
## up to three active resonances, while enemies were still only gaining a
## flat +5 health per difficulty step. The ramp below is deliberately zero
## until this threshold: the early game is already the lethal part, and
## making it harder is not what the late curve needs.
const LATE_GAME_DIFFICULTY := 4.0 ## 200s at the current DIFFICULTY_SECONDS
const LATE_HEALTH_PER_STEP := 0.35
const LATE_DAMAGE_PER_STEP := 0.20
const EARLY_GAME_DIFFICULTY := 1.0
const OPENING_CONTACT_DAMAGE_MULTIPLIER := 0.75

const BOSS_SLAM_RADIUS := 95.0
## 0.7s of warning against a 95px circle is not a dodge, it is a reaction
## test — and the pair is tied together, so getting out means agreeing where
## to go first. The telegraph is now long enough to be a decision.
const BOSS_SLAM_WINDUP := 1.5
const BOSS_SLAM_WINDUP_ENRAGED := 1.1
const BOSS_CHARGE_WINDUP := 0.85
## A hit used to be a scale tween allocated per call, which at a few hundred
## hits a second is a lot of short-lived objects. It is now a plain timer
## stepped with everything else, and it drives a colour flash too — a dark
## enemy taking damage on a dark field was previously almost invisible.
const HIT_FLASH_TIME := 0.12 ## Shared by the emitted hit radius and the drawn telegraph so they can never drift apart.

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
var redraw_count := 0 ## Bumped by _draw() itself; lets tests confirm queue_redraw() calls actually drop instead of trusting the diff.
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
var boss_attack_timer := 0.0
var boss_slam_windup := 0.0
var boss_slam_point := Vector2.ZERO
var boss_enraged := false
var hit_flash := 0.0


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
	boss_attack_timer = randf_range(2.6, 3.6) if is_boss else 0.0
	boss_slam_windup = 0.0
	boss_slam_point = Vector2.ZERO
	boss_enraged = false
	hit_flash = 0.0
	scale = Vector2.ONE

	match archetype:
		"swarm":
			# Individually harmless and worth almost nothing; the point is that
			# they arrive by the dozen. A wave of these is the pair's chance to
			# convert a good position into levels rather than a threat to it.
			move_speed = 128.0
			radius = 9.0
			max_health = 10.0
			contact_damage = 4.0
			xp_value = 3
			enemy_color = Color("9bf6ff")
		"bulwark":
			# The opposite pressure: it will not die quickly, and while it is
			# alive it is walking straight at the chain. Worth real XP because
			# committing damage to it is a real cost.
			move_speed = 44.0
			radius = 30.0
			max_health = 190.0
			contact_damage = 22.0
			xp_value = 26
			enemy_color = Color("8d99ae")
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
			# This archetype only ever spawns as the boss (WaveDirector never
			# hands it to a regular or elite wave), so its base speed is tuned
			# for that fight specifically — fast enough to threaten a chain
			# that keeps its distance, not the ~63px/s crawl a generic tanky
			# mob's stat block would otherwise produce at boss spawn time.
			move_speed = 115.0
			radius = 32.0
			max_health = 260.0
			contact_damage = 26.0
			xp_value = 28
			# Not purple: P2 and 볼타 are purple, and a boss that shares the
			# player palette is the worst possible read in a crowded field.
			enemy_color = Color("c1121f")
		_:
			move_speed = 78.0
			radius = randf_range(14.0, 22.0)
			max_health = 32.0
			contact_damage = 12.0
			xp_value = 5
			enemy_color = Color("ef476f")

	move_speed += difficulty * 2.6 + randf_range(-7.0, 9.0)
	max_health += difficulty * 5.0 + radius * 0.3
	# Spawn pacing alone cannot protect a pair whose first ring closes from an
	# unlucky set of angles. Let contact damage teach pressure before it fully
	# punishes it, reaching the original value at 30 seconds. Special enemies
	# unlock at that same boundary, so they are never softened by this ramp.
	if difficulty < EARLY_GAME_DIFFICULTY:
		contact_damage *= lerpf(
			OPENING_CONTACT_DAMAGE_MULTIPLIER,
			1.0,
			clampf(difficulty / EARLY_GAME_DIFFICULTY, 0.0, 1.0)
		)
	# The boss is excluded: it carries its own multiplier, and compounding the
	# two is how it ended up unkillable.
	if difficulty > LATE_GAME_DIFFICULTY and not is_boss:
		var late := difficulty - LATE_GAME_DIFFICULTY
		max_health *= 1.0 + late * LATE_HEALTH_PER_STEP
		contact_damage *= 1.0 + late * LATE_DAMAGE_PER_STEP
	if elite:
		max_health *= 2.7
		move_speed *= 1.08
		radius *= 1.3
		contact_damage *= 1.4
		xp_value *= 4
	if boss:
		# One explicit multiplier instead of elite x boss, and a gentler contact
		# hit: two touches killing an unupgraded survivor left no fight in it.
		max_health *= 12.0
		radius *= 1.45
		contact_damage *= 1.15
		xp_value = 150
	health = max_health
	z_index = 5 # Threat telegraphs remain above friendly attack effects.
	if not is_instance_valid(body_sprite):
		body_sprite = Sprite2D.new()
		add_child(body_sprite)
	body_sprite.texture = EnemyIcons.get_icon(archetype)
	body_sprite.scale = Vector2.ONE * (radius * 2.65 / maxf(body_sprite.texture.get_width(), body_sprite.texture.get_height()))
	body_sprite.modulate = Color.WHITE
	set_notify_local_transform(true)
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
	if is_instance_valid(body_sprite):
		body_sprite.rotation = -rotation
		body_sprite.modulate = Color("ffc4a1") if boss_enraged else Color.WHITE.lerp(Color("fff1b5"), hit_flash * 0.8)
	var was_slowed := slow_timer > 0.0
	slow_timer = maxf(0.0, slow_timer - delta)
	if was_slowed and slow_timer <= 0.0:
		slow_multiplier = 1.0
	var target := _nearest_living_player(players)
	var target_position := target.global_position
	if archetype == "chain_hunter" or archetype == "brute":
		target_position = (players[0].global_position + players[1].global_position) * 0.5
	var speed_scale := slow_multiplier if slow_timer > 0.0 else 1.0
	var had_telegraph := charge_windup > 0.0 or shooter_windup > 0.0 or chain_windup > 0.0 or boss_slam_windup > 0.0
	var had_flash := hit_flash > 0.0
	if had_flash:
		hit_flash = maxf(0.0, hit_flash - delta / HIT_FLASH_TIME)
		scale = Vector2.ONE * (1.0 + hit_flash * 0.22)

	match archetype:
		"charger":
			_step_charger(target_position, speed_scale, delta)
		"shooter":
			_step_shooter(target_position, speed_scale, delta)
		"brute":
			if boss:
				_step_boss(players, target_position, speed_scale, delta)
			else:
				var direction := global_position.direction_to(target_position)
				position += direction * move_speed * speed_scale * delta
				rotation = direction.angle()
		_:
			var direction := global_position.direction_to(target_position)
			position += direction * move_speed * speed_scale * delta
			rotation = direction.angle()

	if archetype == "chain_hunter":
		_try_damage_chain(players, delta)
	else:
		_try_contact_damage(players)
	# Position and rotation move the node via its transform, which Godot composites
	# without a redraw. The only per-frame state _draw() actually reads is the
	# telegraph windup timers (their pulsing alpha and presence); everything else
	# that _draw() depends on (health, elite/boss flags, radius) already triggers
	# its own queue_redraw() where it changes. Redraw when a telegraph is active
	# on either side of this step — mid-windup for the pulsing alpha, and on the
	# entry/exit frame so the line actually appears and actually clears instead
	# of leaving a stale frame on screen. Skipping it the rest of the time is
	# what keeps a few hundred pooled enemies from redrawing every physics tick
	# regardless of whether anything they draw actually changed.
	if had_telegraph or had_flash or charge_windup > 0.0 or shooter_windup > 0.0 or chain_windup > 0.0 or boss_slam_windup > 0.0:
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


## The boss ("결속 파괴자" / Bond Breaker) alternates a slow chase with two
## telegraphed attacks instead of the generic "walk into the players" a plain
## brute stat block would otherwise produce: 사슬 강타 (Chain Slam) strikes the
## nearest point of the chain itself — draining chain integrity directly
## rather than just player health, which is the whole point of a boss whose
## arrival message already promises it targets the chain — and, once it drops
## below half health, an enraged charge dash that reuses the exact windup/dash
## fields and telegraph the regular charger archetype already draws, so it
## reads as the same kind of threat the player has learned to respect all
## game instead of an unfamiliar one arriving for the first time at the boss.
func _step_boss(players: Array[ChainPlayer], target_position: Vector2, speed_scale: float, delta: float) -> void:
	if not boss_enraged and health <= max_health * 0.5:
		boss_enraged = true
		move_speed *= 1.4
		boss_attack_timer = minf(boss_attack_timer, 1.2)
		enraged.emit(self)
		queue_redraw()

	if charge_timer > 0.0:
		charge_timer -= delta
		position += charge_direction * move_speed * 2.6 * speed_scale * delta
		rotation = charge_direction.angle()
		return
	if charge_windup > 0.0:
		charge_windup -= delta
		if charge_windup <= 0.0:
			charge_timer = 0.5
		return
	if boss_slam_windup > 0.0:
		boss_slam_windup -= delta
		if boss_slam_windup <= 0.0:
			chain_slam.emit(boss_slam_point, 44.0 if boss_enraged else 34.0, BOSS_SLAM_RADIUS)
		return

	var direction := global_position.direction_to(target_position)
	position += direction * move_speed * speed_scale * delta
	rotation = direction.angle()

	boss_attack_timer -= delta
	if boss_attack_timer <= 0.0:
		boss_attack_timer = randf_range(3.2, 4.2) if boss_enraged else randf_range(4.4, 5.6)
		if boss_enraged and randf() < 0.5:
			charge_direction = direction
			telegraph_direction = direction
			charge_windup = BOSS_CHARGE_WINDUP
		else:
			boss_slam_point = _closest_point_on_chain(players)
			telegraph_direction = global_position.direction_to(boss_slam_point)
			boss_slam_windup = BOSS_SLAM_WINDUP_ENRAGED if boss_enraged else BOSS_SLAM_WINDUP


## The point on the players' current chain segment closest to the boss right
## now — captured once at windup start so the telegraph is a committed,
## dodgeable threat (move the chain away from it during the windup) rather
## than one that homes in on wherever the chain ends up by the time it lands.
func _closest_point_on_chain(players: Array[ChainPlayer]) -> Vector2:
	var from := players[0].global_position
	var to := players[1].global_position
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return from
	var ratio := clampf((global_position - from).dot(segment) / length_squared, 0.0, 1.0)
	return from + segment * ratio


func _try_contact_damage(players: Array[ChainPlayer]) -> void:
	if contact_cooldown > 0.0:
		return
	for player in players:
		if global_position.distance_to(player.global_position) <= radius + player.radius:
			# Passing our position lets 가시의 견장 send part of the hit back.
			if player.hurt(contact_damage, global_position):
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
			damaged = player.hurt(contact_damage, global_position) or damaged
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
	hit_flash = 1.0
	scale = Vector2(1.22, 1.22)
	queue_redraw()
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
	redraw_count += 1
	if charge_windup > 0.0:
		var charge_alpha := 0.25 + sin(charge_windup * 34.0) * 0.12
		draw_line(Vector2.ZERO, telegraph_direction.rotated(-rotation) * 240.0, Color(1.0, 0.25, 0.2, charge_alpha), 12.0, true)
	if shooter_windup > 0.0:
		draw_dashed_line(Vector2.ZERO, telegraph_direction.rotated(-rotation) * 320.0, Color(1.0, 0.35, 0.42, 0.8), 3.0, 10.0, true)
	if chain_windup > 0.0:
		draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU, 28, Color("ff5d8f"), 6.0, true)
	if boss_slam_windup > 0.0:
		var total := BOSS_SLAM_WINDUP_ENRAGED if boss_enraged else BOSS_SLAM_WINDUP
		var progress := clampf(1.0 - boss_slam_windup / total, 0.0, 1.0)
		var local_point := (boss_slam_point - global_position).rotated(-rotation)
		draw_line(Vector2.ZERO, local_point, Color(1.0, 0.35, 0.42, 0.4), 3.0, true)
		# Outline plus a filling disc: the ring says where, and how full it is
		# says when. A pulsing outline alone gave the pair no way to time the
		# dodge, only to guess at it.
		draw_circle(local_point, BOSS_SLAM_RADIUS * progress, Color(1.0, 0.25, 0.35, 0.22))
		draw_arc(local_point, BOSS_SLAM_RADIUS, 0.0, TAU, 32, Color(1.0, 0.3, 0.4, 0.75), 5.0, true)
		draw_arc(
			local_point, BOSS_SLAM_RADIUS - 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32,
			Color(1.0, 0.85, 0.4, 0.9), 4.0, true
		)
	if not is_instance_valid(body_sprite):
		EnemyArt.draw_body(self, archetype, radius, hit_flash * 0.8, boss_enraged)
	if elite and not boss:
		for side in 2:
			draw_arc(Vector2.ZERO, radius + 7.0, side * PI - 0.65, side * PI + 0.65, 12, Color("e8c98a"), 2.5, true)
	if boss:
		for quadrant in 4:
			var start := quadrant * TAU / 4.0 + 0.16
			draw_arc(Vector2.ZERO, radius + 12.0, start, start + 0.8, 10,
				Color("ff5a53") if boss_enraged else Color("e8c98a"), 4.0 if boss_enraged else 2.5, true)
	var health_ratio := clampf(health / max_health, 0.0, 1.0)
	if health_ratio < 0.99 or elite:
		draw_rect(Rect2(-radius, -radius - 10.0, radius * 2.0, 4.0), Color("351d3c"))
		draw_rect(Rect2(-radius, -radius - 10.0, radius * 2.0 * health_ratio, 4.0), Color("80ed99"))
