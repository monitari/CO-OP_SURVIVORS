class_name ChaserEnemy
extends Node2D
const EnemyArt := preload("res://scripts/entities/enemy_art.gd")
const EnemyIcons := preload("res://scripts/ui/enemy_icons.gd")
var body_sprite: Sprite2D
var last_damage_player := -1
var last_damage_weapon := ""

func _ready() -> void:
	if is_instance_valid(body_sprite):
		_update_body_facing()

func _update_body_facing() -> void:
	body_sprite.rotation = -rotation
	body_sprite.flip_h = faces_along_heading and cos(rotation) < 0.0

signal died(enemy: ChaserEnemy)
signal ranged_attack(origin: Vector2, direction: Vector2, damage: float)
signal damage_taken(enemy: ChaserEnemy, amount: float)
signal chain_slam(impact_point: Vector2, damage: float, radius: float)
signal enraged(enemy: ChaserEnemy)

## Past this point a pair can be carrying four weapons each, stacked personal
## attributes and up to three active resonances, while enemies were still only
## gaining a flat +5 health per difficulty step. The ramp below is deliberately
## zero until this threshold: the early game is already the lethal part, and
## making it harder is not what the late curve needs.
## Where the stat ramp starts. It used to open at difficulty four — a little
## over four minutes — so by minute ten an ordinary chaser already carried three
## times its base health and twice its touch, on top of a spawn rate that had
## also bottomed out by then. Two curves both finishing early is what made the
## five-to-ten minute stretch read as the hard part of the run. Starting later
## and climbing slightly faster puts the same numbers at the twenty-five minute
## mark while leaving the first ten minutes to the build.
const LATE_GAME_DIFFICULTY := 5.5 ## ~340s at the current DIFFICULTY_SECONDS
const LATE_HEALTH_PER_STEP := 0.42
const LATE_DAMAGE_PER_STEP := 0.22
## A twenty-five-minute run reaches difficulty ~24, and an uncapped linear ramp
## there means a basic chaser that hits for six times its archetype value —
## which is not "harder", it is "one touch kills anyone regardless of build".
## Health is allowed to keep climbing because damage output climbs with it;
## the thing a player cannot out-build is a one-shot.
const LATE_DAMAGE_CAP := 2.8
const LATE_HEALTH_CAP := 9.0
## Ordinary walking speed remains bounded. Runners use a warned, turn-limited
## sprint; moles charge straight, and ranged enemies aim ahead of movement.
const SPEED_RAMP_CAP := 34.0
## Experience per kill rises with the run, so a level-up curve steep enough to
## last twenty-five minutes is not paid for entirely by killing more things.
const XP_PER_DIFFICULTY := 0.20
## Difficulty at which every drop moves up one rung — about minute nine.
const DIFFICULTY_PER_GRADE := 9.0
const EARLY_GAME_DIFFICULTY := 1.4
const OPENING_CONTACT_DAMAGE_MULTIPLIER := 0.5

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
## Constructing a Color from a string parses that string. These two sat in the
## body-tint line that every enemy runs every tick, so a full crowd was parsing
## tens of thousands of colour literals a second to arrive at the same two values.
const ENRAGED_TINT := Color("ffc4a1")
const HIT_TINT := Color("fff1b5")

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
var xp_grade := 0
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
var boss_rank := 0 ## 1-5 for the run's bosses, 0 for everything else.
var hit_flash := 0.0
## Archetype tests that used to sit inside the per-frame step. Each `archetype in
## [...]` builds a fresh array every time it is evaluated — once per enemy per
## tick for the steering ones, and again on every transform notification for the
## facing one, which at a full crowd is tens of thousands of throwaway arrays a
## second for a question whose answer cannot change until setup() runs again.
## Rooftop planters. Not an enemy — it never moves, never touches anyone, and
## pays out a field drop when it is broken — but modelled as one because "a thing
## on the field that every weapon can hit" is precisely what this class already
## is. Making it its own system would have meant teaching a dozen separate damage
## paths about a second kind of target.
var scenery := false
## Bosses and scenery both hold their ground when a crowd walks into them. One
## flag rather than two tests, because the separation pass reads it for every
## sampled pair.
var immovable := false
var faces_along_heading := false ## Painted facing +X, so it mirrors rather than spins.
var leads_its_target := false ## Aims where the survivor is going, not where they are.
var hunts_the_chain := false ## Walks the midpoint between the pair, not the nearer cat.
var _tinted := false ## Whether body_sprite.modulate currently holds anything but white.
## Whether a warning is currently drawn on this body. The crowd loop reads it to
## keep anything mid-telegraph on the full-rate tick: a slam ring that fills in
## coarse jumps is not a fair warning, and the windup timers behind it are the
## one piece of enemy state a player is expected to read precisely.
var telegraphing := false
## Which stagger batch this body belongs to. Handed out round-robin at setup so
## the split is even and stable for as long as the body lives, rather than
## derived from an instance id whose spacing nothing guarantees.
var ai_batch := 0
static var _batch_cursor := 0


