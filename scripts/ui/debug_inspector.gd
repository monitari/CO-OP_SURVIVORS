class_name DebugInspector
extends CanvasLayer

## A debug-build-only runtime workbench. The controls are created lazily on the
## first F10 press, so merely installing the inspector cannot change production
## HUD layout or add noise to UI regression tests.

const Evolutions := preload("res://scripts/catalogs/evolution_catalog.gd")
const Treasures := preload("res://scripts/catalogs/treasure_catalog.gd")
const WeaponTechs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")

const UPDATE_INTERVAL := 0.16
## The cycle starts at 2x because the game already runs at 1x: a first press
## that changed nothing read as a dead key. 1x is the last step, back to normal.
const DEBUG_SPEEDS: Array[float] = [2.0, 5.0, 0.15, 1.0]

var game
var panel: PanelContainer
var readout: RichTextLabel
var ribbon: PanelContainer
var ribbon_label: Label
var is_open := false
var update_remaining := 0.0
## -1 while the inspector is not driving the clock. Engine.time_scale is global
## and the inspector is not its only user -- the soak harnesses accelerate a run
## twentyfold before starting it -- so restoring a flat 1.0 silently cancelled
## someone else's setting. The inspector puts back what it found, and only when
## it was the one that changed it.
var debug_speed_index := -1
var base_time_scale := 1.0
var notice := "F6~F9 명령은 진행 중인 런에서만 동작합니다."
var combat_visuals_enabled := true

## Whether the frame-cost readout is up (F11).
##
## The run already carried a per-phase timer for the headless performance tests
## (main._profile), but nothing could read it while a person was playing — so
## "the game feels bad right now" and "which phase of a tick is expensive" were
## two separate investigations, and the second one only ever happened against a
## scripted fixture rather than against the build that actually felt bad. This
## turns the same counters on live and reports them over a rolling window.
var performance_open := false
## What main.profiling was before the readout took it over. The headless tests
## drive that flag themselves, so it is restored rather than cleared.
var profiling_was := false
## The rolling window, rebuilt from main's accumulators on every refresh.
var frame_sections: Array = []
var frame_tick_ms := 0.0
var frame_worst_ms := 0.0
## FrameProbe's heaviest sections from the last window.
var probe_rows: Array = []
## Seconds of wall clock the current window has been collecting for. The window
## is cleared and restarted every refresh, so a section's share is an average
## over roughly UPDATE_INTERVAL of real play rather than over the whole run.
var frame_window := 0.0
## One physics tick's budget at the project's 60Hz. Sections are drawn as a
## share of this rather than of each other, because what matters is whether the
## tick fits in a frame, not which phase happens to be largest.
const TICK_BUDGET_MS := 1000.0 / 60.0


func configure(main_node: Node) -> void:
	game = main_node
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)


func _exit_tree() -> void:
	# A debug speed must never leak into a reloaded scene.
	_restore_time_scale()


func _restore_time_scale() -> void:
	if debug_speed_index < 0:
		return
	Engine.time_scale = base_time_scale
	debug_speed_index = -1


func reset_run() -> void:
	_restore_time_scale()
	notice = "새 런: 수치 열람만 하면 정상 기록으로 유지됩니다."
	if is_open:
		_refresh()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if key == KEY_F10:
		toggle()
		get_viewport().set_input_as_handled()
		return
	# Everything below needs the panel open, F11 and F12 included.
	#
	# Those two are the game's own 전체화면 and 달빛 연출 keys
	# (InputBindings.toggle_fullscreen / toggle_moonlight), so the inspector can
	# only borrow them while it is visibly up — and main has to stand down for
	# exactly that window, because it reads them as actions and would otherwise
	# fire its own toggle alongside this one. Gating here and yielding there is
	# the whole agreement; see main._input.
	if not is_open:
		return
	match key:
		KEY_F11:
			_toggle_performance()
		KEY_F12:
			_toggle_combat_visuals()
		KEY_F5:
			_cycle_speed()
		KEY_F6:
			_grant_level()
		KEY_F7:
			_prepare_fusions()
		KEY_F8:
			_repair_team()
		KEY_F9:
			_spawn_next_boss()
		_:
			return
	get_viewport().set_input_as_handled()


