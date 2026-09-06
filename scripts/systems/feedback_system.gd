class_name FeedbackSystem
extends Node2D

## All audio is synthesised at runtime — the project ships no sound files — so
## a cue is described by a waveform, a frequency sweep and an envelope rather
## than by a sample. Each distinct cue is rendered once and cached; playback
## reuses a pool of AudioStreamPlayers so a busy fight does not allocate.

const MIX_RATE := 22050

## An AoE hitting dozens of enemies used to spawn one Label + one Tween per
## hit in the same physics tick. The number is still legible well below this
## many stacked on screen at once, so the rest are simply dropped.
const MAX_DAMAGE_NUMBERS_PER_FRAME := 8

## Cue definition fields:
##   freq  starting frequency in Hz
##   to    sweep target (omitted = steady tone)
##   dur   length in seconds
##   vol   peak amplitude, 0-1
##   wave  "sine" | "square" | "saw" | "noise"
##   gap   minimum seconds before this cue may sound again
##
## `gap` is what keeps the mix readable: with two players carrying up to three
## weapons each, six independent cooldowns can land in the same handful of
## frames, and without a floor between repeats the result is mush.
const CUE_PARAMS := {
	"weapon_boomerang": {"freq": 460.0, "to": 220.0, "dur": 0.14, "vol": 0.08, "wave": "sine", "gap": 0.2},
	"weapon_milk": {"freq": 520.0, "to": 300.0, "dur": 0.26, "vol": 0.09, "wave": "sine", "gap": 0.4},
	# --- combat feedback -----------------------------------------------------
	"hit": {"freq": 170.0, "dur": 0.045, "vol": 0.10, "wave": "square", "gap": 0.045},
	"kill": {"freq": 290.0, "to": 200.0, "dur": 0.075, "vol": 0.15, "wave": "sine", "gap": 0.04},
	"xp": {"freq": 720.0, "to": 900.0, "dur": 0.045, "vol": 0.08, "wave": "sine", "gap": 0.03},
	"level": {"freq": 660.0, "to": 990.0, "dur": 0.22, "vol": 0.18, "wave": "sine"},
	"warning": {"freq": 210.0, "to": 150.0, "dur": 0.16, "vol": 0.16, "wave": "saw"},
	"down": {"freq": 150.0, "to": 70.0, "dur": 0.36, "vol": 0.24, "wave": "saw"},
	"revive": {"freq": 440.0, "to": 880.0, "dur": 0.24, "vol": 0.20, "wave": "sine"},
	# Short and downward so it reads as a movement, not as a hit.
	# Browsing and committing need to sound different, or a menu that two
	# people drive at once gives no feedback about which of them just acted.
	"select": {"freq": 620.0, "to": 880.0, "dur": 0.09, "vol": 0.12, "wave": "sine"},
	"reroll": {"freq": 300.0, "to": 700.0, "dur": 0.18, "vol": 0.15, "wave": "square"},
	"dash": {"freq": 720.0, "to": 300.0, "dur": 0.13, "vol": 0.13, "wave": "sine"},
	"resonance": {"freq": 780.0, "to": 1560.0, "dur": 0.30, "vol": 0.22, "wave": "sine"},
	"boss": {"freq": 96.0, "to": 62.0, "dur": 0.50, "vol": 0.28, "wave": "saw"},
	"victory": {"freq": 880.0, "to": 1320.0, "dur": 0.45, "vol": 0.22, "wave": "sine"},

	# --- one per weapon, so a loadout is audible as well as visible ----------
	"weapon_homing": {"freq": 520.0, "to": 760.0, "dur": 0.09, "vol": 0.09, "wave": "sine", "gap": 0.07},
	"weapon_lightning": {"freq": 980.0, "to": 260.0, "dur": 0.065, "vol": 0.085, "wave": "noise", "gap": 0.28},
	"weapon_flame": {"freq": 400.0, "to": 180.0, "dur": 0.12, "vol": 0.09, "wave": "noise", "gap": 0.08},
	"weapon_frost": {"freq": 1100.0, "to": 1500.0, "dur": 0.16, "vol": 0.08, "wave": "sine", "gap": 0.08},
	"weapon_scythe": {"freq": 700.0, "to": 220.0, "dur": 0.11, "vol": 0.11, "wave": "noise", "gap": 0.08},
	"weapon_chain": {"freq": 160.0, "to": 130.0, "dur": 0.16, "vol": 0.09, "wave": "saw", "gap": 0.08},
	"weapon_orbit": {"freq": 880.0, "to": 620.0, "dur": 0.18, "vol": 0.08, "wave": "sine", "gap": 0.10},
	"weapon_lance": {"freq": 360.0, "to": 1160.0, "dur": 0.13, "vol": 0.10, "wave": "square", "gap": 0.08},
	"weapon_mine": {"freq": 240.0, "to": 420.0, "dur": 0.12, "vol": 0.09, "wave": "square", "gap": 0.10},
	"weapon_gravity": {"freq": 180.0, "to": 72.0, "dur": 0.26, "vol": 0.12, "wave": "sine", "gap": 0.12},
	"weapon_starpiercer": {"freq": 620.0, "to": 1380.0, "dur": 0.17, "vol": 0.11, "wave": "square", "gap": 0.08},
	"weapon_thunder_god": {"freq": 1320.0, "to": 190.0, "dur": 0.24, "vol": 0.13, "wave": "square", "gap": 0.10},
	"weapon_supernova": {"freq": 520.0, "to": 95.0, "dur": 0.28, "vol": 0.13, "wave": "noise", "gap": 0.12},
	"weapon_absolute_zero": {"freq": 1450.0, "to": 760.0, "dur": 0.28, "vol": 0.10, "wave": "sine", "gap": 0.12},
	"weapon_black_moon": {"freq": 820.0, "to": 105.0, "dur": 0.20, "vol": 0.13, "wave": "noise", "gap": 0.10},
	"weapon_stigmata": {"freq": 210.0, "to": 680.0, "dur": 0.24, "vol": 0.12, "wave": "saw", "gap": 0.10},
	"weapon_celestial": {"freq": 980.0, "to": 490.0, "dur": 0.30, "vol": 0.10, "wave": "sine", "gap": 0.12},
	"weapon_judgement": {"freq": 460.0, "to": 1540.0, "dur": 0.20, "vol": 0.12, "wave": "square", "gap": 0.10},
	"weapon_ruin_garden": {"freq": 190.0, "to": 510.0, "dur": 0.22, "vol": 0.11, "wave": "saw", "gap": 0.12},
	"weapon_event_horizon": {"freq": 125.0, "to": 42.0, "dur": 0.38, "vol": 0.15, "wave": "sine", "gap": 0.14},

	# Secondary layers mark delayed phases instead of asking one fire sound to
	# explain an entire multi-stage weapon.
	"mine_blast": {"freq": 120.0, "to": 48.0, "dur": 0.24, "vol": 0.18, "wave": "noise", "gap": 0.06},
	"gravity_pull": {"freq": 260.0, "to": 95.0, "dur": 0.34, "vol": 0.09, "wave": "sine", "gap": 0.10},
	"gravity_collapse": {"freq": 78.0, "to": 42.0, "dur": 0.22, "vol": 0.18, "wave": "square", "gap": 0.08},
	"chain_snap": {"freq": 310.0, "to": 1280.0, "dur": 0.10, "vol": 0.10, "wave": "square", "gap": 0.07},

	# --- one per field drop, so a pickup says which pickup it was ------------
	"item_heal": {"freq": 523.0, "to": 784.0, "dur": 0.28, "vol": 0.20, "wave": "sine"},
	"item_magnet": {"freq": 300.0, "to": 1200.0, "dur": 0.30, "vol": 0.18, "wave": "sine"},
	"item_guard": {"freq": 660.0, "to": 990.0, "dur": 0.4, "vol": 0.20, "wave": "sine"},
	"item_frenzy": {"freq": 220.0, "to": 700.0, "dur": 0.34, "vol": 0.22, "wave": "saw"},
	"item_time_stop": {"freq": 900.0, "to": 180.0, "dur": 0.62, "vol": 0.22, "wave": "sine"},
	"item_chain_ward": {"freq": 400.0, "to": 880.0, "dur": 0.42, "vol": 0.22, "wave": "square"},
	"item_purge": {"freq": 300.0, "to": 90.0, "dur": 0.40, "vol": 0.24, "wave": "noise"},
	"item_chest": {"freq": 392.0, "to": 1174.0, "dur": 0.48, "vol": 0.22, "wave": "square"},
	"chest_open": {"freq": 523.0, "to": 1568.0, "dur": 0.55, "vol": 0.20, "wave": "sine"},

	# --- chain and boss state changes ---------------------------------------
	"chain_overcharge": {"freq": 500.0, "to": 720.0, "dur": 0.18, "vol": 0.15, "wave": "sine"},
	"chain_overload": {"freq": 260.0, "to": 80.0, "dur": 0.40, "vol": 0.26, "wave": "saw"},
	"chain_repaired": {"freq": 600.0, "to": 900.0, "dur": 0.25, "vol": 0.18, "wave": "sine"},
	"boss_enrage": {"freq": 130.0, "to": 70.0, "dur": 0.55, "vol": 0.30, "wave": "saw"},
}

