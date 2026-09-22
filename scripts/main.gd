extends Node2D

const CompanionController := preload("res://scripts/systems/companion_controller.gd")
const CoopSelectionUI := preload("res://scripts/ui/coop_selection_ui.gd")
const OnlineCoopScript := preload("res://scripts/systems/online_coop.gd")

const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
]
const VOLUME_STEPS := [0.0, 0.25, 0.5, 0.75, 1.0]
## What the window was actually opened at, which is the requested size unless
## the desktop was too small to hold it once framed. Zero until a window exists.
var applied_window_size := Vector2i.ZERO
static var pending_retry: Dictionary = {}

const PlayerScene := preload("res://scripts/entities/player.gd")
const CharacterData := preload("res://scripts/catalogs/character_catalog.gd")
const EnemyProjectileScript := preload("res://scripts/entities/enemy_projectile.gd")
const SpatialGridScript := preload("res://scripts/systems/enemy_spatial_grid.gd")
const ProgressionScript := preload("res://scripts/systems/progression_system.gd")
const ExperienceScript := preload("res://scripts/systems/experience_system.gd")
const WaveDirectorScript := preload("res://scripts/systems/wave_director.gd")
const ResonanceScript := preload("res://scripts/systems/resonance_system.gd")
const BossHealthBarScript := preload("res://scripts/ui/boss_health_bar.gd")
const EdgePointerScript := preload("res://scripts/ui/edge_pointer.gd")
const ResonancePipsScript := preload("res://scripts/ui/resonance_pips.gd")
const BurstFieldScript := preload("res://scripts/systems/burst_field.gd")
const ChainArcScript := preload("res://scripts/effects/chain_arc.gd")
const ChainFlowScript := preload("res://scripts/effects/chain_flow.gd")
const CrowdRendererScript := preload("res://scripts/effects/crowd_renderer.gd")
const FlightFieldScript := preload("res://scripts/effects/flight_field.gd")
const RooftopOcclusionScript := preload("res://scripts/effects/rooftop_occlusion.gd")
const ShowcaseScript := preload("res://scripts/effects/showcase.gd")
const ParticleFieldScript := preload("res://scripts/systems/particle_field.gd")
const ArenaFloorScript := preload("res://scripts/entities/arena_floor.gd")
const RooftopPropFieldScript := preload("res://scripts/entities/rooftop_prop_field.gd")
const WeaponControllerScript := preload("res://scripts/systems/weapon_controller.gd")
const FeedbackScript := preload("res://scripts/systems/feedback_system.gd")
const FieldItemScript := preload("res://scripts/systems/field_item_system.gd")
const SettingsScript := preload("res://scripts/systems/settings_system.gd")
const MetaProgressionScript := preload("res://scripts/systems/meta_progression.gd")
const IconCatalog := preload("res://scripts/ui/icon_catalog.gd")
const CatTheme := preload("res://scripts/ui/cat_theme.gd")
const CatPanel := preload("res://scripts/ui/cat_panel.gd")
const ItemStateVeilScript := preload("res://scripts/ui/item_state_veil.gd")
const EditorialUI := preload("res://scripts/ui/editorial_ui.gd")
const UIWrite := preload("res://scripts/ui/ui_write.gd")
const NeonGrowthUI := preload("res://scripts/ui/neon_growth_ui.gd")
const CardVisual := preload("res://scripts/ui/growth_card_visual.gd")
const DebugInspectorScript := preload("res://scripts/ui/debug_inspector.gd")
const Treasures := preload("res://scripts/catalogs/treasure_catalog.gd")
const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const WeaponGrowthScript := preload("res://scripts/systems/weapon_growth.gd")
const RunStatsTemplate := preload("res://scripts/templates/run_stats_template.gd")
const InputBindings := preload("res://scripts/templates/input_bindings.gd")

const CHAIN_WARNING_RATIO := 0.82
## Draw layer of the actors. Friendly attack effects stay at or below
## FRIENDLY_EFFECT_Z_MAX so enemies and their shots always read over them.
const WORLD_STAGE_Z := 5
const FRIENDLY_EFFECT_Z_MAX := 4
const CHAIN_RESIST_RATIO := 0.70
## The run is five boss fights, not one. WaveDirector owns the schedule; this
## is the total length so the UI can say how far along a run is without
## recomputing the interval.
const RUN_LENGTH := WaveDirectorScript.RUN_LENGTH
const DOWNED_TOW_SHARE := 0.88
## Four weapons and four treasures. Six of each was tried and the extra two
## slots did not buy two more decisions — they bought permission to stop
## deciding: a survivor could take every weapon that looked interesting and
## still have room, so "which of these do I give a slot to" never actually got
## asked. Four is small enough that the twelve weapons and twenty-six treasures
## visibly do not fit, which is the whole point of having a loadout at all.
## A weapon no longer keeps climbing for free either: a slot spent is depth not
## taken somewhere else (see _score_upgrade_option's slot pressure).
const WEAPON_LOADOUT_CAP := 4
## Treasures are the other half of a build. Attributes used to be unlimited
## free-floating cards; a survivor now commits to four and deepens those.
const TREASURE_LOADOUT_CAP := 4
## What a weapon is worth before anyone has spent anything on it. What each card
## is worth after that depends on where the weapon is in its life and which tech
## it took — both live in WeaponGrowth, so the card pool, the preview, the chest
## and the recommendation scorer all read one ladder.
const BASE_WEAPON_DAMAGE_SCALE := WeaponGrowthScript.OPENING_DAMAGE_SCALE

## Enemies spawn 610-760px out and never stopped chasing, so anything that
## drifted off — a shooter backing away, a charger that overshot — stayed
## alive forever and ate a slot in the 420 cap. Recycling them keeps the
## cap filled with enemies that are actually part of the fight. Comfortably
## beyond the spawn ring so nothing is culled the moment it arrives.
const ENEMY_CULL_RADIUS := 1500.0
## How the crowd is split for steering. Each body carries a batch index and one
## batch steers per tick, with the delta it missed handed back, so timers,
## cooldowns and travel run at the rate they always did and only the granularity
## of the steering drops. Two is deliberate: at three, a runner sprinting at
## 145px/s covers seven pixels between updates, which is visible as a stutter.
##
## There is no distance tier here, and that is a measured decision rather than an
## oversight. Exempting a ring around the pair looks obviously right and saves
## almost nothing: every enemy walks at the survivors, so within seconds of
## spawning the whole crowd has converged into exactly that ring. A 420px
## exemption took the tick from 11.7ms to 11.7ms. What is safe to stagger is
## decided by what the step does, not by where the body is.
const AI_BATCHES := 2
## The one distance tier that does pay: bodies outside the view. The stutter
## that rules out three batches on screen cannot be seen off it, and a large
## crowd keeps a real share of itself out there — spawning in, or left behind
## as the pair kites. The frame they walk into view they drop back to AI_BATCHES.
const OFFSCREEN_AI_BATCHES := 6
## The stagger rests on a compensated delta standing in for the ticks a body
## missed, and that substitution is only honest while the doubled step stays
## small next to the bodies and the distances involved. At the project's 60Hz it
## is: the fastest thing on the field covers about five pixels. The soak tests
## run the clock at twenty times speed, where a physics delta is a third of a
## second and a doubled one is most of a screen — enemies overshoot the survivors
## instead of closing on them, and the measured run stops being the game. Left
## unguarded it turned the soak's three-of-four-bosses loss into a five-of-five
## win and doubled the kill count, which is a balance instrument reporting a game
## nobody plays. Godot's physics delta is fixed at the tick rate rather than
## driven by how fast frames actually render, so this never switches itself off
## on a slow machine — the one case where the stagger is most needed.
## Just above one tick at 60Hz, so a modestly scaled clock still staggers and an
## accelerated one does not.
const MAX_STAGGER_DELTA := 0.02

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

var ai_companion := false
var online_retry_pending := false
var ai_think_remaining := 0.0
var ai_considered_human := -1
## One stable personality roll per AI lobby. It keeps the choice stable while
## the selection UI refreshes, but a new AI partner can pick a different cat.
var ai_character_preference := randi()
var online: OnlineCoop
var players: Array[ChainPlayer] = []
var enemies: Array[ChaserEnemy] = []
## The elites and bosses among `enemies`, for the off-screen threat pointer.
var heavy_enemies: Array[ChaserEnemy] = []
var world_stage: Node2D
var crowd_renderer: CrowdRendererScript
var rooftop_view: EndlessRooftopView
var chain_arc: ChainArc
var chain_flow: ChainFlow
var bursts: BurstField
var particles: ParticleField
var flight_field: FlightField
## A fusion, a resonance and a chest each stop the run and take the screen for
## a couple of seconds. The queue exists because one level-up can produce two
## fusions, and a chest can contain one — they play in order rather than on
## top of each other.
var showcase_queue: Array[Dictionary] = []
var cinematic_active := false
var cinematic_continuation := Callable()
var cinematic_resume_paused := false
var arena_floor: ArenaFloor
var rooftop_props: RooftopPropField
var rooftop_occlusion: RooftopOcclusion
var modal_dim: ColorRect
## One gold wash over the whole frame at the instant a level lands. The growth
## screen no longer arrives as a box appearing, so something has to say "this
## just happened" — the flash and the camera pull are that something.
var growth_flash: ColorRect
var item_state_veil: ItemStateVeil
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
var meta_progression: MetaProgression
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
## 공명 drawn as its slots, under the label (see ResonancePips).
var resonance_pips: Control
var boss_bar: Control
var boss_label: Label
var boss_health_text_label: Label
var help_label: Label
var message_label: Label
var notice_stack: Array[Label] = []
var level_overlay: ColorRect
var level_card_labels: Array = [[], []] ## level_card_labels[slot] = Array[Label], one per offered choice (up to 4)
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
## The screen the game opens on. The lobby used to be the front door, which
## meant there was no way to change a setting, read the credits or leave without
## first getting two people to press something. The title holds those, and hands
## over to the lobby when someone asks to start.
var title_overlay: ColorRect
var title_active := true
var title_cursor := 0
## "menu", "settings" or "credits". Sub-pages rather than separate overlays: all
## three are the same panel with a different list in it, and the cursor, the
## confirm key and the back key behave identically in each.
var title_mode := "menu"
var title_rows: Array[Label] = []
var title_note: Label
var lobby_overlay: ColorRect
var lobby_title: Label
var lobby_p1_label: Label
var lobby_p2_label: Label
var threat_edge_indicator: Control
## Points at an off-screen field drop, the way threat_edge_indicator points at an
## off-screen elite. Every drop on the roof came off a named fight, and each one
## times out, so "there is a box over there" is information with a clock on it.
var item_edge_indicator: Control

var elapsed := 0.0
var kills := 0
var game_over := false
var level_up_active := false
## True once neither survivor has a card left to be offered. It is a label on
## the HUD, not a stop: experience has no ceiling any more (see
## _consume_overflow_levels), so the bar keeps filling and levels keep landing.
var growth_finished := false
var overflow_levels := 0
var character_select_active := true
var character_exit_confirm := false
var lobby_exit_confirm := false
var resonance_vote_active := false
var pause_active := false
var pause_cursor := 0
var pause_settings := false
## The pause menu holds one confirmation at a time. Both destructive entries —
## starting over and leaving the game — go through it, so `pending_quits` is
## what the confirmation will actually do if it is accepted.
var restart_pending := false
var pending_quits := false
var restart_armed_at := 0
var details_overlay: Panel
var debug_inspector
var modal_input_guard := 0
const ReviewUI := preload("res://scripts/ui/review_ui.gd")
const UpgradeValue := preload("res://scripts/systems/upgrade_value.gd")
var lobby_active := true
var run_won := false
var run_reward := 0
## Debug shortcuts deliberately invalidate rewards/discoveries. The inspector
## may skip twenty minutes of progression, so letting that run write permanent
## unlocks would make a test tool part of the metagame.
var debug_run_tainted := false
var meta_cursor := 0
var meta_page := 0
var meta_reset_pending := false
var meta_fish_reset_pending := false
var boss_enemy: ChaserEnemy
var camera_shake := 0.0
## The camera follow, before it is rounded onto the battlefield buffer's texel
## grid, and the rounded value that was last handed to the camera. Everything
## that reads world_camera.position still gets the rounded one — the difference
## is under a pixel — but the follow has to accumulate off the unrounded value.
## See EndlessRooftopView.snap_to_source_texels for why the rounding is there.
var camera_focus := Vector2.ZERO
var camera_written := Vector2.ZERO
var screen_shake_enabled := true
var combat_visuals_enabled := true
var previous_chain_stage := 0
var last_input_gamepad: Array[bool] = [false, false]
var lobby_joined: Array[bool] = [false, false]
var lobby_devices: Array[int] = [-1, -1]
var lobby_device_names: Array[String] = ["키보드", "키보드"]
var lobby_input_cooldown := 0.0
var upgrade_cursors: Array[int] = [0, 0]
var selected_upgrade_indices: Array[int] = [-1, -1] ## -2 = build complete; -1 = choosing; >=0 = locked
var rerolls_remaining: Array[int] = [REROLL_START, REROLL_START]
var last_upgrade_choice_keys: Array = [[], []]
var level_up_input_delay := 0.0
var level_up_gap_remaining := 0.0 ## Blocks input right after the screen opens ## Previous level-up's offered option keys per player, so the exact same hand doesn't repeat back to back
var resonance_cursors: Array[int] = [0, 0]
## Run-long tally shown on the result screen. "pings" and "chain_bursts"
## named features that were never built; these six are events the game
## actually raises, and each is counted at the one place it happens so the
## screen cannot drift from play.
var run_stats := RunStatsTemplate.create()

var chain_max_length := 370.0
var chain_integrity := CHAIN_INTEGRITY_MAX
var chain_overloaded := false
var chain_tutorial_stage := 0
var simulation_phase := 0
## Opt-in frame breakdown, off during play. Timing an algorithm on its own says
## how fast that algorithm is, not where a frame actually goes; the performance
## test turns this on and reads the real cost of each phase of one physics tick.
var profiling := false
var profile_totals: Dictionary = {}
var profile_frames := 0
var _profile_at := 0
## Worst single tick seen, in microseconds. The average hides the thing a player
## actually feels: a pass that runs every other frame costs nothing on one tick
## and double on the next, and it is the double that misses the deadline.
## Every measured tick, so the spread can be read as a distribution. The single
## worst tick is not a useful number on a desktop: a scheduling hiccup inflates
## every section of one frame at once and lands wherever it lands, which is why
## the worst frame of a two hundred body run came out higher than the worst of a
## four hundred body one. A high percentile survives that and still shows a pass
## that genuinely costs double on alternate frames.
var profile_frame_usec: PackedInt32Array = PackedInt32Array()
var _profile_frame_at := 0
var level_overlay_tween: Tween
var resonance_overlay_tween: Tween
var chain_ward_remaining := 0.0
var chain_ward_pulse_timer := 0.0
## Live hostile shots. Kept as a list rather than found by walking the child
## nodes each time, because the weapons that shoot them down have to reach them
## from another node entirely, and because a time stop used to scan every child
## in the scene — a couple of thousand of them — to find the few dozen that were
## projectiles.
var enemy_shots: Array = []
## Spent hostile shots, kept for reuse. See _acquire_enemy_shot.
var enemy_shot_pool: Array[EnemyProjectile] = []
var guard_remaining := 0.0
var frenzy_remaining := 0.0
var time_stop_remaining := 0.0
var item_aura: Node2D

## Team attributes. Experience is a shared pool and both survivors level
## together, so the stats that act on that pool are shared too — one player
## owning a bigger magnet while the other does not would be incoherent when
## either of them picking a gem credits the same bar. Everything that acts on
## a survivor's own body or weapons stays personal (see ChainPlayer).
## Field drops are rare enough that finding one is an event, not a resource
## tick. Every elite and boss leaves something, so a telegraphed hard fight has
## a payoff; ordinary enemies leave experience only (see _try_drop_field_item).
const FIELD_ITEM_HEAL_RATIO := 0.3
## Elites only (and every boss, which spawns one outright). Ordinary kills used
## to roll for one too, at 0.4% across roughly six thousand kills a run — which
## made the rarest thing in the game something that happened constantly, from
## nowhere in particular.
const CHEST_ELITE_CHANCE := 0.34
const CHEST_LUCK_CHANCE := 0.006
## Luck moves the odds; it does not turn every elite into a chest. Without the
## ceiling a maxed-luck greedy pair opened four chests a minute.
const CHEST_MAX_CHANCE := 0.7
## A chest can hand out as many as this. Eight is deliberately close to never:
## the ladder in _roll_chest_reward_count puts it under a tenth of a percent, so
## it exists to be talked about rather than planned around.
const CHEST_MAX_REWARDS := 8
## Moon-fish paid instead of a reward the pair has no room for.
const CHEST_POINT_REWARD := 2
## Even while carried gear can still grow, a chest may introduce a new weapon
## or treasure. Luck makes that exciting branch more common without making a
## full loadout happen automatically after one lucky box.
const CHEST_NEW_GEAR_BASE_CHANCE := 0.18
const CHEST_NEW_GEAR_LUCK_CHANCE := 0.025
const CHEST_NEW_GEAR_MAX_CHANCE := 0.55
## 사슬 결계 used to be 사슬 정비: it topped up the integrity bar and did
## nothing else, which made the rarest-but-one drop in the game a number going
## up. It is now a window instead of a refund — for its duration the chain
## cannot be strained, cannot overload, pays the full overcharge damage bonus
## no matter how the pair is standing, and burns everything that crosses it.
## Long enough to change what a fight is worth attempting, short enough that
## the pair has to decide when to spend it.
## Three timed windows, all short enough that spending one badly is a real
## mistake. 수호의 방울 is the shortest because untouchable is the strongest
## thing an item can say; 멈춘 회중시계 is the rarest for the same reason.
const GUARD_DURATION := 5.0
const FRENZY_DURATION := 8.0
const FRENZY_POWER := 1.8
const FRENZY_MOVE_SPEED := 1.25
const FRENZY_ATTACK_SPEED := 1.35
const TIME_STOP_DURATION := 4.0
const CHAIN_WARD_DURATION := 10.0
const CHAIN_WARD_PULSE := 0.22 ## Seconds between chain burn ticks while warded.
const CHAIN_WARD_PULSE_DAMAGE := 42.0
const CHAIN_WARD_WIDTH := 110.0
const CHAIN_WARD_POWER := 1.55

const EXPERIENCE_MAGNET_BASE := 155.0
## 진홍 목방울 converts actual (not overkill) damage into a shared healing
## pool. A refill budget keeps large area attacks and instant-kill effects from
## turning one frame into a full heal, while sustained damage still sustains the
## pair. Values are per treasure tier.
const LIFESTEAL_PER_TIER := 0.006
const LIFESTEAL_REFILL_PER_SECOND_PER_TIER := 1.5
const LIFESTEAL_BURST_CAP_PER_TIER := 4.0
var team_magnet := 1.0 ## multiplier on the shared XP pickup radius
var team_growth := 1.0 ## multiplier on all shared XP gained
var team_luck := 0
var team_lifesteal := 0.0
var lifesteal_charge := 0.0
var team_overcharge := 0.0
var team_greed := 0.0
var team_level_heal := 0.0
var team_hunt_bonus := 0.0
var team_close_power := 0.0
var team_dash_burst := 0.0
## Run-local record used by the fusion sequence and tests. Recipe hints are now
## unlocked per pair by ownership instead of globally by this first completion.
var fusion_discovered := false

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
## Resonances the pair has already been told are possible, so the notice fires
## once per pairing rather than on every level-up that keeps it true.
var announced_resonance_ids: Dictionary = {}
var resonance_votes: Array[int] = [-1, -1]
var resonance_vote_message := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	# Before anything builds a Label or calls draw_string: this is what the
	# world-space text (damage numbers, the badges over the cats) reads, and it
	# is not covered by the theme the HUD host carries.
	CatTheme.adopt()
	randomize()
	settings = SettingsScript.new() as GameSettings
	settings.load_settings()
	TranslationServer.set_locale(settings.language)
	_apply_display_settings()
	meta_progression = MetaProgressionScript.new() as MetaProgression
	meta_progression.load_progress()
	_setup_input_map()
	online = OnlineCoopScript.new() as OnlineCoop
	online.name = "OnlineCoop"
	add_child(online)
	online.configure(self)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	character_catalog = CharacterData.all_characters()
	_create_world()
	_create_players()
	rooftop_occlusion = RooftopOcclusionScript.new() as RooftopOcclusion
	add_child(rooftop_occlusion)
	rooftop_occlusion.configure(players, rooftop_props)
	feedback = FeedbackScript.new() as FeedbackSystem
	add_child(feedback)
	feedback.sound_enabled = settings.sound_enabled
	feedback.music_enabled = settings.music_enabled
	feedback.sound_volume = settings.sound_volume if settings.sound_enabled else 0.0
	feedback.music_volume = settings.music_volume if settings.music_enabled else 0.0
	feedback.refresh_music()
	feedback.refresh_sound()
	feedback.damage_numbers_enabled = settings.damage_numbers_enabled
	screen_shake_enabled = settings.screen_shake_enabled
	weapon_controller = WeaponControllerScript.new() as WeaponController
	add_child(weapon_controller)
	weapon_controller.configure(players, weapon_loadouts, spatial_grid)
	weapon_controller.flight_field = flight_field
	# Handed over rather than copied: four weapons knock shots down, and they do
	# it from inside the controller and from inside the fields it spawns.
	weapon_controller.enemy_shots = enemy_shots
	weapon_controller.cue_requested.connect(feedback.play_cue)
	weapon_controller.attack_visual.connect(_on_player_attack_visual)
	_create_hud()
	ReviewUI.install(self)
	CoopSelectionUI.install(self)
	_apply_accessibility_text_scale()
	# Runtime inspection is intentionally absent from release exports. In debug
	# builds F10 opens live combat/build telemetry and tightly scoped test actions.
	if OS.is_debug_build():
		debug_inspector = DebugInspectorScript.new()
		add_child(debug_inspector)
		debug_inspector.configure(self)
	rooftop_view = preload("res://scripts/effects/endless_rooftop_view.gd").new()
	add_child(rooftop_view)
	for world_node in [arena_floor, world_stage, wave_director, experience_system,
		field_items, item_aura, bursts, particles, flight_field, rooftop_occlusion,
		world_camera, weapon_controller, feedback]:
		rooftop_view.adopt(world_node)
	_begin_title()
	if not pending_retry.is_empty():
		call_deferred("_resume_pending_retry")
	queue_redraw()


func _resume_pending_retry() -> void:
	var request := pending_retry.duplicate(true)
	pending_retry.clear()
	var characters: Array = request.get("characters", [0, 1])
	if characters.size() >= 2:
		selected_character_indices = [int(characters[0]), int(characters[1])]
	ai_companion = bool(request.get("ai_companion", false))
	var retry_role := int(request.get("online_role", NetworkSession.Role.OFFLINE))
	if retry_role == NetworkSession.Role.HOST:
		_begin_lobby()
		lobby_input_cooldown = 0.0
		selected_character_indices.assign(characters)
		online_retry_pending = true
		online.host_game()
		return
	if retry_role == NetworkSession.Role.CLIENT:
		_begin_lobby()
		lobby_input_cooldown = 0.0
		online.join_game(String(request.get("online_address", "127.0.0.1")))
		return
	character_confirmed = [true, true]
	_start_selected_run()


func _apply_accessibility_text_scale() -> void:
	_apply_text_scale_to(self, 1.14 if settings.large_text_enabled else 1.0)


func _apply_text_scale_to(node: Node, scale_factor: float) -> void:
	if node is Control and node.has_theme_font_size_override("font_size"):
		var current_size: int = node.get_theme_font_size("font_size")
		if (not node.has_meta("accessibility_base_font_size")
				or current_size != int(node.get_meta("accessibility_applied_font_size", current_size))):
			# A screen refresh may deliberately assign a different base size for a
			# different mode. Treat that as the new source instead of restoring an
			# older layout's size from metadata.
			node.set_meta("accessibility_base_font_size", current_size)
		var base_size := int(node.get_meta("accessibility_base_font_size"))
		# Display lettering already has ample size; enlarge dense reading text.
		var applied_size: int = roundi(base_size * scale_factor) if base_size <= 20 else base_size
		# A caption that EditorialUI.fit_text already shrank to fit its box has no
		# room left to grow into. Enlarging it would trade a readable small line
		# for a big clipped one, which is the opposite of an accessibility win.
		if node.has_meta("fit_font_ceiling"):
			applied_size = mini(applied_size, int(node.get_meta("fit_font_ceiling")))
		node.add_theme_font_size_override("font_size", applied_size)
		node.set_meta("accessibility_applied_font_size", applied_size)
	for child in node.get_children():
		_apply_text_scale_to(child, scale_factor)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if ai_companion and device == 1:
		return
	if device < 0 or device > 1:
		return
	last_input_gamepad[device] = connected
	# Every screen that is not the run itself is listed here: a pause menu opened
	# behind one of them is a menu nothing can reach or close. The title joined
	# that list when it became the screen the game opens on.
	if not connected and not title_active and not lobby_active and not character_select_active and not game_over and not level_up_active and not resonance_vote_active:
		_set_pause(true)
		EditorialUI.connection_notice(self, device)


func _input(event: InputEvent) -> void:
	if is_instance_valid(details_overlay) and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("build_details") and character_select_active and not character_exit_confirm:
			ReviewUI.toggle_character_details(self)
			get_viewport().set_input_as_handled()
			return
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
	if lobby_active and not lobby_exit_confirm and event.is_pressed() and not event.is_echo():
		if event is InputEventJoypadButton:
			_join_lobby_with_gamepad(event.device)
		elif event is InputEventKey:
			var key: int = (event as InputEventKey).physical_keycode
			if key == KEY_H:
				online.host_game()
			elif key == KEY_J:
				online.join_game(CoopSelectionUI.lan_address(self))
			elif key in [KEY_W, KEY_A, KEY_S, KEY_D]:
				_join_lobby_slot(0, -1, "키보드 WASD")
			elif key in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
				_join_lobby_slot(1, -1, "키보드 방향키")
	# F11 and F12 are lent to the debug panel while it is open: it puts its frame
	# metering and its combat-render toggle there, and both of those are read as
	# raw keycodes rather than as actions — so without this the pair of them
	# would fire together with 전체화면 and 달빛 연출 on the same press.
	var debug_panel_open: bool = is_instance_valid(debug_inspector) and bool(debug_inspector.is_open)
	if event.is_action_pressed("toggle_moonlight"):
		if debug_panel_open:
			return
		_toggle_moonlight()
		get_viewport().set_input_as_handled()
		return
	# Alt+Enter as well as F11. It is the shortcut every Windows game has, and it
	# is the one a player reaches for once a full-screen window has swallowed the
	# desktop. It is matched as a raw chord rather than bound as an action
	# because Godot's action matching ignores modifiers the bound event does not
	# mention: an Alt+Enter bound to 전체화면 would also register as menu_confirm
	# and 재시작, which are both plain Enter.
	var key := event as InputEventKey
	var alt_enter: bool = (key != null and key.pressed and not key.echo
		and key.alt_pressed and key.keycode in [KEY_ENTER, KEY_KP_ENTER])
	if event.is_action_pressed("toggle_fullscreen") or alt_enter:
		# F11 is lent to the debug panel while it is open; Alt+Enter is not.
		if debug_panel_open and not alt_enter:
			return
		_toggle_fullscreen()
		_persist_settings()
		if title_active:
			_refresh_title_ui()
		# menu_confirm and 재시작 are polled from Input rather than read off this
		# event, so marking it handled is not enough to stop a plain-Enter action
		# from seeing the same press. Dropping the next input tick is.
		if alt_enter:
			modal_input_guard = maxi(modal_input_guard, 2)
		get_viewport().set_input_as_handled()


## Closes the section that started at the last mark and opens the next one.
## Microseconds, accumulated across frames so one slow tick does not decide the
## answer; `profile_frames` divides them back down.
func _profile(section: String) -> void:
	if not profiling:
		return
	var now := Time.get_ticks_usec()
	profile_totals[section] = float(profile_totals.get(section, 0.0)) + float(now - _profile_at)
	_profile_at = now


func _physics_process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_physics_process(delta)
	FrameProbe.add(&"main (whole)", probe_started)


