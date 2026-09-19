class_name ParticleField
extends Node2D

## Small, short-lived feedback marks — footfall dust, hit sparks, dash
## afterimages, pickup motes — all drawn in one pass from one node.
##
## The game already had BurstField for enemy deaths, and it works for the same
## reason this does: at a few hundred events a second, a Node2D plus a tween per
## effect is a stall, while one array and one _draw() is not. This is deliberately
## the second such node rather than an extension of the first, because a death
## burst is a gameplay event the player is meant to read and these are texture —
## they are capped harder, they never outlive a third of a second, and losing
## some of them under load is the correct behaviour.
##
## Everything here is cosmetic. Nothing in this file may affect play.

const MAX_PARTICLES := 260
## Marks this field will accept between two steps.
##
## The cap above bounds what is *drawn*; this bounds what it costs to ask. A
## dense late tick reports tens of thousands of hits — an area weapon landing on
## a packed crowd, or one piercing shot crossing a hundred bodies — and every one
## of them asked for sparks. Each request built a Dictionary and then, once the
## field was full, shifted a 260-entry array down by one to make room for a mark
## that the next request would immediately evict. Practically all of that work
## was thrown away in the same tick it was done.
##
## So the field stops listening once it has taken a frame's worth. The marks it
## already has are exactly as good as the ones it is refusing — they are the same
## sparks from the same volley — and this file's rule has always been that losing
## some of them under load is correct.
##
## It was 120, five times what the field can hold. A mark lives a fifth to a
## third of a second and at most MAX_PARTICLES are alive, so past about twenty
## new marks a tick each one arrives only to evict one still on screen — a
## hundred dictionaries a tick built to replace sparks that looked the same.
const MAX_EMITTED_PER_STEP := 24

## Kinds, and what each one is for:
##   dust   a soft puff left under a moving survivor, so running reads as running
##   spark  a thrown shard, so a hit reads as a hit and not as a number changing
##   ring   an expanding outline, for a dash afterimage or a pickup pop
##   mote   a slow rising fleck, for something good having just happened
var particles: Array = []
## Emitted since the last step, against MAX_EMITTED_PER_STEP.
var emitted_this_step := 0
## Where the next eviction writes once the field is full. Rotating over a list
## that is appended to in time order and compacted in place keeps it pointed at
## roughly the oldest mark, without the array shift that taking the literal
## oldest one required.
var _evict_at := 0


func _ready() -> void:
	# Under the survivors and enemies, over the floor: texture, not information.
	z_index = 1


func emit_dust(at: Vector2, color: Color, drift: Vector2 = Vector2.ZERO) -> void:
	if emitted_this_step >= MAX_EMITTED_PER_STEP:
		return
	_add({
		"kind": "dust", "position": at, "velocity": drift, "color": color,
		"age": 0.0, "life": 0.34, "size": randf_range(4.0, 7.5), "spin": 0.0,
	})


func emit_sparks(at: Vector2, color: Color, count: int = 4, speed: float = 190.0) -> void:
	# Clamped before the loop rather than inside _add, so a refused spark costs
	# one comparison instead of a Dictionary.
	count = mini(count, MAX_EMITTED_PER_STEP - emitted_this_step)
	for index in count:
		var direction := Vector2.from_angle(randf() * TAU)
		_add({
			"kind": "spark", "position": at, "velocity": direction * speed * randf_range(0.55, 1.4),
			"color": color, "age": 0.0, "life": randf_range(0.16, 0.3),
			"size": randf_range(5.0, 11.0), "spin": 0.0,
		})


func emit_ring(at: Vector2, color: Color, radius: float, life: float = 0.3) -> void:
	if emitted_this_step >= MAX_EMITTED_PER_STEP:
		return
	_add({
		"kind": "ring", "position": at, "velocity": Vector2.ZERO, "color": color,
		"age": 0.0, "life": life, "size": radius, "spin": 0.0,
	})


func emit_motes(at: Vector2, color: Color, count: int = 6) -> void:
	count = mini(count, MAX_EMITTED_PER_STEP - emitted_this_step)
	for index in count:
		_add({
			"kind": "mote", "position": at + Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 10.0)),
			"velocity": Vector2(randf_range(-22.0, 22.0), randf_range(-95.0, -55.0)),
			"color": color, "age": 0.0, "life": randf_range(0.45, 0.75),
			"size": randf_range(2.5, 4.5), "spin": randf() * TAU,
		})


func step(delta: float) -> void:
	emitted_this_step = 0
	if particles.is_empty():
		return
	var survivors: Array = []
	for particle in particles:
		particle["age"] = float(particle["age"]) + delta
		if float(particle["age"]) >= float(particle["life"]):
			continue
		var velocity := particle["velocity"] as Vector2
		particle["position"] = (particle["position"] as Vector2) + velocity * delta
		# Everything decelerates; a spark that kept its speed would read as a
		# projectile, which is the one thing a cosmetic mark must never do.
		particle["velocity"] = velocity * maxf(0.0, 1.0 - delta * 6.0)
		survivors.append(particle)
	particles = survivors
	_evict_at = 0
	queue_redraw()


func clear_all() -> void:
	if particles.is_empty():
		return
	particles.clear()
	_evict_at = 0
	queue_redraw()


func _add(particle: Dictionary) -> void:
	emitted_this_step += 1
	# The oldest mark is the one nobody is still looking at. Overwritten in place
	# rather than shifted out of the front: pop_front moves every entry after it,
	# so a full field made each new mark cost the length of the whole field.
	if particles.size() >= MAX_PARTICLES:
		if _evict_at >= particles.size():
			_evict_at = 0
		particles[_evict_at] = particle
		_evict_at += 1
	else:
		particles.append(particle)
	queue_redraw()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:particle_field", probe_started)


func _probed_draw() -> void:
	for particle in particles:
		var progress := clampf(float(particle["age"]) / float(particle["life"]), 0.0, 1.0)
		var fade := 1.0 - progress
		var color := Color(particle["color"] as Color, fade * 0.8)
		var origin := particle["position"] as Vector2
		var size := float(particle["size"])
		match String(particle["kind"]):
			"dust":
				draw_circle(origin, size * (0.6 + progress * 1.5), Color(color, fade * 0.35))
			"spark":
				var heading := (particle["velocity"] as Vector2).normalized()
				draw_line(origin, origin - heading * size * (0.4 + fade), color, 2.0 * fade + 0.6, true)
			"ring":
				draw_arc(origin, size * (0.35 + progress * 1.1), 0.0, TAU, 22, color, 3.5 * fade + 0.5, true)
			"mote":
				var sway := sin(float(particle["spin"]) + progress * 7.0) * 5.0
				draw_circle(origin + Vector2(sway, 0.0), size * fade + 0.7, color)
