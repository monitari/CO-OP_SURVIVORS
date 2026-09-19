extends SceneTree

## A late-run frame, rebuilt the same way every time, and measured.
##
## Not a pass/fail test (the `_capture` suffix keeps it out of the suite loop):
## wall-clock numbers depend on the machine and on what else it is doing, so the
## output is for comparing a change against the commit before it on the same
## machine, not for asserting on.
##
##   godot --path . --script res://tests/perf_bench_capture.gd
##
## The scene is the one the performance complaint is actually about: the crowd
## at its cap, both survivors carrying four enhanced weapons grown through the
## real upgrade path to the tier ceiling, every offensive treasure maxed. Built
## through _apply_upgrade rather than by writing numbers into dictionaries, so a
## balance change that alters what a late weapon looks like moves the benchmark
## with it.
##
## Two measurements. LIVE runs the game and is what a player feels. FROZEN stops
## physics after the field has filled and redraws the same scene, which is the
## render cost alone — the difference between them is the simulation.

const MainScene := preload("res://scenes/main.tscn")
const TestHarness := preload("res://tests/test_harness.gd")
const Treasures := preload("res://scripts/catalogs/treasure_catalog.gd")
const Techs := preload("res://scripts/catalogs/weapon_tech_catalog.gd")
const Growth := preload("res://scripts/systems/weapon_growth.gd")

const CROWD := 620
const LOADOUTS := [["homing", "milk", "frost", "gravity"], ["flame", "orbit", "mine", "scythe"]]
const TREASURE_SET := ["might", "area", "amount", "haste"]
const WARMUP := 150
const LIVE_FRAMES := 360
const FROZEN_FRAMES := 240

var main: Node


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "PERF_BENCH_FAIL", 900.0)
	call_deferred("_run")


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	seed(20260919)
	await process_frame
	if not TestHarness.require_loaded(self, main, "PERF_BENCH_FAIL"):
		return
	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	await physics_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main.progression.required_experience = 1 << 30
	for slot in 2:
		main.players[slot].max_health = 1e9
		main.players[slot].health = 1e9
		_build(slot)
	main.players[0].position = Vector2(-110.0, 0.0)
	main.players[1].position = Vector2(110.0, 0.0)
	var crowd := int(OS.get_environment("BENCH_CROWD")) if OS.get_environment("BENCH_CROWD") != "" else CROWD
	for index in crowd:
		var enemy := main.wave_director._acquire_enemy("chaser", 1.0, Vector2.ZERO, false, false) as ChaserEnemy
		enemy.max_health = 1e12
		enemy.health = 1e12
		enemy.position = Vector2.from_angle(TAU * float(index) / 47.0) * (170.0 + float(index % 13) * 46.0)
		main._register_enemy(enemy)
	main.spatial_grid.rebuild(main.enemies)
	main.wave_director.set_physics_process(false)

	_apply_disables()
	for frame in WARMUP:
		_keep_alive()
		await physics_frame
	print("BENCH build P1 %s" % _loadout_text(0))
	print("BENCH build P2 %s" % _loadout_text(1))

	main.profile_totals.clear()
	main.profile_frames = 0
	main.profile_frame_usec.clear()
	main.profiling = true
	FrameProbe.clear()
	FrameProbe.enabled = true
	_hook_phases()
	var live := await _measure(LIVE_FRAMES, true)
	_unhook_phases()
	FrameProbe.enabled = false
	main.profiling = false
	_report("LIVE", live)
	_report_sections()
	_report_probe()
	_report_phases()
	_census()
	_callback_census()
	print("BENCH main tick avg %.2fms" % [_average(main.profile_frame_usec)])

	main.set_physics_process(false)
	main.weapon_controller.set_physics_process(false)
	await process_frame
	var frozen := await _measure(FROZEN_FRAMES, false)
	_report("FROZEN", frozen)
	if OS.get_environment("BENCH_LAYERS") != "":
		await _layer_sweep(frozen)
	print("BENCH_DONE")
	quit(0)