func _probed_physics_process(delta: float) -> void:
	# Reconnection must keep counting while the run is paused and while modal
	# input is guarded; OnlineCoop itself is process-always for the same reason.
	if online != null:
		online.connection_tick(delta)
	if modal_input_guard > 0:
		modal_input_guard -= 1
		return
	if is_instance_valid(details_overlay) and details_overlay.visible:
		return
	# Derived from the state flags every tick rather than toggled at each of
	# the dozen places an overlay opens or closes, so it cannot drift out of
	# sync with what is actually on screen.
	var modal := (title_active or lobby_active or character_select_active or level_up_active
		or resonance_vote_active or pause_active or game_over or cinematic_active)
	modal_dim.visible = modal
	# The growth screen, the resonance vote, the pause menu and a showcase (a
	# chest opening) show the run through; every other overlay replaces a screen
	# there is nothing behind. The resonance vote joined that list when it became
	# a growth screen: it is a choice made about two cats standing in a fight, and
	# blacking the fight out was the single biggest reason it read as a different
	# game's menu.
	var veil := (level_up_active or resonance_vote_active or pause_active or cinematic_active) and not (title_active or lobby_active or character_select_active or game_over)
	if modal_dim.veil_only != veil:
		modal_dim.veil_only = veil
		modal_dim.queue_redraw()
	for notice in notice_stack:
		if is_instance_valid(notice): notice.visible = not modal
	# A screen that interrupts a live fight freezes the tree and then *moves the
	# camera*: growth, a chest and the pause menu all pull the view in on the
	# pair and lift it. The crowd is drawn in batches culled against this
	# rectangle and the bodies themselves are hidden nodes, so a view that walks
	# past a stale rectangle walks into enemies nobody is drawing. The early
	# returns below are what would otherwise leave it stale.
	#
	# Only those screens, and not every modal: the title, the lobby and
	# character select have no fight behind them to keep drawn, and this value
	# also decides how often the crowd separation runs on a given body — so
	# writing it from a state that has no camera worth speaking of would change
	# the separation rate for nothing.
	if veil and is_instance_valid(crowd_renderer):
		crowd_renderer.view_rect = _visible_world_rect()
	if online.is_client():
		online.client_tick(delta)
		# The client's crowd arrives in snapshots rather than from a local tick,
		# but it is drawn by the same batch renderer, which only rebuilds when it
		# is told the crowd moved. Returning before this left a client's enemies
		# frozen where the renderer first saw them.
		# The received shots travel on this loop too: nothing else moves them now
		# that they have no physics callback of their own.
		if not (pause_active or level_up_active or resonance_vote_active \
				or cinematic_active or game_over):
			_step_enemy_shots(delta)
		crowd_renderer.view_rect = _visible_world_rect()
		crowd_renderer.dirty = true
		return
	# The run is over on the result screen, so its bars are stale information
	# drawn on top of the panel that replaced them — and the P2 panel reaches
	# far enough right to clip the overlay's own corner.
	combat_hud.visible = not title_active and not lobby_active and not character_select_active and not game_over and not pause_active and not resonance_vote_active
	if modal:
		# The loadout under each health bar stays up through growth and a chest:
		# those are exactly the moments it is changing.
		if not (level_up_active or cinematic_active):
			for slot in 2:
				combat_hud.get_node("Carried%d" % slot).visible = false
		_hide_boss_readout()
		# Both of these live above the dim, so a fading banner or an off-screen
		# arrow would otherwise sit on top of the overlay panel.
		threat_edge_indicator.visible = false
		item_edge_indicator.visible = false
		message_label.modulate.a = 0.0
	# Checked before every other state: a showcase is on top of whatever opened
	# it, and the run must not advance underneath it.
	if cinematic_active:
		return
	if title_active:
		lobby_input_cooldown = maxf(0.0, lobby_input_cooldown - delta)
		if lobby_input_cooldown <= 0.0:
			_handle_title_input()
		return
	if lobby_active:
		lobby_input_cooldown = maxf(0.0, lobby_input_cooldown - delta)
		if lobby_exit_confirm:
			if Input.is_action_just_pressed("menu_confirm"):
				_confirm_lobby_exit()
			elif Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
				_set_lobby_exit_confirm(false)
			return
		if lobby_input_cooldown <= 0.0 and Input.is_action_just_pressed("pause"):
			_set_lobby_exit_confirm(true)
		return
	if game_over:
		_handle_result_input()
		return
	if pause_active:
		_handle_pause_input()
		return
	if character_select_active:
		if not character_exit_confirm:
			_step_ai_character(delta)
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
	if profiling:
		profile_frames += 1
		_profile_at = Time.get_ticks_usec()
		_profile_frame_at = _profile_at
	weapon_controller.elapsed = elapsed
	for player in players:
		if player.input_source == ChainPlayer.InputSource.AI:
			var command := CompanionController.command(player, players[0], spatial_grid, enemy_shots, chain_max_length, self)
			player.set_command(command["movement"], command["dash"])
		player.step_movement(delta)
		player.step_recovery(delta)
	_apply_chain_constraint()
	_update_revives(delta)
	_update_timed_items(delta)
	_refill_lifesteal(delta)
	_update_chain_ward(delta)
	_update_chain_integrity(delta)
	_update_chain_visual()
	_update_camera(delta)
	# Again, now that this tick's camera move has happened.
	crowd_renderer.view_rect = _visible_world_rect()

	var cull_origin := (players[0].position + players[1].position) * 0.5
	_update_contact_pressure()
	item_aura.step(delta)
	simulation_phase += 1
	_profile("players_chain_camera")
	# What is left of the tick after the crowd separation was fixed is not any one
	# line inside the step — it is the six hundred calls themselves. So the crowd
	# is split into batches and one batch steers per tick, with the skipped time
	# handed back as a larger delta. Timers, cooldowns and travel therefore run at
	# the same rate they always did; what drops is how often a body reconsiders
	# where it is going, which for a body walking a straight line at the pair is
	# the one thing that can be sampled coarsely without anyone being able to see
	# it. Two exemptions steer every tick regardless: the bosses, because they are
	# the fight, and anything mid-telegraph, because a warning has to be smooth to
	# be readable. Contact needs no exemption — a touch is gated by a cooldown of
	# three quarters of a second per body, so checking for it on alternate ticks
	# delays a hit by at most a sixtieth of a second and changes no damage at all,
	# and nothing on the field moves far enough between updates to pass through a
	# survivor unnoticed. A body that starts a windup is telegraphing by the end
	# of the same step, so it is back on the full-rate tick before its warning has
	# drawn a single frame.
	var cull_radius_squared := ENEMY_CULL_RADIUS * ENEMY_CULL_RADIUS
	var stepping := time_stop_remaining <= 0.0
	var staggering := delta <= MAX_STAGGER_DELTA
	for enemy_index in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[enemy_index] as ChaserEnemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var batch := enemy.ai_batch + simulation_phase
		# Bosses and fixed scenery remain in the world when the pair wanders away.
		if not enemy.boss and not enemy.scenery and enemy.position.distance_squared_to(cull_origin) > cull_radius_squared:
			# Swapped out rather than removed in place: remove_at shifts every body
			# after it, and a crowd walking off one edge culls dozens a tick.
			enemies[enemy_index] = enemies[enemies.size() - 1]
			enemies.pop_back()
			wave_director.release_enemy(enemy)
			continue
		if not stepping:
			continue
		if not staggering or enemy.boss or enemy.telegraphing:
			enemy.step(players, delta)
		elif enemy.on_screen:
			if batch % AI_BATCHES == 0:
				enemy.step(players, delta * AI_BATCHES)
		elif batch % OFFSCREEN_AI_BATCHES == 0:
			enemy.step(players, delta * OFFSCREEN_AI_BATCHES)
	_profile("enemy_ai")
	spatial_grid.rebuild(enemies)
	_profile("grid_rebuild")
	_separate_crowd()
	crowd_renderer.dirty = true
	_profile("crowd_separation")
	# Ticked here rather than in _gain_shared_xp so the queue drains on run
	# time: the pair gets the gap back as play, not as a paused screen.
	if level_up_gap_remaining > 0.0:
		level_up_gap_remaining = maxf(0.0, level_up_gap_remaining - delta)
		if level_up_gap_remaining <= 0.0 and progression.can_level_up():
			_begin_level_up()
			return
	bursts.step(delta)
	particles.step(delta)
	flight_field.step(delta)
	rooftop_occlusion.step()
	_update_threat_indicator()
	_update_item_indicator()
	_profile("effects")
	experience_system.step(players, delta)
	field_items.step(players, delta)
	_step_enemy_shots(delta)
	_profile("pickups")

	for player_index in 2:
		for weapon_slot in weapon_loadouts[player_index].size():
			attack_timers[player_index][weapon_slot] -= delta

	var midpoint := (players[0].position + players[1].position) * 0.5
	if time_stop_remaining <= 0.0:
		for enemy in wave_director.step(delta, elapsed, midpoint, enemies.size()):
			_register_enemy(enemy)
	_profile("spawning")
	for player_index in 2:
		for weapon_slot in weapon_loadouts[player_index].size():
			if attack_timers[player_index][weapon_slot] <= 0.0:
				weapon_controller.perform_attack(player_index, weapon_slot, _tension_damage_multiplier())
				attack_timers[player_index][weapon_slot] = _weapon_interval(player_index, weapon_slot)
	_profile("weapons")
	weapon_controller.chain_length = chain_max_length
	weapon_controller.chain_tension = clampf(
		players[0].position.distance_to(players[1].position) / chain_max_length, 0.0, 1.0
	)
	wave_director.boss_active = is_instance_valid(boss_enemy) and not boss_enemy.dead
	# The pair's move charges at the pair's own rate: a held-out chain brings it
	# round faster, a slack one slower, and a survivor on the floor nearly stops
	# it. Same tension number the HUD and the overcharge bonus already read.
	for resonance in resonance_system.step(delta, ResonanceSystem.charge_rate(
		clampf(players[0].position.distance_to(players[1].position) / maxf(1.0, chain_max_length), 0.0, 1.0),
		not players[0].downed and not players[1].downed)):
		weapon_controller.perform_resonance(resonance,
			_tension_damage_multiplier() * _resonance_trade_power(resonance))
		# The payoff for having been tied together all run: the chain floods.
		chain_flow.surge()
		run_stats["resonance_casts"] = int(run_stats["resonance_casts"]) + 1
	if is_instance_valid(boss_enemy) and not boss_enemy.dead:
		boss_bar.report(boss_enemy.health, boss_enemy.max_health, bool(boss_enemy.boss_enraged))
		boss_health_text_label.text = String(boss_bar.health_text)

	_profile("resonance")
	_update_hud()
	_refresh_item_state_veil()
	_profile("hud")
	if profiling:
		profile_frame_usec.append(Time.get_ticks_usec() - _profile_frame_at)
	if (players[0].downed and players[1].downed) or players[0].bleedout_remaining <= 0.0 or players[1].bleedout_remaining <= 0.0:
		_end_run()
	online.host_tick(delta)


## The boss bar, its name and its health text are parented to the HUD layer
## rather than to combat_hud, so hiding the HUD left the readout drawn across
## every overlay — a stray "4799 / 4799" floating over the growth screen.
func _hide_boss_readout() -> void:
	boss_bar.visible = false
	boss_label.visible = false
	boss_health_text_label.visible = false


func _create_world() -> void:
	# The run remains an ordinary 2D simulation. LIFTED only gives drawings a
	# vertical axis; unlike the finite prototype's perspective view it never
	# changes a gameplay coordinate as the camera crosses the endless roof.
	RooftopSpace.view_mode = RooftopSpace.View.LIFTED
	RooftopSpace.focus = Vector2.ZERO
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
	wave_director.reclaim_capacity = _reclaim_spawn_capacity
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_calm_started.connect(_on_wave_calm_started)
	wave_director.encounter_started.connect(_on_encounter_started)
	add_child(wave_director)
	item_aura = preload("res://scripts/effects/item_aura.gd").new()
	item_aura.game = self
	item_aura.z_index = 7
	add_child(item_aura)
	resonance_system = ResonanceScript.new() as ResonanceSystem
	add_child(resonance_system)

	arena_floor = ArenaFloorScript.new() as ArenaFloor
	add_child(arena_floor)

	# Actors and solid roof furniture share one y-sorted layer. Their origins
	# are all the point where they meet the roof, so this alone decides whether
	# a cat passes behind or in front of a vent.
	world_stage = Node2D.new()
	world_stage.name = "WorldStage"
	world_stage.y_sort_enabled = true
	# One step above the friendly attack effects, which top out at 4 (a scythe
	# sweep, a gravity well, a combat flare): the crowd is what the player has to
	# read and dodge, so a friendly effect must never paint over an enemy.
	world_stage.z_index = WORLD_STAGE_Z
	add_child(world_stage)
	rooftop_props = RooftopPropFieldScript.new() as RooftopPropField
	rooftop_props.configure(world_stage)
	add_child(rooftop_props)
	rooftop_props.follow(Vector2.ZERO)
	# The ordinary crowd is drawn in batches rather than by each enemy node;
	# see CrowdRenderer for why and for which enemies still draw themselves.
	crowd_renderer = CrowdRendererScript.new() as CrowdRendererScript
	crowd_renderer.name = "CrowdRenderer"
	crowd_renderer.enemies = enemies
	crowd_renderer.shots = enemy_shots
	crowd_renderer.stage = world_stage
	add_child(crowd_renderer)

	bursts = BurstFieldScript.new() as BurstField
	add_child(bursts)

	particles = ParticleFieldScript.new() as ParticleField
	add_child(particles)
	flight_field = FlightFieldScript.new() as FlightField
	add_child(flight_field)

	chain_arc = ChainArcScript.new() as ChainArc
	world_stage.add_child(chain_arc)

	chain_flow = ChainFlowScript.new() as ChainFlow
	world_stage.add_child(chain_flow)

	world_camera = Camera2D.new()
	world_camera.enabled = true
	# Godot's built-in smoothing used to run on top of the manual lerp in
	# _update_camera, so every camera move was damped twice and the view
	# lagged the pair. The manual lerp is the one that also applies shake, so
	# it stays and this one goes.
	world_camera.position_smoothing_enabled = false
	add_child(world_camera)

	_apply_moonlight()


## The whole moonlight pass hangs off one switch, because the only way to know
## whether a lighting change helped is to see the same scene with it and
## without it — and the scene that decides it is the one at minute twenty with
## two hundred enemies on screen, which is not a scene anyone can set up twice.
## F12 during a run. Deliberately not saved: this is an instrument, not a
## preference, and a preference would have to earn a row in the pause menu.
func _toggle_moonlight() -> void:
	Moonlight.enabled = not Moonlight.enabled
	_apply_moonlight()
	if not title_active and not lobby_active:
		_show_message(tr("달빛 연출 %s") % tr("켜짐" if Moonlight.enabled else "꺼짐"), Color("8ecae6"))


func set_combat_visuals_enabled(enabled: bool) -> void:
	combat_visuals_enabled = enabled
	weapon_controller.visible = enabled
	flight_field.visible = enabled
	bursts.visible = enabled
	particles.visible = enabled
	crowd_renderer.attack_visuals_enabled = enabled
	crowd_renderer.refresh()


## Everything the pass touches that is drawn once and kept, rather than redrawn
## every frame: the rooftop window, the actors, and the chain's halo material.
func _apply_moonlight() -> void:
	chain_flow.visible = Moonlight.enabled
	arena_floor.queue_redraw()
	for player in players:
		if is_instance_valid(player):
			player.queue_redraw()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_redraw()
	if is_instance_valid(chain_arc):
		chain_arc.queue_redraw()


func _create_players() -> void:
	var player_one := PlayerScene.new() as ChainPlayer
	player_one.setup(1, Color("43d9ff"))
	player_one.position = Vector2(-105.0, 0.0)
	player_one.stand_height = RooftopSpace.CAT_STAND
	player_one.z_index = 0
	world_stage.add_child(player_one)
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
	player_two.setup(2, CatTheme.P2)
	player_two.position = Vector2(105.0, 0.0)
	player_two.stand_height = RooftopSpace.CAT_STAND
	player_two.z_index = 0
	world_stage.add_child(player_two)
	player_two.damaged.connect(_on_player_damaged)
	player_two.downed_started.connect(_on_player_downed)
	player_two.revived_player.connect(_on_player_revived)
	player_two.dashed.connect(_on_player_dashed)
	player_two.second_chance_used.connect(_on_second_chance_used)
	player_two.dodged.connect(_on_player_dodged)
	player_two.reflected.connect(_on_damage_reflected)
	player_two.footfall.connect(_on_footfall)
	players.append(player_two)


## One typeface for the whole game, including the parts that are not Controls —
## see CatTheme.FAMILY.
const CatUIFont := CatTheme.FAMILY


func _build_ui_theme_host() -> Control:
	var theme := Theme.new()
	theme.default_font = CatTheme.adopt()
	theme.set_color("font_color", "Label", CatTheme.CREAM)
	# Every button is a paper button (CatTheme.button_surface), written in ink.
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(key, "Button", CatTheme.INK)
	theme.set_color("font_disabled_color", "Button", Color(CatTheme.MUTED, 0.6))
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
	# Between the play field and the HUD text: it has to tint the fight without
	# tinting the numbers a player reads to understand the fight.
	item_state_veil = ItemStateVeilScript.new() as ItemStateVeil
	item_state_veil.name = "ItemStateVeil"
	layer.add_child(item_state_veil)
	growth_flash = ColorRect.new()
	growth_flash.name = "GrowthFlash"
	growth_flash.position = Vector2.ZERO
	growth_flash.size = Vector2(1280.0, 720.0)
	growth_flash.color = Color(CatTheme.GOLD, 1.0)
	growth_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its own clock, like the growth panel's: the tree is paused when it plays.
	growth_flash.process_mode = Node.PROCESS_MODE_ALWAYS
	growth_flash.modulate.a = 0.0
	growth_flash.visible = false
	layer.add_child(growth_flash)
	var screen_host := layer
	combat_hud = Control.new()
	combat_hud.name = "CombatHUD"
	combat_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(combat_hud)
	layer = combat_hud

	hud_portrait_icons = [
		_create_icon_rect(layer, Vector2(26.0, 21.0), Vector2(42.0, 42.0)),
		_create_icon_rect(layer, Vector2(1212.0, 21.0), Vector2(42.0, 42.0)),
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
	p2_status_label.add_theme_color_override("font_color", CatTheme.P2)
	_confine_label(p2_status_label)
	layer.add_child(p2_status_label)
	p2_health_bar = _create_bar(layer, Vector2(913.0, 56.0), Vector2(330.0, 28.0), CatTheme.P2)
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
	resonance_pips = ResonancePipsScript.new() as Control
	resonance_pips.position = Vector2(710.0, 125.0)
	resonance_pips.size = Vector2(115.0, 6.0)
	layer.add_child(resonance_pips)

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
	# Drawn rather than themed: the one enemy the run is built around used to
	# announce itself with the same widget as the XP meter (see BossHealthBar).
	boss_bar = BossHealthBarScript.new() as Control
	boss_bar.position = Vector2(390.0, 148.0)
	boss_bar.size = Vector2(500.0, 38.0)
	boss_bar.visible = false
	layer.add_child(boss_bar)
	# The name and the health number are painted by the bar itself now. Both
	# labels stay as hidden stubs because the online snapshot, the pause screen
	# and three tests still address them by name.
	boss_health_text_label = _create_bar_text(layer, Vector2(390.0, 164.0), Vector2(500.0, 22.0), 14)
	boss_health_text_label.size = Vector2(500.0, 22.0)
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
	layer.add_child(message_label)

	layer = screen_host
	level_overlay = CatPanel.new()
	# Growth is presented directly over the paused fight.
	level_overlay.translucent = true
	# Its own clock: the tree is paused while it is open, so the entrance and
	# exit have to run on a node that ignores that.
	level_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	level_overlay.position = Vector2(0.0, LEVEL_OVERLAY_Y)
	level_overlay.size = Vector2(1280.0, LEVEL_OVERLAY_HEIGHT)
	# Cards provide their own reading surface; the overlay adds no window frame.
	level_overlay.chromeless = true
	level_overlay.visible = false
	layer.add_child(level_overlay)

	level_card_labels[0] = _create_level_cards(level_overlay)
	level_card_labels[1] = _create_level_cards(level_overlay)

	# The resonance vote is a growth screen. It is the same moment — the run is
	# held, the pair are looking at cards, one of them is going to change what
	# they have built — so it is now literally the same furniture: the same panel
	# geometry, the same card component, the same fan, the same entrance, and the
	# same paused fight showing through behind it (see the `veil` flag in
	# _physics_process). It used to be a boxed-in window of wrapped text floating
	# over a blacked-out screen, which read as a different game's menu and hid
	# the two cats the choice is about.
	resonance_overlay = CatPanel.new()
	resonance_overlay.translucent = true
	resonance_overlay.chromeless = true
	resonance_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	resonance_overlay.position = Vector2(0.0, LEVEL_OVERLAY_Y)
	resonance_overlay.size = Vector2(1280.0, LEVEL_OVERLAY_HEIGHT)
	resonance_overlay.visible = false
	layer.add_child(resonance_overlay)

	resonance_title = Label.new()
	resonance_title.position = Vector2(0.0, 4.0)
	resonance_title.size = Vector2(1280.0, 40.0)
	resonance_title.text = "공명핵 — 둘이 함께 하나를 고르세요"
	resonance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_title.add_theme_font_size_override("font_size", 27)
	resonance_title.add_theme_color_override("font_color", CatTheme.GOLD)
	_confine_label(resonance_title)
	resonance_overlay.add_child(resonance_title)
	_add_cat_caption(resonance_overlay, "보스가 남긴 공명핵으로 공명 하나를 켭니다. 같은 카드에 둘 다 확정하면 발현!", Vector2(240, 44), Vector2(800, 24), 15)

	# Both survivors read the same hand here, so there is one fan in the middle
	# rather than the level-up screen's own-hand/partner-hand split. Each card
	# carries both cursors on its badge strip, which is the negotiation the
	# mechanic is asking for: you can see what your partner is pointing at before
	# either of you commits.
	resonance_cards = []
	for index in RESONANCE_CARD_SLOTS:
		var card := CardVisual.create_card()
		# The two portraits flank the resonance's own icon. A resonance is the
		# only thing in the game that belongs to both survivors at once, and the
		# pair of cats either side of one symbol is what says that before anyone
		# reads the tag line underneath.
		for portrait_slot in 2:
			var cat_icon := _create_icon_rect(card,
				Vector2(8 if portrait_slot == 0 else RESONANCE_CARD_WIDTH - 50.0, 54.0),
				Vector2(42.0, 42.0))
			cat_icon.name = "Cat%d" % portrait_slot
		resonance_overlay.add_child(card)
		resonance_cards.append(card)

	resonance_status = Label.new()
	resonance_status.position = Vector2(220.0, 452.0)
	resonance_status.size = Vector2(840.0, 56.0)
	resonance_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resonance_status.add_theme_font_size_override("font_size", 17)
	resonance_status.add_theme_color_override("font_color", Color("e4c1f9"))
	_confine_label(resonance_status, true)
	resonance_overlay.add_child(resonance_status)

	var resonance_controls := Label.new()
	resonance_controls.name = "ResonanceControls"
	resonance_controls.position = Vector2(220.0, 512.0)
	resonance_controls.size = Vector2(840.0, 24.0)
	resonance_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resonance_controls.add_theme_font_size_override("font_size", 13)
	resonance_controls.add_theme_color_override("font_color", Color("b7d8ed"))
	_confine_label(resonance_controls)
	resonance_overlay.add_child(resonance_controls)

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
		bed.add_theme_stylebox_override("panel", CatTheme.surface(CatTheme.NIGHT_PANEL))
		character_overlay.add_child(bed)
		# The Korean key, not the translation: the caption is built once, and a
		# Label translates its own text every time it draws, so leaving the key
		# in place keeps it right after the language is changed. EditorialUI
		# also finds these two by their text when it rebuilds the screen.
		_add_cat_caption(character_overlay, "나" if slot == local_view_slot() else "동료",
			Vector2(46 + slot * 564, 108), Vector2(100, 30), 18)

	character_portrait_icons = [
		_create_icon_rect(character_overlay, Vector2(258.0, 92.0), Vector2(84.0, 84.0)),
		_create_icon_rect(character_overlay, Vector2(798.0, 92.0), Vector2(84.0, 84.0)),
	]
	character_p1_label = _create_character_label(Vector2(38.0, 184.0), Color("43d9ff"))
	character_p2_label = _create_character_label(Vector2(578.0, 184.0), CatTheme.P2)
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

	# Same panel geometry as the lobby it hands over to, so the two screens sit
	# in the same frame and the hand-off reads as one page turning rather than
	# the window jumping.
	title_overlay = CatPanel.new()
	title_overlay.position = Vector2(90.0, 55.0)
	title_overlay.size = Vector2(1100.0, 610.0)
	title_overlay.visible = false
	layer.add_child(title_overlay)
	title_rows = []
	for index in maxi(8, maxi(TITLE_MENU.size(), TITLE_SETTINGS.size())):
		var row := Label.new()
		row.name = "TitleRow%d" % index
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_color", CatTheme.CREAM)
		_confine_label(row)
		title_overlay.add_child(row)
		title_rows.append(row)
	title_note = Label.new()
	title_note.name = "TitleNote"
	title_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title_note.add_theme_font_size_override("font_size", 15)
	title_note.add_theme_color_override("font_color", CatTheme.MUTED)
	_confine_label(title_note)
	title_overlay.add_child(title_note)

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
	lobby_p2_label = _create_lobby_slot(Vector2(575.0, 318.0), CatTheme.P2)
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
	result_overlay.position = Vector2(148.0, 40.0)
	result_overlay.size = Vector2(984.0, 640.0)
	result_overlay.visible = false
	layer.add_child(result_overlay)
	result_label = Label.new()
	result_label.position = Vector2(40.0, 26.0)
	result_label.size = Vector2(840.0, 598.0)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 22)
	_confine_label(result_label, true)
	result_overlay.add_child(result_label)
	for slot in 2:
		var portrait := _create_icon_rect(result_overlay, Vector2(55 + slot * 735, 58), Vector2(75, 75))
		portrait.name = "ResultCat%d" % slot

	threat_edge_indicator = _create_edge_indicator(layer, Color("ff5d8f"))
	item_edge_indicator = _create_edge_indicator(layer, CHEST_POINTER_COLOR)
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
	var style := CatTheme.surface(CatTheme.NIGHT_PANEL.lerp(color, 0.12))
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


## Both marks are the same drawn control (see EdgePointer): an arrowhead on the
## bearing plus a pill that sizes itself to its own text. They used to be plain
## Labels in a flat box, which meant the two most time-critical readings on the
## HUD — which way, how far — were carried by a word and a number rather than by
## a shape that points.
func _create_edge_indicator(parent: Node, color: Color) -> Control:
	var pointer := EdgePointerScript.new() as Control
	pointer.accent = color
	pointer.visible = false
	parent.add_child(pointer)
	return pointer


