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
## A second, smaller allowance for marks that belong to an *event* rather than to
## the texture of a busy fight: a cast leaving a cat, a heavy blow landing, a
## mine going off. Without it a late tick's hundreds of chip-damage sparks spent
## the whole frame's allowance before the one explosion that mattered asked, and
## the moment the player caused drew nothing. Events still share MAX_PARTICLES,
## so the drawn total stays bounded.
const MAX_EVENTS_PER_STEP := 16
## Flares are the brightest mark here, so they are the most tightly held: a
## screen full of four-point stars is a screen with no hit that stands out.
const MAX_FLARES_PER_STEP := 5
## Debris is thrown up off the roof and falls back onto it. Pixels per second
## squared of lift lost, in the same upright units the rooftop uses for height.
const CHIP_GRAVITY := 900.0

## Kinds, and what each one is for:
##   dust   a soft puff left under a moving survivor, so running reads as running
##   spark  a thrown shard, so a hit reads as a hit and not as a number changing
##   ring   an expanding outline, for a dash afterimage or a pickup pop
##   mote   a slow rising fleck, for something good having just happened
##   flare  a four-point star that opens and closes, for a blow that lands hard
##   chip   a fleck of debris thrown up off the roof that falls and settles,
##          so a kill scatters the body onto the floor instead of vanishing
##   streak a line drawn inward toward a point, for a pull or an implosion
var particles: Array = []
## Emitted since the last step, against MAX_EMITTED_PER_STEP.
var emitted_this_step := 0
var events_this_step := 0
var flares_this_step := 0
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


## A hard blow: a four-point star that snaps open and closes again. `size` is
## the length of one point.
func emit_flare(at: Vector2, color: Color, size := 24.0, life := 0.2) -> void:
	if flares_this_step >= MAX_FLARES_PER_STEP or events_this_step >= MAX_EVENTS_PER_STEP:
		return
	flares_this_step += 1
	_add_event({
		"kind": "flare", "position": at, "velocity": Vector2.ZERO, "color": color,
		"age": 0.0, "life": life, "size": size, "spin": randf_range(-0.3, 0.3),
	})


## Sparks for an event rather than for texture: drawn from the event allowance,
## so a cast or an explosion still throws them on a tick already full of hits.
func emit_burst(at: Vector2, color: Color, count := 6, speed := 240.0) -> void:
	count = mini(count, MAX_EVENTS_PER_STEP - events_this_step)
	for index in count:
		var direction := Vector2.from_angle(TAU * (float(index) + randf() * 0.6) / float(maxi(1, count)))
		_add_event({
			"kind": "spark", "position": at, "velocity": direction * speed * randf_range(0.7, 1.25),
			"color": color, "age": 0.0, "life": randf_range(0.2, 0.34),
			"size": randf_range(7.0, 13.0), "spin": 0.0,
		})


## An expanding outline on the event allowance, for a cast leaving a cat.
func emit_pulse(at: Vector2, color: Color, radius: float, life := 0.22) -> void:
	if events_this_step >= MAX_EVENTS_PER_STEP:
		return
	_add_event({
		"kind": "ring", "position": at, "velocity": Vector2.ZERO, "color": color,
		"age": 0.0, "life": life, "size": radius, "spin": 0.0,
	})


## Debris thrown up off the roof. Texture, so it rides the ordinary allowance and
## is the first thing dropped under load.
func emit_chips(at: Vector2, color: Color, count := 4, speed := 150.0) -> void:
	count = mini(count, MAX_EMITTED_PER_STEP - emitted_this_step)
	for index in count:
		var direction := Vector2.from_angle(randf() * TAU)
		_add({
			"kind": "chip", "position": at, "velocity": direction * speed * randf_range(0.4, 1.0),
			"color": color, "age": 0.0, "life": randf_range(0.9, 1.1),
			"size": randf_range(4.5, 7.0), "spin": randf() * TAU,
			"height": 6.0, "lift": randf_range(150.0, 240.0),
		})


## Lines drawn in from a circle toward its centre: a pull, an implosion.
func emit_implode(centre: Vector2, radius: float, color: Color, count := 10) -> void:
	count = mini(count, MAX_EVENTS_PER_STEP - events_this_step)
	for index in count:
		var direction := Vector2.from_angle(TAU * float(index) / float(maxi(1, count)) + randf() * 0.3)
		_add_event({
			"kind": "streak", "position": centre + direction * radius, "velocity": -direction * radius * 5.2,
			"color": color, "age": 0.0, "life": 0.26, "size": 16.0, "spin": 0.0,
		})


func step(delta: float) -> void:
	emitted_this_step = 0
	events_this_step = 0
	flares_this_step = 0
	if particles.is_empty():
		return
	var survivors: Array = []
	for particle in particles:
		particle["age"] = float(particle["age"]) + delta
		if float(particle["age"]) >= float(particle["life"]):
			continue
		var velocity := particle["velocity"] as Vector2
		particle["position"] = (particle["position"] as Vector2) + velocity * delta
		if particle.has("lift"):
			# Debris: up, over, down, one small bounce, then it lies on the roof.
			var lift := float(particle["lift"]) - CHIP_GRAVITY * delta
			var height := float(particle["height"]) + lift * delta
			if height <= 0.0:
				height = 0.0
				lift = -lift * 0.28 if lift < -140.0 else 0.0
				velocity *= 0.45
			particle["height"] = height
			particle["lift"] = lift
			particle["spin"] = float(particle["spin"]) + delta * (9.0 if height > 0.0 else 0.0)
			particle["velocity"] = velocity * maxf(0.0, 1.0 - delta * 1.6)
		else:
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


func _add_event(particle: Dictionary) -> void:
	events_this_step += 1
	_store(particle)


func _add(particle: Dictionary) -> void:
	emitted_this_step += 1
	_store(particle)


func _store(particle: Dictionary) -> void:
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
			"flare":
				# Opens fast and closes slower: the eye catches the snap.
				var open := minf(1.0, progress * 5.0) * (1.0 - progress * progress)
				var reach := size * (0.4 + open)
				var hot := Color(color.lightened(0.5), minf(1.0, open * 1.4))
				for arm in 4:
					var direction := Vector2.from_angle(float(particle["spin"]) + TAU * float(arm) / 4.0)
					var side := direction.orthogonal() * size * 0.12 * open
					draw_colored_polygon(PackedVector2Array([origin + side, origin + direction * reach, origin - side]), hot)
				draw_circle(origin, size * 0.22 * open + 1.0, Color(1.0, 1.0, 1.0, open))
			"chip":
				var height := float(particle["height"])
				var lying := 1.0 - smoothstep(0.7, 1.0, progress)
				if height > 0.5:
					draw_circle(origin + Vector2(0.0, 2.0), size * 0.7, Color(Moonlight.SHADOW_INK, 0.25 * lying))
				var lifted := origin - Vector2(0.0, height * RooftopSpace.TILT)
				var turn := Vector2.from_angle(float(particle["spin"])) * size
				var chip_color := Color(particle["color"] as Color, lying)
				draw_colored_polygon(PackedVector2Array([lifted + turn, lifted + turn.orthogonal() * 0.6,
					lifted - turn, lifted - turn.orthogonal() * 0.6]), chip_color)
			"streak":
				var heading := (particle["velocity"] as Vector2).normalized()
				draw_line(origin, origin - heading * size * (0.5 + fade), Color(color, fade), 2.4 * fade + 0.8, true)