## `boss_rank` is 1-5 for the run's five bosses and 0 for everything else. Each
## boss is a real step up rather than the same fight with a bigger timer: more
## health, a heavier touch, and — from the third one on — the enraged patterns
## from the start instead of only below half health.
func setup(difficulty: float, new_archetype: String = "chaser", is_elite: bool = false, is_boss: bool = false, rank: int = 0) -> void:
	archetype = new_archetype
	scenery = archetype == "planter"
	immovable = is_boss or scenery
	# Every painted enemy except the legacy chaser has a readable left/right
	# silhouette. Keep the body upright and mirror that art from its movement
	# heading instead of rotating the whole sprite sideways.
	faces_along_heading = archetype != "chaser" and archetype != "planter"
	leads_its_target = archetype in ["wasp", "owl", "mole"]
	hunts_the_chain = archetype == "chain_hunter" or archetype == "brute"
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
	boss_rank = rank if is_boss else 0
	hit_flash = 0.0
	telegraphing = false
	ai_batch = _batch_cursor
	_batch_cursor += 1
	scale = Vector2.ONE

	match archetype:
		"swarm":
			xp_grade = 0
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
			xp_grade = 2
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
			xp_grade = 1
			move_speed = 68.0
			radius = 20.0
			max_health = 52.0
			contact_damage = 20.0
			xp_value = 7
			enemy_color = Color("ff8c42")
		"shooter":
			xp_grade = 1
			move_speed = 58.0
			radius = 16.0
			max_health = 42.0
			contact_damage = 8.0
			xp_value = 8
			enemy_color = Color("ffd166")
		"chain_hunter":
			xp_grade = 1
			move_speed = 102.0
			radius = 18.0
			max_health = 48.0
			contact_damage = 10.0
			xp_value = 9
			enemy_color = Color("06d6a0")
		"brute":
			xp_grade = 2
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
			xp_grade = 0
			move_speed = 78.0
			radius = randf_range(14.0, 22.0)
			max_health = 32.0
			contact_damage = 12.0
			xp_value = 5
			enemy_color = Color("ef476f")

	if scenery:
		# Deliberately fragile and deliberately flat on the difficulty curve: this
		# is a thing to notice and break, not a fight. Late in a run a planter
		# should still fall to a single sweep of whatever the pair is carrying.
		move_speed = 0.0
		radius = randf_range(20.0, 26.0)
		max_health = 26.0 + difficulty * 3.0
		contact_damage = 0.0
		xp_value = 0
		xp_grade = 0
		enemy_color = Color("80ed99")
	move_speed += minf(difficulty * 2.6, SPEED_RAMP_CAP) + randf_range(-7.0, 9.0)
	if archetype in ["rat_runner", "wasp", "hedgehog", "mole", "owl"]:
		var stats: Array = {
			"rat_runner": [145.0, 13.0, 28.0, 8.0, 7],
			"wasp": [76.0, 13.0, 30.0, 7.0, 9],
			"hedgehog": [48.0, 24.0, 125.0, 18.0, 20],
			"mole": [92.0, 18.0, 60.0, 14.0, 13],
			"owl": [66.0, 22.0, 85.0, 12.0, 17],
		}[archetype]
		move_speed = stats[0] + minf(difficulty * 2.6, SPEED_RAMP_CAP)
		radius = stats[1]
		max_health = stats[2]
		if is_boss and archetype == "owl":
			max_health = 260.0
			move_speed = 88.0
		contact_damage = stats[3]
		xp_value = stats[4]
		xp_grade = 2 if archetype in ["hedgehog", "owl"] else 1
	max_health += difficulty * 5.0 + radius * 0.3
	xp_value = maxi(1, int(round(float(xp_value) * (1.0 + difficulty * XP_PER_DIFFICULTY))))
	# Spawn pacing alone cannot protect a pair whose first ring closes from an
	# unlucky set of angles. Let contact damage teach pressure before it fully
	# punishes it, reaching the original value near 87 seconds. The quadratic
	# ramp keeps the first minute gentler while the pair earns its initial picks.
	if difficulty < EARLY_GAME_DIFFICULTY:
		contact_damage *= lerpf(
			OPENING_CONTACT_DAMAGE_MULTIPLIER,
			1.0,
			pow(clampf(difficulty / EARLY_GAME_DIFFICULTY, 0.0, 1.0), 2.0)
		)
	# The boss is excluded: it carries its own multiplier, and compounding the
	# two is how it ended up unkillable.
	if difficulty > LATE_GAME_DIFFICULTY and not is_boss:
		var late := difficulty - LATE_GAME_DIFFICULTY
		max_health *= minf(LATE_HEALTH_CAP, 1.0 + late * LATE_HEALTH_PER_STEP)
		contact_damage *= minf(LATE_DAMAGE_CAP, 1.0 + late * LATE_DAMAGE_PER_STEP)
	if elite:
		max_health *= 2.7
		move_speed *= 1.08
		radius *= 1.3
		contact_damage *= 1.4
		xp_grade = maxi(xp_grade, 2)
	if boss:
		# One explicit multiplier instead of elite x boss, and a gentler contact
		# hit: two touches killing an unupgraded survivor left no fight in it.
		# The rank step is 1.42 rather than a doubling: the pair's output over
		# five minutes of upgrades grows by roughly that much, so each boss
		# stays about as long a fight as the one before it.
		var rank_step := pow(1.42, float(maxi(1, boss_rank) - 1))
		max_health *= 12.0 * rank_step
		radius *= 1.45 + float(maxi(1, boss_rank) - 1) * 0.06
		contact_damage *= 1.15 + float(maxi(1, boss_rank) - 1) * 0.12
		move_speed += float(maxi(1, boss_rank) - 1) * 7.0
		xp_value = 150 * maxi(1, boss_rank)
		xp_grade = 3
	# Every kill drops now, so the silhouette has to carry two things at once:
	# what died, and how deep into the run it died. The archetype sets the rung
	# — a flea is never worth what a bulwark is — and the run lifts the whole
	# ladder a step at a time, so late trash reads richer than early trash
	# without every drop collapsing into one colour.
	#
	# Absolute value thresholds did this before and could not: xp_value climbs
	# 20% per difficulty step, so by minute twenty a mouse cleared the same bar
	# a bulwark cleared at minute one and the four grades stopped separating
	# anything. The top grade stays reserved for elites and bosses, which is
	# what makes spotting one on the floor mean something.
	# One rung, not a ladder of them: there are only four grades and the
	# archetypes already spread across three, so lifting by two would put a
	# flea and a guard dog on the same colour and undo the separation this
	# exists to show.
	var depth := mini(1, int(difficulty / DIFFICULTY_PER_GRADE))
	if boss:
		xp_grade = 3
	elif elite:
		xp_grade = clampi(maxi(xp_grade, 2) + depth, 2, 3)
	else:
		xp_grade = clampi(xp_grade + depth, 0, 2)
	health = max_health
	z_index = 5 # Threat telegraphs remain above friendly attack effects.
	if not is_instance_valid(body_sprite):
		body_sprite = Sprite2D.new()
		add_child(body_sprite)
	body_sprite.visible = true
	body_sprite.texture = EnemyIcons.get_icon(archetype)
	body_sprite.scale = Vector2.ONE * (radius * 2.65 / maxf(body_sprite.texture.get_width(), body_sprite.texture.get_height()))
	body_sprite.modulate = Color.WHITE
	_tinted = false
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
	if scenery:
		# No steering, no target, no contact. All a planter needs from a tick is
		# for its hit flash to fade, and at a hundred of them on a late field
		# that difference is the whole reason this returns here.
		if hit_flash > 0.0:
			hit_flash = maxf(0.0, hit_flash - delta / HIT_FLASH_TIME)
			scale = Vector2.ONE * (1.0 + hit_flash * 0.22)
			queue_redraw()
		return
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	var was_slowed := slow_timer > 0.0
	slow_timer = maxf(0.0, slow_timer - delta)
	if was_slowed and slow_timer <= 0.0:
		slow_multiplier = 1.0
		modulate = Color.WHITE
	var here := global_position
	var target := _nearest_living_player(players, here)
	var target_position := target.global_position
	# Predict ranged aim and the mole's committed dash before their warning.
	if leads_its_target:
		target_position += target.current_input.limit_length() * target.move_speed * 0.65
	if hunts_the_chain:
		target_position = (players[0].global_position + players[1].global_position) * 0.5
	var speed_scale := slow_multiplier if slow_timer > 0.0 else 1.0
	var had_telegraph := charge_windup > 0.0 or shooter_windup > 0.0 or chain_windup > 0.0 or boss_slam_windup > 0.0
	var had_flash := hit_flash > 0.0
	if had_flash:
		hit_flash = maxf(0.0, hit_flash - delta / HIT_FLASH_TIME)
		scale = Vector2.ONE * (1.0 + hit_flash * 0.22)

	match archetype:
		"rat_runner":
			_step_runner(target_position, speed_scale, delta)
		"wasp", "owl":
			_step_shooter(target_position, speed_scale, delta)
			if archetype == "wasp" and shooter_windup <= 0.0:
				position += here.direction_to(target_position).orthogonal() * move_speed * speed_scale * delta * 0.65
			if boss:
				boss_attack_timer -= delta
				if boss_attack_timer <= 0.0:
					boss_attack_timer = 4.0
					shooter_windup = 1.0
					telegraph_direction = here.direction_to(target_position)
		"mole":
			_step_charger(target_position, speed_scale, delta)
		"hedgehog":
			var hedgehog_direction := here.direction_to(target_position)
			position += hedgehog_direction * move_speed * speed_scale * delta
			rotation = hedgehog_direction.angle()
		"charger":
			_step_charger(target_position, speed_scale, delta)
		"shooter":
			_step_shooter(target_position, speed_scale, delta)
		"brute":
			if boss:
				_step_boss(players, target_position, speed_scale, delta)
			else:
				var direction := here.direction_to(target_position)
				position += direction * move_speed * speed_scale * delta
				rotation = direction.angle()
		_:
			var direction := here.direction_to(target_position)
			position += direction * move_speed * speed_scale * delta
			rotation = direction.angle()

	if archetype == "chain_hunter":
		_try_damage_chain(players, delta)
	else:
		_try_contact_damage(players)
	# Runs here rather than at the top of the step so it reads the heading this
	# step just chose. It used to be driven by NOTIFICATION_LOCAL_TRANSFORM_CHANGED,
	# which meant every position write in the step — and every push the crowd
	# separation applied afterwards — re-entered GDScript to recompute a facing
	# that only depends on rotation. At a few hundred bodies that was thousands of
	# callbacks a frame to answer the same question this one line answers once.
	if is_instance_valid(body_sprite):
		_update_body_facing()
		# Skipped entirely in the ordinary case. Almost every body on the field is
		# neither enraged nor mid-flash on any given tick, and writing white over
		# white is still a property write across the engine boundary.
		if boss_enraged:
			body_sprite.modulate = ENRAGED_TINT
			_tinted = true
		elif hit_flash > 0.0:
			body_sprite.modulate = Color.WHITE.lerp(HIT_TINT, hit_flash * 0.8)
			_tinted = true
		elif _tinted:
			body_sprite.modulate = Color.WHITE
			_tinted = false
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
	# Sprite tint/scale handle hit flashes without rebuilding health/elite art.
	telegraphing = charge_windup > 0.0 or shooter_windup > 0.0 or chain_windup > 0.0 or boss_slam_windup > 0.0
	if had_telegraph or telegraphing:
		queue_redraw()