func _create_bar(parent: Node, bar_position: Vector2, bar_size: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = bar_position
	bar.size = bar_size
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = CatTheme.NIGHT
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


## The growth screen used to be a 1240x568 panel parked over the middle of the
## roof: it covered the fight it was interrupting, and the pair chose their next
## card while looking at a box instead of at the run.
##
## It is a band along the bottom now. The world stays on screen, the camera pulls
## in on the pair while the tree is paused (see _pull_camera_for_growth), and the
## choices sit under the action as two fans of cards — P1's on the left, P2's on
## the right — the way a hand of cards actually sits in front of a player.
const LEVEL_OVERLAY_Y := 176.0
const LEVEL_OVERLAY_HEIGHT := 544.0
const LEVEL_CARD_SLOTS := 6
## Where each hand's reroll button is parked before NeonGrowthUI places it.
const LEVEL_HALF_X := [0.0, 640.0]

## The resonance hand, laid out the way the growth hand is: one centred fan of
## full-size growth cards. The numbers match NeonGrowthUI's three-card case on
## purpose — the two screens are the same moment and a player should not have to
## re-learn where to look.
const RESONANCE_CARD_SLOTS := 3
const RESONANCE_CARD_WIDTH := 224.0
const RESONANCE_CARD_HEIGHT := 372.0
const RESONANCE_CARD_SPREAD := 244.0
const RESONANCE_CARD_Y := 88.0
## How far the outermost card in the fan is tilted, in radians.
const RESONANCE_CARD_TILT := 0.11
## Height at the bottom of a resonance card kept clear of its body text: the
## badge strip that carries the two cursors, plus the row of 선택 buttons
## ReviewUI parks above it for mouse play.
const RESONANCE_CARD_BUTTON_ROOM := 104.0

## One reroll for a whole run meant nobody ever spent it: a resource you can
## never get back is a resource you hoard. It now refills on a schedule, so
## spending one is a normal thing to do rather than a decision about the
## entire run.
const REROLL_START := 2
const REROLL_PER_LEVELS := 3
const REROLL_CAP := 3

## Each point of shared luck gives a visible chance at a fourth choice.
## The ceiling preserves the normal three-card hand as a possible outcome.
const LUCK_FOURTH_CARD_CHANCE_PER_POINT := 0.07
const LUCK_FOURTH_CARD_MAX_CHANCE := 0.60


## The six card slots one survivor's hand can deal, built from the shared growth
## card template (the chest showcase deals the same card). NeonGrowthUI lays
## them out and paints them each refresh.
func _create_level_cards(parent: Node) -> Array:
	var cards: Array = []
	for index in LEVEL_CARD_SLOTS:
		var card := CardVisual.create_card()
		parent.add_child(card)
		cards.append(card)
	return cards


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


## Menu rows, per page. The last entry of every page is the way out of it.
const TITLE_MENU := ["게임 시작", "영구 성장", "설정", "제작진", "게임 종료"]
const TITLE_SETTINGS := [
	"화면 모드", "창 해상도", "주사율 / FPS", "수직 동기화", "큰 글자",
	"화면 흔들림", "피해 숫자", "효과음 음량", "음악 음량", "언어", "뒤로",
]
const TITLE_CREDITS := ["뒤로"]


func _begin_title() -> void:
	feedback.play_music("title")
	title_active = true
	_set_lobby_exit_confirm(false)
	title_mode = "menu"
	title_cursor = 0
	lobby_active = false
	character_select_active = false
	_set_character_exit_confirm(false)
	lobby_input_cooldown = 0.25
	title_overlay.visible = true
	lobby_overlay.visible = false
	character_overlay.visible = false
	combat_hud.visible = false
	help_label.text = ""
	_refresh_title_ui()
	get_tree().paused = true


func _title_rows() -> Array:
	match title_mode:
		"modes": return ["AI 모드    혼자 출발", "로컬 멀티    함께 출발", "LAN 멀티    방 만들기 / 연결", "뒤로"]
		"settings": return TITLE_SETTINGS
		"meta":
			var rows: Array = []
			if meta_reset_pending:
				return ["취소", "성장 초기화    사용한 생선 전액 환급"]
			if meta_fish_reset_pending:
				return ["취소", "생선 0개로 초기화    되돌릴 수 없음"]
			for entry in MetaProgression.UPGRADES.slice(meta_page * 6, meta_page * 6 + 6):
				rows.append(String(entry["name"]))
			rows.append(tr("다음 성장 분야  %d / %d") % [meta_page + 1, ceili(MetaProgression.UPGRADES.size() / 6.0)])
			rows.append("성장 초기화    전액 환급")
			rows.append("생선 초기화    보유량 0")
			return rows
		"credits": return TITLE_CREDITS
	return TITLE_MENU


func _leave_title_subpage() -> void:
	feedback.play_cue("cancel")
	if title_mode == "meta" and (meta_reset_pending or meta_fish_reset_pending):
		meta_reset_pending = false
		meta_fish_reset_pending = false
		title_cursor = 0
		_refresh_title_ui()
		return
	if title_mode == "menu":
		return
	var previous_mode := title_mode
	title_mode = "menu"
	match previous_mode:
		"meta": title_cursor = 1
		"settings": title_cursor = 2
		"credits": title_cursor = 3
		_: title_cursor = 0
	_refresh_title_ui()


func _handle_title_input() -> void:
	if title_mode == "settings" and (Input.is_action_just_pressed("menu_left")
			or Input.is_action_just_pressed("menu_right")):
		_change_setting(title_cursor,
			-1 if Input.is_action_just_pressed("menu_left") else 1, false)
		_refresh_title_ui()
	elif title_mode == "settings" and (Input.is_action_just_pressed("menu_previous")
			or Input.is_action_just_pressed("menu_next")):
		var step := 1 if Input.is_action_just_pressed("menu_next") else -1
		title_cursor = wrapi(title_cursor + step, 0, TITLE_SETTINGS.size())
		feedback.play_cue("select")
		_refresh_title_ui()
	elif Input.is_action_just_pressed("menu_previous") or Input.is_action_just_pressed("menu_next"):
		var step := 1 if Input.is_action_just_pressed("menu_next") else -1
		title_cursor = wrapi(title_cursor + step, 0, _title_rows().size())
		feedback.play_cue("select")
		_refresh_title_ui()
	elif Input.is_action_just_pressed("menu_confirm"):
		_activate_title_item(title_cursor)
	elif Input.is_action_just_pressed("menu_cancel") or Input.is_action_just_pressed("pause"):
		# Cancel leaves a sub-page. On the menu itself it does nothing: quitting
		# is an entry a player picks, not something a stray key press does.
		if title_mode != "menu":
			_leave_title_subpage()


func _activate_title_item(index: int) -> void:
	if not title_active:
		return
	var rows := _title_rows()
	if index < 0 or index >= rows.size():
		return
	title_cursor = index
	if title_mode == "settings":
		if index == 10:
			title_mode = "menu"
			title_cursor = 2
			feedback.play_cue("select")
		else:
			_change_setting(index, 1, true)
		_refresh_title_ui()
		return
	feedback.play_cue("select")
	if title_mode == "modes":
		if index == 3:
			title_mode = "menu"
			title_cursor = 0
			_refresh_title_ui()
			return
		_begin_lobby()
		lobby_input_cooldown = 0.0
		if index == 0:
			_join_ai_companion()
		elif index == 1:
			_join_lobby_slot(0, -1, "키보드 WASD")
			_join_lobby_slot(1, -1, "키보드 방향키")
		return
	if title_mode == "meta":
		if meta_reset_pending or meta_fish_reset_pending:
			if index == 1:
				if meta_fish_reset_pending:
					meta_progression.discard_points()
				else:
					meta_progression.reset_upgrades()
			meta_reset_pending = false
			meta_fish_reset_pending = false
			title_cursor = 0
			_refresh_title_ui()
			return
		if index == 6:
			meta_page = wrapi(meta_page + 1, 0, ceili(MetaProgression.UPGRADES.size() / 6.0))
			title_cursor = 0
			_refresh_title_ui()
			return
		if index == 7:
			meta_reset_pending = true
			title_cursor = 0
			_refresh_title_ui()
			return
		if index == 8:
			meta_fish_reset_pending = true
			title_cursor = 0
			_refresh_title_ui()
			return
		var entry: Dictionary = MetaProgression.UPGRADES[meta_page * 6 + index]
		if meta_progression.purchase(String(entry["id"])):
			feedback.play_cue("purchase")
		_refresh_title_ui()
		return
	if title_mode == "credits":
		title_mode = "menu"
		title_cursor = 3
		_refresh_title_ui()
		return
	match index:
		0:
			title_mode = "modes"
			title_cursor = 0
			_refresh_title_ui()
		1:
			title_mode = "meta"
			title_cursor = 0
			_refresh_title_ui()
		2:
			title_mode = "settings"
			title_cursor = 0
			_refresh_title_ui()
		3:
			title_mode = "credits"
			title_cursor = 0
			_refresh_title_ui()
		4: get_tree().quit()


func _refresh_title_ui() -> void:
	EditorialUI.refresh_title(self)
	ReviewUI.refresh_title(self)
	_apply_text_scale_to(title_overlay, 1.14 if settings.large_text_enabled else 1.0)


func _begin_lobby() -> void:
	if online != null and online.is_online():
		online.stop()
	_set_lobby_exit_confirm(false)
	ai_companion = false
	title_active = false
	title_overlay.visible = false
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


func _set_lobby_exit_confirm(enabled: bool) -> void:
	lobby_exit_confirm = enabled
	if is_instance_valid(lobby_overlay) and lobby_overlay.has_node("LobbyExitConfirm"):
		lobby_overlay.get_node("LobbyExitConfirm").visible = enabled
	if not enabled:
		lobby_input_cooldown = maxf(lobby_input_cooldown, 0.12)


func _confirm_lobby_exit() -> void:
	if online != null and online.is_online():
		online.stop()
	lobby_joined = [false, false]
	lobby_devices = [-1, -1]
	lobby_device_names = ["", ""]
	_set_lobby_exit_confirm(false)
	_begin_title()


func _join_ai_companion() -> void:
	if not lobby_active or lobby_input_cooldown > 0.0 or lobby_joined[1]:
		return
	ai_companion = true
	# Rotate through the credible shortlist between AI runs. A random starting
	# offset varies a fresh launch; incrementing prevents unlucky repeat rolls.
	ai_character_preference = posmod(ai_character_preference + 1, 5)
	if not lobby_joined[0]:
		_join_lobby_slot(0, -1, "키보드 WASD")
	_join_lobby_slot(1, -2, "AI 동료    자동 이동 / 구조 / 성장")


func local_view_slot() -> int:
	return 1 if online != null and online.is_client() else 0


func display_player_number(slot: int) -> int:
	return 1 if slot == local_view_slot() else 2


func player_label(slot: int) -> String:
	return tr("나") if slot == local_view_slot() else tr("동료")


func _step_ai_character(delta: float) -> void:
	if not ai_companion or character_confirmed[1]:
		return
	var previous := ai_think_remaining
	ai_think_remaining = maxf(0.0, ai_think_remaining - delta)
	if ai_think_remaining <= 0.0:
		selected_character_indices[1] = CompanionController.choose_character(self, 0)
		character_confirmed[1] = true
		_refresh_character_select_ui()
		if character_confirmed[0]:
			_start_selected_run()
	elif int(previous * 3.0) != int(ai_think_remaining * 3.0):
		selected_character_indices[1] = wrapi(selected_character_indices[1] + 1, 0, character_catalog.size())
		_refresh_character_select_ui()


func _can_control_player_slot(slot: int) -> bool:
	if slot < 0 or slot > 1:
		return false
	if online != null and online.is_client():
		return slot == 1
	if (online != null and online.is_host()) or ai_companion:
		return slot == 0
	return true


func _set_character_choice(slot: int, character_index: int, confirmed: bool) -> void:
	if not _can_control_player_slot(slot) or not character_select_active:
		return
	selected_character_indices[slot] = clampi(character_index, 0, character_catalog.size() - 1)
	character_confirmed[slot] = confirmed
	_refresh_character_select_ui()
	if online != null and online.is_client():
		online.request_character_choice(selected_character_indices[slot], confirmed)
	elif character_confirmed[0] and character_confirmed[1]:
		_start_selected_run()


func _confirm_growth_choice(slot: int, choice_index: int) -> void:
	if not _can_control_player_slot(slot) or not level_up_active or level_up_input_delay > 0.0:
		return
	if online != null and online.is_client():
		online.request_growth_select(choice_index)
	else:
		_select_upgrade(slot + 1, choice_index)


func _cancel_growth_choice(slot: int) -> void:
	if not _can_control_player_slot(slot) or not level_up_active:
		return
	if online != null and online.is_client():
		online.request_growth_cancel()
	elif selected_upgrade_indices[slot] >= 0 and selected_upgrade_indices[1 - slot] < 0:
		selected_upgrade_indices[slot] = -1
		feedback.play_cue("cancel")
		_refresh_level_up_ui()


func _reroll_growth_choice(slot: int) -> void:
	if (not _can_control_player_slot(slot) or not level_up_active
			or level_up_input_delay > 0.0 or selected_upgrade_indices[slot] >= 0
			or rerolls_remaining[slot] <= 0):
		return
	if online != null and online.is_client():
		online.request_growth_reroll()
	else:
		_reroll_choices(slot + 1)


func _join_lobby_with_gamepad(device: int) -> void:
	if device < 0 or device > 1:
		return
	_join_lobby_slot(device, device, tr("게임패드 %d") % (device + 1))


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
	EditorialUI.refresh_lobby(self)


func _format_lobby_slot(slot: int) -> String:
	var heading := "P%d  ·  %s" % [slot + 1, player_label(slot)]
	if lobby_joined[slot]:
		return (tr("%s    ✓ 참가 완료\n%s") % [heading, tr(lobby_device_names[slot])]).replace("\n", "    ")
	# The control hints are already in the footer. Keeping this card to one line
	# prevents the second line from disappearing behind its padded paper frame.
	return (tr("%s    ○ 참가 대기\n%s") % [heading, ""]).strip_edges()


func _begin_character_select() -> void:
	character_select_active = true
	_set_character_exit_confirm(false)
	character_confirmed = [false, false]
	ai_considered_human = -1
	character_overlay.visible = true
	_refresh_character_select_ui()
	get_tree().paused = true


func _handle_character_select_input() -> void:
	if character_exit_confirm:
		if Input.is_action_just_pressed("menu_confirm"):
			_confirm_character_exit()
		elif Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
			_set_character_exit_confirm(false)
		return
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_cancel"):
		_set_character_exit_confirm(true)
		return
	if online.is_client():
		return
	for player_index in 2:
		if (online.is_host() and player_index == 1) or (ai_companion and player_index == 1):
			continue
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


func _set_character_exit_confirm(enabled: bool) -> void:
	character_exit_confirm = enabled
	if is_instance_valid(character_overlay) and character_overlay.has_node("CharacterExitConfirm"):
		character_overlay.get_node("CharacterExitConfirm").visible = enabled
	if not enabled:
		lobby_input_cooldown = maxf(lobby_input_cooldown, 0.12)


func _confirm_character_exit() -> void:
	if online != null and online.is_online():
		online.stop()
	character_confirmed = [false, false]
	character_select_active = false
	_set_character_exit_confirm(false)
	_begin_title()


func _refresh_character_select_ui() -> void:
	if ai_companion and ai_considered_human != selected_character_indices[0]:
		ai_considered_human = selected_character_indices[0]
		ai_think_remaining = 1.4
		character_confirmed[1] = false
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
	_apply_text_scale_to(character_overlay, 1.14 if settings.large_text_enabled else 1.0)
	if online != null:
		online.send_character_state()
	if ai_companion:
		character_overlay.get_node("CharacterConfirm1").text = "AI    준비 완료" if character_confirmed[1] else "AI    조합 고민 중…"


## The select screen used to show a name, two bars and a sentence, which is not
## enough to choose with — especially now that the weapon you pick also decides
## which fusion and which treasure your whole run is aimed at. It now shows the
## full stat block, where the weapon ends up, and a plain-language difficulty
## read so the choice can be made without knowing the catalog by heart.
## Routes and materials are explicit here. A first-time player should be able
## to choose a plan before the run instead of losing a slot to a hidden recipe.
func _format_character_card(player_index: int) -> String:
	var character := character_catalog[selected_character_indices[player_index]]
	var tech_names: Array[String] = []
	var synergy_names: Array[String] = []
	var evolution := Evolutions.for_base(String(character["weapon_id"]))
	for tech in WeaponTechs.for_weapon(String(character["weapon_id"])):
		var treasure := Treasures.by_id(String(tech["synergy_treasure_id"]))
		tech_names.append(tr(String(tech["name"])))
		synergy_names.append(tr(String(treasure.get("name", "보물"))))
	var playstyle := String(EditorialUI.PLAYSTYLE.get(
		String(character["weapon_id"]), "자동 공격")).split("    ")[-1]
	return "\n".join([
		tr("무기    %s    %s") % [tr(String(character["weapon_name"])), tr(playstyle)],
		tr("테크 Lv.%d    %s") % [WeaponGrowthScript.TECH_UNLOCK_TIER, " / ".join(tech_names)],
		tr("필수 보물    %s") % " / ".join(synergy_names),
		tr("Lv.%d 진화    %s") % [Evolutions.EVOLUTION_TIER, tr(String(evolution.get("weapon_name", "최종 진화")))],
	])

## What this survivor does to the pair's leash, in plain language. The number
## itself is in the stat row; this says what it means.
func _chain_note(character: Dictionary) -> String:
	var contribution := float(character["chain"])
	if contribution >= 40.0:
		return tr("사슬 길게")
	if contribution <= -15.0:
		return tr("사슬 짧게")
	return tr("사슬 보통")


## The pair's shared read on their two picks, without naming anything they have
## not unlocked. It compares the two survivors' demands rather than previewing
## the tech tree, because "are these two going to cover for each other" is the
## question character select actually has to answer.
## The plan this cat's starting weapon is on, named before the run rather than
## discovered during it.
##
## Every starting weapon has one final form. The route decides which treasure
## completes it, so both possible materials are named before the run.
func _route_note(character: Dictionary) -> String:
	var evolution := Evolutions.for_base(String(character["weapon_id"]))
	if evolution.is_empty():
		return ""
	var synergies: Array[String] = []
	for tech in WeaponTechs.for_weapon(String(character["weapon_id"])):
		var treasure := Treasures.by_id(String(tech["synergy_treasure_id"]))
		var treasure_name := String(treasure.get("name", ""))
		if not treasure_name.is_empty() and treasure_name not in synergies:
			synergies.append(treasure_name)
	var localized_synergies: Array[String] = []
	for name in synergies:
		localized_synergies.append(tr(name))
	return tr("Lv.%d 진화  ·  %s    필수 보물 Lv.%d  %s") % [
		Evolutions.EVOLUTION_TIER, tr(String(evolution["weapon_name"])),
		Evolutions.REQUIRED_TREASURE_TIER, " / ".join(localized_synergies)]


func _synergy_preview() -> String:
	var first: Dictionary = character_catalog[selected_character_indices[0]]
	var second: Dictionary = character_catalog[selected_character_indices[1]]
	var first_profile := CharacterCatalog.difficulty_profile(first)
	var second_profile := CharacterCatalog.difficulty_profile(second)
	var coverage := (float(first_profile["coverage"]) + float(second_profile["coverage"])) * 0.5
	var durability := (float(first_profile["durability"]) + float(second_profile["durability"])) * 0.5

	if coverage < 0.4 and durability < 0.45:
		return tr("둘 다 좁게 싸우고 얇습니다 — 포위되기 전에 정리해야 합니다")
	if coverage < 0.4:
		return tr("둘 다 한 번에 적은 수만 처리합니다 — 몰리면 함께 물러나세요")
	if durability < 0.45:
		return tr("화력은 넓지만 둘 다 무릅니다 — 사슬 거리를 짧게 유지하세요")
	if coverage > 0.7 and durability > 0.6:
		return tr("넓게 처리하고 잘 버팁니다 — 과충전을 오래 끌고 가도 됩니다")
	return tr("한쪽이 넓게 쓸고 한쪽이 앞을 맡는 조합입니다")


func _start_selected_run() -> void:
	debug_run_tainted = false
	if is_instance_valid(debug_inspector):
		debug_inspector.reset_run()
	for player_index in 2:
		selected_characters[player_index] = character_catalog[selected_character_indices[player_index]].duplicate(true)
		weapon_loadouts[player_index] = [_build_weapon_state(selected_characters[player_index])]
		players[player_index].apply_character(selected_characters[player_index])
		if online.is_host() and player_index == 1:
			players[player_index].input_source = ChainPlayer.InputSource.REMOTE
		elif online.is_client():
			players[player_index].input_source = ChainPlayer.InputSource.REMOTE
		else:
			players[player_index].input_source = ChainPlayer.InputSource.AI if ai_companion and player_index == 1 else ChainPlayer.InputSource.LOCAL
		players[player_index].set_command(Vector2.ZERO)
		meta_progression.apply_to_player(players[player_index])
		attack_timers[player_index] = [0.15 + player_index * 0.12]
		treasure_loadouts[player_index] = []
		hud_portrait_icons[player_index].texture = IconCatalog.survivor(String(selected_characters[player_index]["id"]))
	character_select_active = false
	character_overlay.visible = false
	# Cleared here as well as in the lobby. Every way into a run has to leave the
	# front door shut behind it, and this is the only step all of them share —
	# the lobby hands over here, and so does anything that skips straight to a
	# chosen pair. Leaving it set kept the tree paused and the play field dimmed
	# under a title screen nobody could see.
	title_active = false
	title_overlay.visible = false
	# The leash is decided by who was picked. Two claw-range cats fight on a
	# 275px rope, two anchors on 480px, and that single number changes more
	# about how a run plays than any stat on the card above it.
	chain_max_length = CharacterCatalog.chain_length_for(selected_characters[0], selected_characters[1])
	chain_integrity = CHAIN_INTEGRITY_MAX
	chain_overloaded = false
	chain_tutorial_stage = 0
	chain_ward_remaining = 0.0
	chain_ward_pulse_timer = 0.0
	guard_remaining = 0.0
	frenzy_remaining = 0.0
	time_stop_remaining = 0.0
	for player in players:
		player.field_move_multiplier = 1.0
	# Cleared in place: the controller and its fields hold this same array.
	# Parked rather than freed — the pool outlives a run, so the next one starts
	# with its shots already built.
	for shot in enemy_shots:
		if is_instance_valid(shot):
			(shot as EnemyProjectile).release()
	enemy_shots.clear()
	rerolls_remaining = [REROLL_START, REROLL_START]
	level_up_gap_remaining = 0.0
	growth_finished = false
	overflow_levels = 0
	_reset_run_stats()
	last_upgrade_choice_keys = [[], []]
	lifesteal_charge = 0.0
	wave_director.planters_alive = 0
	wave_director.checked_planter_cells.clear()
	fusion_discovered = false
	# Both treasure loadouts are empty here, so this zeroes every shared effect
	# and puts back only what permanent progression contributes.
	_recompute_team_effects()
	field_items.clear_all()
	bursts.clear_all()
	particles.clear_all()
	flight_field.clear_all()
	showcase_queue.clear()
	cinematic_active = false
	cinematic_continuation = Callable()
	lobby_active = false
	lobby_overlay.visible = false
	get_tree().paused = false
	feedback.play_music("field")
	# Controls already appear on the lobby and character-select screens;
	# repeating them under the play field forever is noise.
	help_label.visible = false
	# Derived from the schedule rather than written out, which is how it came to
	# still say 02:00 after the boss moved to five minutes.
	_show_message(tr("옥상 보스 %d명 격파    총 %02d:%02d") % [
		WaveDirectorScript.BOSS_COUNT, int(RUN_LENGTH) / 60, int(RUN_LENGTH) % 60
	], Color("80ed99"))
	# Send only after characters, permanent bonuses and the chain length have
	# been applied, so the client mirrors the host-authoritative build.
	if online != null:
		online.send_run_start()


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
		_show_message("황금 목줄 해제", Color("8ecae6"))
		feedback.play_cue("warning")


func chain_warded() -> bool:
	return chain_ward_remaining > 0.0


func world_stopped() -> bool:
	return time_stop_remaining > 0.0


## The three timed field windows. Each one announces its own end, because a
## window whose expiry is invisible is a window players cannot plan around.
## Hands the veil every window that is currently open. Assembled here rather
## than read out of main by the veil itself, so the one place that knows what a
## timed item is is also the one place that says what it looks like.
func _refresh_item_state_veil() -> void:
	if not is_instance_valid(item_state_veil):
		return
	var windows: Dictionary = {}
	if time_stop_remaining > 0.0:
		windows["time_stop"] = [time_stop_remaining, TIME_STOP_DURATION]
	if frenzy_remaining > 0.0:
		windows["frenzy"] = [frenzy_remaining, FRENZY_DURATION]
	if guard_remaining > 0.0:
		windows["guard"] = [guard_remaining, GUARD_DURATION]
	if chain_ward_remaining > 0.0:
		windows["chain_ward"] = [chain_ward_remaining, CHAIN_WARD_DURATION]
	item_state_veil.refresh(windows)


func _update_timed_items(delta: float) -> void:
	if guard_remaining > 0.0:
		guard_remaining = maxf(0.0, guard_remaining - delta)
		# Re-asserted every tick against the *remaining* window rather than set
		# once at pickup. The invulnerability timer is shared with everything
		# else that grants a moment of it — a revive sets 1.5s, a hit sets 0.55s
		# — so anything that touched it mid-window would otherwise quietly cut
		# the window short. The window is the authority.
		for player in players:
			if not player.downed:
				player.invulnerability = maxf(player.invulnerability, guard_remaining)
		if guard_remaining <= 0.0:
			_show_message("아홉 목숨 방울 해제", Color("8ecae6"))
	if frenzy_remaining > 0.0:
		frenzy_remaining = maxf(0.0, frenzy_remaining - delta)
		if frenzy_remaining <= 0.0:
			for player in players:
				player.field_move_multiplier = 1.0
			_show_message("광란 진정", Color("8ecae6"))
	if time_stop_remaining > 0.0:
		time_stop_remaining = maxf(0.0, time_stop_remaining - delta)
		# The freeze flag itself is written by _step_enemy_shots, which is the
		# one place that walks this list.
		if time_stop_remaining <= 0.0:
			_show_message("시간이 다시 흐릅니다", Color("c77dff"))
			feedback.play_cue("warning")


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
			feedback.play_cue("chain_repaired")
			_show_message("사슬 복구 — 과충전을 다시 쓸 수 있습니다", Color("80ed99"))


func _trigger_chain_overload() -> void:
	chain_overloaded = true
	run_stats["overloads"] = int(run_stats["overloads"]) + 1
	for player in players:
		player.hurt(CHAIN_OVERLOAD_DAMAGE, Vector2.INF, false)
	camera_shake = maxf(camera_shake, 14.0)
	feedback.play_cue("chain_overload")
	_show_message("사슬 과부하    서로 가까이!", Color("ff5d8f"))


func _update_chain_visual() -> void:
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
	# Teach the risk and the recovery on their first real use. This visual update
	# runs on both the host and the remote client, so each player sees the cue.
	if not (level_up_active or resonance_vote_active or pause_active or cinematic_active or game_over) and not chain_warded():
		if chain_tutorial_stage == 0 and stage >= 2 and not chain_overloaded:
			chain_tutorial_stage = 1
			_show_message(tr("사슬 과충전  공격 +25% · 내구도 감소"), Color("fff275"))
		elif chain_tutorial_stage == 1 and stage == 3:
			chain_tutorial_stage = 2
			_show_message(tr("붙어서 사슬 내구도를 회복하세요"), Color("80ed99"))
	# The visible leash, its running light and the weapon hit path all come from
	# one sampled rope. A slack tether therefore bows toward the viewer, settles
	# close to the roof, and attacks exactly where the player sees it lying.
	chain_arc.set_state(players[0].position, players[1].position, chain_color,
		chain_max_length, chain_overloaded, chain_warded())
	chain_flow.position = chain_arc.position
	chain_flow.curve = chain_arc.local_points()
	chain_flow.set_state(
		RooftopSpace.raised(players[0].position, RooftopSpace.CHAIN_ANCHOR) - chain_arc.position,
		RooftopSpace.raised(players[1].position, RooftopSpace.CHAIN_ANCHOR) - chain_arc.position,
		chain_color, stage, chain_warded(), chain_overloaded)
	weapon_controller.chain_path = chain_arc.ground_points()
	weapon_controller.chain_visual_path = chain_arc.drawn_points()
	# Only entering the final tension band produces a leash cue.
	feedback.play_chain_limit(stage, previous_chain_stage)
	if stage == 3 and previous_chain_stage < 3:
		camera_shake = maxf(camera_shake, 4.0)
	previous_chain_stage = stage


## An elite or the boss can be off screen while it closes in; a partner
## cannot, because the chain caps the pair at a fraction of a screen. So one
## indicator, pointed at whichever heavy enemy is nearest and outside the
## view, clamped to the screen edge along that bearing.
func _update_threat_indicator() -> void:
	var view := rooftop_view.view_size
	var centre := world_camera.position
	var nearest: ChaserEnemy = null
	var nearest_distance := 0.0
	# Only elites and bosses can be pointed at, so only they are walked: the whole
	# crowd used to be scanned every tick to find the handful that qualify.
	for index in range(heavy_enemies.size() - 1, -1, -1):
		var enemy := heavy_enemies[index]
		if not is_instance_valid(enemy) or enemy.dead or not enemy.active or not (enemy.elite or enemy.boss):
			heavy_enemies.remove_at(index)
			continue
		var offset := rooftop_view.project_offset((enemy.global_position - centre) * world_camera.zoom)
		if absf(offset.x) < view.x * 0.5 - 40.0 and absf(offset.y) < view.y * 0.5 - 40.0:
			continue
		var distance := offset.length()
		if nearest == null or distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest == null:
		threat_edge_indicator.visible = false
		return
	# Nearness drives the arrow's size and the pill's glow, so "it is nearly on
	# us" lands before the number is read. Measured against half the view, which
	# is roughly the distance at which something off screen becomes urgent.
	var nearness := 1.0 - clampf(nearest_distance / maxf(1.0, view.length()), 0.0, 1.0)
	threat_edge_indicator.report(
		"%s %dm" % ["보스" if nearest.boss else "정예", int(nearest_distance / 10.0)],
		_edge_bearing(nearest.global_position, centre), nearness,
		Color("fff275") if nearest.boss else Color("ff5d8f"), nearest.boss)
	_place_edge_indicator(threat_edge_indicator, nearest.global_position, view, centre)
	threat_edge_indicator.visible = true


## Gold rather than the threat pointer's pink, because the two share an edge and
## a screen: one of them is something to run from.
const CHEST_POINTER_COLOR := Color("ffd166")
## Under this much life left, the pointer says how long the drop has instead of
## only where it is — a box that expires while the pair is crossing to it is the
## one way this pointer can make the run worse.
const ITEM_POINTER_CLOCK := 9.0


## The drop pointer. Same rule as the threat pointer — only what is off screen is
## pointed at, because a box the pair can already see needs no arrow — and the
## same edge placement, so the two read as one family of marks rather than as two
## unrelated HUD pieces.
func _update_item_indicator() -> void:
	var view := rooftop_view.view_size
	var centre := world_camera.position
	var nearest: FieldItem = null
	var nearest_distance := 0.0
	for candidate in field_items.active_items:
		var item := candidate as FieldItem
		if not is_instance_valid(item) or not item.active:
			continue
		var offset := rooftop_view.project_offset((item.global_position - centre) * world_camera.zoom)
		if absf(offset.x) < view.x * 0.5 - 40.0 and absf(offset.y) < view.y * 0.5 - 40.0:
			continue
		var distance := offset.length()
		# A chest outranks every other drop at any distance: it is the one that
		# hands out cards, and the pair should never trade it for a tuna tin
		# that happened to land closer.
		var better := nearest == null
		if not better and item.item_id == "chest" and nearest.item_id != "chest":
			better = true
		elif not better and (item.item_id == "chest") == (nearest.item_id == "chest"):
			better = distance < nearest_distance
		if better:
			nearest = item
			nearest_distance = distance
	if nearest == null:
		item_edge_indicator.visible = false
		return
	var item_label := tr("상자") if nearest.item_id == "chest" else tr(field_items.item_display_name(nearest.item_id))
	var expiring: bool = nearest.lifetime <= ITEM_POINTER_CLOCK
	var mark := tr("%s %dm %d초") % [item_label, int(nearest_distance / 10.0), ceili(nearest.lifetime)] 		if expiring else tr("%s %dm") % [item_label, int(nearest_distance / 10.0)]
	var item_nearness := 1.0 - clampf(nearest_distance / maxf(1.0, view.length()), 0.0, 1.0)
	item_edge_indicator.report(mark, _edge_bearing(nearest.global_position, centre),
		item_nearness, field_items.item_color(nearest.item_id),
		nearest.lifetime <= FieldItem.FADE_WARNING)
	_place_edge_indicator(item_edge_indicator, nearest.global_position, view, centre)
	# Both pointers clamp to the same edge along their own bearing, so a chest
	# and an elite in roughly the same direction land on top of each other. The
	# drop is the one that moves: the threat mark is the one being read in a
	# hurry.
	if threat_edge_indicator.visible:
		var gap := item_edge_indicator.position - threat_edge_indicator.position
		if absf(gap.x) < item_edge_indicator.size.x and absf(gap.y) < item_edge_indicator.size.y:
			var below := threat_edge_indicator.position.y + item_edge_indicator.size.y + 6.0
			if below + item_edge_indicator.size.y > view.y - 40.0:
				below = threat_edge_indicator.position.y - item_edge_indicator.size.y - 6.0
			item_edge_indicator.position.y = below
	item_edge_indicator.visible = true


## Which way the mark points, in screen space.
func _edge_bearing(at: Vector2, centre: Vector2) -> Vector2:
	var direction := rooftop_view.project_offset((at - centre) * world_camera.zoom)
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT


## Puts `pointer` on the screen edge along the bearing to `at`, inset far enough
## that the mark — and the arrowhead outside it — is never half off screen.
func _place_edge_indicator(pointer: Control, at: Vector2, view: Vector2, centre: Vector2) -> void:
	var direction := _edge_bearing(at, centre)
	var half := view * 0.5 - Vector2(96.0, 118.0)
	var reach := minf(half.x / maxf(0.001, absf(direction.x)), half.y / maxf(0.001, absf(direction.y)))
	pointer.position = view * 0.5 + direction * reach - pointer.size * 0.5


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
	# Anything that places the camera outright — a run starting, a test walking
	# the pair to the far side of the roof — writes world_camera.position. The
	# value this function last wrote is remembered, so a position that is no
	# longer that value belongs to somebody else and becomes the new truth.
	if not world_camera.position.is_equal_approx(camera_written):
		camera_focus = world_camera.position
	# The follow is tracked unrounded and only the camera is snapped. Rounding
	# the tracked value instead would let a slow follow round its own step back
	# to zero every frame and stall the camera short of the pair.
	camera_focus = camera_focus.lerp(midpoint, minf(1.0, delta * 8.0))
	camera_written = rooftop_view.snap_to_source_texels(camera_focus + shake_offset, world_camera.zoom)
	world_camera.position = camera_written
	# The rooftop follows the view rather than existing as a fixed slab, so
	# there is no edge to reach however far the pair kites.
	var coverage := rooftop_view.view_size * EndlessRooftopView.OVERSCAN * 0.5 / world_camera.zoom
	arena_floor.follow(world_camera.position, maxf(coverage.x, coverage.y) + ArenaFloor.REDRAW_STEP)
	rooftop_props.follow(world_camera.position)
	rooftop_props.update_visibility(players, delta)


## A wave only reads as a wave if it is announced. The surge waves get their
## own wording and a heavier cue so the difference is audible as well as
## visible before the enemies actually arrive.
func _on_wave_started(wave_index: int, is_surge: bool) -> void:
	if is_surge:
		_show_message(tr("%d파 대공세    서로 등을 맡으세요!") % (wave_index + 1), Color("ff5d8f"))
		feedback.play_cue("warning")
		camera_shake = maxf(camera_shake, 7.0)
	else:
		_show_message(tr("%d파 시작    발을 맞춰 포위를 뚫으세요") % (wave_index + 1), Color("fff275"))
		feedback.play_cue("kill")


func _on_wave_calm_started(_wave_index: int) -> void:
	_show_message("공세 종료    잠시 숨을 고르세요", Color("80ed99"))


func _register_enemy(enemy: ChaserEnemy) -> void:
	# WaveDirector owns pooling, while WorldStage owns presentation. Reparenting
	# keeps the same global ground point and lets every live body participate in
	# the same front-to-back order as the survivors and roof furniture.
	if enemy.get_parent() != world_stage:
		enemy.reparent(world_stage, true)
	enemy.z_index = 0
	# setup() runs before the director assigns the final spawn point. Aim the
	# freshly placed body at the pair now, so enemies on the right side of the
	# ring do not spend their first (possibly AI-staggered) frames looking away.
	if not enemy.scenery:
		enemy.face_toward((players[0].position + players[1].position) * 0.5)
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.ranged_attack.is_connected(_on_enemy_ranged_attack):
		enemy.ranged_attack.connect(_on_enemy_ranged_attack)
	if not enemy.damage_taken.is_connected(_on_enemy_damaged):
		enemy.damage_taken.connect(_on_enemy_damaged)
	if not enemy.chain_slam.is_connected(_on_boss_chain_slam):
		enemy.chain_slam.connect(_on_boss_chain_slam)
	if not enemy.attack_warning.is_connected(_on_boss_attack_warning):
		enemy.attack_warning.connect(_on_boss_attack_warning)
	if not enemy.enraged.is_connected(_on_boss_enraged):
		enemy.enraged.connect(_on_boss_enraged)
	if enemy not in enemies:
		enemies.append(enemy)
	if (enemy.elite or enemy.boss) and enemy not in heavy_enemies:
		heavy_enemies.append(enemy)
	if enemy.boss:
		boss_enemy = enemy
		boss_bar.reset(boss_name(enemy.boss_rank), enemy.boss_rank,
			WaveDirectorScript.BOSS_COUNT, enemy.max_health)
		boss_bar.visible = true
		# The bar paints the name and the rank pips itself; the label stays for
		# the callers that still read its text.
		boss_label.visible = false
		boss_label.text = "%s   %d/%d" % [
			boss_name(enemy.boss_rank), enemy.boss_rank, WaveDirectorScript.BOSS_COUNT
		]
		boss_health_text_label.text = "%d / %d" % [int(ceil(enemy.health)), int(ceil(enemy.max_health))]
		# The bar prints the number itself, above the fill rather than across it.
		# This label stays as a hidden stub because the online snapshot and two
		# tests still read its text.
		boss_health_text_label.visible = false
		_show_message(tr("%s 출현    철벽 포위   %d / %d") % [
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
	"폭주 청소 로봇", "밤사냥꾼 부엉왕", "옥상 관리자", "폭풍 부엉왕", "최종 관제 코어",
]


func boss_name(rank: int) -> String:
	return tr(String(BOSS_NAMES[clampi(rank - 1, 0, BOSS_NAMES.size() - 1)]))


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
	var projectile := _acquire_enemy_shot()
	projectile.setup(origin, direction, damage, players)
	enemy_shots.append(projectile)
	if online != null:
		online.send_enemy_shot(origin, direction, projectile.speed)


## Hostile shots are pooled like the friendly ones. A late field is a few hundred
## in the air at once with a steady turnover, and every one of them used to be a
## node built and thrown away.
func _acquire_enemy_shot() -> EnemyProjectile:
	if not enemy_shot_pool.is_empty():
		var reused: EnemyProjectile = enemy_shot_pool.pop_back()
		reused.pooled = false
		return reused
	var projectile := EnemyProjectileScript.new() as EnemyProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.broken.connect(_on_enemy_shot_broken)
	projectile.released.connect(_on_enemy_shot_released)
	rooftop_view.world.add_child(projectile)
	return projectile


func _on_enemy_shot_released(shot: EnemyProjectile) -> void:
	if shot.pooled:
		return
	shot.pooled = true
	enemy_shot_pool.append(shot)


## One tick for every hostile shot in the air, and the only thing that prunes
## `enemy_shots`.
##
## The list used to be swept only inside the time-stop branch, which is to say
## almost never: a shot that timed out or hit somebody freed its node and left a
## dead reference behind, and over a full run that list grew without bound.
## CrowdRenderer walks it every rendered frame and the AI companion walks it
## every tick, so the cost of a run's accumulated misses was paid twice a frame,
## forever.
func _step_enemy_shots(delta: float) -> void:
	var frozen := time_stop_remaining > 0.0
	for index in range(enemy_shots.size() - 1, -1, -1):
		var candidate: Variant = enemy_shots[index]
		var shot := candidate as EnemyProjectile if is_instance_valid(candidate) else null
		var finished := shot == null
		if not finished:
			shot.frozen = frozen
			finished = shot.step(delta)
		if finished:
			# Swap-remove: walking backwards means the entry pulled in from the
			# end has already been stepped this tick.
			enemy_shots[index] = enemy_shots[enemy_shots.size() - 1]
			enemy_shots.pop_back()


func _on_player_attack_visual(player_index: int, weapon_id: String,
		origin: Vector2, color: Color, radius: float) -> void:
	if online != null:
		online.send_player_attack(player_index, weapon_id, origin, color, radius)


## A shot knocked out of the air by 월식 낫, 결속 파동, 궤도 파편 or 지뢰 결계.
## It gets its own spark and its own note: a shot that simply stopped existing
## would read as the weapon having missed it rather than having answered it.
func _on_enemy_shot_broken(at: Vector2) -> void:
	particles.emit_sparks(at, Color("ffd166"), 5, 190.0)
	feedback.report_hit()


## The boss's Chain Slam always drains chain integrity directly — it is
## targeting the bond itself, not the survivors — and additionally hurts
## anyone still standing inside the telegraphed impact radius when it lands.
## The boss crossing half health changes how the fight is played, so it gets
## an announcement of its own rather than passing silently.
func _on_boss_attack_warning(origin: Vector2) -> void:
	feedback.play_cue_at("danger", origin)


func _on_boss_enraged(_enemy: ChaserEnemy) -> void:
	feedback.play_cue_at("boss_enrage", _enemy.global_position)
	feedback.play_music("boss_enraged")
	weapon_controller.play_boss_flare(_enemy.global_position, true)
	camera_shake = maxf(camera_shake, 12.0)
	_show_message("청소 로봇 폭주    속도 증가", Color("ff5d8f"))


func _on_boss_chain_slam(impact_point: Vector2, damage: float, radius: float) -> void:
	var hit_someone := false
	for player in players:
		if impact_point.distance_to(player.global_position) <= radius + player.radius:
			hit_someone = player.hurt(damage) or hit_someone
	chain_integrity = maxf(0.0, chain_integrity - BOSS_SLAM_INTEGRITY_DRAIN)
	camera_shake = maxf(camera_shake, 13.0)
	feedback.play_cue("warning")
	_show_message("사슬 강타    내구도 주의" if hit_someone else "충격 회피    내구도 주의", Color("ff5d8f"))


func _on_enemy_damaged(enemy: ChaserEnemy, amount: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_on_enemy_damaged(enemy, amount)
	FrameProbe.add(&"hit_feedback (incl)", probe_started)


func _probed_on_enemy_damaged(enemy: ChaserEnemy, amount: float) -> void:
	feedback.show_damage(enemy.global_position, amount, Color("fff4cf"))
	# Sparks scale with the hit rather than being constant, so a chip and a
	# critical do not look identical, and a screenful of swarm hits does not
	# spend the whole particle budget on chip damage.
	particles.emit_sparks(enemy.global_position, Color("fff4cf"), 2 if amount < 40.0 else 5, 150.0 + amount)
	# The weapon that landed the blow picks the impact sound, so a lightning
	# tick and a scythe sweep are different events to the ear as well as to the
	# eye. Reported rather than played: an area weapon can land dozens of these
	# in one tick and they are flushed together — see FeedbackSystem.report_hit.
	feedback.report_hit(enemy.last_damage_weapon)
	_record_combat_damage(enemy.last_damage_player, enemy.last_damage_weapon, amount)
	if not enemy.scenery:
		_apply_lifesteal(amount)


func _lifesteal_tiers() -> float:
	return team_lifesteal / LIFESTEAL_PER_TIER


func _refill_lifesteal(delta: float) -> void:
	if team_lifesteal <= 0.0:
		lifesteal_charge = 0.0
		return
	var tiers := _lifesteal_tiers()
	var cap := tiers * LIFESTEAL_BURST_CAP_PER_TIER
	lifesteal_charge = minf(cap,
		lifesteal_charge + tiers * LIFESTEAL_REFILL_PER_SECOND_PER_TIER * delta)


func _apply_lifesteal(actual_damage: float) -> void:
	if team_lifesteal <= 0.0 or lifesteal_charge <= 0.0 or actual_damage <= 0.0:
		return
	var wounded: Array[ChainPlayer] = []
	for player in players:
		if not player.downed and player.health < player.max_health:
			wounded.append(player)
	if wounded.is_empty():
		return
	var healing := minf(lifesteal_charge, actual_damage * team_lifesteal)
	lifesteal_charge -= healing
	var each := healing / float(wounded.size())
	for player in wounded:
		player.heal(each)


func _on_player_damaged(player: ChainPlayer, amount: float) -> void:
	feedback.show_damage(player.global_position, amount, Color("ff8fab"))
	feedback.play_cue_at("hurt", player.global_position)
	camera_shake = maxf(camera_shake, 7.0)
	Input.start_joy_vibration(player.player_index - 1, 0.25, 0.55, 0.16)


func _on_player_downed(player: ChainPlayer) -> void:
	feedback.play_cue_at("down", player.global_position)
	camera_shake = 12.0
	_show_message(tr("%s 다운 — 18초 안에 가까이 머물러 구조하세요!") % player.character_name, Color("ff5d8f"))


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
	_show_message(tr("%s의 아홉 목숨!") % player.character_name, Color("fff275"))


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
	var revived_index := players.find(player)
	if revived_index >= 0:
		var rescuer_index := 1 - revived_index
		run_stats["revives_by_player"][rescuer_index] = int(run_stats["revives_by_player"][rescuer_index]) + 1
		_award_contribution(rescuer_index, CONTRIBUTION_REVIVE)
	feedback.play_cue_at("revive", player.global_position)
	_show_message(tr("%s 부활 — 사슬이 다시 이어집니다") % player.character_name, Color("80ed99"))


func _set_pause(enabled: bool, replicate := true) -> void:
	pause_active = enabled
	restart_pending = false
	pending_quits = false
	pause_cursor = 0
	pause_settings = false
	pause_overlay.visible = enabled
	if enabled:
		modal_dim.visible = true
		if not modal_dim.veil_only:
			modal_dim.veil_only = true
			modal_dim.queue_redraw()
	elif not (title_active or lobby_active or character_select_active or level_up_active or game_over or cinematic_active):
		modal_dim.visible = false
	if enabled:
		for notice in notice_stack:
			if is_instance_valid(notice):
				notice.visible = false
	combat_hud.visible = not enabled and not game_over and not resonance_vote_active and not title_active and not lobby_active and not character_select_active
	if enabled:
		_update_pause_text()
	get_tree().paused = enabled
	if replicate and online != null:
		online.send_pause_state(enabled)


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
	elif Input.is_action_just_pressed("menu_left") or Input.is_action_just_pressed("menu_right"):
		var direction := -1 if Input.is_action_just_pressed("menu_left") else 1
		var setting_index: int = _pause_setting_index(pause_cursor) if pause_settings else -1
		if setting_index >= 0:
			_change_setting(setting_index, direction, false)
		else:
			pause_cursor = ReviewUI.pause_neighbor(
				pause_cursor, "left" if direction < 0 else "right", pause_settings)
		_update_pause_text()
	elif Input.is_action_just_pressed("menu_previous") or Input.is_action_just_pressed("menu_next"):
		pause_cursor = ReviewUI.pause_neighbor(
			pause_cursor, "down" if Input.is_action_just_pressed("menu_next") else "up", pause_settings)
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
		_step_sound_volume()
		_persist_settings()
		_update_pause_text()
	elif Input.is_action_just_pressed("toggle_music"):
		_step_music_volume()
		_persist_settings()
		_update_pause_text()


func window_size() -> Vector2i:
	return WINDOW_SIZES[clampi(settings.window_size_index, 0, WINDOW_SIZES.size() - 1)]


func window_size_label() -> String:
	var requested := window_size()
	if applied_window_size != Vector2i.ZERO and applied_window_size != requested:
		return tr("%d × %d    화면에 맞춤") % [applied_window_size.x, applied_window_size.y]
	return "%d × %d" % [requested.x, requested.y]


func monitor_refresh_rate() -> int:
	if DisplayServer.get_name() == "headless":
		return 60
	var refresh := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	return 60 if refresh < 1.0 else maxi(1, roundi(refresh))


func frame_rate_label() -> String:
	match settings.frame_rate_limit:
		0: return tr("모니터 %d Hz") % monitor_refresh_rate()
		-1: return tr("제한 없음")
		_: return "%d FPS" % settings.frame_rate_limit


func display_mode_label() -> String:
	return tr("전체 화면") if settings.fullscreen_enabled else tr("창 모드")


func language_label() -> String:
	return "English" if settings.language == "en" else "한국어"


func settings_description(index: int) -> String:
	match index:
		0:
			return tr("기본은 창 모드입니다. F11 또는 Alt+Enter로도 언제든 전환할 수 있습니다.")
		1:
			return tr("창 모드 크기를 고릅니다. 전체 화면에서는 모니터의 기본 해상도를 사용합니다.")
		2:
			return tr("렌더링 프레임을 제한합니다. 현재 모니터는 약 %d Hz로 감지되었습니다.") % monitor_refresh_rate()
		3:
			return tr("화면 찢어짐을 줄입니다. 켜면 모니터 주사율이 프레임 상한보다 우선합니다.")
		4:
			return tr("메뉴와 설명의 작은 글자를 키웁니다.")
		5:
			return tr("피격과 강한 공격에서 발생하는 카메라 흔들림을 조절합니다.")
		6:
			return tr("적에게 준 피해 수치를 전투 화면에 표시합니다.")
		7:
			return tr("효과음 음량을 25% 단위로 조절합니다.")
		8:
			return tr("음악 음량을 25% 단위로 조절합니다.")
		9:
			return tr("화면에 표시할 언어를 고릅니다. 변경 내용은 즉시 적용됩니다.")
		_: return tr("Enter / A로 변경하고 Esc / B로 메인 메뉴로 돌아갑니다.")


## Full screen, whichever of the two full-screen modes the platform gave us.
func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN 		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Shrinks a window down to `room`, keeping 16:9 so the stretch never has to
## letterbox what the desktop could have shown.
static func fit_window_size(requested: Vector2i, room: Vector2i) -> Vector2i:
	if requested.x <= room.x and requested.y <= room.y:
		return requested
	var height := mini(room.y, room.x * 9 / 16)
	# Rounded to a whole multiple of nine so the result is 16:9 to the pixel.
	# Three pixels of height are cheaper than the one-pixel letterbox the stretch
	# would otherwise put along the top of every screen.
	height = (height / 9) * 9
	# Small enough to be unplayable is worse than a window running off the edge,
	# so the floor is half the authored canvas.
	height = maxi(height, 360)
	return Vector2i(height * 16 / 9, height)


## Places the windowed-mode window: framed, sized to something the desktop can
## actually show, and centred on the screen.
##
## Two things used to go wrong here and they were the same thing. A 1920x1080
## client area does not fit a 1080p desktop once the window manager has added a
## title bar, so the old code dropped the frame and let the window cover the
## whole desktop instead — and then never moved it. Its client origin stayed
## where the *framed* window's outer corner had been, measured at (1912, -31) on
## a 1080p desktop, so the picture and the pointer disagreed by the height of a
## title bar and every button had to be clicked a little below itself. And a
## borderless window the exact size of the desktop is indistinguishable from
## full screen, so turning 전체화면 off appeared to do nothing at all.
##
## So the window keeps its frame, the size is clamped to what the desktop's
## usable area can hold, and the position is always set rather than inherited.
## Filling the screen is what 전체화면 is for, and it is now the only thing that
## does it.
func _apply_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var screen := DisplayServer.window_get_current_screen()
	# The usable rect, not the screen: a taskbar is as much in the way as a
	# title bar, and on a multi-monitor desktop its origin is not (0, 0).
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var requested := window_size()
	DisplayServer.window_set_size(requested)
	# Measured rather than assumed: the frame is the window manager's number,
	# and it is zero on the platforms that do not draw one.
	var frame := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	applied_window_size = fit_window_size(requested, usable.size - frame)
	if applied_window_size != requested:
		DisplayServer.window_set_size(applied_window_size)
	# `window_set_position` places the client area, so the frame hanging above
	# and around it has to be paid for out of the centring rather than ignored.
	var inset := DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()
	DisplayServer.window_set_position(
		usable.position + (usable.size - applied_window_size - frame) / 2 + inset)


func _apply_display_settings() -> void:
	_apply_refresh_rate()
	_set_fullscreen(settings.fullscreen_enabled)


func _apply_refresh_rate() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.vsync_enabled else DisplayServer.VSYNC_DISABLED)
	if settings.frame_rate_limit < 0:
		Engine.max_fps = 0
	elif settings.frame_rate_limit == 0:
		# With V-Sync the display server owns the cap. Without it, match the
		# detected monitor rate so "monitor" keeps the same meaning.
		Engine.max_fps = 0 if settings.vsync_enabled else monitor_refresh_rate()
	else:
		Engine.max_fps = settings.frame_rate_limit


func _step_frame_rate(direction := 1, wrap_choice := true) -> void:
	var limits: Array = SettingsScript.FRAME_RATE_LIMITS
	var current := limits.find(settings.frame_rate_limit)
	var next := (wrapi(current + direction, 0, limits.size()) if wrap_choice
		else clampi(current + direction, 0, limits.size() - 1))
	settings.frame_rate_limit = int(limits[next])
	_apply_refresh_rate()


## The one place the window mode changes. It takes what the player asked for
## rather than flipping whatever the window happens to be, so the settings row,
## F11 and Alt+Enter cannot drift out of step with each other.
func _set_fullscreen(on: bool) -> void:
	# Keep the requested value authoritative. Querying the OS immediately after
	# a mode switch can return the previous mode for one frame and used to save
	# that stale value over the player''s choice.
	settings.fullscreen_enabled = on
	if DisplayServer.get_name() == "headless":
		return
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_finish_windowed_mode()
		# Full screen forces borderless on. Some window managers apply that
		# transition at the end of the frame, so restore the frame and size once
		# more after the mode change has settled.
		call_deferred("_finish_windowed_mode")


func _finish_windowed_mode() -> void:
	if DisplayServer.get_name() == "headless" or settings.fullscreen_enabled:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	_apply_window_size()


func _toggle_fullscreen() -> void:
	_set_fullscreen(not settings.fullscreen_enabled)


func _persist_settings() -> void:
	settings.screen_shake_enabled = screen_shake_enabled
	settings.damage_numbers_enabled = feedback.damage_numbers_enabled
	settings.sound_enabled = feedback.sound_enabled
	settings.music_enabled = feedback.music_enabled
	settings.sound_volume = feedback.sound_volume
	settings.music_volume = feedback.music_volume
	settings.save_settings()


func _volume_step(value: float, direction := 1, wrap_choice := true) -> float:
	var nearest := 0
	for index in VOLUME_STEPS.size():
		if absf(float(VOLUME_STEPS[index]) - value) < absf(float(VOLUME_STEPS[nearest]) - value):
			nearest = index
	var next := (wrapi(nearest + direction, 0, VOLUME_STEPS.size()) if wrap_choice
		else clampi(nearest + direction, 0, VOLUME_STEPS.size() - 1))
	return float(VOLUME_STEPS[next])


func _step_sound_volume(direction := 1, wrap_choice := true) -> void:
	feedback.sound_volume = _volume_step(feedback.sound_volume, direction, wrap_choice)
	feedback.sound_enabled = feedback.sound_volume > 0.0
	feedback.refresh_sound()


func _step_music_volume(direction := 1, wrap_choice := true) -> void:
	feedback.music_volume = _volume_step(feedback.music_volume, direction, wrap_choice)
	feedback.music_enabled = feedback.music_volume > 0.0
	feedback.refresh_music()


## Applies one settings-page value immediately. Enter/click cycles choices,
## while left/right stops at each end and gives booleans a clear off/on side.
func _change_setting(index: int, direction: int, wrap_choice: bool) -> void:
	match index:
		0:
			_set_fullscreen(not settings.fullscreen_enabled if wrap_choice else direction > 0)
		1:
			var next := settings.window_size_index + direction
			settings.window_size_index = (wrapi(next, 0, WINDOW_SIZES.size()) if wrap_choice
				else clampi(next, 0, WINDOW_SIZES.size() - 1))
			if not settings.fullscreen_enabled:
				_apply_window_size()
		2:
			_step_frame_rate(direction, wrap_choice)
		3:
			settings.vsync_enabled = (not settings.vsync_enabled if wrap_choice else direction > 0)
			_apply_refresh_rate()
		4:
			settings.large_text_enabled = (not settings.large_text_enabled if wrap_choice else direction > 0)
			_apply_accessibility_text_scale()
		5:
			screen_shake_enabled = (not screen_shake_enabled if wrap_choice else direction > 0)
		6:
			feedback.damage_numbers_enabled = (
				not feedback.damage_numbers_enabled if wrap_choice else direction > 0)
		7:
			_step_sound_volume(direction, wrap_choice)
		8:
			_step_music_volume(direction, wrap_choice)
		9:
			var languages: Array = SettingsScript.LANGUAGES
			var current := languages.find(settings.language)
			var next := (wrapi(current + direction, 0, languages.size()) if wrap_choice
				else clampi(current + direction, 0, languages.size() - 1))
			settings.language = String(languages[next])
			TranslationServer.set_locale(settings.language)
		_:
			return
	_persist_settings()
	# Played after the value changes, so sound-volume adjustments preview the
	# new level rather than the old one.
	feedback.play_cue("select")


func _update_pause_text() -> void:
	EditorialUI.refresh_pause(self)
	ReviewUI.refresh_pause(self)
	_apply_text_scale_to(pause_overlay, 1.14 if settings.large_text_enabled else 1.0)


func _pause_setting_index(index: int) -> int:
	return int({
		9: 0, 10: 1, 11: 2, 12: 3,
		8: 4, 1: 5, 2: 6, 3: 7, 4: 8, 13: 9,
	}.get(index, -1))


func _activate_pause_item(index: int) -> void:
	if not pause_active:
		return
	if restart_pending:
		if index == 0:
			restart_pending = false
			_update_pause_text()
		elif index == 1 and Time.get_ticks_msec() >= restart_armed_at:
			get_tree().paused = false
			if pending_quits:
				get_tree().quit()
			else:
				get_tree().reload_current_scene()
		return
	var setting_index: int = _pause_setting_index(index)
	if setting_index >= 0:
		_change_setting(setting_index, 1, true)
		_update_pause_text()
		return
	match index:
		0:
			if online != null and online.is_client():
				online.request_pause(false)
			else:
				_set_pause(false)
			return
		7:
			pause_settings = not pause_settings
			pause_cursor = 7
		5, 6:
			# Both of these throw the run away, so both ask first, and both open on
			# cancel. The arming delay is what stops a double click on the entry
			# itself from landing on the confirmation underneath it.
			restart_pending = true
			pending_quits = index == 6
			pause_cursor = 0
			restart_armed_at = Time.get_ticks_msec() + 400
	_update_pause_text()


## Fires every weapon a player owns once — used by the physics loop's
## per-weapon cooldown check above (one call per ready weapon) and reused by
## tests that want to trigger "this player attacks now" without waiting out
## real cooldowns.
func _perform_character_attack(player_index: int) -> void:
	for weapon_slot in weapon_loadouts[player_index].size():
		weapon_controller.perform_attack(player_index, weapon_slot, _tension_damage_multiplier())


## Stops bodies standing inside each other. The pass lives with the grid it
## walks — see EnemySpatialGrid.separate — and runs on the arrays the grid was
## rebuilt from this tick.
func _separate_crowd() -> void:
	spatial_grid.view_rect = crowd_renderer.view_rect.grow(CrowdRendererScript.CULL_MARGIN) if is_instance_valid(crowd_renderer) else Rect2(-1e9, -1e9, 2e9, 2e9)
	spatial_grid.separate(players)


## The same push for one explicit pair of nodes, for callers holding two bodies
## rather than a rebuilt grid. Weighted by size so a mouse bounces off a
## bulwark rather than moving it; a boss is immovable.
func _resolve_overlap(first: ChaserEnemy, second: ChaserEnemy) -> void:
	if not is_instance_valid(first) or not is_instance_valid(second) or first.dead or second.dead:
		return
	if first.scenery or second.scenery:
		return
	if first.immovable and second.immovable:
		return
	var offset := second.position - first.position
	var minimum := (first.radius + second.radius) * EnemySpatialGrid.CROWD_OVERLAP_SLACK
	var distance_squared := offset.length_squared()
	if distance_squared >= minimum * minimum:
		return
	var distance := sqrt(distance_squared)
	var direction := offset / distance if distance > 0.01 else Vector2.from_angle(randf() * TAU)
	var push := (minimum - distance) * EnemySpatialGrid.CROWD_PUSH
	var first_share := 0.0 if first.immovable else (1.0 if second.immovable else second.radius / (first.radius + second.radius))
	var second_share := 0.0 if second.immovable else (1.0 if first.immovable else first.radius / (first.radius + second.radius))
	first.position -= direction * push * first_share
	second.position += direction * push * second_share


func _update_contact_pressure() -> void:
	# Two bounded neighbourhood queries, not a neighbour scan for every enemy.
	var ramp := clampf((elapsed - 90.0) / 150.0, 0.0, 1.0)
	for player in players:
		var touching := 0
		if ramp > 0.0:
			for enemy in spatial_grid.query_radius(player.global_position, 100.0):
				if enemy.dead or enemy.scenery: continue
				var reach: float = player.radius + enemy.radius + 12.0
				if enemy.global_position.distance_squared_to(player.global_position) <= reach * reach:
					touching += 1
					if touching >= 6: break
		player.contact_pressure = 1.0 + minf(4.0, maxf(0.0, touching - 2.0)) * 0.15 * ramp


func _reclaim_spawn_capacity(count: int, center: Vector2) -> int:
	var candidates: Array[ChaserEnemy] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and not enemy.boss and not enemy.elite:
			candidates.append(enemy)
	candidates.sort_custom(func(a: ChaserEnemy, b: ChaserEnemy) -> bool:
		return a.global_position.distance_squared_to(center) > b.global_position.distance_squared_to(center))
	var reclaimed := mini(count, candidates.size())
	for index in reclaimed:
		_cull_enemy(candidates[index])
	return reclaimed


func _cull_enemy(enemy: ChaserEnemy) -> void:
	enemies.erase(enemy)
	wave_director.release_enemy(enemy)


func _on_enemy_died(enemy: ChaserEnemy) -> void:
	var death_position := enemy.global_position
	if enemy.scenery:
		_on_planter_broken(enemy, death_position)
		return
	var dropped_xp := enemy.xp_value
	var dropped_grade := enemy.xp_grade
	var defeated_boss := enemy.boss
	var was_elite := enemy.elite
	var killer_index := enemy.last_damage_player
	if was_elite or defeated_boss:
		dropped_xp = roundi(float(dropped_xp) * (1.0 + team_hunt_bonus))
	enemies.erase(enemy)
	kills += 1
	if killer_index >= 0 and killer_index < 2:
		run_stats["kills_by_player"][killer_index] = int(run_stats["kills_by_player"][killer_index]) + 1
		_award_contribution(killer_index,
			CONTRIBUTION_BOSS_KILL if defeated_boss else CONTRIBUTION_ELITE_KILL if was_elite else CONTRIBUTION_KILL)
	_drop_experience(death_position, dropped_xp, dropped_grade, was_elite or defeated_boss)
	bursts.spawn(death_position, enemy.enemy_color, 2.6 if defeated_boss else (1.7 if was_elite else 1.0))
	# Only the named kills light the roof. An ordinary body dies several times a
	# second in a late wave, and a light on each of them would fill the whole
	# budget with flickers and leave nothing for the thing that earned one.
	if defeated_boss or was_elite:
		weapon_controller._spawn_reactive_light(death_position, enemy.enemy_color.lerp(Color("fff4cf"), 0.3),
			240.0 if defeated_boss else 140.0, 0.5 if defeated_boss else 0.3,
			0.38 if defeated_boss else 0.22, 1.9)
	feedback.report_kill()
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
		var restored := 0.0
		for player in players:
			var before := player.health
			player.heal(player.max_health * 0.5)
			restored += player.health - before
		chain_integrity = CHAIN_INTEGRITY_MAX
		chain_overloaded = false
		field_items.spawn_item(death_position, "chest")
		# The first two bosses each leave a 공명핵, which is exactly the number
		# of resonance slots. "How many resonances can we have?" is therefore
		# answered by something the pair watched happen rather than by a rule.
		if enemy.boss_rank <= ResonanceSystem.MAX_ACTIVE_RESONANCES:
			_award_resonance_core()
		var field_track := "moonlight" if enemy.boss_rank % 2 == 1 else "field"
		feedback.play_music(field_track + ("_late" if enemy.boss_rank >= 2 else ""))
		feedback.play_cue("victory")
		_show_message(tr("%s 격파    남은 보스 %d    둘의 체력 +%d") % [
			boss_name(enemy.boss_rank), wave_director.bosses_remaining(), roundi(restored)
		], Color("80ed99"))
		return
	# Rolled after the boss branch on purpose: the boss carries the elite flag,
	# so rolling before it would hand out a guaranteed drop at the exact moment
	# the run ends and nobody can walk to it.
	_try_drop_field_item(death_position, was_elite)
	# Ordinary kills reward experience, never automatic healing.



## What a kill leaves on the floor: its own gem, every time.
##
## Ordinary kills used to pay into a shared bank that dropped one gem when it
## was worth collecting, because twenty thousand kills a run meant a floor
## littered with crumbs. The cost was that most of a run's kills produced
## nothing to look at — the reward for clearing a swarm pack was a number
## moving somewhere off screen. Every enemy drops now; what separates them is
## the grade of the gem, which ChaserEnemy sets from the archetype and how far
## into the run it died, so the floor reads as a spread of ranks rather than a
## uniform sprinkle.
## What a drop is worth, by the rung it landed on.
##
## The smallest is deliberately untouched: an early mouse should still be worth
## an early mouse, and the opening minutes are paced against that number. Every
## rung above it now pays much more than the one below. Late in a run the ladder
## has lifted and almost everything dying is a shard or a prism, so this is what
## keeps level-ups arriving at minute twenty instead of the curve flattening out
## the moment the experience requirement outgrows what a mote is worth.
const XP_GRADE_REWARD := [1.0, 2.0, 4.0, 8.0]


## A planter opened. It is not a kill — it does not count toward the tally, it
## pays no experience, and it cannot roll a chest — so it takes none of the death
## path below. What it does is hand over a field drop every time, which is the
## whole reason to walk over and break one.
func _on_planter_broken(enemy: ChaserEnemy, at: Vector2) -> void:
	enemies.erase(enemy)
	wave_director.release_enemy(enemy)
	bursts.spawn(at, Color("80ed99"), 1.2)
	particles.emit_motes(at, Color("b7e4c7"), 10)
	feedback.report_kill()
	field_items.spawn_item(at, field_items.roll_item_id(team_luck))
	run_stats["planters"] = int(run_stats.get("planters", 0)) + 1


func _drop_experience(at: Vector2, amount: int, grade: int, _notable: bool) -> void:
	var rung := clampi(grade, 0, XP_GRADE_REWARD.size() - 1)
	experience_system.spawn_gem(at, maxi(1, roundi(float(amount) * XP_GRADE_REWARD[rung])), grade)


## Elites and bosses leave things on the floor. Ordinary enemies leave
## experience and nothing else.
##
## The 1.5% roll on every ordinary kill read as generosity and worked as noise:
## across six thousand kills a run it meant a steady drizzle of pickups from
## nowhere in particular, so walking to one was never a decision and the pair
## stopped reading the floor at all. A drop is now a thing a named fight left
## behind, which is the only way "there is an item over there" can be worth
## crossing a crowd for.
func _try_drop_field_item(drop_position: Vector2, was_elite: bool) -> void:
	if not was_elite:
		return
	# A chest that could fall off any kill is a slot machine running in the
	# background; one that only falls off a fight the pair had to actually win is
	# a reward for winning it.
	var chest_chance := minf(CHEST_MAX_CHANCE,
		CHEST_ELITE_CHANCE + CHEST_LUCK_CHANCE * float(team_luck) * (1.0 + team_greed * 0.5))
	if randf() < chest_chance:
		field_items.spawn_item(drop_position, "chest")
		return
	field_items.spawn_item(drop_position, field_items.roll_item_id(team_luck))


## Field pickups act on the pair, not the survivor who walked over them — the
## chain already decides who can reach a drop, so making the reward personal
## would punish whoever happened to be on the wrong side of it.
func _on_field_item_collected(item_id: String, collector_index := -1) -> void:
	var label: String = tr("%s 획득!") % tr(field_items.item_display_name(item_id))
	var color: Color = field_items.item_color(item_id)
	match item_id:
		"chest":
			var rewards := _open_chest()
			var centre := (players[0].global_position + players[1].global_position) * 0.5
			weapon_controller.play_shockwave(centre, 260.0, color, 0.48, false)
			particles.emit_motes(centre, color, 22)
			camera_shake = maxf(camera_shake, 12.0)
			label += tr("    카드 %d장 획득") % rewards.size()
			# Pushed to the front so the box is seen opening before anything it
			# contained gets its own showcase (a chest can hand out a fusion).
			_queue_showcase({"kind": "chest", "rewards": rewards}, true)
			_play_showcase_queue()
			# The loadout under the health bars stays visible while the box opens.
			_update_hud()
		"heal":
			var restored: Array[int] = [0, 0]
			for slot in 2:
				var before := players[slot].health
				players[slot].heal(players[slot].max_health * FIELD_ITEM_HEAL_RATIO)
				restored[slot] = roundi(players[slot].health - before)
			label += tr("    나 +%d HP    동료 +%d HP") % [restored[local_view_slot()], restored[1 - local_view_slot()]]
		"magnet":
			var pulled := experience_system.magnetize_all()
			# Two rings from the pair's midpoint so the pull has a visible source
			# and the stream of gems reads as caused rather than coincidental.
			var centre := (players[0].global_position + players[1].global_position) * 0.5
			weapon_controller.play_shockwave(centre, 900.0, color, 0.55, true)
			camera_shake = maxf(camera_shake, 4.0)
			label += tr("    경험치 결정 %d개 견인") % pulled
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
			label += tr("    %d초 사슬 무적    화력 +%d%%") % [
				int(CHAIN_WARD_DURATION), roundi((CHAIN_WARD_POWER - 1.0) * 100.0)]
		"guard":
			guard_remaining = GUARD_DURATION
			for player in players:
				if not player.downed:
					player.invulnerability = maxf(player.invulnerability, GUARD_DURATION)
				particles.emit_ring(player.global_position, color, 74.0, 0.5)
			camera_shake = maxf(camera_shake, 6.0)
			label += tr("    %d초 무적") % int(GUARD_DURATION)
		"frenzy":
			frenzy_remaining = FRENZY_DURATION
			for player in players:
				player.field_move_multiplier = FRENZY_MOVE_SPEED
				particles.emit_sparks(player.global_position, color, 12, 300.0)
			camera_shake = maxf(camera_shake, 9.0)
			label += tr("    %d초 광란    피해 +%d%%    이속 +%d%%    공속 +%d%%") % [
				int(FRENZY_DURATION), roundi((FRENZY_POWER - 1.0) * 100.0),
				roundi((FRENZY_MOVE_SPEED - 1.0) * 100.0), roundi((FRENZY_ATTACK_SPEED - 1.0) * 100.0),
			]
		"time_stop":
			time_stop_remaining = TIME_STOP_DURATION
			var stop_centre := (players[0].global_position + players[1].global_position) * 0.5
			weapon_controller.play_shockwave(stop_centre, 1100.0, color, 0.7, false)
			particles.emit_motes(stop_centre, color, 20)
			camera_shake = maxf(camera_shake, 14.0)
			label += tr("    %d초 시간 정지") % int(TIME_STOP_DURATION)
		"purge":
			var midpoint := (players[0].global_position + players[1].global_position) * 0.5
			var visible_world := _visible_world_rect()
			var purged := 0
			for candidate in enemies.duplicate():
				var enemy := candidate as ChaserEnemy
				if not is_instance_valid(enemy) or enemy.dead or enemy.scenery:
					continue
				if visible_world.grow(enemy.radius).has_point(enemy.global_position):
					# Twice current health still clears the hedgehog's damage reduction.
					enemy.take_damage(maxf(enemy.health, enemy.max_health) * 2.0 + 1.0)
					purged += 1
			# The view-clear is the biggest thing an item does, so it gets the
			# biggest presentation in the game: an expanding front, a bright core
			# flash, and a burst at every enemy it caught.
			var view_radius := visible_world.size.length() * 0.5
			weapon_controller.play_shockwave(midpoint, view_radius, color, 0.42, false)
			weapon_controller.play_shockwave(midpoint, view_radius * 0.55, Color.WHITE, 0.3, false)
			weapon_controller.play_purge_rays(midpoint, view_radius, color)
			camera_shake = maxf(camera_shake, 22.0)
			label += tr("    시야 내 적 %d체 청소") % purged
	run_stats["items"] = int(run_stats["items"]) + 1
	if collector_index >= 0 and collector_index < 2:
		run_stats["items_by_player"][collector_index] = int(run_stats["items_by_player"][collector_index]) + 1
		_award_contribution(collector_index, CONTRIBUTION_ITEM)
	var item_counts: Dictionary = run_stats["items_by_type"]
	item_counts[item_id] = int(item_counts.get(item_id, 0)) + 1
	var pickup_centre := (players[0].global_position + players[1].global_position) * 0.5
	particles.emit_motes(pickup_centre, color, 8)
	feedback.play_item_cue(item_id)
	_show_message(label, color)


## World-space rectangle currently visible through the gameplay camera. Purge
## uses the actual view instead of a fixed radius so zooming out never leaves a
## visible elite or boss inexplicably untouched.
func _visible_world_rect() -> Rect2:
	if is_instance_valid(rooftop_view):
		return rooftop_view.visible_bounds(world_camera.get_screen_center_position(), world_camera.zoom)
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(1280.0, 720.0)
	var centre := (players[0].global_position + players[1].global_position) * 0.5
	var zoom := Vector2.ONE
	if is_instance_valid(world_camera):
		centre = world_camera.get_screen_center_position()
		zoom = world_camera.zoom
	var world_size := Vector2(
		viewport_size.x / maxf(0.001, absf(zoom.x)),
		viewport_size.y / maxf(0.001, absf(zoom.y))
	)
	return Rect2(centre - world_size * 0.5, world_size)


## A chest is resolved immediately so it never opens a second modal over a
## level-up. A ready fusion still wins, but otherwise every reward may either
## deepen carried gear or introduce something new. Luck raises the latter odds.
## Each reward carries the icon it will be thrown out as, not only its name:
## the opening showcase shows what came out, and a list of text would be the
## thing the box was supposed to replace.
func _open_chest() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for reward_index in _roll_chest_reward_count():
		var upgrade_candidates := _chest_upgrade_candidates()
		var unlock_candidates := _chest_unlock_candidates()
		var candidates: Array[Dictionary] = []
		if not unlock_candidates.is_empty() and (upgrade_candidates.is_empty() or randf() < _chest_new_gear_chance()):
			candidates = unlock_candidates
		else:
			candidates = upgrade_candidates if not upgrade_candidates.is_empty() else unlock_candidates
		if candidates.is_empty():
			# Nothing left that either survivor can still take. The box pays in
			# moon-fish rather than inventing a reward, so a late chest opened by
			# a finished build is worth something to the next run.
			var paid := 0 if debug_run_tainted else meta_progression.award(CHEST_POINT_REWARD)
			results.append({
				"label": tr("달빛 생선 +%d") % paid,
				"detail": "영구 재화로 저장",
				"advice": "neutral",
				"icon": IconCatalog.upgrade("luck"),
				"slot": -1,
				"card": {"category": "상자 보상", "title": tr("달빛 생선 +%d") % paid,
					"body": "영구 재화로 저장\n다음 원정에서 사용", "icon": IconCatalog.upgrade("luck"),
					"advice": "neutral", "reason": "빌드 완성 보상"},
			})
			continue
		var chosen := _choose_chest_candidate(candidates)
		var slot := int(chosen["slot"])
		var option: Dictionary = chosen["option"]
		var art := IconCatalog.upgrade(_option_icon_id(slot, option), _option_weapon_id(slot, option))
		var detail := _upgrade_preview(slot, option).replace("\n", "    ")
		var rating := _score_upgrade_option(slot, option)
		var score := float(rating["score"])
		var advice := "recommended" if score >= RECOMMEND_MIN_SCORE else (
			"discouraged" if score <= DISCOURAGE_MAX_SCORE else "neutral"
		)
		var advice_reason := String(rating["reason"])
		if advice == "discouraged":
			advice_reason = _discouragement_reason(slot, option, score)
		# Annotated the way a growth hand is, so the card model reads the same
		# verdict fields; taken before the reward is applied because the card body
		# is a before/after of the build it is about to change.
		option["recommendation_reason"] = String(rating["reason"])
		option["recommended"] = advice == "recommended"
		option["discouraged"] = advice == "discouraged"
		option["discouragement_reason"] = advice_reason
		var card: Dictionary = NeonGrowthUI.card_model(self, slot, option)
		_apply_upgrade(slot, option)
		_apply_pending_evolutions(slot)
		results.append({
			"label": "%s %s" % [player_label(slot), String(chosen["label"])],
			"detail": detail,
			"advice": advice,
			"advice_reason": advice_reason,
			"icon": art,
			"slot": slot,
			"card": card,
			"tint": NeonGrowthUI.card_tint(self, slot),
			# The portrait is what actually reads at a glance while eight things
			# are flying out of a box: a player finds their own cat, not a "P2".
			"owner_icon": IconCatalog.survivor(String(selected_characters[slot]["id"])) if selected_characters[slot] != null else null,
		})
	return results


## How many things come out. Every rung is rarer than the one below it and the
## top of the ladder is close to never — a chest is a moment, and a moment that
## happens reliably is a formality. Luck shifts the whole roll down rather than
## widening any single band, so a lucky pair sees the middle of the ladder more
## often without the top of it becoming something to plan around.
const CHEST_REWARD_LADDER := [
	[0.0008, CHEST_MAX_REWARDS],
	[0.004, 7],
	[0.012, 6],
	[0.030, 5],
	[0.065, 4],
	[0.130, 3],
	[0.300, 2],
]


func _roll_chest_reward_count() -> int:
	var roll := pow(randf(), 1.0 + maxf(0.0, float(team_luck)) * 0.10)
	for rung in CHEST_REWARD_LADDER:
		if roll < float(rung[0]):
			return int(rung[1])
	return 2


func _chest_new_gear_chance() -> float:
	return minf(CHEST_NEW_GEAR_MAX_CHANCE,
		CHEST_NEW_GEAR_BASE_CHANCE + CHEST_NEW_GEAR_LUCK_CHANCE * float(team_luck))


func _chest_upgrade_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for slot in 2:
		for weapon_slot in weapon_loadouts[slot].size():
			var state: Dictionary = weapon_loadouts[slot][weapon_slot]
			if int(state.get("tier", 1)) >= Evolutions.WEAPON_MAX_TIER or WeaponGrowthScript.needs_tech(state):
				continue
			# Titles are the growth hand's own, so a chest reward's card names the
			# upgrade exactly as the level-up card for it would.
			for upgrade_id in ["weapon_power", "weapon_rate"]:
				candidates.append({
					"slot": slot, "priority": 2,
					"option": {"id": upgrade_id, "weapon_slot": weapon_slot,
						"title": "%s\n%s" % ["마력 증폭" if upgrade_id == "weapon_power" else "고속 시전", String(state["weapon_name"])]},
					"label": "%s %s" % [tr(String(state["weapon_name"])), tr("화력") if upgrade_id == "weapon_power" else tr("속도")],
				})
			for key in ["a", "b"]:
				if _special_has_room(slot, weapon_slot, key):
					var spec := _special_spec(state, key)
					candidates.append({
						"slot": slot, "priority": 2,
						"option": {"id": "special_" + key, "weapon_slot": weapon_slot,
							"title": "%s\n%s" % [String(spec.get("title", "특성")), String(state["weapon_name"])]},
						"label": tr("%s 특성") % tr(String(state["weapon_name"])),
					})
		for treasure_slot in treasure_loadouts[slot].size():
			var treasure: Dictionary = treasure_loadouts[slot][treasure_slot]
			if int(treasure["tier"]) < Treasures.MAX_TIER:
				candidates.append({
					"slot": slot, "priority": 2,
					"option": {"id": "treasure_upgrade", "treasure_slot": treasure_slot, "title": String(treasure["name"])},
					"label": "%s Lv.%d" % [String(treasure["name"]), int(treasure["tier"]) + 1],
				})
	return candidates


func _chest_unlock_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for slot in 2:
		if weapon_loadouts[slot].size() < WEAPON_LOADOUT_CAP:
			for character in _pick_unowned_characters(slot, character_catalog.size()):
				candidates.append({
					"slot": slot, "priority": 1,
					"option": {"id": "unlock_weapon", "character": character,
						"title": "신규 무기: %s" % String(character["weapon_name"])},
					"label": tr("신규 %s") % tr(String(character["weapon_name"])),
				})
		if treasure_loadouts[slot].size() < TREASURE_LOADOUT_CAP:
			for treasure in _pick_unowned_treasures(slot, Treasures.all_treasures().size()):
				candidates.append({
					"slot": slot, "priority": 1,
					"option": {"id": "unlock_treasure", "treasure": treasure,
						"title": "새 보물: %s" % String(treasure["name"])},
					"label": "신규 %s" % String(treasure["name"]),
				})
	return candidates


## Who gets this one.
##
## The box used to hand every reward to whichever build was shallower, which was
## fair and completely predictable — two survivors opening a chest together knew
## the answer before it opened, and a chest that spilled four things spread them
## two and two every time. Each reward now rolls its own owner, so one survivor
## walking away with the whole box is a thing that happens; the showcase says who
## got what, which is what makes the roll worth watching rather than worth
## auditing afterwards.
##
## The caller has already rolled whether this reward is carried growth or new
## gear. Priority only compares candidates inside that category (most notably,
## a ready fusion is never displaced by an ordinary tier).
func _choose_chest_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var highest_priority := 0
	for candidate in candidates:
		highest_priority = maxi(highest_priority, int(candidate["priority"]))
	var priority_pool := candidates.filter(func(candidate: Dictionary) -> bool: return int(candidate["priority"]) == highest_priority)
	# The owner is rolled first and the reward second, rather than picking from
	# the pooled list: drawing straight from the pool would quietly favour
	# whichever survivor happened to have more options open.
	var wanted := 0 if randf() < 0.5 else 1
	var owned := priority_pool.filter(func(candidate: Dictionary) -> bool: return int(candidate["slot"]) == wanted)
	if owned.is_empty():
		owned = priority_pool
	return owned.pick_random()


func _build_depth(slot: int) -> int:
	var depth := 0
	for weapon in weapon_loadouts[slot]:
		depth += int((weapon as Dictionary).get("tier", 1))
	for treasure in treasure_loadouts[slot]:
		depth += int((treasure as Dictionary).get("tier", 1))
	return depth


## Adds a showcase to the queue. `front` is for a chest, whose own opening has
## to be seen before whatever the chest happened to contain.
func _queue_showcase(entry: Dictionary, front := false) -> void:
	if front:
		showcase_queue.push_front(entry)
	else:
		showcase_queue.append(entry)


## Plays everything queued, then calls `continuation`. The tree is paused for
## the duration and put back the way it was found, so this works both from a
## level-up (already paused) and from a chest picked up mid-fight (not).
func _play_showcase_queue(continuation := Callable()) -> void:
	cinematic_continuation = continuation
	if not cinematic_active:
		cinematic_resume_paused = get_tree().paused
	_advance_showcase_queue()


func _advance_showcase_queue() -> void:
	if showcase_queue.is_empty():
		cinematic_active = false
		get_tree().paused = cinematic_resume_paused
		var next := cinematic_continuation
		cinematic_continuation = Callable()
		if next.is_valid():
			next.call()
		return
	var entry: Dictionary = showcase_queue.pop_front()
	cinematic_active = true
	get_tree().paused = true
	var node := ShowcaseScript.new() as Showcase
	node.player_labels = [player_label(0), player_label(1)]
	match String(entry["kind"]):
		"fusion":
			var second_icon: Texture2D = IconCatalog.weapon(String(entry["material_weapon_id"])) if entry.has("material_weapon_id") else null
			node.play_fusion(
				IconCatalog.weapon(String(entry["base_weapon_id"])),
				second_icon,
				IconCatalog.weapon(String(entry["weapon_id"])),
				String(entry["name"]), Color("ffd166"))
			feedback.play_cue("resonance")
		"resonance":
			node.play_resonance(
				IconCatalog.weapon(String(entry["weapon_a_id"])),
				IconCatalog.weapon(String(entry["weapon_b_id"])),
				String(entry["name"]), Color("c77dff"))
			feedback.play_cue("resonance")
		"chest":
			node.play_chest(entry["rewards"])
			feedback.play_cue("chest_open")
	node.finished.connect(_advance_showcase_queue)
	hud_layer.add_child(node)
	camera_shake = maxf(camera_shake, 8.0)


func _gain_shared_xp(amount: int, collector_index := -1) -> void:
	var gained := int(round(float(amount) * team_growth))
	progression.add_experience(gained)
	if collector_index >= 0 and collector_index < 2:
		run_stats["xp_by_player"][collector_index] = int(run_stats["xp_by_player"][collector_index]) + gained
		_award_contribution(collector_index, float(gained))
	feedback.report_xp()
	# Not opened here any more: the physics loop watches the queue so a level
	# earned mid-burst waits out the gap instead of interrupting on the frame
	# the gem happened to land.
	if not level_up_active and progression.can_level_up() and level_up_gap_remaining <= 0.0:
		_begin_level_up()


## What a level is worth once the catalogue has nothing left to sell.
##
## A run used to simply stop counting: the bar froze, the gems still on the
## floor were worth nothing, and the last stretch of a twenty-five minute run
## paid the pair in nothing at all. Every level past a finished build now buys a
## small permanent step for both survivors instead, so experience never has a
## ceiling — it just stops being a decision and becomes a number that keeps
## going up.
const OVERFLOW_MIGHT := 0.02
const OVERFLOW_HEALTH := 6.0


func _begin_level_up() -> void:
	if not progression.can_level_up():
		return
	var next_p1 := _get_upgrade_choices(1)
	var next_p2 := _get_upgrade_choices(2)
	if next_p1.is_empty() and next_p2.is_empty():
		_consume_overflow_levels()
		return
	growth_finished = false
	if not progression.consume_level_up():
		return
	if progression.level % REROLL_PER_LEVELS == 0:
		for slot in 2:
			rerolls_remaining[slot] = mini(REROLL_CAP, rerolls_remaining[slot] + 1)
	level_up_active = true
	modal_dim.visible = true
	if not modal_dim.veil_only:
		modal_dim.veil_only = true
		modal_dim.queue_redraw()
	for notice in notice_stack:
		if is_instance_valid(notice):
			notice.visible = false
	level_up_input_delay = LEVEL_UP_INPUT_DELAY
	level_up_gap_remaining = 0.0
	selected_upgrade_indices = [-2 if next_p1.is_empty() else -1, -2 if next_p2.is_empty() else -1]
	upgrade_cursors = [0, 0]
	p1_choices = next_p1
	p2_choices = next_p2
	level_overlay.visible = true
	_animate_level_overlay(true)
	_pull_camera_for_growth()
	_refresh_level_up_ui()
	_update_hud()
	get_tree().paused = true
	feedback.play_cue("level")
	online.send_growth_state("growth_open")


## A key that identifies one specific offered option (not just its id, since
## e.g. "weapon_power" exists once per owned weapon) so _get_upgrade_choices
## can avoid repeating the exact same hand the very next level-up.
## The growth screen used to blink into existence between two frames, which
## after a wave of experience reads as the game glitching rather than as a
## moment arriving. It now drops in and lifts out over a fifth of a second.
##
## Runs on the overlay's own tween, which processes while the tree is paused
## because the overlay is PROCESS_MODE_ALWAYS — everything else on screen is
## frozen at this point, including the tween server's usual clock.
const LEVEL_OVERLAY_ENTER := 0.22
const LEVEL_OVERLAY_EXIT := 0.16


## How far the view closes in while a growth choice is open, and how long the
## move takes. Small on purpose: this is a beat of emphasis on two cats standing
## in a fight, not a cutscene. Nothing puts the zoom back — _update_camera lerps
## it to the framing the pair's own positions ask for as soon as the run resumes,
## so handing control back is also what pulls the view out again.
const GROWTH_ZOOM := 1.22
const GROWTH_ZOOM_TIME := 0.34
const GROWTH_FLASH_ALPHA := 0.26
const GROWTH_FLASH_TIME := 0.30
## Screen pixels the view rises by while the band is up. _update_camera frames
## the pair at roughly y=445, which the band now covers — so pulling in without
## this would zoom the camera onto two cats hidden behind the cards. The strip
## left between the HUD and the band is about 130..286, and this puts them in
## the middle of it. Nothing puts it back either: _update_camera lerps the view
## home over a third of a second once the run resumes, which is what makes
## handing control back read as the camera letting go.
const GROWTH_LIFT := 200.0


func _pull_camera_for_growth() -> void:
	_pull_camera_for_choice(level_overlay)


## The same beat for any screen that holds the run to ask the pair something.
## `panel` owns the tween because the tree is paused while it plays, and the
## panel is the node that ignores that.
func _pull_camera_for_choice(panel: Control) -> void:
	if not is_instance_valid(world_camera) or not is_instance_valid(panel):
		return
	var tween := panel.create_tween()
	tween.set_parallel(true)
	# Clamped rather than multiplied blind: back-to-back level-ups would
	# otherwise each pull in another 22% on a view the run never got to reset.
	var target := Vector2.ONE * minf(GROWTH_ZOOM, world_camera.zoom.x * GROWTH_ZOOM)
	var pull := tween.tween_property(world_camera, "zoom", target, GROWTH_ZOOM_TIME)
	pull.set_trans(Tween.TRANS_CUBIC)
	pull.set_ease(Tween.EASE_OUT)
	# Screen pixels converted to world units at the zoom being tweened *to*, so
	# the pair ends up where the strip actually is rather than where it would be
	# at the zoom the view happened to start from.
	var lift := tween.tween_property(world_camera, "position:y",
		world_camera.position.y - GROWTH_LIFT / target.y, GROWTH_ZOOM_TIME)
	lift.set_trans(Tween.TRANS_CUBIC)
	lift.set_ease(Tween.EASE_OUT)
	if is_instance_valid(growth_flash):
		growth_flash.visible = true
		growth_flash.modulate.a = GROWTH_FLASH_ALPHA
		var fade := tween.tween_property(growth_flash, "modulate:a", 0.0, GROWTH_FLASH_TIME)
		fade.set_trans(Tween.TRANS_QUAD)
		fade.set_ease(Tween.EASE_OUT)
		# Guarded because a queued level-up can restart the flash before this
		# fires, and an unguarded callback would then hide the new one.
		tween.chain().tween_callback(func() -> void:
			if growth_flash.modulate.a <= 0.01:
				growth_flash.visible = false)


func _animate_level_overlay(opening: bool) -> void:
	level_overlay_tween = _animate_choice_panel(level_overlay, level_overlay_tween, opening,
		func() -> bool: return level_up_active)


func _animate_resonance_overlay(opening: bool) -> void:
	resonance_overlay_tween = _animate_choice_panel(resonance_overlay, resonance_overlay_tween, opening,
		func() -> bool: return resonance_vote_active)


## Drops a choice panel in and lifts it back out. `still_open` is asked at the
## end of the exit, because the run is already running again underneath by then
## and a screen that reopened in the meantime must not be taken down.
func _animate_choice_panel(panel: Control, running: Tween, opening: bool, still_open: Callable) -> Tween:
	if not is_instance_valid(panel):
		return null
	# Killed rather than left running: queued level-ups can open a new screen
	# while the previous one is still lifting out, and two tweens on the same
	# properties fight each other into a stuck half-faded panel.
	if running != null and running.is_valid():
		running.kill()
	panel.pivot_offset = panel.size * 0.5
	var tween := panel.create_tween()
	tween.set_parallel(true)
	if opening:
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.94, 0.9)
		panel.position.y = LEVEL_OVERLAY_Y + 26.0
		tween.tween_property(panel, "modulate:a", 1.0, LEVEL_OVERLAY_ENTER)
		tween.tween_property(panel, "scale", Vector2.ONE, LEVEL_OVERLAY_ENTER)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "position:y", LEVEL_OVERLAY_Y, LEVEL_OVERLAY_ENTER)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return tween
	tween.tween_property(panel, "modulate:a", 0.0, LEVEL_OVERLAY_EXIT)
	tween.tween_property(panel, "scale", Vector2(0.96, 0.94), LEVEL_OVERLAY_EXIT)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "position:y", LEVEL_OVERLAY_Y - 18.0, LEVEL_OVERLAY_EXIT)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# The panel is only actually taken down once the exit has played; the run is
	# already unpaused underneath it, which is what makes the lift-out read as
	# handing control back rather than as a second pause.
	tween.chain().tween_callback(func() -> void:
		if not bool(still_open.call()):
			panel.visible = false
			panel.modulate.a = 1.0
			panel.scale = Vector2.ONE
			panel.position.y = LEVEL_OVERLAY_Y)
	return tween


