class_name FeedbackSystem
extends Node2D

var sound_enabled := true
var damage_numbers_enabled := true
var hit_sound_cooldown := 0.0


func _process(delta: float) -> void:
	hit_sound_cooldown = maxf(0.0, hit_sound_cooldown - delta)


func play_cue(cue: String) -> void:
	if not sound_enabled:
		return
	var frequency := 440.0
	var duration := 0.08
	var volume := 0.2
	match cue:
		"hit":
			if hit_sound_cooldown > 0.0:
				return
			hit_sound_cooldown = 0.045
			frequency = 170.0
			duration = 0.045
			volume = 0.12
		"kill":
			frequency = 290.0
			duration = 0.075
		"xp":
			frequency = 720.0
			duration = 0.045
			volume = 0.1
		"level":
			frequency = 880.0
			duration = 0.18
			volume = 0.18
		"warning":
			frequency = 210.0
			duration = 0.16
			volume = 0.16
		"down":
			frequency = 105.0
			duration = 0.32
			volume = 0.24
		"revive":
			frequency = 660.0
			duration = 0.22
		"resonance":
			frequency = 1040.0
			duration = 0.28
			volume = 0.22
		"boss":
			frequency = 82.0
			duration = 0.45
			volume = 0.28
		"victory":
			frequency = 1320.0
			duration = 0.42
			volume = 0.22
	_play_tone(frequency, duration, volume)


func show_damage(world_position: Vector2, amount: float, color: Color = Color.WHITE) -> void:
	if not damage_numbers_enabled:
		return
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


func _play_tone(frequency: float, duration: float, volume: float) -> void:
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
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -5.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