## One survivor at the end of a long run: four weapons grown to the ceiling on
## the route that focuses power, four treasures at their cap.
func _build(slot: int) -> void:
	main.weapon_loadouts[slot] = []
	main.attack_timers[slot] = []
	for weapon_id in LOADOUTS[slot]:
		for character in main.character_catalog:
			if String(character["weapon_id"]) == weapon_id:
				main._apply_upgrade(slot, {"id": "unlock_weapon", "weapon_slot": -1, "character": character})
	for weapon_slot in main.weapon_loadouts[slot].size():
		for step in 40:
			var state: Dictionary = main.weapon_loadouts[slot][weapon_slot]
			if int(state.get("tier", 1)) >= EvolutionCatalog.WEAPON_MAX_TIER:
				break
			if Growth.needs_tech(state):
				var routes: Array = Techs.for_weapon(Growth.base_id(state))
				main._apply_upgrade(slot, {"id": "choose_tech", "weapon_slot": weapon_slot, "tech": routes[0]})
				continue
			# Alternate the axes the way a real player spreads cards, so counts,
			# radii and cooldowns all reach where a late weapon has them.
			var axis: String = ["weapon_power", "special_a", "weapon_rate", "special_b"][step % 4]
			var option := {"id": axis, "weapon_slot": weapon_slot}
			if not main.UpgradeValue.has_effect(main, slot, option):
				option = {"id": "weapon_power", "weapon_slot": weapon_slot}
			main._apply_upgrade(slot, option)
			main._apply_pending_evolutions(slot)
	main.showcase_queue.clear()
	for treasure_id in TREASURE_SET:
		main._apply_upgrade(slot, {"id": "unlock_treasure", "weapon_slot": -1, "treasure": Treasures.by_id(treasure_id)})
		for tier in Treasures.MAX_TIER:
			for index in main.treasure_loadouts[slot].size():
				if String(main.treasure_loadouts[slot][index]["id"]) == treasure_id \
						and int(main.treasure_loadouts[slot][index]["tier"]) < Treasures.MAX_TIER:
					main._apply_upgrade(slot, {"id": "treasure_upgrade", "weapon_slot": -1, "treasure_slot": index})


func _keep_alive() -> void:
	for player in main.players:
		player.health = player.max_health
		player.downed = false
	if main.level_up_active or main.cinematic_active or main.resonance_vote_active:
		main.level_up_active = false
		main.cinematic_active = false
		main.resonance_vote_active = false
		main.level_overlay.visible = false
		main.get_tree().paused = false


func _measure(frames: int, live: bool) -> Dictionary:
	var samples := PackedFloat32Array()
	var draws := 0.0
	var objects := 0.0
	var primitives := 0.0
	var physics_ms := 0.0
	var process_ms := 0.0
	var last := Time.get_ticks_usec()
	for frame in frames:
		if live:
			_keep_alive()
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var sorted := Array(samples)
	sorted.sort()
	return {
		"p50": sorted[int(sorted.size() * 0.5)], "p90": sorted[int(sorted.size() * 0.9)],
		"p99": sorted[int(sorted.size() * 0.99)], "max": sorted[sorted.size() - 1],
		"draws": draws / frames, "objects": objects / frames, "primitives": primitives / frames,
		"physics": physics_ms / frames, "process": process_ms / frames,
	}


func _report(label: String, m: Dictionary) -> void:
	print("BENCH %-6s frame p50 %6.2fms  p90 %6.2fms  p99 %6.2fms  max %6.2fms | draw %5d  objects %6d  prims %7d | engine physics %5.2fms  process %5.2fms" % [
		label, m["p50"], m["p90"], m["p99"], m["max"],
		int(m["draws"]), int(m["objects"]), int(m["primitives"]), m["physics"], m["process"]])


func _report_sections() -> void:
	var frames := maxf(1.0, float(main.profile_frames))
	var keys: Array = main.profile_totals.keys()
	keys.sort_custom(func(a, b): return float(main.profile_totals[a]) > float(main.profile_totals[b]))
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s %.2f" % [key, float(main.profile_totals[key]) / frames / 1000.0])
	print("BENCH sections(ms/tick): " + "  ".join(parts))