## Drains every banked level at once rather than one per call: the growth
## screen is what used to pace them, and without it a backlog of six levels
## would otherwise take six frames of message banners to clear.
func _consume_overflow_levels() -> void:
	var gained := 0
	while progression.consume_level_up():
		gained += 1
		overflow_levels += 1
		for player in players:
			player.might += OVERFLOW_MIGHT
			player.max_health += OVERFLOW_HEALTH
			player.heal(OVERFLOW_HEALTH)
	growth_finished = true
	level_up_gap_remaining = 0.0
	if gained <= 0:
		return
	_show_message(tr("초월 성장 %d    빌드 완성 이후에도 계속 강해집니다") % overflow_levels,
		Color("80ed99"))
	_update_hud()


func _option_key(option: Dictionary) -> String:
	var option_id := String(option["id"])
	if option_id == "choose_tech":
		return "choose_tech:%d:%s" % [int(option["weapon_slot"]), String((option["tech"] as Dictionary)["id"])]
	if option_id == "unlock_weapon":
		return "unlock_weapon:%s:%s" % [String((option["character"] as Dictionary)["id"]), String((option.get("tech", {}) as Dictionary).get("id", ""))]
	if option_id == "unlock_treasure":
		return "unlock_treasure:" + String((option["treasure"] as Dictionary)["id"])
	if option_id == "treasure_upgrade":
		return "treasure_upgrade:%d" % int(option["treasure_slot"])
	return "%s:%d" % [option_id, int(option.get("weapon_slot", -1))]