## Looping beds, rendered from note lists the same way cues are rendered from
## sweeps. Entries are [start seconds, frequency, duration, volume, waveform].
const MUSIC_TRACKS := {
	"field": {
		"length": 4.0,
		"notes": [
			[0.0, 110.0, 1.30, 0.10, "saw"], [2.0, 110.0, 1.30, 0.10, "saw"],
			[0.0, 440.0, 0.35, 0.05, "sine"], [0.5, 523.25, 0.35, 0.05, "sine"],
			[1.0, 659.25, 0.35, 0.05, "sine"], [1.5, 523.25, 0.35, 0.05, "sine"],
			[2.0, 440.0, 0.35, 0.05, "sine"], [2.5, 659.25, 0.35, 0.05, "sine"],
			[3.0, 392.0, 0.35, 0.05, "sine"], [3.5, 659.25, 0.35, 0.05, "sine"],
		],
	},
	"boss": {
		"length": 3.0,
		"notes": [
			[0.0, 73.42, 1.40, 0.13, "saw"], [1.5, 73.42, 1.40, 0.13, "saw"],
			[0.0, 293.66, 0.20, 0.05, "square"], [0.75, 415.30, 0.20, 0.05, "square"],
			[1.5, 293.66, 0.20, 0.05, "square"], [2.25, 415.30, 0.20, 0.05, "square"],
		],
	},
	# A second field theme appears after odd-numbered boss checkpoints. A bass
	# walk and syncopated bell melody keep it recognisably feline/playful while
	# giving the back half of a run a new pulse.
	"moonlight": {
		"length": 8.0,
		"notes": [
			[0.0, 98.0, 0.72, 0.09, "saw"], [1.0, 123.47, 0.72, 0.09, "saw"],
			[2.0, 146.83, 0.72, 0.09, "saw"], [3.0, 123.47, 0.72, 0.09, "saw"],
			[4.0, 110.0, 0.72, 0.09, "saw"], [5.0, 146.83, 0.72, 0.09, "saw"],
			[6.0, 164.81, 0.72, 0.09, "saw"], [7.0, 123.47, 0.72, 0.09, "saw"],
			[0.0, 587.33, 0.24, 0.045, "sine"], [0.75, 783.99, 0.18, 0.045, "sine"],
			[1.5, 659.25, 0.30, 0.05, "sine"], [2.5, 880.0, 0.20, 0.045, "sine"],
			[3.25, 739.99, 0.30, 0.05, "sine"], [4.0, 659.25, 0.22, 0.045, "sine"],
			[5.0, 987.77, 0.18, 0.05, "sine"], [5.75, 880.0, 0.26, 0.045, "sine"],
			[6.5, 739.99, 0.28, 0.05, "sine"], [7.25, 587.33, 0.38, 0.05, "sine"],
		],
	},
}

