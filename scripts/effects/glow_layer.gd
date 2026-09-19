class_name GlowLayer
extends Node2D
## The light half of an effect, kept as a separate canvas item from its body.
##
## The tempting way to make lightning glow is to hang an additive material on
## the bolt. It is also the way to lose it: additive blending drops whatever is
## darker than what it lands on, so an effect's outline and its shaded side
## disappear, and once several casts overlap the additions saturate and the
## screen resolves into one white shape with no attack legible inside it.
##
## So an effect draws its body normally — outline, shading, all of it — and
## hands the part that is actually emitting light to one of these, which sits
## one z-step above it with the shared additive material. Turning the moonlight
## pass off simply means no layer is attached and the effect is exactly what it
## was before.

## Draws this layer's contents. Takes the layer itself, so the painter can be a
## plain method on the effect and still draw in the layer's coordinate space —
## which is the parent's, since the layer never moves.
var painter := Callable()


## Attaches a glow to `host`, or returns null when the moonlight pass is off so
## callers can skip redrawing something that is not there.
static func attach(host: Node2D, draw_callable: Callable, z_offset := 1) -> GlowLayer:
	if not Moonlight.enabled:
		return null
	var layer := GlowLayer.new()
	layer.painter = draw_callable
	layer.material = Moonlight.additive()
	# Relative, so the glow follows wherever the effect's own z_index puts it
	# rather than pinning every halo in the game to one absolute depth.
	layer.z_as_relative = true
	# In front for effects whose glow is the outer edge of the thing, behind
	# for the ones with a crisp core the halo should spread out from.
	layer.z_index = z_offset
	host.add_child(layer)
	return layer


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:glow_layer", probe_started)


func _probed_draw() -> void:
	if painter.is_valid():
		painter.call(self)