func toggle() -> void:
	if panel == null:
		_build_panel()
	is_open = not is_open
	if not is_open:
		_restore_time_scale()
		_stop_performance()
	else:
		_refresh()
	_sync_visibility()


func _toggle_performance() -> void:
	if performance_open:
		_stop_performance()
		notice = "프레임 계측 종료."
		_refresh()
		return
	if not is_instance_valid(game):
		return
	performance_open = true
	profiling_was = bool(game.profiling)
	game.profiling = true
	FrameProbe.enabled = true
	_clear_window()
	notice = "프레임 계측 중 — 계측 자체가 틱당 10여 마이크로초를 씁니다."
	_refresh()


func _toggle_combat_visuals() -> void:
	combat_visuals_enabled = not combat_visuals_enabled
	if is_instance_valid(game):
		game.set_combat_visuals_enabled(combat_visuals_enabled)
	notice = "공격 렌더링 %s" % ("켜짐" if combat_visuals_enabled else "꺼짐")
	_refresh()


func _stop_performance() -> void:
	if not performance_open:
		return
	performance_open = false
	if is_instance_valid(game):
		game.profiling = profiling_was
	frame_sections.clear()
	FrameProbe.enabled = false
	probe_rows.clear()


## Empties main's accumulators so the next window starts clean. Called on every
## refresh, which is what makes the readout a rolling average of the last
## UPDATE_INTERVAL of play rather than of the whole session — a run-long average
## would keep reporting a spike from two minutes ago.
func _clear_window() -> void:
	if not is_instance_valid(game):
		return
	game.profile_totals.clear()
	game.profile_frames = 0
	game.profile_frame_usec.clear()
	frame_window = 0.0
	FrameProbe.clear()


## Reads main's accumulators into the shape the readout draws, then restarts the
## window.
func _sample_performance() -> void:
	if not is_instance_valid(game):
		return
	var ticks: int = maxi(1, int(game.profile_frames))
	var totals: Dictionary = game.profile_totals
	var rows: Array = []
	var tick_total := 0.0
	for section: String in totals:
		var per_tick := float(totals[section]) / float(ticks) / 1000.0
		tick_total += per_tick
		rows.append({"section": section, "ms": per_tick})
	rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first["ms"]) > float(second["ms"]))
	frame_sections = rows
	frame_tick_ms = tick_total
	# The worst tick in the window rather than the mean of the worst, because a
	# phase that costs double on alternate frames averages away and is exactly
	# what a player feels.
	var worst := 0
	for value: int in game.profile_frame_usec:
		worst = maxi(worst, value)
	frame_worst_ms = float(worst) / 1000.0
	# Everything that ticks or draws in its own node, per physics tick — the
	# part main's sections cannot see (FrameProbe).
	var probe: Array = []
	for section: StringName in FrameProbe.totals:
		probe.append({"section": String(section), "ms": float(FrameProbe.totals[section]) / float(ticks) / 1000.0})
	probe.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first["ms"]) > float(second["ms"]))
	probe_rows = probe.slice(0, 8)
	_clear_window()


func _process(delta: float) -> void:
	if not is_open:
		return
	# Folding has to follow the screen it yields to frame by frame, so it is
	# deliberately not on the throttled text cadence below.
	_sync_visibility()
	# The inspector must remain readable at 5x simulation speed. Use real time,
	# not scaled game time, for its refresh cadence.
	update_remaining -= delta / maxf(0.001, Engine.time_scale)
	if update_remaining <= 0.0:
		# The only place the window is closed and read. Everything else that
		# refreshes the text — a command key, a new run — redraws the numbers
		# this last took rather than taking a fresh sample from a window a few
		# milliseconds long, which would report noise as a spike.
		if performance_open:
			_sample_performance()
		update_remaining = UPDATE_INTERVAL
		_refresh()


