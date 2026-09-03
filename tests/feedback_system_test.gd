extends SceneTree

const FeedbackScript := preload("res://scripts/systems/feedback_system.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "FEEDBACK_TEST_FAIL", 30.0)
	call_deferred("_run")


func _run() -> void:
	await _test_damage_number_cap()
	await _test_tone_cache_and_player_pool()

	if failures.is_empty():
		print("FEEDBACK_TEST_PASS: damage numbers capped per frame, tones cached, players pooled")
		quit(0)
	else:
		for failure in failures:
			push_error("FEEDBACK_TEST_FAIL: " + failure)
		quit(1)


## An AoE hitting dozens of enemies used to spawn one Label + one Tween per hit
## in the same physics tick. show_damage() now drops anything past
## MAX_DAMAGE_NUMBERS_PER_FRAME instead of piling all of them on screen, and
## the counter has to actually reset every physics tick or the cap would only
## ever fire once for the whole run.
func _test_damage_number_cap() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	for i in feedback.MAX_DAMAGE_NUMBERS_PER_FRAME + 12:
		feedback.show_damage(Vector2.ZERO, 10.0)
	var labels := 0
	for child in feedback.get_children():
		if child is Label:
			labels += 1
	_check(labels == feedback.MAX_DAMAGE_NUMBERS_PER_FRAME, "a single tick caps spawned damage labels at %d (got %d)" % [feedback.MAX_DAMAGE_NUMBERS_PER_FRAME, labels])

	feedback._physics_process(0.0) # simulate the next physics tick's reset
	for i in feedback.MAX_DAMAGE_NUMBERS_PER_FRAME:
		feedback.show_damage(Vector2.ZERO, 10.0)
	labels = 0
	for child in feedback.get_children():
		if child is Label:
			labels += 1
	_check(labels == feedback.MAX_DAMAGE_NUMBERS_PER_FRAME * 2, "the cap resets on the next physics tick instead of staying latched")

	feedback.queue_free()
	await process_frame


## A "kill" cue has no cooldown, so an AoE clearing many enemies at once used
## to re-synthesize the same waveform and spin up a fresh AudioStreamPlayer
## node every single time. Confirms the synthesis happens once per distinct
## cue and finished players return to a pool instead of being freed.
func _test_tone_cache_and_player_pool() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	feedback.play_cue("xp")
	feedback.play_cue("xp")
	feedback.play_cue("xp")
	_check(feedback.tone_cache.size() == 1, "repeated plays of the same cue synthesize its waveform only once")
	_check(feedback.get_children().size() >= 1, "at least one AudioStreamPlayer was created to play the cue")

	var first_stream: AudioStreamWAV = feedback.tone_cache["xp"]
	feedback.play_cue("xp")
	_check(feedback.tone_cache["xp"] == first_stream, "the cached stream instance is reused, not regenerated, on later calls")

	feedback.play_cue("hit")
	feedback.play_cue("level")
	_check(feedback.tone_cache.size() == 3, "a new cue still gets synthesized and cached on first use")

	# "xp" is a ~45ms tone; wait long enough for every player to finish and
	# return itself to the pool, then confirm the next play reuses one of
	# those idle players instead of creating a fresh node.
	var players_before := feedback.get_children().size()
	await create_timer(0.3).timeout
	_check(feedback.player_pool.size() > 0, "finished players return themselves to the pool")
	feedback.play_cue("xp")
	var players_after := feedback.get_children().size()
	_check(players_after <= players_before, "reusing a pooled player does not grow the node count")

	feedback.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
