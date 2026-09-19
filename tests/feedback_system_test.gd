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
	await _test_synthesis_quality()
	await _test_weapon_fire_and_impact()
	await _test_batching_and_voices()
	await _test_chain_limit()
	await _test_cat_palette()

	if failures.is_empty():
		print("FEEDBACK_TEST_PASS: damage numbers capped, tones cached, players pooled, every cue defined, music slot loops, cues are a cat-themed stereo palette at 48k, fire and impact differ per weapon, combat cues batch under a voice cap, the leash only sounds at its limit")
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
	# Counted on the batched field rather than as Label children: a number is
	# no longer a node (DamageNumberField), which is the whole point of it.
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	for i in feedback.MAX_DAMAGE_NUMBERS_PER_FRAME + 12:
		feedback.show_damage(Vector2.ZERO, 10.0)
	var labels: int = feedback.live_damage_numbers()
	_check(labels == feedback.MAX_DAMAGE_NUMBERS_PER_FRAME, "a single tick caps spawned damage numbers at %d (got %d)" % [feedback.MAX_DAMAGE_NUMBERS_PER_FRAME, labels])

	feedback._physics_process(0.0) # simulate the next physics tick's reset
	for i in feedback.MAX_DAMAGE_NUMBERS_PER_FRAME:
		feedback.show_damage(Vector2.ZERO, 10.0)
	labels = feedback.live_damage_numbers()
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

	var weapon_ids := [
		"homing", "lightning", "flame", "frost", "scythe", "chain", "orbit", "lance", "mine", "gravity",
		"starpiercer", "thunder_god", "supernova", "absolute_zero", "black_moon",
		"stigmata", "celestial", "judgement", "ruin_garden", "event_horizon",
	]
	for weapon_id in weapon_ids:
		_check(feedback.CUE_PARAMS.has("weapon_" + weapon_id), "weapon %s has its own fire cue" % weapon_id)

	var item_ids := ["heal", "magnet", "chain_ward", "purge", "chest"]
	for item_id in item_ids:
		_check(feedback.CUE_PARAMS.has("item_" + item_id), "field drop %s has its own pickup cue" % item_id)

	for cue in ["hit", "kill", "xp", "level", "warning", "down", "revive", "resonance",
			"boss", "victory", "chain_overcharge", "chain_overload", "chain_repaired", "boss_enrage",
			"mine_blast", "gravity_pull", "gravity_collapse", "chain_snap", "chest_open"]:
		_check(feedback.CUE_PARAMS.has(cue), "cue %s is defined" % cue)

	# Distinct cues must actually sound different, or naming them separately
	# buys nothing.
	var signatures: Dictionary = {}
	for weapon_id in weapon_ids:
		var params: Dictionary = feedback.CUE_PARAMS["weapon_" + weapon_id]
		signatures["%s|%s|%s" % [params.get("freq"), params.get("to", params.get("freq")), params.get("wave", "sine")]] = true
	_check(signatures.size() == weapon_ids.size(), "all weapon cues are audibly distinct (%d unique of %d)" % [signatures.size(), weapon_ids.size()])

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
	for track_id: String in feedback.MUSIC_TRACKS.keys():
		for note: Array in (feedback.MUSIC_TRACKS[track_id] as Dictionary)["notes"]:
			_check(String(note[4]) not in ["saw", "square"],
				"music track %s has no repeating hard-edged pulse" % track_id)

	feedback.play_music("field")
	_check(feedback._music_cache["field"] == field_stream, "replaying the same track reuses the rendered bed")

	feedback.play_music("boss")
	_check(feedback._current_track == "boss", "the boss bed replaces the field bed")
	_check(feedback._music_cache.has("boss"), "the boss bed renders on first use")
	feedback.play_music("moonlight")
	_check(feedback._current_track == "moonlight", "the alternate field theme has its own music slot")
	_check(feedback._music_cache.has("moonlight"), "the alternate field theme renders on first use")

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


