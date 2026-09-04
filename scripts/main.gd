extends Node2D

const PlayerScene := preload("res://scripts/player.gd")
const ProjectileScene := preload("res://scripts/projectile.gd")
const CharacterData := preload("res://scripts/character_catalog.gd")
const EnemyProjectileScript := preload("res://scripts/enemy_projectile.gd")
const SpatialGridScript := preload("res://scripts/systems/enemy_spatial_grid.gd")
const ProgressionScript := preload("res://scripts/systems/progression_system.gd")
const ExperienceScript := preload("res://scripts/systems/experience_system.gd")
const WaveDirectorScript := preload("res://scripts/systems/wave_director.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const WeaponControllerScript := preload("res://scripts/systems/weapon_controller.gd")
const FeedbackScript := preload("res://scripts/systems/feedback_system.gd")
const SettingsScript := preload("res://scripts/systems/settings_system.gd")

const CHAIN_WARNING_RATIO := 0.82
const CHAIN_RESIST_RATIO := 0.70
const RUN_BOSS_TIME := 120.0
const DOWNED_TOW_SHARE := 0.88
const WEAPON_LOADOUT_CAP := 3

# Overcharge is a loan against the chain, not a free damage bonus. Holding the
# survivors apart past CHAIN_WARNING_RATIO burns integrity; only closing back
# inside CHAIN_RESIST_RATIO pays it back. The gap between the two ratios is a
# neutral band so ordinary spacing neither drains nor refills.
const CHAIN_INTEGRITY_MAX := 100.0
const CHAIN_DRAIN_AT_WARNING := 9.0
const CHAIN_DRAIN_AT_LIMIT := 26.0
const CHAIN_INTEGRITY_RECOVERY := 14.0
const CHAIN_OVERLOAD_DAMAGE := 12.0
const CHAIN_OVERLOAD_PENALTY := 0.8
const CHAIN_OVERLOAD_CLEAR := 45.0

## How hard the boss's Chain Slam attack drains integrity directly, separate
## from — and stackable with — the overcharge drain above. Roughly one second
## of max-tension overcharge drain in a single hit: painful if the chain is
## already strained, survivable if it was not.
const BOSS_SLAM_INTEGRITY_DRAIN := 28.0

var players: Array[ChainPlayer] = []
var enemies: Array[ChaserEnemy] = []
var chain_line: Line2D
var chain_glow: Line2D
var world_camera: Camera2D
var spatial_grid: EnemySpatialGrid
var progression: SharedProgression
var experience_system: ExperienceSystem
var wave_director: WaveDirector
var resonance_system: ResonanceSystem
var weapon_controller: WeaponController
var feedback: FeedbackSystem
var settings: GameSettings
var hud_layer: CanvasLayer
var hud_label: Label
var xp_bar: ProgressBar
var p1_status_label: Label
var p2_status_label: Label
var p1_health_bar: ProgressBar
var p2_health_bar: ProgressBar
var chain_bar: ProgressBar
var chain_integrity_bar: ProgressBar
var chain_status_label: Label
var resonance_status_label: Label
var boss_bar: ProgressBar
var boss_label: Label
var help_label: Label
var message_label: Label
var level_overlay: ColorRect
var level_title: Label
var level_card_labels: Array = [[], []] ## level_card_labels[slot] = Array[Label], one per offered choice (up to 3)
var p1_level_footer: Label
var p2_level_footer: Label
var character_overlay: ColorRect
var character_title: Label
var character_p1_label: Label
var character_p2_label: Label
var resonance_overlay: ColorRect
var resonance_title: Label
var resonance_choices_label: Label
var character_roster_label: Label
var character_synergy_label: Label
var result_overlay: ColorRect
var result_label: Label
var pause_overlay: ColorRect
var pause_label: Label
var lobby_overlay: ColorRect
var lobby_title: Label
var lobby_p1_label: Label
var lobby_p2_label: Label
var tutorial_label: Label
var build_inspect_label: Label
var p1_edge_indicator: Label
var p2_edge_indicator: Label
var threat_edge_indicator: Label

var elapsed := 0.0
var kills := 0
var game_over := false
var level_up_active := false
var character_select_active := true
var resonance_vote_active := false
var pause_active := false
var lobby_active := true
var run_won := false
var boss_enemy: ChaserEnemy
var camera_shake := 0.0
var screen_shake_enabled := true
var previous_chain_stage := 0
var last_input_gamepad: Array[bool] = [false, false]
var lobby_joined: Array[bool] = [false, false]
var lobby_devices: Array[int] = [-1, -1]
var lobby_device_names: Array[String] = ["키보드", "키보드"]
var lobby_input_cooldown := 0.0
var upgrade_cursors: Array[int] = [0, 0]
var selected_upgrade_indices: Array[int] = [-1, -1] ## -1 = still choosing; >=0 = locked in but not yet applied until both players lock
var rerolls_remaining: Array[int] = [1, 1] ## Spent across the whole run, not refilled per level-up
var last_upgrade_choice_keys: Array = [[], []] ## Previous level-up's offered option keys per player, so the exact same 3 don't repeat back to back
var resonance_cursors: Array[int] = [0, 0]
var build_inspect_active := false
var tutorial_active := false
var tutorial_step := 0
var tutorial_start_kills := 0
var tutorial_start_xp := 0
var quick_ping_cooldowns: Array[float] = [0.0, 0.0]
var chain_combo_cooldown := 0.0
var boss_chain_damage_cooldown := 0.0
var pacing_announced: Dictionary = {}
var last_countdown_second := -1
var run_stats := {"revives": 0, "pings": 0, "overcharge_time": 0.0, "chain_bursts": 0, "resonance_casts": 0}

var chain_max_length := 370.0
var chain_integrity := CHAIN_INTEGRITY_MAX
var chain_overloaded := false

var character_catalog: Array[Dictionary] = []
var selected_character_indices: Array[int] = [0, 1]
var character_confirmed: Array[bool] = [false, false]
var selected_characters: Array[Dictionary] = [{}, {}]

## weapon_loadouts[player_index] is an Array[Dictionary], one entry per owned
## weapon (max WEAPON_LOADOUT_CAP). Each dictionary is self-contained — it
## carries its own weapon_id/weapon_name/tags/color alongside its numeric
## stats — because a picked-up weapon belongs to whichever character it came
## from, not to the player's own character, so it can't borrow those fields
## from selected_characters[i] the way the single starting weapon used to.
var weapon_loadouts: Array = [[], []]
var attack_timers: Array = [[], []] ## attack_timers[player_index][weapon_slot], 1:1 with weapon_loadouts

var p1_choices: Array[Dictionary] = []
var p2_choices: Array[Dictionary] = []
var resonance_candidates: Array[Dictionary] = []
var resonance_votes: Array[int] = [-1, -1]
var resonance_vote_message := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	randomize()
	settings = SettingsScript.new() as GameSettings
	settings.load_settings()
	_setup_input_map()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	character_catalog = CharacterData.all_characters()
	_create_world()
	_create_players()
	feedback = FeedbackScript.new() as FeedbackSystem
	add_child(feedback)
	feedback.sound_enabled = settings.sound_enabled
	feedback.damage_numbers_enabled = settings.damage_numbers_enabled
	screen_shake_enabled = settings.screen_shake_enabled
	weapon_controller = WeaponControllerScript.new() as WeaponController
	add_child(weapon_controller)
	weapon_controller.configure(players, weapon_loadouts, spatial_grid)
	_create_hud()
	_begin_lobby()
	queue_redraw()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if device < 0 or device > 1:
		return
	last_input_gamepad[device] = connected
	if not connected and not character_select_active and not game_over and not level_up_active and not resonance_vote_active:
		_set_pause(true)
		pause_label.text = "P%d 컨트롤러 연결이 끊어졌습니다.\n\n다시 연결한 뒤 ESC / START로 계속하세요.\n키보드 조작도 사용할 수 있습니다." % (device + 1)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var device := clampi(event.device, 0, 1)
		last_input_gamepad[device] = true
	elif event is InputEventKey and event.pressed:
		last_input_gamepad = [false, false]
	if lobby_active and event.is_pressed() and not event.is_echo():
		if event is InputEventJoypadButton:
			_join_lobby_with_gamepad(event.device)
		elif event is InputEventKey:
			var key: int = (event as InputEventKey).physical_keycode
			if key in [KEY_W, KEY_A, KEY_S, KEY_D]:
				_join_lobby_slot(0, -1, "키보드 WASD")
			elif key in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
				_join_lobby_slot(1, -1, "키보드 방향키")
	if event.is_action_pressed("toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if lobby_active:
		lobby_input_cooldown = maxf(0.0, lobby_input_cooldown - delta)
		if lobby_input_cooldown <= 0.0 and Input.is_action_just_pressed("pause") and (lobby_joined[0] or lobby_joined[1]):
			_begin_lobby()
		return
	if game_over:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return
	if pause_active:
		_handle_pause_input()
		return
	if character_select_active:
		lobby_input_cooldown = maxf(0.0, lobby_input_cooldown - delta)
		if lobby_input_cooldown > 0.0:
			return
		_handle_character_select_input()
		return
	if resonance_vote_active:
		_handle_resonance_vote_input()
		return
	if level_up_active:
		_handle_level_up_input()
		return
	if Input.is_action_just_pressed("pause"):
		_set_pause(true)
		return

	elapsed += delta
	weapon_controller.elapsed = elapsed
	for player in players:
		player.step_movement(delta)
	_apply_chain_constraint()
	_update_revives(delta)
	_update_chain_integrity(delta)
	_update_chain_visual()
	_update_camera(delta)

	for candidate in enemies.duplicate():
		var enemy := candidate as ChaserEnemy
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.step(players, delta)
	spatial_grid.rebuild(enemies)
	experience_system.step(players, delta)

	for player_index in 2:
		for weapon_slot in weapon_loadouts[player_index].size():
			attack_timers[player_index][weapon_slot] -= delta

	var midpoint := (players[0].position + players[1].position) * 0.5
	for enemy in wave_director.step(delta, elapsed, midpoint, enemies.size()):
		_register_enemy(enemy)
	for player_index in 2:
		for weapon_slot in weapon_loadouts[player_index].size():
			if attack_timers[player_index][weapon_slot] <= 0.0:
				weapon_controller.perform_attack(player_index, weapon_slot, _tension_damage_multiplier())
				attack_timers[player_index][weapon_slot] = float(weapon_loadouts[player_index][weapon_slot]["cooldown"])
	for resonance in resonance_system.step(delta):
		weapon_controller.perform_resonance(resonance, _tension_damage_multiplier())
	if is_instance_valid(boss_enemy) and not boss_enemy.dead:
		boss_bar.value = boss_enemy.health

	_update_hud()
	if (players[0].downed and players[1].downed) or players[0].bleedout_remaining <= 0.0 or players[1].bleedout_remaining <= 0.0:
		_end_run()


func _draw() -> void:
	var grid_color := Color(0.15, 0.22, 0.35, 0.24)
	for coordinate in range(-2400, 2401, 96):
		draw_line(Vector2(coordinate, -2400), Vector2(coordinate, 2400), grid_color, 1.0)
		draw_line(Vector2(-2400, coordinate), Vector2(2400, coordinate), grid_color, 1.0)
	draw_circle(Vector2.ZERO, 115.0, Color(0.2, 0.35, 0.55, 0.08))
	draw_arc(Vector2.ZERO, 115.0, 0.0, TAU, 64, Color(0.25, 0.55, 0.85, 0.3), 2.0)


func _create_world() -> void:
	spatial_grid = SpatialGridScript.new() as EnemySpatialGrid
	progression = ProgressionScript.new() as SharedProgression
	add_child(progression)
	experience_system = ExperienceScript.new() as ExperienceSystem
	experience_system.experience_collected.connect(_gain_shared_xp)
	add_child(experience_system)
	wave_director = WaveDirectorScript.new() as WaveDirector
	add_child(wave_director)
	resonance_system = ResonanceScript.new() as ResonanceSystem
	add_child(resonance_system)

	chain_glow = Line2D.new()
	chain_glow.width = 18.0
	chain_glow.default_color = Color(0.25, 0.75, 1.0, 0.12)
	chain_glow.z_index = -2
	chain_glow.add_point(Vector2.ZERO)
	chain_glow.add_point(Vector2.ZERO)
	add_child(chain_glow)

	chain_line = Line2D.new()
	chain_line.width = 5.0
	chain_line.default_color = Color("43d9ff")
	chain_line.z_index = -1
	chain_line.add_point(Vector2.ZERO)
	chain_line.add_point(Vector2.ZERO)
	add_child(chain_line)

	world_camera = Camera2D.new()
	world_camera.enabled = true
	world_camera.position_smoothing_enabled = true
	world_camera.position_smoothing_speed = 7.0
	add_child(world_camera)


func _create_players() -> void:
	var player_one := PlayerScene.new() as ChainPlayer
	player_one.setup(1, Color("43d9ff"))
	player_one.position = Vector2(-105.0, 0.0)
	add_child(player_one)
	player_one.damaged.connect(_on_player_damaged)
	player_one.downed_started.connect(_on_player_downed)
	player_one.revived_player.connect(_on_player_revived)
	players.append(player_one)

	var player_two := PlayerScene.new() as ChainPlayer
	player_two.setup(2, Color("9b5de5"))
	player_two.position = Vector2(105.0, 0.0)
	add_child(player_two)
	player_two.damaged.connect(_on_player_damaged)
	player_two.downed_started.connect(_on_player_downed)
	player_two.revived_player.connect(_on_player_revived)
	players.append(player_two)


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	hud_layer = layer
	add_child(layer)

	_make_hud_panel(layer, Vector2(18.0, 14.0), Vector2(365.0, 96.0), Color(0.02, 0.04, 0.09, 0.88))
	_make_hud_panel(layer, Vector2(897.0, 14.0), Vector2(365.0, 96.0), Color(0.02, 0.04, 0.09, 0.88))
	_make_hud_panel(layer, Vector2(430.0, 14.0), Vector2(420.0, 182.0), Color(0.02, 0.04, 0.09, 0.82))

	p1_status_label = Label.new()
	p1_status_label.position = Vector2(34.0, 24.0)
	p1_status_label.size = Vector2(330.0, 52.0)
	p1_status_label.add_theme_font_size_override("font_size", 20)
	p1_status_label.add_theme_color_override("font_color", Color("43d9ff"))
	layer.add_child(p1_status_label)
	p1_health_bar = _create_bar(layer, Vector2(34.0, 80.0), Vector2(330.0, 13.0), Color("43d9ff"))

	p2_status_label = Label.new()
	p2_status_label.position = Vector2(913.0, 24.0)
	p2_status_label.size = Vector2(330.0, 52.0)
	p2_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_status_label.add_theme_font_size_override("font_size", 20)
	p2_status_label.add_theme_color_override("font_color", Color("b892ff"))
	layer.add_child(p2_status_label)
	p2_health_bar = _create_bar(layer, Vector2(913.0, 80.0), Vector2(330.0, 13.0), Color("b892ff"))

	hud_label = Label.new()
	hud_label.position = Vector2(440.0, 23.0)
	hud_label.size = Vector2(400.0, 70.0)
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_color", Color("e7f6ff"))
	layer.add_child(hud_label)

	chain_bar = _create_bar(layer, Vector2(455.0, 111.0), Vector2(370.0, 12.0), Color("43d9ff"))
	chain_bar.max_value = 100.0
	chain_integrity_bar = _create_bar(layer, Vector2(455.0, 127.0), Vector2(370.0, 6.0), Color("80ed99"))
	chain_integrity_bar.max_value = CHAIN_INTEGRITY_MAX
	chain_integrity_bar.value = CHAIN_INTEGRITY_MAX
	chain_status_label = Label.new()
	chain_status_label.position = Vector2(415.0, 140.0)
	chain_status_label.size = Vector2(450.0, 32.0)
	chain_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_status_label.add_theme_font_size_override("font_size", 17)
	layer.add_child(chain_status_label)

	resonance_status_label = Label.new()
	resonance_status_label.position = Vector2(415.0, 169.0)
	resonance_status_label.size = Vector2(450.0, 32.0)
	resonance_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_status_label.add_theme_font_size_override("font_size", 17)
	resonance_status_label.add_theme_color_override("font_color", Color("e4c1f9"))
	layer.add_child(resonance_status_label)

	boss_label = Label.new()
	boss_label.position = Vector2(390.0, 200.0)
	boss_label.size = Vector2(500.0, 28.0)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 19)
	boss_label.add_theme_color_override("font_color", Color("fff275"))
	boss_label.text = "결속 파괴자"
	boss_label.visible = false
	layer.add_child(boss_label)
	boss_bar = _create_bar(layer, Vector2(390.0, 228.0), Vector2(500.0, 12.0), Color("ef476f"))
	boss_bar.visible = false

	xp_bar = _create_bar(layer, Vector2(20.0, 695.0), Vector2(1240.0, 17.0), Color("80ed99"))
	xp_bar.show_percentage = false
	xp_bar.max_value = progression.required_experience

	help_label = Label.new()
	help_label.position = Vector2(24.0, 660.0)
	help_label.size = Vector2(1232.0, 30.0)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.text = "캐릭터 선택 중 — 각자 고유 무기와 능력치를 확인하고 확정하세요."
	help_label.add_theme_font_size_override("font_size", 18)
	help_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.93, 0.9))
	layer.add_child(help_label)

	message_label = Label.new()
	message_label.position = Vector2(0.0, 248.0)
	message_label.size = Vector2(1280.0, 60.0)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 31)
	message_label.modulate.a = 0.0
	layer.add_child(message_label)

	level_overlay = ColorRect.new()
	level_overlay.position = Vector2(110.0, 95.0)
	level_overlay.size = Vector2(1060.0, 525.0)
	level_overlay.color = Color(0.025, 0.035, 0.075, 0.97)
	level_overlay.visible = false
	layer.add_child(level_overlay)

	level_title = Label.new()
	level_title.position = Vector2(0.0, 24.0)
	level_title.size = Vector2(1060.0, 55.0)
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_title.add_theme_font_size_override("font_size", 31)
	level_title.add_theme_color_override("font_color", Color("fff275"))
	level_overlay.add_child(level_title)

	level_card_labels[0] = _create_level_cards(level_overlay, 50.0, Color("43d9ff"))
	level_card_labels[1] = _create_level_cards(level_overlay, 545.0, Color("b892ff"))
	p1_level_footer = _create_level_footer(level_overlay, 50.0, Color("43d9ff"))
	p2_level_footer = _create_level_footer(level_overlay, 545.0, Color("b892ff"))

	resonance_overlay = ColorRect.new()
	resonance_overlay.position = Vector2(180.0, 105.0)
	resonance_overlay.size = Vector2(920.0, 500.0)
	resonance_overlay.color = Color(0.055, 0.025, 0.09, 0.985)
	resonance_overlay.visible = false
	layer.add_child(resonance_overlay)

	resonance_title = Label.new()
	resonance_title.position = Vector2(0.0, 25.0)
	resonance_title.size = Vector2(920.0, 55.0)
	resonance_title.text = "공명 후보 발견 — 같은 기술에 투표하세요"
	resonance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_title.add_theme_font_size_override("font_size", 29)
	resonance_title.add_theme_color_override("font_color", Color("fff275"))
	resonance_overlay.add_child(resonance_title)

	resonance_choices_label = Label.new()
	resonance_choices_label.position = Vector2(55.0, 92.0)
	resonance_choices_label.size = Vector2(810.0, 370.0)
	resonance_choices_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_choices_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resonance_choices_label.add_theme_font_size_override("font_size", 21)
	resonance_choices_label.add_theme_color_override("font_color", Color("e4c1f9"))
	resonance_overlay.add_child(resonance_choices_label)

	character_overlay = ColorRect.new()
	character_overlay.position = Vector2(90.0, 65.0)
	character_overlay.size = Vector2(1100.0, 585.0)
	character_overlay.color = Color(0.018, 0.028, 0.065, 0.985)
	layer.add_child(character_overlay)

	character_title = Label.new()
	character_title.position = Vector2(0.0, 24.0)
	character_title.size = Vector2(1100.0, 60.0)
	character_title.text = "사슬에 묶일 두 생존자를 선택하세요"
	character_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_title.add_theme_font_size_override("font_size", 32)
	character_title.add_theme_color_override("font_color", Color("fff275"))
	character_overlay.add_child(character_title)
	character_roster_label = Label.new()
	character_roster_label.position = Vector2(45.0, 78.0)
	character_roster_label.size = Vector2(1010.0, 32.0)
	character_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_roster_label.add_theme_font_size_override("font_size", 17)
	character_roster_label.add_theme_color_override("font_color", Color("a9b8d4"))
	character_overlay.add_child(character_roster_label)

	character_p1_label = _create_character_label(Vector2(55.0, 112.0), Color("43d9ff"))
	character_p2_label = _create_character_label(Vector2(570.0, 112.0), Color("b892ff"))
	character_overlay.add_child(character_p1_label)
	character_overlay.add_child(character_p2_label)
	character_synergy_label = Label.new()
	character_synergy_label.position = Vector2(100.0, 522.0)
	character_synergy_label.size = Vector2(900.0, 40.0)
	character_synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_synergy_label.add_theme_font_size_override("font_size", 18)
	character_synergy_label.add_theme_color_override("font_color", Color("fff275"))
	character_overlay.add_child(character_synergy_label)

	lobby_overlay = ColorRect.new()
	lobby_overlay.position = Vector2(90.0, 55.0)
	lobby_overlay.size = Vector2(1100.0, 610.0)
	lobby_overlay.color = Color(0.012, 0.022, 0.055, 0.995)
	layer.add_child(lobby_overlay)
	lobby_title = Label.new()
	lobby_title.position = Vector2(0.0, 48.0)
	lobby_title.size = Vector2(1100.0, 110.0)
	lobby_title.text = "CHAINBOUND SURVIVORS\n두 생존자가 모두 참가해야 결속할 수 있습니다"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_font_size_override("font_size", 30)
	lobby_title.add_theme_color_override("font_color", Color("fff275"))
	lobby_overlay.add_child(lobby_title)
	lobby_p1_label = _create_lobby_slot(Vector2(75.0, 210.0), Color("43d9ff"))
	lobby_p2_label = _create_lobby_slot(Vector2(575.0, 210.0), Color("b892ff"))
	lobby_overlay.add_child(lobby_p1_label)
	lobby_overlay.add_child(lobby_p2_label)
	var lobby_help := Label.new()
	lobby_help.position = Vector2(60.0, 500.0)
	lobby_help.size = Vector2(980.0, 65.0)
	lobby_help.text = "키보드 P1: WASD     ·     키보드 P2: 방향키\n게임패드 1번 → P1     ·     게임패드 2번 → P2\n참가 후 ESC / START로 취소"
	lobby_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_help.add_theme_font_size_override("font_size", 20)
	lobby_help.add_theme_color_override("font_color", Color("a9b8d4"))
	lobby_overlay.add_child(lobby_help)

	pause_overlay = ColorRect.new()
	pause_overlay.position = Vector2(330.0, 185.0)
	pause_overlay.size = Vector2(620.0, 350.0)
	pause_overlay.color = Color(0.02, 0.03, 0.07, 0.98)
	pause_overlay.visible = false
	layer.add_child(pause_overlay)
	pause_label = Label.new()
	pause_label.position = Vector2(30.0, 28.0)
	pause_label.size = Vector2(560.0, 290.0)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 22)
	pause_overlay.add_child(pause_label)

	result_overlay = ColorRect.new()
	result_overlay.position = Vector2(260.0, 120.0)
	result_overlay.size = Vector2(760.0, 480.0)
	result_overlay.color = Color(0.02, 0.03, 0.07, 0.985)
	result_overlay.visible = false
	layer.add_child(result_overlay)
	result_label = Label.new()
	result_label.position = Vector2(40.0, 35.0)
	result_label.size = Vector2(680.0, 405.0)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 24)
	result_overlay.add_child(result_label)

	tutorial_label = Label.new()
	tutorial_label.position = Vector2(340.0, 570.0)
	tutorial_label.size = Vector2(600.0, 72.0)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_label.add_theme_font_size_override("font_size", 19)
	tutorial_label.add_theme_color_override("font_color", Color("fff275"))
	tutorial_label.visible = false
	_make_label_background(tutorial_label, Color(0.02, 0.03, 0.07, 0.9))
	layer.add_child(tutorial_label)

	build_inspect_label = Label.new()
	build_inspect_label.position = Vector2(300.0, 555.0)
	build_inspect_label.size = Vector2(680.0, 85.0)
	build_inspect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_inspect_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	build_inspect_label.add_theme_font_size_override("font_size", 17)
	build_inspect_label.add_theme_color_override("font_color", Color("dbe7ff"))
	build_inspect_label.visible = false
	_make_label_background(build_inspect_label, Color(0.02, 0.03, 0.07, 0.96))
	layer.add_child(build_inspect_label)

	p1_edge_indicator = _create_edge_indicator(layer, Color("43d9ff"))
	p2_edge_indicator = _create_edge_indicator(layer, Color("b892ff"))
	threat_edge_indicator = _create_edge_indicator(layer, Color("ff5d8f"))