func _step_runner(target_position: Vector2, speed_scale: float, delta: float) -> void:
	if charge_timer > 0.0:
		charge_timer = maxf(0.0, charge_timer - delta)
		# A runner pursues through a broad turn, unlike the mole's straight dash.
		# Reversing or dashing across its nose exploits the limited turn rate.
		var heading := rotate_toward(charge_direction.angle(), global_position.direction_to(target_position).angle(), delta * 1.8)
		charge_direction = Vector2.from_angle(heading)
		position += charge_direction * maxf(340.0, move_speed * 2.8) * speed_scale * delta
		rotation = charge_direction.angle()
		return
	if charge_windup > 0.0:
		charge_windup -= delta
		if charge_windup <= 0.0: charge_timer = 1.5
		return
	behavior_timer -= delta
	rotation = global_position.direction_to(target_position).angle()
	position += Vector2.from_angle(rotation) * move_speed * speed_scale * delta
	if behavior_timer <= 0.0 and global_position.distance_squared_to(target_position) < 680.0 * 680.0:
		behavior_timer = 1.8
		charge_direction = global_position.direction_to(target_position)
		telegraph_direction = charge_direction
		charge_windup = 0.75


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
			if archetype == "owl":
				for angle in [-0.32, 0.32]:
					ranged_attack.emit(global_position, telegraph_direction.rotated(angle), 10.0)
				if boss:
					for index in 8:
						ranged_attack.emit(global_position, Vector2.from_angle(index * TAU / 8.0), 12.0)
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
	# From the third boss on, the enrage threshold moves up rather than the
	# stat block simply growing: the late bosses spend most of the fight in the
	# pattern set the early ones only reach at half health.
	var enrage_at := 0.5 + float(maxi(1, boss_rank) - 1) * 0.12
	if not boss_enraged and health <= max_health * minf(0.9, enrage_at):
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
	# Read once after the step has moved us, then compared squared: the loop ran
	# for every body on the field every tick, and a square root per player per
	# body is a real cost for a test that never needed the actual distance.
	var at := global_position
	for player in players:
		var reach := radius + player.radius
		if at.distance_squared_to(player.global_position) <= reach * reach:
			# Passing our position lets 가시의 견장 send part of the hit back.
			if player.hurt(contact_damage * player.contact_pressure, at):
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


