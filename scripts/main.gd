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
const BurstFieldScript := preload("res://scripts/systems/burst_field.gd")
const ParticleFieldScript := preload("res://scripts/systems/particle_field.gd")
const ArenaFloorScript := preload("res://scripts/arena_floor.gd")
const WeaponControllerScript := preload("res://scripts/systems/weapon_controller.gd")
const FeedbackScript := preload("res://scripts/systems/feedback_system.gd")
const FieldItemScript := preload("res://scripts/systems/field_item_system.gd")
const SettingsScript := preload("res://scripts/systems/settings_system.gd")
const IconCatalog := preload("res://scripts/ui/icon_catalog.gd")
const CatTheme := preload("res://scripts/ui/cat_theme.gd")
const CatPanel := preload("res://scripts/ui/cat_panel.gd")
const EditorialUI := preload("res://scripts/ui/editorial_ui.gd")
const Treasures := preload("res://scripts/treasure_catalog.gd")
const Evolutions := preload("res://scripts/evolution_catalog.gd")

const CHAIN_WARNING_RATIO := 0.82
const CHAIN_RESIST_RATIO := 0.70
## The run is five boss fights, not one. WaveDirector owns the schedule; this
## is the total length so the UI can say how far along a run is without
## recomputing the interval.
const RUN_LENGTH := WaveDirectorScript.RUN_LENGTH
const DOWNED_TOW_SHARE := 0.88
const WEAPON_LOADOUT_CAP := 4
## Treasures are the other half of a build. Attributes used to be unlimited
## free-floating cards; a survivor now commits to four and deepens those.
const TREASURE_LOADOUT_CAP := 4

## Enemies spawn 610-760px out and never stopped chasing, so anything that
## drifted off — a shooter backing away, a charger that overshot — stayed
## alive forever and ate a slot in the 420 cap. Recycling them keeps the
## cap filled with enemies that are actually part of the fight. Comfortably
## beyond the spawn ring so nothing is culled the moment it arrives.
const ENEMY_CULL_RADIUS := 1500.0

## P1 confirms with W and P2 with the up arrow — the same keys they move
## with. Without a beat of dead time the screen appearing mid-stride reads
## a movement key as a card confirmation and picks for them.
const LEVEL_UP_INPUT_DELAY := 0.45
## Breathing room between one level-up screen closing and the next opening.
## Experience arrives in bursts — a swarm pack, a magnet item — so several
## levels can come due at once, and back-to-back screens turned that into a
## stutter where the run stopped, resumed for a frame, and stopped again.
## The pending levels are not lost; they simply queue behind this.
const LEVEL_UP_GAP := 1.1

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
var bursts: BurstField
var particles: ParticleField
var arena_floor: ArenaFloor
var modal_dim: ColorRect
var world_camera: Camera2D
var spatial_grid: EnemySpatialGrid
var progression: SharedProgression
var experience_system: ExperienceSystem
var field_items: FieldItemSystem
var wave_director: WaveDirector
var resonance_system: ResonanceSystem
var weapon_controller: WeaponController
var feedback: FeedbackSystem
var settings: GameSettings
var hud_layer: CanvasLayer
var combat_hud: Control
var boss_hud_panel: ColorRect
var hud_label: Label
var xp_bar: ProgressBar
var xp_text_label: Label
var p1_status_label: Label
var p2_status_label: Label
var p1_health_bar: ProgressBar
var p2_health_bar: ProgressBar
var p1_health_text_label: Label
var p2_health_text_label: Label
var hud_portrait_icons: Array[TextureRect] = []
var chain_bar: ProgressBar
var chain_integrity_bar: ProgressBar
var chain_distance_text_label: Label
var chain_integrity_text_label: Label
var chain_status_label: Label
var resonance_status_label: Label
var boss_bar: ProgressBar
var boss_label: Label
var boss_health_text_label: Label
var help_label: Label
var message_label: Label
var level_overlay: ColorRect
var level_title: Label
var level_card_labels: Array = [[], []] ## level_card_labels[slot] = Array[Label], one per offered choice (up to 3)
var p1_level_footer: Label
var p2_level_footer: Label
var level_portrait_icons: Array[TextureRect] = []
var level_weapon_icons: Array = [[], []]
var level_treasure_icons: Array = [[], []]
var character_overlay: ColorRect
var character_title: Label
var character_p1_label: Label
var character_p2_label: Label
var character_portrait_icons: Array[TextureRect] = []
var resonance_overlay: ColorRect
var resonance_title: Label
var resonance_cards: Array = []
var resonance_status: Label
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
var team_stats_label: Label
var threat_edge_indicator: Label

var elapsed := 0.0
var kills := 0
var game_over := false
var level_up_active := false
var character_select_active := true
var resonance_vote_active := false
var pause_active := false
var pause_cursor := 0
var restart_pending := false
var restart_armed_at := 0
var details_overlay: Panel
var modal_input_guard := 0
const ReviewUI := preload("res://scripts/ui/review_ui.gd")
const UpgradeValue := preload("res://scripts/upgrade_value.gd")
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
var rerolls_remaining: Array[int] = [REROLL_START, REROLL_START]
var last_upgrade_choice_keys: Array = [[], []]
var level_up_input_delay := 0.0
var level_up_gap_remaining := 0.0 ## Blocks input right after the screen opens ## Previous level-up's offered option keys per player, so the exact same 3 don't repeat back to back
var resonance_cursors: Array[int] = [0, 0]
var tutorial_active := false
var tutorial_step := 0
var tutorial_start_kills := 0
var tutorial_start_xp := 0
var quick_ping_cooldowns: Array[float] = [0.0, 0.0]
var chain_combo_cooldown := 0.0
var boss_chain_damage_cooldown := 0.0
var pacing_announced: Dictionary = {}
var last_countdown_second := -1
## Run-long tally shown on the result screen. "pings" and "chain_bursts"
## named features that were never built; these six are events the game
## actually raises, and each is counted at the one place it happens so the
## screen cannot drift from play.
var run_stats := {
	"bosses": 0,
	"revives": 0,
	"dashes": 0,
	"overcharge_time": 0.0,
	"overloads": 0,
	"resonance_casts": 0,
	"items": 0,
	"reflected": 0.0,
}

var chain_max_length := 370.0
var chain_integrity := CHAIN_INTEGRITY_MAX
var chain_overloaded := false
var chain_ward_remaining := 0.0
var chain_ward_pulse_timer := 0.0

## Team attributes. Experience is a shared pool and both survivors level
## together, so the stats that act on that pool are shared too — one player
## owning a bigger magnet while the other does not would be incoherent when
## either of them picking a gem credits the same bar. Everything that acts on
## a survivor's own body or weapons stays personal (see ChainPlayer).
## Field drops are rare enough that finding one is an event, not a resource
## tick. Luck raises the odds the same way it weights level-up cards, and
## elites always leave something so a telegraphed hard fight has a payoff.
const FIELD_ITEM_BASE_CHANCE := 0.015
const FIELD_ITEM_LUCK_CHANCE := 0.005
const FIELD_ITEM_HEAL_RATIO := 0.3
## 사슬 결계 used to be 사슬 정비: it topped up the integrity bar and did
## nothing else, which made the rarest-but-one drop in the game a number going
## up. It is now a window instead of a refund — for its duration the chain
## cannot be strained, cannot overload, pays the full overcharge damage bonus
## no matter how the pair is standing, and burns everything that crosses it.
## Long enough to change what a fight is worth attempting, short enough that
## the pair has to decide when to spend it.
const CHAIN_WARD_DURATION := 8.0
const CHAIN_WARD_PULSE := 0.22 ## Seconds between chain burn ticks while warded.
const CHAIN_WARD_PULSE_DAMAGE := 26.0
const CHAIN_WARD_WIDTH := 74.0
const FIELD_ITEM_PURGE_DAMAGE := 120.0
const FIELD_ITEM_PURGE_RADIUS := 620.0

const EXPERIENCE_MAGNET_BASE := 155.0
var team_magnet := 1.0 ## multiplier on the shared XP pickup radius
var team_growth := 1.0 ## multiplier on all shared XP gained
var team_luck := 0
var team_overcharge := 0.0
var team_greed := 0.0
var team_level_heal := 0.0
var team_hunt_bonus := 0.0
var team_close_power := 0.0
var team_dash_burst := 0.0
## Set the first time either survivor fuses a weapon. Until then the level-up
## screen says nothing about fusion requirements: the first one is meant to be
## discovered, and every one after that is meant to be plannable.
var fusion_discovered := false ## extra weight toward new-tech and special upgrade cards

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
var treasure_loadouts: Array = [[], []] ## Per player, Array[Dictionary] of carried treasures
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
	feedback.music_enabled = settings.music_enabled
	feedback.damage_numbers_enabled = settings.damage_numbers_enabled
	screen_shake_enabled = settings.screen_shake_enabled
	weapon_controller = WeaponControllerScript.new() as WeaponController
	add_child(weapon_controller)
	weapon_controller.configure(players, weapon_loadouts, spatial_grid)
	_create_hud()
	ReviewUI.install(self)
	_begin_lobby()
	queue_redraw()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if device < 0 or device > 1:
		return
	last_input_gamepad[device] = connected
	if not connected and not lobby_active and not character_select_active and not game_over and not level_up_active and not resonance_vote_active:
		_set_pause(true)
		EditorialUI.connection_notice(self, device)


func _input(event: InputEvent) -> void:
	if is_instance_valid(details_overlay) and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("build_details") and (level_up_active or pause_active):
			ReviewUI.toggle_details(self)
			get_viewport().set_input_as_handled()
			return
		if details_overlay.visible and (event.is_action_pressed("pause") or event.is_action_pressed("menu_cancel")):
			ReviewUI.toggle_details(self)
			get_viewport().set_input_as_handled()
			return
		if details_overlay.visible and (event.is_action_pressed("menu_previous") or event.is_action_pressed("menu_next")):
			# The redesigned sheet fits every category without scrolling. Consume
			# navigation here so it cannot change a card behind the modal.
			get_viewport().set_input_as_handled()
			return
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
	if modal_input_guard > 0:
		modal_input_guard -= 1
		return
	if is_instance_valid(details_overlay) and details_overlay.visible:
		return
	# Derived from the state flags every tick rather than toggled at each of
	# the dozen places an overlay opens or closes, so it cannot drift out of
	# sync with what is actually on screen.
	var modal := (lobby_active or character_select_active or level_up_active
		or resonance_vote_active or pause_active or game_over)
	modal_dim.visible = modal
	combat_hud.visible = not lobby_active and not character_select_active
	if modal:
		for slot in 2:
			combat_hud.get_node("Carried%d" % slot).visible = false
		# Both of these live above the dim, so a fading banner or an off-screen
		# arrow would otherwise sit on top of the overlay panel.
		threat_edge_indicator.visible = false
		message_label.modulate.a = 0.0
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
		player.step_recovery(delta)
	_apply_chain_constraint()
	_update_revives(delta)
	_update_chain_ward(delta)
	_update_chain_integrity(delta)
	_update_chain_visual()
	_update_camera(delta)

	var cull_origin := (players[0].position + players[1].position) * 0.5
	for candidate in enemies.duplicate():
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		# The boss is the objective — it is never recycled for wandering off.
		if not enemy.boss and enemy.global_position.distance_to(cull_origin) > ENEMY_CULL_RADIUS:
			_cull_enemy(enemy)
			continue
		enemy.step(players, delta)
	spatial_grid.rebuild(enemies)
	# Ticked here rather than in _gain_shared_xp so the queue drains on run
	# time: the pair gets the gap back as play, not as a paused screen.
	if level_up_gap_remaining > 0.0:
		level_up_gap_remaining = maxf(0.0, level_up_gap_remaining - delta)
		if level_up_gap_remaining <= 0.0 and progression.can_level_up():
			_begin_level_up()
			return
	bursts.step(delta)
	particles.step(delta)
	_update_threat_indicator()
	experience_system.step(players, delta)
	field_items.step(players, delta)

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
				attack_timers[player_index][weapon_slot] = _weapon_interval(player_index, weapon_slot)
	weapon_controller.chain_length = chain_max_length
	weapon_controller.chain_tension = clampf(
		players[0].position.distance_to(players[1].position) / chain_max_length, 0.0, 1.0
	)
	wave_director.boss_active = is_instance_valid(boss_enemy) and not boss_enemy.dead
	for resonance in resonance_system.step(delta):
		weapon_controller.perform_resonance(resonance, _tension_damage_multiplier())
		run_stats["resonance_casts"] = int(run_stats["resonance_casts"]) + 1
	if is_instance_valid(boss_enemy) and not boss_enemy.dead:
		boss_bar.value = boss_enemy.health
		boss_health_text_label.text = "%d / %d" % [int(ceil(boss_enemy.health)), int(ceil(boss_enemy.max_health))]

	_update_hud()
	if (players[0].downed and players[1].downed) or players[0].bleedout_remaining <= 0.0 or players[1].bleedout_remaining <= 0.0:
		_end_run()


func _create_world() -> void:
	spatial_grid = SpatialGridScript.new() as EnemySpatialGrid
	progression = ProgressionScript.new() as SharedProgression
	add_child(progression)
	experience_system = ExperienceScript.new() as ExperienceSystem
	experience_system.experience_collected.connect(_gain_shared_xp)
	add_child(experience_system)
	field_items = FieldItemScript.new() as FieldItemSystem
	field_items.item_collected.connect(_on_field_item_collected)
	add_child(field_items)
	wave_director = WaveDirectorScript.new() as WaveDirector
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_calm_started.connect(_on_wave_calm_started)
	wave_director.encounter_started.connect(_on_encounter_started)
	add_child(wave_director)
	resonance_system = ResonanceScript.new() as ResonanceSystem
	add_child(resonance_system)

	arena_floor = ArenaFloorScript.new() as ArenaFloor
	add_child(arena_floor)

	bursts = BurstFieldScript.new() as BurstField
	add_child(bursts)

	particles = ParticleFieldScript.new() as ParticleField
	add_child(particles)

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
	# Godot's built-in smoothing used to run on top of the manual lerp in
	# _update_camera, so every camera move was damped twice and the view
	# lagged the pair. The manual lerp is the one that also applies shake, so
	# it stays and this one goes.
	world_camera.position_smoothing_enabled = false
	add_child(world_camera)


func _create_players() -> void:
	var player_one := PlayerScene.new() as ChainPlayer
	player_one.setup(1, Color("43d9ff"))
	player_one.position = Vector2(-105.0, 0.0)
	add_child(player_one)
	player_one.damaged.connect(_on_player_damaged)
	player_one.downed_started.connect(_on_player_downed)
	player_one.revived_player.connect(_on_player_revived)
	player_one.dashed.connect(_on_player_dashed)
	player_one.second_chance_used.connect(_on_second_chance_used)
	player_one.dodged.connect(_on_player_dodged)
	player_one.reflected.connect(_on_damage_reflected)
	player_one.footfall.connect(_on_footfall)
	players.append(player_one)

	var player_two := PlayerScene.new() as ChainPlayer
	player_two.setup(2, Color("b892ff"))
	player_two.position = Vector2(105.0, 0.0)
	add_child(player_two)
	player_two.damaged.connect(_on_player_damaged)
	player_two.downed_started.connect(_on_player_downed)
	player_two.revived_player.connect(_on_player_revived)
	player_two.dashed.connect(_on_player_dashed)
	player_two.second_chance_used.connect(_on_second_chance_used)
	player_two.dodged.connect(_on_player_dodged)
	player_two.reflected.connect(_on_damage_reflected)
	player_two.footfall.connect(_on_footfall)
	players.append(player_two)