func _make_hud_panel(parent: Node, panel_position: Vector2, panel_size: Vector2, color: Color) -> void:
	var panel := ColorRect.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.color = color
	parent.add_child(panel)


func _make_label_background(label: Label, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	label.add_theme_stylebox_override("normal", style)


func _create_lobby_slot(slot_position: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.position = slot_position
	label.size = Vector2(450.0, 220.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", color)
	_make_label_background(label, Color(color, 0.08))
	return label


func _create_edge_indicator(parent: Node, color: Color) -> Label:
	var label := Label.new()
	label.size = Vector2(115.0, 34.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.visible = false
	_make_label_background(label, Color(0.02, 0.03, 0.07, 0.88))
	parent.add_child(label)
	return label


func _create_bar(parent: Node, bar_position: Vector2, bar_size: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = bar_position
	bar.size = bar_size
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	background.corner_radius_top_left = 5
	background.corner_radius_top_right = 5
	background.corner_radius_bottom_left = 5
	background.corner_radius_bottom_right = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 5
	fill.corner_radius_top_right = 5
	fill.corner_radius_bottom_left = 5
	fill.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


const LEVEL_CARD_WIDTH := 142.0
const LEVEL_CARD_HEIGHT := 345.0
const LEVEL_CARD_GAP := 13.0
const LEVEL_CARD_Y := 105.0


## Builds the three card slots for one player's level-up choices. Each card is
## a single autowrapping Label with a bordered background (swapped per-frame
## in _refresh_level_up_ui() to show focus/locked/unlock-type state) rather
## than separate title/description nodes, matching how the rest of this HUD
## builds text blocks with a StyleBoxFlat behind them.
func _create_level_cards(parent: Node, half_x: float, accent: Color) -> Array:
	var cards: Array = []
	for index in 3:
		var card := Label.new()
		card.position = Vector2(half_x + (LEVEL_CARD_WIDTH + LEVEL_CARD_GAP) * index, LEVEL_CARD_Y)
		card.size = Vector2(LEVEL_CARD_WIDTH, LEVEL_CARD_HEIGHT)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		card.add_theme_font_size_override("font_size", 16)
		card.add_theme_color_override("font_color", Color("e7f6ff"))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(accent, 0.1)
		style.border_color = Color(accent, 0.4)
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(10)
		card.add_theme_stylebox_override("normal", style)
		parent.add_child(card)
		cards.append(card)
	return cards


func _create_level_footer(parent: Node, half_x: float, color: Color) -> Label:
	var footer := Label.new()
	footer.position = Vector2(half_x, LEVEL_CARD_Y + LEVEL_CARD_HEIGHT + 8.0)
	footer.size = Vector2(LEVEL_CARD_WIDTH * 3.0 + LEVEL_CARD_GAP * 2.0, 55.0)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 16)
	footer.add_theme_color_override("font_color", color)
	parent.add_child(footer)
	return footer


func _create_character_label(label_position: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = Vector2(475.0, 420.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", color)
	return label


func _begin_lobby() -> void:
	lobby_active = true
	lobby_joined = [false, false]
	lobby_devices = [-1, -1]
	lobby_device_names = ["", ""]
	lobby_input_cooldown = 0.25
	lobby_overlay.visible = true
	character_overlay.visible = false
	help_label.text = "참가 대기 중 — 두 사람이 각자 사용할 조작을 눌러 참가하세요."
	_refresh_lobby_ui()
	get_tree().paused = true


func _join_lobby_with_gamepad(device: int) -> void:
	if device < 0 or device > 1:
		return
	_join_lobby_slot(device, device, "게임패드 %d" % (device + 1))


func _join_lobby_slot(slot: int, device: int, device_name: String) -> void:
	if not lobby_active or lobby_input_cooldown > 0.0 or lobby_joined[slot]:
		return
	if device >= 0 and device in lobby_devices:
		return
	lobby_joined[slot] = true
	lobby_devices[slot] = device
	lobby_device_names[slot] = device_name
	last_input_gamepad[slot] = device >= 0
	feedback.play_cue("xp")
	_refresh_lobby_ui()
	if lobby_joined[0] and lobby_joined[1]:
		_finish_lobby()


func _finish_lobby() -> void:
	lobby_active = false
	lobby_overlay.visible = false
	lobby_input_cooldown = 0.3
	help_label.text = "캐릭터 선택 중 — 각자 고유 무기와 능력치를 확인하고 확정하세요."
	_begin_character_select()


func _refresh_lobby_ui() -> void:
	lobby_p1_label.text = _format_lobby_slot(0)
	lobby_p2_label.text = _format_lobby_slot(1)


func _format_lobby_slot(slot: int) -> String:
	var heading := "P%d" % (slot + 1)
	if lobby_joined[slot]:
		return "%s\n\n✓ 참가 완료\n%s\n\nESC / START  참가 취소" % [heading, lobby_device_names[slot]]
	var hint := "WASD 중 아무 키\n또는 1번 게임패드 버튼" if slot == 0 else "방향키 중 아무 키\n또는 2번 게임패드 버튼"
	return "%s\n\n참가 대기\n\n%s" % [heading, hint]


func _begin_character_select() -> void:
	character_select_active = true
	character_confirmed = [false, false]
	character_overlay.visible = true
	_refresh_character_select_ui()
	get_tree().paused = true


func _handle_character_select_input() -> void:
	for player_index in 2:
		if character_confirmed[player_index]:
			var cancel_action := "p1_select_cancel" if player_index == 0 else "p2_select_cancel"
			if Input.is_action_just_pressed(cancel_action):
				character_confirmed[player_index] = false
				_refresh_character_select_ui()
			continue
		var prefix := "p1_" if player_index == 0 else "p2_"
		if Input.is_action_just_pressed(prefix + "select_previous"):
			selected_character_indices[player_index] = wrapi(
				selected_character_indices[player_index] - 1, 0, character_catalog.size()
			)
			_refresh_character_select_ui()
		elif Input.is_action_just_pressed(prefix + "select_next"):
			selected_character_indices[player_index] = wrapi(
				selected_character_indices[player_index] + 1, 0, character_catalog.size()
			)
			_refresh_character_select_ui()
		elif Input.is_action_just_pressed(prefix + "select_confirm"):
			character_confirmed[player_index] = true
			_refresh_character_select_ui()

	if character_confirmed[0] and character_confirmed[1]:
		_start_selected_run()


func _refresh_character_select_ui() -> void:
	character_p1_label.text = _format_character_card(0)
	character_p2_label.text = _format_character_card(1)
	var roster: Array[String] = []
	for character in character_catalog:
		roster.append(String(character["name"]))
	character_roster_label.text = "전체 생존자  ·  " + "   ".join(roster)
	character_synergy_label.text = _synergy_preview()


func _format_character_card(player_index: int) -> String:
	var character := character_catalog[selected_character_indices[player_index]]
	var player_name := "P1" if player_index == 0 else "P2"
	var controls := "LB / RB 선택 · A 확정" if last_input_gamepad[player_index] else ("A / D 선택 · W 확정" if player_index == 0 else "← / → 선택 · ↑ 확정")
	var cancel_hint := "B로 변경" if last_input_gamepad[player_index] else ("S로 변경" if player_index == 0 else "↓로 변경")
	var status := "✓ 선택 완료 · " + cancel_hint if character_confirmed[player_index] else controls
	var health_blocks := _stat_blocks(remap(float(character["health"]), 90.0, 120.0, 2.0, 5.0))
	var speed_blocks := _stat_blocks(remap(float(character["speed"]), 205.0, 240.0, 2.0, 5.0))
	return "%s\n<  %s  >  ·  %s\n\n고유 무기: %s\n%s\n\n체력 %s  %.0f\n속도 %s  %.0f\n\n%s" % [
		player_name,
		String(character["name"]),
		String(character["title"]),
		String(character["weapon_name"]),
		String(character["description"]),
		health_blocks, float(character["health"]),
		speed_blocks, float(character["speed"]),
		status
	]


func _stat_blocks(value: float) -> String:
	var filled := clampi(int(round(value)), 1, 5)
	return "■".repeat(filled) + "□".repeat(5 - filled)


func _synergy_preview() -> String:
	var first: Dictionary = character_catalog[selected_character_indices[0]]
	var second: Dictionary = character_catalog[selected_character_indices[1]]
	var names: Array[String] = []
	for resonance in resonance_system.catalog:
		var requirements: Array = resonance["requires"]
		var tags_a: Array = first["tags"]
		var tags_b: Array = second["tags"]
		if (requirements[0] in tags_a and requirements[1] in tags_b) or (requirements[1] in tags_a and requirements[0] in tags_b):
			names.append(String(resonance["name"]))
	return "예상 공명: " + (" · ".join(names) if not names.is_empty() else "직접적인 조합 없음 — 각자의 강점을 활용하세요")


## Builds a self-contained weapon-loadout entry from a character's catalog
## entry: the numeric weapon stats plus the identity fields (id/name/tags/
## color/source) that a picked-up weapon needs to carry with it once it no
## longer matches the player's own selected_characters[i].
func _build_weapon_state(character: Dictionary) -> Dictionary:
	var state: Dictionary = (character["weapon"] as Dictionary).duplicate(true)
	state["weapon_id"] = character["weapon_id"]
	state["weapon_name"] = character["weapon_name"]
	state["tags"] = (character["tags"] as Array).duplicate()
	state["color"] = character["color"]
	state["source_character"] = character["name"]
	return state


func _start_selected_run() -> void:
	for player_index in 2:
		selected_characters[player_index] = character_catalog[selected_character_indices[player_index]].duplicate(true)
		weapon_loadouts[player_index] = [_build_weapon_state(selected_characters[player_index])]
		players[player_index].apply_character(selected_characters[player_index])
		attack_timers[player_index] = [0.15 + player_index * 0.12]
	character_select_active = false
	character_overlay.visible = false
	chain_integrity = CHAIN_INTEGRITY_MAX
	chain_overloaded = false
	rerolls_remaining = [1, 1] ## Spent across the run, not refilled per level-up
	last_upgrade_choice_keys = [[], []]
	lobby_active = false
	lobby_overlay.visible = false
	get_tree().paused = false
	help_label.text = "P1 WASD     P2 방향키     금빛 과충전: +25% (사슬 내구 소모)     ESC / START: 일시정지"
	_show_message("목표: 02:00에 나타나는 결속 파괴자를 처치하세요", Color("80ed99"))


func _apply_chain_constraint() -> void:
	var offset := players[1].position - players[0].position
	var distance := offset.length()
	if distance <= 0.001:
		return
	var direction := offset.normalized()
	var p1_share := _chain_correction_share(direction)
	if distance > chain_max_length * 0.92:
		var resistance := (distance - chain_max_length * 0.92) * 0.08
		players[0].position += direction * resistance * p1_share
		players[1].position -= direction * resistance * (1.0 - p1_share)
		offset = players[1].position - players[0].position
		distance = offset.length()
	if distance <= chain_max_length:
		return
	var overflow := distance - chain_max_length
	players[0].position += direction * overflow * p1_share
	players[1].position -= direction * overflow * (1.0 - p1_share)


## Fraction of a chain correction absorbed by player 0; player 1 takes the rest.
##
## While both survivors are on their feet the correction lands on whoever is
## straining outward, so neither can outrun the chain. That rule inverts once
## one of them goes down: a downed survivor pushes outward with nothing, so the
## input split would hand the whole correction to the partner and anchor them in
## place instead of letting them drag the body clear. Dead weight therefore
## takes almost all of the correction and gets towed, keeping a little back so
## the pull still reads as heavy.
func _chain_correction_share(direction: Vector2) -> float:
	if players[0].downed != players[1].downed:
		return DOWNED_TOW_SHARE if players[0].downed else 1.0 - DOWNED_TOW_SHARE
	var p1_outward := maxf(0.0, players[0].current_input.dot(-direction))
	var p2_outward := maxf(0.0, players[1].current_input.dot(direction))
	return (p1_outward + 0.25) / (p1_outward + p2_outward + 0.5)


func _update_revives(delta: float) -> void:
	for player in players:
		player.step_bleedout(delta)
	for downed_index in 2:
		var downed_player := players[downed_index]
		if not downed_player.downed:
			continue
		var rescuer := players[1 - downed_index]
		if not rescuer.downed and downed_player.global_position.distance_to(rescuer.global_position) <= 105.0:
			downed_player.revive_progress += delta
		else:
			downed_player.revive_progress = maxf(0.0, downed_player.revive_progress - delta * 0.55)
		if downed_player.revive_progress >= 2.6:
			downed_player.revive()
		downed_player.queue_redraw()


## Burns chain integrity while the survivors hold an overcharged gap and pays it
## back only once they close inside the resist ratio. Running the bar to zero
## overloads the chain: the damage bonus inverts into a penalty until they have
## spent long enough together to repair it.
func _update_chain_integrity(delta: float) -> void:
	var ratio := players[0].position.distance_to(players[1].position) / chain_max_length
	if ratio >= CHAIN_WARNING_RATIO:
		var strain := inverse_lerp(CHAIN_WARNING_RATIO, 1.0, minf(ratio, 1.0))
		var drain := lerpf(CHAIN_DRAIN_AT_WARNING, CHAIN_DRAIN_AT_LIMIT, strain)
		chain_integrity = maxf(0.0, chain_integrity - drain * delta)
		if chain_integrity <= 0.0 and not chain_overloaded:
			_trigger_chain_overload()
	elif ratio < CHAIN_RESIST_RATIO:
		chain_integrity = minf(CHAIN_INTEGRITY_MAX, chain_integrity + CHAIN_INTEGRITY_RECOVERY * delta)
		if chain_overloaded and chain_integrity >= CHAIN_OVERLOAD_CLEAR:
			chain_overloaded = false
			feedback.play_cue("revive")
			_show_message("사슬 복구 — 과충전을 다시 쓸 수 있습니다", Color("80ed99"))


func _trigger_chain_overload() -> void:
	chain_overloaded = true
	for player in players:
		player.hurt(CHAIN_OVERLOAD_DAMAGE)
	camera_shake = maxf(camera_shake, 14.0)
	feedback.play_cue("down")
	_show_message("사슬 과부하! 서로 가까워져 복구하세요", Color("ff5d8f"))


func _update_chain_visual() -> void:
	chain_line.set_point_position(0, players[0].position)
	chain_line.set_point_position(1, players[1].position)
	chain_glow.set_point_position(0, players[0].position)
	chain_glow.set_point_position(1, players[1].position)
	var ratio := players[0].position.distance_to(players[1].position) / chain_max_length
	var stage := 0
	var chain_color := Color("43d9ff")
	if ratio >= 0.95:
		stage = 3
		chain_color = Color("ff5d8f")
	elif ratio >= CHAIN_WARNING_RATIO:
		stage = 2
		chain_color = Color("fff275")
	elif ratio >= CHAIN_RESIST_RATIO:
		stage = 1
		chain_color = Color("8ecae6")
	if chain_overloaded:
		chain_color = Color("6b2338")
	chain_line.default_color = chain_color
	chain_line.width = 2.5 if chain_overloaded else 5.0
	chain_glow.default_color = Color(chain_color, 0.05 if chain_overloaded else 0.12 + ratio * 0.13)
	if stage == 3 and previous_chain_stage < 3:
		feedback.play_cue("warning")
		camera_shake = maxf(camera_shake, 4.0)
	previous_chain_stage = stage


func _update_camera(delta: float) -> void:
	var midpoint := (players[0].position + players[1].position) * 0.5
	var shake_offset := Vector2.ZERO
	if screen_shake_enabled and camera_shake > 0.05:
		shake_offset = Vector2(randf_range(-camera_shake, camera_shake), randf_range(-camera_shake, camera_shake))
		camera_shake = move_toward(camera_shake, 0.0, delta * 24.0)
	world_camera.position = world_camera.position.lerp(midpoint, minf(1.0, delta * 8.0)) + shake_offset


func _register_enemy(enemy: ChaserEnemy) -> void:
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.ranged_attack.is_connected(_on_enemy_ranged_attack):
		enemy.ranged_attack.connect(_on_enemy_ranged_attack)
	if not enemy.damage_taken.is_connected(_on_enemy_damaged):
		enemy.damage_taken.connect(_on_enemy_damaged)
	if not enemy.chain_slam.is_connected(_on_boss_chain_slam):
		enemy.chain_slam.connect(_on_boss_chain_slam)
	if enemy not in enemies:
		enemies.append(enemy)
	if enemy.boss:
		boss_enemy = enemy
		boss_bar.max_value = enemy.max_health
		boss_bar.value = enemy.health
		boss_bar.visible = true
		boss_label.visible = true
		_show_message("경고 — 결속 파괴자가 사슬을 노립니다!", Color("ff5d8f"))
		feedback.play_cue("boss")
		camera_shake = 10.0


func _on_enemy_ranged_attack(origin: Vector2, direction: Vector2, damage: float) -> void:
	var projectile := EnemyProjectileScript.new() as EnemyProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.setup(origin, direction, damage, players)
	add_child(projectile)


## The boss's Chain Slam always drains chain integrity directly — it is
## targeting the bond itself, not the survivors — and additionally hurts
## anyone still standing inside the telegraphed impact radius when it lands.
func _on_boss_chain_slam(impact_point: Vector2, damage: float, radius: float) -> void:
	var hit_someone := false
	for player in players:
		if impact_point.distance_to(player.global_position) <= radius + player.radius:
			hit_someone = player.hurt(damage) or hit_someone
	chain_integrity = maxf(0.0, chain_integrity - BOSS_SLAM_INTEGRITY_DRAIN)
	camera_shake = maxf(camera_shake, 13.0)
	feedback.play_cue("warning")
	_show_message("결속 파괴자가 사슬을 강타했습니다!" if hit_someone else "결속 파괴자가 사슬 내구도를 노렸습니다!", Color("ff5d8f"))


func _on_enemy_damaged(enemy: ChaserEnemy, amount: float) -> void:
	feedback.show_damage(enemy.global_position, amount, Color("fff4cf"))
	feedback.play_cue("hit")


func _on_player_damaged(player: ChainPlayer, amount: float) -> void:
	feedback.show_damage(player.global_position, amount, Color("ff8fab"))
	feedback.play_cue("warning")
	camera_shake = maxf(camera_shake, 7.0)
	Input.start_joy_vibration(player.player_index - 1, 0.25, 0.55, 0.16)


func _on_player_downed(player: ChainPlayer) -> void:
	feedback.play_cue("down")
	camera_shake = 12.0
	_show_message("%s 다운 — 18초 안에 가까이 머물러 구조하세요!" % player.character_name, Color("ff5d8f"))


func _on_player_revived(player: ChainPlayer) -> void:
	feedback.play_cue("revive")
	_show_message("%s 부활 — 사슬이 다시 이어집니다" % player.character_name, Color("80ed99"))


func _set_pause(enabled: bool) -> void:
	pause_active = enabled
	pause_overlay.visible = enabled
	if enabled:
		_update_pause_text()
	get_tree().paused = enabled


func _handle_pause_input() -> void:
	if Input.is_action_just_pressed("pause"):
		_set_pause(false)
	elif Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
	elif Input.is_action_just_pressed("toggle_shake"):
		screen_shake_enabled = not screen_shake_enabled
		_persist_settings()
		_update_pause_text()
	elif Input.is_action_just_pressed("toggle_numbers"):
		feedback.damage_numbers_enabled = not feedback.damage_numbers_enabled
		_persist_settings()
		_update_pause_text()
	elif Input.is_action_just_pressed("toggle_sound"):
		feedback.sound_enabled = not feedback.sound_enabled
		_persist_settings()
		_update_pause_text()


func _persist_settings() -> void:
	settings.screen_shake_enabled = screen_shake_enabled
	settings.damage_numbers_enabled = feedback.damage_numbers_enabled
	settings.sound_enabled = feedback.sound_enabled
	settings.save_settings()


func _update_pause_text() -> void:
	pause_label.text = "일시정지\n\nESC / START   계속하기\nENTER          처음부터\n\n[F1] 화면 흔들림: %s\n[F2] 피해 숫자: %s\n[F3] 효과음: %s\n[F11] 전체 화면" % [
		"켜짐" if screen_shake_enabled else "꺼짐",
		"켜짐" if feedback.damage_numbers_enabled else "꺼짐",
		"켜짐" if feedback.sound_enabled else "꺼짐"
	]


## Fires every weapon a player owns once — used by the physics loop's
## per-weapon cooldown check above (one call per ready weapon) and reused by
## tests that want to trigger "this player attacks now" without waiting out
## real cooldowns.
func _perform_character_attack(player_index: int) -> void:
	for weapon_slot in weapon_loadouts[player_index].size():
		weapon_controller.perform_attack(player_index, weapon_slot, _tension_damage_multiplier())


func _on_enemy_died(enemy: ChaserEnemy) -> void:
	var death_position := enemy.global_position
	var dropped_xp := enemy.xp_value
	var defeated_boss := enemy.boss
	enemies.erase(enemy)
	kills += 1
	experience_system.spawn_gem(death_position, dropped_xp)
	feedback.play_cue("kill")
	wave_director.release_enemy(enemy)
	if defeated_boss:
		boss_bar.visible = false
		boss_label.visible = false
		_end_run(true)
		return
	if kills % 18 == 0:
		for player in players:
			player.heal(8.0)
		_show_message("사슬의 마력이 회복되었습니다  +8 HP", Color("80ed99"))


func _gain_shared_xp(amount: int) -> void:
	progression.add_experience(amount)
	feedback.play_cue("xp")
	if not level_up_active and progression.can_level_up():
		_begin_level_up()


func _begin_level_up() -> void:
	if not progression.consume_level_up():
		return
	level_up_active = true
	selected_upgrade_indices = [-1, -1]
	upgrade_cursors = [0, 0]
	build_inspect_active = false
	build_inspect_label.visible = false
	p1_choices = _get_upgrade_choices(1)
	p2_choices = _get_upgrade_choices(2)
	level_overlay.visible = true
	_refresh_level_up_ui()
	_update_hud()
	get_tree().paused = true
	feedback.play_cue("level")


## A key that identifies one specific offered option (not just its id, since
## e.g. "weapon_power" exists once per owned weapon) so _get_upgrade_choices
## can avoid repeating the exact same 3-card set the very next level-up.
func _option_key(option: Dictionary) -> String:
	if String(option["id"]) == "unlock_weapon":
		return "unlock_weapon:" + String((option["character"] as Dictionary)["id"])
	return "%s:%d" % [String(option["id"]), int(option.get("weapon_slot", -1))]


## Characters whose weapon this player does not already carry, shuffled and
## capped at `count` — the pool of "new tech" candidates a level-up can offer.
func _pick_unowned_characters(slot: int, count: int) -> Array[Dictionary]:
	var owned_ids: Dictionary = {}
	for weapon in weapon_loadouts[slot]:
		owned_ids[String(weapon["weapon_id"])] = true
	var candidates: Array[Dictionary] = []
	for character in character_catalog:
		if not owned_ids.has(String(character["weapon_id"])):
			candidates.append(character)
	candidates.shuffle()
	return candidates.slice(0, count)


## Builds the pool of everything this level-up could offer: two generic
## options, four per owned weapon (power/rate/special_a/special_b), and — if
## the player has room under WEAPON_LOADOUT_CAP — a couple of "learn this
## other character's weapon" candidates competing on equal footing in the
## same shuffle, not guaranteed to appear every time.
func _get_upgrade_choices(player_index: int) -> Array[Dictionary]:
	var slot := player_index - 1
	var loadout: Array = weapon_loadouts[slot]
	var pool: Array[Dictionary] = [
		{"id": "move", "weapon_slot": -1, "title": "가벼운 발걸음"},
		{"id": "vitality", "weapon_slot": -1, "title": "생명력"}
	]
	for weapon_slot in loadout.size():
		var weapon_name := String(loadout[weapon_slot]["weapon_name"])
		var weapon_id := String(loadout[weapon_slot]["weapon_id"])
		pool.append({"id": "weapon_power", "weapon_slot": weapon_slot, "title": "마력 증폭 · %s" % weapon_name})
		pool.append({"id": "weapon_rate", "weapon_slot": weapon_slot, "title": "고속 시전 · %s" % weapon_name})
		match weapon_id:
			"homing":
				pool.append({"id": "special_a", "weapon_slot": weapon_slot, "title": "다중 유도"})
				pool.append({"id": "special_b", "weapon_slot": weapon_slot, "title": "마력 추진"})
			"lightning":
				pool.append({"id": "special_a", "weapon_slot": weapon_slot, "title": "연쇄 전도"})
				pool.append({"id": "special_b", "weapon_slot": weapon_slot, "title": "확장 도체"})
			"flame":
				pool.append({"id": "special_a", "weapon_slot": weapon_slot, "title": "불씨 범람"})
				pool.append({"id": "special_b", "weapon_slot": weapon_slot, "title": "열풍 추진"})
			"frost":
				pool.append({"id": "special_a", "weapon_slot": weapon_slot, "title": "혹한 영역"})
				pool.append({"id": "special_b", "weapon_slot": weapon_slot, "title": "동상"})
			"scythe":
				pool.append({"id": "special_a", "weapon_slot": weapon_slot, "title": "긴 자루"})
				pool.append({"id": "special_b", "weapon_slot": weapon_slot, "title": "보름베기"})
			"chain":
				pool.append({"id": "special_a", "weapon_slot": weapon_slot, "title": "넓은 파동"})
				pool.append({"id": "special_b", "weapon_slot": weapon_slot, "title": "느슨한 족쇄"})
	if loadout.size() < WEAPON_LOADOUT_CAP:
		for character in _pick_unowned_characters(slot, 2):
			pool.append({
				"id": "unlock_weapon", "weapon_slot": -1, "character": character,
				"title": "신규 기술: %s" % String(character["weapon_name"])
			})
	for option in pool:
		option["description"] = _upgrade_preview(slot, option)

	var previous_keys: Array = last_upgrade_choice_keys[slot]
	var fresh_pool: Array[Dictionary] = []
	for option in pool:
		if not (_option_key(option) in previous_keys):
			fresh_pool.append(option)
	if fresh_pool.size() >= 3:
		pool = fresh_pool

	pool.shuffle()
	var choices: Array[Dictionary] = pool.slice(0, 3)
	var choice_keys: Array = []
	for option in choices:
		choice_keys.append(_option_key(option))
	last_upgrade_choice_keys[slot] = choice_keys
	return choices


func _upgrade_preview(slot: int, option: Dictionary) -> String:
	var upgrade_id := String(option["id"])
	if upgrade_id == "unlock_weapon":
		var character: Dictionary = option["character"]
		var tag_names: Array[String] = []
		for tag in (character["tags"] as Array):
			tag_names.append(_tag_name(String(tag)))
		return "%s의 %s 습득\n태그: %s" % [String(character["name"]), String(character["weapon_name"]), " · ".join(tag_names)]
	if upgrade_id == "move":
		return "이동 속도 %.0f → %.0f" % [players[slot].move_speed, players[slot].move_speed * 1.08]
	if upgrade_id == "vitality":
		return "최대 체력 %.0f → %.0f · 즉시 15 회복" % [players[slot].max_health, players[slot].max_health + 15.0]
	var weapon_slot := int(option["weapon_slot"])
	var state: Dictionary = weapon_loadouts[slot][weapon_slot]
	var weapon_id := String(state["weapon_id"])
	var tier_hint := "  ·  T%d → T%d" % [int(state.get("tier", 1)), int(state.get("tier", 1)) + 1]
	match upgrade_id:
		"weapon_power":
			return "피해 %.1f → %.1f%s" % [float(state["damage"]), float(state["damage"]) * 1.25, tier_hint]
		"weapon_rate":
			return "발동 %.2f초 → %.2f초%s" % [float(state["cooldown"]), maxf(0.2, float(state["cooldown"]) * 0.88), tier_hint]
		"special_a":
			match weapon_id:
				"homing": return "동시 발사 %d → %d%s" % [int(state["count"]), int(state["count"]) + 1, tier_hint]
				"flame": return "화염탄 %d → %d%s" % [int(state["count"]), int(state["count"]) + 2, tier_hint]
				"lightning": return "연쇄 %d → %d%s" % [int(state["jumps"]), int(state["jumps"]) + 1, tier_hint]
				"frost": return "반경 %.0f → %.0f%s" % [float(state["radius"]), float(state["radius"]) + 30.0, tier_hint]
				"scythe": return "사거리 %.0f → %.0f%s" % [float(state["range"]), float(state["range"]) + 30.0, tier_hint]
				"chain": return "파동 폭 %.0f → %.0f%s" % [float(state["width"]), float(state["width"]) + 14.0, tier_hint]
		"special_b":
			match weapon_id:
				"homing", "flame": return "투사체 속도 %.0f → %.0f%s" % [float(state["speed"]), float(state["speed"]) + (70.0 if weapon_id == "homing" else 55.0), tier_hint]
				"lightning": return "첫 타격 사거리 %.0f → %.0f%s" % [float(state["range"]), float(state["range"]) + 55.0, tier_hint]
				"frost": return "감속 배율 %.0f%% → %.0f%%%s" % [float(state["slow"]) * 100.0, maxf(0.25, float(state["slow"]) - 0.08) * 100.0, tier_hint]
				"scythe": return "공격 각도 %.0f° → %.0f°%s" % [rad_to_deg(float(state["arc"])), rad_to_deg(minf(PI * 1.75, float(state["arc"]) + 0.25)), tier_hint]
				"chain": return "사슬 한계 %.0f → %.0f%s" % [chain_max_length, chain_max_length + 30.0, tier_hint]
	return "현재 능력을 강화합니다."


func _handle_level_up_input() -> void:
	if Input.is_action_pressed("build_inspect"):
		if not build_inspect_active:
			build_inspect_active = true
			_refresh_build_inspect_ui()
		return
	elif build_inspect_active:
		build_inspect_active = false
		build_inspect_label.visible = false

	for slot in 2:
		var player_index := slot + 1
		var prefix := "p1_select_" if player_index == 1 else "p2_select_"
		var choices := p1_choices if player_index == 1 else p2_choices
		if selected_upgrade_indices[slot] >= 0:
			if Input.is_action_just_pressed(prefix + "cancel") and selected_upgrade_indices[1 - slot] < 0:
				selected_upgrade_indices[slot] = -1
				_refresh_level_up_ui()
			continue
		if Input.is_action_just_pressed(prefix + "previous"):
			upgrade_cursors[slot] = wrapi(upgrade_cursors[slot] - 1, 0, choices.size())
			_refresh_level_up_ui()
		elif Input.is_action_just_pressed(prefix + "next"):
			upgrade_cursors[slot] = wrapi(upgrade_cursors[slot] + 1, 0, choices.size())
			_refresh_level_up_ui()
		elif Input.is_action_just_pressed(prefix + "confirm"):
			_select_upgrade(player_index, upgrade_cursors[slot])
		elif Input.is_action_just_pressed("p%d_reroll" % player_index) and rerolls_remaining[slot] > 0:
			_reroll_choices(player_index)


func _reroll_choices(player_index: int) -> void:
	var slot := player_index - 1
	rerolls_remaining[slot] -= 1
	if player_index == 1:
		p1_choices = _get_upgrade_choices(1)
	else:
		p2_choices = _get_upgrade_choices(2)
	upgrade_cursors[slot] = 0
	_refresh_level_up_ui()


## Locks in choice_index for player_index without applying it yet. Both
## players' picks only take effect once BOTH have locked — until then, the
## player who locked first can still cancel back to browsing (see
## _handle_level_up_input), which is only meaningful if the upgrade hasn't
## already changed their stats.
func _select_upgrade(player_index: int, choice_index: int) -> void:
	var slot := player_index - 1
	var choices := p1_choices if player_index == 1 else p2_choices
	if choice_index < 0 or choice_index >= choices.size():
		return
	selected_upgrade_indices[slot] = choice_index
	upgrade_cursors[slot] = choice_index
	_refresh_level_up_ui()
	if selected_upgrade_indices[0] >= 0 and selected_upgrade_indices[1] >= 0:
		_apply_upgrade(0, p1_choices[selected_upgrade_indices[0]])
		_apply_upgrade(1, p2_choices[selected_upgrade_indices[1]])
		_after_personal_upgrade_choices()


func _apply_upgrade(player_slot: int, option: Dictionary) -> void:
	var upgrade_id := String(option["id"])
	if upgrade_id == "unlock_weapon":
		var character: Dictionary = option["character"]
		weapon_loadouts[player_slot].append(_build_weapon_state(character))
		attack_timers[player_slot].append(0.2)
		return
	if upgrade_id == "move":
		players[player_slot].move_speed *= 1.08
		return
	if upgrade_id == "vitality":
		players[player_slot].max_health += 15.0
		players[player_slot].heal(15.0)
		return
	var weapon_slot := int(option["weapon_slot"])
	var state: Dictionary = weapon_loadouts[player_slot][weapon_slot]
	var weapon_id := String(state["weapon_id"])
	match upgrade_id:
		"weapon_power":
			state["damage"] = float(state["damage"]) * 1.25
		"weapon_rate":
			state["cooldown"] = maxf(0.2, float(state["cooldown"]) * 0.88)
		"special_a":
			match weapon_id:
				"homing", "flame":
					state["count"] = int(state["count"]) + (1 if weapon_id == "homing" else 2)
				"lightning":
					state["jumps"] = int(state["jumps"]) + 1
				"frost":
					state["radius"] = float(state["radius"]) + 30.0
				"scythe":
					state["range"] = float(state["range"]) + 30.0
				"chain":
					state["width"] = float(state["width"]) + 14.0
		"special_b":
			match weapon_id:
				"homing":
					state["speed"] = float(state["speed"]) + 70.0
				"lightning":
					state["range"] = float(state["range"]) + 55.0
				"flame":
					state["speed"] = float(state["speed"]) + 55.0
				"frost":
					state["slow"] = maxf(0.25, float(state["slow"]) - 0.08)
				"scythe":
					state["arc"] = minf(PI * 1.75, float(state["arc"]) + 0.25)
				"chain":
					chain_max_length += 30.0
	if upgrade_id in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
		state["tier"] = int(state.get("tier", 1)) + 1


func _refresh_level_up_ui() -> void:
	level_title.text = "공유 레벨 %d — 좌우로 고르고 확정하세요" % progression.level
	_refresh_player_cards(1)
	_refresh_player_cards(2)
	if build_inspect_active:
		_refresh_build_inspect_ui()


func _refresh_player_cards(player_index: int) -> void:
	var slot := player_index - 1
	var choices := p1_choices if player_index == 1 else p2_choices
	var cards: Array = level_card_labels[slot]
	var locked := selected_upgrade_indices[slot] >= 0
	var accent := Color("43d9ff") if player_index == 1 else Color("b892ff")

	for index in cards.size():
		var card: Label = cards[index]
		var option: Dictionary = choices[index] if index < choices.size() else {}
		var style := card.get_theme_stylebox("normal") as StyleBoxFlat
		var is_unlock := String(option.get("id", "")) == "unlock_weapon"
		var is_focused := not locked and index == upgrade_cursors[slot]
		var is_chosen := locked and index == selected_upgrade_indices[slot]

		card.visible = (not locked) or is_chosen
		card.text = "%s\n\n%s" % [String(option.get("title", "")), String(option.get("description", ""))]
		if is_unlock:
			card.text = "✦ " + card.text

		var border := Color("fff275") if is_unlock else accent
		if is_chosen:
			style.bg_color = Color(border, 0.28)
			style.border_color = border
			style.set_border_width_all(3)
		elif is_focused:
			style.bg_color = Color(border, 0.2)
			style.border_color = Color(border, 0.9)
			style.set_border_width_all(3)
		else:
			style.bg_color = Color(border, 0.08)
			style.border_color = Color(border, 0.35)
			style.set_border_width_all(2)
		card.scale = Vector2(1.05, 1.05) if is_focused else Vector2.ONE

	var footer: Label = p1_level_footer if player_index == 1 else p2_level_footer
	var character := selected_characters[slot]
	var heading := "P%d  %s" % [player_index, String(character["name"])]
	if locked:
		footer.text = heading + "\n✓ 확정 — 상대를 기다리는 중 (취소하려면 다시 시도)"
	else:
		var keys := ["LB/RB", "A", "B"] if last_input_gamepad[slot] else (["A/D", "W", "S"] if player_index == 1 else ["←/→", "↑", "↓"])
		var reroll_hint := "  ·  재추첨 %d회 남음" % rerolls_remaining[slot]
		footer.text = heading + "\n%s 이동 · %s 확정 · %s 취소%s" % [keys[0], keys[1], keys[2], reroll_hint]


func _refresh_build_inspect_ui() -> void:
	var lines: Array[String] = []
	for slot in 2:
		var player_index := slot + 1
		var names: Array[String] = []
		for weapon in weapon_loadouts[slot]:
			names.append("%s T%d" % [String(weapon["weapon_name"]), int(weapon.get("tier", 1))])
		lines.append("P%d  %s  ·  %s" % [player_index, String(selected_characters[slot]["name"]), " / ".join(names)])
	build_inspect_label.text = "현재 빌드\n\n" + "\n".join(lines)
	build_inspect_label.visible = true


func _finish_level_up() -> void:
	level_up_active = false
	level_overlay.visible = false
	build_inspect_active = false
	build_inspect_label.visible = false
	get_tree().paused = false
	_show_message("레벨 %d — 두 테크가 강화되었습니다" % progression.level, Color("fff275"))
	if progression.can_level_up():
		call_deferred("_begin_level_up")


func _after_personal_upgrade_choices() -> void:
	var candidates := resonance_system.get_candidates_for_loadouts(weapon_loadouts[0], weapon_loadouts[1])
	# The vote screen still uses the fixed p1_choice_1/2/3 digit inputs (a
	# cursor-based rework was scoped out of this pass), so it can only ever
	# present three options regardless of how many weapon pairs qualify.
	resonance_candidates = candidates.slice(0, 3)
	if resonance_candidates.is_empty():
		_finish_level_up()
		return
	resonance_vote_active = true
	resonance_votes[0] = -1
	resonance_votes[1] = -1
	resonance_vote_message = ""
	level_overlay.visible = false
	resonance_overlay.visible = true
	_refresh_resonance_vote_ui()


func _handle_resonance_vote_input() -> void:
	for player_index in 2:
		if resonance_votes[player_index] >= 0:
			continue
		var prefix := "p1_choice_" if player_index == 0 else "p2_choice_"
		for choice_index in resonance_candidates.size():
			if Input.is_action_just_pressed(prefix + str(choice_index + 1)):
				resonance_votes[player_index] = choice_index
				_refresh_resonance_vote_ui()
				break
	if resonance_votes[0] < 0 or resonance_votes[1] < 0:
		return
	if resonance_votes[0] == resonance_votes[1]:
		var chosen := resonance_candidates[resonance_votes[0]]
		resonance_system.activate(chosen)
		resonance_vote_active = false
		resonance_overlay.visible = false
		_show_message("공명 완성 — %s" % String(chosen["name"]), Color("fff275"))
		feedback.play_cue("resonance")
		_finish_level_up()
	else:
		resonance_votes[0] = -1
		resonance_votes[1] = -1
		resonance_vote_message = "선택이 달랐습니다. 대화한 뒤 다시 투표하세요."
		_refresh_resonance_vote_ui()


func _refresh_resonance_vote_ui() -> void:
	var text := ""
	for index in resonance_candidates.size():
		var resonance := resonance_candidates[index]
		var requirements: Array = resonance["requires"]
		text += "[%d]  %s  ·  %s + %s\n%s\n\n" % [index + 1, String(resonance["name"]), _tag_name(String(requirements[0])), _tag_name(String(requirements[1])), String(resonance["description"])]
	var p1_vote := "대기" if resonance_votes[0] < 0 else String(resonance_candidates[resonance_votes[0]]["name"])
	var p2_vote := "대기" if resonance_votes[1] < 0 else String(resonance_candidates[resonance_votes[1]]["name"])
	var p1_keys := "X/A/B" if last_input_gamepad[0] else "A/S/D"
	var p2_keys := "X/A/B" if last_input_gamepad[1] else "←/↓/→"
	text += "P1 %s: %s     P2 %s: %s\n%s" % [p1_keys, p1_vote, p2_keys, p2_vote, resonance_vote_message]
	resonance_choices_label.text = text


func _tag_name(tag: String) -> String:
	var names := {
		"tracking": "추적", "lightning": "번개", "projectile": "투사체", "storm": "폭풍",
		"arcane": "비전", "chain": "연쇄", "fire": "화염", "frost": "서리",
		"shadow": "그림자", "tether": "결속", "aura": "오라", "melee": "근접",
		"holy": "성휘", "control": "제어", "burst": "폭발", "arc": "호격"
	}
	return String(names.get(tag, tag))


func _tension_damage_multiplier() -> float:
	if chain_overloaded:
		return CHAIN_OVERLOAD_PENALTY
	var ratio := players[0].position.distance_to(players[1].position) / chain_max_length
	return 1.25 if ratio >= CHAIN_WARNING_RATIO else 1.0


func _update_hud() -> void:
	var minutes := int(elapsed) / 60
	var seconds := int(elapsed) % 60
	var distance := players[0].position.distance_to(players[1].position)
	var tension := clampf(distance / chain_max_length, 0.0, 1.0)
	var objective := "보스 격파" if wave_director.boss_spawned else "보스 %02d:%02d" % [int(maxf(0.0, RUN_BOSS_TIME - elapsed)) / 60, int(maxf(0.0, RUN_BOSS_TIME - elapsed)) % 60]
	hud_label.text = "%02d:%02d  ·  처치 %d\n공유 LV.%d  ·  %s" % [minutes, seconds, kills, progression.level, objective]
	p1_status_label.text = _player_status_text(0)
	p2_status_label.text = _player_status_text(1)
	p1_health_bar.max_value = players[0].max_health
	p1_health_bar.value = players[0].health
	p2_health_bar.max_value = players[1].max_health
	p2_health_bar.value = players[1].health
	chain_bar.value = tension * 100.0
	var chain_state := "안정"
	var chain_color := Color("43d9ff")
	if chain_overloaded:
		chain_state = "과부하 · 공격력 -20% · 붙어서 복구"
		chain_color = Color("ff5d8f")
	elif tension >= 0.95:
		chain_state = "한계! 서로 가까워지세요"
		chain_color = Color("ff5d8f")
	elif tension >= CHAIN_WARNING_RATIO:
		chain_state = "과충전 · 공격력 +25%"
		chain_color = Color("fff275")
	elif tension >= CHAIN_RESIST_RATIO:
		chain_state = "팽팽함"
		chain_color = Color("8ecae6")
	chain_status_label.text = "사슬 %d%%  ·  내구 %d%%  ·  %s" % [int(tension * 100.0), int(round(chain_integrity)), chain_state]
	chain_status_label.add_theme_color_override("font_color", chain_color)
	var fill := chain_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = chain_color
	chain_integrity_bar.value = chain_integrity
	var integrity_fill := chain_integrity_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if integrity_fill != null:
		if chain_overloaded:
			integrity_fill.bg_color = Color("ff5d8f")
		elif chain_integrity < 40.0:
			integrity_fill.bg_color = Color("fff275")
		else:
			integrity_fill.bg_color = Color("80ed99")
	if resonance_system.active_resonances.is_empty():
		resonance_status_label.text = "공명 대기 · 두 무기 T3 필요"
	else:
		var resonance_names: Array[String] = []
		for active in resonance_system.active_resonances:
			resonance_names.append(String(active["name"]))
		resonance_status_label.text = "공명 %d/%d  ·  %s" % [
			resonance_system.active_resonances.size(), resonance_system.MAX_ACTIVE_RESONANCES, " · ".join(resonance_names)
		]
	xp_bar.max_value = progression.required_experience
	xp_bar.value = progression.experience
	help_label.text = "공유 XP  %d / %d     ·     P1 WASD     P2 방향키     ·     ESC / START 일시정지" % [progression.experience, progression.required_experience]


func _player_status_text(player_index: int) -> String:
	var player := players[player_index]
	var prefix := "P%d  %s  %d/%d HP" % [player_index + 1, player.character_name, int(player.health), int(player.max_health)]
	if player.downed:
		return prefix + "\nDOWN %.1f초 · 구조 %.0f%%" % [player.bleedout_remaining, player.revive_progress / 2.6 * 100.0]
	return prefix + "\n" + _loadout_summary(player_index)


## Compact HUD summary of a player's whole loadout: the weapon name when they
## only carry one (matches how this used to read before extra weapons existed),
## or a tier list once they have picked up more.
func _loadout_summary(player_index: int) -> String:
	var loadout: Array = weapon_loadouts[player_index]
	if loadout.size() == 1:
		return "%s · T%d" % [String(loadout[0]["weapon_name"]), int(loadout[0].get("tier", 1))]
	var tiers: Array[String] = []
	for weapon in loadout:
		tiers.append("T%d" % int(weapon.get("tier", 1)))
	return "무기 %d종 · %s" % [loadout.size(), "/".join(tiers)]


func _show_message(text: String, color: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(message_label, "modulate:a", 0.0, 0.45)


func _end_run(victory: bool = false) -> void:
	if game_over:
		return
	game_over = true
	run_won = victory
	level_up_active = false
	level_overlay.visible = false
	resonance_overlay.visible = false
	pause_overlay.visible = false
	result_overlay.visible = true
	get_tree().paused = true
	var heading := "결속을 지켜냈습니다!" if victory else "사슬이 끊어졌습니다"
	var reason := "결속 파괴자를 쓰러뜨렸습니다." if victory else "두 명이 모두 다운되었거나 구조 시간이 끝났습니다."
	result_label.text = "%s\n\n%s\n\n생존 시간  %02d:%02d\n처치  %d\n공유 레벨  %d\n\nP1  %s  ·  %s\nP2  %s  ·  %s\n\nENTER / A  다시 결속하기" % [
		heading, reason, int(elapsed) / 60, int(elapsed) % 60, kills, progression.level,
		players[0].character_name, _loadout_summary(0),
		players[1].character_name, _loadout_summary(1)
	]
	result_label.add_theme_color_override("font_color", Color("fff275") if victory else Color("ff8fab"))
	feedback.play_cue("victory" if victory else "down")


func _setup_input_map() -> void:
	_add_key_action("p1_left", KEY_A)
	_add_key_action("p1_right", KEY_D)
	_add_key_action("p1_up", KEY_W)
	_add_key_action("p1_down", KEY_S)
	_add_key_action("p2_left", KEY_LEFT)
	_add_key_action("p2_right", KEY_RIGHT)
	_add_key_action("p2_up", KEY_UP)
	_add_key_action("p2_down", KEY_DOWN)
	_add_key_action("restart", KEY_ENTER)
	_add_key_action("pause", KEY_ESCAPE)
	_add_key_action("toggle_shake", KEY_F1)
	_add_key_action("toggle_numbers", KEY_F2)
	_add_key_action("toggle_sound", KEY_F3)
	_add_key_action("toggle_fullscreen", KEY_F11)
	_add_key_action("p1_choice_1", KEY_A)
	_add_key_action("p1_choice_2", KEY_S)
	_add_key_action("p1_choice_3", KEY_D)
	_add_key_action("p2_choice_1", KEY_LEFT)
	_add_key_action("p2_choice_2", KEY_DOWN)
	_add_key_action("p2_choice_3", KEY_RIGHT)
	_add_key_action("p1_select_previous", KEY_A)
	_add_key_action("p1_select_next", KEY_D)
	_add_key_action("p1_select_confirm", KEY_W)
	_add_key_action("p1_select_cancel", KEY_S)
	_add_key_action("p2_select_previous", KEY_LEFT)
	_add_key_action("p2_select_next", KEY_RIGHT)
	_add_key_action("p2_select_confirm", KEY_UP)
	_add_key_action("p2_select_cancel", KEY_DOWN)
	_add_key_action("p1_reroll", KEY_Q)
	_add_key_action("p2_reroll", KEY_SLASH)
	_add_key_action("build_inspect", KEY_TAB)
	_add_joy_axis("p1_left", 0, JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("p1_right", 0, JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("p1_up", 0, JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("p1_down", 0, JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("p2_left", 1, JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("p2_right", 1, JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("p2_up", 1, JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("p2_down", 1, JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button("p1_choice_1", 0, JOY_BUTTON_X)
	_add_joy_button("p1_choice_2", 0, JOY_BUTTON_A)
	_add_joy_button("p1_choice_3", 0, JOY_BUTTON_B)
	_add_joy_button("p2_choice_1", 1, JOY_BUTTON_X)
	_add_joy_button("p2_choice_2", 1, JOY_BUTTON_A)
	_add_joy_button("p2_choice_3", 1, JOY_BUTTON_B)
	_add_joy_button("p1_select_previous", 0, JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("p1_select_next", 0, JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("p1_select_confirm", 0, JOY_BUTTON_A)
	_add_joy_button("p1_select_cancel", 0, JOY_BUTTON_B)
	_add_joy_button("p2_select_previous", 1, JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("p2_select_next", 1, JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("p2_select_confirm", 1, JOY_BUTTON_A)
	_add_joy_button("p2_select_cancel", 1, JOY_BUTTON_B)
	_add_joy_button("pause", 0, JOY_BUTTON_START)
	_add_joy_button("pause", 1, JOY_BUTTON_START)
	_add_joy_button("restart", 0, JOY_BUTTON_A)
	_add_joy_button("restart", 1, JOY_BUTTON_A)
	_add_joy_button("p1_reroll", 0, JOY_BUTTON_Y)
	_add_joy_button("p2_reroll", 1, JOY_BUTTON_Y)
	_add_joy_button("build_inspect", 0, JOY_BUTTON_BACK)
	_add_joy_button("build_inspect", 1, JOY_BUTTON_BACK)


func _add_key_action(action: StringName, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, event)


func _add_joy_axis(action: StringName, device: int, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


func _add_joy_button(action: StringName, device: int, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	InputMap.action_add_event(action, event)