## Takes the caller's own position so the hot path does not pay for the global
## transform twice more on top of the read it has already made.
func _nearest_living_player(players: Array[ChainPlayer], from: Vector2 = global_position) -> ChainPlayer:
	if players[0].downed and not players[1].downed:
		return players[1]
	if players[1].downed and not players[0].downed:
		return players[0]
	if from.distance_squared_to(players[1].global_position) < from.distance_squared_to(players[0].global_position):
		return players[1]
	return players[0]


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * ratio)


func take_damage(amount: float, source_player := -1, source_weapon := "") -> bool:
	if dead or not active:
		return false
	if archetype == "hedgehog": amount *= 0.72
	# Report only health that was genuinely removed. This is both the honest
	# damage number and the authority for lifesteal, so a 999,999-point purge on
	# a ten-health enemy cannot become a full-party heal exploit.
	var actual_damage := minf(maxf(0.0, amount), health)
	health -= amount
	last_damage_player = source_player
	last_damage_weapon = source_weapon
	damage_taken.emit(self, actual_damage)
	hit_flash = 1.0
	scale = Vector2(1.22, 1.22)
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


func _draw() -> void:
	redraw_count += 1
	# Wings, claws and spines are now part of the painted sprite itself.
	if charge_windup > 0.0:
		var charge_alpha := 0.25 + sin(charge_windup * 34.0) * 0.12
		if archetype == "rat_runner":
			draw_circle(Vector2.ZERO, radius + 12, Color(1.0, 0.55, 0.15, charge_alpha))
			draw_arc(Vector2.ZERO, radius + 16, -1.0, 1.0, 16, Color("ffbf69"), 4, true)
		else:
			draw_line(Vector2.ZERO, telegraph_direction.rotated(-rotation) * 240.0, Color(1.0, 0.25, 0.2, charge_alpha), 12.0, true)
	if shooter_windup > 0.0:
		draw_dashed_line(Vector2.ZERO, telegraph_direction.rotated(-rotation) * 320.0, Color(1.0, 0.35, 0.42, 0.8), 3.0, 10.0, true)
		if archetype == "owl":
			for angle in [-0.32, 0.32]:
				draw_dashed_line(Vector2.ZERO, telegraph_direction.rotated(angle - rotation) * 320.0, Color(1.0, 0.55, 0.25, 0.6), 2.0, 12.0, true)
			if boss: draw_arc(Vector2.ZERO, radius + 28.0, 0, TAU, 40, Color(1.0, 0.55, 0.25, 0.7), 6.0, true)
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
	if not boss and (health_ratio < 0.99 or elite):
		draw_rect(Rect2(-radius, -radius - 10.0, radius * 2.0, 4.0), Color("351d3c"))
		draw_rect(Rect2(-radius, -radius - 10.0, radius * 2.0 * health_ratio, 4.0), Color("80ed99"))
