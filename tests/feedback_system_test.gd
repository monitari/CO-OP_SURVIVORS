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
	await _test_cue_coverage()
	await _test_music_slot()

	if failures.is_empty():
		print("FEEDBACK_TEST_PASS: damage numbers capped, tones cached, players pooled, every cue defined, music slot loops")
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
	_check(feedback._tone_cache.size() == 1, "repeated plays of the same cue synthesize its waveform only once")
	_check(feedback.get_children().size() >= 1, "at least one AudioStreamPlayer was created to play the cue")

	var first_stream: AudioStreamWAV = feedback._tone_cache["xp"]
	feedback.play_cue("xp")
	_check(feedback._tone_cache["xp"] == first_stream, "the cached stream instance is reused, not regenerated, on later calls")

	feedback.play_cue("hit")
	feedback.play_cue("level")
	_check(feedback._tone_cache.size() == 3, "a new cue still gets synthesized and cached on first use")

	# "xp" is a ~45ms tone; wait long enough for every player to finish and
	# return itself to the pool, then confirm the next play reuses one of
	# those idle players instead of creating a fresh node.
	var players_before := feedback.get_children().size()
	await create_timer(0.3).timeout
	_check(feedback._player_pool.size() > 0, "finished players return themselves to the pool")
	feedback.play_cue("xp")
	var players_after := feedback.get_children().size()
	_check(players_after <= players_before, "reusing a pooled player does not grow the node count")

	feedback.queue_free()
	await process_frame


## play_cue() ignores an id it does not know, so a cue the game asks for but
## never defined fails completely silently. Every id the rest of the codebase
## can request has to exist in the table, and every weapon and field drop has
## to have one — those are generated from ids rather than written literally.
func _test_cue_coverage() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	var weapon_ids := ["homing", "lightning", "flame", "frost", "scythe", "chain"]
	for weapon_id in weapon_ids:
		_check(feedback.CUE_PARAMS.has("weapon_" + weapon_id), "weapon %s has its own fire cue" % weapon_id)

	var item_ids := ["heal", "magnet", "chain_repair", "purge"]
	for item_id in item_ids:
		_check(feedback.CUE_PARAMS.has("item_" + item_id), "field drop %s has its own pickup cue" % item_id)

	for cue in ["hit", "kill", "xp", "level", "warning", "down", "revive", "resonance",
			"boss", "victory", "chain_overcharge", "chain_overload", "chain_repaired", "boss_enrage"]:
		_check(feedback.CUE_PARAMS.has(cue), "cue %s is defined" % cue)

	# Distinct cues must actually sound different, or naming them separately
	# buys nothing.
	var signatures: Dictionary = {}
	for weapon_id in weapon_ids:
		var params: Dictionary = feedback.CUE_PARAMS["weapon_" + weapon_id]
		signatures["%s|%s|%s" % [params.get("freq"), params.get("to", params.get("freq")), params.get("wave", "sine")]] = true
	_check(signatures.size() == weapon_ids.size(), "all six weapon cues are audibly distinct (%d unique of %d)" % [signatures.size(), weapon_ids.size()])

	# Every cue must render without error and produce actual samples.
	for cue in feedback.CUE_PARAMS.keys():
		feedback._cue_cooldowns.clear()
		feedback.play_cue(String(cue))
	_check(feedback._tone_cache.size() == feedback.CUE_PARAMS.size(), "every defined cue renders to a stream")
	for cue in feedback._tone_cache.keys():
		var stream: AudioStreamWAV = feedback._tone_cache[cue]
		_check(stream.data.size() > 0, "cue %s renders non-empty audio" % cue)

	feedback.queue_free()
	await process_frame


func _test_music_slot() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	feedback.play_music("field")
	_check(feedback._current_track == "field", "the music slot tracks what should be playing")
	_check(feedback._music_cache.has("field"), "the field bed is rendered on first use")
	var field_stream: AudioStreamWAV = feedback._music_cache["field"]
	_check(field_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "a music bed loops instead of playing once")
	_check(field_stream.data.size() > 0, "the field bed renders non-empty audio")

	feedback.play_music("field")
	_check(feedback._music_cache["field"] == field_stream, "replaying the same track reuses the rendered bed")

	feedback.play_music("boss")
	_check(feedback._current_track == "boss", "the boss bed replaces the field bed")
	_check(feedback._music_cache.has("boss"), "the boss bed renders on first use")

	feedback.stop_music()
	_check(feedback._current_track.is_empty(), "stopping clears the current track")

	# The toggle must not lose which bed belongs to the current situation.
	feedback.play_music("field")
	feedback.music_enabled = false
	feedback.refresh_music()
	_check(not feedback._music_player.playing, "muting music actually stops playback")
	feedback.music_enabled = true
	feedback.refresh_music()
	_check(feedback._current_track == "field", "unmuting resumes the track that was playing")

	_check(AudioServer.get_bus_index("SFX") >= 0, "an SFX bus exists for cue playback")
	_check(AudioServer.get_bus_index("Music") >= 0, "a Music bus exists so the two can be balanced apart")

	feedback.queue_free()
	await process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
