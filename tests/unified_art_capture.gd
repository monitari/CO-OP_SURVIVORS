extends SceneTree
const Icons := preload("res://scripts/ui/icon_catalog.gd")
const Enemies := preload("res://scripts/ui/enemy_icons.gd")
const Font := preload("res://assets/fonts/Jua-Regular.ttf")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var canvas := Control.new()
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color("243b43")
	bg.size = Vector2(1280, 720)
	canvas.add_child(bg)
	caption(canvas, "달빛 옥상 · 통합 아트", Vector2(28, 16), 28)
	caption(canvas, "기존 아틀라스와 신규 에셋 · 동일 화면 크기 비교", Vector2(28, 51), 16)
	var cats := ["lyra", "ignis", "neve", "echo", "latte"]
	for index in cats.size(): tile(canvas, Icons.survivor(cats[index]), cats[index], Vector2(30 + index * 155, 82))
	var weapons := ["homing", "gravity", "boomerang", "milk", "skipping_stone", "cream_tide"]
	for index in weapons.size(): tile(canvas, Icons.weapon(weapons[index]), weapons[index], Vector2(30 + index * 155, 285))
	var enemies := ["chaser", "charger", "rat_runner", "wasp", "hedgehog", "mole", "owl"]
	for index in enemies.size(): tile(canvas, Enemies.get_icon(enemies[index]), enemies[index], Vector2(30 + index * 155, 488))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot_runtime/unified-art.png")
	print("UNIFIED_ART_CAPTURE_PASS")
	quit()

func caption(parent: Control, text: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", Font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff9ea"))
	parent.add_child(label)

func tile(parent: Control, texture: Texture2D, title: String, at: Vector2) -> void:
	var art := TextureRect.new()
	art.texture = texture
	art.position = at
	art.size = Vector2(132, 132)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(art)
	caption(parent, title, at + Vector2(0, 137), 16)