## Characters whose weapon this player does not already carry, shuffled and
## capped at `count` — the pool of "new tech" candidates a level-up can offer.
##
## Ownership is read off `base_weapon_id`, never off `weapon_id`, and that is the
## whole fix for the duplicate-weapon bug. An enhancement renames the slot — the
## 유도탄 a survivor has carried all run becomes 성좌 관통포, keeping its base id
## and losing its old weapon_id — so a check against weapon_id stopped
## recognising it the moment it enhanced, and the level-up hand and the chest
## both started offering 유도탄 back as "신규 무기". Taking it gave the survivor
## two slots of the same weapon, one enhanced and one at Lv.1.
func _carried_weapon_ids(slot: int) -> Dictionary:
	var owned_ids: Dictionary = {}
	for weapon: Dictionary in weapon_loadouts[slot]:
		owned_ids[String(weapon.get("base_weapon_id", weapon["weapon_id"]))] = true
		owned_ids[String(weapon["weapon_id"])] = true
	return owned_ids


func _pick_unowned_characters(slot: int, count: int) -> Array[Dictionary]:
	var owned_ids := _carried_weapon_ids(slot)
	var candidates: Array[Dictionary] = []
	for character in character_catalog:
		if not owned_ids.has(String(character["weapon_id"])):
			candidates.append(character)
	candidates.shuffle()
	return candidates.slice(0, count)


## Treasures this player does not already carry, shuffled and capped. Mirrors
## _pick_unowned_characters so both halves of a build are offered the same way.
## The enhancement this weapon slot is owed right now, or an empty dictionary.
## The selected route supplies the required treasure id; both halves are shown
## on the route card and in the full-stat sheet.
func _available_evolution(slot: int, weapon_slot: int) -> Dictionary:
	var weapon: Dictionary = weapon_loadouts[slot][weapon_slot]
	if bool(weapon.get("evolved", false)):
		return {}
	if int(weapon.get("tier", 1)) < Evolutions.EVOLUTION_TIER:
		return {}
	if String(weapon.get("tech_id", "")).is_empty():
		return {}
	var treasure_id := String(weapon.get("tech_synergy_treasure_id", ""))
	if treasure_id.is_empty() or _treasure_tier(slot, treasure_id) < Evolutions.REQUIRED_TREASURE_TIER:
		return {}
	return _selected_evolution_for_state(weapon)


## One enhanced form per weapon, whichever route it took. The route survives the
## enhancement as delivery and growth weighting rather than as a separate entry
## in the catalogue (see EvolutionCatalog.build_state).
func _selected_evolution_for_state(weapon: Dictionary) -> Dictionary:
	return Evolutions.for_base(String(weapon.get("base_weapon_id", weapon.get("weapon_id", ""))))


## Enhances every weapon that has just completed its recipe, and reports what
## changed so the caller can show it. Called after any weapon or treasure upgrade
## because either Lv.7 or the required treasure's Lv.4 can be the last step. The
## enhancement itself is not another card the player must buy.
func _apply_pending_evolutions(player_slot: int) -> Array[Dictionary]:
	var enhanced: Array[Dictionary] = []
	for weapon_slot in weapon_loadouts[player_slot].size():
		var evolution := _available_evolution(player_slot, weapon_slot)
		if evolution.is_empty():
			continue
		var base_state: Dictionary = weapon_loadouts[player_slot][weapon_slot]
		weapon_controller.clear_sustained_for_player(player_slot)
		weapon_loadouts[player_slot][weapon_slot] = Evolutions.build_state(evolution, base_state)
		_merge_weapon_damage_record(player_slot, String(base_state["weapon_id"]), String(evolution["weapon_id"]))
		fusion_discovered = true
		if not debug_run_tainted:
			meta_progression.mark_discovered(String(evolution["weapon_id"]))
		# The biggest single step in the tree used to be one line in the message
		# banner, identical in weight to "+25% 피해". It gets the screen now.
		_queue_showcase({
			"kind": "fusion",
			"base_weapon_id": String(base_state["weapon_id"]),
			"weapon_id": String(evolution["weapon_id"]),
			"name": String(evolution["weapon_name"]),
		})
		enhanced.append(evolution)
	return enhanced


## Required treasures named by this survivor's chosen routes and not yet held.
## They receive a useful weight, not a guaranteed slot: missing one is now a
## real reason to reroll or change the rest of the build.
func _synergy_treasures(slot: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for weapon: Dictionary in weapon_loadouts[slot]:
		var treasure_id := String(weapon.get("tech_synergy_treasure_id", ""))
		if treasure_id.is_empty() or seen.has(treasure_id) or _treasure_tier(slot, treasure_id) > 0:
			continue
		seen[treasure_id] = true
		var treasure := Treasures.by_id(treasure_id)
		if not treasure.is_empty():
			result.append(treasure)
	return result


## What a second copy of a shared treasure is worth.
##
## Shared treasures change a team resource, so a pair could take the same one on
## both survivors and get exactly double the effect. That made doubling up the
## answer on every shared card — two 성장의 서 flatly beats one plus anything
## else — while quietly costing each survivor one of their four personal slots.
## The deeper holding now counts in full and the shallower one at this rate, so
## a second copy is still worth taking when the pair really wants that resource,
## and never simply because it is the same card again.
const SHARED_SECOND_CARRIER := 0.5


## Effective tiers of one shared treasure across the pair, on the weighted ladder
## (TreasureCatalog.effective_tiers) so a deep shared treasure pays like a deep
## personal one.
func _shared_tiers(treasure_id: String) -> float:
	var deeper := 0.0
	var shallower := 0.0
	for slot in 2:
		var tier := Treasures.effective_tiers(treasure_id, _treasure_tier(slot, treasure_id))
		if tier > deeper:
			shallower = deeper
			deeper = tier
		elif tier > shallower:
			shallower = tier
	return deeper + shallower * SHARED_SECOND_CARRIER


## Rebuilds every team-wide number from the two treasure loadouts and permanent
## progression. Called whenever a shared treasure is taken or deepened, and once
## on a fresh run, so one place decides what the pair's shared effects add up to
## instead of a dozen increments scattered through the upgrade path.
func _recompute_team_effects() -> void:
	team_overcharge = _shared_tiers("overcharge") * 0.06
	team_greed = _shared_tiers("greed") * 0.30
	# 성장의 서 was worth +10% shared XP a tier, so one carrier at its cap doubled
	# the pair's experience and two carriers went past +150%. That is not a
	# treasure, it is a second difficulty setting: the measured effect was the
	# gap between level-ups halving, from roughly 16 seconds to under 11, which
	# is the whole of "레벨업이 너무 쉬워진다". Worse, it compounds with itself —
	# faster levels buy more cards, which buy more of everything, including this.
	# Halved, so a maxed pair gains about 50% rather than 100%+.
	team_growth = 1.0 + _shared_tiers("growth") * 0.05
	team_luck = meta_progression.team_luck_bonus() + int(round(_shared_tiers("luck")))
	team_lifesteal = _shared_tiers("lifesteal") * LIFESTEAL_PER_TIER
	team_level_heal = _shared_tiers("catnip") * 0.04
	team_hunt_bonus = _shared_tiers("bounty_bell") * 0.18
	team_close_power = _shared_tiers("twin_charm") * 0.05
	team_dash_burst = _shared_tiers("dash_claw") * 11.0
	# The shared magnet is what the two cats bring to it plus anything bought
	# between runs, so a Nova pair really does sweep a screen others walk across.
	team_magnet = 1.0 + meta_progression.team_magnet_bonus() + _shared_tiers("magnet") * 0.20
	_apply_team_magnet()


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


func _growth_choice_count() -> int:
	var count := 3
	for extra in 3:
		var chance := minf(0.85, maxf(0.0, float(team_luck)) * 0.075 / float(extra + 1))
		if randf() < chance:
			count += 1
	return count


## Relative pull of each kind of card in the weighted part of a hand. Gear the
## survivor already carries is deliberately not the heaviest entry here; see
## _get_upgrade_choices for why.
const GROWTH_WEIGHT_WEAPON := 3.0
const GROWTH_WEIGHT_TREASURE := 2.2
const GROWTH_WEIGHT_NEW_WEAPON := 3.0
const GROWTH_WEIGHT_NEW_TREASURE := 3.0
## What each point of shared luck adds to both discovery weights. Luck used to
## buy extra copies of build-defining cards in a flat shuffle; the shuffle is
## gone, so it leans the category draw instead and means the same thing.
const LUCK_DISCOVERY_WEIGHT := 0.4


## Every growth card one owned weapon could be offered right now. A weapon
## contributes at most one of these to a hand (see _get_upgrade_choices), so
## this is the set that one card is drawn from rather than four cards the hand
## deals from directly.
func _weapon_growth_options(slot: int, weapon_slot: int) -> Array[Dictionary]:
	var state: Dictionary = weapon_loadouts[slot][weapon_slot]
	if int(state.get("tier", 1)) >= Evolutions.WEAPON_MAX_TIER or WeaponGrowthScript.needs_tech(state):
		return []
	var weapon_name := String(state["weapon_name"])
	var options: Array[Dictionary] = []
	if WeaponTechs.allows(state, "weapon_power"):
		options.append({"id": "weapon_power", "weapon_slot": weapon_slot, "title": "마력 증폭\n%s" % weapon_name})
	if WeaponTechs.allows(state, "weapon_rate"):
		options.append({"id": "weapon_rate", "weapon_slot": weapon_slot, "title": "고속 시전\n%s" % weapon_name})
	for key: String in ["a", "b"]:
		if not WeaponTechs.allows(state, "special_" + key):
			continue
		var spec := _special_spec(state, key)
		if spec.is_empty():
			continue
		options.append({
			"id": "special_" + key, "weapon_slot": weapon_slot,
			"title": "%s\n%s" % [String(spec["title"]), weapon_name],
		})
	return options.filter(func(option: Dictionary) -> bool: return UpgradeValue.has_effect(self, slot, option))


## Removes one option from `options` and returns it, preferring one the previous
## hand did not already show. Returns an empty dictionary when nothing is left.
func _draw_growth_option(options: Array, previous_keys: Array) -> Dictionary:
	if options.is_empty():
		return {}
	var fresh: Array = []
	for option in options:
		if not (_option_key(option as Dictionary) in previous_keys):
			fresh.append(option)
	var picked: Dictionary = (fresh if not fresh.is_empty() else options).pick_random()
	options.erase(picked)
	return picked


## Picks one non-empty bucket in proportion to its weight.
func _pick_growth_bucket(buckets: Array) -> Dictionary:
	var total := 0.0
	for bucket: Dictionary in buckets:
		if not (bucket["options"] as Array).is_empty():
			total += float(bucket["weight"])
	if total <= 0.0:
		return {}
	var roll := randf() * total
	var last: Dictionary = {}
	for bucket: Dictionary in buckets:
		if (bucket["options"] as Array).is_empty():
			continue
		last = bucket
		roll -= float(bucket["weight"])
		if roll <= 0.0:
			return bucket
	return last


## Deals one survivor's growth hand.
##
## This used to be a single flat shuffle over every valid card, and the bag it
## shuffled was lopsided by construction: each owned weapon put up to four cards
## into it (화력 · 속도 · 특성 A · 특성 B) and each owned treasure one, against two
## new-weapon cards and a handful of new treasures. A survivor carrying four
## weapons and four treasures was therefore drawing three cards out of roughly
## twenty that all said "make what you already have bigger". The opening of a run
## felt like a formality because of it — nearly every hand was a damage card for
## the weapon that was already working, so the first weapon snowballed, levels
## arrived faster for it, and the build decisions the loadout caps exist to force
## were never actually put to the player.
##
## A hand is dealt by category now, and a category is a row of the build rather
## than a pile of cards:
##
##   무기 성장   one card per owned weapon, drawn from that weapon's own axes
##   보물 성장   one card per owned treasure that still has a tier to take
##   신규 무기   only while a weapon slot is free
##   신규 보물   only while a treasure slot is free
##
## One card per owned weapon is the load-bearing rule: a weapon can never take
## more than one slot in a hand, so holding more gear no longer crowds discovery
## out of the draw — it just means each piece is offered less often, which is
## what a four-slot loadout should feel like.
##
## Every slot is now drawn from the weighted buckets. No carried item and no new
## discovery is guaranteed to appear, which makes a weak hand and a reroll an
## actual part of the run instead of an edge case.
func _get_upgrade_choices(player_index: int) -> Array[Dictionary]:
	var slot := player_index - 1
	var loadout: Array = weapon_loadouts[slot]
	var treasures: Array = treasure_loadouts[slot]
	var choice_count := _growth_choice_count()

	# A weapon grows untyped for its first few cards and then has to commit to a
	# route before it takes another tier. One-route weapons are assigned the
	# moment they reach the gate (see _apply_upgrade), so they never stop here.
	for weapon_slot in loadout.size():
		var carried: Dictionary = loadout[weapon_slot]
		if not WeaponGrowthScript.needs_tech(carried):
			continue
		var tech_choices: Array[Dictionary] = []
		for tech in WeaponTechs.for_weapon(String(carried.get("base_weapon_id", carried["weapon_id"]))):
			var option := {
				"id": "choose_tech", "weapon_slot": weapon_slot, "tech": tech,
				"title": String(tech["name"]),
			}
			option["description"] = _upgrade_preview(slot, option)
			tech_choices.append(option)
		last_upgrade_choice_keys[slot] = []
		_annotate_recommendations(slot, tech_choices)
		return tech_choices

	var previous_keys: Array = last_upgrade_choice_keys[slot]

	# 무기 성장 — at most one card per weapon, and which of its axes is offered is
	# itself part of the draw.
	var weapon_growth: Array[Dictionary] = []
	for weapon_slot in loadout.size():
		var axes := _weapon_growth_options(slot, weapon_slot)
		var axis := _draw_growth_option(axes, previous_keys)
		if not axis.is_empty():
			weapon_growth.append(axis)

	# 보물 성장 — deepening what the survivor committed a slot to.
	var treasure_growth: Array[Dictionary] = []
	for treasure_slot in treasures.size():
		var treasure: Dictionary = treasures[treasure_slot]
		if int(treasure["tier"]) >= Treasures.MAX_TIER:
			continue
		var option := {
			"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": treasure_slot,
			"title": String(treasure["name"]),
		}
		if UpgradeValue.has_effect(self, slot, option):
			treasure_growth.append(option)

	# 신규 무기 — a new weapon arrives untyped: its route is chosen at
	# TECH_UNLOCK_TIER, once the survivor has seen what it does.
	var new_weapons: Array[Dictionary] = []
	if loadout.size() < WEAPON_LOADOUT_CAP:
		for character in _pick_unowned_characters(slot, 3):
			new_weapons.append({
				"id": "unlock_weapon", "weapon_slot": -1, "character": character,
				"title": "신규 무기: %s" % String(character["weapon_name"]),
			})

	# 신규 보물 — required route materials join the same weighted discovery pool
	# as everything else; they are not inserted into the hand for free.
	var new_treasures: Array[Dictionary] = []
	if treasures.size() < TREASURE_LOADOUT_CAP:
		var suited := _synergy_treasures(slot)
		var offered_ids: Dictionary = {}
		for treasure in suited:
			offered_ids[String(treasure["id"])] = true
			new_treasures.append({
				"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure,
				"title": "필수 보물: %s" % String(treasure["name"]),
			})
		for treasure in _pick_unowned_treasures(slot, maxi(3, suited.size()) + 3):
			if offered_ids.has(String(treasure["id"])):
				continue
			offered_ids[String(treasure["id"])] = true
			new_treasures.append({
				"id": "unlock_treasure", "weapon_slot": -1, "treasure": treasure,
				"title": "새 보물: %s" % String(treasure["name"]),
			})
	var discovery_filter := func(option: Dictionary) -> bool: return UpgradeValue.has_effect(self, slot, option)
	new_weapons.assign(new_weapons.filter(discovery_filter))
	new_treasures.assign(new_treasures.filter(discovery_filter))

	var luck_lean := maxf(0.0, float(team_luck)) * LUCK_DISCOVERY_WEIGHT
	var buckets: Array = [
		{"options": weapon_growth, "weight": GROWTH_WEIGHT_WEAPON},
		{"options": treasure_growth, "weight": GROWTH_WEIGHT_TREASURE},
		{"options": new_weapons, "weight": GROWTH_WEIGHT_NEW_WEAPON + luck_lean},
		{"options": new_treasures, "weight": GROWTH_WEIGHT_NEW_TREASURE + luck_lean},
	]

	var choices: Array[Dictionary] = []
	while choices.size() < choice_count:
		var bucket := _pick_growth_bucket(buckets)
		if bucket.is_empty():
			break
		var drawn := _draw_growth_option(bucket["options"] as Array, previous_keys)
		if drawn.is_empty():
			break
		choices.append(drawn)

	for option in choices:
		option["description"] = _upgrade_preview(slot, option)
	choices.shuffle()

	var choice_keys: Array = []
	for option in choices:
		choice_keys.append(_option_key(option))
	last_upgrade_choice_keys[slot] = choice_keys
	_annotate_recommendations(slot, choices)
	return choices


## Every base weapon's two unique upgrades, in one table.
##
## Four of the original ten weapons — 궤도 파편, 관통 광선, 지뢰 결계, 중력 붕괴 — had no
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
	"boomerang": {
		"a": {"title": "장난감 바구니", "label": "발사 수", "primitive": "Count", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "멀리 던지기", "label": "왕복 거리", "primitive": "Range", "field": "range", "delta": 30.0},
	},
	"milk": {
		"a": {"title": "한 통 더", "label": "웅덩이 수", "primitive": "Count", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "흥건하게", "label": "웅덩이 크기", "primitive": "Radius", "field": "radius", "delta": 11.0},
	},
	"homing": {
		"a": {"title": "다중 유도", "label": "동시 발사", "primitive": "Count", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "마력 추진", "label": "투사체 속도", "primitive": "ProjectileSpeed", "field": "speed", "delta": 46.0},
	},
	"lightning": {
		"a": {"title": "연쇄 전도", "label": "연쇄", "primitive": "Chain", "field": "jumps", "delta": 1, "integer": true},
		"b": {"title": "확장 도체", "label": "첫 타격 사거리", "primitive": "Range", "field": "range", "delta": 36.0},
	},
	"flame": {
		"a": {"title": "불씨 범람", "label": "화염탄", "primitive": "Count", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "열풍 추진", "label": "투사체 속도", "primitive": "ProjectileSpeed", "field": "speed", "delta": 36.0},
	},
	"frost": {
		"a": {"title": "혹한 영역", "label": "반경", "primitive": "Radius", "field": "radius", "delta": 19.0},
		"b": {"title": "동상", "label": "감속 배율", "primitive": "Slow", "field": "slow", "delta": -0.05, "floor": 0.34, "percent": true},
	},
	"scythe": {
		"a": {"title": "긴 자루", "label": "사거리", "primitive": "Range", "field": "range", "delta": 19.0},
		"b": {"title": "보름베기", "label": "공격 각도", "primitive": "Area", "field": "arc", "delta": 0.17, "cap": PI * 1.5, "degrees": true},
	},
	"chain": {
		"a": {"title": "넓은 파동", "label": "파동 폭", "primitive": "Area", "field": "width", "delta": 9.0},
		"b": {"title": "느슨한 족쇄", "label": "사슬 한계", "primitive": "Range", "field": "chain_length", "delta": 30.0, "target": "run"},
	},
	"orbit": {
		"a": {"title": "파편 증식", "label": "파편 수", "primitive": "Count", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "확장 궤도", "label": "궤도 반경", "primitive": "Radius", "field": "radius", "delta": 14.0},
	},
	"lance": {
		"a": {"title": "장사정", "label": "사거리", "primitive": "Range", "field": "range", "delta": 58.0},
		"b": {"title": "분광", "label": "광선 수", "primitive": "Count", "field": "beams", "delta": 1, "integer": true},
	},
	"mine": {
		"a": {"title": "다중 매설", "label": "매설 수", "primitive": "Count", "field": "count", "delta": 1, "integer": true},
		"b": {"title": "광역 결계", "label": "폭발 반경", "primitive": "Radius", "field": "radius", "delta": 14.0},
	},
	"gravity": {
		"a": {"title": "사건 확대", "label": "붕괴 반경", "primitive": "Radius", "field": "radius", "delta": 22.0},
		"b": {"title": "강한 인력", "label": "인력", "primitive": "Force", "field": "pull", "delta": 45.0,
			"extra_field": "cast_range", "extra_delta": 38.0},
	},
}


