extends SceneTree

const MetaScript := preload("res://scripts/systems/meta_progression.gd")
const PlayerScript := preload("res://scripts/entities/player.gd")
const MainScene := preload("res://scenes/main.tscn")
const SAVE := "res://tests/tmp/meta_progression_test.cfg"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var meta := MetaScript.new() as MetaProgression
	meta.save_path = SAVE
	_check(meta.points == 0, "a fresh profile starts empty")
	_check(meta.award_clear() == MetaProgression.CLEAR_REWARD, "a clear grants the advertised reward")
	var first_cost := meta.cost("might")
	_check(meta.purchase("might"), "an affordable permanent upgrade can be bought")
	_check(meta.rank("might") == 1 and meta.points == MetaProgression.CLEAR_REWARD - first_cost, "purchase spends points and raises one rank")
	meta.mark_discovered("comet_storm")

	var loaded := MetaScript.new() as MetaProgression
	loaded.save_path = SAVE
	loaded.load_progress()
	_check(loaded.rank("might") == 1, "ranks persist")
	_check(loaded.is_discovered("comet_storm"), "fusion discoveries persist")
	loaded.points = 10000
	var cap := int(MetaProgression.by_id("luck")["max_rank"])
	while loaded.purchase("luck"):
		pass
	_check(loaded.rank("luck") == cap and loaded.cost("luck") == 0, "every permanent upgrade has a hard cap")

	var player := PlayerScript.new() as ChainPlayer
	player.max_health = 100.0
	player.health = 100.0
	var might_before := player.might
	loaded.apply_to_player(player)
	_check(player.might > might_before, "bought power is applied to the next run")
	_check(loaded.team_luck_bonus() == cap, "team utility bonuses are exposed to the run")

	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.meta_progression.save_path = SAVE
	main.meta_progression.points = 0
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	main.run_stats["bosses"] = WaveDirector.BOSS_COUNT - 1
	main._end_run(true)
	_check(main.run_reward == 0, "a synthetic or incomplete victory grants no clear currency")
	main.game_over = false
	main.run_stats["bosses"] = WaveDirector.BOSS_COUNT
	main._end_run(true)
	_check(main.run_reward == MetaProgression.CLEAR_REWARD, "the real five-boss clear pays the result-screen reward")
	paused = false
	main.free()
	player.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if failures.is_empty():
		print("META_PROGRESSION_PASS: clear reward, capped purchases, save/load and next-run bonuses")
		quit(0)
	else:
		for failure in failures:
			push_error("META_PROGRESSION_FAIL: " + failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