var sound_enabled := true
var music_enabled := true
var damage_numbers_enabled := true
var damage_numbers_this_frame := 0

var _cue_cooldowns: Dictionary = {}
var _tone_cache: Dictionary = {}
var _music_cache: Dictionary = {}
var _player_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_track := ""


func _ready() -> void:
	_ensure_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -14.0
	add_child(_music_player)


## Separate SFX and Music buses so the two can be balanced (and later exposed
## as sliders) independently. Created at runtime because the project has no
## bus layout resource to ship.
func _ensure_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _physics_process(_delta: float) -> void:
	damage_numbers_this_frame = 0


func _process(delta: float) -> void:
	for cue in _cue_cooldowns.keys():
		var remaining: float = float(_cue_cooldowns[cue]) - delta
		if remaining <= 0.0:
			_cue_cooldowns.erase(cue)
		else:
			_cue_cooldowns[cue] = remaining


func play_cue(cue: String) -> void:
	if not sound_enabled:
		return
	if _cue_cooldowns.has(cue):
		return
	var params: Dictionary = CUE_PARAMS.get(cue, {})
	if params.is_empty():
		return
	var gap := float(params.get("gap", 0.0))
	if gap > 0.0:
		_cue_cooldowns[cue] = gap
	if not _tone_cache.has(cue):
		_tone_cache[cue] = _render_cue(params)
	var player := _acquire_player()
	player.stream = _tone_cache[cue]
	player.play()


