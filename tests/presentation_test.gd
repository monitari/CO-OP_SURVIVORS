extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const BurstFieldScript := preload("res://scripts/systems/burst_field.gd")
const EnemyScript := preload("res://scripts/entities/enemy.gd")
const TestHarness := preload("res://tests/test_harness.gd")

var failures: Array[String] = []


func _initialize() -> void:
	TestHarness.arm_watchdog(self, "PRESENTATION_FAIL", 60.0)
	call_deferred("_run")


## The review pass found that most of what the game does is invisible: enemies
## died with no effect, hits did not read on a dark field, overlays floated over
## live gameplay, and three edge indicators were built and never updated. These
## checks pin the fixes for those.
func _run() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	if not TestHarness.require_loaded(self, main, "PRESENTATION_FAIL"):
		return

	main.selected_character_indices[0] = 0
	main.selected_character_indices[1] = 1
	main.character_confirmed[0] = true
	main.character_confirmed[1] = true
	main._start_selected_run()
	main.set_physics_process(false)
	await process_frame

	# Before anything kills an enemy: the gems those kills drop are magneted in
	# immediately and the level-up they trigger would legitimately raise the dim.
	await _test_modal_dim(main)
	_test_bursts()
	_test_death_spawns_a_burst(main)
	_test_hit_flash(main)
	_test_no_per_hit_tween(main)
	_test_threat_indicator(main)
	_test_palette(main)
	_test_attack_ring_hierarchy(main)
	await _test_reactive_light_reuse(main)
	_test_layout(main)
	await _test_nothing_is_clipped(main)

	if failures.is_empty():
		print("PRESENTATION_PASS: kills burst, hits flash, overlays dim the field, threats point off screen")
		quit(0)
	else:
		for failure in failures:
			push_error("PRESENTATION_FAIL: " + failure)
		quit(1)


func _test_bursts() -> void:
	var field := BurstFieldScript.new() as BurstField
	root.add_child(field)
	field.spawn(Vector2.ZERO, Color.RED, 1.0)
	_check(field.bursts.size() == 1, "a burst is recorded")

	# It has to clean up after itself, or a three-minute run accumulates every
	# kill it ever drew.
	for tick in 60:
		field.step(1.0 / 60.0)
	_check(field.bursts.is_empty(), "a burst expires on its own (%d left)" % field.bursts.size())

	# And a wave of simultaneous deaths must not grow without bound.
	for index in BurstField.MAX_BURSTS * 3:
		field.spawn(Vector2(index, 0.0), Color.RED, 1.0)
	_check(field.bursts.size() <= BurstField.MAX_BURSTS,
		"simultaneous deaths stay under the cap (%d)" % field.bursts.size())

	field.clear_all()
	_check(field.bursts.is_empty(), "a new run starts with an empty field")
	field.free()


## Reactive lights expire independently. A strong Node reference left in the
## cap used to become an invalid freed instance when the next lightning cast
## tried to evict it.
func _test_reactive_light_reuse(main: Node) -> void:
	var controller: WeaponController = main.weapon_controller
	controller.clear_transients()
	for index in WeaponController.REACTIVE_LIGHT_CAP:
		controller._spawn_reactive_light(Vector2(index * 20.0, 0.0), Color.WHITE, 48.0, 0.06, 0.2)
	await create_timer(0.12).timeout
	await process_frame
	controller._spawn_reactive_light(Vector2.ZERO, Color.WHITE, 48.0, 0.06, 0.2)
	_check(controller.reactive_lights.size() == 1,
		"expired reactive lights are swept before the next cast (%d handles)" % controller.reactive_lights.size())
	if not controller.reactive_lights.is_empty():
		_check(controller.reactive_lights[0].get_ref() != null, "the retained reactive-light handle is live")
	controller.clear_transients()


func _test_death_spawns_a_burst(main: Node) -> void:
	main.bursts.clear_all()
	var enemy := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	enemy.position = Vector2(120.0, 40.0)
	main._register_enemy(enemy)
	enemy.take_damage(enemy.max_health * 2.0)
	_check(main.bursts.bursts.size() == 1, "killing an enemy leaves a burst behind")
	if main.bursts.bursts.size() == 1:
		var burst: Dictionary = main.bursts.bursts[0]
		_check((burst["position"] as Vector2).is_equal_approx(Vector2(120.0, 40.0)),
			"the burst is where the enemy died")

	# An elite death has to read louder than a trash mob's.
	main.bursts.clear_all()
	var elite := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, true, false) as ChaserEnemy
	elite.position = Vector2(-200.0, 0.0)
	main._register_enemy(elite)
	elite.take_damage(elite.max_health * 2.0)
	var elite_radius: float = float(main.bursts.bursts[0]["radius"])
	main.bursts.clear_all()
	var mob := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	mob.position = Vector2(-260.0, 0.0)
	main._register_enemy(mob)
	mob.take_damage(mob.max_health * 2.0)
	var mob_radius: float = float(main.bursts.bursts[0]["radius"])
	_check(elite_radius > mob_radius, "an elite death bursts bigger (%.0f vs %.0f)" % [elite_radius, mob_radius])
	main.bursts.clear_all()