func _census() -> void:
	var by_type: Dictionary = {}
	for child in main.weapon_controller.get_children():
		var key: String = child.get_class()
		if child.get_script() != null:
			key = String(child.get_script().resource_path).get_file()
		by_type[key] = int(by_type.get(key, 0)) + 1
	var lights := 0
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is PointLight2D and (node as PointLight2D).is_visible_in_tree():
			lights += 1
		for child in node.get_children():
			stack.append(child)
	print("BENCH census weapon_controller %s | visible PointLight2D %d | nodes %d" % [
		str(by_type), lights, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


func _loadout_text(slot: int) -> String:
	var parts: Array[String] = []
	for weapon in main.weapon_loadouts[slot]:
		parts.append("%s:%d" % [String(weapon["weapon_id"]), int(weapon.get("tier", 1))])
	return ", ".join(parts)


## Everything that ticks in its own node, per physics tick. Sections marked
## (incl) are nested inside others and are not additive with them.
func _report_probe() -> void:
	var ticks := maxf(1.0, float(main.profile_frames))
	var keys: Array = FrameProbe.totals.keys()
	keys.sort_custom(func(a, b): return int(FrameProbe.totals[a]) > int(FrameProbe.totals[b]))
	for key in keys:
		print("BENCH probe %-24s %7.2f ms/tick   %8.1f calls/tick" % [
			String(key), float(FrameProbe.totals[key]) / ticks / 1000.0, float(FrameProbe.calls[key]) / ticks])


## Where one frame's wall time actually goes, from the engine's own signals:
## physics ticks (and how many of them the frame had to run to catch up),
## _process, and the render submission between frame_pre_draw and
## frame_post_draw. The catch-up count is the thing to watch: once a frame costs
## more than one tick's worth, the next frame runs several ticks, which makes it
## slower still — the late game was spending most of its time in that spiral.
var _phase_at := 0
var _phase: Dictionary = {}
var _ticks_this_frame := 0
var _frames_seen := 0
var _tick_histogram: Dictionary = {}


var _markers: Array[Node] = []
var _callbacks_started := 0


func _hook_phases() -> void:
	for first in [true, false]:
		var marker: Node = load("res://tests/perf_tick_marker_capture.gd").new()
		marker.first = first
		marker.process_physics_priority = -1000000 if first else 1000000
		marker.stamped.connect(_on_marker)
		root.add_child(marker)
		_markers.append(marker)
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_phase.clear()
	_tick_histogram.clear()
	_frames_seen = 0
	_phase_at = Time.get_ticks_usec()


func _unhook_phases() -> void:
	for marker in _markers:
		marker.queue_free()
	_markers.clear()
	physics_frame.disconnect(_on_physics_frame)
	process_frame.disconnect(_on_process_frame)
	RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_on_post_draw)


func _stamp(label: String) -> void:
	var now := Time.get_ticks_usec()
	_phase[label] = int(_phase.get(label, 0)) + (now - _phase_at)
	_phase_at = now


func _on_physics_frame() -> void:
	if _ticks_this_frame == 0:
		_stamp("between frames")
	else:
		_stamp("physics ticks")
	_ticks_this_frame += 1


func _on_process_frame() -> void:
	_stamp("physics ticks" if _ticks_this_frame > 0 else "between frames")


func _on_pre_draw() -> void:
	_stamp("process + draw callbacks")


func _on_post_draw() -> void:
	_stamp("render submit")
	_tick_histogram[_ticks_this_frame] = int(_tick_histogram.get(_ticks_this_frame, 0)) + 1
	_ticks_this_frame = 0
	_frames_seen += 1


func _report_phases() -> void:
	var frames := maxf(1.0, float(_frames_seen))
	var parts: Array[String] = []
	for key in _phase:
		parts.append("%s %.2f" % [key, float(_phase[key]) / frames / 1000.0])
	print("BENCH phases(ms/frame): " + "  ".join(parts))
	var counts: Array = _tick_histogram.keys()
	counts.sort()
	var hist: Array[String] = []
	for key in counts:
		hist.append("%d틱×%d" % [int(key), int(_tick_histogram[key])])
	print("BENCH physics ticks per frame: " + "  ".join(hist))


## Every node that the engine calls back during a physics tick or a process
## frame, grouped by script. A callback that nobody wraps in a probe still shows
## up here, which is how the gap between the probes and the wall clock is found.
func _callback_census() -> void:
	var physics: Dictionary = {}
	var process: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var key: String = node.get_class()
		if node.get_script() != null:
			key = String(node.get_script().resource_path).get_file()
		if node.is_physics_processing():
			physics[key] = int(physics.get(key, 0)) + 1
		if node.is_processing():
			process[key] = int(process.get(key, 0)) + 1
	print("BENCH physics callbacks: " + str(physics))
	print("BENCH process callbacks: " + str(process))


func _average(values: PackedInt32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += value
	return float(total) / float(values.size()) / 1000.0


## BENCH_DISABLE=a,b,... switches pieces off for an A/B against the same scene.
func _apply_disables() -> void:
	var wanted := OS.get_environment("BENCH_DISABLE").split(",", false)
	if wanted.is_empty():
		return
	print("BENCH disabled: " + ", ".join(wanted))
	for item in wanted:
		match item:
			"numbers": main.feedback.damage_numbers_enabled = false
			"lights": LightField.enabled = false
			"moonlight": Moonlight.enabled = false; main._apply_moonlight()
			"hud": main.combat_hud.visible = false
			"main": main.set_physics_process(false)
			"hudtick": main.set_meta("bench_skip_hud", true)
			"combat": main.set_combat_visuals_enabled(false)
			"milk":
				for slot in 2:
					for weapon in main.weapon_loadouts[slot]:
						if String(weapon["weapon_id"]) in ["milk", "cream_tide"]:
							weapon["cooldown"] = 1e9
							weapon["base_cooldown"] = 1e9
			"fields":
				for slot in 2:
					for weapon in main.weapon_loadouts[slot]:
						if String(weapon["weapon_id"]) in ["absolute_zero", "celestial", "event_horizon", "black_moon"]:
							weapon["cooldown"] = 1e9
							weapon["base_cooldown"] = 1e9
			"weapons":
				for slot in 2:
					for weapon in main.weapon_loadouts[slot]:
						weapon["cooldown"] = 1e9
						weapon["base_cooldown"] = 1e9


func _on_marker(first: bool) -> void:
	if first:
		_stamp("tick: engine before scripts")
	else:
		_stamp("tick: scripts")


## BENCH_LAYERS=1: with the scene frozen, hides one layer at a time and reports
## what it was costing the renderer. Frozen so every arm draws the same scene.
func _layer_sweep(_base: Dictionary) -> void:
	# Paused, so every self-ticking effect stops where it is: a puddle that dries
	# up halfway through the sweep otherwise reads as whatever layer was hidden
	# at that moment being expensive.
	# Time stopped rather than the tree paused: a paused tree also stops the
	# battlefield buffer re-rendering (EndlessRooftopView freezes it on purpose),
	# and then there is no world to measure. At time scale zero every tick passes
	# a zero delta, so nothing ages, moves or expires, and every frame still draws.
	Engine.time_scale = 0.0
	await process_frame
	print("BENCH buffer %s (logical %s)" % [str(main.rooftop_view.surface.size), str(main.rooftop_view.surface.size_2d_override)])
	var layers := ["light_field_node", "moonlight", "display", "world_stage", "combat_hud", "crowd_renderer", "arena_floor", "rooftop_occlusion",
		"rooftop_props", "particles", "bursts", "flight_field", "weapon_controller", "chain_arc",
		"chain_flow", "item_aura", "hud_layer"]
	for layer in layers:
		if layer == "moonlight":
			var base_m := await _measure(90, false)
			Moonlight.enabled = false
			main._apply_moonlight()
			var off_m := await _measure(90, false)
			Moonlight.enabled = true
			main._apply_moonlight()
			_print_layer("moonlight(glow+lights)", base_m, off_m)
			continue
		var node = main.get(layer)
		if layer == "light_field_node":
			node = main.weapon_controller.light_field
		if layer == "display":
			node = main.rooftop_view.display
		if node == null or not is_instance_valid(node) or not ("visible" in node):
			print("BENCH layer %-18s (없음)" % layer)
			continue
		var was: bool = node.visible
		var base := await _measure(90, false)
		node.visible = false
		var m := await _measure(90, false)
		node.visible = was
		_print_layer(layer, base, m)
	# Children of the world stage, grouped by script, since that is where the
	# y-sorted scene lives.
	var groups: Dictionary = {}
	var sources: Array = main.world_stage.get_children()
	sources.append_array(main.weapon_controller.get_children())
	# The HUD, one level down, so a heavy widget type shows up by name.
	var hud_stack: Array[Node] = [main.combat_hud]
	while not hud_stack.is_empty():
		var hud_node: Node = hud_stack.pop_back()
		for hud_child in hud_node.get_children():
			hud_stack.append(hud_child)
			if hud_child is CanvasItem:
				hud_child.set_meta("bench_hud", true)
				sources.append(hud_child)
	for child in sources:
		var key: String = child.get_class()
		if child.get_script() != null:
			key = String(child.get_script().resource_path).get_file()
		if child.get_parent() == main.weapon_controller:
			key = "wc/" + key
		elif child.has_meta("bench_hud"):
			key = "hud/" + key
		if not groups.has(key):
			groups[key] = []
		groups[key].append(child)
	# Every light in the battlefield as one more group, wherever it is parented.
	var lights: Array = []
	var stack: Array[Node] = [main.rooftop_view.world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is PointLight2D and node.visible:
			lights.append(node)
		for child in node.get_children():
			stack.append(child)
	groups["PointLight2D (all)"] = lights
	for key in groups:
		var nodes: Array = groups[key]
		var states: Array = []
		for node in nodes:
			states.append(node.visible if "visible" in node else true)
		var base := await _measure(90, false)
		for node in nodes:
			if "visible" in node:
				node.visible = false
		var m := await _measure(90, false)
		for index in nodes.size():
			if "visible" in nodes[index]:
				nodes[index].visible = states[index]
		print("BENCH stage −%-26s ×%-4d draw Δ%+5d  prims Δ%+6d  p50 Δ%+5.2f" % [
			key, nodes.size(), int(m["draws"] - base["draws"]), int(m["primitives"] - base["primitives"]), m["p50"] - base["p50"]])


func _print_layer(layer: String, base: Dictionary, m: Dictionary) -> void:
	print("BENCH layer −%-22s p50 %5.2f→%5.2fms (Δ%+5.2f)  draw %4d→%4d  prims %6d→%6d" % [
		layer, base["p50"], m["p50"], m["p50"] - base["p50"], int(base["draws"]), int(m["draws"]),
		int(base["primitives"]), int(m["primitives"])])
