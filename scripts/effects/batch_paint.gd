class_name BatchPaint
extends RefCounted

## Collects many small shapes and hands them to the renderer as two commands.
##
## A canvas item that issues draw_circle, draw_arc, draw_polyline and
## draw_colored_polygon in turn gets a separate draw call for nearly every one of
## them, because the renderer can only merge consecutive commands of the same
## kind. A mine's rune ring was seventeen commands and thirty-odd draw calls; an
## orbit ring was four commands per shard. The shapes themselves are trivial —
## the cost was all in the switching.
##
## So a painter appends every filled shape into one triangle list (disjoint
## triangles are fine in a single RenderingServer triangle array) and every
## stroke into one segment list, and flushes each once. Strokes of different
## widths or colours still need separate flushes; callers group them.

var indices := PackedInt32Array()
var points := PackedVector2Array()
var colors := PackedColorArray()


func fill_circle(centre: Vector2, radius: float, color: Color, segments := 16) -> void:
	var hub := points.size()
	points.append(centre)
	colors.append(color)
	for step in segments:
		points.append(centre + Vector2.from_angle(TAU * float(step) / float(segments)) * radius)
		colors.append(color)
	for step in segments:
		indices.append(hub)
		indices.append(hub + 1 + step)
		indices.append(hub + 1 + (step + 1) % segments)


## A convex polygon as a fan from its first point.
func fill_polygon(outline: PackedVector2Array, color: Color) -> void:
	var first := points.size()
	for point in outline:
		points.append(point)
		colors.append(color)
	for step in range(1, outline.size() - 1):
		indices.append(first)
		indices.append(first + step)
		indices.append(first + step + 1)


## Any simple outline, concave included, as a fan from `hub` — which must see
## every edge, as the centre of a star does.
func fill_fan(hub: Vector2, outline: PackedVector2Array, color: Color) -> void:
	var centre := points.size()
	points.append(hub)
	colors.append(color)
	for point in outline:
		points.append(point)
		colors.append(color)
	for step in outline.size():
		indices.append(centre)
		indices.append(centre + 1 + step)
		indices.append(centre + 1 + (step + 1) % outline.size())


func flush(canvas: CanvasItem) -> void:
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
	indices.clear()
	points.clear()
	colors.clear()


## Appends an arc as line segments (pairs of points) for draw_multiline.
static func arc_segments(out: PackedVector2Array, centre: Vector2, radius: float, from: float, to: float, steps: int) -> void:
	var previous := centre + Vector2.from_angle(from) * radius
	for step in range(1, steps + 1):
		var next := centre + Vector2.from_angle(lerpf(from, to, float(step) / float(steps))) * radius
		out.append(previous)
		out.append(next)
		previous = next


## Appends a closed outline as line segments.
static func loop_segments(out: PackedVector2Array, outline: PackedVector2Array) -> void:
	for index in outline.size():
		out.append(outline[index])
		out.append(outline[(index + 1) % outline.size()])