## The panel is anchored over the right half of the screen, which is exactly
## where every menu puts P2's side: the growth screen's cards and reroll button,
## the character grid, the resonance vote. F6 and F7 open the growth screen on
## purpose, so a panel that simply sat on top of it would bury the very cards the
## command exists to show, and MOUSE_FILTER_STOP would swallow the clicks too.
## While such a screen is up the inspector folds into a click-through ribbon,
## below every overlay, and unfolds when the screen closes. The ribbon used to
## run along the bottom edge; the growth screen is a band across that whole edge
## now, so it sits in the strip just under the combat HUD instead — where the
## boss readout would be, and that readout is hidden while a modal is up.
func _modal_screen_active() -> bool:
	return (game.title_active or game.lobby_active or game.character_select_active
		or game.game_over or game.cinematic_active or game.level_up_active
		or game.resonance_vote_active or game.pause_active)


func _sync_visibility() -> void:
	if panel == null:
		return
	var folded := is_open and _modal_screen_active()
	panel.visible = is_open and not folded
	ribbon.visible = folded


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "DebugInspectorPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.535
	panel.anchor_top = 0.018
	panel.anchor_right = 0.992
	panel.anchor_bottom = 0.982
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.012, 0.022, 0.043, 0.965)
	box.border_color = Color("43d9ff")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	box.shadow_size = 10
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	readout = RichTextLabel.new()
	readout.name = "DebugReadout"
	readout.bbcode_enabled = true
	readout.fit_content = false
	readout.scroll_active = true
	readout.selection_enabled = true
	readout.add_theme_font_size_override("normal_font_size", 14)
	readout.add_theme_font_size_override("bold_font_size", 14)
	readout.add_theme_color_override("default_color", Color("dcecff"))
	margin.add_child(readout)
	panel.visible = false

	ribbon = PanelContainer.new()
	ribbon.name = "DebugInspectorRibbon"
	ribbon.anchor_left = 0.0
	ribbon.anchor_top = 0.0
	ribbon.anchor_right = 1.0
	ribbon.anchor_bottom = 0.0
	ribbon.offset_left = 12.0
	ribbon.offset_top = 134.0
	ribbon.offset_right = -12.0
	ribbon.offset_bottom = 162.0
	# Handing the pointer back to the screen underneath is the whole point of
	# folding, so neither the ribbon nor its label may accept a click.
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ribbon_box := StyleBoxFlat.new()
	ribbon_box.bg_color = Color(0.012, 0.022, 0.043, 0.902)
	ribbon_box.border_color = Color("43d9ff")
	ribbon_box.set_border_width_all(1)
	ribbon_box.set_corner_radius_all(8)
	ribbon_box.content_margin_left = 12
	ribbon_box.content_margin_right = 12
	ribbon.add_theme_stylebox_override("panel", ribbon_box)
	add_child(ribbon)

	ribbon_label = Label.new()
	ribbon_label.name = "DebugRibbonText"
	ribbon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon_label.clip_text = true
	ribbon_label.add_theme_font_size_override("font_size", 13)
	ribbon_label.add_theme_color_override("font_color", Color("dcecff"))
	ribbon.add_child(ribbon_label)
	ribbon.visible = false