func _test_hit_flash(main: Node) -> void:
	var enemy := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	enemy.position = Vector2(400.0, 0.0)
	main._register_enemy(enemy)
	enemy.take_damage(1.0)
	_check(enemy.hit_flash > 0.0, "a surviving enemy flashes when hit")
	_check(enemy.scale.x > 1.0, "and pops")

	# The flash must clear, or every enemy that ever took a hit stays white.
	for tick in int(ChaserEnemy.HIT_FLASH_TIME * 60.0) + 4:
		enemy.step(main.players, 1.0 / 60.0)
	_check(is_equal_approx(enemy.hit_flash, 0.0), "the flash fades (%.3f)" % enemy.hit_flash)
	_check(absf(enemy.scale.x - 1.0) < 0.01, "the pop settles back (%.3f)" % enemy.scale.x)
	enemy.take_damage(enemy.max_health * 2.0)
	main.bursts.clear_all()


## The pop used to allocate a Tween per hit. Late in a run that is hundreds of
## short-lived objects a second.
func _test_no_per_hit_tween(_main: Node) -> void:
	# Unregistered on purpose: main routes damage_taken into the floating damage
	# numbers, which tween by design. What is being measured here is whether the
	# enemy's own hit pop still allocates one per hit.
	# Built directly rather than through the pool: a recycled enemy keeps the
	# signal connections main gave it, and main routes damage_taken into the
	# floating damage numbers, which tween by design. What is measured here is
	# the enemy's own hit pop.
	var enemy := EnemyScript.new() as ChaserEnemy
	root.add_child(enemy)
	enemy.setup(0.0, "chaser")
	var before := enemy.get_tree().get_processed_tweens().size()
	for index in 40:
		enemy.take_damage(0.01)
	var after := enemy.get_tree().get_processed_tweens().size()
	_check(after == before, "forty hits allocate no tweens (%d -> %d)" % [before, after])
	enemy.free()


func _test_modal_dim(main: Node) -> void:
	main.set_physics_process(true)
	# Re-enabling physics does not take effect until the following frame, so
	# the first one still carries the character-select state this test set up.
	await physics_frame
	await physics_frame
	_check(not main.modal_dim.visible, "ordinary play is undimmed")

	main.level_up_active = true
	await physics_frame
	_check(main.modal_dim.visible, "a level-up dims the field behind the cards")
	main.level_up_active = false

	main.pause_active = true
	await physics_frame
	_check(main.modal_dim.visible, "so does the pause screen")
	main.pause_active = false
	await physics_frame
	_check(not main.modal_dim.visible, "and the dim lifts when the overlay closes")
	main.set_physics_process(false)

	_check(main.modal_dim.size == Vector2(1280.0, 720.0), "the dim covers the whole screen")


func _test_threat_indicator(main: Node) -> void:
	main.world_camera.position = Vector2.ZERO
	for candidate in main.enemies.duplicate():
		main._cull_enemy(candidate)

	# An ordinary mob off screen is not worth an arrow; a swarm would fill the
	# edge with them.
	var mob := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, false, false) as ChaserEnemy
	mob.position = Vector2(2000.0, 0.0)
	main._register_enemy(mob)
	main._update_threat_indicator()
	_check(not main.threat_edge_indicator.visible, "an off-screen trash mob raises no indicator")

	var elite := main.wave_director._acquire_enemy("chaser", 0.0, Vector2.ZERO, true, false) as ChaserEnemy
	elite.position = Vector2(2000.0, 0.0)
	main._register_enemy(elite)
	main._update_threat_indicator()
	_check(main.threat_edge_indicator.visible, "an off-screen elite does")
	_check(main.threat_edge_indicator.position.x > 640.0,
		"the indicator sits on the side the elite is on (x=%.0f)" % main.threat_edge_indicator.position.x)
	var pinned: Vector2 = main.threat_edge_indicator.position
	_check(pinned.x <= 1280.0 and pinned.y >= 0.0 and pinned.y <= 720.0,
		"the indicator stays on screen (%s)" % str(pinned))

	# Once it is in view there is nothing to point at.
	elite.position = Vector2(120.0, 30.0)
	main._update_threat_indicator()
	_check(not main.threat_edge_indicator.visible, "an elite in view needs no indicator")

	for candidate in main.enemies.duplicate():
		main._cull_enemy(candidate)
	main.bursts.clear_all()


