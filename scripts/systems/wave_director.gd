class_name WaveDirector
extends Node2D

## Spawning used to be one continuous trickle whose interval shrank with time,
## which gave a run no shape at all — no build-up, no relief, nothing to read
## as "here comes another one". It now runs in waves: an assault stretch that
## opens with a surge, then a short lull before the next wave escalates.

signal wave_started(wave_index: int, is_surge_wave: bool)
signal wave_calm_started(wave_index: int)

const EnemyScript := preload("res://scripts/enemy.gd")

const WAVE_DURATION := 20.0
const WAVE_CALM := 5.0 ## Trailing quiet stretch of each wave, for regrouping and picking up drops.
const SURGE_EVERY := 3 ## Every third wave opens with a much larger surge.
const BOSS_TIME := 120.0
const OPENING_SPAWN_INTERVAL := 0.78
const SECOND_WAVE_SPAWN_INTERVAL := 0.68
const FIRST_REINFORCEMENT_COUNT := 3
const CHARGER_UNLOCK_TIME := 30.0

var enemy_pool: Array[ChaserEnemy] = []
var spawn_timer := 0.0
var elite_timer := 35.0
var boss_spawned := false
var enemy_cap := 420

var wave_index := 0
var wave_elapsed := 0.0
var in_calm := false


## The assault stretch tightens as waves go on, but never below a floor — the
## enemy cap and the cull radius are what bound the fight, not the interval.
func spawn_interval() -> float:
	# The first two waves are the learning window: the pair is still on one
	# weapon each and has not yet had time to establish armor, recovery, or a
	# resonance. Ease the stream here, then join the original curve from wave 2.
	if wave_index == 0:
		return OPENING_SPAWN_INTERVAL
	if wave_index == 1:
		return SECOND_WAVE_SPAWN_INTERVAL
	return maxf(0.16, 0.62 - float(wave_index) * 0.045)


func is_surge_wave(index: int) -> bool:
	return index > 0 and index % SURGE_EVERY == 0


func step(delta: float, elapsed: float, center: Vector2, active_count: int) -> Array[ChaserEnemy]:
	var spawned: Array[ChaserEnemy] = []
	var difficulty := elapsed / 30.0

	# --- wave clock ---------------------------------------------------------
	wave_elapsed += delta
	if wave_elapsed >= WAVE_DURATION:
		wave_elapsed -= WAVE_DURATION
		wave_index += 1
		in_calm = false
		wave_started.emit(wave_index, is_surge_wave(wave_index))
		# A wave opens with a burst so it lands as an event rather than as a
		# slightly faster trickle.
		# The first boundary used to combine four instant reinforcements with
		# the charger unlock two seconds earlier. Three plain chasers make it a
		# readable escalation without turning the end of the tutorial into a wall.
		var surge := 10 if is_surge_wave(wave_index) else (FIRST_REINFORCEMENT_COUNT if wave_index == 1 else 4)
		for index in surge:
			if active_count + spawned.size() >= enemy_cap:
				break
			spawned.append(_acquire_enemy(_pick_archetype(elapsed), difficulty, center, false, false))
	elif not in_calm and wave_elapsed >= WAVE_DURATION - WAVE_CALM:
		in_calm = true
		wave_calm_started.emit(wave_index)

	spawn_timer -= delta
	elite_timer -= delta
	if active_count >= enemy_cap:
		return spawned

	if elapsed >= BOSS_TIME and not boss_spawned:
		boss_spawned = true
		spawned.append(_acquire_enemy("brute", difficulty, center, true, true))
	# Elites and the boss ignore the lull — the calm is a break from the swarm,
	# not a guarantee that nothing happens.
	if elite_timer <= 0.0:
		elite_timer = 38.0
		spawned.append(_acquire_enemy(_pick_archetype(elapsed), difficulty, center, true, false))

	if in_calm:
		return spawned

	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval()
		var count := 2 if wave_index >= 2 and randf() < 0.4 else 1
		for index in count:
			if active_count + spawned.size() >= enemy_cap:
				break
			spawned.append(_acquire_enemy(_pick_archetype(elapsed), difficulty, center, false, false))
	return spawned


func release_enemy(enemy: ChaserEnemy) -> void:
	if enemy in enemy_pool:
		return
	enemy.deactivate()
	enemy_pool.append(enemy)


func _acquire_enemy(archetype: String, difficulty: float, center: Vector2, elite: bool, boss: bool) -> ChaserEnemy:
	var enemy: ChaserEnemy
	if enemy_pool.is_empty():
		enemy = EnemyScript.new() as ChaserEnemy
		add_child(enemy)
	else:
		enemy = enemy_pool.pop_back()
	enemy.setup(difficulty, archetype, elite, boss)
	var angle := randf() * TAU
	var distance := randf_range(610.0, 760.0) if not boss else 820.0
	enemy.position = center + Vector2.from_angle(angle) * distance
	return enemy


func _pick_archetype(elapsed: float) -> String:
	var roll := randf()
	if elapsed >= 55.0 and roll < 0.16:
		return "chain_hunter"
	if elapsed >= 36.0 and roll < 0.34:
		return "shooter"
	if elapsed >= CHARGER_UNLOCK_TIME and roll < 0.55:
		return "charger"
	return "chaser"