## The mix used to be sharp for three reasons that are all synthesis rather than
## balance: half the sample rate it needed, an edge on the front of every cue,
## and a hard clamp at the top that manufactured harmonics of its own. None of
## the three is audible in a headless test, but all three leave marks in the
## samples.
func _test_synthesis_quality() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	_check(feedback.MIX_RATE == 48000, "cues are synthesised at 48 kHz")
	for cue in ["hit", "impact_zap", "weapon_thunder_god", "chain_strained", "down"]:
		feedback._cue_cooldowns.clear()
		feedback.play_cue(cue)
		var stream: AudioStreamWAV = feedback._tone_cache[cue]
		_check(stream.mix_rate == feedback.MIX_RATE, "cue %s is rendered at the mix rate" % cue)
		var samples := stream.data
		var first := samples.decode_s16(0)
		_check(absf(float(first)) < 2600.0,
			"cue %s opens on a ramp rather than a step (%d)" % [cue, first])
		var last := samples.decode_s16(samples.size() - 2)
		_check(absf(float(last)) < 2600.0, "cue %s lands on silence rather than a step" % cue)
		# A hard clamp shows up as samples pinned at full scale. The soft knee
		# never reaches the rail at all, so any sample there is a clamp.
		var railed := 0
		for index in int(samples.size() / 2):
			if absi(samples.decode_s16(index * 2)) >= 32760:
				railed += 1
		_check(railed == 0, "cue %s is shaped by the soft knee, never clipped (%d samples at the rail)" % [cue, railed])

	# The band-limiting correction has to be doing something at the edges of a
	# cycle and nothing in the middle, or an edged waveform is still naive.
	_check(absf(FeedbackScript._poly_blep(0.5, 0.02)) < 0.0001,
		"the band-limiting correction leaves the middle of a cycle alone")
	_check(absf(FeedbackScript._poly_blep(0.005, 0.02)) > 0.1
		and absf(FeedbackScript._poly_blep(0.995, 0.02)) > 0.1,
		"the band-limiting correction rounds both edges of a cycle")
	_check(absf(FeedbackScript._soft_clip(4.0)) <= 1.0 and absf(FeedbackScript._soft_clip(-4.0)) <= 1.0,
		"the soft knee bounds anything handed to it")

	# The beds are allowed their own rate, but they have to declare it, or they
	# would play back at the wrong pitch.
	feedback.play_music("moonlight")
	var bed: AudioStreamWAV = feedback._music_cache["moonlight"]
	_check(bed.mix_rate == feedback.MUSIC_MIX_RATE, "a music bed carries the rate it was rendered at")

	feedback.queue_free()
	await process_frame


## Firing a weapon and connecting with it are two different events, and the
## roster is big enough that "which weapon" has to survive both. Every weapon
## has its own fire cue and an impact class, and the two halves are built so
## they cannot be mistaken for each other.
func _test_weapon_fire_and_impact() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	var weapon_ids := [
		"boomerang", "milk", "homing", "lightning", "flame", "frost", "scythe", "chain",
		"orbit", "lance", "mine", "gravity", "starpiercer", "thunder_god", "supernova",
		"absolute_zero", "black_moon", "stigmata", "celestial", "judgement",
		"ruin_garden", "event_horizon",
	]
	var classes: Dictionary = {}
	for weapon_id in weapon_ids:
		var impact: String = FeedbackScript.impact_cue(weapon_id)
		_check(impact != "hit", "weapon %s lands on an impact class of its own" % weapon_id)
		_check(feedback.CUE_PARAMS.has(impact), "impact cue %s is defined" % impact)
		classes[impact] = true
		var fire: Dictionary = feedback.CUE_PARAMS["weapon_" + weapon_id]
		var landed: Dictionary = feedback.CUE_PARAMS[impact]
		# An impact that sounded like the shot that caused it tells the pair
		# nothing about whether the shot connected. Every impact is the shorter
		# of the pair, and none of them sweeps the way a cast does.
		_check(float(landed["dur"]) < float(fire["dur"]),
			"%s lands shorter than it fires" % weapon_id)
	_check(classes.size() >= 6,
		"the roster spreads across enough impact characters to tell apart (%d)" % classes.size())

	# And the classes themselves have to be distinct, or grouping the roster
	# into them bought nothing.
	var signatures: Dictionary = {}
	for impact: String in classes.keys():
		var params: Dictionary = feedback.CUE_PARAMS[impact]
		signatures["%s|%s|%s" % [params["freq"], params["to"], params["wave"]]] = true
	_check(signatures.size() == classes.size(),
		"every impact class is audibly distinct (%d of %d)" % [signatures.size(), classes.size()])

	# An unclassified weapon is ordinary rather than silent.
	_check(FeedbackScript.impact_cue("a_weapon_that_does_not_exist") == "hit",
		"an unclassified weapon still makes a sound")

	feedback.queue_free()
	await process_frame


