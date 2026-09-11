class_name ReactiveLight
extends PointLight2D
## A brief pool of light cast back onto the roof by a major hit or spell.
##
## These are deliberately scarce and short lived. Additive effect art says
## that an attack emits; this light is the quieter second half that lets the
## floor and nearby bodies answer it without turning the whole arena into a
## permanent bloom pass.

static var _radial_texture: GradientTexture2D

var age := 0.0
var lifetime := 0.18
var peak_energy := 0.28


func setup(at: Vector2, tint: Color, radius: float, duration: float, strength: float) -> void:
	global_position = at
	color = tint
	lifetime = maxf(0.06, duration)
	peak_energy = clampf(strength, 0.0, 0.42)
	energy = peak_energy
	texture = _texture()
	texture_scale = maxf(0.2, radius / 64.0)
	blend_mode = Light2D.BLEND_MODE_ADD
	shadow_enabled = false


func _process(delta: float) -> void:
	age += delta
	var progress := clampf(age / lifetime, 0.0, 1.0)
	# A fast attack and a slow glow tail: the light is felt on impact and is
	# already out of the way before the next combat decision.
	energy = peak_energy * pow(1.0 - progress, 2.4)
	if age >= lifetime:
		queue_free()


static func _texture() -> GradientTexture2D:
	if _radial_texture != null:
		return _radial_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.82))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_radial_texture = GradientTexture2D.new()
	_radial_texture.width = 128
	_radial_texture.height = 128
	_radial_texture.fill = GradientTexture2D.FILL_RADIAL
	_radial_texture.fill_from = Vector2(0.5, 0.5)
	_radial_texture.fill_to = Vector2(1.0, 0.5)
	_radial_texture.gradient = gradient
	return _radial_texture