func _refresh() -> void:
	if readout == null or not is_instance_valid(game):
		return
	ribbon_label.text = "INSPECTOR 접힘      %s 화면을 닫으면 다시 펼쳐집니다      %s배속      %s" % [
		_state_name(), _speed_text(Engine.time_scale), notice,
	]
	var lines: Array[String] = []
	lines.append("[font_size=20][color=#43d9ff][b]RUNTIME INSPECTOR[/b][/color][/font_size]  [color=#7f96ae]F10 닫기[/color]")
	lines.append("[color=#94a8bd]F5 배속 2 → 5 → 0.15 → 1배      F6 레벨업[/color]")
	lines.append("[color=#94a8bd]F7 즉시 진화      F8 완전 회복      F9 다음 보스[/color]")
	lines.append("[color=#94a8bd]F11 프레임 계측 %s      F12 공격 렌더링 %s[/color]" % ["끄기" if performance_open else "켜기", "끄기" if combat_visuals_enabled else "켜기"])
	lines.append("[color=#24384f]────────────────────────────────────────[/color]")
	if game.debug_run_tainted:
		lines.append("[color=#ff5d8f][b]DEBUG MUTATED[/b]  보상  발견 기록 저장 안 함[/color]")
	lines.append("[color=#ffd166]%s[/color]" % notice)
	lines.append("")
	if performance_open:
		lines.append(_performance_report())
		lines.append("")
	lines.append(_run_report())
	if game.players.size() >= 2:
		lines.append("")
		lines.append(_chain_report())
		for slot in 2:
			lines.append("")
			lines.append(_player_report(slot))
	lines.append("")
	lines.append(_resonance_report())
	readout.text = "\n".join(lines)
	# F6 and F7 open a growth screen as their last act, so folding has to land
	# on the same frame as the command rather than on the next process tick.
	_sync_visibility()


func _state_name() -> String:
	if game.title_active:
		return "타이틀"
	if game.lobby_active:
		return "로비"
	if game.character_select_active:
		return "캐릭터 선택"
	if game.game_over:
		return "결과"
	if game.cinematic_active:
		return "연출"
	if game.level_up_active:
		return "성장 선택"
	if game.resonance_vote_active:
		return "공명 선택"
	if game.pause_active:
		return "일시정지"
	return "전투"


## The slow step is 0.15x, which "%.0f" renders as "0" and "%.1f" as "0.1" — the
## one speed worth announcing precisely was the one that announced itself as a
## stopped clock. Trailing zeros are trimmed so 1/2/5x stay short.
func _speed_text(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.left(-1)
	return text.trim_suffix(".")


## Where a frame actually goes, right now, in the build the player is playing.
##
## Three blocks, in the order a performance problem is usually read:
##
##   1. what the frame costs (render and physics, against the 60Hz budget)
##   2. which phase of the physics tick it is going to (the bars)
##   3. how many of the things that drive those phases are alive
##
## The third block is there because the first two say a phase is expensive and
## never say why. A weapon phase at 6ms means nothing on its own; a weapon phase
## at 6ms next to "투사체 340" is a diagnosis.
func _performance_report() -> String:
	var lines: Array[String] = []
	lines.append("[font_size=16][color=#ffd166][b]프레임 계측[/b][/color][/font_size]")
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(1.0, float(fps))
	lines.append("%s FPS %d[/color]      프레임 %.1fms      예산 %.1fms" % [
		_budget_color(frame_ms, TICK_BUDGET_MS), fps, frame_ms, TICK_BUDGET_MS,
	])
	# The split before the breakdown, because it decides which breakdown is even
	# worth reading. A simulation that measures 1.8ms inside a 7ms frame says the
	# bars below are not where the time is going, and that is the most useful
	# single thing this panel can say — the section timings alone cannot say it.
	#
	# Reported as the engine's own two monitors and nothing derived from them.
	# Subtracting both from the frame time to get "everything else" looks like
	# the obvious next line and is not sound: the monitors are sampled on their
	# own schedule and the frame time is a smoothed average, so the difference is
	# routinely negative and a clamped negative reads as a confident zero.
	lines.append("[color=#dcecff]스크립트 _process %.2fms      _physics %.2fms[/color]  [color=#7f96ae]엔진 계측[/color]" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	])
	lines.append("[color=#7f96ae]드로우 콜 %d      그린 오브젝트 %d      노드 %d      메모리 %.0fMB[/color]" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	])
	# The gap, named. main._profile only wraps main's *own* _physics_process, and
	# every projectile, milk pool, weapon field and mine is a node with a
	# _physics_process of its own that the engine calls directly — so they are
	# invisible to the bars below however expensive they get. Measured at 620
	# enemies with four weapons firing, main's sections came to 1.7ms of a 15ms
	# frame and the effect nodes owned most of the rest. Reading the bars without
	# this line sends you optimising the one part that was already fast.
	var engine_physics := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var untracked := engine_physics - frame_tick_ms
	lines.append("[color=#94a8bd]main 틱 합계 %.2fms  (최악 %.2fms)[/color]      %s이펙트 노드 등 그 외 %.2fms[/color]" % [
		frame_tick_ms, frame_worst_ms, _budget_color(untracked, TICK_BUDGET_MS * 0.5), maxf(0.0, untracked),
	])
	if frame_sections.is_empty():
		lines.append("[color=#7f96ae]틱 표본을 모으는 중…[/color]")
	for row: Dictionary in frame_sections:
		var section_ms := float(row["ms"])
		var share := clampf(section_ms / TICK_BUDGET_MS, 0.0, 1.0)
		var filled := int(round(share * 24.0))
		lines.append("%s%s[/color][color=#24384f]%s[/color]  [color=#dcecff]%-20s %5.2fms[/color]" % [
			_budget_color(section_ms, TICK_BUDGET_MS * 0.34),
			"█".repeat(filled), "░".repeat(24 - filled),
			String(row["section"]), section_ms,
		])
	if not probe_rows.is_empty():
		lines.append("[color=#94a8bd]노드별 (틱당, incl은 다른 항목에 포함됨)[/color]")
		for row: Dictionary in probe_rows:
			lines.append("%s%-26s %5.2fms[/color]" % [
				_budget_color(float(row["ms"]), TICK_BUDGET_MS * 0.2), String(row["section"]), float(row["ms"])])
	lines.append("[color=#24384f]────────────────────────────────────────[/color]")
	lines.append(_population_report())
	return "\n".join(lines)


