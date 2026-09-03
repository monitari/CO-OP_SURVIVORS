class_name FeedbackSystem
extends Node2D

var sound_enabled := true
var damage_numbers_enabled := true
var hit_sound_cooldown := 0.0
var damage_numbers_this_frame := 0

## An AoE hitting dozens of enemies used to spawn one Label + one Tween per
## hit in the same physics tick. The number is still legible well below this
## many stacked on screen at once, so the rest are simply dropped rather than
## queued or batched.
const MAX_DAMAGE_NUMBERS_PER_FRAME := 8

## frequency (Hz), duration (s), volume (0-1) per cue name — the single source
## of truth for both playback and the one-time synthesis in _play_tone().
const CUE_PARAMS := {
	"hit": [170.0, 0.045, 0.12],
	"kill": [290.0, 0.075, 0.2],
	"xp": [720.0, 0.045, 0.1],
	"level": [880.0, 0.18, 0.18],
	"warning": [210.0, 0.16, 0.16],
	"down": [105.0, 0.32, 0.24],
	"revive": [660.0, 0.22, 0.2],
	"resonance": [1040.0, 0.28, 0.22],
	"boss": [82.0, 0.45, 0.28],
	"victory": [1320.0, 0.42, 0.22],
}

var tone_cache: Dictionary = {}
var player_pool: Array[AudioStreamPlayer] = []


func _physics_process(_delta: float) -> void:
	damage_numbers_this_frame = 0


func _process(delta: float) -> void:
	hit_sound_cooldown = maxf(0.0, hit_sound_cooldown - delta)


func play_cue(cue: String) -> void:
	if not sound_enabled:
		return
	if cue == "hit":
		if hit_sound_cooldown > 0.0:
			return
		hit_sound_cooldown = 0.045
	var params: Array = CUE_PARAMS.get(cue, [440.0, 0.08, 0.2])
	_play_tone(cue, float(params[0]), float(params[1]), float(params[2]))


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


## Synthesizes each distinct cue's waveform once and reuses the resulting
## AudioStreamWAV across every future playback instead of re-encoding a fresh
## PCM buffer per call — "kill" has no cooldown, so an AoE clearing 20 enemies
## used to encode 20 buffers and spin up 20 AudioStreamPlayer nodes in one
## frame. Multiple AudioStreamPlayers can safely share one stream resource for
## simultaneous playback, so caching costs nothing when several cues overlap.
func _play_tone(cue: String, frequency: float, duration: float, volume: float) -> void:
	if not tone_cache.has(cue):
		tone_cache[cue] = _synthesize_tone(frequency, duration, volume)
	var player := _acquire_player()
	player.stream = tone_cache[cue]
	player.play()


func _synthesize_tone(frequency: float, duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := maxi(1, int(duration * mix_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(mix_rate)
		var decay := pow(1.0 - float(index) / float(sample_count), 2.0)
		var wave := sin(TAU * frequency * time) + sin(TAU * frequency * 1.5 * time) * 0.22
		var sample := int(clampf(wave * decay * volume, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


## Reuses an idle player instead of creating and freeing an AudioStreamPlayer
## node for every single cue. The pool only grows as far as actual polyphony
## requires (concurrent overlapping cues), then those players are recycled.
func _acquire_player() -> AudioStreamPlayer:
	for player in player_pool:
		if not player.playing:
			player_pool.erase(player)
			return player
	var player := AudioStreamPlayer.new()
	player.volume_db = -5.0
	player.finished.connect(func() -> void: player_pool.append(player))
	add_child(player)
	return player
