class_name RooftopOcclusion
extends Node2D
## A restrained see-through read for a survivor hidden by tall roof furniture.
##
## The furniture is allowed to stand in front of a cat — that is the whole point
## of giving it height — so this is what keeps a hidden cat playable: its outline
## and the ring where it stands, drawn over everything, only while enough of it
## is actually covered to need them.

## Share of a body that has to be covered before the outline appears. Grazing a
## table leg is not hiding.
const HIDDEN_SHARE := 0.34
## Share at which the furniture itself starts to thin. Lower than the outline's,
## so the piece eases off a little before the outline has to take over.
const THIN_SHARE := 0.22
var players: Array[ChainPlayer] = []
var prop_field: RooftopPropField


func configure(survivors: Array[ChainPlayer], field: RooftopPropField) -> void:
	players = survivors
	prop_field = field
	z_index = 9


func step() -> void:
	queue_redraw()


## The screen area a survivor's drawing occupies, in the stage's coordinates:
## from the ears down to the paws, around the lifted body.
static func body_rect(player: ChainPlayer) -> Rect2:
	var at := player.global_position + RooftopSpace.lift(player.stand_height)
	var reach := player.radius
	return Rect2(at.x - reach, at.y - reach * 1.45, reach * 2.0, reach * 2.8)


static func covered_share(body: Rect2, cover: Rect2) -> float:
	var overlap := body.intersection(cover)
	return overlap.size.x * overlap.size.y / maxf(1.0, body.size.x * body.size.y)


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:rooftop_occlusion", probe_started)


func _probed_draw() -> void:
	if not is_instance_valid(prop_field):
		return
	var covers := prop_field.living_props()
	for player in players:
		if not is_instance_valid(player) or not hidden(player, covers):
			continue
		var at := player.global_position + RooftopSpace.lift(player.stand_height)
		var tint := player.body_color
		# The translucent body says who is behind the solid; the floor ring says
		# exactly where that survivor still stands.
		draw_circle(player.global_position, player.radius * 0.72, Color(tint, 0.08))
		draw_arc(player.global_position, player.radius * 0.82, 0.0, TAU, 28, Color(tint, 0.72), 2.0, true)
		draw_circle(at, player.radius, Color(tint, 0.16))
		draw_arc(at, player.radius + 2.0, 0.0, TAU, 32, Color(tint.lightened(0.35), 0.78), 2.4, true)
		for side: float in [-1.0, 1.0]:
			var ear := PackedVector2Array([
				at + Vector2(side * 7.0, -player.radius * 0.72),
				at + Vector2(side * 18.0, -player.radius * 1.38),
				at + Vector2(side * 21.0, -player.radius * 0.45),
			])
			draw_polyline(ear, Color(tint.lightened(0.35), 0.78), 2.4, true)


func hidden(player: ChainPlayer, covers: Array[RoofDecor]) -> bool:
	var body := body_rect(player)
	for prop in covers:
		if prop.modulate.a < 0.4 or not prop.bulky() or not RooftopSpace.in_front_of(prop.ground.y, player.global_position.y):
			continue
		if covered_share(body, prop.screen_rect()) >= HIDDEN_SHARE:
			return true
	return false