## How many of each kind of live thing there is. These are the inputs to every
## per-phase cost above: the enemy loop is linear in the crowd, the weapon phase
## is linear in what the weapons have left lying around, and the renderer pays
## for all of it.
func _population_report() -> String:
	var counts := {"투사체": 0, "우유 웅덩이": 0, "무기 장판": 0, "지뢰": 0, "기타 이펙트": 0}
	if is_instance_valid(game.weapon_controller):
		for child in game.weapon_controller.get_children():
			if child is HomingProjectile:
				counts["투사체"] += 1
			elif child is MilkPool:
				counts["우유 웅덩이"] += 1
			elif child is WeaponField:
				counts["무기 장판"] += 1
			elif child is ProximityMine:
				counts["지뢰"] += 1
			else:
				counts["기타 이펙트"] += 1
	var alive := 0
	var offscreen := 0
	var view: Rect2 = game._visible_world_rect()
	for enemy in game.enemies:
		var body := enemy as ChaserEnemy
		if body == null or not is_instance_valid(body) or body.dead:
			continue
		alive += 1
		if not view.has_point(body.global_position):
			offscreen += 1
	var lines: Array[String] = []
	lines.append("[color=#dcecff]적 %d[/color] [color=#7f96ae](화면 밖 %d  상한 %d)[/color]      [color=#dcecff]경험치 %d[/color]      [color=#dcecff]적 탄 %d[/color]" % [
		alive, offscreen, int(game.wave_director.enemy_cap),
		game.experience_system.active_gems.size() if is_instance_valid(game.experience_system) else 0,
		game.enemy_shots.size(),
	])
	var parts: Array[String] = []
	for key: String in counts:
		parts.append("%s %d" % [key, int(counts[key])])
	lines.append("[color=#dcecff]%s[/color]" % "      ".join(parts))
	return "\n".join(lines)


## Opens a colour tag that goes amber then red as `value` approaches `budget`.
## Returns only the opening tag; callers close it, because several of them wrap
## more than one field in the same verdict.
func _budget_color(value: float, budget: float) -> String:
	if value >= budget:
		return "[color=#ff5d8f]"
	if value >= budget * 0.6:
		return "[color=#ffd166]"
	return "[color=#71ffcd]"