## Two colours in the palette collided: the boss was 9b5de5 and 볼타 is b892ff,
## so the thing hunting you and a person chained to you were the same purple.
## Exact inequality would not have caught that — they were different values of
## the same colour — so this measures distance instead.
func _test_palette(main: Node) -> void:
	var boss := EnemyScript.new() as ChaserEnemy
	boss.setup(4.0, "brute", true, true)
	var closest := 99.0
	var closest_name := ""
	for character in CharacterCatalog.all_characters():
		var colour := Color(character["color"])
		var distance := Vector3(
			colour.r - boss.enemy_color.r,
			colour.g - boss.enemy_color.g,
			colour.b - boss.enemy_color.b
		).length()
		if distance < closest:
			closest = distance
			closest_name = String(character["name"])
	boss.free()
	_check(closest > 0.35,
		"the boss colour is not mistakable for a survivor (nearest %s at %.2f)" % [closest_name, closest])
	var partner_frame := main.combat_hud.get_node("P2Frame") as Panel
	var partner_surface := partner_frame.get_theme_stylebox("panel") as StyleBoxFlat
	_check(partner_surface.border_color.is_equal_approx(Color(main.CatTheme.P2, 0.42)),
		"partner HUD owns the warm orange colour")


## Friendly rings and enemy telegraphs both draw circles on the field, and the
## pair has to tell them apart instantly. That used to be enforced by keeping
## friendly rings dim and thin — which worked, and then kept working past the
## point of usefulness: they became so faint that a firing weapon read as a
## smudge.
##
## The distinction is a temporal one, not a brightness one. A friendly ring
## flashes once and is gone inside a fraction of a second; an enemy telegraph
## sits there filling up for well over a second before it lands. Nothing that
## disappears that fast can be mistaken for something you have to dodge, so the
## ring is free to be as legible as it likes.
func _test_attack_ring_hierarchy(main: Node) -> void:
	var before: int = main.weapon_controller.get_child_count()
	main.weapon_controller._draw_ring(Vector2.ZERO, 200.0, Color("43d9ff"), 12.0)
	_check(main.weapon_controller.get_child_count() == before + 2, "an area attack creates a filled footprint and one ring")
	var fill := main.weapon_controller.get_child(main.weapon_controller.get_child_count() - 2) as Polygon2D
	_check(fill != null and fill.polygon.size() >= 32, "the attack radius is represented by a filled area")
	var ring := main.weapon_controller.get_child(main.weapon_controller.get_child_count() - 1) as Line2D
	_check(ring != null, "the ring is a drawable line")
	if ring == null:
		return

	# Legible: the old ceilings were 4px and 34% alpha, which is what made a
	# cast invisible in the first place.
	_check(ring.width >= 5.0, "a friendly ring is thick enough to see (width %.1f)" % ring.width)
	_check(ring.default_color.a >= 0.6, "and solid enough to see (alpha %.2f)" % ring.default_color.a)

	# Transient: comfortably shorter-lived than the shortest enemy telegraph.
	var ring_lifetime := 0.0
	for tween in main.weapon_controller.get_tree().get_processed_tweens():
		if tween.is_valid():
			ring_lifetime = maxf(ring_lifetime, tween.get_total_elapsed_time())
	_check(main.weapon_controller.RING_HOLD + main.weapon_controller.RING_FADE < ChaserEnemy.BOSS_SLAM_WINDUP_ENRAGED * 0.5,
		"a friendly ring is gone long before an enemy telegraph would land (%.2fs vs %.2fs)" % [
			main.weapon_controller.RING_HOLD + main.weapon_controller.RING_FADE,
			ChaserEnemy.BOSS_SLAM_WINDUP_ENRAGED,
		])
	ring.queue_free()


