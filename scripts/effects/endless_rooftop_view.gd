class_name EndlessRooftopView
extends Node
## A gently tilted battlefield, rendered with overscan. Simulation nodes retain
## their original ground coordinates; HUD and menus stay on the main viewport.
const OVERSCAN := 1.5
const TILT := 0.86
const PERSPECTIVE := 0.18
const ViewShader := preload("res://scripts/effects/endless_rooftop.gdshader")
var surface: SubViewport
var world: Node2D
var display: TextureRect
var view_size := Vector2(1280, 720)


func _ready() -> void:
	surface = SubViewport.new()
	surface.disable_3d = true
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.handle_input_locally = false
	add_child(surface)
	world = Node2D.new()
	world.name = "Battlefield"
	surface.add_child(world)
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	display = TextureRect.new()
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture = surface.get_texture()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = ViewShader
	display.material = shader_material
	layer.add_child(display)
	get_viewport().size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	view_size = get_viewport().get_visible_rect().size
	surface.size = Vector2i((view_size * OVERSCAN).ceil())
	display.size = view_size


func adopt(node: Node) -> void:
	node.reparent(world, true)


## Forward/inverse of the shader mapping, in logical screen pixels.
func project_offset(offset: Vector2) -> Vector2:
	var p := offset / view_size
	var scale_at_depth := 1.0 / (1.0 - PERSPECTIVE * p.y)
	return Vector2(p.x, p.y * TILT) * scale_at_depth * view_size


func unproject_offset(offset: Vector2) -> Vector2:
	var p := offset / view_size
	return Vector2(p.x / (1.0 + PERSPECTIVE * p.y / TILT),
		p.y / (TILT + PERSPECTIVE * p.y)) * view_size


func visible_bounds(centre: Vector2, zoom: Vector2) -> Rect2:
	var half := view_size * 0.5
	var bounds := Rect2(centre + unproject_offset(-half) / zoom, Vector2.ZERO)
	for corner in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		bounds = bounds.expand(centre + unproject_offset(corner) / zoom)
	return bounds