## The spec for one weapon's special, or an empty dictionary if it has none.
##
## Given a weapon *state*, the answer depends on the route: a tech whose delivery
## leaves a special with nothing to act on swaps it for its own (see
## WeaponTechCatalog.SPECIAL_OVERRIDES). An enhanced weapon keeps the specials of
## the weapon it grew from wherever the enhanced form still has that field, so
## the last third of a run is not only 화력 and 속도 cards. Given a bare weapon id
## it returns the catalogue special, which is what the lobby and older callers ask.
func _special_spec(weapon: Variant, key: String) -> Dictionary:
	if weapon is Dictionary:
		var state: Dictionary = weapon
		var override := WeaponTechs.special_override(state, key)
		var spec: Dictionary = override if not override.is_empty() \
			else (WEAPON_SPECIALS.get(WeaponGrowthScript.base_id(state), {}) as Dictionary).get(key, {})
		if spec.is_empty():
			return {}
		if bool(state.get("evolved", false)) and String(spec.get("target", "weapon")) != "run" \
				and not state.has(String(spec["field"])):
			return {}
		return spec
	var entry: Dictionary = WEAPON_SPECIALS.get(String(weapon), {})
	return entry.get(key, {})


func _special_current(spec: Dictionary, state: Dictionary) -> float:
	if String(spec.get("target", "weapon")) == "run":
		return chain_max_length
	return float(state.get(String(spec["field"]), 0.0))


## How far a special may take its field, written once per primitive rather than
## once per weapon.
##
## Nothing bounded these at all. A 반경 card added its delta forever, a 발사 수
## card added another projectile forever, and both were then multiplied again by
## 확장의 렌즈 and 분열의 화살통. That is where the late game went: 크림 해일
## reached twelve pools of nearly three times their catalogue radius and covered
## the entire screen, 성좌 관통포 put eighteen bolts in the air per cast, and the
## frame rate went with them. A cap per primitive keeps every weapon's identity —
## a 반경 weapon still roughly doubles its reach over a run — and takes away the
## unbounded tail that made the last third of a run unreadable.
##
## Ratios are of the weapon's *own* catalogue value, so an enhanced form that
## opens wider than its base weapon is allowed to stay wider.
const SPECIAL_CAP_RATIO := {
	"Radius": 1.85,
	"Range": 1.85,
	"Area": 1.85,
	"ProjectileSpeed": 1.70,
	"Force": 1.90,
}
## Counts cannot sensibly be a ratio — a weapon that fires one projectile would
## be capped at one — so they cap on a bonus over the catalogue value instead.
const SPECIAL_CAP_BONUS := {
	"Count": 3,
	"Chain": 3,
}


## The ceiling for one special on one weapon, or INF where it has none.
## An explicit `cap` in the table always wins; 보름베기 stops at a full circle
## for a reason that has nothing to do with its primitive.
func _special_cap(spec: Dictionary, state: Dictionary) -> float:
	if spec.has("cap"):
		return float(spec["cap"])
	# 느슨한 족쇄 moves the pair's leash, not a field on the weapon, so there is
	# no catalogue value to take a share of.
	if String(spec.get("target", "weapon")) == "run" or state.is_empty():
		return INF
	var primitive := String(spec.get("primitive", ""))
	var field := String(spec["field"])
	var baseline: Dictionary = UpgradeValue.baseline(state)
	if not baseline.has(field):
		return INF
	if SPECIAL_CAP_BONUS.has(primitive):
		return float(baseline[field]) + float(SPECIAL_CAP_BONUS[primitive])
	if SPECIAL_CAP_RATIO.has(primitive):
		return float(baseline[field]) * float(SPECIAL_CAP_RATIO[primitive])
	return INF


## The value this special would move its field to, floors and caps applied.
## `growth_scale` is the weapon's stage and route (WeaponGrowth.special_scale); count
## specials always move by exactly their delta.
func _special_next(spec: Dictionary, current: float, growth_scale := 1.0, state: Dictionary = {}) -> float:
	var delta := float(spec["delta"])
	if not bool(spec.get("integer", false)):
		delta *= growth_scale
	var moved := current + delta
	if spec.has("floor"):
		moved = maxf(minf(current, float(spec["floor"])), moved)
	var cap := _special_cap(spec, state)
	if cap < INF:
		# Never lets a cap pull a value that is already past it back down.
		moved = minf(maxf(current, cap), moved)
	return moved


func _special_scale(state: Dictionary, spec: Dictionary, key: String) -> float:
	return 1.0 if bool(spec.get("integer", false)) else WeaponGrowthScript.special_scale(state, key)


## Whether taking this special would actually change anything. Only the bounded
## specials can ever answer no, but asking generically is what keeps a future
## bounded one from quietly becoming a dead card.
func _special_has_room(slot: int, weapon_slot: int, key: String) -> bool:
	var state: Dictionary = weapon_loadouts[slot][weapon_slot]
	var spec := _special_spec(state, key)
	if spec.is_empty():
		return false
	var current := _special_current(spec, state)
	return not is_equal_approx(_special_next(spec, current, _special_scale(state, spec, key), state), current)


## Applies a special to a weapon state dictionary in place. Takes the state
## rather than a loadout index so the recommendation scorer can run it against
## a throwaway copy without touching the real build.
func apply_special_to_state(state: Dictionary, key: String) -> void:
	var spec := _special_spec(state, key)
	if spec.is_empty() or String(spec.get("target", "weapon")) == "run":
		return
	var field := String(spec["field"])
	var growth_scale := _special_scale(state, spec, key)
	var next := _special_next(spec, float(state.get(field, 0.0)), growth_scale, state)
	state[field] = int(round(next)) if bool(spec.get("integer", false)) else next
	# Only where the weapon already reads the field: an enhanced gravity well has
	# no cast range of its own, and inventing one would shrink its reach to 38px.
	if spec.has("extra_field") and state.has(String(spec["extra_field"])):
		var extra := String(spec["extra_field"])
		state[extra] = float(state[extra]) + float(spec["extra_delta"]) * growth_scale
	if bool(spec.get("integer", false)):
		state["damage"] = float(state["damage"]) * (1.0 + WeaponGrowthScript.integer_focus_damage(state, key))


func _special_preview(spec: Dictionary, state: Dictionary, key := "") -> String:
	var current := _special_current(spec, state)
	var next := _special_next(spec, current, _special_scale(state, spec, key) if not key.is_empty() else 1.0, state)
	var line := ""
	if bool(spec.get("integer", false)):
		line = "%s %d → %d" % [String(spec["label"]), int(round(current)), int(round(next))]
		var bonus := WeaponGrowthScript.integer_focus_damage(state, key) if not key.is_empty() else 0.0
		if bonus > 0.0:
			line += "    피해 +%d%%" % roundi(bonus * 100.0)
	elif bool(spec.get("percent", false)):
		line = "%s %.0f%% → %.0f%%" % [String(spec["label"]), current * 100.0, next * 100.0]
	elif bool(spec.get("degrees", false)):
		line = "%s %.0f° → %.0f°" % [String(spec["label"]), rad_to_deg(current), rad_to_deg(next)]
	else:
		line = "%s %.0f → %.0f" % [String(spec["label"]), current, next]
	return line


## Rates only the three or four cards that were actually dealt. The score combines
## expected combat value, current survivability, run timing and the build graph:
## an option that creates a new tier-3 weapon pairing wins a large explicit
## bonus because it immediately unlocks a resonance vote.
## How the screen advises.
##
## A card is starred when it clears an absolute bar *and* stands close to the
## best card in the hand; it is marked against when it is both clearly the worst
## on offer and weak on its own terms. What changed is what those bars are
## measuring.
##
## The scores they compare used to come off two different scales. Every option
## started from a table of hand-tuned values, and then any option with a
## projected damage gain *threw that value away* and took a number derived from
## the gain alone. A treasure that measurably lifted the pair's output by 8%
## therefore scored 25 + 0.08×220 ≈ 43 and lost to 아홉 목숨 리본's flat table
## value of 58, while a weapon card worth 4% scored 34 and was marked against.
## The screen was ranking "what this is worth to the build" against "what this
## does to our damage" as though they were the same number, and the advice moved
## with whichever scale a card happened to land on. The projected gain is a term
## added to a card's standing value now (see _score_upgrade_option), so the two
## halves are summed in one currency instead of replacing each other.
##
## The bars also stayed still while the loadout caps moved. Four weapons and four
## treasures make a slot roughly half again as expensive as it was at six, and
## the biggest thing the screen can tell a survivor is which cards spend one.
const RECOMMEND_MIN_SCORE := 46.0
const RECOMMEND_RELATIVE := 0.84
const DISCOURAGE_MAX_SCORE := 34.0
const DISCOURAGE_RELATIVE := 0.62
## How far apart the best and worst card in a hand have to be before the screen
## says anything at all. Below this the hand is a matter of taste, and a star on
## the top of three cards within a hair of each other is exactly the false
## certainty this pass exists to stop printing.
const ADVICE_MIN_SPREAD := 9.0
## At or below this a card is not weak, it is inert — a fire-rate upgrade on a
## weapon already at the cooldown floor. Those are marked against on their own
## merits rather than by comparison, since there is no hand in which taking one
## is the right move.
const DEAD_CARD_SCORE := 1.0
## Score points one whole doubling of the pair's projected output is worth, and
## the most any single card can collect from that term. The cap is what keeps a
## 40% card from condemning the three ordinary cards next to it: past a point,
## more damage stops being the thing that decides a run.
const COMBAT_SCORE_PER_RATIO := 190.0
const COMBAT_SCORE_CAP := 46.0
## Below this the projected gain rounds to a number nobody should act on, so the
## card keeps the phrase that says what it is *for* instead.
const REASON_MIN_GAIN := 0.02


func _annotate_recommendations(slot: int, choices: Array[Dictionary]) -> void:
	var best_score := -INF
	var worst_score := INF
	for option in choices:
		var rating := _score_upgrade_option(slot, option)
		option["recommendation_score"] = float(rating["score"])
		option["recommendation_reason"] = String(rating["reason"])
		option["recommended"] = false
		option["discouraged"] = false
		best_score = maxf(best_score, float(rating["score"]))
		worst_score = minf(worst_score, float(rating["score"]))
	if choices.size() < 2:
		return

	# Ranked rather than filtered, because the two things the advice must never
	# do are structural rather than numeric: the weakest card in a hand is never
	# starred, and the strongest is never marked against, so a player is never
	# told they lose whatever they pick. Walking from each end and stopping
	# before the other guarantees both without a running tally.
	var ranked: Array[int] = []
	for index in choices.size():
		ranked.append(index)
	ranked.sort_custom(func(first: int, second: int) -> bool:
		return float(choices[first]["recommendation_score"]) > float(choices[second]["recommendation_score"]))

	# A card that provably cannot change anything is marked first and regardless
	# of everything below, because that is a fact about the card rather than a
	# comparison with the cards next to it. Doing it here and not in the ranked
	# pass is the difference between a dead card being named and a dead card
	# losing its mark to a merely mediocre one that happened to rank above it.
	var discouraged := 0
	for rank in range(ranked.size() - 1, 0, -1):
		var dead: Dictionary = choices[ranked[rank]]
		if float(dead["recommendation_score"]) > DEAD_CARD_SCORE:
			continue
		dead["discouraged"] = true
		dead["discouragement_reason"] = _discouragement_reason(slot, dead, float(dead["recommendation_score"]))
		discouraged += 1

	if best_score - worst_score < ADVICE_MIN_SPREAD:
		return

	var recommend_bar := maxf(RECOMMEND_MIN_SCORE, best_score * RECOMMEND_RELATIVE)
	var discourage_bar := minf(DISCOURAGE_MAX_SCORE, best_score * DISCOURAGE_RELATIVE)
	# At most half the hand carries a verdict either way. One star and two
	# crosses on a three-card hand obeys both structural rules above and still
	# reads as the screen telling the player they have already lost; the useful
	# thing to say about three cards is which one, not which two not.
	var verdict_cap := maxi(1, choices.size() / 2)
	var recommended := 0
	for rank in ranked.size() - 1:
		var option: Dictionary = choices[ranked[rank]]
		if recommended >= verdict_cap or float(option["recommendation_score"]) < recommend_bar:
			break
		option["recommended"] = true
		recommended += 1
	for rank in range(ranked.size() - 1, 0, -1):
		var option: Dictionary = choices[ranked[rank]]
		if discouraged >= verdict_cap:
			break
		if bool(option["discouraged"]) or bool(option["recommended"]):
			continue
		if float(option["recommendation_score"]) > discourage_bar:
			break
		option["discouraged"] = true
		option["discouragement_reason"] = _discouragement_reason(slot, option, float(option["recommendation_score"]))
		discouraged += 1


## Why a card is marked against. Deliberately about this build rather than about
## the card — "지금 무기와 맞지 않음" is actionable, "약함" is not.
func _discouragement_reason(slot: int, option: Dictionary, score: float) -> String:
	var upgrade_id := String(option["id"])
	if score <= 1.0:
		return tr("지금은 효과 없음")
	if upgrade_id == "unlock_weapon":
		# The cost of a new weapon is not that it is weak — it is Lv.1 in a
		# loadout of four, and every card it takes afterwards is a card the
		# weapons already working do not get. Which of those two the survivor is
		# actually paying depends on how much room is left.
		var free_weapon_slots: int = WEAPON_LOADOUT_CAP - int(weapon_loadouts[slot].size())
		if free_weapon_slots <= 1:
			return tr("마지막 무기 칸을 씁니다")
		return tr("화력이 %d갈래로 갈립니다") % (weapon_loadouts[slot].size() + 1)
	if upgrade_id == "unlock_treasure":
		var new_effect := _option_icon_id(slot, option)
		if not UpgradeValue.benefits_loadout(weapon_loadouts[slot], new_effect):
			return tr("지금 무기와 맞지 않음")
		if TREASURE_LOADOUT_CAP - treasure_loadouts[slot].size() <= 1:
			return tr("마지막 보물 칸을 씁니다")
		return tr("Lv.1부터 다시 쌓습니다")
	if upgrade_id == "treasure_upgrade":
		var effect := _option_icon_id(slot, option)
		if not UpgradeValue.benefits_loadout(weapon_loadouts[slot], effect):
			return tr("지금 무기와 맞지 않음")
		return tr("성장이 느린 편")
	return tr("다른 카드가 더 급합니다")


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
	var reason := tr("균형 성장")
	match effect_id:
		"choose_tech":
			score = 65.0
			reason = tr("성장 경로 결정")
			# A route whose required treasure is already underway is much safer.
			var synergy_id := String((option["tech"] as Dictionary)["synergy_treasure_id"])
			if _treasure_tier(slot, synergy_id) > 0:
				score += 14.0
				reason = tr("필수 보물 보유")
		"weapon_power":
			score = 50.0
			reason = tr("주력 피해")
		"weapon_rate":
			score = 47.0
			reason = tr("발동 빈도")
		"special_a", "special_b":
			score = 28.0
			reason = tr("제어    편의 강화")
			var w: Dictionary = loadout[int(option["weapon_slot"])]
			if upgrade_id == "special_b" and w.has("speed"):
				score += 30.0 * (70.0 if w["weapon_id"] == "homing" else 55.0) / maxf(1.0, float(w["speed"]))
			if upgrade_id == "special_b" and w["weapon_id"] == "frost":
				score += (1.0 - health_ratio) * 30.0
		"might":
			score = 39.0 + loadout.size() * 7.0
			reason = tr("무기 %d종 강화") % loadout.size()
		"area":
			score = 38.0 + loadout.size() * 4.0
			reason = tr("전체 범위")
		"amount":
			score = 45.0
			reason = tr("투사체 화력")
		"haste":
			score = 43.0 + loadout.size() * 5.0
			reason = tr("전체 발동")
		"projectile_speed":
			score = 36.0
			reason = tr("명중 안정화")
		"duration":
			score = 40.0
			reason = tr("투사체  장판 유지")
		"vitality":
			score = 34.0 + (1.0 - health_ratio) * 48.0
			reason = tr("체력 여유") if health_ratio >= 0.5 else tr("위기 생존")
		"armor":
			score = 35.0 + minf(20.0, elapsed / 6.0) + (1.0 - health_ratio) * 18.0
			reason = tr("접촉 피해 절감")
		"recovery":
			score = 34.0 + (1.0 - health_ratio) * 30.0
			reason = tr("장기 생존")
		"move":
			score = 34.0
			reason = tr("회피와 구조 기동")
		"magnet":
			score = 32.0 + maxf(0.0, 12.0 - progression.level)
			reason = tr("XP 회수")
		"growth":
			score = 52.0 - progression.level * 3.0
			reason = tr("성장 가속")
		"luck":
			score = 40.0 - progression.level * 1.5
			reason = tr("희귀 카드 확률")
		"lifesteal":
			score = 37.0 + (1.0 - health_ratio) * 42.0 + loadout.size() * 2.0
			reason = tr("공격으로 팀 회복")
		"catnip":
			score = 31.0 + (1.0 - health_ratio) * 38.0
			reason = tr("성장 때 팀 회복")
		"bounty_bell":
			score = 55.0 - progression.level * 1.7
			reason = tr("강적 XP 증폭")
		"twin_charm":
			score = 42.0 + maxf(0.0, 10.0 - team_overcharge * 20.0)
			reason = tr("밀착 전투 화력")
		"dash_claw":
			score = 40.0 + minf(12.0, float(run_stats["dashes"]) * 0.5)
			reason = tr("대시를 공격으로")
		"lucky_paw":
			score = 38.0 + (1.0 - health_ratio) * 30.0
			reason = tr("피해 완전 회피")
		"nine_lives":
			score = 58.0 + (1.0 - health_ratio) * 34.0
			reason = tr("치명타 1회 무효")
		"unlock_weapon":
			# A new weapon is worth the most when the survivor has room to grow it
			# and the least when it would take the last socket: at four slots the
			# question is not "is another weapon good" — it is "is this one worth
			# a quarter of the loadout".
			var free_weapon_slots := WEAPON_LOADOUT_CAP - loadout.size()
			score = 32.0 + float(free_weapon_slots) * 7.0
			reason = tr("공격 축 추가")

	# Projected damage is added to what the card is already worth rather than
	# replacing it. It used to overwrite the score outright, which put the two
	# halves of a card's value on separate scales and made the advice depend on
	# which scale the card happened to land on (see _annotate_recommendations).
	# Capped because past a point more damage stops being the thing that decides
	# a run, and a single 40% card should not silently condemn the whole hand.
	var marginal := UpgradeValue.gain(self, slot, option)
	if marginal > 0.0:
		score += minf(COMBAT_SCORE_CAP, marginal * COMBAT_SCORE_PER_RATIO)
		# The score sums both halves; the *reason* only has room for one line, so
		# it prints the projected number whenever that number is large enough to
		# be worth reading and keeps the table's phrase when it is not.
		if marginal >= REASON_MIN_GAIN:
			reason = tr("예상 화력 +%d%%") % roundi(marginal * 100.0)
	elif upgrade_id in ["weapon_power", "weapon_rate"]:
		# A damage or cooldown card that measurably does nothing is not a weak
		# card, it is a dead one, and the screen should say so outright.
		score = 0.0
	# Reward a treasure this loadout can actually use, and prefer one that suits
	# a route somebody already committed to.
	if is_treasure:
		if not UpgradeValue.benefits_loadout(loadout, effect_id):
			score = 5.0
			reason = tr("후속 무기 준비")
		# A route material is the second half of an enhancement and should score
		# accordingly, while still competing for a hand rather than being forced.
		var path := _fusion_path_value(slot, effect_id)
		if not path.is_empty():
			score += float(path["value"])
	if upgrade_id == "unlock_weapon":
		# The same slot pressure the treasure half has always had, applied to the
		# half where it matters more: a weapon taken at Lv.1 into the last socket
		# also competes for every growth card the existing weapons still want.
		var free_weapon_slots := WEAPON_LOADOUT_CAP - loadout.size()
		if free_weapon_slots <= 1:
			score -= 9.0
			reason = tr("%s   마지막 칸") % reason
		else:
			reason = tr("%s   빈 칸 %d") % [reason, free_weapon_slots]
	elif upgrade_id == "unlock_treasure":
		# Committing a slot is worth more while several are open and less when it
		# would spend the last of them on a whim.
		var free_slots := TREASURE_LOADOUT_CAP - treasures.size()
		score += 6.0 if free_slots > 1 else -8.0
		reason = tr("%s   슬롯 %d칸") % [reason, free_slots]
	elif upgrade_id == "treasure_upgrade":
		# Deepening is the payoff for having committed, and a treasure one step
		# from its cap is the cheapest remaining power in the pool.
		var carried: Dictionary = treasures[int(option["treasure_slot"])]
		var tier := int(carried["tier"])
		score += float(tier) * 3.0
		if tier + 1 >= Treasures.MAX_TIER:
			score += 10.0
			reason = tr("%s   최종 티어") % reason
		else:
			reason = "%s   Lv.%d" % [reason, tier + 1]

	var new_resonance := _new_resonance_from_option(slot, option)
	if not new_resonance.is_empty():
		score += 120.0
		reason = tr("공명 해금   %s") % new_resonance
	elif int(option.get("weapon_slot", -1)) >= 0:
		var weapon: Dictionary = loadout[int(option["weapon_slot"])]
		if int(weapon.get("tier", 1)) == Evolutions.EVOLUTION_TIER - 1 \
				and not bool(weapon.get("evolved", false)) \
				and _treasure_tier(slot, String(weapon.get("tech_synergy_treasure_id", ""))) >= Evolutions.REQUIRED_TREASURE_TIER:
			score += 34.0
			reason = tr("다음 카드로 Lv.%d 진화") % Evolutions.EVOLUTION_TIER
		elif int(weapon.get("tier", 1)) == WeaponGrowthScript.TECH_UNLOCK_TIER - 1 and String(weapon.get("tech_id", "")).is_empty():
			# The card that opens the route decision is worth a little more than
			# its numbers: every card after it is priced by the route.
			score += 10.0
			reason = tr("레벨 %d   테크 선택") % WeaponGrowthScript.TECH_UNLOCK_TIER
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
	# Starting and newly learned weapons begin modestly; committing upgrade tiers
	# overtakes the old curve, while a fusion replaces this scaled base entirely.
	state["damage"] = float(state["damage"]) * BASE_WEAPON_DAMAGE_SCALE
	# What this weapon's interval was before anything was spent on it. Every
	# speed floor is a share of this, so a slow weapon stays slow however many
	# 속도 cards it is handed (WeaponGrowth.RATE_MIN_RATIO).
	state["base_cooldown"] = float((character["weapon"] as Dictionary).get("cooldown", 1.0))
	state["weapon_id"] = character["weapon_id"]
	state["base_weapon_id"] = character["weapon_id"]
	state["weapon_name"] = character["weapon_name"]
	state["tags"] = (character["tags"] as Array).duplicate()
	state["color"] = character["color"]
	state["source_character"] = character["name"]
	return state


## The first growth axis a route names that would actually move the weapon.
func _route_lead_axis(slot: int, weapon_slot: int, route: Dictionary) -> String:
	for axis: String in route.get("upgrades", []):
		if not axis.begins_with("special_") or _special_has_room(slot, weapon_slot, axis.substr(axis.length() - 1)):
			return axis
	return "weapon_power"


## What a treasure is worth to a route waiting for it. Before the required tier
## it is build-completing value; afterwards only its ordinary synergy remains.
func _fusion_path_value(slot: int, treasure_id: String) -> Dictionary:
	var best := {}
	var best_progress := -1.0
	for weapon: Dictionary in weapon_loadouts[slot]:
		if String(weapon.get("tech_synergy_treasure_id", "")) != treasure_id:
			continue
		var progress := minf(1.0, float(int(weapon.get("tier", 1))) / float(Evolutions.EVOLUTION_TIER))
		if progress <= best_progress:
			continue
		best_progress = progress
		var waiting := _treasure_tier(slot, treasure_id) < Evolutions.REQUIRED_TREASURE_TIER \
				and not bool(weapon.get("evolved", false))
		best = {"value": (42.0 + progress * 38.0) if waiting else (12.0 + progress * 26.0)}
	return best


func _new_resonance_from_option(slot: int, option: Dictionary) -> String:
	var before := resonance_system.get_candidates_for_loadouts(weapon_loadouts[0], weapon_loadouts[1])
	var known: Dictionary = {}
	for candidate in before:
		known[String(candidate["id"])] = true
	var preview: Array = [weapon_loadouts[0].duplicate(true), weapon_loadouts[1].duplicate(true)]
	var preview_treasures: Array = [treasure_loadouts[0].duplicate(true), treasure_loadouts[1].duplicate(true)]
	var option_id := String(option["id"])
	if option_id == "unlock_weapon":
		var new_state := _build_weapon_state(option["character"] as Dictionary)
		if option.has("tech"):
			WeaponTechs.apply_to_state(new_state, option["tech"] as Dictionary)
		preview[slot].append(new_state)
	elif option_id == "unlock_treasure":
		preview_treasures[slot].append(Treasures.build_state(option["treasure"] as Dictionary))
	elif option_id == "treasure_upgrade":
		var treasure_slot := int(option.get("treasure_slot", -1))
		if treasure_slot < 0:
			return ""
		var grown_treasure: Dictionary = preview_treasures[slot][treasure_slot]
		grown_treasure["tier"] = int(grown_treasure.get("tier", 1)) + 1
	elif option_id == "choose_tech":
		var route_slot := int(option.get("weapon_slot", -1))
		if route_slot < 0:
			return ""
		WeaponTechs.apply_to_state(preview[slot][route_slot], option["tech"] as Dictionary)
	else:
		var weapon_slot := int(option.get("weapon_slot", -1))
		if weapon_slot < 0:
			return ""
		var grown: Dictionary = preview[slot][weapon_slot]
		grown["tier"] = int(grown.get("tier", 1)) + 1

	# Either half can be the last recipe card. Promote every recipe completed by
	# the preview so weapon Lv.7 and treasure Lv.4 receive the same recommendation.
	for player_slot in 2:
		for weapon_slot in preview[player_slot].size():
			var grown: Dictionary = preview[player_slot][weapon_slot]
			if bool(grown.get("evolved", false)) or int(grown.get("tier", 1)) < Evolutions.EVOLUTION_TIER:
				continue
			var required_id := String(grown.get("tech_synergy_treasure_id", ""))
			if required_id.is_empty() or String(grown.get("tech_id", "")).is_empty():
				continue
			var material_tier := 0
			for carried: Dictionary in preview_treasures[player_slot]:
				if String(carried.get("id", "")) == required_id:
					material_tier = int(carried.get("tier", 1))
					break
			if material_tier < Evolutions.REQUIRED_TREASURE_TIER:
				continue
			var evolution := Evolutions.for_base(String(grown.get("base_weapon_id", grown["weapon_id"])))
			if not evolution.is_empty():
				preview[player_slot][weapon_slot] = Evolutions.build_state(evolution, grown)
	for candidate in resonance_system.get_candidates_for_loadouts(preview[0], preview[1]):
		if not known.has(String(candidate["id"])):
			return String(candidate["name"])
	return ""