## The HUD ran on Godot's built-in fallback font, which has no Korean weight
## worth the name — every label was the same flat grey shape. SystemFont picks a
## real family off the machine at runtime, so the game gets proper type without a
## font binary in the repository or a licence question attached to it. The list
## is ordered by preference and falls through common Korean UI families before
## giving up and taking whatever the platform offers.
const UI_FONT_FAMILIES := [
	"Pretendard", "Malgun Gothic", "Apple SD Gothic Neo",
	"NanumBarunGothic", "Noto Sans KR", "Segoe UI",
]


func _build_ui_theme_host() -> Control:
	var font := SystemFont.new()
	font.font_names = UI_FONT_FAMILIES
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	var theme := Theme.new()
	theme.default_font = font
	theme.set_color("font_color", "Label", CatTheme.CREAM)
	# Screens keep their own type scale; family and neutral ink are inherited.
	var host := Control.new()
	host.name = "ThemeHost"
	host.theme = theme
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return host


func _create_hud() -> void:
	hud_layer = CanvasLayer.new()
	var layer := _build_ui_theme_host()
	hud_layer.add_child(layer)
	add_child(hud_layer)

	# A quiet illustrated night behind every modal, below the combat HUD.
	modal_dim = CatPanel.new()
	modal_dim.backdrop = true
	modal_dim.position = Vector2.ZERO
	modal_dim.size = Vector2(1280.0, 720.0)
	modal_dim.visible = false
	layer.add_child(modal_dim)
	var screen_host := layer
	combat_hud = Control.new()
	combat_hud.name = "CombatHUD"
	combat_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(combat_hud)
	layer = combat_hud

	_make_hud_panel(layer, Vector2(18.0, 14.0), Vector2(365.0, 86.0))
	_make_hud_panel(layer, Vector2(897.0, 14.0), Vector2(365.0, 86.0))
	_make_hud_panel(layer, Vector2(430.0, 14.0), Vector2(420.0, 116.0))

	hud_portrait_icons = [
		_create_icon_rect(layer, Vector2(31.0, 20.0), Vector2(30.0, 30.0)),
		_create_icon_rect(layer, Vector2(1217.0, 20.0), Vector2(30.0, 30.0)),
	]
	p1_status_label = Label.new()
	p1_status_label.position = Vector2(66.0, 24.0)
	p1_status_label.size = Vector2(298.0, 26.0)
	p1_status_label.add_theme_font_size_override("font_size", 20)
	p1_status_label.add_theme_color_override("font_color", Color("43d9ff"))
	_confine_label(p1_status_label)
	layer.add_child(p1_status_label)
	p1_health_bar = _create_bar(layer, Vector2(34.0, 56.0), Vector2(330.0, 28.0), Color("43d9ff"))
	p1_health_text_label = _create_bar_text(layer, Vector2(34.0, 56.0), Vector2(330.0, 28.0), 15)
	p1_health_text_label.size = p1_health_bar.size

	p2_status_label = Label.new()
	p2_status_label.position = Vector2(913.0, 24.0)
	p2_status_label.size = Vector2(298.0, 26.0)
	p2_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_status_label.add_theme_font_size_override("font_size", 20)
	p2_status_label.add_theme_color_override("font_color", Color("b892ff"))
	_confine_label(p2_status_label)
	layer.add_child(p2_status_label)
	p2_health_bar = _create_bar(layer, Vector2(913.0, 56.0), Vector2(330.0, 28.0), Color("b892ff"))
	p2_health_text_label = _create_bar_text(layer, Vector2(913.0, 56.0), Vector2(330.0, 28.0), 15)
	p2_health_text_label.size = p2_health_bar.size

	hud_label = Label.new()
	hud_label.position = Vector2(440.0, 22.0)
	hud_label.size = Vector2(400.0, 30.0)
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.add_theme_font_size_override("font_size", 19)
	hud_label.add_theme_color_override("font_color", CatTheme.CREAM)
	_confine_label(hud_label)
	layer.add_child(hud_label)

	chain_bar = _create_bar(layer, Vector2(455.0, 55.0), Vector2(370.0, 21.0), Color("43d9ff"))
	chain_bar.max_value = 100.0
	chain_distance_text_label = _create_bar_text(layer, Vector2(455.0, 55.0), Vector2(370.0, 21.0), 14)
	chain_distance_text_label.size = chain_bar.size
	chain_integrity_bar = _create_bar(layer, Vector2(455.0, 81.0), Vector2(370.0, 17.0), Color("80ed99"))
	chain_integrity_bar.max_value = CHAIN_INTEGRITY_MAX
	chain_integrity_bar.value = CHAIN_INTEGRITY_MAX
	chain_integrity_text_label = _create_bar_text(layer, Vector2(455.0, 81.0), Vector2(370.0, 17.0), 12)
	chain_integrity_text_label.size = chain_integrity_bar.size
	chain_status_label = Label.new()
	chain_status_label.position = Vector2(455.0, 103.0)
	chain_status_label.size = Vector2(255.0, 22.0)
	chain_status_label.add_theme_font_size_override("font_size", 14)
	_confine_label(chain_status_label)
	layer.add_child(chain_status_label)

	resonance_status_label = Label.new()
	resonance_status_label.position = Vector2(710.0, 103.0)
	resonance_status_label.size = Vector2(115.0, 22.0)
	resonance_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	resonance_status_label.add_theme_font_size_override("font_size", 14)
	resonance_status_label.add_theme_color_override("font_color", Color("e4c1f9"))
	_confine_label(resonance_status_label)
	layer.add_child(resonance_status_label)

	boss_hud_panel = _make_hud_panel(layer, Vector2(378.0, 134.0), Vector2(524.0, 60.0))
	boss_hud_panel.visible = false
	boss_label = Label.new()
	boss_label.position = Vector2(390.0, 138.0)
	boss_label.size = Vector2(500.0, 28.0)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 19)
	boss_label.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(boss_label)
	boss_label.text = "폭주 청소 로봇"
	boss_label.visible = false
	layer.add_child(boss_label)
	boss_bar = _create_bar(layer, Vector2(390.0, 164.0), Vector2(500.0, 22.0), Color("ef476f"))
	boss_bar.visible = false
	boss_health_text_label = _create_bar_text(layer, Vector2(390.0, 164.0), Vector2(500.0, 22.0), 14)
	boss_health_text_label.size = boss_bar.size
	boss_health_text_label.visible = false

	xp_bar = _create_bar(layer, Vector2(20.0, 688.0), Vector2(1240.0, 24.0), Color("80ed99"))
	xp_bar.show_percentage = false
	xp_bar.max_value = progression.required_experience
	xp_text_label = _create_bar_text(layer, Vector2(20.0, 688.0), Vector2(1240.0, 24.0), 14)
	xp_text_label.size = xp_bar.size

	help_label = Label.new()
	help_label.position = Vector2(24.0, 660.0)
	help_label.size = Vector2(1232.0, 30.0)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.text = "캐릭터 선택 중 — 각자 고유 무기와 능력치를 확인하고 확정하세요."
	help_label.add_theme_font_size_override("font_size", 18)
	help_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.93, 0.9))
	_confine_label(help_label, true)
	layer.add_child(help_label)

	message_label = Label.new()
	# y=248 at 31px put the largest text on screen directly over the two
	# survivors — the boss warning covered the boss. It now sits in the HUD
	# band under the bars, clear of everything that moves.
	message_label.position = Vector2(340.0, 596.0)
	message_label.size = Vector2(600.0, 38.0)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 24)
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confine_label(message_label)
	message_label.modulate.a = 0.0
	_make_label_background(message_label, Color(0.02, 0.03, 0.07, 0.9))
	layer.add_child(message_label)

	layer = screen_host
	level_overlay = CatPanel.new()
	level_overlay.position = Vector2(20.0, 132.0)
	level_overlay.size = Vector2(1240.0, 545.0)
	level_overlay.visible = false
	layer.add_child(level_overlay)

	level_title = Label.new()
	level_title.position = Vector2(0.0, 24.0)
	level_title.size = Vector2(1240.0, 55.0)
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_title.add_theme_font_size_override("font_size", 31)
	level_title.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(level_title)
	level_overlay.add_child(level_title)

	level_card_labels[0] = _create_level_cards(level_overlay, 8.0, Color("43d9ff"))
	level_card_labels[1] = _create_level_cards(level_overlay, 624.0, Color("b892ff"))
	level_portrait_icons = [
		_create_icon_rect(level_overlay, Vector2(8.0, 392.0), Vector2(68.0, 68.0)),
		_create_icon_rect(level_overlay, Vector2(624.0, 392.0), Vector2(68.0, 68.0)),
	]
	level_weapon_icons[0] = _create_badged_icon_row(level_overlay, 84.0, 384.0, WEAPON_LOADOUT_CAP)
	level_weapon_icons[1] = _create_badged_icon_row(level_overlay, 700.0, 384.0, WEAPON_LOADOUT_CAP)
	level_treasure_icons[0] = _create_badged_icon_row(level_overlay, 84.0, 428.0, TREASURE_LOADOUT_CAP)
	level_treasure_icons[1] = _create_badged_icon_row(level_overlay, 700.0, 428.0, TREASURE_LOADOUT_CAP)
	p1_level_footer = _create_level_footer(level_overlay, 8.0, Color("43d9ff"))
	p2_level_footer = _create_level_footer(level_overlay, 624.0, Color("b892ff"))

	resonance_overlay = CatPanel.new()
	resonance_overlay.position = Vector2(180.0, 132.0)
	resonance_overlay.size = Vector2(920.0, 500.0)
	resonance_overlay.visible = false
	layer.add_child(resonance_overlay)

	resonance_title = Label.new()
	resonance_title.position = Vector2(0.0, 25.0)
	resonance_title.size = Vector2(920.0, 55.0)
	resonance_title.text = "둘이 함께, 냥이 공명"
	resonance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_title.add_theme_font_size_override("font_size", 29)
	resonance_title.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(resonance_title)
	resonance_overlay.add_child(resonance_title)
	_add_cat_caption(resonance_overlay, "합성 무기가 만났어요. 같은 기술에 투표하면 함께 발동!", Vector2(40, 72), Vector2(840, 25), 16)

	# Voting used to be a wall of text and two number keys, which reads as a
	# quiz rather than a decision. It is now the same card grid as the level-up
	# screen, and both survivors' cursors are drawn live on it — you can see
	# what your partner is pointing at before either of you commits, which is
	# the whole negotiation the mechanic is asking for.
	resonance_cards = []
	for index in RESONANCE_CARD_SLOTS:
		var card := Label.new()
		card.position = Vector2(
			RESONANCE_CARD_MARGIN + (RESONANCE_CARD_WIDTH + RESONANCE_CARD_GAP) * index,
			RESONANCE_CARD_Y
		)
		card.size = Vector2(RESONANCE_CARD_WIDTH, RESONANCE_CARD_HEIGHT)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		card.add_theme_font_size_override("font_size", 16)
		card.add_theme_color_override("font_color", CatTheme.CREAM)
		_confine_label(card, true)
		var style := StyleBoxFlat.new()
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		style.set_content_margin_all(14)
		style.content_margin_top = 78.0
		style.content_margin_bottom = 44.0
		card.add_theme_stylebox_override("normal", style)
		for slot in 2:
			var icon := _create_icon_rect(card, Vector2(75 + slot * 64, 14), Vector2(54, 54))
			icon.name = "Cat%d" % slot
		var pips := Label.new()
		pips.name = "Pips"
		pips.position = Vector2(10.0, RESONANCE_CARD_HEIGHT - 38.0)
		pips.size = Vector2(RESONANCE_CARD_WIDTH - 20.0, 28.0)
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pips.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pips.add_theme_font_size_override("font_size", 15)
		_confine_label(pips)
		_make_label_background(pips, Color(0.03, 0.02, 0.06, 0.85))
		card.add_child(pips)
		resonance_overlay.add_child(card)
		resonance_cards.append(card)

	resonance_status = Label.new()
	resonance_status.position = Vector2(40.0, 424.0)
	resonance_status.size = Vector2(840.0, 56.0)
	resonance_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resonance_status.add_theme_font_size_override("font_size", 17)
	resonance_status.add_theme_color_override("font_color", Color("e4c1f9"))
	_confine_label(resonance_status, true)
	resonance_overlay.add_child(resonance_status)

	character_overlay = CatPanel.new()
	character_overlay.position = Vector2(70.0, 30.0)
	character_overlay.size = Vector2(1140.0, 655.0)
	layer.add_child(character_overlay)

	character_title = Label.new()
	character_title.position = Vector2(0.0, 16.0)
	character_title.size = Vector2(1140.0, 52.0)
	character_title.text = "오늘 밤, 함께할 두 고양이"
	character_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_title.add_theme_font_size_override("font_size", 28)
	character_title.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(character_title)
	character_overlay.add_child(character_title)
	character_roster_label = Label.new()
	character_roster_label.position = Vector2(65.0, 62.0)
	character_roster_label.size = Vector2(1010.0, 26.0)
	character_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_roster_label.add_theme_font_size_override("font_size", 17)
	character_roster_label.add_theme_color_override("font_color", CatTheme.MUTED)
	_confine_label(character_roster_label)
	character_overlay.add_child(character_roster_label)
	for slot in 2:
		var bed := Panel.new()
		bed.position = Vector2(24 + slot * 564, 94)
		bed.size = Vector2(528, 477)
		bed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bed.add_theme_stylebox_override("panel", CatTheme.surface(CatTheme.INK, 24))
		character_overlay.add_child(bed)
		_add_cat_caption(character_overlay, "P%d" % (slot + 1), Vector2(46 + slot * 564, 108), Vector2(50, 30), 18)

	character_portrait_icons = [
		_create_icon_rect(character_overlay, Vector2(258.0, 92.0), Vector2(84.0, 84.0)),
		_create_icon_rect(character_overlay, Vector2(798.0, 92.0), Vector2(84.0, 84.0)),
	]
	character_p1_label = _create_character_label(Vector2(38.0, 184.0), Color("43d9ff"))
	character_p2_label = _create_character_label(Vector2(578.0, 184.0), Color("b892ff"))
	character_overlay.add_child(character_p1_label)
	character_overlay.add_child(character_p2_label)
	character_synergy_label = Label.new()
	character_synergy_label.position = Vector2(90.0, 596.0)
	character_synergy_label.size = Vector2(960.0, 44.0)
	character_synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_synergy_label.add_theme_font_size_override("font_size", 18)
	character_synergy_label.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(character_synergy_label, true)
	character_overlay.add_child(character_synergy_label)

	lobby_overlay = CatPanel.new()
	lobby_overlay.position = Vector2(90.0, 55.0)
	lobby_overlay.size = Vector2(1100.0, 610.0)
	layer.add_child(lobby_overlay)
	lobby_title = Label.new()
	lobby_title.position = Vector2(0.0, 42.0)
	lobby_title.size = Vector2(1100.0, 62.0)
	lobby_title.text = "달빛 냥이 원정대"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_font_size_override("font_size", 42)
	lobby_title.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(lobby_title, true)
	lobby_overlay.add_child(lobby_title)
	_add_cat_caption(lobby_overlay, "CO-OP SURVIVORS   /   사슬 하나, 고양이 둘", Vector2(100, 110), Vector2(900, 32), 18)
	_add_cat_caption(lobby_overlay, "친구와 발맞춰 옥상을 지켜요. 두 사람이 참가하면 출발!", Vector2(100, 153), Vector2(900, 32), 19)
	lobby_p1_label = _create_lobby_slot(Vector2(75.0, 318.0), Color("43d9ff"))
	lobby_p2_label = _create_lobby_slot(Vector2(575.0, 318.0), Color("b892ff"))
	for slot in 2:
		var portrait := _create_icon_rect(lobby_overlay, Vector2(241 + slot * 500, 200), Vector2(118, 118))
		portrait.texture = IconCatalog.survivor("lyra" if slot == 0 else "volta")
	lobby_overlay.add_child(lobby_p1_label)
	lobby_overlay.add_child(lobby_p2_label)
	var lobby_help := Label.new()
	lobby_help.position = Vector2(60.0, 535.0)
	lobby_help.size = Vector2(980.0, 50.0)
	lobby_help.text = "키보드 하나 또는 게임패드 두 개로 함께해요\nESC / START  참가 취소"
	lobby_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_help.add_theme_font_size_override("font_size", 17)
	lobby_help.add_theme_color_override("font_color", CatTheme.MUTED)
	_confine_label(lobby_help, true)
	lobby_overlay.add_child(lobby_help)

	pause_overlay = CatPanel.new()
	pause_overlay.position = Vector2(220.0, 92.0)
	pause_overlay.size = Vector2(840.0, 536.0)
	pause_overlay.visible = false
	layer.add_child(pause_overlay)
	var rest_icon := _create_icon_rect(pause_overlay, Vector2(302, 20), Vector2(56, 56))
	rest_icon.texture = IconCatalog.upgrade("recovery")
	pause_label = Label.new()
	pause_label.position = Vector2(30.0, 84.0)
	pause_label.size = Vector2(600.0, 372.0)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 20)
	_confine_label(pause_label, true)
	pause_overlay.add_child(pause_label)

	result_overlay = CatPanel.new()
	# The run summary grew (loadouts, then the co-op tally) while this panel
	# stayed the size it was, and clip_text cuts silently — the last four
	# lines, including "ENTER / A" and the whole tally, were simply gone.
	result_overlay.position = Vector2(180.0, 132.0)
	result_overlay.size = Vector2(920.0, 545.0)
	result_overlay.visible = false
	layer.add_child(result_overlay)
	result_label = Label.new()
	result_label.position = Vector2(40.0, 26.0)
	result_label.size = Vector2(840.0, 493.0)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 22)
	_confine_label(result_label, true)
	result_overlay.add_child(result_label)
	for slot in 2:
		var portrait := _create_icon_rect(result_overlay, Vector2(55 + slot * 735, 58), Vector2(75, 75))
		portrait.name = "ResultCat%d" % slot

	tutorial_label = Label.new()
	tutorial_label.position = Vector2(340.0, 570.0)
	tutorial_label.size = Vector2(600.0, 72.0)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_label.add_theme_font_size_override("font_size", 19)
	tutorial_label.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(tutorial_label, true)
	tutorial_label.visible = false
	_make_label_background(tutorial_label, Color(0.02, 0.03, 0.07, 0.9))
	layer.add_child(tutorial_label)

	team_stats_label = Label.new()
	# One shared line under the cards. The personal build sits in each
	# player’s own footer; only the pooled stats belong in the middle.
	team_stats_label.position = Vector2(150.0, 480.0)
	team_stats_label.size = Vector2(940.0, 58.0)
	team_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	team_stats_label.add_theme_font_size_override("font_size", 16)
	team_stats_label.add_theme_color_override("font_color", CatTheme.MUTED)
	_confine_label(team_stats_label)
	team_stats_label.visible = false
	_make_label_background(team_stats_label, Color(0.02, 0.03, 0.07, 0.9))
	level_overlay.add_child(team_stats_label)

	threat_edge_indicator = _create_edge_indicator(layer, Color("ff5d8f"))
	EditorialUI.apply(self)


