class_name Moonlight
extends RefCounted
## The rooftop has exactly one light, and it is up and to the left.
##
## Before this file every surface had its own private idea of where light came
## from. The crate threw its shadow down-right by six pixels, the vent by a
## different six, the yarn by five, and the survivors and the enemies threw
## nothing at all — so the roof read as a sheet of coloured shapes rather than
## as a place standing under a sky. Everything that draws ground now asks this
## one object which way the light runs, what a surface looks like under it, and
## what shape a shadow is.
##
## Two rules keep the night from costing the game its readability.
##
## The floor loses value and saturation; the actors do not. Darkening the whole
## frame is the obvious way to make a night scene and the wrong one here — an
## enemy that sinks into a dark roof is an enemy nobody dodges. So the grade
## applies to ground and props, and survivors, enemies and telegraphs keep the
## contrast they were designed with.
##
## Light that is *added* to the scene is drawn as its own layer, never as a
## blend mode over a whole effect. Additive blending over an effect's body eats
## its dark outline, and eight overlapping attacks stop being eight attacks and
## become one white slab. Bodies stay normally blended and the glow rides above
## them — see GlowLayer.

## Which way the moonlight travels, so this is also the way every shadow falls.
## Down and to the right, from a moon sitting off the upper-left corner.
const SHADOW_DIRECTION := Vector2(0.53, 0.848)
## The colour of the moon itself, used for lit edges and for the night cast.
const MOON := Color(0.78, 0.86, 1.0)
const SHADOW_INK := Color(0.043, 0.078, 0.129)
## Shadows on a top-down roof are the footprint of a thing, not a silhouette of
## it, so they are flattened hard along the light direction.
const SHADOW_SQUASH := 0.42
## How far out from under a body its contact shadow sits, as a share of radius.
## Small on purpose: this is the shadow of something standing on the roof, and
## pushing it further reads as the thing hovering.
const SHADOW_REACH := 0.34
## The grade applied to ground surfaces. Saturation drops further than value
## does, because what makes a daylit palette look like a night one is mostly
## the colour draining out of it, not the brightness.
const GROUND_SATURATION := 0.82
const GROUND_VALUE := 0.88
## How far a graded surface is pulled toward the moon's own colour at its own
## brightness. This used to be a per-channel multiply, which looked right on
## the blue-grey paving and destroyed everything warm: scaling red down and
## blue up took a wooden crate from brown to an exactly neutral grey in one
## step. A partial lerp cools every surface by the same amount while leaving
## the differences between them — which is the whole point of grading the roof
## rather than just tinting it.
const NIGHT_MIX := 0.24
## Additive alpha is a light budget rather than an opacity — two overlapping
## glows are twice as bright — so no single effect is allowed to spend more
## than this much of the frame on its own halo.
const GLOW_CEILING := 0.55

## The whole moonlight pass, on one switch, so the same scene can be compared
## with it and without it. F12 in a run. Off restores exactly the flat-lit look
## the rooftop had before: no grade, no contact shadows, no additive glow.
static var enabled := true

static var _additive: CanvasItemMaterial


## One shared additive material for every glow layer in the game. Godot batches
## by material, so sharing the instance is also what keeps a screenful of
## simultaneous glows from becoming a screenful of draw calls.
static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


## A surface lying on the roof, seen by moonlight. `lit` is how much of the
## moon this particular face catches: 0 for ground out in the open, up toward 1
## for an edge turned into the light.
static func ground(color: Color, lit := 0.0) -> Color:
	if not enabled:
		return color
	var graded := color
	graded.s = color.s * GROUND_SATURATION
	graded.v = color.v * GROUND_VALUE
	var cast := Color(MOON.r * graded.v, MOON.g * graded.v, MOON.b * graded.v, color.a)
	graded = graded.lerp(cast, NIGHT_MIX)
	if lit <= 0.0:
		return graded
	return graded.lerp(Color(MOON.r, MOON.g, MOON.b, color.a), lit * 0.5)


## The bright edge a solid catches on the side facing the moon. Callers guard
## this with `enabled` — an unlit roof has no rim to draw at all.
static func rim(color: Color, strength := 0.55) -> Color:
	return ground(color).lerp(MOON, strength)


## How far a solid of this height throws its shadow across the roof. Props pass
## their own height so a crate and a vent lid disagree about length but never
## about direction, which is the part the eye actually checks.
static func cast_offset(height: float) -> Vector2:
	return SHADOW_DIRECTION * height


## The common footing rule: a soft, flattened ellipse just off-centre along the
## light, in two passes so it has an edge that fades instead of a hard rim.
##
## `spin` cancels a rotated canvas. Enemies turn to face where they are going,
## and a shadow that turned with them would read as the roof tilting, so they
## pass their own negated rotation and the shadow stays flat on the ground.
static func ground_shadow(canvas: Node2D, at: Vector2, radius: float, strength := 1.0, spin := 0.0) -> void:
	if not enabled or radius <= 0.0:
		return
	var centre := at + (SHADOW_DIRECTION * radius * SHADOW_REACH).rotated(spin)
	canvas.draw_set_transform(centre, spin, Vector2(1.0, SHADOW_SQUASH))
	canvas.draw_circle(Vector2.ZERO, radius * 1.14, Color(SHADOW_INK, 0.12 * strength))
	canvas.draw_circle(Vector2.ZERO, radius * 0.80, Color(SHADOW_INK, 0.16 * strength))
	canvas.draw_set_transform(Vector2.ZERO)


## Clamps a halo to the light budget. Everything drawn into a GlowLayer should
## come through here rather than picking an alpha directly, so that no one
## effect can decide on its own to be the brightest thing on the roof.
static func glow(color: Color, strength: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(strength, 0.0, GLOW_CEILING))