## The resonance the two highlighted routes will eventually produce. Preview
## states are promoted to their final forms here because resonance itself only
## activates after both weapons are finished.
func _growth_resonance_preview() -> Dictionary:
	var preview: Array = [
		weapon_loadouts[0].duplicate(true),
		weapon_loadouts[1].duplicate(true),
	]
	for slot in 2:
		var choices: Array = p1_choices if slot == 0 else p2_choices
		var selected := selected_upgrade_indices[slot]
		if selected < 0:
			selected = upgrade_cursors[slot]
		if selected < 0 or selected >= choices.size():
			continue
		var option: Dictionary = choices[selected]
		var option_id := String(option.get("id", ""))
		if option_id == "choose_tech":
			WeaponTechs.apply_to_state(
				preview[slot][int(option["weapon_slot"])], option["tech"] as Dictionary)
		elif option_id == "unlock_weapon":
			var state := _build_weapon_state(option["character"] as Dictionary)
			if option.has("tech"):
				WeaponTechs.apply_to_state(state, option["tech"] as Dictionary)
			preview[slot].append(state)
	for slot in 2:
		for weapon_index in preview[slot].size():
			var state: Dictionary = preview[slot][weapon_index]
			if bool(state.get("evolved", false)) or String(state.get("tech_id", "")).is_empty():
				continue
			var evolution := Evolutions.for_base(String(state.get("base_weapon_id", state["weapon_id"])))
			if not evolution.is_empty():
				preview[slot][weapon_index] = Evolutions.build_state(evolution, state)
	var candidates := resonance_system.rank_candidates(
		resonance_system.get_candidates_for_loadouts(preview[0], preview[1]), 1)
	return {} if candidates.is_empty() else candidates[0]


func _upgrade_preview(slot: int, option: Dictionary) -> String:
	var upgrade_id := String(option["id"])
	if upgrade_id == "choose_tech":
		var tech: Dictionary = option["tech"]
		var state: Dictionary = weapon_loadouts[slot][int(option["weapon_slot"])].duplicate(true)
		WeaponTechs.apply_to_state(state, tech)
		var evolution := Evolutions.for_base(String(state.get("base_weapon_id", state["weapon_id"])))
		var synergy := Treasures.by_id(String(tech["synergy_treasure_id"]))
		return tr("%s\n특화 %s +1    필수 보물 %s Lv.%d\n무기 Lv.%d 진화    %s") % [
			_tech_focus(tech), _tech_axes_text(state, tech), tr(String(synergy.get("name", "없음"))),
			Evolutions.REQUIRED_TREASURE_TIER, Evolutions.EVOLUTION_TIER,
			tr(String(evolution.get("weapon_name", "최종 진화"))),
		]
	if upgrade_id == "unlock_weapon":
		var character: Dictionary = option["character"]
		var routes: Array[String] = []
		for route in WeaponTechs.for_weapon(String(character["weapon_id"])):
			routes.append(tr(String(route["name"])))
		return tr("%s\n레벨 %d에 테크 선택    %s") % [
			tr(String(EditorialUI.PLAYSTYLE.get(String(character["weapon_id"]), "자동 공격"))),
			WeaponGrowthScript.TECH_UNLOCK_TIER, " / ".join(routes)]
	if upgrade_id == "unlock_treasure":
		var treasure: Dictionary = option["treasure"]
		return tr("%s
획득 후 보물 %d/%d칸 사용") % [
			Treasures.tier_text(treasure, 1), treasure_loadouts[slot].size() + 1, TREASURE_LOADOUT_CAP
		]
	if upgrade_id == "treasure_upgrade":
		var carried: Dictionary = treasure_loadouts[slot][int(option["treasure_slot"])]
		var next_tier := int(carried["tier"]) + 1
		return tr("%s
레벨 %d → %d") % [
			Treasures.tier_text(Treasures.by_id(String(carried["id"])), next_tier), int(carried["tier"]), next_tier
		]
	var weapon_slot := int(option["weapon_slot"])
	var state: Dictionary = weapon_loadouts[slot][weapon_slot]
	var tier := int(state.get("tier", 1))
	var tier_hint := tr("\n레벨 %d → %d") % [tier, mini(Evolutions.WEAPON_MAX_TIER, tier + 1)]
	if tier + 1 >= Evolutions.WEAPON_MAX_TIER:
		tier_hint = tr("\n레벨 %d — 최대 강화") % Evolutions.WEAPON_MAX_TIER
	elif tier + 1 == Evolutions.EVOLUTION_TIER and not bool(state.get("evolved", false)):
		var required_id := String(state.get("tech_synergy_treasure_id", ""))
		var required := Treasures.by_id(required_id)
		if _treasure_tier(slot, required_id) >= Evolutions.REQUIRED_TREASURE_TIER:
			tier_hint = tr("\n레벨 %d — 이 카드로 진화") % Evolutions.EVOLUTION_TIER
		else:
			tier_hint = tr("\n레벨 %d — %s Lv.%d 필요") % [Evolutions.EVOLUTION_TIER,
				tr(String(required.get("name", "보물"))), Evolutions.REQUIRED_TREASURE_TIER]
	elif tier + 1 == WeaponGrowthScript.TECH_UNLOCK_TIER and String(state.get("tech_id", "")).is_empty():
		tier_hint = tr("\n레벨 %d — 테크 선택 가능") % WeaponGrowthScript.TECH_UNLOCK_TIER
	var focus := WeaponGrowthScript.focus_label(state, upgrade_id)
	if not focus.is_empty():
		tier_hint += "    " + focus
	match upgrade_id:
		"weapon_power":
			return tr("피해 %.1f → %.1f%s\n한 번에 더 큰 피해") % [float(state["damage"]), float(state["damage"]) * WeaponGrowthScript.power_step(state), tier_hint]
		"weapon_rate":
			return tr("발동 %.2f초 → %.2f초%s\n더 자주 공격") % [float(state["cooldown"]), WeaponGrowthScript.next_cooldown(state), tier_hint]
		"special_a", "special_b":
			var key := upgrade_id.substr(upgrade_id.length() - 1)
			var spec := _special_spec(state, key)
			if not spec.is_empty():
				return _special_preview(spec, state, key) + tier_hint
	return tr("현재 능력을 강화합니다.")


## What a growth card says, split by role so the card can set each part apart
## instead of printing one paragraph. `_upgrade_preview` is the same information
## as a single line of text (tooltips, the fusion screen and the tests read it);
## this is what the face of the card is built from.
##
##   name     the upgrade itself — "마력 증폭", a treasure, a route
##   subject  what it applies to — the weapon, or the treasure's stat
##   level    [from, to]; from 0 is a new piece of gear
##   stats    rows of {label, from, to, post}: from is what the survivor has now,
##            to is what they will have after taking the card. A treasure row is
##            the running total rather than the step, since the total is what a
##            player compares against the rest of their build.
##   tags     short chips: {text, kind} with kind one of focus / off / evolve /
##            tech / max / shared
##   effect   one line of what the card does, in words
##   synergy  what this pairs well with — set apart because it is advice about
##            the build, not a property of the card
##   note     small print: slots used, where a route leads
## What a special does, in words, by the primitive it grows. The row above it
## says how much; this says what the player will see change.
const SPECIAL_EFFECTS := {
	"Count": "한 번에 더 많이",
	"Range": "더 멀리 닿는 공격",
	"Radius": "더 넓은 영역",
	"Area": "더 넓게 휩쓰는 공격",
	"ProjectileSpeed": "더 빠르게 날아가는 투사체",
	"Chain": "더 많은 적에게 연쇄",
	"Slow": "적을 더 강하게 늦춤",
	"Pierce": "더 많은 적을 꿰뚫음",
	"Force": "적을 더 세게 밀쳐냄",
}


func _card_sections(slot: int, option: Dictionary) -> Dictionary:
	var upgrade_id := String(option["id"])
	var sections := {"name": "", "subject": "", "level": [], "stats": [], "tags": [],
		"effect": "", "synergy": "", "note": ""}
	match upgrade_id:
		"choose_tech":
			var tech: Dictionary = option["tech"]
			var state: Dictionary = weapon_loadouts[slot][int(option["weapon_slot"])].duplicate(true)
			var axes_text := _tech_axes_text(state, tech)
			WeaponTechs.apply_to_state(state, tech)
			var evolution := Evolutions.for_base(String(state.get("base_weapon_id", state["weapon_id"])))
			var synergy := Treasures.by_id(String(tech["synergy_treasure_id"]))
			sections["name"] = tr(String(tech["name"]))
			sections["subject"] = tr(String(state["weapon_name"]))
			sections["effect"] = _tech_focus(tech)
			sections["tags"] = [{"text": tr("특화 %s +1") % axes_text, "kind": "focus"}]
			if not synergy.is_empty():
				sections["synergy"] = tr("필수 보물 · %s Lv.%d") % [tr(String(synergy["name"])), Evolutions.REQUIRED_TREASURE_TIER]
			sections["note"] = tr("무기 Lv.%d 진화 → %s") % [Evolutions.EVOLUTION_TIER, tr(String(evolution.get("weapon_name", "최종 진화")))]
			return sections
		"unlock_weapon":
			var character: Dictionary = option["character"]
			var routes: Array[String] = []
			for route in WeaponTechs.for_weapon(String(character["weapon_id"])):
				routes.append(tr(String(route["name"])))
			sections["name"] = tr(String(character["weapon_name"]))
			sections["subject"] = tr("새 무기")
			sections["level"] = [0, 1]
			sections["effect"] = _spaced(tr(String(EditorialUI.PLAYSTYLE.get(String(character["weapon_id"]), "자동 공격"))))
			sections["tags"] = [{"text": tr("Lv.%d 테크 선택") % WeaponGrowthScript.TECH_UNLOCK_TIER, "kind": "tech"}]
			if not routes.is_empty():
				sections["note"] = " / ".join(routes)
			sections["note"] = _join_note(String(sections["note"]),
				tr("무기 칸 %d/%d") % [weapon_loadouts[slot].size() + 1, WEAPON_LOADOUT_CAP])
			return sections
		"unlock_treasure", "treasure_upgrade":
			var treasure: Dictionary
			var tier := 0
			if upgrade_id == "unlock_treasure":
				treasure = option["treasure"]
			else:
				var carried: Dictionary = treasure_loadouts[slot][int(option["treasure_slot"])]
				treasure = Treasures.by_id(String(carried["id"]))
				tier = int(carried["tier"])
			sections["name"] = tr(String(treasure["name"]))
			sections["subject"] = tr("%s 보물") % tr(String(treasure.get("stat", "")))
			sections["level"] = [tier, tier + 1]
			var row := _treasure_row(treasure, tier, tier + 1)
			if row.is_empty():
				sections["effect"] = _spaced(tr(String(treasure["text"])))
			else:
				sections["stats"] = [row]
			var tags: Array = []
			if bool(treasure.get("shared", false)):
				tags.append({"text": tr("팀 공유"), "kind": "shared"})
			if tier + 1 >= Treasures.MAX_TIER:
				tags.append({"text": tr("최대 레벨"), "kind": "max"})
			sections["tags"] = tags
			for owned: Dictionary in weapon_loadouts[slot]:
				if String(owned.get("tech_synergy_treasure_id", "")) == String(treasure["id"]):
					sections["synergy"] = tr("%s 진화 재료") % tr(String(owned["weapon_name"]))
					break
			if upgrade_id == "unlock_treasure":
				sections["note"] = tr("보물 칸 %d/%d") % [treasure_loadouts[slot].size() + 1, TREASURE_LOADOUT_CAP]
			return sections

	var state: Dictionary = weapon_loadouts[slot][int(option["weapon_slot"])]
	var tier := int(state.get("tier", 1))
	sections["subject"] = tr(String(state["weapon_name"]))
	sections["level"] = [tier, mini(Evolutions.WEAPON_MAX_TIER, tier + 1)]
	var tags: Array = []
	if tier + 1 >= Evolutions.WEAPON_MAX_TIER:
		tags.append({"text": tr("최대 강화"), "kind": "max"})
	elif tier + 1 == Evolutions.EVOLUTION_TIER and not bool(state.get("evolved", false)):
		var required_id := String(state.get("tech_synergy_treasure_id", ""))
		if _treasure_tier(slot, required_id) >= Evolutions.REQUIRED_TREASURE_TIER:
			tags.append({"text": tr("이 카드로 진화"), "kind": "evolve"})
		else:
			var required := Treasures.by_id(required_id)
			tags.append({"text": tr("%s Lv.%d 필요") % [tr(String(required.get("name", "보물"))),
				Evolutions.REQUIRED_TREASURE_TIER], "kind": "tech"})
	elif tier + 1 == WeaponGrowthScript.TECH_UNLOCK_TIER and String(state.get("tech_id", "")).is_empty():
		tags.append({"text": tr("테크 선택 가능"), "kind": "tech"})
	var focus := WeaponGrowthScript.focus_label(state, upgrade_id)
	if not focus.is_empty():
		tags.append({"text": tr(focus), "kind": "focus" if focus == "테크 특화" else "off"})
	sections["tags"] = tags
	match upgrade_id:
		"weapon_power":
			sections["name"] = tr("마력 증폭")
			sections["stats"] = [{"label": tr("피해"), "from": "%.1f" % float(state["damage"]),
				"to": "%.1f" % (float(state["damage"]) * WeaponGrowthScript.power_step(state)), "post": ""}]
			sections["effect"] = tr("한 번에 더 큰 피해")
		"weapon_rate":
			sections["name"] = tr("고속 시전")
			sections["stats"] = [{"label": tr("발동 간격"), "from": tr("%.2f초") % float(state["cooldown"]),
				"to": tr("%.2f초") % WeaponGrowthScript.next_cooldown(state), "post": ""}]
			sections["effect"] = tr("더 자주 공격")
		"special_a", "special_b":
			var key := upgrade_id.substr(upgrade_id.length() - 1)
			var spec := _special_spec(state, key)
			sections["name"] = tr(String(spec.get("title", "특성")))
			if not spec.is_empty():
				sections["stats"] = _special_rows(spec, state, key)
				sections["effect"] = tr(String(SPECIAL_EFFECTS.get(String(spec.get("primitive", "")), "")))
	var partner := _fusion_partner_for_option(slot, option)
	if not partner.is_empty():
		sections["synergy"] = tr("%s 조합") % tr(String(partner["name"]))
	return sections


## `_special_preview` as stat rows: the field itself, and for a focused integer
## special the damage it adds on top.
func _special_rows(spec: Dictionary, state: Dictionary, key: String) -> Array:
	var current := _special_current(spec, state)
	var next := _special_next(spec, current, _special_scale(state, spec, key), state)
	var row := {"label": tr(String(spec["label"])), "post": ""}
	if bool(spec.get("integer", false)):
		row["from"] = "%d" % int(round(current))
		row["to"] = "%d" % int(round(next))
	elif bool(spec.get("percent", false)):
		row["from"] = "%.0f%%" % (current * 100.0)
		row["to"] = "%.0f%%" % (next * 100.0)
	elif bool(spec.get("degrees", false)):
		row["from"] = "%.0f°" % rad_to_deg(current)
		row["to"] = "%.0f°" % rad_to_deg(next)
	else:
		row["from"] = "%.0f" % current
		row["to"] = "%.0f" % next
	var rows: Array = [row]
	if bool(spec.get("integer", false)):
		var bonus := WeaponGrowthScript.integer_focus_damage(state, key)
		if bonus > 0.0:
			rows.append({"label": tr("추가 피해"), "from": "", "to": "+%d%%" % roundi(bonus * 100.0), "post": ""})
	return rows


## A treasure's line as a before/after row of running totals. The catalog writes
## each effect as a sentence with one {v} in it ("공격력 +{v}%"), so the row keeps
## the sentence and puts the two totals where the number was. Empty for the
## effects that carry no number (기사회생).
func _treasure_row(treasure: Dictionary, from_tier: int, to_tier: int) -> Dictionary:
	var treasure_id := String(treasure["id"])
	if treasure_id == "amount":
		# Half a projectile a tier, counted whole where a volley is fired.
		return {"label": tr("발사체"), "from": "+" + String.num(0.5 * from_tier, 1) if from_tier > 0 else "",
			"to": "+" + String.num(0.5 * to_tier, 1), "post": tr("(정수만큼 발사)")}
	var text := tr(String(treasure["text"]))
	var pattern := RegEx.create_from_string("([+-]?)\\{v\\}(%p|%|초|s)?")
	var found := pattern.search(text)
	if found == null:
		return {}
	var unit_value := float(treasure["value"]) * float(treasure.get("display", 1.0))
	var total := func(tier: int) -> String:
		return found.get_string(1) + Treasures._number(unit_value * Treasures.effective_tiers(treasure_id, tier)) + found.get_string(2)
	return {
		"label": _spaced(text.substr(0, found.get_start()).strip_edges()),
		"from": total.call(from_tier) if from_tier > 0 else "",
		"to": total.call(to_tier),
		"post": _spaced(text.substr(found.get_end()).strip_edges()),
	}


## The catalog separates clauses with runs of spaces, which read as a gap in a
## sentence once the text is wrapped on a card.
func _spaced(text: String) -> String:
	return RegEx.create_from_string("\\s{2,}").sub(text, " · ", true)


func _join_note(first: String, second: String) -> String:
	return second if first.is_empty() else first + "  ·  " + second


## The names of the growth axes a route leans on, as the card and the lobby say
## them: "화력 · 연쇄" rather than a list of upgrade ids.
func _tech_axes_text(state: Dictionary, tech: Dictionary) -> String:
	var axes: Array = tech.get("upgrades", [])
	if axes.size() >= 4:
		return tr("균형")
	var preview := state.duplicate()
	WeaponTechs.apply_to_state(preview, tech)
	var names: Array[String] = []
	for axis: String in axes:
		match axis:
			"weapon_power": names.append(tr("화력"))
			"weapon_rate": names.append(tr("속도"))
			_:
				var spec := _special_spec(preview, axis.substr(axis.length() - 1))
				names.append(tr(String(spec.get("label", spec.get("title", "고유")))))
	return " · ".join(names)


func _tech_focus(tech: Dictionary) -> String:
	return tr(String(tech.get("behavior_description", tech.get("description", "자유 성장"))))


func _handle_level_up_input() -> void:
	if level_up_input_delay > 0.0:
		level_up_input_delay = maxf(0.0, level_up_input_delay - get_physics_process_delta_time())
		if level_up_input_delay <= 0.0:
			_refresh_level_up_ui()
		return
	if ai_companion and selected_upgrade_indices[1] == -1:
		_select_upgrade(2, CompanionController.choose(self, 1, p2_choices))
		if not level_up_active:
			return
	for slot in 2:
		if (online.is_host() and slot == 1) or (ai_companion and slot == 1):
			continue
		var player_index := slot + 1
		var prefix := "p1_select_" if player_index == 1 else "p2_select_"
		var choices := p1_choices if player_index == 1 else p2_choices
		if selected_upgrade_indices[slot] != -1:
			if selected_upgrade_indices[slot] >= 0 and Input.is_action_just_pressed(prefix + "cancel") and selected_upgrade_indices[1 - slot] < 0:
				selected_upgrade_indices[slot] = -1
				feedback.play_cue("cancel")
				_refresh_level_up_ui()
			continue
		if slot != focused_growth_slot():
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


## The previous draw's keys are already excluded by _get_upgrade_choices, so a
## reroll is guaranteed to move — a reroll that can hand back the same three
## cards is worse than no reroll at all.
func _reroll_choices(player_index: int) -> void:
	var slot := player_index - 1
	var current := p1_choices if player_index == 1 else p2_choices
	if not current.is_empty() and current.all(func(option: Dictionary) -> bool: return String(option["id"]) == "choose_tech"):
		return
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
	if selected_upgrade_indices[slot] != -1:
		return
	feedback.play_cue("confirm")
	selected_upgrade_indices[slot] = choice_index
	upgrade_cursors[slot] = choice_index
	_refresh_level_up_ui()
	online.send_growth_state()
	if selected_upgrade_indices[0] != -1 and selected_upgrade_indices[1] != -1:
		if selected_upgrade_indices[0] >= 0:
			_apply_upgrade(0, p1_choices[selected_upgrade_indices[0]])
		if selected_upgrade_indices[1] >= 0:
			_apply_upgrade(1, p2_choices[selected_upgrade_indices[1]])
		# A card that completed either half of a recipe enhances it here, with no
		# second card and no confirmation: the pair already paid for both pieces.
		for slot_index in 2:
			_apply_pending_evolutions(slot_index)
		# Any enhancement the two picks produced is shown before the run is
		# handed back.
		if showcase_queue.is_empty():
			_after_personal_upgrade_choices()
		else:
			level_overlay.visible = false
			_play_showcase_queue(_after_personal_upgrade_choices)


func _apply_upgrade(player_slot: int, option: Dictionary) -> void:
	var upgrade_id := String(option["id"])
	if upgrade_id == "choose_tech":
		weapon_controller.clear_sustained_for_player(player_slot)
		var route_slot := int(option["weapon_slot"])
		var route: Dictionary = option["tech"]
		WeaponTechs.apply_to_state(weapon_loadouts[player_slot][route_slot], route)
		# Choosing a route takes a whole growth hand, so it pays one step on the
		# route's own lead axis. Without it every weapon cost a card more than it
		# used to, and over a run that was measured as a third fewer enhancements.
		_apply_upgrade(player_slot, {"id": _route_lead_axis(player_slot, route_slot, route), "weapon_slot": route_slot})
		return
	if upgrade_id == "unlock_weapon":
		var character: Dictionary = option["character"]
		var weapon_id := String(character["weapon_id"])
		# One slot per weapon, enforced where the slot is actually taken — the
		# same rule treasures have had, for the same reason. The offer paths all
		# filter out what the survivor carries, but they filter against a loadout
		# read at the moment the card was dealt: a chest reward landing between
		# the deal and the pick, a hand resolved after an enhancement renamed a
		# slot, or a loadout arriving from the host can all present an id that is
		# already carried. The old code appended regardless, which is how a
		# survivor ended up with 성좌 관통포 in one slot and a fresh Lv.1 유도탄
		# in another.
		#
		# A repeat pays a tier on the copy they already have instead. That is
		# what the card was offering them anyway, and it means a stale card is
		# never simply thrown away.
		for carried_index in weapon_loadouts[player_slot].size():
			var carried_weapon: Dictionary = weapon_loadouts[player_slot][carried_index]
			if String(carried_weapon.get("base_weapon_id", carried_weapon["weapon_id"])) != weapon_id \
					and String(carried_weapon["weapon_id"]) != weapon_id:
				continue
			if not WeaponGrowthScript.needs_tech(carried_weapon):
				_apply_upgrade(player_slot, {"id": "weapon_power", "weapon_slot": carried_index})
			return
		# The cap is checked here too, not only where cards are offered, so no
		# stale card can push a loadout past the number of sockets the HUD draws.
		if weapon_loadouts[player_slot].size() >= WEAPON_LOADOUT_CAP:
			return
		var new_state := _build_weapon_state(character)
		# Older callers (chest fixtures, saved tests) may still hand a route in.
		if option.has("tech"):
			WeaponTechs.apply_to_state(new_state, option["tech"] as Dictionary)
		weapon_loadouts[player_slot].append(new_state)
		attack_timers[player_slot].append(0.2)
		return
	if upgrade_id == "unlock_treasure":
		var treasure: Dictionary = option["treasure"]
		var treasure_id := String(treasure["id"])
		# One slot per treasure, enforced where the slot is actually taken; see
		# the weapon half above for why the offer-side filter is not enough on
		# its own.
		var carried_slot := -1
		for index in treasure_loadouts[player_slot].size():
			if String(treasure_loadouts[player_slot][index]["id"]) == treasure_id:
				carried_slot = index
				break
		if carried_slot >= 0:
			var owned: Dictionary = treasure_loadouts[player_slot][carried_slot]
			if int(owned["tier"]) < Treasures.MAX_TIER:
				owned["tier"] = int(owned["tier"]) + 1
				_apply_attribute(player_slot, treasure_id, int(owned["tier"]))
			return
		if treasure_loadouts[player_slot].size() >= TREASURE_LOADOUT_CAP:
			return
		var state := Treasures.build_state(treasure)
		treasure_loadouts[player_slot].append(state)
		_apply_attribute(player_slot, treasure_id, 1)
		return
	if upgrade_id == "treasure_upgrade":
		var carried: Dictionary = treasure_loadouts[player_slot][int(option["treasure_slot"])]
		carried["tier"] = int(carried["tier"]) + 1
		_apply_attribute(player_slot, String(carried["id"]), int(carried["tier"]))
		return
	var weapon_slot := int(option["weapon_slot"])
	var state: Dictionary = weapon_loadouts[player_slot][weapon_slot]
	# A weapon waiting on its route takes no more tiers until it has one; the
	# growth hand asks for the route first, and a chest never offers the card.
	if WeaponGrowthScript.needs_tech(state):
		return
	match upgrade_id:
		"weapon_power":
			state["damage"] = float(state["damage"]) * WeaponGrowthScript.power_step(state)
		"weapon_rate":
			state["cooldown"] = WeaponGrowthScript.next_cooldown(state)
		"special_a", "special_b":
			var key := upgrade_id.substr(upgrade_id.length() - 1)
			var spec := _special_spec(state, key)
			if not spec.is_empty() and String(spec.get("target", "weapon")) == "run":
				chain_max_length = _special_next(spec, chain_max_length, _special_scale(state, spec, key))
			else:
				apply_special_to_state(state, key)
	if upgrade_id in ["weapon_power", "weapon_rate", "special_a", "special_b"]:
		state["tier"] = mini(Evolutions.WEAPON_MAX_TIER, int(state.get("tier", 1)) + 1)


## Applies the step of a treasure into `tier` and reports whether it handled the
## id, so _apply_upgrade can fall through to the weapon-slot path for everything
## else. How much a step is worth grows with the tier (TreasureCatalog.TIER_WEIGHTS).
func _apply_attribute(player_slot: int, upgrade_id: String, tier := 1) -> bool:
	var player := players[player_slot]
	var step := Treasures.increment(upgrade_id, tier)
	match upgrade_id:
		"move":
			player.move_speed *= 1.0 + step
		"vitality":
			player.max_health += step
			player.heal(step)
		"might":
			player.might += step
		"area":
			player.area += step
		"amount":
			player.amount += step
		"haste":
			player.haste = maxf(HASTE_FLOOR, player.haste - step)
		"projectile_speed":
			player.projectile_speed += step
		"duration":
			player.duration += step
		"armor":
			player.armor += step
		"recovery":
			player.recovery += step
		"crit":
			player.crit_chance = minf(CRIT_CAP, player.crit_chance + step)
		"pierce":
			player.pierce += roundi(step)
		"thorns":
			player.thorns += step
		"resolve":
			player.resolve += step
		"overcharge", "greed", "magnet", "growth", "luck", "lifesteal", "catnip", "bounty_bell", "twin_charm", "dash_claw":
			# Shared effects are recomputed from what the pair is carrying rather
			# than added to as they are picked, because what one copy is worth now
			# depends on whether the other survivor is holding one too.
			_recompute_team_effects()
			if upgrade_id == "lifesteal":
				# A newly taken bell works on the very next hit rather than waiting
				# for its token bucket to fill from zero.
				lifesteal_charge = minf(
					_lifesteal_tiers() * LIFESTEAL_BURST_CAP_PER_TIER,
					lifesteal_charge + LIFESTEAL_BURST_CAP_PER_TIER)
		"lucky_paw":
			player.dodge_chance = minf(0.45, player.dodge_chance + step)
		"nine_lives":
			player.second_chances += roundi(step)
		_:
			return false
	return true


const HASTE_FLOOR := 0.6
const CRIT_CAP := 0.60


func focused_growth_slot() -> int:
	if online != null and online.is_client():
		return 1
	if (online != null and online.is_host()) or ai_companion:
		return 0
	return 0 if selected_upgrade_indices[0] == -1 else 1


func _refresh_level_up_ui() -> void:
	CoopSelectionUI.restore(self)
	_refresh_player_cards(1)
	_refresh_player_cards(2)
	CoopSelectionUI.refresh(self)
	_apply_text_scale_to(level_overlay, 1.14 if settings.large_text_enabled else 1.0)


## Per-hand state the cards do not paint themselves: tooltips and the reroll
## button. The cards are laid out and painted by NeonGrowthUI.
func _refresh_player_cards(player_index: int) -> void:
	EditorialUI.refresh_growth(self, player_index - 1)


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
	if String(option.get("id", "")) == "unlock_weapon":
		return String((option["character"] as Dictionary)["weapon_id"])
	var weapon_slot := int(option.get("weapon_slot", -1))
	if weapon_slot >= 0 and weapon_slot < weapon_loadouts[slot].size():
		return String(weapon_loadouts[slot][weapon_slot]["weapon_id"])
	return ""


## The top-right seal never exposes a recipe the player has not assembled.
## Once both ingredients are carried, it shows the *other* owned ingredient,
## which reads naturally as “combine this with that” without naming the result.
func _fusion_partner_for_option(slot: int, option: Dictionary) -> Dictionary:
	var option_id := String(option.get("id", ""))
	if option_id in ["unlock_weapon", "unlock_treasure"]:
		return {}
	var treasure_id := ""
	var weapon_id := ""
	if option_id == "treasure_upgrade":
		var treasure_slot := int(option.get("treasure_slot", -1))
		if treasure_slot >= 0 and treasure_slot < treasure_loadouts[slot].size():
			treasure_id = String(treasure_loadouts[slot][treasure_slot]["id"])
	else:
		var weapon_slot := int(option.get("weapon_slot", -1))
		if weapon_slot >= 0 and weapon_slot < weapon_loadouts[slot].size():
			weapon_id = String(weapon_loadouts[slot][weapon_slot]["weapon_id"])

	# The seal appears once both recipe pieces are carried and names the other
	# ingredient; its tooltip states the required treasure tier.
	if not weapon_id.is_empty():
		var state: Dictionary = weapon_loadouts[slot][int(option.get("weapon_slot", -1))]
		var synergy := String(state.get("tech_synergy_treasure_id", ""))
		if not synergy.is_empty() and _treasure_tier(slot, synergy) > 0:
			var treasure := Treasures.by_id(synergy)
			if not treasure.is_empty():
				return {"name": String(treasure["name"]), "texture": IconCatalog.upgrade(synergy)}

	if not treasure_id.is_empty():
		for owned: Dictionary in weapon_loadouts[slot]:
			if String(owned.get("tech_synergy_treasure_id", "")) == treasure_id:
				return {"name": String(owned["weapon_name"]), "texture": IconCatalog.weapon(String(owned["weapon_id"]))}
	return {}


## The nearest final form this survivor can reach through the selected tech.
## Requirements and results are always named so a new player can plan ahead.
func _fusion_progress_line(slot: int) -> String:
	var best := ""
	var best_progress := -1.0
	var fused: Array[String] = []
	for weapon in weapon_loadouts[slot]:
		if bool(weapon.get("evolved", false)):
			fused.append(String(weapon["weapon_name"]))
			continue
		if String(weapon.get("tech_id", "")).is_empty():
			# Below the route gate the next step is the route, not a material.
			var untyped_progress := minf(1.0, float(int(weapon.get("tier", 1))) / float(WeaponGrowthScript.TECH_UNLOCK_TIER)) * 0.4
			if untyped_progress > best_progress:
				best_progress = untyped_progress
				best = tr("%s %d/%d → 테크 선택") % [tr(String(weapon["weapon_name"])),
					mini(int(weapon.get("tier", 1)), WeaponGrowthScript.TECH_UNLOCK_TIER), WeaponGrowthScript.TECH_UNLOCK_TIER]
			continue
		var evolution := _selected_evolution_for_state(weapon)
		if evolution.is_empty():
			continue
		var weapon_tier := int(weapon.get("tier", 1))
		var treasure_id := String(weapon.get("tech_synergy_treasure_id", ""))
		var treasure := Treasures.by_id(treasure_id)
		var treasure_tier := _treasure_tier(slot, treasure_id)
		var weapon_progress := minf(1.0, float(weapon_tier) / float(Evolutions.EVOLUTION_TIER))
		var treasure_progress := minf(1.0, float(treasure_tier) / float(Evolutions.REQUIRED_TREASURE_TIER))
		var progress := (weapon_progress + treasure_progress) * 0.5
		if progress <= best_progress:
			continue
		best_progress = progress
		best = tr("%s %d/%d + %s %d/%d → %s") % [
			tr(String(weapon["weapon_name"])), weapon_tier, Evolutions.EVOLUTION_TIER,
			tr(String(treasure.get("name", "보물"))), treasure_tier, Evolutions.REQUIRED_TREASURE_TIER,
			tr(String(evolution["weapon_name"])),
		]
	if not fused.is_empty():
		var localized_fused: Array[String] = []
		for weapon_name in fused:
			localized_fused.append(tr(weapon_name))
		var done := tr("완료 ") + "  ".join(localized_fused)
		return done if best.is_empty() else best
	return best if not best.is_empty() else tr("대상 없음")


func _finish_level_up() -> void:
	online.send_growth_close()
	level_up_active = false
	_animate_level_overlay(false)
	get_tree().paused = false
	if team_level_heal > 0.0:
		for player in players:
			player.heal(player.max_health * team_level_heal)
	_show_message(tr("LV.%d    둘 다 성장 완료") % progression.level, Color("fff275"))
	if progression.can_level_up():
		level_up_gap_remaining = LEVEL_UP_GAP


## Level-up no longer activates anything by itself. Matching tags make a
## resonance *possible* and the pair is told so; the boss's core is what turns
## one of them on. The old behaviour activated the top-ranked candidate the
## moment the tags lined up, which meant the run's climactic mechanic arrived as
## a banner during a menu the pair were already reading — no moment, and no say
## in which of two possible resonances they got.
func _after_personal_upgrade_choices() -> void:
	_announce_new_resonance_candidates()
	_finish_level_up()


