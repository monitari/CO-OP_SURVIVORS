extends Control

var cat: ChainPlayer
var character_id := ""
var arena: SubViewport
var controller: WeaponController
var enemies: Array[ChaserEnemy] = []
var actors: Array[ChainPlayer] = []
var grid := EnemySpatialGrid.new()
var caption: Label
var timer := 0.0
var cooldown := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var display := SubViewportContainer.new()
	display.size = Vector2(330, 130)
	display.stretch = true
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	arena = SubViewport.new()
	arena.size = Vector2i(660, 260)
	arena.transparent_bg = true
	arena.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	display.add_child(arena)
	# Explicit texture sizing keeps world distances independent of UI scale.
	display.stretch = false
	display.size = Vector2(660, 260)
	arena.size = Vector2i(660, 260)
	display.scale = Vector2.ONE * 0.5
	caption = Label.new()
	caption.position = Vector2(0, 132)
	caption.size = Vector2(330, 43)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 13)
	add_child(caption)

func set_character(character: Dictionary, weapon: Dictionary = {}) -> void:
	if arena == null or character_id == String(character["id"]):
		return
	character_id = String(character["id"])
	for child in arena.get_children():
		child.free()
	enemies.clear()
	actors.clear()
	grid = EnemySpatialGrid.new()
	for slot in 2:
		var player := ChainPlayer.new()
		player.input_source = ChainPlayer.InputSource.AI
		player.setup(slot + 1, Color.WHITE)
		player.apply_character(character)
		player.display_name = "나" if slot == 0 else "동료"
		arena.add_child(player)
		player.position = Vector2(230 + slot * 190, 135)
		actors.append(player)
	cat = actors[0]
	actors[1].visible = String(character["weapon_id"]) == "chain"
	for index in 7:
		var enemy := ChaserEnemy.new()
		arena.add_child(enemy)
		enemy.setup(1.0)
		enemy.remove_from_group("enemies")
		enemy.health = 100000.0
		enemy.position = Vector2(340, 130) + Vector2.from_angle(index * TAU / 7.0) * Vector2(150, 80)
		enemies.append(enemy)
	grid.rebuild(enemies)
	var state := weapon.duplicate(true)
	if state.is_empty():
		state = character["weapon"].duplicate(true)
		for key in ["weapon_id", "color", "tags"]:
			state[key] = character[key]
	controller = WeaponController.new()
	arena.add_child(controller)
	controller.configure(actors, [[state], []], grid)
	cooldown = maxf(0.5, float(state["cooldown"]) * cat.haste)
	timer = 0.1
	var explanation := {
		"homing": "별이 가까운 적을 추적해 맞힙니다.",
		"lightning": "가까운 적에서 다음 적으로 번개가 이어집니다.",
		"flame": "사방으로 불씨를 쏘아 여러 적을 공격합니다.",
		"frost": "주변 원 안의 적을 공격하고 느리게 합니다.",
		"scythe": "적을 향해 넓은 부채꼴로 휩씁니다.",
		"chain": "나와 동료를 잇는 사슬에 닿은 적을 공격합니다.",
		"orbit": "파편이 내 주변을 돌며 닿은 적을 공격합니다.",
		"lance": "일직선 위의 적을 한꺼번에 관통합니다.",
		"mine": "설치한 결계에 적이 다가오면 폭발합니다.",
		"gravity": "적이 모인 곳을 끌어당겨 공격합니다.",
		"boomerang": "던진 장난감이 돌아와 반대쪽까지 지나갑니다.",
		"milk": "주변에 깐 웅덩이가 지속 피해와 둔화를 줍니다."
	}
	caption.text = String(character["weapon_name"]) + " · 실제 무기 시연\n" + String(explanation.get(character["weapon_id"], character["description"]))

func _process(delta: float) -> void:
	if arena == null:
		return
	arena.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
	if not is_visible_in_tree() or controller == null:
		return
	for enemy in enemies:
		enemy.health = 100000.0
		enemy.step(actors, delta)
		if enemy.position.distance_to(cat.position) < 42.0:
			enemy.position += (enemy.position - cat.position).normalized() * 130.0
	grid.rebuild(enemies)
	controller.elapsed += delta
	timer -= delta
	if timer <= 0.0:
		timer += cooldown
		controller.perform_attack(0, 0, 1.0)