## One area weapon can land on forty enemies inside a single physics tick. Forty
## copies of one waveform starting a frame apart is not forty hits, it is one
## loud smear, so they are counted and flushed as one cue — and whatever does
## get through still has to fit inside a fixed number of voices.
func _test_batching_and_voices() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	for i in 40:
		feedback.report_hit("scythe")
	for i in 12:
		feedback.report_kill()
	feedback.report_xp()
	_check(feedback._batched.size() == 3, "a tick's reports collapse to one entry per group")
	_check(int(feedback._batched["impact_slash"]) == 40, "the group remembers how many there were")
	_check(feedback._tone_cache.is_empty(), "nothing is played until the tick is flushed")

	feedback._physics_process(0.0)
	_check(feedback._batched.is_empty(), "the flush clears the tick")
	_check(feedback._tone_cache.size() == 3, "forty hits, twelve kills and a mote cost three cues")
	_check(feedback._cue_cooldowns.has("impact_slash"), "the flushed cue took its own cooldown")

	# Reporting with sound off must not quietly build a backlog that fires the
	# moment it is turned back on.
	feedback.sound_enabled = false
	for i in 20:
		feedback.report_hit("flame")
	_check(feedback._batched.is_empty(), "reports are dropped outright while sound is off")
	feedback.sound_enabled = true

	# The voice cap. Every distinct cue in the table is asked for at once, which
	# is far more than any real tick, and the node count has to hold.
	for cue in feedback.CUE_PARAMS.keys():
		feedback._cue_cooldowns.clear()
		feedback.play_cue(String(cue))
	_check(feedback._voices.size() <= feedback.MAX_VOICES,
		"the voice budget holds under every cue at once (%d of %d)" % [feedback._voices.size(), feedback.MAX_VOICES])

	# And the cap costs the mix its least important sound rather than its most
	# recent one: a downed partner is heard over chip damage, never behind it.
	feedback._player_pool.clear()
	for player in feedback._voices:
		feedback._voice_priority[player.get_instance_id()] = feedback._priority_of("hit")
	_check(feedback._acquire_player(feedback._priority_of("down")) != null,
		"an important cue takes a voice from chip damage when the budget is full")
	feedback._player_pool.clear()
	for player in feedback._voices:
		feedback._voice_priority[player.get_instance_id()] = feedback._priority_of("down")
	_check(feedback._acquire_player(feedback._priority_of("hit")) == null,
		"chip damage never takes a voice from something that matters more")
	_check(feedback._priority_of("down") > feedback._priority_of("hit")
		and feedback._priority_of("resonance") > feedback._priority_of("xp"),
		"the things a run turns on outrank the things a run is full of")

	feedback.queue_free()
	await process_frame


## The leash gets exactly one cue, and it fires when the leash actually reaches
## its limit. Lower tension bands remain silent.
func _test_chain_limit() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	_check(feedback.CUE_PARAMS.has("chain_strained"), "reaching the end of the leash has a cue")
	for retired in ["chain_tension_1", "chain_tension_2", "chain_tension_3", "chain_release"]:
		_check(not feedback.CUE_PARAMS.has(retired),
			"the per-band tension creak %s is absent" % retired)

	feedback.play_chain_limit(3, 2)
	_check(feedback._tone_cache.has("chain_strained"), "arriving at the limit sounds")
	feedback._tone_cache.clear()
	feedback._cue_cooldowns.clear()

	for from_stage in 4:
		for to_stage in 4:
			if to_stage >= 3 and from_stage < 3:
				continue
			feedback.play_chain_limit(to_stage, from_stage)
	_check(feedback._tone_cache.is_empty(),
		"lower bands, holding the limit and easing off are silent")
	_check(float(feedback.CUE_PARAMS["chain_strained"]["gap"]) >= 1.0,
		"the limit cue cannot chatter faster than once a second")

	feedback.queue_free()
	await process_frame


## The palette is a cat's rather than an oscillator's, and that is a thing worth
## holding in place: the combat cues are bells, chimes, plucked string, paws and
## air, and the moment one of them goes back to being a bare low sawtooth is the
## moment the game starts sounding rude again.
func _test_cat_palette() -> void:
	var feedback := FeedbackScript.new() as FeedbackSystem
	root.add_child(feedback)
	await process_frame

	var raw := ["saw", "square"]
	var voiced := 0
	for id: String in feedback.CUE_PARAMS.keys():
		var shape := String((feedback.CUE_PARAMS[id] as Dictionary).get("wave", "sine"))
		_check(shape not in raw, "cue %s is an instrument rather than a bare %s" % [id, shape])
		if shape == "mew":
			voiced += 1
	_check(voiced > 0 and voiced <= 3,
		"a mew is kept for the few moments that are about the pair, not spent everywhere (%d)" % voiced)

	# Width. Every cue is two renderings a few cents apart, and the beating
	# between them is most of what keeps a synthesised note from sounding flat.
	feedback.play_cue("kill")
	var cue: AudioStreamWAV = feedback._tone_cache["kill"]
	_check(cue.stereo, "cues are rendered in stereo")
	var differs := false
	for frame in mini(2000, int(cue.data.size() / 4)):
		if cue.data.decode_s16(frame * 4) != cue.data.decode_s16(frame * 4 + 2):
			differs = true
			break
	_check(differs, "the two channels are genuinely different rather than a doubled mono cue")

	# A bell is a stack of partials dying at different rates, which is the whole
	# reason it sounds like an object instead of a beep.
	_check(feedback.BELL_PARTIALS.size() >= 3 and feedback.BELL_DECAYS.size() == feedback.BELL_PARTIALS.size(),
		"a bell has partials, each with its own rate of dying away")
	_check(float(feedback.BELL_PARTIALS[1]) != 2.0,
		"a bell's partials are inharmonic, which is what makes it metal rather than organ")

	feedback.queue_free()
	await process_frame