func _run_report() -> String:
	var state := _state_name()
	var elapsed := float(game.elapsed)
	var wave_text := "%d%s" % [
		int(game.wave_director.wave_index) + 1,
		" (휴식)" if game.wave_director.in_calm else "",
	]
	var next_boss := float(game.wave_director.next_boss_time())
	return ("[color=#80ed99][b]RUN[/b][/color]  %s      %s      %s배속      %d FPS\n" % [
		state, _clock(elapsed), _speed_text(Engine.time_scale), Engine.get_frames_per_second()
	] + "웨이브 %s      적 %d/%d      처치 %d\n" % [
		wave_text, game.enemies.size(), int(game.wave_director.enemy_cap), int(game.kills)
	] + "LV.%d  XP %d/%d      보스 %d/%d      다음 %s%s" % [
		int(game.progression.level), int(game.progression.experience), int(game.progression.required_experience),
		int(game.wave_director.bosses_spawned), int(game.wave_director.BOSS_COUNT),
		"완료" if int(game.wave_director.bosses_spawned) >= int(game.wave_director.BOSS_COUNT) else _clock(next_boss),
		" [전투 중]" if game.wave_director.boss_active else "",
	])


func _chain_report() -> String:
	var distance: float = game.players[0].global_position.distance_to(game.players[1].global_position)
	var ratio: float = distance / maxf(1.0, float(game.chain_max_length))
	var state := "과부하" if game.chain_overloaded else ("위험" if ratio >= float(game.CHAIN_WARNING_RATIO) else "안정")
	return "[color=#c77dff][b]CHAIN[/b][/color]  %.0f / %.0f px  (%d%%, %s)\n내구도 %.0f / %.0f      오버차지 보너스 +%.0f%%" % [
		distance, float(game.chain_max_length), int(round(ratio * 100.0)), state,
		float(game.chain_integrity), float(game.CHAIN_INTEGRITY_MAX), float(game.team_overcharge) * 100.0,
	]


func _player_report(slot: int) -> String:
	var player = game.players[slot]
	var lines: Array[String] = []
	var color := "#43d9ff" if slot == 0 else "#d89cff"
	lines.append("[color=%s][b]%s  %s[/b][/color]  HP %.0f/%.0f%s" % [
		color, game.player_label(slot), player.character_name, player.health, player.max_health,
		"  [다운]" if player.downed else "",
	])
	lines.append("공격 %.0f%%      공속 %.0f%%      범위 %.0f%%      방어 %.1f      재생 %.1f/s" % [
		player.might * 100.0, (1.0 / maxf(0.01, player.haste)) * 100.0,
		player.area * 100.0, player.armor, player.recovery,
	])
	var weapons: Array = game.weapon_loadouts[slot]
	if weapons.is_empty():
		lines.append("무기  없음")
	else:
		for weapon_slot in weapons.size():
			var weapon: Dictionary = weapons[weapon_slot]
			lines.append("무기  %s  T%d%s      피해 %.1f      발동 %.2fs" % [
				String(weapon.get("weapon_name", weapon.get("weapon_id", "?"))),
				int(weapon.get("tier", 1)), " [진화]" if bool(weapon.get("evolved", false)) else "",
				float(weapon.get("damage", 0.0)), float(game._weapon_interval(slot, weapon_slot)),
			])
			var path := _fusion_path_report(slot, weapon)
			if not path.is_empty():
				lines.append(path)
	var treasure_bits: Array[String] = []
	for treasure: Dictionary in game.treasure_loadouts[slot]:
		treasure_bits.append("%s T%d%s" % [
			String(treasure.get("name", treasure.get("id", "?"))), int(treasure.get("tier", 1)),
			"  공유" if bool(treasure.get("shared", false)) else "",
		])
	lines.append("보물  %s" % ("없음" if treasure_bits.is_empty() else " / ".join(treasure_bits)))
	return "\n".join(lines)