func _test_layout(main: Node) -> void:
	_check(is_equal_approx(main.p1_health_bar.position.y, main.p2_health_bar.position.y),
		"both player health bars share a baseline")
	_check(main.p1_health_text_label.position == main.p1_health_bar.position
		and main.p1_health_text_label.size == main.p1_health_bar.size,
		"P1 health text is aligned inside its bar")
	for pair in [[main.chain_distance_text_label, main.chain_bar], [main.chain_integrity_text_label, main.chain_integrity_bar], [main.xp_text_label, main.xp_bar]]:
		var caption: Label = pair[0]
		var meter: ProgressBar = pair[1]
		_check(is_equal_approx(caption.position.x, meter.position.x) and is_equal_approx(caption.size.x, meter.size.x),
			"upper HUD labels align with their meter widths")
		_check(caption.position.y + caption.size.y <= meter.position.y and meter.position.y < 130,
			"meter labels stay above the thin top bars without overlapping their fill")
	_check(main.level_overlay.position.y >= main.chain_integrity_bar.position.y + main.chain_integrity_bar.size.y,
		"the level-up panel starts below the chain bars")
	# The largest text on screen used to land on top of the two survivors.
	_check(main.message_label.position.y > 480.0,
		"the message banner is clear of the play area (y=%.0f)" % main.message_label.position.y)
	# Two smoothers stacked meant every camera move was damped twice.
	_check(not main.world_camera.position_smoothing_enabled,
		"only the manual camera lerp smooths the view")
	# Cards at 142px fit about seven Korean glyphs a line.
	_check(main.LEVEL_CARD_WIDTH >= 165.0,
		"level-up cards are wide enough for Korean text (%.0f)" % main.LEVEL_CARD_WIDTH)
	var half_width: float = main.LEVEL_CARD_WIDTH * 3.0 + main.LEVEL_CARD_GAP * 2.0
	_check(596.0 + half_width <= main.level_overlay.size.x,
		"both card halves fit inside the overlay (%.0f of %.0f)" % [596.0 + half_width, main.level_overlay.size.x])
	var bounded_labels: Array = [
		main.p1_status_label, main.p2_status_label, main.hud_label,
		main.chain_status_label, main.resonance_status_label,
		main.message_label, main.character_p1_label, main.character_p2_label,
		main.character_synergy_label, main.resonance_status,
		main.pause_label, main.result_label,
	]
	for label: Label in bounded_labels:
		_check(label.clip_text, "%s clips text to its UI bounds" % label.name)
	for player_cards: Array in main.level_card_labels:
		for card: Label in player_cards:
			_check(card.clip_text, "level-up cards clip text to their UI bounds")


## Every fixed-size HUD label is built with clip_text on, which cuts overflow
## silently — no warning, no ellipsis, the text is simply not there. The result
## screen grew past its box exactly that way and lost both the co-op tally and
## the line telling a dead pair how to restart. Godot reports the two counts
## needed to catch it: how many lines the text wraps to, and how many of those
## actually fit.
func _test_nothing_is_clipped(main: Node) -> void:
	# _begin_level_up returns early unless a level-up is actually pending, and
	# an early return leaves every card empty — which is a guard that measures
	# nothing at all.
	main.progression.experience = main.progression.required_experience
	main._begin_level_up()
	_check(main.level_overlay.visible, "the level-up screen actually opened")
	_check(String(main.level_card_labels[0][0].text).length() > 0, "the cards actually carry text")
	await process_frame
	await process_frame
	for slot in 2:
		for index in 3:
			_check_fits("P%d의 %d번 카드" % [slot + 1, index + 1], main.level_card_labels[slot][index])
	_check_fits("P1 빌드 요약", main.p1_level_footer)
	_check_fits("P2 빌드 요약", main.p2_level_footer)
	main.level_up_active = false

	main._end_run(true)
	await process_frame
	await process_frame
	_check_fits("결과 화면", main.result_label)

	# Character select carries the fullest text block in the game now — every
	# stat, the fusion it leads to and a difficulty read — so it is the screen
	# most likely to quietly outgrow its box.
	main.character_overlay.visible = true
	main._refresh_character_select_ui()
	await process_frame
	_check_fits("P1 선택 카드", main.character_p1_label)
	_check_fits("P2 선택 카드", main.character_p2_label)
	_check_fits("예상 공명", main.character_synergy_label)
	main.character_overlay.visible = false
	# Naming the tail explicitly: this is the line that went missing, and it is
	# the only thing on screen telling the pair how to leave the finished run.
	var text: String = main.result_label.text
	_check(text.ends_with("ENTER / A  메인 메뉴로"),
		"the result screen ends with the action it actually performs")


func _check_fits(name: String, label: Label) -> void:
	var wrapped := label.get_line_count()
	var shown := label.get_visible_line_count()
	_check(wrapped <= shown, "%s의 텍스트가 잘리지 않는다 (%d줄 중 %d줄만 보임)" % [name, wrapped, shown])


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
