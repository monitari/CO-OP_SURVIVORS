class_name WaveDirector
extends Node2D

const EnemyScript := preload("res://scripts/enemy.gd")

var enemy_pool: Array[ChaserEnemy] = []
var spawn_timer := 0.0
var elite_timer := 35.0
var boss_spawned := false
var enemy_cap := 420


func step(delta: float, elapsed: float, center: Vector2, active_count: int) -> Array[ChaserEnemy]:
	var spawned: Array[ChaserEnemy] = []
	spawn_timer -= delta
	elite_timer -= delta
	if active_count >= enemy_cap:
		return spawned
	if elapsed >= 120.0 and not boss_spawned:
		boss_spawned = true
		spawned.append(_acquire_enemy("brute", elapsed / 30.0, center, true, true))
	if elite_timer <= 0.0:
		elite_timer = 38.0
		spawned.append(_acquire_enemy(_pick_archetype(elapsed), elapsed / 30.0, center, true, false))
	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.1, 0.58 - elapsed * 0.0035)
		var count := 2 if elapsed > 45.0 and randf() < 0.35 else 1
		for index in count:
			if active_count + spawned.size() >= enemy_cap:
				break
			spawned.append(_acquire_enemy(_pick_archetype(elapsed), elapsed / 30.0, center, false, false))
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
	if elapsed >= 18.0 and roll < 0.55:
		return "charger"
	return "chaser"