## Convenience wrappers so callers name the thing that happened rather than
## assembling cue ids inline.
func play_item_cue(item_id: String) -> void:
	play_cue("item_" + item_id)


func play_music(track_id: String) -> void:
	if track_id == _current_track:
		return
	_current_track = track_id
	if not music_enabled or not MUSIC_TRACKS.has(track_id):
		_music_player.stop()
		return
	if not _music_cache.has(track_id):
		_music_cache[track_id] = _render_music(MUSIC_TRACKS[track_id])
	_music_player.stream = _music_cache[track_id]
	_music_player.play()


func stop_music() -> void:
	_current_track = ""
	_music_player.stop()


## Re-applies the music toggle without losing which track should be playing,
## so flipping it off and on again resumes the right bed.
func refresh_music() -> void:
	var track := _current_track
	_current_track = ""
	if music_enabled and not track.is_empty():
		play_music(track)
	else:
		_current_track = track
		_music_player.stop()


func show_damage(world_position: Vector2, amount: float, color: Color = Color.WHITE) -> void:
	if not damage_numbers_enabled:
		return
	if damage_numbers_this_frame >= MAX_DAMAGE_NUMBERS_PER_FRAME:
		return
	damage_numbers_this_frame += 1
	var label := Label.new()
	label.text = str(int(round(amount)))
	label.position = world_position - Vector2(28.0, 34.0)
	label.size = Vector2(56.0, 30.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.z_index = 20
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0.0, -30.0), 0.48)
	tween.tween_property(label, "modulate:a", 0.0, 0.48).set_delay(0.12)
	tween.chain().tween_callback(label.queue_free)


## Frequency is swept by accumulating phase rather than by evaluating
## sin(TAU * f * t): with a changing f the latter warps the whole waveform
## instead of gliding the pitch.
func _render_cue(params: Dictionary) -> AudioStreamWAV:
	var duration := float(params["dur"])
	var start_freq := float(params["freq"])
	var end_freq := float(params.get("to", start_freq))
	var volume := float(params["vol"])
	var shape := String(params.get("wave", "sine"))

	var sample_count := maxi(1, int(duration * MIX_RATE))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		var freq := lerpf(start_freq, end_freq, progress)
		phase += TAU * freq / float(MIX_RATE)
		var decay := pow(1.0 - progress, 2.0)
		var value := _wave_sample(shape, phase) * decay * volume
		bytes.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _make_stream(bytes, false)


func _render_music(track: Dictionary) -> AudioStreamWAV:
	var length := float(track["length"])
	var sample_count := maxi(1, int(length * MIX_RATE))
	var mix := PackedFloat32Array()
	mix.resize(sample_count)

	for entry in track["notes"]:
		var note: Array = entry
		var start := int(float(note[0]) * MIX_RATE)
		var freq := float(note[1])
		var note_samples := int(float(note[2]) * MIX_RATE)
		var volume := float(note[3])
		var shape := String(note[4])
		var phase := 0.0
		for offset in note_samples:
			var index := start + offset
			if index >= sample_count:
				break
			phase += TAU * freq / float(MIX_RATE)
			# Soft attack as well as decay: a hard edge on a looping bed
			# reads as a click every time the note starts.
			var progress := float(offset) / float(note_samples)
			var envelope := minf(1.0, progress * 12.0) * pow(1.0 - progress, 1.5)
			mix[index] += _wave_sample(shape, phase) * envelope * volume

	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in sample_count:
		bytes.encode_s16(index * 2, int(clampf(mix[index], -1.0, 1.0) * 32767.0))
	return _make_stream(bytes, true)


func _make_stream(bytes: PackedByteArray, looping: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(bytes.size() / 2)
	return stream


func _wave_sample(shape: String, phase: float) -> float:
	match shape:
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"saw":
			return fmod(phase / TAU, 1.0) * 2.0 - 1.0
		"noise":
			return randf_range(-1.0, 1.0)
	# The default keeps the original two-partial sine, which is what every
	# pre-existing cue was tuned against.
	return sin(phase) + sin(phase * 1.5) * 0.22


## Reuses an idle player instead of creating and freeing an AudioStreamPlayer
## node for every single cue. The pool only grows as far as actual polyphony
## requires, then those players are recycled.
func _acquire_player() -> AudioStreamPlayer:
	for player in _player_pool:
		if not player.playing:
			_player_pool.erase(player)
			return player
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.volume_db = -5.0
	player.finished.connect(func() -> void: _player_pool.append(player))
	add_child(player)
	return player