func _resonance_report() -> String:
	var active: Array = game.resonance_system.active_resonances
	var bits: Array[String] = []
	for entry: Dictionary in active:
		bits.append("%s %.1fs" % [String(entry.get("name", entry.get("id", "?"))), maxf(0.0, float(entry.get("cooldown_remaining", 0.0)))])
	var result := "[color=#ff9fcb][b]RESONANCE[/b][/color]  활성 %d/%d  %s" % [
		active.size(), int(game.resonance_system.MAX_ACTIVE_RESONANCES),
		"없음" if bits.is_empty() else " / ".join(bits),
	]
	var candidates: Array = game.resonance_system.get_candidates_for_loadouts(
		game.weapon_loadouts[0], game.weapon_loadouts[1])
	if not candidates.is_empty():
		var candidate_names: Array[String] = []
		for candidate: Dictionary in candidates:
			var candidate_name := String(candidate.get("name", candidate.get("id", "?")))
			if candidate_name not in candidate_names:
				candidate_names.append(candidate_name)
		result += "\n대기 후보 %d개      %s" % [candidate_names.size(), " / ".join(candidate_names)]
	return result


func _fusion_path_report(_slot: int, weapon: Dictionary) -> String:
	if bool(weapon.get("evolved", false)):
		return ""
	var evolution := Evolutions.for_base(String(weapon.get("weapon_id", "")))
	if evolution.is_empty():
		return "      [color=#ff5d8f]↳ 진화 경로 없음[/color]"
	var weapon_tier := int(weapon.get("tier", 1))
	var evolution_ready := weapon_tier >= Evolutions.EVOLUTION_TIER
	return "      [color=%s]↳ %s      무기 %d/%d%s[/color]" % [
		"#80ed99" if evolution_ready else "#8298ad", String(evolution["weapon_name"]),
		weapon_tier, Evolutions.EVOLUTION_TIER,
		"  [자동 진화]" if evolution_ready else "",
	]


func _can_mutate_run() -> bool:
	if game.title_active or game.lobby_active or game.character_select_active or game.game_over:
		notice = "먼저 캐릭터를 선택해 런을 시작하세요."
		return false
	if game.level_up_active or game.resonance_vote_active or game.pause_active or game.cinematic_active:
		notice = "현재 선택/연출 화면을 닫은 뒤 다시 실행하세요."
		return false
	return true


func _cycle_speed() -> void:
	_mark_tainted()
	if debug_speed_index < 0:
		base_time_scale = Engine.time_scale
	debug_speed_index = (debug_speed_index + 1) % DEBUG_SPEEDS.size()
	Engine.time_scale = DEBUG_SPEEDS[debug_speed_index]
	notice = "시뮬레이션 속도 %s배" % _speed_text(Engine.time_scale)
	_refresh()


func _grant_level() -> void:
	if not _can_mutate_run():
		_refresh()
		return
	_mark_tainted()
	var needed := maxi(0, int(game.progression.required_experience) - int(game.progression.experience))
	game.progression.add_experience(needed)
	var before := int(game.progression.level)
	game._begin_level_up()
	notice = "레벨 %d → %d, 성장 카드 점검 화면을 열었습니다." % [before, int(game.progression.level)]
	_refresh()