## A quiet notice in the bottom-right when a pairing first becomes possible, and
## nothing at all when it has already been mentioned. This is the promise the
## core later pays off, so it names the resonance and says what it is waiting on.
func _announce_new_resonance_candidates() -> void:
	if not resonance_system.has_free_slot():
		return
	for candidate in resonance_system.get_candidates_for_loadouts(weapon_loadouts[0], weapon_loadouts[1]):
		var id := String(candidate["id"])
		if announced_resonance_ids.has(id):
			continue
		announced_resonance_ids[id] = true
		_show_message(tr("공명 가능 — %s    다음 공명핵에서 선택") % ResonanceSystem.display_name(candidate), Color("e4c1f9"))


## A boss died and left a core. Opens the selection if there is anything to
## spend it on, and otherwise holds it: a core is never consumed by a screen
## that had nothing to offer.
func _award_resonance_core() -> void:
	resonance_system.grant_core()
	_show_message("공명핵 획득", Color("fff275"))
	_open_resonance_core_choice()


func _open_resonance_core_choice() -> void:
	if resonance_system.pending_cores <= 0 or not resonance_system.has_free_slot():
		return
	var candidates := resonance_system.get_candidates_for_loadouts(weapon_loadouts[0], weapon_loadouts[1])
	resonance_candidates = resonance_system.rank_candidates(candidates)
	if resonance_candidates.is_empty():
		# The core keeps. Telling the pair why is the whole point — a reward that
		# silently does nothing is the failure this system was rebuilt to remove.
		_show_message("공명핵 보관 중 — 두 사람이 진화 무기를 하나씩 갖추면 사용할 수 있습니다", Color("e4c1f9"))
		return
	if resonance_candidates.size() == 1:
		# Nothing to decide, so nothing is asked (§13). A one-option screen is a
		# confirmation dialog wearing a choice's clothes.
		_commit_resonance_choice(resonance_candidates[0])
		return
	resonance_votes[0] = -1
	resonance_votes[1] = -1
	resonance_cursors[0] = 0
	resonance_cursors[1] = 0
	resonance_vote_message = ""
	# The AI companion locks the highest-ranked candidate immediately. The human
	# still makes the final choice, without having to operate a nonexistent P2.
	if ai_companion:
		resonance_votes[1] = 0
	resonance_vote_active = true
	# Dealt in exactly as a growth hand is, over the paused fight, with the same
	# view pull: this is the biggest choice the pair makes and it should arrive
	# as a moment rather than as a window appearing.
	modal_dim.visible = true
	if not modal_dim.veil_only:
		modal_dim.veil_only = true
		modal_dim.queue_redraw()
	for notice in notice_stack:
		if is_instance_valid(notice):
			notice.visible = false
	resonance_overlay.visible = true
	get_tree().paused = true
	_refresh_resonance_vote_ui()
	_animate_resonance_overlay(true)
	_pull_camera_for_choice(resonance_overlay)
	feedback.play_cue("level")
	if online != null:
		online.send_resonance_state("resonance_open")


## Spends the core on this resonance and gives it the screen.
func _commit_resonance_choice(chosen: Dictionary) -> void:
	_activate_resonance(chosen)
	resonance_vote_active = false
	_animate_resonance_overlay(false)
	get_tree().paused = false
	_show_message(tr("공명 발현 — %s") % ResonanceSystem.display_name(chosen), Color("fff275"))
	# Deliberately a different shape from the fusion showcase: a resonance is
	# the pair's move, so the two weapons orbit and stay two rather than
	# converging into one.
	_queue_showcase({
		"kind": "resonance",
		"weapon_a_id": String(chosen.get("weapon_a_id", "")),
		"weapon_b_id": String(chosen.get("weapon_b_id", "")),
		"name": String(chosen["name"]),
	})
	_play_showcase_queue(Callable())
	if online != null:
		online.send_resonance_close(chosen)


func _set_resonance_cursor(slot: int, index: int) -> void:
	if not _can_control_player_slot(slot) or not resonance_vote_active \
			or resonance_candidates.is_empty() or resonance_votes[slot] >= 0:
		return
	var next := wrapi(index, 0, resonance_candidates.size())
	if online != null and online.is_client():
		online.request_resonance_action("cursor", next)
		return
	resonance_cursors[slot] = next
	_refresh_resonance_vote_ui()
	if online != null:
		online.send_resonance_state()


func _confirm_resonance_vote(slot: int, index: int) -> void:
	if not _can_control_player_slot(slot) or not resonance_vote_active \
			or resonance_candidates.is_empty() or resonance_votes[slot] >= 0:
		return
	var chosen := wrapi(index, 0, resonance_candidates.size())
	if online != null and online.is_client():
		online.request_resonance_action("confirm", chosen)
		return
	resonance_cursors[slot] = chosen
	resonance_votes[slot] = chosen
	feedback.play_cue("confirm")
	_resolve_resonance_votes()


func _cancel_resonance_vote(slot: int) -> void:
	if not _can_control_player_slot(slot) or not resonance_vote_active \
			or resonance_votes[slot] < 0:
		return
	if online != null and online.is_client():
		online.request_resonance_action("cancel", resonance_cursors[slot])
		return
	resonance_votes[slot] = -1
	feedback.play_cue("cancel")
	_refresh_resonance_vote_ui()
	if online != null:
		online.send_resonance_state()


func _resolve_resonance_votes() -> void:
	_refresh_resonance_vote_ui()
	if online != null:
		online.send_resonance_state()
	if resonance_votes[0] < 0 or resonance_votes[1] < 0:
		return
	if resonance_votes[0] == resonance_votes[1]:
		_commit_resonance_choice(resonance_candidates[resonance_votes[0]])
		return
	resonance_votes[0] = -1
	resonance_votes[1] = 0 if ai_companion else -1
	resonance_vote_message = "선택이 갈렸습니다 — 상대의 커서를 보고 다시 고르세요"
	feedback.play_cue("warning")
	_refresh_resonance_vote_ui()
	if online != null:
		online.send_resonance_state()


## Both survivors browse the same three cards with the same controls the
## level-up screen uses, and each one's cursor is visible to the other the whole
## time. A vote locks only on confirm and can be taken back until the pair
## actually agrees — a disagreement is a conversation, not a failure state.
func _handle_resonance_vote_input() -> void:
	for slot in 2:
		if not _can_control_player_slot(slot):
			continue
		var prefix := "p1_select_" if slot == 0 else "p2_select_"
		if resonance_votes[slot] >= 0:
			if Input.is_action_just_pressed(prefix + "cancel"):
				_cancel_resonance_vote(slot)
			continue
		if Input.is_action_just_pressed(prefix + "previous"):
			_set_resonance_cursor(slot, resonance_cursors[slot] - 1)
		elif Input.is_action_just_pressed(prefix + "next"):
			_set_resonance_cursor(slot, resonance_cursors[slot] + 1)
		elif Input.is_action_just_pressed(prefix + "confirm"):
			_confirm_resonance_vote(slot, resonance_cursors[slot])


## What one resonance card says, in the shape CardVisual.paint reads. Built the
## same way a growth card's model is, so the two screens cannot drift apart.
##
## The card names who supplies what, because "each survivor has to contribute a
## tag" is the rule a pair can fail without ever seeing why — and naming the two
## weapons next to their tags turns 요구 태그: 화염 + 냉기 into something they can
## check against the loadout they are actually holding.
func _resonance_card_model(resonance: Dictionary, badge: String, badge_color: Color) -> Dictionary:
	var requirements: Array = resonance["requires"]
	var contributed: Array[String] = []
	var weapons: Array[String] = []
	for slot in 2:
		var weapon_slot := int(resonance.get("weapon_%s_slot" % ("a" if slot == 0 else "b"), -1))
		if weapon_slot < 0 or weapon_slot >= weapon_loadouts[slot].size():
			continue
		var carried: Dictionary = weapon_loadouts[slot][weapon_slot]
		var mine: Array[String] = []
		for requirement in requirements:
			if requirement in (carried["tags"] as Array):
				mine.append(tr(_tag_name(String(requirement))))
		contributed.append("%s [%s]" % [player_label(slot), " ".join(mine)])
		weapons.append(tr(String(carried["weapon_name"])))
	# Falls back to the bare requirement when the candidate did not come from a
	# live pair of loadouts, which is what the codex and the theme tests hand in.
	# The live path always has both.
	# One line per survivor, each naming the weapon and the tag it brings, rather
	# than a tag line and a separate weapon line. Same two facts, half the height
	# — which is what leaves the description room to actually be read.
	var supply := "%s + %s" % [tr(_tag_name(String(requirements[0]))), tr(_tag_name(String(requirements[1])))]
	if contributed.size() == 2 and weapons.size() == 2:
		supply = "%s %s\n%s %s" % [contributed[0], weapons[0], contributed[1], weapons[1]]
	elif contributed.size() == 2:
		supply = "%s\n%s" % [contributed[0], contributed[1]]
	return {
		"category": "공명",
		"title": ResonanceSystem.display_name(resonance),
		"body": "%s\n\n%s" % [supply, ResonanceSystem.display_description(resonance)],
		"icon": IconCatalog.generated(String(resonance["id"]), "upgrade"),
		"fusion": null,
		"fusion_name": "",
		"tech": false,
		"compact": true,
		# Clear of the two 선택 buttons ReviewUI parks above the badge strip.
		"body_bottom": RESONANCE_CARD_BUTTON_ROOM,
		"badge": badge,
		"badge_color": badge_color,
	}


func _refresh_resonance_vote_ui() -> void:
	var count := mini(resonance_cards.size(), resonance_candidates.size())
	var middle := (count - 1) * 0.5
	for index in resonance_cards.size():
		var card: Label = resonance_cards[index]
		if index >= count:
			card.visible = false
			continue
		card.visible = true
		var resonance: Dictionary = resonance_candidates[index]

		var pointed_by: Array[int] = []
		var locked_by: Array[int] = []
		for slot in 2:
			if resonance_votes[slot] == index:
				locked_by.append(slot)
			elif resonance_votes[slot] < 0 and resonance_cursors[slot] == index:
				pointed_by.append(slot)
		var attention := locked_by.size() + pointed_by.size()
		# Ownership colours, read the same way the growth hand reads them: the
		# local survivor is cyan and their partner is the warm orange, whichever
		# physical slot each of them is sitting in.
		var accent := Color("e4c1f9")
		if locked_by.size() == 2:
			accent = CardVisual.CHEST
		elif not locked_by.is_empty():
			accent = CardVisual.CYAN if locked_by[0] == local_view_slot() else CardVisual.PARTNER
		elif not pointed_by.is_empty():
			accent = CardVisual.CYAN if pointed_by[0] == local_view_slot() else CardVisual.PARTNER

		var badge := _resonance_pip_text(pointed_by, locked_by)
		var model := _resonance_card_model(resonance, badge, accent.lightened(0.25) if attention > 0 else Color("b7d8ed"))
		CardVisual.paint(card, model, accent, attention > 0, RESONANCE_CARD_WIDTH, RESONANCE_CARD_HEIGHT)
		for portrait_slot in 2:
			var portrait := card.get_node_or_null("Cat%d" % portrait_slot) as TextureRect
			if portrait == null:
				continue
			portrait.texture = IconCatalog.survivor(String(selected_characters[portrait_slot]["id"])) \
				if selected_characters[portrait_slot] != null else null
			# Dimmed unless that survivor is the one attending to this card, so
			# the pair of portraits also reads as "whose cursor is here".
			var attending: bool = portrait_slot in locked_by or portrait_slot in pointed_by
			portrait.modulate = Color.WHITE if attending else Color(1, 1, 1, 0.45)

		# The same standing fan as a three-card growth hand: pivot at the bottom
		# centre so the cards lean out from one line, and the attended card lifts
		# along its own axis rather than straight up.
		card.size = Vector2(RESONANCE_CARD_WIDTH, RESONANCE_CARD_HEIGHT)
		card.pivot_offset = Vector2(RESONANCE_CARD_WIDTH * 0.5, RESONANCE_CARD_HEIGHT)
		var tilt: float = (index - middle) / maxf(1.0, middle) * RESONANCE_CARD_TILT
		card.rotation = tilt
		card.scale = Vector2.ONE
		card.z_index = 8 if attention > 0 else 3
		var rest := Vector2(
			640.0 + (index - middle) * RESONANCE_CARD_SPREAD - RESONANCE_CARD_WIDTH * 0.5,
			RESONANCE_CARD_Y + absf(index - middle) * 5.0)
		card.position = rest + (Vector2.UP.rotated(tilt) * NeonGrowthUI.CARD_HOVER_LIFT if attention > 0 else Vector2.ZERO)
		card.modulate = Color.WHITE

	var waiting: Array[String] = []
	for slot in 2:
		if resonance_votes[slot] < 0:
			waiting.append("%s" % player_label(slot))
	var lines: Array[String] = []
	if waiting.size() == 1:
		lines.append(tr("%s 선택 대기 중 — 확정한 쪽은 취소로 되돌릴 수 있습니다") % waiting[0])
	elif waiting.size() == 2:
		lines.append("각자 공명을 고른 뒤 확정하세요")
	if not resonance_vote_message.is_empty():
		lines.append(resonance_vote_message)
	resonance_status.text = "\n".join(lines)
	# The same controls line the growth screen carries, in the same corner, so
	# the two screens answer "what do I press" identically.
	var controls: Label = resonance_overlay.get_node_or_null("ResonanceControls")
	if controls != null:
		controls.text = "나 A / D    W 확정    S 취소     동료 ← / →    ↑ 확정    ↓ 취소"
		if last_input_gamepad[local_view_slot()]:
			controls.text = "LB / RB 이동    A 확정    B 취소"


## The pips are the point of this screen: a hollow marker is "P2 is looking at
## this one", a filled one is "P2 has committed to it".
func _resonance_pip_text(pointed_by: Array[int], locked_by: Array[int]) -> String:
	var parts: Array[String] = []
	for slot in 2:
		if slot in locked_by:
			parts.append(tr("● %s 확정") % player_label(slot))
		elif slot in pointed_by:
			parts.append("○ %s" % player_label(slot))
	return "   ".join(parts)


## One name per tag, held in the resonance system so the card, the codex and the
## generated resonance names all read the same word for the same tag.
func _tag_name(tag: String) -> String:
	return String(ResonanceSystem.TAG_NAMES.get(tag, tag))


## A weapon's own cooldown scaled by its owner's haste, floored so stacked
## haste can never drive an interval to zero (which would fire every frame).
## The XP pickup radius lives on ExperienceSystem, so the shared magnet
## attribute is pushed into it whenever it changes rather than read per frame.
func _apply_team_magnet() -> void:
	experience_system.magnet_radius = EXPERIENCE_MAGNET_BASE * team_magnet


## Takes a resonance live.
##
## Nothing is swept any more. This used to silence the two weapons that earned
## the resonance, and their sustained fields had to be cleared with them —
## 절대영도 and the frost auras hold a field alive between casts, so a weapon that
## had stopped casting would have left its aura standing on the roof for the rest
## of the run. The weapons keep casting now, so their fields are theirs to refresh
## and clearing them here would only put a hole in an aura the survivor is
## standing in.
func _activate_resonance(resonance: Dictionary) -> void:
	resonance_system.activate(resonance)


## What the two weapons behind the pair's move lend it. Both owners' 공격 and both
## weapons' tiers feed it, so a resonance is the thing their whole build is
## pointed at rather than a flat effect bolted on top of it.
func _resonance_trade_power(resonance: Dictionary) -> float:
	var total := 0.0
	for side in ["a", "b"]:
		var player_index := 0 if side == "a" else 1
		var weapon_slot := int(resonance.get("weapon_%s_slot" % side, -1))
		var tier := Evolutions.EVOLUTION_TIER
		if weapon_slot >= 0 and weapon_slot < weapon_loadouts[player_index].size():
			tier = int(weapon_loadouts[player_index][weapon_slot].get("tier", tier))
		var above := float(maxi(0, tier - Evolutions.EVOLUTION_TIER))
		total += players[player_index].might * (1.0 + ResonanceSystem.TRADE_TIER_BONUS * above)
	return total * 0.5 * ResonanceSystem.TRADE_POWER


func _weapon_interval(player_index: int, weapon_slot: int) -> float:
	var state: Dictionary = weapon_loadouts[player_index][weapon_slot]
	var frenzy_rate := FRENZY_ATTACK_SPEED if frenzy_remaining > 0.0 else 1.0
	# The floor is a share of this weapon's own catalogue interval rather than a
	# flat 0.25s. Under the flat floor every weapon in the game converged on the
	# same cadence late in a run — a 6.6s orbit and a 1.1s star bolt both firing
	# four times a second — which flattened the roster and buried the renderer.
	return maxf(WeaponGrowthScript.interval_floor(state),
		float(state["cooldown"]) * players[player_index].haste / frenzy_rate)


func _tension_damage_multiplier() -> float:
	if frenzy_remaining > 0.0:
		return _base_tension_multiplier() * FRENZY_POWER
	return _base_tension_multiplier()


func _base_tension_multiplier() -> float:
	# The ward pays the overcharge bonus unconditionally. That is the whole
	# reason to pick the drop up at a moment when the pair is fighting close
	# together rather than only when the chain is already in trouble.
	if chain_warded():
		return CHAIN_WARD_POWER + team_overcharge
	if chain_overloaded:
		return CHAIN_OVERLOAD_PENALTY
	var ratio := players[0].position.distance_to(players[1].position) / chain_max_length
	if ratio >= CHAIN_WARNING_RATIO:
		return 1.25 + team_overcharge
	return 1.0 + team_close_power if ratio <= 0.45 else 1.0


func _update_hud() -> void:
	boss_hud_panel.visible = false
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
	UIWrite.font_color(p1_health_text_label, Color("ffcfdf") if players[0].downed else Color("f4f8ff"))
	UIWrite.font_color(p2_health_text_label, Color("ffcfdf") if players[1].downed else Color("f4f8ff"))
	chain_bar.value = tension * 100.0
	chain_distance_text_label.text = tr("거리  %d%%") % int(round(tension * 100.0))
	var chain_state := ""
	var chain_color := Color("43d9ff")
	if chain_overloaded:
		chain_state = "과부하    붙어서 회복"
		chain_color = Color("ff5d8f")
	elif tension >= 0.95:
		chain_state = "한계    가까이 붙기"
		chain_color = Color("ff5d8f")
	elif tension >= CHAIN_WARNING_RATIO:
		chain_state = tr("과충전   공격 +%d%%") % roundi((0.25 + team_overcharge) * 100.0)
		chain_color = Color("fff275")
	elif tension >= CHAIN_RESIST_RATIO:
		chain_state = "저항    붙으면 회복"
		chain_color = Color("8ecae6")
	chain_status_label.text = chain_state
	chain_status_label.visible = not chain_state.is_empty()
	# Written on the paper strip, so in the ink shade of the bar colour.
	UIWrite.font_color(chain_status_label, CardVisual.ink_of(chain_color))
	var fill := chain_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		UIWrite.bg_color(fill, chain_color)
	chain_integrity_bar.value = chain_integrity
	chain_integrity_text_label.text = tr("내구도  %d%%") % int(round(chain_integrity))
	var integrity_fill := chain_integrity_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if integrity_fill != null:
		if chain_overloaded:
			UIWrite.bg_color(integrity_fill, Color("ff5d8f"))
		elif chain_integrity < 40.0:
			UIWrite.bg_color(integrity_fill, Color("fff275"))
		else:
			UIWrite.bg_color(integrity_fill, Color("80ed99"))
	# The third column of the shared strip, always present so the row keeps its
	# three-column shape from the first second of a run. Before either half
	# exists it reads as empty slots, which is the truthful thing to show: the
	# pair has two to fill and nothing in them yet.
	var held_cores := resonance_system.pending_cores
	var active_count := resonance_system.active_resonances.size()
	if held_cores > 0:
		# An unspent core is the pair owing themselves a decision, so it stays on
		# the HUD until it is gone rather than being mentioned once and forgotten.
		resonance_status_label.text = tr("공명핵 %d") % held_cores
		UIWrite.font_color(resonance_status_label, CatTheme.GOLD_INK)
	else:
		resonance_status_label.text = tr("공명 %d/%d") % [active_count, ResonanceSystem.MAX_ACTIVE_RESONANCES]
		UIWrite.font_color(resonance_status_label, Color("6f3a9c"))
	if resonance_pips != null:
		resonance_pips.report(active_count, ResonanceSystem.MAX_ACTIVE_RESONANCES, held_cores)
	xp_bar.max_value = progression.required_experience
	xp_bar.value = progression.experience
	xp_text_label.text = (tr("LV.%d    초월 %d    XP %d / %d") % [
		progression.level, overflow_levels,
		int(progression.experience), int(progression.required_experience),
	]) if growth_finished else ("LV.%d    XP %d / %d" % [
		progression.level, int(progression.experience), int(progression.required_experience)
	])
	EditorialUI.refresh_hud(self)


func _player_status_text(player_index: int) -> String:
	var player := players[player_index]
	return "%s  %s" % [player_label(player_index), tr(player.character_name)]


func _player_health_text(player_index: int) -> String:
	var player := players[player_index]
	if player.downed:
		return tr("DOWN %.1f초   구조 %.0f%%") % [player.bleedout_remaining, player.revive_progress / 2.6 * 100.0]
	return "%d / %d" % [int(player.health), int(player.max_health)]


## The co-op line of the result screen: what the pair did together, next to
## the survival numbers above it. These are the counters run_stats has been
## carrying unused; nothing else reads them.
func _run_stats_summary() -> String:
	var totals := tr("보스 %d대   구조 %d회   대시 %d회   공명 %d회   아이템 %d개   과충전 %.0f초") % [
		int(run_stats["bosses"]), int(run_stats["revives"]), int(run_stats["dashes"]),
		int(run_stats["resonance_casts"]), int(run_stats["items"]),
		float(run_stats["overcharge_time"])
	]
	return totals + "\n" + _item_count_summary()


func _result_highlight() -> String:
	if int(run_stats["revives"]) > 0:
		return tr("오늘의 협동    동료 구조 %d회 · 끝까지 함께 버텼어요") % int(run_stats["revives"])
	if int(run_stats["bosses"]) > 0:
		return tr("오늘의 성과    옥상 보스 %d대 격파") % int(run_stats["bosses"])
	var lead := 0 if _player_damage_total(0) >= _player_damage_total(1) else 1
	var damage := _player_damage_total(lead)
	if damage > 0.0:
		return tr("오늘의 활약    %s %s · 총 피해 %.0f") % [player_label(lead), tr(players[lead].character_name), damage]
	return tr("첫걸음 완료    다음 원정에서는 더 오래 발맞춰 보세요")


func _reset_run_stats() -> void:
	run_stats = RunStatsTemplate.create()


const CONTRIBUTION_DAMAGE_SCALE := 0.02
const CONTRIBUTION_KILL := 2.0
const CONTRIBUTION_ELITE_KILL := 12.0
const CONTRIBUTION_BOSS_KILL := 60.0
const CONTRIBUTION_ITEM := 10.0
const CONTRIBUTION_REVIVE := 80.0


func _award_contribution(player_index: int, points: float) -> void:
	if player_index < 0 or player_index >= 2 or points <= 0.0:
		return
	run_stats["contribution_points"][player_index] = float(run_stats["contribution_points"][player_index]) + points
	var progress: float = float(run_stats["contribution_progress"][player_index]) + points
	var contribution_level: int = int(run_stats["personal_levels"][player_index])
	var requirement := float(SharedProgression.requirement_for_level(contribution_level))
	while progress >= requirement:
		progress -= requirement
		contribution_level += 1
		requirement = float(SharedProgression.requirement_for_level(contribution_level))
	run_stats["contribution_progress"][player_index] = progress
	run_stats["personal_levels"][player_index] = contribution_level


func _record_combat_damage(player_index: int, weapon_id: String, amount: float) -> void:
	if amount <= 0.0 or weapon_id.is_empty():
		return
	if weapon_id.begins_with("resonance:"):
		run_stats["resonance_damage"] = float(run_stats["resonance_damage"]) + amount
		return
	if player_index < 0 or player_index >= 2:
		return
	var damage_by_weapon: Dictionary = run_stats["weapon_damage"][player_index]
	damage_by_weapon[weapon_id] = float(damage_by_weapon.get(weapon_id, 0.0)) + amount
	_award_contribution(player_index, amount * CONTRIBUTION_DAMAGE_SCALE)


func _merge_weapon_damage_record(player_index: int, old_id: String, new_id: String) -> void:
	var damage_by_weapon: Dictionary = run_stats["weapon_damage"][player_index]
	if damage_by_weapon.has(old_id):
		damage_by_weapon[new_id] = float(damage_by_weapon.get(new_id, 0.0)) + float(damage_by_weapon[old_id])
		damage_by_weapon.erase(old_id)


func _weapon_dps(player_index: int, weapon_id: String) -> float:
	return float(run_stats["weapon_damage"][player_index].get(weapon_id, 0.0)) / maxf(1.0, elapsed)


func _player_damage_total(player_index: int) -> float:
	var total := 0.0
	for value in (run_stats["weapon_damage"][player_index] as Dictionary).values():
		total += float(value)
	return total


func _result_player_summary(player_index: int) -> String:
	var contribution := tr("기여 LV.%d   처치 %d   아이템 %d") % [
		int(run_stats["personal_levels"][player_index]), int(run_stats["kills_by_player"][player_index]),
		int(run_stats["items_by_player"][player_index])
	]
	var combat := tr("총 피해 %.0f   구조 %d   DPS %.1f") % [
		_player_damage_total(player_index),
		int(run_stats["revives_by_player"][player_index]),
		_player_damage_total(player_index) / maxf(1.0, elapsed),
	]
	return contribution + "\n" + combat


func _item_count_summary() -> String:
	var parts: Array[String] = []
	var item_counts: Dictionary = run_stats["items_by_type"]
	for item_id in item_counts:
		parts.append("%s ×%d" % [tr(field_items.item_display_name(String(item_id))), int(item_counts[item_id])])
	return tr("획득 없음") if parts.is_empty() else "   ".join(parts)


const NOTICE_CAP := 10
const NOTICE_WIDTH := 440.0
const NOTICE_PITCH := 19.0
## Bottom edge of the newest notice: just above the XP bar at y=690.
const NOTICE_BOTTOM := 684.0


func _show_message(text: String, color: Color) -> void:
	message_label.text = text # Last event remains available to accessibility/tests.
	message_label.modulate.a = 0.0
	for index in range(notice_stack.size() - 1, -1, -1):
		if not is_instance_valid(notice_stack[index]) or notice_stack[index].is_queued_for_deletion():
			notice_stack.remove_at(index)
	if notice_stack.size() >= NOTICE_CAP:
		notice_stack.pop_front().queue_free()
	# A running log in the bottom-right corner: bare outlined text, right-aligned,
	# newest at the bottom just above the XP bar, older lines climbing above it.
	var notice := Label.new()
	notice.text = text.replace("\n", "    ")
	notice.size = Vector2(NOTICE_WIDTH, NOTICE_PITCH)
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice.clip_text = true
	# 13px over the rooftop, in the corner of the eye, while the fight runs: the
	# readout face rather than the menus' handwriting, for the same reason the
	# HUD strip above it uses it (see CatTheme.READOUT).
	notice.add_theme_font_override("font", CatTheme.READOUT)
	notice.add_theme_font_size_override("font_size", 13)
	notice.add_theme_color_override("font_color", color)
	notice.add_theme_color_override("font_outline_color", Color(0.02, 0.035, 0.07, 0.92))
	notice.add_theme_constant_override("outline_size", 4)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.get_parent().add_child(notice)
	notice_stack.append(notice)
	for index in notice_stack.size():
		notice_stack[index].position = Vector2(1280.0 - 16.0 - NOTICE_WIDTH,
			NOTICE_BOTTOM - float(notice_stack.size() - index) * NOTICE_PITCH)
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(notice, "modulate:a", 0.0, 0.65)
	tween.tween_callback(notice.queue_free)


func _handle_result_input() -> void:
	if run_won:
		if Input.is_action_just_pressed("p1_select_previous") or Input.is_action_just_pressed("p2_select_previous"):
			meta_cursor = wrapi(meta_cursor - 1, 0, MetaProgression.UPGRADES.size())
			_refresh_meta_result_ui()
		elif Input.is_action_just_pressed("p1_select_next") or Input.is_action_just_pressed("p2_select_next"):
			meta_cursor = wrapi(meta_cursor + 1, 0, MetaProgression.UPGRADES.size())
			_refresh_meta_result_ui()
		elif Input.is_action_just_pressed("meta_buy"):
			var entry: Dictionary = MetaProgression.UPGRADES[meta_cursor]
			if meta_progression.purchase(String(entry["id"])):
				feedback.play_cue("purchase")
			_refresh_meta_result_ui()
	if Input.is_action_just_pressed("restart"):
		_retry_same_pair()
	elif Input.is_action_just_pressed("menu_cancel") or Input.is_action_just_pressed("pause"):
		_return_to_main_menu()


func _retry_same_pair() -> void:
	if online != null and online.is_client():
		online.request_result_action("retry")
		return
	if online != null and online.is_host():
		_store_pending_retry()
		online.send_retry_run()
		get_tree().create_timer(0.12, true, false, true).timeout.connect(_reload_pending_retry)
		return
	_accept_online_retry()


func _accept_online_retry() -> void:
	_store_pending_retry()
	_reload_pending_retry()


func _store_pending_retry() -> void:
	pending_retry = {
		"characters": selected_character_indices.duplicate(),
		"ai_companion": ai_companion,
		"online_role": int(online.session.role) if online != null else 0,
		"online_address": online.session.address if online != null else "127.0.0.1",
	}


func _reload_pending_retry() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _return_to_main_menu() -> void:
	if online != null and online.is_client():
		online.request_result_action("menu")
		return
	if online != null and online.is_host():
		online.send_return_to_menu()
		get_tree().create_timer(0.12, true, false, true).timeout.connect(_accept_online_return_to_menu)
		return
	_accept_online_return_to_menu()


func _accept_online_return_to_menu() -> void:
	if online != null and online.is_online():
		online.stop()
	pending_retry.clear()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _refresh_meta_result_ui() -> void:
	if not is_instance_valid(result_overlay) or not result_overlay.has_node("MetaTitle"):
		return
	var title := result_overlay.get_node("MetaTitle") as Label
	title.visible = run_won
	title.text = tr("클리어 보상 +%d 달빛 생선      보유 %d      다음 원정부터 적용") % [run_reward, meta_progression.points]
	if meta_progression.last_save_error != OK:
		title.text = "저장할 수 없습니다    진행 상황은 변경되지 않았어요"
	for visible_index in 6:
		var index := (meta_cursor / 6) * 6 + visible_index
		var card := result_overlay.get_node("MetaUpgrade%d" % visible_index) as Label
		card.visible = run_won
		if not run_won:
			continue
		var entry: Dictionary = MetaProgression.UPGRADES[index]
		var id := String(entry["id"])
		var rank := meta_progression.rank(id)
		var cap := int(entry["max_rank"])
		var price := meta_progression.cost(id)
		card.text = "%s%s\nLv.%d/%d    %s\n%s" % [
			"◆ " if index == meta_cursor else "", tr(String(entry["name"])), rank, cap,
			"MAX" if price <= 0 else tr("%d개") % price, tr(String(entry["summary"]))]
		var style := card.get_theme_stylebox("normal") as StyleBoxFlat
		if style != null:
			style.set_border_width_all(3 if index == meta_cursor else 2)
			style.border_color = CatTheme.GOLD_INK if index == meta_cursor else CatTheme.INK_LINE


func _end_run(victory: bool = false, grant_rewards := true) -> void:
	if game_over:
		return
	game_over = true
	run_won = victory
	run_reward = 0
	if grant_rewards and victory and not debug_run_tainted and int(run_stats["bosses"]) >= WaveDirectorScript.BOSS_COUNT:
		run_reward = meta_progression.award_clear()
	level_up_active = false
	level_overlay.visible = false
	resonance_overlay.visible = false
	pause_overlay.visible = false
	result_overlay.visible = true
	combat_hud.visible = false
	_hide_boss_readout()
	for slot in 2:
		var portrait := result_overlay.get_node("ResultCat%d" % slot) as TextureRect
		portrait.texture = IconCatalog.survivor(String(selected_characters[slot]["id"]))
	get_tree().paused = true
	result_label.add_theme_color_override("font_color", CatTheme.INK if victory else CatTheme.DANGER_INK)
	EditorialUI.refresh_result(self, victory)
	if debug_run_tainted:
		result_overlay.get_node("ResultReason").text = "디버그 조작을 사용한 런입니다. 보상과 발견 기록은 저장되지 않습니다."
	_update_hud()
	feedback.play_music("result_win" if victory else "result_loss")
	if online != null:
		online.send_result(victory, grant_rewards and victory and not debug_run_tainted
			and int(run_stats["bosses"]) >= WaveDirectorScript.BOSS_COUNT)


func _setup_input_map() -> void:
	InputBindings.install()