func _make_hud_panel(parent: Node, panel_position: Vector2, panel_size: Vector2) -> ColorRect:
	var panel := CatPanel.new()
	panel.position = panel_position
	panel.size = panel_size
	parent.add_child(panel)
	return panel


func _add_cat_caption(parent: Node, text: String, at: Vector2, bounds: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = bounds
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", CatTheme.MUTED)
	_confine_label(label)
	parent.add_child(label)
	return label


func _make_label_background(label: Label, color: Color) -> void:
	var style := CatTheme.surface(CatTheme.INK.lerp(color, 0.2))
	label.add_theme_stylebox_override("normal", style)


func _confine_label(label: Label, wrap := false) -> void:
	# Fixed-size HUD panels must own their text even when Korean localization or
	# dynamic values produce a longer line than the English baseline.
	label.clip_text = true
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _create_lobby_slot(slot_position: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.position = slot_position
	label.size = Vector2(450.0, 200.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	_confine_label(label, true)
	_make_label_background(label, Color(color, 0.08))
	return label


func _create_edge_indicator(parent: Node, color: Color) -> Label:
	var label := Label.new()
	label.size = Vector2(115.0, 34.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	_confine_label(label)
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
	background.bg_color = CatTheme.INK
	background.border_color = CatTheme.OUTLINE
	background.set_border_width_all(1)
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
	background.set_corner_radius_all(int(bar_size.y * 0.5))
	fill.set_corner_radius_all(int(bar_size.y * 0.5))
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _create_bar_text(parent: Node, label_position: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f4f8ff"))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_confine_label(label)
	parent.add_child(label)
	return label


func _create_icon_rect(parent: Node, icon_position: Vector2, icon_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.position = icon_position
	icon.size = icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


## One row of small badged icons — the build ribbon uses two of them, weapons
## and treasures, in place of the two dense lines of attribute numbers that used
## to sit here. A row of icons says "this is what you are carrying" at a glance;
## "공격 100 · 범위 100 · 탄량 +0 · 신속 100" did not.
func _create_badged_icon_row(parent: Node, start_x: float, row_y: float, count: int) -> Array:
	var icons: Array = []
	for index in count:
		var socket := Panel.new()
		socket.position = Vector2(start_x + index * 42.0, row_y)
		socket.size = Vector2(38.0, 38.0)
		socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_theme_stylebox_override("panel", _slot_placeholder_style())
		parent.add_child(socket)
		var icon := _create_icon_rect(socket, Vector2.ZERO, Vector2(38.0, 38.0))
		var tier := Label.new()
		tier.name = "Tier"
		tier.position = Vector2(15.0, 21.0)
		tier.size = Vector2(24.0, 17.0)
		tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tier.add_theme_font_size_override("font_size", 10)
		tier.add_theme_color_override("font_color", Color("f4f8ff"))
		_make_label_background(tier, Color(0.01, 0.02, 0.05, 0.9))
		icon.add_child(tier)
		icons.append(icon)
	return icons


## An empty treasure slot still shows as a slot: the pair can see how many
## commitments they have left without opening anything.
func _slot_placeholder_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CatTheme.INK
	style.border_color = CatTheme.OUTLINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


## Widened twice now. The recommendation lines added to card copy made the
## old width break Korean words mid-syllable on nearly every card.
const LEVEL_CARD_WIDTH := 196.0
const LEVEL_CARD_HEIGHT := 262.0
const LEVEL_CARD_GAP := 10.0
const LEVEL_CARD_Y := 105.0

const RESONANCE_CARD_SLOTS := 3
const RESONANCE_CARD_WIDTH := 268.0
const RESONANCE_CARD_HEIGHT := 306.0
const RESONANCE_CARD_GAP := 14.0
const RESONANCE_CARD_Y := 100.0
const RESONANCE_CARD_MARGIN := 30.0

## One reroll for a whole run meant nobody ever spent it: a resource you can
## never get back is a resource you hoard. It now refills on a schedule, so
## spending one is a normal thing to do rather than a decision about the
## entire run.
const REROLL_START := 2
const REROLL_PER_LEVELS := 3
const REROLL_CAP := 3

## Extra shuffle entries each point of luck gives a build-defining option.
## At one entry per point luck moved the odds by about two cards in a
## hundred, which is not a stat worth a treasure slot.
const LUCK_WEIGHT_PER_POINT := 2


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
		card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		card.add_theme_font_size_override("font_size", 16)
		card.add_theme_color_override("font_color", CatTheme.CREAM)
		_confine_label(card, true)
		# The icon sits above the text rather than beside it, and the stylebox's
		# top margin is what makes room for it — the card used to open with three
		# blank lines, which is a layout expressed as content.
		var icon := _create_icon_rect(card, Vector2((LEVEL_CARD_WIDTH - 64.0) * 0.5, 16.0), Vector2(64.0, 64.0))
		icon.name = "Icon"
		var recommendation := Label.new()
		recommendation.name = "Recommendation"
		recommendation.position = Vector2(10.0, LEVEL_CARD_HEIGHT - 40.0)
		recommendation.size = Vector2(LEVEL_CARD_WIDTH - 20.0, 30.0)
		recommendation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		recommendation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		recommendation.add_theme_font_size_override("font_size", 13)
		recommendation.add_theme_color_override("font_color", CatTheme.GOLD)
		_confine_label(recommendation)
		_make_label_background(recommendation, Color(0.22, 0.16, 0.02, 0.95))
		card.add_child(recommendation)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(accent, 0.1)
		style.border_color = Color(accent, 0.4)
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		style.set_content_margin_all(12)
		style.content_margin_top = 92.0
		style.content_margin_bottom = 48.0
		card.add_theme_stylebox_override("normal", style)
		parent.add_child(card)
		cards.append(card)
	return cards


func _create_level_footer(parent: Node, half_x: float, color: Color) -> Label:
	var footer := Label.new()
	# 317px at font 13 wraps the attribute line in two, so the four written
	# lines became five and the last one fell outside the box — invisibly,
	# because clip_text does not complain. That fifth line is the status line:
	# "잠시 후 선택할 수 있습니다" is the only thing explaining why input is
	# ignored during the anti-misclick delay, and nobody had ever seen it.
	footer.position = Vector2(half_x + 270.0, LEVEL_CARD_Y + LEVEL_CARD_HEIGHT + 6.0)
	footer.size = Vector2(338.0, 100.0)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", color)
	_confine_label(footer, true)
	parent.add_child(footer)
	return footer


func _create_character_label(label_position: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = Vector2(524.0, 400.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	_confine_label(label, true)
	return label


func _begin_lobby() -> void:
	lobby_active = true
	lobby_joined = [false, false]
	lobby_devices = [-1, -1]
	lobby_device_names = ["", ""]
	lobby_input_cooldown = 0.25
	lobby_overlay.visible = true
	combat_hud.visible = false
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
		return "%s  ·  ✓ 참가 완료\n%s\nESC / START  취소" % [heading, lobby_device_names[slot]]
	var hint := "WASD  /  패드 1 아무 버튼" if slot == 0 else "방향키  /  패드 2 아무 버튼"
	return "%s  ·  참가 대기\n\n%s" % [heading, hint]


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
	for player_index in 2:
		var character: Dictionary = character_catalog[selected_character_indices[player_index]]
		character_portrait_icons[player_index].texture = IconCatalog.survivor(String(character["id"]))
	var roster: Array[String] = []
	for character in character_catalog:
		roster.append(String(character["name"]))
	character_roster_label.text = "   ".join(roster)
	character_synergy_label.text = _synergy_preview()
	EditorialUI.refresh_characters(self)


## The select screen used to show a name, two bars and a sentence, which is not
## enough to choose with — especially now that the weapon you pick also decides
## which fusion and which treasure your whole run is aimed at. It now shows the
## full stat block, where the weapon ends up, and a plain-language difficulty
## read so the choice can be made without knowing the catalog by heart.
## Deliberately says nothing about fusions or resonances.
##
## The card used to print "합성 X T7 + Y T4 → Z" and the strip under it listed
## the resonances the pair would eventually reach. That is the whole back half
## of the run, handed over before the run starts — the first fusion is meant to
## be found, and a resonance is meant to be the thing the pair discovers they
## have built toward. What belongs here is what the survivor is like to play
## right now: how they attack, how sturdy they are, and how demanding they are.
func _format_character_card(player_index: int) -> String:
	var character := character_catalog[selected_character_indices[player_index]]
	var weapon: Dictionary = character["weapon"]
	# The stat grid lives above this label; what belongs here
	# is the part a number cannot say. The leash line is called out separately
	# because it is the one stat that changes how both players have to move.
	var lines: Array[String] = [
		String(character["weapon_name"]),
		"피해 %.0f      %.2f초마다      %s" % [
			float(weapon["damage"]), float(weapon["cooldown"]),
			_chain_note(character),
		],
		"자력 %.0f%%      사슬 %+.0f      회피 %.0f%%" % [
			float(character["pickup"]) * 100.0, float(character["chain"]),
			float(character.get("dodge", 0.0)) * 100.0,
		],
		"",
		_character_select_status(player_index),
	]
	return "\n".join(lines)


## What this survivor does to the pair's leash, in plain language. The number
## itself is in the stat row; this says what it means.
func _chain_note(character: Dictionary) -> String:
	var contribution := float(character["chain"])
	if contribution >= 40.0:
		return "사슬 길게"
	if contribution <= -15.0:
		return "사슬 짧게"
	return "사슬 보통"


func _character_select_status(player_index: int) -> String:
	if character_confirmed[player_index]:
		var cancel := "B로 변경" if last_input_gamepad[player_index] else ("S로 변경" if player_index == 0 else "↓로 변경")
		return "선택 완료      %s" % cancel
	if last_input_gamepad[player_index]:
		return "LB / RB 선택      A 확정"
	return "A / D 선택      W 확정" if player_index == 0 else "← / → 선택      ↑ 확정"


## The pair's shared read on their two picks, without naming anything they have
## not unlocked. It compares the two survivors' demands rather than previewing
## the tech tree, because "are these two going to cover for each other" is the
## question character select actually has to answer.
func _synergy_preview() -> String:
	var first: Dictionary = character_catalog[selected_character_indices[0]]
	var second: Dictionary = character_catalog[selected_character_indices[1]]
	var first_profile := CharacterCatalog.difficulty_profile(first)
	var second_profile := CharacterCatalog.difficulty_profile(second)
	var coverage := (float(first_profile["coverage"]) + float(second_profile["coverage"])) * 0.5
	var durability := (float(first_profile["durability"]) + float(second_profile["durability"])) * 0.5

	if coverage < 0.4 and durability < 0.45:
		return "둘 다 좁게 싸우고 얇습니다 — 포위되기 전에 정리해야 합니다"
	if coverage < 0.4:
		return "둘 다 한 번에 적은 수만 처리합니다 — 몰리면 함께 물러나세요"
	if durability < 0.45:
		return "화력은 넓지만 둘 다 무릅니다 — 사슬 거리를 짧게 유지하세요"
	if coverage > 0.7 and durability > 0.6:
		return "넓게 처리하고 잘 버팁니다 — 과충전을 오래 끌고 가도 됩니다"
	return "한쪽이 넓게 쓸고 한쪽이 앞을 맡는 조합입니다"


func _start_selected_run() -> void:
	for player_index in 2:
		selected_characters[player_index] = character_catalog[selected_character_indices[player_index]].duplicate(true)
		weapon_loadouts[player_index] = [_build_weapon_state(selected_characters[player_index])]
		players[player_index].apply_character(selected_characters[player_index])
		attack_timers[player_index] = [0.15 + player_index * 0.12]
		treasure_loadouts[player_index] = []
		hud_portrait_icons[player_index].texture = IconCatalog.survivor(String(selected_characters[player_index]["id"]))
	character_select_active = false
	character_overlay.visible = false
	# The leash is decided by who was picked. Two claw-range cats fight on a
	# 275px rope, two anchors on 480px, and that single number changes more
	# about how a run plays than any stat on the card above it.
	chain_max_length = CharacterCatalog.chain_length_for(selected_characters[0], selected_characters[1])
	chain_integrity = CHAIN_INTEGRITY_MAX
	chain_overloaded = false
	chain_ward_remaining = 0.0
	chain_ward_pulse_timer = 0.0
	rerolls_remaining = [REROLL_START, REROLL_START]
	level_up_gap_remaining = 0.0
	for key in run_stats:
		run_stats[key] = 0.0 if key in ["overcharge_time", "reflected"] else 0
	last_upgrade_choice_keys = [[], []]
	team_magnet = 1.0
	team_growth = 1.0
	team_luck = 0
	team_overcharge = 0.0
	team_greed = 0.0
	team_level_heal = 0.0
	team_hunt_bonus = 0.0
	team_close_power = 0.0
	team_dash_burst = 0.0
	fusion_discovered = false
	# The shared magnet is the average of what the two cats bring to it, so a
	# Nova pair really does sweep a screen the other pairs have to walk across.
	team_magnet = (float(selected_characters[0]["pickup"]) + float(selected_characters[1]["pickup"])) * 0.5
	_apply_team_magnet()
	field_items.clear_all()
	bursts.clear_all()
	particles.clear_all()
	lobby_active = false
	lobby_overlay.visible = false
	get_tree().paused = false
	feedback.play_music("field")
	# Controls already appear on the lobby and character-select screens;
	# repeating them under the play field forever is noise.
	help_label.visible = false
	# Derived from the schedule rather than written out, which is how it came to
	# still say 02:00 after the boss moved to five minutes.
	_show_message("청소 로봇 %d대 격파 · 총 %02d:%02d" % [
		WaveDirectorScript.BOSS_COUNT, int(RUN_LENGTH) / 60, int(RUN_LENGTH) % 60
	], Color("80ed99"))


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
			# 불굴 buys time on both sides of a rescue: a longer bleedout to be
			# reached in, and a faster rescue once the partner arrives.
			downed_player.revive_progress += delta * (1.0 + rescuer.resolve * 0.05)
		else:
			downed_player.revive_progress = maxf(0.0, downed_player.revive_progress - delta * 0.55)
		if downed_player.revive_progress >= 2.6:
			downed_player.revive()
		downed_player.queue_redraw()


## Burns chain integrity while the survivors hold an overcharged gap and pays it
## back only once they close inside the resist ratio. Running the bar to zero
## overloads the chain: the damage bonus inverts into a penalty until they have
## spent long enough together to repair it.
## Runs the 사슬 결계 window: the chain is untouchable and lethal for its
## duration. Ticked before _update_chain_integrity so the integrity pass sees
## the ward and skips itself entirely rather than draining and being topped
## back up, which would leave the bar visibly stuttering.
func _update_chain_ward(delta: float) -> void:
	if chain_ward_remaining <= 0.0:
		return
	var was_active := chain_ward_remaining > 0.0
	chain_ward_remaining = maxf(0.0, chain_ward_remaining - delta)
	chain_integrity = CHAIN_INTEGRITY_MAX
	chain_overloaded = false
	chain_ward_pulse_timer -= delta
	if chain_ward_pulse_timer <= 0.0:
		chain_ward_pulse_timer = CHAIN_WARD_PULSE
		weapon_controller.burn_chain(CHAIN_WARD_WIDTH, CHAIN_WARD_PULSE_DAMAGE * _tension_damage_multiplier())
		var midpoint := (players[0].global_position + players[1].global_position) * 0.5
		particles.emit_sparks(midpoint, Color("fff275"), 5, 240.0)
	if was_active and chain_ward_remaining <= 0.0:
		_show_message("사슬 결계 해제", Color("8ecae6"))
		feedback.play_cue("warning")


func chain_warded() -> bool:
	return chain_ward_remaining > 0.0


func _update_chain_integrity(delta: float) -> void:
	if chain_warded():
		# Overcharge time still counts: the pair is holding the gap, they are
		# simply not paying for it this once. Hiding that would understate what
		# the drop actually bought them on the result screen.
		if players[0].position.distance_to(players[1].position) / chain_max_length >= CHAIN_WARNING_RATIO:
			run_stats["overcharge_time"] = float(run_stats["overcharge_time"]) + delta
		return
	var ratio := players[0].position.distance_to(players[1].position) / chain_max_length
	if ratio >= CHAIN_WARNING_RATIO:
		var strain := inverse_lerp(CHAIN_WARNING_RATIO, 1.0, minf(ratio, 1.0))
		# 과충전 코어 makes the overcharge window both stronger and cheaper to
		# hold, which is the one upgrade that rewards playing the chain badly on
		# purpose.
		var drain := lerpf(CHAIN_DRAIN_AT_WARNING, CHAIN_DRAIN_AT_LIMIT, strain)
		drain *= maxf(0.25, 1.0 - team_overcharge * 1.2)
		chain_integrity = maxf(0.0, chain_integrity - drain * delta)
		run_stats["overcharge_time"] = float(run_stats["overcharge_time"]) + delta
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
	run_stats["overloads"] = int(run_stats["overloads"]) + 1
	for player in players:
		player.hurt(CHAIN_OVERLOAD_DAMAGE, Vector2.INF, false)
	camera_shake = maxf(camera_shake, 14.0)
	feedback.play_cue("down")
	_show_message("사슬 과부하 · 서로 가까이!", Color("ff5d8f"))


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
	# A warded chain reads as one thing regardless of tension, because for its
	# duration tension has stopped meaning anything.
	if chain_warded():
		stage = 0
		chain_color = Color("fff275").lerp(Color.WHITE, 0.35 + sin(elapsed * 22.0) * 0.25)
	chain_line.default_color = chain_color
	chain_line.width = (10.0 + sin(elapsed * 16.0) * 2.0) if chain_warded() else (2.5 if chain_overloaded else 5.0)
	chain_glow.default_color = Color(chain_color, 0.30 if chain_warded() else (0.05 if chain_overloaded else 0.12 + ratio * 0.13))
	if stage == 3 and previous_chain_stage < 3:
		feedback.play_cue("warning")
		camera_shake = maxf(camera_shake, 4.0)
	previous_chain_stage = stage


## An elite or the boss can be off screen while it closes in; a partner
## cannot, because the chain caps the pair at a fraction of a screen. So one
## indicator, pointed at whichever heavy enemy is nearest and outside the
## view, clamped to the screen edge along that bearing.
func _update_threat_indicator() -> void:
	var view := Vector2(1280.0, 720.0)
	var centre := world_camera.position
	var nearest: ChaserEnemy = null
	var nearest_distance := 0.0
	for candidate in enemies:
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead or not (enemy.elite or enemy.boss):
			continue
		var offset := enemy.global_position - centre
		if absf(offset.x) < view.x * 0.5 - 40.0 and absf(offset.y) < view.y * 0.5 - 40.0:
			continue
		var distance := offset.length()
		if nearest == null or distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest == null:
		threat_edge_indicator.visible = false
		return
	var direction := (nearest.global_position - centre).normalized()
	var half := view * 0.5 - Vector2(80.0, 52.0)
	var reach := minf(half.x / maxf(0.001, absf(direction.x)), half.y / maxf(0.001, absf(direction.y)))
	threat_edge_indicator.position = view * 0.5 + direction * reach - threat_edge_indicator.size * 0.5
	threat_edge_indicator.text = "%s %dm" % ["보스" if nearest.boss else "정예", int(nearest_distance / 10.0)]
	threat_edge_indicator.add_theme_color_override("font_color", Color("fff275") if nearest.boss else Color("ff5d8f"))
	threat_edge_indicator.visible = true


func _update_camera(delta: float) -> void:
	var midpoint := (players[0].position + players[1].position) * 0.5
	var bounds := Rect2(players[0].position, Vector2.ZERO).expand(players[1].position)
	if is_instance_valid(boss_enemy) and not boss_enemy.dead and boss_enemy.position.distance_to(midpoint) < 1050.0:
		bounds = bounds.expand(boss_enemy.position)
		midpoint = bounds.get_center()
	# Reserve the upper 200 px for HUD/announcements and keep actor margins.
	var target_zoom := minf(1.0, minf(1120.0 / (bounds.size.x + 180.0), 440.0 / (bounds.size.y + 180.0)))
	world_camera.zoom = world_camera.zoom.lerp(Vector2.ONE * maxf(0.45, target_zoom), minf(1.0, delta * 5.0))
	midpoint.y -= 85.0 / world_camera.zoom.y
	var shake_offset := Vector2.ZERO
	if screen_shake_enabled and camera_shake > 0.05:
		shake_offset = Vector2(randf_range(-camera_shake, camera_shake), randf_range(-camera_shake, camera_shake))
		camera_shake = move_toward(camera_shake, 0.0, delta * 24.0)
	world_camera.position = world_camera.position.lerp(midpoint, minf(1.0, delta * 8.0)) + shake_offset
	# The rooftop follows the view rather than existing as a fixed slab, so
	# there is no edge to reach however far the pair kites.
	arena_floor.follow(world_camera.position)


## A wave only reads as a wave if it is announced. The surge waves get their
## own wording and a heavier cue so the difference is audible as well as
## visible before the enemies actually arrive.
func _on_wave_started(wave_index: int, is_surge: bool) -> void:
	if is_surge:
		_show_message("제 %d파 — 대규모 공세!" % wave_index, Color("ff5d8f"))
		feedback.play_cue("warning")
		camera_shake = maxf(camera_shake, 7.0)
	else:
		_show_message("제 %d파" % wave_index, Color("fff275"))
		feedback.play_cue("kill")


func _on_wave_calm_started(_wave_index: int) -> void:
	_show_message("잠시 숫을 돌리세요", Color("80ed99"))


func _register_enemy(enemy: ChaserEnemy) -> void:
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.ranged_attack.is_connected(_on_enemy_ranged_attack):
		enemy.ranged_attack.connect(_on_enemy_ranged_attack)
	if not enemy.damage_taken.is_connected(_on_enemy_damaged):
		enemy.damage_taken.connect(_on_enemy_damaged)
	if not enemy.chain_slam.is_connected(_on_boss_chain_slam):
		enemy.chain_slam.connect(_on_boss_chain_slam)
	if not enemy.enraged.is_connected(_on_boss_enraged):
		enemy.enraged.connect(_on_boss_enraged)
	if enemy not in enemies:
		enemies.append(enemy)
	if enemy.boss:
		boss_enemy = enemy
		boss_bar.max_value = enemy.max_health
		boss_bar.value = enemy.health
		boss_bar.visible = true
		boss_label.visible = true
		boss_label.text = "%s   %d/%d" % [
			boss_name(enemy.boss_rank), enemy.boss_rank, WaveDirectorScript.BOSS_COUNT
		]
		boss_health_text_label.text = "%d / %d" % [int(ceil(enemy.health)), int(ceil(enemy.max_health))]
		boss_health_text_label.visible = true
		_show_message("%s 출현   %d / %d" % [
			boss_name(enemy.boss_rank), enemy.boss_rank, WaveDirectorScript.BOSS_COUNT
		], Color("ff5d8f"))
		weapon_controller.play_boss_flare(enemy.global_position)
		feedback.play_cue("boss")
		feedback.play_music("boss")
		camera_shake = 10.0


## The five bosses are one escalating machine rather than the same fight five
## times, and naming them is most of what makes that legible during play — the
## stat block is behind a health bar the player never sees the number on.
const BOSS_NAMES := [
	"폭주 청소 로봇", "경비 드론 모함", "옥상 관리자", "구역 통제기", "최종 관제 코어",
]


func boss_name(rank: int) -> String:
	return String(BOSS_NAMES[clampi(rank - 1, 0, BOSS_NAMES.size() - 1)])


## A named encounter has arrived. These are announced rather than merely
## spawned: the point of a stampede or a siege is that the pair gets to decide
## how to stand before it lands, and that requires a beat of warning.
func _on_encounter_started(encounter_id: String) -> void:
	var title := wave_director.encounter_name(encounter_id)
	var friendly := encounter_id == "swarm_tide"
	_show_message("%s" % title, Color("9bf6ff") if friendly else Color("ff5d8f"))
	feedback.play_cue("select" if friendly else "warning")
	if not friendly:
		camera_shake = maxf(camera_shake, 6.0)


func _on_enemy_ranged_attack(origin: Vector2, direction: Vector2, damage: float) -> void:
	var projectile := EnemyProjectileScript.new() as EnemyProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.setup(origin, direction, damage, players)
	add_child(projectile)


## The boss's Chain Slam always drains chain integrity directly — it is
## targeting the bond itself, not the survivors — and additionally hurts
## anyone still standing inside the telegraphed impact radius when it lands.
## The boss crossing half health changes how the fight is played, so it gets
## an announcement of its own rather than passing silently.
func _on_boss_enraged(_enemy: ChaserEnemy) -> void:
	feedback.play_cue("boss_enrage")
	weapon_controller.play_boss_flare(_enemy.global_position, true)
	camera_shake = maxf(camera_shake, 12.0)
	_show_message("청소 로봇 폭주 · 속도 증가", Color("ff5d8f"))


func _on_boss_chain_slam(impact_point: Vector2, damage: float, radius: float) -> void:
	var hit_someone := false
	for player in players:
		if impact_point.distance_to(player.global_position) <= radius + player.radius:
			hit_someone = player.hurt(damage) or hit_someone
	chain_integrity = maxf(0.0, chain_integrity - BOSS_SLAM_INTEGRITY_DRAIN)
	camera_shake = maxf(camera_shake, 13.0)
	feedback.play_cue("warning")
	_show_message("사슬 강타 · 내구도 주의" if hit_someone else "충격 회피 · 내구도 주의", Color("ff5d8f"))


func _on_enemy_damaged(enemy: ChaserEnemy, amount: float) -> void:
	feedback.show_damage(enemy.global_position, amount, Color("fff4cf"))
	# Sparks scale with the hit rather than being constant, so a chip and a
	# critical do not look identical, and a screenful of swarm hits does not
	# spend the whole particle budget on chip damage.
	particles.emit_sparks(enemy.global_position, Color("fff4cf"), 2 if amount < 40.0 else 5, 150.0 + amount)
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


## 가시의 견장 sends a share of a contact hit back into whatever was standing
## where it came from. Resolved through the spatial grid rather than kept as a
## reference on the player, so a reflected hit cannot outlive its attacker.
func _on_damage_reflected(attacker_position: Vector2, amount: float) -> void:
	if amount <= 0.0:
		return
	var hit := false
	for candidate in spatial_grid.query_radius(attacker_position, 46.0):
		var enemy := candidate as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		enemy.take_damage(amount)
		hit = true
		break
	if hit:
		run_stats["reflected"] = float(run_stats["reflected"]) + amount


func _on_player_dashed(_player: ChainPlayer) -> void:
	run_stats["dashes"] = int(run_stats["dashes"]) + 1
	# Three afterimages laid back along the burst, so a dash leaves a readable
	# streak rather than teleporting the survivor a body-length sideways.
	for step in 3:
		particles.emit_ring(
			_player.global_position - _player.dash_direction * float(step) * 26.0,
			_player.body_color, _player.radius + 6.0, 0.26 + float(step) * 0.05
		)
	particles.emit_sparks(_player.global_position, _player.body_color, 6, 260.0)
	camera_shake = maxf(camera_shake, 3.0)
	feedback.play_cue("dash")
	if team_dash_burst > 0.0:
		weapon_controller.perform_pounce(_player.global_position, team_dash_burst, _player.body_color)


func _on_second_chance_used(player: ChainPlayer) -> void:
	bursts.spawn(player.global_position, Color("fff275"), 2.2)
	particles.emit_motes(player.global_position, Color("fff275"), 18)
	camera_shake = maxf(camera_shake, 8.0)
	_show_message("%s의 아홉 목숨!" % player.character_name, Color("fff275"))


func _on_player_dodged(player: ChainPlayer) -> void:
	particles.emit_ring(player.global_position, Color("f4f8ff"), player.radius + 14.0, 0.24)
	particles.emit_sparks(player.global_position, player.body_color.lightened(0.35), 5, 210.0)
	feedback.play_cue("dash")


## Dust under a running cat. Emitted from the player on its own cadence rather
## than every frame, because at two survivors times sixty frames the field
## would be nothing but dust.
func _on_footfall(at: Vector2, color: Color) -> void:
	particles.emit_dust(at, color.lerp(Color("d9c9b0"), 0.55))


func _on_player_revived(player: ChainPlayer) -> void:
	run_stats["revives"] = int(run_stats["revives"]) + 1
	feedback.play_cue("revive")
	_show_message("%s 부활 — 사슬이 다시 이어집니다" % player.character_name, Color("80ed99"))


func _set_pause(enabled: bool) -> void:
	pause_active = enabled
	restart_pending = false
	pause_cursor = 0
	pause_overlay.visible = enabled
	if enabled:
		_update_pause_text()
	get_tree().paused = enabled


func _handle_pause_input() -> void:
	if restart_pending:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
			restart_pending = false
			_update_pause_text()
		elif Input.is_action_just_pressed("menu_previous") or Input.is_action_just_pressed("menu_next"):
			pause_cursor = 1 - pause_cursor
			_update_pause_text()
		elif Input.is_action_just_pressed("menu_confirm"):
			_activate_pause_item(pause_cursor)
		return
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
		_set_pause(false)
	elif Input.is_action_just_pressed("menu_previous") or Input.is_action_just_pressed("menu_next"):
		pause_cursor = wrapi(pause_cursor + (1 if Input.is_action_just_pressed("menu_next") else -1), 0, 6)
		_update_pause_text()
	elif Input.is_action_just_pressed("menu_confirm"):
		_activate_pause_item(pause_cursor)
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
	elif Input.is_action_just_pressed("toggle_music"):
		feedback.music_enabled = not feedback.music_enabled
		feedback.refresh_music()
		_persist_settings()
		_update_pause_text()


func _persist_settings() -> void:
	settings.screen_shake_enabled = screen_shake_enabled
	settings.damage_numbers_enabled = feedback.damage_numbers_enabled
	settings.sound_enabled = feedback.sound_enabled
	settings.music_enabled = feedback.music_enabled
	settings.save_settings()


func _update_pause_text() -> void:
	EditorialUI.refresh_pause(self)
	ReviewUI.refresh_pause(self)


func _activate_pause_item(index: int) -> void:
	if not pause_active:
		return
	if restart_pending:
		if index == 0:
			restart_pending = false
			_update_pause_text()
		elif index == 1 and Time.get_ticks_msec() >= restart_armed_at:
			get_tree().paused = false
			get_tree().reload_current_scene()
		return
	match index:
		0:
			_set_pause(false)
			return
		1: screen_shake_enabled = not screen_shake_enabled
		2: feedback.damage_numbers_enabled = not feedback.damage_numbers_enabled
		3: feedback.sound_enabled = not feedback.sound_enabled
		4:
			feedback.music_enabled = not feedback.music_enabled
			feedback.refresh_music()
		5:
			restart_pending = true
			pause_cursor = 0 # Cancel is always the initial focus.
			restart_armed_at = Time.get_ticks_msec() + 400
	if index in [1, 2, 3, 4]:
		_persist_settings()
	_update_pause_text()


## Fires every weapon a player owns once — used by the physics loop's
## per-weapon cooldown check above (one call per ready weapon) and reused by
## tests that want to trigger "this player attacks now" without waiting out
## real cooldowns.
func _perform_character_attack(player_index: int) -> void:
	for weapon_slot in weapon_loadouts[player_index].size():
		weapon_controller.perform_attack(player_index, weapon_slot, _tension_damage_multiplier())


## Recycles an enemy that wandered out of the fight. Deliberately not the
## death path: nothing was killed, so there is no experience gem, no field
## drop and no kill counted.
func _cull_enemy(enemy: ChaserEnemy) -> void:
	enemies.erase(enemy)
	wave_director.release_enemy(enemy)


func _on_enemy_died(enemy: ChaserEnemy) -> void:
	var death_position := enemy.global_position
	var dropped_xp := enemy.xp_value
	var dropped_grade := enemy.xp_grade
	var defeated_boss := enemy.boss
	var was_elite := enemy.elite
	if was_elite or defeated_boss:
		dropped_xp = roundi(float(dropped_xp) * (1.0 + team_hunt_bonus))
	enemies.erase(enemy)
	kills += 1
	experience_system.spawn_gem(death_position, dropped_xp, dropped_grade)
	bursts.spawn(death_position, enemy.enemy_color, 2.6 if defeated_boss else (1.7 if was_elite else 1.0))
	feedback.play_cue("kill")
	wave_director.release_enemy(enemy)
	if defeated_boss:
		boss_bar.visible = false
		boss_label.visible = false
		boss_health_text_label.visible = false
		boss_enemy = null
		wave_director.boss_active = false
		run_stats["bosses"] = int(run_stats["bosses"]) + 1
		weapon_controller.play_boss_flare(death_position, true)
		particles.emit_motes(death_position, Color("fff275"), 20)
		camera_shake = maxf(camera_shake, 18.0)
		# Only the last one ends the run. Every other kill is a checkpoint: the
		# pair is patched up, handed a guaranteed drop, and put back on the
		# clock for the next one.
		if enemy.boss_rank >= WaveDirectorScript.BOSS_COUNT:
			_end_run(true)
			return
		for player in players:
			player.heal(player.max_health * 0.5)
		chain_integrity = CHAIN_INTEGRITY_MAX
		chain_overloaded = false
		field_items.spawn_item(death_position, field_items.roll_item_id())
		feedback.play_music("field")
		feedback.play_cue("victory")
		_show_message("%s 격파   남은 청소 로봇 %d대" % [
			boss_name(enemy.boss_rank), wave_director.bosses_remaining()
		], Color("80ed99"))
		return
	# Rolled after the boss branch on purpose: the boss carries the elite flag,
	# so rolling before it would hand out a guaranteed drop at the exact moment
	# the run ends and nobody can walk to it.
	_try_drop_field_item(death_position, was_elite)
	if kills % 18 == 0:
		for player in players:
			player.heal(8.0)
		_show_message("사슬의 마력이 회복되었습니다  +8 HP", Color("80ed99"))


## Elites always leave a drop; ordinary kills roll against a small chance that
## team luck raises. The boss is excluded because defeating it ends the run,
## so a pickup nobody can reach would just be noise.
func _try_drop_field_item(drop_position: Vector2, was_elite: bool) -> void:
	var chance := (FIELD_ITEM_BASE_CHANCE + FIELD_ITEM_LUCK_CHANCE * float(team_luck)) * (1.0 + team_greed)
	if not was_elite and randf() >= chance:
		return
	field_items.spawn_item(drop_position, field_items.roll_item_id())


## Field pickups act on the pair, not the survivor who walked over them — the
## chain already decides who can reach a drop, so making the reward personal
## would punish whoever happened to be on the wrong side of it.
func _on_field_item_collected(item_id: String) -> void:
	var label: String = field_items.item_display_name(item_id)
	var color: Color = field_items.item_color(item_id)
	match item_id:
		"heal":
			for player in players:
				player.heal(player.max_health * FIELD_ITEM_HEAL_RATIO)
			label += " — 두 사람 회복"
		"magnet":
			var pulled := experience_system.magnetize_all()
			# Two rings from the pair's midpoint so the pull has a visible source
			# and the stream of gems reads as caused rather than coincidental.
			var centre := (players[0].global_position + players[1].global_position) * 0.5
			weapon_controller.play_shockwave(centre, 900.0, color, 0.55, true)
			camera_shake = maxf(camera_shake, 4.0)
			label += " — 맵 전체 경험치 %d개 견인" % pulled
		"chain_ward":
			chain_ward_remaining = CHAIN_WARD_DURATION
			chain_ward_pulse_timer = 0.0
			chain_integrity = CHAIN_INTEGRITY_MAX
			chain_overloaded = false
			var span := players[0].global_position.distance_to(players[1].global_position)
			var centre := (players[0].global_position + players[1].global_position) * 0.5
			weapon_controller.play_shockwave(centre, maxf(320.0, span * 0.75), color, 0.5, false)
			particles.emit_motes(centre, color, 14)
			for player in players:
				particles.emit_ring(player.global_position, color, 60.0, 0.45)
			camera_shake = maxf(camera_shake, 10.0)
			label += " — %d초간 사슬 무적·과충전" % int(CHAIN_WARD_DURATION)
		"purge":
			var midpoint := (players[0].global_position + players[1].global_position) * 0.5
			var burned := 0
			for candidate in enemies.duplicate():
				var enemy := candidate as ChaserEnemy
				if not is_instance_valid(enemy) or enemy.dead:
					continue
				if midpoint.distance_to(enemy.global_position) <= FIELD_ITEM_PURGE_RADIUS:
					enemy.take_damage(FIELD_ITEM_PURGE_DAMAGE)
					burned += 1
			# The screen-clear is the biggest thing an item does, so it gets the
			# biggest presentation in the game: an expanding front, a bright core
			# flash, and a burst at every enemy it caught.
			weapon_controller.play_shockwave(midpoint, FIELD_ITEM_PURGE_RADIUS, color, 0.42, false)
			weapon_controller.play_shockwave(midpoint, FIELD_ITEM_PURGE_RADIUS * 0.55, Color.WHITE, 0.3, false)
			weapon_controller.play_purge_rays(midpoint, FIELD_ITEM_PURGE_RADIUS, color)
			camera_shake = maxf(camera_shake, 22.0)
			label += " — 적 %d체 정화" % burned
	run_stats["items"] = int(run_stats["items"]) + 1
	var pickup_centre := (players[0].global_position + players[1].global_position) * 0.5
	particles.emit_motes(pickup_centre, color, 8)
	feedback.play_item_cue(item_id)
	_show_message(label, color)


func _gain_shared_xp(amount: int) -> void:
	progression.add_experience(int(round(float(amount) * team_growth)))
	feedback.play_cue("xp")
	# Not opened here any more: the physics loop watches the queue so a level
	# earned mid-burst waits out the gap instead of interrupting on the frame
	# the gem happened to land.
	if not level_up_active and progression.can_level_up() and level_up_gap_remaining <= 0.0:
		_begin_level_up()


func _begin_level_up() -> void:
	if not progression.consume_level_up():
		return
	if progression.level % REROLL_PER_LEVELS == 0:
		for slot in 2:
			rerolls_remaining[slot] = mini(REROLL_CAP, rerolls_remaining[slot] + 1)
	level_up_active = true
	level_up_input_delay = LEVEL_UP_INPUT_DELAY
	level_up_gap_remaining = 0.0
	selected_upgrade_indices = [-1, -1]
	upgrade_cursors = [0, 0]
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
	var option_id := String(option["id"])
	if option_id == "unlock_weapon":
		return "unlock_weapon:" + String((option["character"] as Dictionary)["id"])
	if option_id == "unlock_treasure":
		return "unlock_treasure:" + String((option["treasure"] as Dictionary)["id"])
	if option_id == "treasure_upgrade":
		return "treasure_upgrade:%d" % int(option["treasure_slot"])
	return "%s:%d" % [option_id, int(option.get("weapon_slot", -1))]


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


## Treasures this player does not already carry, shuffled and capped. Mirrors
## _pick_unowned_characters so both halves of a build are offered the same way.
## The fusion a weapon slot could perform right now, or an empty dictionary.
## Both halves have to be satisfied: the weapon maxed, and the treasure it
## wants carried deep enough.
func _available_evolution(slot: int, weapon_slot: int) -> Dictionary:
	var weapon: Dictionary = weapon_loadouts[slot][weapon_slot]
	if bool(weapon.get("evolved", false)):
		return {}
	if int(weapon.get("tier", 1)) < Evolutions.WEAPON_MAX_TIER:
		return {}
	var evolution := Evolutions.for_base(String(weapon["weapon_id"]))
	if evolution.is_empty():
		return {}
	if _treasure_tier(slot, String(evolution["treasure_id"])) < Evolutions.REQUIRED_TREASURE_TIER:
		return {}
	return evolution


func _treasure_tier(slot: int, treasure_id: String) -> int:
	for treasure in treasure_loadouts[slot]:
		if String(treasure["id"]) == treasure_id:
			return int(treasure["tier"])
	return 0


func _pick_unowned_treasures(slot: int, count: int) -> Array[Dictionary]:
	var owned_ids: Dictionary = {}
	for treasure in treasure_loadouts[slot]:
		owned_ids[String(treasure["id"])] = true
	var candidates: Array[Dictionary] = []
	for treasure in Treasures.all_treasures():
		if not owned_ids.has(String(treasure["id"])):
			candidates.append(treasure)
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
	var treasures: Array = treasure_loadouts[slot]
	var pool: Array[Dictionary] = []

	# Carried treasures can be deepened; the twelve that are not carried are
	# only reachable while there is still a free slot. That gating is the whole
	# point of the system — an unlimited stat pool has no decisions in it.
	for treasure_slot in treasures.size():
		var treasure: Dictionary = treasures[treasure_slot]
		if int(treasure["tier"]) >= Treasures.MAX_TIER:
			continue
		pool.append({
			"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": treasure_slot,
			"title": String(treasure["name"]),
		})
	if treasures.size() < TREASURE_LOADOUT_CAP:
		# A fixed number of candidates: luck acts on the weighting below and
		# nowhere else. Scaling the candidate count as well pulled the other
		# way — more unlock entries in the pool means each one is drawn less
		# often — and left luck with no measurable direction at all.
		for treasure in _pick_unowned_treasures(slot, 3):
			pool.append({
				"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure,
				"title": "새 보물: %s" % String(treasure["name"]),
			})
	for weapon_slot in loadout.size():
		var weapon_name := String(loadout[weapon_slot]["weapon_name"])
		var weapon_id := String(loadout[weapon_slot]["weapon_id"])
		pool.append({"id": "weapon_power", "weapon_slot": weapon_slot, "title": "마력 증폭\n%s" % weapon_name})
		pool.append({"id": "weapon_rate", "weapon_slot": weapon_slot, "title": "고속 시전\n%s" % weapon_name})
		for key: String in ["a", "b"]:
			var spec := _special_spec(weapon_id, key)
			if spec.is_empty():
				continue
			pool.append({
				"id": "special_" + key, "weapon_slot": weapon_slot,
				"title": "%s\n%s" % [String(spec["title"]), weapon_name],
			})
	# A fusion is the biggest single step in the tree, so its card is added
	# unconditionally whenever one is available rather than competing for a
	# slot in the shuffle.
	for weapon_slot in loadout.size():
		var evolution := _available_evolution(slot, weapon_slot)
		if evolution.is_empty():
			continue
		pool.append({
			"id": "evolve_weapon", "weapon_slot": weapon_slot, "evolution": evolution,
			"title": "합성: %s" % String(evolution["weapon_name"]),
		})
	if loadout.size() < WEAPON_LOADOUT_CAP:
		for character in _pick_unowned_characters(slot, 2):
			pool.append({
				"id": "unlock_weapon", "weapon_slot": -1, "character": character,
				"title": "신규 기술: %s" % String(character["weapon_name"])
			})
	pool = pool.filter(func(option: Dictionary) -> bool: return UpgradeValue.has_effect(self, slot, option))
	var ready_fusions: Array[Dictionary] = []
	for option in pool:
		if option["id"] == "evolve_weapon":
			ready_fusions.append(option)
		option["description"] = _upgrade_preview(slot, option)

	var previous_keys: Array = last_upgrade_choice_keys[slot]
	var fresh_pool: Array[Dictionary] = []
	for option in pool:
		if not (_option_key(option) in previous_keys):
			fresh_pool.append(option)
	if fresh_pool.size() >= 3:
		pool = fresh_pool

	# Luck's one job: build-defining options — a new weapon, a new treasure, or
	# a weapon's unique special rather than a flat number — get an extra entry
	# in the shuffle per point, so they come up more often.
	var weighted: Array[Dictionary] = pool.duplicate()
	for extra in team_luck * LUCK_WEIGHT_PER_POINT:
		for option in pool:
			var option_id := String(option["id"])
			if option_id in ["unlock_weapon", "unlock_treasure", "special_a", "special_b"]:
				weighted.append(option)

	weighted.shuffle()
	var choices: Array[Dictionary] = []
	var chosen_keys: Array = []
	for option in ready_fusions.slice(0, 3):
		choices.append(option)
		chosen_keys.append(_option_key(option))
	for option in weighted:
		if choices.size() >= 3:
			break
		var key := _option_key(option)
		if key in chosen_keys:
			continue
		choices.append(option)
		chosen_keys.append(key)

	# Tier progress is the only route to resonance, so at least one weapon
	# upgrade is always on the table. Without this the attribute cards dilute
	# the pool badly enough (roughly 4 weapon options among 17) that a pair
	# could go several levels without either weapon reaching tier 3.
	if not _has_weapon_upgrade(choices) and not loadout.is_empty():
		var weapon_options: Array[Dictionary] = []
		for option in pool:
			if int(option.get("weapon_slot", -1)) >= 0:
				weapon_options.append(option)
		if not weapon_options.is_empty():
			weapon_options.shuffle()
			choices[choices.size() - 1] = weapon_options[0]

	var choice_keys: Array = []
	for option in choices:
		choice_keys.append(_option_key(option))
	last_upgrade_choice_keys[slot] = choice_keys
	_annotate_recommendations(slot, choices)
	return choices


## Every base weapon's two unique upgrades, in one table.
##
## Four of the ten weapons — 궤도 파편, 관통 광선, 지뢰 결계, 중력 붕괴 — had no
## specials at all: they could only ever be handed flat damage and cooldown,
## which is exactly the "every weapon plays the same" problem. They have them
## now, and the table is the reason all ten stay in step: the card pool, the
## application and the preview text are all generated from these entries, so a
## weapon cannot end up offerable but inert, or upgraded but silent about it.
##
## `target: "run"` marks the one upgrade that changes something outside the
## weapon — 느슨한 족쇄 lengthens the pair's leash, which is both a freedom
## upgrade and, since 결속 파동 scales with tension, a damage one.
const WEAPON_SPECIALS := {
	"homing": {
		"a": {"title": "다중 유도", "label": "동시 발사", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "마력 추진", "label": "투사체 속도", "field": "speed", "delta": 70.0},
	},
	"lightning": {
		"a": {"title": "연쇄 전도", "label": "연쇄", "field": "jumps", "delta": 1, "integer": true},
		"b": {"title": "확장 도체", "label": "첫 타격 사거리", "field": "range", "delta": 55.0},
	},
	"flame": {
		"a": {"title": "불씨 범람", "label": "화염탄", "field": "count", "delta": 2, "integer": true},
		"b": {"title": "열풍 추진", "label": "투사체 속도", "field": "speed", "delta": 55.0},
	},
	"frost": {
		"a": {"title": "혹한 영역", "label": "반경", "field": "radius", "delta": 30.0},
		"b": {"title": "동상", "label": "감속 배율", "field": "slow", "delta": -0.08, "floor": 0.25, "percent": true},
	},
	"scythe": {
		"a": {"title": "긴 자루", "label": "사거리", "field": "range", "delta": 30.0},
		"b": {"title": "보름베기", "label": "공격 각도", "field": "arc", "delta": 0.25, "cap": PI * 1.75, "degrees": true},
	},
	"chain": {
		"a": {"title": "넓은 파동", "label": "파동 폭", "field": "width", "delta": 14.0},
		"b": {"title": "느슨한 족쇄", "label": "사슬 한계", "field": "chain_length", "delta": 45.0, "target": "run"},
	},
	"orbit": {
		"a": {"title": "파편 증식", "label": "파편 수", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "확장 궤도", "label": "궤도 반경", "field": "radius", "delta": 22.0},
	},
	"lance": {
		"a": {"title": "장사정", "label": "사거리", "field": "range", "delta": 90.0},
		"b": {"title": "분광", "label": "광선 수", "field": "beams", "delta": 1, "integer": true},
	},
	"mine": {
		"a": {"title": "다중 매설", "label": "매설 수", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "광역 결계", "label": "폭발 반경", "field": "radius", "delta": 22.0},
	},
	"gravity": {
		"a": {"title": "사건 확대", "label": "붕괴 반경", "field": "radius", "delta": 35.0},
		"b": {"title": "강한 인력", "label": "인력", "field": "pull", "delta": 70.0,
			"extra_field": "cast_range", "extra_delta": 60.0},
	},
}


## The spec for one weapon's special, or an empty dictionary if it has none —
## fused weapons are already at the top of their track and take neither.
func _special_spec(weapon_id: String, key: String) -> Dictionary:
	var entry: Dictionary = WEAPON_SPECIALS.get(weapon_id, {})
	return entry.get(key, {})


func _special_current(spec: Dictionary, state: Dictionary) -> float:
	if String(spec.get("target", "weapon")) == "run":
		return chain_max_length
	return float(state.get(String(spec["field"]), 0.0))


## The value this special would move its field to, floors and caps applied.
func _special_next(spec: Dictionary, current: float) -> float:
	var moved := current + float(spec["delta"])
	if spec.has("floor"):
		moved = maxf(float(spec["floor"]), moved)
	if spec.has("cap"):
		moved = minf(float(spec["cap"]), moved)
	return moved


## Whether taking this special would actually change anything. Only the two
## bounded specials can ever answer no, but asking generically is what keeps a
## future bounded one from quietly becoming a dead card.
func _special_has_room(slot: int, weapon_slot: int, key: String) -> bool:
	var state: Dictionary = weapon_loadouts[slot][weapon_slot]
	var spec := _special_spec(String(state["weapon_id"]), key)
	if spec.is_empty():
		return false
	var current := _special_current(spec, state)
	return not is_equal_approx(_special_next(spec, current), current)


## Applies a special to a weapon state dictionary in place. Takes the state
## rather than a loadout index so the recommendation scorer can run it against
## a throwaway copy without touching the real build.
func apply_special_to_state(state: Dictionary, key: String) -> void:
	var spec := _special_spec(String(state["weapon_id"]), key)
	if spec.is_empty() or String(spec.get("target", "weapon")) == "run":
		return
	var field := String(spec["field"])
	var next := _special_next(spec, float(state.get(field, 0.0)))
	state[field] = int(round(next)) if bool(spec.get("integer", false)) else next
	if spec.has("extra_field"):
		var extra := String(spec["extra_field"])
		state[extra] = float(state.get(extra, 0.0)) + float(spec["extra_delta"])


func _special_preview(spec: Dictionary, state: Dictionary) -> String:
	var current := _special_current(spec, state)
	var next := _special_next(spec, current)
	if bool(spec.get("integer", false)):
		return "%s %d → %d" % [String(spec["label"]), int(round(current)), int(round(next))]
	if bool(spec.get("percent", false)):
		return "%s %.0f%% → %.0f%%" % [String(spec["label"]), current * 100.0, next * 100.0]
	if bool(spec.get("degrees", false)):
		return "%s %.0f° → %.0f°" % [String(spec["label"]), rad_to_deg(current), rad_to_deg(next)]
	return "%s %.0f → %.0f" % [String(spec["label"]), current, next]


func _has_weapon_upgrade(options: Array) -> bool:
	for option in options:
		if int(option.get("weapon_slot", -1)) >= 0:
			return true
	return false


## Rates only the three cards that were actually dealt. The score combines
## expected combat value, current survivability, run timing and the build graph:
## an option that creates a new tier-3 weapon pairing wins a large explicit
## bonus because it immediately unlocks a resonance vote.
func _annotate_recommendations(slot: int, choices: Array[Dictionary]) -> void:
	var best_index := -1
	var best_score := -INF
	for index in choices.size():
		var rating := _score_upgrade_option(slot, choices[index])
		choices[index]["recommendation_score"] = float(rating["score"])
		choices[index]["recommendation_reason"] = String(rating["reason"])
		choices[index]["recommended"] = false
		if float(rating["score"]) > best_score:
			best_score = float(rating["score"])
			best_index = index
	if best_index >= 0:
		choices[best_index]["recommended"] = true


## Scores one card so the level-up screen can star the strongest. Treasures are
## scored on the attribute they actually grant rather than on the wrapper id, so
## the same table serves "take this treasure" and "deepen the one you hold" —
## the difference between them is the slot pressure and depth adjustments after
## the table, not a second copy of it.
##
## Reasons are deliberately short. They sit on a card that already carries a
## title, an effect line and a tier line, and a sentence there is noise.
func _score_upgrade_option(slot: int, option: Dictionary) -> Dictionary:
	var upgrade_id := String(option["id"])
	var loadout: Array = weapon_loadouts[slot]
	var treasures: Array = treasure_loadouts[slot]
	var player := players[slot]
	var health_ratio := player.health / maxf(1.0, player.max_health)
	var is_treasure := upgrade_id in ["unlock_treasure", "treasure_upgrade"]
	var effect_id := _option_icon_id(slot, option) if is_treasure else upgrade_id
	var score := 20.0
	var reason := "균형 성장"
	match effect_id:
		"weapon_power":
			score = 50.0
			reason = "주력 피해"
		"weapon_rate":
			score = 47.0
			reason = "발동 빈도"
		"special_a", "special_b":
			score = 28.0
			reason = "제어 · 편의 강화"
			var w: Dictionary = loadout[int(option["weapon_slot"])]
			if upgrade_id == "special_b" and w.has("speed"):
				score += 30.0 * (70.0 if w["weapon_id"] == "homing" else 55.0) / maxf(1.0, float(w["speed"]))
			if upgrade_id == "special_b" and w["weapon_id"] == "frost":
				score += (1.0 - health_ratio) * 30.0
		"might":
			score = 39.0 + loadout.size() * 7.0
			reason = "무기 %d종 강화" % loadout.size()
		"area":
			score = 38.0 + loadout.size() * 4.0
			reason = "전체 범위"
		"amount":
			score = 45.0
			reason = "투사체 화력"
		"haste":
			score = 43.0 + loadout.size() * 5.0
			reason = "전체 발동"
		"projectile_speed":
			score = 36.0
			reason = "명중 안정화"
		"vitality":
			score = 34.0 + (1.0 - health_ratio) * 48.0
			reason = "체력 여유" if health_ratio >= 0.5 else "위기 생존"
		"armor":
			score = 35.0 + minf(20.0, elapsed / 6.0) + (1.0 - health_ratio) * 18.0
			reason = "접촉 피해 절감"
		"recovery":
			score = 34.0 + (1.0 - health_ratio) * 30.0
			reason = "장기 생존"
		"move":
			score = 34.0
			reason = "회피와 구조 기동"
		"magnet":
			score = 32.0 + maxf(0.0, 12.0 - progression.level)
			reason = "XP 회수"
		"growth":
			score = 52.0 - progression.level * 3.0
			reason = "성장 가속"
		"luck":
			score = 40.0 - progression.level * 1.5
			reason = "희귀 카드 확률"
		"catnip":
			score = 31.0 + (1.0 - health_ratio) * 38.0
			reason = "성장 때 팀 회복"
		"bounty_bell":
			score = 55.0 - progression.level * 1.7
			reason = "강적 XP 증폭"
		"twin_charm":
			score = 42.0 + maxf(0.0, 10.0 - team_overcharge * 20.0)
			reason = "밀착 전투 화력"
		"dash_claw":
			score = 40.0 + minf(12.0, float(run_stats["dashes"]) * 0.5)
			reason = "대시를 공격으로"
		"lucky_paw":
			score = 38.0 + (1.0 - health_ratio) * 30.0
			reason = "피해 완전 회피"
		"nine_lives":
			score = 58.0 + (1.0 - health_ratio) * 34.0
			reason = "치명타 1회 무효"
		"unlock_weapon":
			score = 44.0 + (WEAPON_LOADOUT_CAP - loadout.size()) * 4.0
			reason = "공격 축 추가"
		"evolve_weapon":
			# Nothing else on the screen is close: a fusion reworks the attack and
			# is the only route to resonance.
			score = 200.0
			reason = "합성 — 최종 단계"

	var marginal := UpgradeValue.gain(self, slot, option)
	if marginal > 0.0 and upgrade_id != "evolve_weapon":
		score = 25.0 + minf(110.0, marginal * 220.0)
		reason = "예상 화력 +%d%%" % maxi(1, roundi(marginal * 100.0))
	elif upgrade_id in ["weapon_power", "weapon_rate"]:
		score = 0.0
	# Reward only treasures on an owned, unfinished fusion path.
	if is_treasure:
		if not UpgradeValue.benefits_loadout(loadout, effect_id):
			score = 5.0
			reason = "후속 무기 준비"
		# A treasure that is the missing half of a fusion used to be worth a flat
		# +20, which loses to a generic damage card at 50 — so the screen would
		# recommend more damage to a pair standing one treasure tier away from
		# reworking their whole weapon. The bonus now scales with how complete
		# the path already is, which makes the last step before a fusion the
		# strongest ordinary card in the pool without ever outranking the fusion
		# card itself.
		var path := _fusion_path_value(slot, effect_id)
		if not path.is_empty():
			score += float(path["value"])
			reason = String(path["reason"])
	if upgrade_id == "unlock_treasure":
		# Slots are finite now, so committing one is worth more while several
		# are open and less when it would spend the last of them on a whim.
		var free_slots := TREASURE_LOADOUT_CAP - treasures.size()
		score += 6.0 if free_slots > 1 else -8.0
		reason = "%s   슬롯 %d칸" % [reason, free_slots]
	elif upgrade_id == "treasure_upgrade":
		# Deepening is the payoff for having committed, and a treasure one step
		# from its cap is the cheapest remaining power in the pool.
		var carried: Dictionary = treasures[int(option["treasure_slot"])]
		var tier := int(carried["tier"])
		score += float(tier) * 3.0
		if tier + 1 >= Treasures.MAX_TIER:
			score += 10.0
			reason = "%s   최종 티어" % reason
		else:
			reason = "%s   T%d" % [reason, tier + 1]

	var new_resonance := _new_resonance_from_option(slot, option)
	if not new_resonance.is_empty():
		score += 120.0
		reason = "공명 해금   %s" % new_resonance
	elif int(option.get("weapon_slot", -1)) >= 0:
		var weapon: Dictionary = loadout[int(option["weapon_slot"])]
		if int(weapon.get("tier", 1)) == Evolutions.WEAPON_MAX_TIER - 1:
			score += 34.0
			reason = "T%d   합성 직전" % Evolutions.WEAPON_MAX_TIER
	return {"score": score, "reason": reason}


## What a treasure is worth as fusion material, given how far along that fusion
## already is. Returns an empty dictionary when the treasure feeds no fusion this
## survivor is actually working toward.
##
## Progress is measured over both requirements together, so "weapon maxed,
## treasure one tier short" scores far above "weapon at tier 2, treasure one tier
## short" — the same card, but only one of them is the last step.
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


func _fusion_path_value(slot: int, treasure_id: String) -> Dictionary:
	var best := {}
	var best_progress := -1.0
	for weapon: Dictionary in weapon_loadouts[slot]:
		if bool(weapon.get("evolved", false)):
			continue
		var evolution := Evolutions.for_base(String(weapon["weapon_id"]))
		if evolution.is_empty() or String(evolution.get("treasure_id", "")) != treasure_id:
			continue
		var treasure_tier := _treasure_tier(slot, treasure_id)
		if treasure_tier >= Evolutions.REQUIRED_TREASURE_TIER:
			continue # this half is already done; the weapon is what is missing
		var weapon_progress := float(int(weapon.get("tier", 1))) / float(Evolutions.WEAPON_MAX_TIER)
		var treasure_progress := float(treasure_tier) / float(Evolutions.REQUIRED_TREASURE_TIER)
		var progress := (weapon_progress + treasure_progress) * 0.5
		if progress <= best_progress:
			continue
		best_progress = progress
		var weapon_tier := int(weapon.get("tier", 1))
		var last_step: bool = (
			treasure_tier + 1 >= Evolutions.REQUIRED_TREASURE_TIER
			and weapon_tier >= Evolutions.WEAPON_MAX_TIER
		)
		best = {
			"value": 24.0 + progress * 90.0 + (40.0 if last_step else 0.0),
			"reason": "%s 합성 재료" % String(evolution["weapon_name"]) if not last_step else "%s 합성까지 한 걸음" % String(evolution["weapon_name"]),
		}
	return best


func _new_resonance_from_option(slot: int, option: Dictionary) -> String:
	var before := resonance_system.get_candidates_for_loadouts(weapon_loadouts[0], weapon_loadouts[1])
	var known: Dictionary = {}
	for candidate in before:
		known[String(candidate["id"])] = true
	var preview: Array = [weapon_loadouts[0].duplicate(true), weapon_loadouts[1].duplicate(true)]
	var option_id := String(option["id"])
	if option_id == "unlock_weapon":
		preview[slot].append(_build_weapon_state(option["character"] as Dictionary))
	elif option_id == "evolve_weapon":
		# The only card that can actually open a resonance now that the gate is
		# fusion: a tier bump on an unfused weapon never reaches it.
		var fusing_slot := int(option["weapon_slot"])
		preview[slot][fusing_slot] = Evolutions.build_state(option["evolution"], preview[slot][fusing_slot])
	else:
		var weapon_slot := int(option.get("weapon_slot", -1))
		if weapon_slot < 0:
			return ""
		preview[slot][weapon_slot]["tier"] = int(preview[slot][weapon_slot].get("tier", 1)) + 1
	for candidate in resonance_system.get_candidates_for_loadouts(preview[0], preview[1]):
		if not known.has(String(candidate["id"])):
			return String(candidate["name"])
	return ""


func _upgrade_preview(slot: int, option: Dictionary) -> String:
	var upgrade_id := String(option["id"])
	if upgrade_id == "unlock_weapon":
		var character: Dictionary = option["character"]
		var tag_names: Array[String] = []
		for tag in (character["tags"] as Array):
			tag_names.append(_tag_name(String(tag)))
		return "%s\n피해 %.0f · %.2f초" % [EditorialUI.PLAYSTYLE.get(String(character["weapon_id"]), "자동 공격"), float(character["weapon"]["damage"]), float(character["weapon"]["cooldown"])]
	if upgrade_id == "evolve_weapon":
		var evolution: Dictionary = option["evolution"]
		return "%s\n최종 단계 도달" % String(evolution["description"])
	if upgrade_id == "unlock_treasure":
		var treasure: Dictionary = option["treasure"]
		return "%s
보물 %d/%d칸" % [
			String(treasure["per_tier"]), treasure_loadouts[slot].size() + 1, TREASURE_LOADOUT_CAP
		]
	if upgrade_id == "treasure_upgrade":
		var carried: Dictionary = treasure_loadouts[slot][int(option["treasure_slot"])]
		return "%s
T%d → T%d" % [
			String(carried["per_tier"]), int(carried["tier"]), int(carried["tier"]) + 1
		]
	var weapon_slot := int(option["weapon_slot"])
	var state: Dictionary = weapon_loadouts[slot][weapon_slot]
	var weapon_id := String(state["weapon_id"])
	var tier := int(state.get("tier", 1))
	var tier_hint := "\nT%d → T%d" % [tier, mini(Evolutions.WEAPON_MAX_TIER, tier + 1)]
	if tier + 1 >= Evolutions.WEAPON_MAX_TIER and not bool(state.get("evolved", false)):
		tier_hint = "\nT%d — 합성 직전" % Evolutions.WEAPON_MAX_TIER
	match upgrade_id:
		"weapon_power":
			return "피해 %.1f → %.1f%s" % [float(state["damage"]), float(state["damage"]) * 1.25, tier_hint]
		"weapon_rate":
			return "발동 %.2f초 → %.2f초%s" % [float(state["cooldown"]), maxf(0.2, float(state["cooldown"]) * 0.88), tier_hint]
		"special_a", "special_b":
			var spec := _special_spec(weapon_id, upgrade_id.substr(upgrade_id.length() - 1))
			if not spec.is_empty():
				return _special_preview(spec, state) + tier_hint
	return "현재 능력을 강화합니다."


func _handle_level_up_input() -> void:
	if level_up_input_delay > 0.0:
		level_up_input_delay = maxf(0.0, level_up_input_delay - get_physics_process_delta_time())
		if level_up_input_delay <= 0.0:
			_refresh_level_up_ui()
		return
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
			feedback.play_cue("select")
			_select_upgrade(player_index, upgrade_cursors[slot])
		elif Input.is_action_just_pressed("p%d_reroll" % player_index) and rerolls_remaining[slot] > 0:
			_reroll_choices(player_index)


## The previous draw's keys are already excluded by _get_upgrade_choices, so a
## reroll is guaranteed to move — a reroll that can hand back the same three
## cards is worse than no reroll at all.
func _reroll_choices(player_index: int) -> void:
	var slot := player_index - 1
	rerolls_remaining[slot] -= 1
	feedback.play_cue("reroll")
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
	if upgrade_id == "evolve_weapon":
		var weapon_slot := int(option["weapon_slot"])
		var base_state: Dictionary = weapon_loadouts[player_slot][weapon_slot]
		weapon_loadouts[player_slot][weapon_slot] = Evolutions.build_state(option["evolution"], base_state)
		fusion_discovered = true
		feedback.play_cue("resonance")
		_show_message("합성 완성 — %s" % String((option["evolution"] as Dictionary)["weapon_name"]), Color("fff275"))
		return
	if upgrade_id == "unlock_treasure":
		var treasure: Dictionary = option["treasure"]
		var state := Treasures.build_state(treasure)
		treasure_loadouts[player_slot].append(state)
		_apply_attribute(player_slot, String(state["id"]))
		return
	if upgrade_id == "treasure_upgrade":
		var carried: Dictionary = treasure_loadouts[player_slot][int(option["treasure_slot"])]
		carried["tier"] = int(carried["tier"]) + 1
		_apply_attribute(player_slot, String(carried["id"]))
		return
	var weapon_slot := int(option["weapon_slot"])
	var state: Dictionary = weapon_loadouts[player_slot][weapon_slot]
	var weapon_id := String(state["weapon_id"])
	match upgrade_id:
		"weapon_power":
			state["damage"] = float(state["damage"]) * 1.25
		"weapon_rate":
			state["cooldown"] = maxf(0.2, float(state["cooldown"]) * 0.88)
		"special_a", "special_b":
			var key := upgrade_id.substr(upgrade_id.length() - 1)
			var spec := _special_spec(weapon_id, key)
			if not spec.is_empty() and String(spec.get("target", "weapon")) == "run":
				chain_max_length = _special_next(spec, chain_max_length)
			else:
				apply_special_to_state(state, key)
	if upgrade_id in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
		state["tier"] = mini(Evolutions.WEAPON_MAX_TIER, int(state.get("tier", 1)) + 1)


## Applies an attribute card and reports whether it handled the id, so
## _apply_upgrade can fall through to the weapon-slot path for everything else.
func _apply_attribute(player_slot: int, upgrade_id: String) -> bool:
	var player := players[player_slot]
	match upgrade_id:
		"move":
			player.move_speed *= 1.08
		"vitality":
			player.max_health += 15.0
			player.heal(15.0)
		"might":
			player.might += 0.15
		"area":
			player.area += 0.15
		"amount":
			player.amount += 1
		"haste":
			player.haste = maxf(0.4, player.haste - 0.1)
		"projectile_speed":
			player.projectile_speed += 0.15
		"armor":
			player.armor += 2.0
		"recovery":
			player.recovery += 0.8
		"crit":
			player.crit_chance = minf(0.85, player.crit_chance + 0.08)
		"pierce":
			player.pierce += 1
		"thorns":
			player.thorns += 0.15
		"resolve":
			player.resolve += 4.0
		"overcharge":
			team_overcharge += 0.10
		"greed":
			team_greed += 0.40
		"magnet":
			team_magnet += 0.25
			_apply_team_magnet()
		"growth":
			team_growth += 0.15
		"luck":
			team_luck += 1
		"catnip":
			team_level_heal += 0.05
		"bounty_bell":
			team_hunt_bonus += 0.25
		"twin_charm":
			team_close_power += 0.08
		"dash_claw":
			team_dash_burst += 16.0
		"lucky_paw":
			player.dodge_chance = minf(0.60, player.dodge_chance + 0.04)
		"nine_lives":
			player.second_chances += 1
		_:
			return false
	return true


func _refresh_level_up_ui() -> void:
	level_title.text = "성장 선택   /   LV.%02d" % progression.level
	_refresh_player_cards(1)
	_refresh_player_cards(2)
	_refresh_team_stats_ui()


func _refresh_player_cards(player_index: int) -> void:
	var slot := player_index - 1
	var choices := p1_choices if player_index == 1 else p2_choices
	var cards: Array = level_card_labels[slot]
	var locked := selected_upgrade_indices[slot] >= 0
	var accent := CatTheme.P1 if player_index == 1 else CatTheme.P2

	for index in cards.size():
		var card: Label = cards[index]
		var option: Dictionary = choices[index] if index < choices.size() else {}
		var style := card.get_theme_stylebox("normal") as StyleBoxFlat
		var is_unlock := String(option.get("id", "")) == "unlock_weapon"
		var is_focused := not locked and index == upgrade_cursors[slot]
		var is_chosen := locked and index == selected_upgrade_indices[slot]
		var is_recommended := bool(option.get("recommended", false))

		card.visible = (not locked) or is_chosen
		card.text = "%s\n%s" % [String(option.get("title", "")), String(option.get("description", ""))]
		var icon := card.get_node("Icon") as TextureRect
		icon.texture = IconCatalog.upgrade(_option_icon_id(slot, option), _option_weapon_id(slot, option))
		# The reason lives on the badge instead of as a fourth line of body copy:
		# it explains the star, so it belongs to the star.
		var recommendation := card.get_node("Recommendation") as Label
		recommendation.visible = is_recommended
		recommendation.text = "★ %s" % String(option.get("recommendation_reason", ""))

		var border := CatTheme.GOLD if is_unlock or is_recommended else accent
		if level_up_input_delay > 0.0:
			# Visibly inert until input opens, so the pause reads as deliberate
			# rather than as the game ignoring a keypress.
			style.bg_color = CatTheme.PANEL
			style.border_color = CatTheme.OUTLINE
			style.set_border_width_all(2)
		elif is_chosen:
			style.bg_color = CatTheme.CARD.lerp(border, 0.13)
			style.border_color = border
			style.set_border_width_all(3)
		elif is_focused:
			style.bg_color = CatTheme.CARD.lerp(border, 0.08)
			style.border_color = Color(border, 0.9)
			style.set_border_width_all(3)
		else:
			style.bg_color = CatTheme.CARD
			style.border_color = CatTheme.OUTLINE
			style.set_border_width_all(2)
		# Focus stays inside its grid cell: scaling used to overlap the next card.
		card.scale = Vector2.ONE

	_refresh_level_build_icons(slot)
	var footer: Label = p1_level_footer if player_index == 1 else p2_level_footer
	var character := selected_characters[slot]
	var lines: Array[String] = [
		"P%d %s" % [player_index, String(character["name"])],
		"무기 %d/%d    보물 %d/%d" % [
			weapon_loadouts[slot].size(), WEAPON_LOADOUT_CAP,
			treasure_loadouts[slot].size(), TREASURE_LOADOUT_CAP,
		],
	]
	if level_up_input_delay > 0.0:
		lines.append("잠시 후 선택할 수 있습니다")
	elif locked:
		lines.append("✓ 확정 — 상대를 기다리는 중 (취소 가능)")
	else:
		var keys := ["LB/RB", "A", "B"] if last_input_gamepad[slot] else (["A/D", "W", "S"] if player_index == 1 else ["←/→", "↑", "↓"])
		var reroll_key := "Y" if last_input_gamepad[slot] else ("Q" if player_index == 1 else "/")
		lines.append("%s 이동   %s 확정   %s 취소" % [keys[0], keys[1], keys[2]])
		lines.append("%s 재추첨 %d/%d회   %d레벨마다 충전" % [
			reroll_key, rerolls_remaining[slot], REROLL_CAP, REROLL_PER_LEVELS,
		])
	footer.text = "\n".join(lines)
	EditorialUI.refresh_growth(self, slot)


## Which atlas entry a card should show. Treasure ids are deliberately the same
## strings the upgrade atlas is ordered by, so a treasure needs no special case
## beyond naming itself.
func _option_icon_id(slot: int, option: Dictionary) -> String:
	var option_id := String(option.get("id", ""))
	if option_id == "unlock_treasure":
		return String((option["treasure"] as Dictionary)["id"])
	if option_id == "treasure_upgrade":
		return String((treasure_loadouts[slot][int(option["treasure_slot"])] as Dictionary)["id"])
	return option_id


func _option_weapon_id(slot: int, option: Dictionary) -> String:
	if String(option.get("id", "")) == "evolve_weapon":
		return String((option["evolution"] as Dictionary)["weapon_id"])
	if String(option.get("id", "")) == "unlock_weapon":
		return String((option["character"] as Dictionary)["weapon_id"])
	var weapon_slot := int(option.get("weapon_slot", -1))
	if weapon_slot >= 0 and weapon_slot < weapon_loadouts[slot].size():
		return String(weapon_loadouts[slot][weapon_slot]["weapon_id"])
	return ""


## Draws what this survivor is carrying as two rows of icons: weapons on top,
## treasures under them, empty slots shown as empty. This replaced two lines of
## attribute numbers that nobody could read mid-decision.
func _refresh_level_build_icons(slot: int) -> void:
	level_portrait_icons[slot].texture = IconCatalog.survivor(String(selected_characters[slot]["id"]))
	_refresh_icon_row(level_weapon_icons[slot], weapon_loadouts[slot], true)
	_refresh_icon_row(level_treasure_icons[slot], treasure_loadouts[slot], false)


func _refresh_icon_row(icons: Array, carried: Array, is_weapon: bool) -> void:
	for index in icons.size():
		var icon := icons[index] as TextureRect
		var tier := icon.get_node("Tier") as Label
		if index >= carried.size():
			# An empty slot is information: it is how many commitments are left.
			icon.texture = null
			tier.visible = false
			continue
		var entry: Dictionary = carried[index]
		icon.texture = IconCatalog.weapon(String(entry["weapon_id"])) if is_weapon else IconCatalog.upgrade(String(entry["id"]))
		tier.visible = true
		tier.text = "T%d" % int(entry.get("tier", 1))
func _refresh_team_stats_ui() -> void:
	# Show the two-part commitment before the player spends limited slots.
	team_stats_label.text = "합성  P1  %s\n합성  P2  %s" % [_fusion_progress_line(0), _fusion_progress_line(1)]
	team_stats_label.visible = true


## The nearest fusion this survivor could reach, written as the two
## requirements it still needs. Only the weapon closest to fusing is reported,
## so the strip stays one line per survivor.
func _fusion_progress_line(slot: int) -> String:
	var best := ""
	var best_progress := -1.0
	var fused: Array[String] = []
	for weapon in weapon_loadouts[slot]:
		if bool(weapon.get("evolved", false)):
			fused.append(String(weapon["weapon_name"]))
			continue
		var evolution := Evolutions.for_base(String(weapon["weapon_id"]))
		if evolution.is_empty():
			continue
		var treasure_id := String(evolution["treasure_id"])
		var treasure := Treasures.by_id(treasure_id)
		var weapon_tier := int(weapon.get("tier", 1))
		var treasure_tier := _treasure_tier(slot, treasure_id)
		var progress := float(weapon_tier) / float(Evolutions.WEAPON_MAX_TIER) + float(treasure_tier) / float(Evolutions.REQUIRED_TREASURE_TIER)
		if progress <= best_progress:
			continue
		best_progress = progress
		best = "%s T%d/%d + %s T%d/%d → %s" % [
			String(weapon["weapon_name"]), weapon_tier, Evolutions.WEAPON_MAX_TIER,
			String(treasure.get("name", treasure_id)), treasure_tier, Evolutions.REQUIRED_TREASURE_TIER,
			String(evolution["weapon_name"]),
		]
	if not fused.is_empty():
		var done := "완료 " + "  ".join(fused)
		return done if best.is_empty() else best
	return best if not best.is_empty() else "대상 없음"


func _finish_level_up() -> void:
	level_up_active = false
	level_overlay.visible = false
	get_tree().paused = false
	if team_level_heal > 0.0:
		for player in players:
			player.heal(player.max_health * team_level_heal)
	_show_message("LV.%d · 둘 다 성장 완료" % progression.level, Color("fff275"))
	if progression.can_level_up():
		level_up_gap_remaining = LEVEL_UP_GAP


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
	resonance_cursors = [0, 0]
	resonance_vote_message = ""
	level_overlay.visible = false
	resonance_overlay.visible = true
	_refresh_resonance_vote_ui()


## Both survivors browse the same three cards with the same controls the
## level-up screen uses, and each one's cursor is visible to the other the whole
## time. A vote locks only on confirm and can be taken back until the pair
## actually agrees — a disagreement is a conversation, not a failure state.
func _handle_resonance_vote_input() -> void:
	for slot in 2:
		var prefix := "p1_select_" if slot == 0 else "p2_select_"
		if resonance_votes[slot] >= 0:
			if Input.is_action_just_pressed(prefix + "cancel"):
				resonance_votes[slot] = -1
				_refresh_resonance_vote_ui()
			continue
		if Input.is_action_just_pressed(prefix + "previous"):
			resonance_cursors[slot] = wrapi(resonance_cursors[slot] - 1, 0, resonance_candidates.size())
			_refresh_resonance_vote_ui()
		elif Input.is_action_just_pressed(prefix + "next"):
			resonance_cursors[slot] = wrapi(resonance_cursors[slot] + 1, 0, resonance_candidates.size())
			_refresh_resonance_vote_ui()
		elif Input.is_action_just_pressed(prefix + "confirm"):
			resonance_votes[slot] = resonance_cursors[slot]
			feedback.play_cue("select")
			_refresh_resonance_vote_ui()

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
		return
	# Only the disagreement is cleared, not the browsing position: both cursors
	# stay where they were so the pair argues from where they actually are.
	resonance_votes[0] = -1
	resonance_votes[1] = -1
	resonance_vote_message = "선택이 갈렸습니다 — 상대의 커서를 보고 다시 고르세요"
	feedback.play_cue("warning")
	_refresh_resonance_vote_ui()


func _refresh_resonance_vote_ui() -> void:
	for index in resonance_cards.size():
		var card: Label = resonance_cards[index]
		if index >= resonance_candidates.size():
			card.visible = false
			continue
		card.visible = true
		var resonance: Dictionary = resonance_candidates[index]
		for slot in 2:
			var icon := card.get_node("Cat%d" % slot) as TextureRect
			icon.texture = IconCatalog.survivor(String(selected_characters[slot]["id"]))
		var requirements: Array = resonance["requires"]
		card.text = "%s\n%s + %s\n\n%s" % [
			String(resonance["name"]),
			_tag_name(String(requirements[0])), _tag_name(String(requirements[1])),
			String(resonance["description"]),
		]

		var pointed_by: Array[int] = []
		var locked_by: Array[int] = []
		for slot in 2:
			if resonance_votes[slot] == index:
				locked_by.append(slot)
			elif resonance_votes[slot] < 0 and resonance_cursors[slot] == index:
				pointed_by.append(slot)
		var pips: Label = card.get_node("Pips")
		pips.text = _resonance_pip_text(pointed_by, locked_by)
		pips.visible = not pips.text.is_empty()

		var style := card.get_theme_stylebox("normal") as StyleBoxFlat
		var attention := locked_by.size() + pointed_by.size()
		var accent := Color("e4c1f9")
		if locked_by.size() == 2:
			accent = Color("fff275")
		elif not locked_by.is_empty():
			accent = Color("43d9ff") if locked_by[0] == 0 else Color("b892ff")
		elif not pointed_by.is_empty():
			accent = Color("43d9ff") if pointed_by[0] == 0 else Color("b892ff")
		style.bg_color = CatTheme.CARD.lerp(CatTheme.P1, 0.035 * float(attention))
		style.border_color = CatTheme.P1 if attention > 0 else CatTheme.OUTLINE
		style.set_border_width_all(2 + attention)
		card.scale = Vector2.ONE

	var waiting: Array[String] = []
	for slot in 2:
		if resonance_votes[slot] < 0:
			waiting.append("P%d" % (slot + 1))
	var lines: Array[String] = []
	if waiting.size() == 1:
		lines.append("%s 선택 대기 중 — 확정한 쪽은 취소로 되돌릴 수 있습니다" % waiting[0])
	elif waiting.size() == 2:
		var p1_keys := "LB/RB   A" if last_input_gamepad[0] else "A/D 이동   W 확정"
		var p2_keys := "LB/RB   A" if last_input_gamepad[1] else "←/→ 이동   ↑ 확정"
		lines.append("P1 %s     P2 %s" % [p1_keys, p2_keys])
	if not resonance_vote_message.is_empty():
		lines.append(resonance_vote_message)
	resonance_status.text = "\n".join(lines)


## The pips are the point of this screen: a hollow marker is "P2 is looking at
## this one", a filled one is "P2 has committed to it".
func _resonance_pip_text(pointed_by: Array[int], locked_by: Array[int]) -> String:
	var parts: Array[String] = []
	for slot in 2:
		if slot in locked_by:
			parts.append("● P%d 확정" % (slot + 1))
		elif slot in pointed_by:
			parts.append("○ P%d" % (slot + 1))
	return "   ".join(parts)


func _tag_name(tag: String) -> String:
	var names := {
		"tracking": "추적", "lightning": "번개", "projectile": "투사체", "storm": "폭풍",
		"arcane": "비전", "chain": "연쇄", "fire": "화염", "frost": "서리",
		"shadow": "그림자", "tether": "결속", "aura": "오라", "melee": "근접",
		"holy": "성휘", "control": "제어", "burst": "폭발", "arc": "호격"
	}
	return String(names.get(tag, tag))


## A weapon's own cooldown scaled by its owner's haste, floored so stacked
## haste can never drive an interval to zero (which would fire every frame).
## The XP pickup radius lives on ExperienceSystem, so the shared magnet
## attribute is pushed into it whenever it changes rather than read per frame.
func _apply_team_magnet() -> void:
	experience_system.magnet_radius = EXPERIENCE_MAGNET_BASE * team_magnet


func _weapon_interval(player_index: int, weapon_slot: int) -> float:
	var base := float(weapon_loadouts[player_index][weapon_slot]["cooldown"])
	return maxf(0.12, base * players[player_index].haste)


func _tension_damage_multiplier() -> float:
	# The ward pays the overcharge bonus unconditionally. That is the whole
	# reason to pick the drop up at a moment when the pair is fighting close
	# together rather than only when the chain is already in trouble.
	if chain_warded():
		return 1.25 + team_overcharge
	if chain_overloaded:
		return CHAIN_OVERLOAD_PENALTY
	var ratio := players[0].position.distance_to(players[1].position) / chain_max_length
	if ratio >= CHAIN_WARNING_RATIO:
		return 1.25 + team_overcharge
	return 1.0 + team_close_power if ratio <= 0.45 else 1.0


func _update_hud() -> void:
	boss_hud_panel.visible = boss_bar.visible
	var distance := players[0].position.distance_to(players[1].position)
	var tension := clampf(distance / chain_max_length, 0.0, 1.0)
	p1_status_label.text = _player_status_text(0)
	p2_status_label.text = _player_status_text(1)
	p1_health_bar.max_value = players[0].max_health
	p1_health_bar.value = players[0].health
	p2_health_bar.max_value = players[1].max_health
	p2_health_bar.value = players[1].health
	p1_health_text_label.text = _player_health_text(0)
	p2_health_text_label.text = _player_health_text(1)
	p1_health_text_label.add_theme_color_override("font_color", Color("ffcfdf") if players[0].downed else Color("f4f8ff"))
	p2_health_text_label.add_theme_color_override("font_color", Color("ffcfdf") if players[1].downed else Color("f4f8ff"))
	chain_bar.value = tension * 100.0
	chain_distance_text_label.text = "사슬 거리  %d%%" % int(round(tension * 100.0))
	var chain_state := ""
	var chain_color := Color("43d9ff")
	if chain_overloaded:
		chain_state = "과부하   공격 -20%"
		chain_color = Color("ff5d8f")
	elif tension >= 0.95:
		chain_state = "한계   가까이!"
		chain_color = Color("ff5d8f")
	elif tension >= CHAIN_WARNING_RATIO:
		chain_state = "과충전   공격 +%d%%" % roundi((0.25 + team_overcharge) * 100.0)
		chain_color = Color("fff275")
	elif tension >= CHAIN_RESIST_RATIO:
		chain_state = "저항"
		chain_color = Color("8ecae6")
	chain_status_label.text = chain_state
	chain_status_label.visible = not chain_state.is_empty()
	chain_status_label.add_theme_color_override("font_color", chain_color)
	var fill := chain_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = chain_color
	chain_integrity_bar.value = chain_integrity
	chain_integrity_text_label.text = "내구도  %d%%" % int(round(chain_integrity))
	var integrity_fill := chain_integrity_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if integrity_fill != null:
		if chain_overloaded:
			integrity_fill.bg_color = Color("ff5d8f")
		elif chain_integrity < 40.0:
			integrity_fill.bg_color = Color("fff275")
		else:
			integrity_fill.bg_color = Color("80ed99")
	resonance_status_label.visible = not resonance_system.active_resonances.is_empty()
	if resonance_system.active_resonances.is_empty():
		resonance_status_label.text = ""
	else:
		resonance_status_label.text = "공명 %d/%d" % [
			resonance_system.active_resonances.size(), resonance_system.MAX_ACTIVE_RESONANCES
		]
	xp_bar.max_value = progression.required_experience
	xp_bar.value = progression.experience
	xp_text_label.text = "LV.%d    XP %d / %d" % [
		progression.level, int(progression.experience), int(progression.required_experience)
	]
	EditorialUI.refresh_hud(self)


func _player_status_text(player_index: int) -> String:
	var player := players[player_index]
	return "P%d  %s" % [player_index + 1, player.character_name]


func _player_health_text(player_index: int) -> String:
	var player := players[player_index]
	if player.downed:
		return "DOWN %.1f초   구조 %.0f%%" % [player.bleedout_remaining, player.revive_progress / 2.6 * 100.0]
	return "%d / %d" % [int(player.health), int(player.max_health)]


## Compact HUD summary of a player's whole loadout: the weapon name when they
## only carry one (matches how this used to read before extra weapons existed),
## or a tier list once they have picked up more.
func _loadout_summary(player_index: int) -> String:
	var loadout: Array = weapon_loadouts[player_index]
	if loadout.size() == 1:
		return "%s T%d" % [String(loadout[0]["weapon_name"]), int(loadout[0].get("tier", 1))]
	var tiers: Array[String] = []
	for weapon in loadout:
		tiers.append("T%d" % int(weapon.get("tier", 1)))
	return "무기 %d종 %s" % [loadout.size(), "/".join(tiers)]


## The co-op line of the result screen: what the pair did together, next to
## the survival numbers above it. These are the counters run_stats has been
## carrying unused; nothing else reads them.
func _run_stats_summary() -> String:
	return "보스 %d대    구조 %d회    대시 %d회    공명 %d회    아이템 %d개    과충전 %.0f초    과부하 %d회" % [
		int(run_stats["bosses"]), int(run_stats["revives"]), int(run_stats["dashes"]),
		int(run_stats["resonance_casts"]), int(run_stats["items"]),
		float(run_stats["overcharge_time"]), int(run_stats["overloads"])
	]


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
	for slot in 2:
		var portrait := result_overlay.get_node("ResultCat%d" % slot) as TextureRect
		portrait.texture = IconCatalog.survivor(String(selected_characters[slot]["id"]))
	get_tree().paused = true
	result_label.add_theme_color_override("font_color", CatTheme.INK if victory else Color("994938"))
	EditorialUI.refresh_result(self, victory)
	_update_hud()
	feedback.stop_music()
	feedback.play_cue("victory" if victory else "down")


func _setup_input_map() -> void:
	_add_key_action("build_details", KEY_TAB)
	_add_key_action("menu_previous", KEY_UP)
	_add_key_action("menu_previous", KEY_W)
	_add_key_action("menu_next", KEY_DOWN)
	_add_key_action("menu_next", KEY_S)
	_add_key_action("menu_confirm", KEY_ENTER)
	_add_key_action("menu_cancel", KEY_BACKSPACE)
	for device in 2:
		_add_joy_button("build_details", device, JOY_BUTTON_X)
		_add_joy_button("menu_previous", device, JOY_BUTTON_DPAD_UP)
		_add_joy_button("menu_next", device, JOY_BUTTON_DPAD_DOWN)
		_add_joy_button("menu_confirm", device, JOY_BUTTON_A)
		_add_joy_button("menu_cancel", device, JOY_BUTTON_B)
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
	_add_key_action("toggle_music", KEY_F4)
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
	_add_key_action("p1_dash", KEY_SPACE)
	_add_key_action("p2_dash", KEY_PERIOD)
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
	# The right trigger is the only pad control still free, and it is where a
	# dash sits on most games anyway.
	_add_joy_axis("p1_dash", 0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_axis("p2_dash", 1, JOY_AXIS_TRIGGER_RIGHT, 1.0)


func _add_key_action(action: StringName, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joy_axis(action: StringName, device: int, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joy_button(action: StringName, device: int, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)