func _prepare_fusions() -> void:
	if not _can_mutate_run():
		_refresh()
		return
	_mark_tainted()
	var prepared: Array[String] = []
	var blocked: Array[String] = []
	for slot in 2:
		var target_slot := -1
		var evolution: Dictionary = {}
		for weapon_slot in game.weapon_loadouts[slot].size():
			var weapon: Dictionary = game.weapon_loadouts[slot][weapon_slot]
			if bool(weapon.get("evolved", false)):
				continue
			var base_id := String(weapon.get("base_weapon_id", weapon.get("weapon_id", "")))
			if String(weapon.get("tech_id", "")).is_empty():
				var techs := WeaponTechs.for_weapon(base_id)
				if not techs.is_empty():
					WeaponTechs.apply_to_state(weapon, techs[0])
			evolution = Evolutions.for_base(base_id)
			if not evolution.is_empty():
				target_slot = weapon_slot
				break
		if target_slot < 0:
			blocked.append("%s 진화 가능한 기본 무기 없음" % game.player_label(slot))
			continue
		# The inspector temporarily supplies the route material at Lv.4, then
		# restores the loadout after the real evolution gate has run.
		while int(game.weapon_loadouts[slot][target_slot].get("tier", 1)) < Evolutions.EVOLUTION_TIER:
			game._apply_upgrade(slot, {"id": "weapon_power", "weapon_slot": target_slot})
		var required_id := String(game.weapon_loadouts[slot][target_slot].get("tech_synergy_treasure_id", ""))
		var material_slot := -1
		for index in game.treasure_loadouts[slot].size():
			if String(game.treasure_loadouts[slot][index]["id"]) == required_id:
				material_slot = index
				break
		var original_tier := 0
		if material_slot < 0:
			game.treasure_loadouts[slot].append({"id": required_id, "tier": Evolutions.REQUIRED_TREASURE_TIER})
		else:
			original_tier = int(game.treasure_loadouts[slot][material_slot]["tier"])
			game.treasure_loadouts[slot][material_slot]["tier"] = Evolutions.REQUIRED_TREASURE_TIER
		game._apply_pending_evolutions(slot)
		if material_slot < 0:
			game.treasure_loadouts[slot].pop_back()
		else:
			game.treasure_loadouts[slot][material_slot]["tier"] = original_tier
		prepared.append("%s %s" % [game.player_label(slot), String(evolution["weapon_name"])])
	if prepared.is_empty():
		notice = "진화 준비 실패: %s" % ", ".join(blocked)
		_refresh()
		return
	game.last_upgrade_choice_keys = [[], []]
	var needed := maxi(0, int(game.progression.required_experience) - int(game.progression.experience))
	game.progression.add_experience(needed)
	game._begin_level_up()
	notice = "진화 완료: %s%s" % [
		", ".join(prepared), "    " + ", ".join(blocked) if not blocked.is_empty() else "",
	]
	_refresh()


func _repair_team() -> void:
	if not _can_mutate_run():
		_refresh()
		return
	_mark_tainted()
	for player in game.players:
		if player.downed:
			player.revive()
		player.heal(player.max_health)
	game.chain_integrity = game.CHAIN_INTEGRITY_MAX
	game.chain_overloaded = false
	game._update_hud()
	notice = "두 생존자와 사슬 내구도를 완전히 복구했습니다."
	_refresh()


func _spawn_next_boss() -> void:
	if not _can_mutate_run():
		_refresh()
		return
	if game.wave_director.boss_active:
		notice = "이미 보스가 전투 중입니다."
		_refresh()
		return
	if int(game.wave_director.bosses_spawned) >= int(game.wave_director.BOSS_COUNT):
		notice = "모든 보스를 이미 소환했습니다."
		_refresh()
		return
	_mark_tainted()
	var center: Vector2 = (game.players[0].position + game.players[1].position) * 0.5
	var original_cap := int(game.wave_director.enemy_cap)
	# The command must still work while the ordinary-enemy cap is full. The cap
	# is restored immediately after WaveDirector has reserved the encounter.
	game.wave_director.enemy_cap = maxi(original_cap, game.enemies.size() + 40)
	var spawned: Array = game.wave_director.step(
		0.0, float(game.wave_director.next_boss_time()), center, game.enemies.size())
	game.wave_director.enemy_cap = original_cap
	for enemy in spawned:
		game._register_enemy(enemy)
	notice = "보스 %d와 전용 포위대를 소환했습니다." % int(game.wave_director.bosses_spawned)
	_refresh()


func _treasure_slot(player_slot: int, treasure_id: String) -> int:
	for index in game.treasure_loadouts[player_slot].size():
		if String(game.treasure_loadouts[player_slot][index].get("id", "")) == treasure_id:
			return index
	return -1


func _mark_tainted() -> void:
	if (not game.title_active and not game.lobby_active and not game.character_select_active
			and not game.game_over):
		game.debug_run_tainted = true


func _clock(seconds: float) -> String:
	var whole := maxi(0, int(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
