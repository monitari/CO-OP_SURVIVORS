class_name LightField
extends Node2D

## The roof answering the magic cast on it.
##
## The moonlight pass already separates an effect's body from its bloom, and the
## bloom is a picture of light: an additive shape drawn over the frame at the
## place the attack is. This is the other half, and it is a genuinely different
## technique — real Light2Ds, so the paving, the crates, the planters and the
## cats standing near a cast are *lit by it*, brighter on the side facing the
## attack, for as long as it lasts. A halo says "this is bright". A light says
## "the roof is standing next to something bright", which is the part of a night
## scene that cannot be faked by drawing another glow on top.
##
## Two rules keep it from becoming the permanent bloom pass the art direction
## rules out.
##
## **The budget is small and it is spent on what matters.** A screen full of
## lights is a screen with no dark left in it, and the whole look rests on a
## cold roof with warm magic on it. So there is a hard ceiling on how many exist
## at once, and a new light that cannot fit takes the place of the *weakest*
## one already burning rather than the oldest — a repeating weapon's faint pulse
## gives way to a resonance, never the other way round.
##
## **A repeating attack gets a weak light and a rare one gets a strong light.**
## The energies in WeaponController's cast table are deliberately an order of
## magnitude apart between a bolt that fires three times a second and a fused
## weapon that lands once in a while, because otherwise the roof simply sits at
## a constant raised brightness and none of it reads as an event.
##
## Every light is placed in world coordinates and pooled, so nothing here
## allocates mid-wave and the same piece of roof is lit the same way each time
## the pair crosses it.

## PointLight2Ds alive at once. Past roughly this many the roof stops having a
## dark side at all, which is the failure the art direction names.
const MAX_LIGHTS := 14
## Nothing may burn brighter than this. Additive light stacks, so the ceiling is
## per-light and the budget above is what bounds the sum.
const MAX_ENERGY := 0.42
## Shared by every pooled light; built once.
static var _radial: GradientTexture2D

## Off restores exactly the look the roof had before this existed: the drawn
## bodies and their glow layers, and no light cast back onto anything. For the
## on/off comparison this project uses to judge a visual change.
static var enabled := true

var _lights: Array[PointLight2D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _peak: PackedFloat32Array = PackedFloat32Array()
var _falloff: PackedFloat32Array = PackedFloat32Array()
## Live count, for tests and the profiler.
var burning := 0


## A light that flares and is gone. `strength` is its peak energy, `falloff` how
## sharply it decays — a hit wants to be felt and then out of the way, a field
## that lingers wants an even burn.
func flash(at: Vector2, tint: Color, radius: float, duration: float, strength: float, falloff := 2.4) -> void:
	if not enabled or not Moonlight.enabled or strength <= 0.0:
		return
	var slot := _free_slot(strength)
	if slot < 0:
		return
	var light := _lights[slot]
	light.global_position = at
	light.color = tint
	light.texture_scale = maxf(0.2, radius / 64.0)
	_age[slot] = 0.0
	_life[slot] = maxf(0.05, duration)
	_peak[slot] = clampf(strength, 0.0, MAX_ENERGY)
	_falloff[slot] = falloff
	light.energy = _peak[slot]
	light.visible = true


func _process(delta: float) -> void:
	if burning <= 0:
		return
	var live := 0
	for slot in _lights.size():
		var light := _lights[slot]
		if not light.visible:
			continue
		_age[slot] += delta
		var progress := clampf(_age[slot] / _life[slot], 0.0, 1.0)
		if progress >= 1.0:
			light.visible = false
			continue
		light.energy = _peak[slot] * pow(1.0 - progress, _falloff[slot])
		live += 1
	burning = live


## A slot for a light of this strength: a dark one if there is one, otherwise the
## dimmest thing currently burning, and only if this cast is brighter than it.
func _free_slot(strength: float) -> int:
	for slot in _lights.size():
		if not _lights[slot].visible:
			burning += 1
			return slot
	if _lights.size() < MAX_LIGHTS:
		_build_light()
		burning += 1
		return _lights.size() - 1
	var weakest := -1
	var weakest_energy := strength
	for slot in _lights.size():
		if _lights[slot].energy < weakest_energy:
			weakest_energy = _lights[slot].energy
			weakest = slot
	return weakest


func clear_all() -> void:
	for light in _lights:
		light.visible = false
	burning = 0


func _build_light() -> void:
	var light := PointLight2D.new()
	light.texture = _texture()
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	_lights.append(light)
	_age.append(0.0)
	_life.append(1.0)
	_peak.append(0.0)
	_falloff.append(2.4)


static func _texture() -> GradientTexture2D:
	if _radial != null:
		return _radial
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.82))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_radial = GradientTexture2D.new()
	_radial.width = 128
	_radial.height = 128
	_radial.fill = GradientTexture2D.FILL_RADIAL
	_radial.fill_from = Vector2(0.5, 0.5)
	_radial.fill_to = Vector2(1.0, 0.5)
	_radial.gradient = gradient
	return _radial


## A light that lives as long as the thing that owns it — a frost aura, a spilt
## pool of milk, a collapsing well. Parented to the effect rather than taken from
## the pool above, because the pool is for events and these are conditions: they
## must not be evicted by the next bolt, and they must travel with the field.
##
## `subtract` is for the one weapon that is a collapse. A gravity well that threw
## light would be the opposite of what it is; on SUB it takes the moonlight out
## of the floor it is pulling in, and the roof goes darker toward the middle of
## it. Nothing else in the game does this, which is the point.
static func attach(host: Node2D, tint: Color, radius: float, strength: float, subtract := false, minor := false) -> PointLight2D:
	if not enabled or not Moonlight.enabled or strength <= 0.0:
		return null
	if minor and not _minor_slot_free():
		return null
	var light := PointLight2D.new()
	light.texture = _texture()
	light.blend_mode = Light2D.BLEND_MODE_SUB if subtract else Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	light.color = tint
	light.texture_scale = maxf(0.2, radius / 64.0)
	light.energy = clampf(strength, 0.0, MAX_ENERGY)
	host.add_child(light)
	if minor:
		_minor_lights.append(light)
	return light


## Attached lights that are texture rather than information: the faint floor glow
## under a puddle of milk, of which a late run can have thirty. A 2D light costs
## every pixel it touches a pass through the lighting loop, and on the late-run
## benchmark thirty-one lights were three quarters of a millisecond of GPU time
## by themselves (tests/perf_bench_capture.gd, BENCH_LAYERS=1). The puddles past
## this many simply do not light the floor; at an energy of 0.09 nobody can tell
## which ones those are. Conditions that matter — a frost aura, a gravity well —
## are not minor and are never refused.
const MAX_MINOR_LIGHTS := 6
static var _minor_lights: Array[PointLight2D] = []


static func _minor_slot_free() -> bool:
	var live: Array[PointLight2D] = []
	for light in _minor_lights:
		if is_instance_valid(light) and not light.is_queued_for_deletion():
			live.append(light)
	_minor_lights = live
	return _minor_lights.size() < MAX_MINOR_LIGHTS
