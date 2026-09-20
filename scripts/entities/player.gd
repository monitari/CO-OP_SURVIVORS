class_name ChainPlayer
extends Node2D

## The game's one typeface, for the badge and the downed prompt drawn straight
## onto the world. These used to take ThemeDB's built-in fallback, which put a
## second typeface on screen next to every HUD label.
## The badge over a survivor and the downed prompt are read at a glance during
## a fight, so they take the readout face rather than the menus' handwriting.
const UIFont := preload("res://scripts/ui/cat_theme.gd").READOUT

const Icons := preload("res://scripts/ui/icon_catalog.gd")
var portrait: Texture2D

signal damaged(player: ChainPlayer, amount: float)
signal downed_started(player: ChainPlayer)
signal revived_player(player: ChainPlayer)
signal dashed(player: ChainPlayer)
signal second_chance_used(player: ChainPlayer)
signal dodged(player: ChainPlayer)

## A short burst along the last movement direction with brief invulnerability.
## Until now the only way to avoid a telegraphed attack was to walk out of
## it, which the pressure measurement showed is not enough. The chain is
## what bounds the dash: burst distance is well under the leash length, so
## dashing away from a partner runs into the constraint and repositions the
## pair rather than letting one survivor break off alone.
const DASH_DURATION := 0.18
const DASH_SPEED_MULTIPLIER := 3.2
const DASH_COOLDOWN := 1.4
const DASH_INVULNERABILITY := 0.26
## A critical hit is worth taking a treasure slot for, so it is a doubling
## rather than a nudge.
const CRIT_MULTIPLIER := 2.0
const BLEEDOUT_BASE := 18.0
## Thorns answer the one damage source the pair cannot shoot back at: an
## enemy that has already reached them.
signal reflected(attacker_position: Vector2, amount: float)
## Raised on a cadence while this survivor is actually moving, so the scene can
## leave dust behind without the player node knowing what a ParticleField is.
signal footfall(at: Vector2, color: Color)

## How fast the drawn heading catches up to the pressed direction. The input
## itself is still instant — movement must never feel filtered — but everything
## that shows which way the cat is facing (tail, lean, aim mark) turns over a
## few frames instead of snapping, which is the difference between a cat turning
## around and a sprite being replaced with a mirrored copy.
const TURN_SPEED := 13.0
const LEAN_MAX := 0.34 ## radians of body tilt at a full-speed turn
const FOOTFALL_INTERVAL := 0.11

enum InputSource { LOCAL, AI, REMOTE }
var input_source := InputSource.LOCAL
var commanded_movement := Vector2.ZERO
var commanded_dash := false


func set_command(movement: Vector2, dash := false) -> void:
	commanded_movement = movement.limit_length(1.0)
	commanded_dash = dash


var player_index := 0
var display_index := 0
var display_name := ""
var move_speed := 230.0
## Temporary world-effect multiplier. Kept separate from move_speed so a timed
## pickup can end without undoing permanent speed upgrades earned meanwhile.
var field_move_multiplier := 1.0
var radius := 24.0
var body_color := Color.WHITE
var health := 100.0
var max_health := 100.0
var invulnerability := 0.0
var last_input := Vector2.RIGHT
var character_name := ""
var weapon_id := ""
var downed := false
var bleedout_remaining := 18.0
var revive_progress := 0.0
var current_input := Vector2.ZERO
## Contact-only pack pressure; shields and dash immunity still use hurt().
var contact_pressure := 1.0

## Personal attributes, applied across this player's whole weapon loadout
## rather than to a single weapon. Multipliers start neutral at 1.0; `amount`
## and `armor` are additive. These live on the player node alongside
## move_speed/max_health because that is already where per-survivor stats are
## kept, and hurt() needs armor without reaching back into main.gd.
var might := 1.0 ## damage multiplier
var area := 1.0 ## radius / range / arc / width multiplier
var projectile_speed := 1.0 ## projectile travel speed multiplier
var duration := 1.0 ## lifetime multiplier for projectiles and persistent weapon fields
## Extra projectiles per volley. A float that accumulates in fractions and is
## floored where it is read, because 분열의 화살통 used to hand out a whole extra
## projectile on every one of its ten tiers: +10 shots on every count weapon in
## the game, which on a weapon that fires one is eleven times the volley. The
## ladder is fractional now, so the treasure is worth taking without being the
## single largest source of things on screen.
var amount := 0.0
var haste := 1.0 ## cooldown multiplier, lower is faster
var armor := 0.0 ## flat damage subtracted from every hit
var recovery := 0.0 ## health per second regenerated while standing
var crit_chance := 0.0 ## chance a hit deals CRIT_MULTIPLIER damage
var pierce := 0 ## extra enemies a projectile passes through
var thorns := 0.0 ## fraction of contact damage returned to the attacker
var resolve := 0.0 ## extra bleedout seconds, and faster rescues
var dodge_chance := 0.0 ## chance to ignore a hit entirely
var second_chances := 0 ## fatal hits converted into a short recovery window
var dash_timer := 0.0 ## remaining burst time
var dash_cooldown := 0.0
var dash_direction := Vector2.RIGHT
var tail_phase := 0.0 ## Drives the tail sway; advanced by step_movement.
var facing := Vector2.RIGHT ## Smoothed heading; drawing reads this, movement does not.
var lean := 0.0 ## Signed turn rate, smoothed. Drives the body tilt.
var footfall_timer := 0.0
## How far off the roof this cat's body is drawn, with the contact shadow left
## behind on the floor. Zero everywhere the roof is flat, which is every screen
## the run currently has — the survivor then draws exactly as it always did, at
## its own position, with the same shadow Moonlight puts under every actor.
##
## Above zero it separates two things that used to be the same point: where the
## cat *is*, which nothing about this changes, and where the cat is *drawn*,
## which moves up the screen. That is the whole of standing on a floor rather
## than lying on it, and the price of it is that the shadow underneath becomes
## the only statement of where the cat actually stands — so the shadow is never
## optional once this is set. See RooftopSpace.
var stand_height := 0.0


func setup(index: int, color: Color) -> void:
	z_index = 6
	player_index = index
	body_color = color
	queue_redraw()


func apply_character(character: Dictionary) -> void:
	portrait = Icons.survivor(String(character["id"]))
	character_name = String(character["name"])
	weapon_id = String(character["weapon_id"])
	body_color = Color(character["color"])
	max_health = float(character["health"])
	health = max_health
	move_speed = float(character["speed"])
	field_move_multiplier = 1.0
	downed = false
	revive_progress = 0.0
	might = float(character.get("might", 1.0))
	area = float(character.get("area", 1.0))
	projectile_speed = float(character.get("projectile_speed", 1.0))
	duration = float(character.get("duration", 1.0))
	amount = float(character.get("amount", 0))
	haste = float(character.get("haste", 1.0))
	armor = float(character.get("armor", 0.0))
	recovery = float(character.get("recovery", 0.0))
	crit_chance = float(character.get("crit", 0.0))
	pierce = int(character.get("pierce", 0))
	thorns = float(character.get("thorns", 0.0))
	resolve = float(character.get("resolve", 0.0))
	dodge_chance = float(character.get("dodge", 0.0))
	second_chances = int(character.get("second_chances", 0))
	bleedout_remaining = BLEEDOUT_BASE + resolve
	dash_timer = 0.0
	dash_cooldown = 0.0
	facing = Vector2.RIGHT
	lean = 0.0
	footfall_timer = 0.0
	queue_redraw()


func step_movement(delta: float) -> void:
	var was_invulnerable := invulnerability > 0.0
	invulnerability = maxf(0.0, invulnerability - delta)
	var was_dashing := dash_timer > 0.0
	# A moving cat's tail swings faster than a sitting one's.
	var previous_phase := tail_phase
	tail_phase += delta * (2.2 + current_input.length() * 4.5)
	if absf(sin(tail_phase) - sin(previous_phase)) > 0.03:
		queue_redraw()
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	if was_invulnerable or was_dashing or dash_cooldown > 0.0:
		queue_redraw()
	var prefix := "p1_" if player_index == 1 else "p2_"
	var input_vector := commanded_movement
	var dash_requested := commanded_dash
	commanded_dash = false
	if input_source == InputSource.LOCAL:
		input_vector = Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
		dash_requested = Input.is_action_just_pressed(prefix + "dash")
	if input_vector.length_squared() > 0.01:
		last_input = input_vector.normalized()
	if dash_requested:
		try_dash()
	_step_facing(delta, input_vector)

	if dash_timer > 0.0:
		dash_timer = maxf(0.0, dash_timer - delta)
		# The chain resolves by who is straining outward, so a dashing survivor
		# has to read as pushing that way or the leash would settle the wrong
		# player back.
		current_input = dash_direction
		position += dash_direction * move_speed * field_move_multiplier * DASH_SPEED_MULTIPLIER * delta
		return

	current_input = input_vector
	var speed_multiplier := 0.28 if downed else 1.0
	position += input_vector * move_speed * field_move_multiplier * speed_multiplier * delta
	if not downed and input_vector.length_squared() > 0.04:
		footfall_timer -= delta
		if footfall_timer <= 0.0:
			footfall_timer = FOOTFALL_INTERVAL
			footfall.emit(global_position + Vector2(0.0, radius * 0.6), body_color)
	else:
		footfall_timer = 0.0


## Turns the drawn heading toward wherever the survivor is going and records how
## hard that turn was, which is what the body tilt reads. The dash overrides the
## target because a dash is a committed direction — the cat should already be
## pointing that way when it launches, not catching up through the burst.
func _step_facing(delta: float, input_vector: Vector2) -> void:
	var target := dash_direction if dash_timer > 0.0 else (
		input_vector.normalized() if input_vector.length_squared() > 0.01 else facing
	)
	var previous := facing
	var weight := minf(1.0, delta * (TURN_SPEED * (2.4 if dash_timer > 0.0 else 1.0)))
	facing = previous.slerp(target, weight)
	if facing.length_squared() < 0.001:
		facing = target
	facing = facing.normalized()
	var turned := previous.angle_to(facing)
	# Smoothed rather than taken raw, so the lean settles out of a turn instead
	# of snapping upright the frame the stick centres.
	lean = lerpf(lean, clampf(turned / maxf(0.0001, delta) / 12.0, -1.0, 1.0), minf(1.0, delta * 9.0))
	if absf(turned) > 0.006 or absf(lean) > 0.01:
		queue_redraw()


## Starts a dash if one is available. Returns whether it actually began, so
## callers can spend a cue on it only when something happened.
func try_dash() -> bool:
	if downed or dash_timer > 0.0 or dash_cooldown > 0.0:
		return false
	dash_timer = DASH_DURATION
	dash_cooldown = DASH_COOLDOWN
	dash_direction = last_input.normalized()
	invulnerability = maxf(invulnerability, DASH_INVULNERABILITY)
	dashed.emit(self)
	queue_redraw()
	return true


func dash_ready() -> bool:
	return not downed and dash_timer <= 0.0 and dash_cooldown <= 0.0


## Armor subtracts flat damage but can never fully negate a hit — a chip
## minimum keeps stacked armor from making a survivor untouchable.
## `source_position` lets a contact hit be reflected back at whatever landed
## it. Attacks with no attacker on the field (the chain overload, a boss slam)
## simply leave it empty and reflect nothing.
func hurt(incoming_damage: float, source_position := Vector2.INF, can_dodge := true) -> bool:
	if invulnerability > 0.0 or downed:
		return false
	if can_dodge and dodge_chance > 0.0 and randf() < dodge_chance:
		invulnerability = 0.28
		dodged.emit(self)
		queue_redraw()
		return false
	if thorns > 0.0 and source_position != Vector2.INF:
		reflected.emit(source_position, incoming_damage * thorns)
	health = maxf(0.0, health - maxf(1.0, incoming_damage - armor))
	invulnerability = 0.55
	damaged.emit(self, incoming_damage)
	if health <= 0.0 and second_chances > 0:
		second_chances -= 1
		health = max_health * 0.28
		invulnerability = 1.25
		second_chance_used.emit(self)
	elif health <= 0.0:
		downed = true
		bleedout_remaining = BLEEDOUT_BASE + resolve
		revive_progress = 0.0
		downed_started.emit(self)
	queue_redraw()
	return true


func heal(healing: float) -> void:
	if downed:
		return
	health = minf(max_health, health + healing)
	queue_redraw()


## Regenerates health from the recovery attribute. Downed survivors are
## excluded — they are on the bleedout clock and only a revive brings them back.
func step_recovery(delta: float) -> void:
	if downed or recovery <= 0.0 or health >= max_health:
		return
	heal(recovery * delta)


func step_bleedout(delta: float) -> void:
	if not downed:
		return
	bleedout_remaining = maxf(0.0, bleedout_remaining - delta)
	queue_redraw()


func revive() -> void:
	downed = false
	health = max_health * 0.4
	bleedout_remaining = BLEEDOUT_BASE + resolve
	revive_progress = 0.0
	invulnerability = 1.5
	revived_player.emit(self)
	queue_redraw()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:player", probe_started)


func _probed_draw() -> void:
	var flash := invulnerability > 0.0 and int(invulnerability * 18.0) % 2 == 0
	var color := Color.WHITE if flash else body_color
	# Drawn before anything else, so the cat stands on the roof rather than
	# floating over it. Same rule the enemies and the props use.
	var lift := RooftopSpace.lift(stand_height)
	var lunge := Vector2.ZERO
	if stand_height > 0.0:
		# A dash throws the body forward and drags the shadow out behind it.
		# Both come off the same clock, so the cat gathers back over its own
		# feet as the burst ends rather than snapping upright.
		var burst := dash_timer / DASH_DURATION if dash_timer > 0.0 else 0.0
		var along := dash_direction if dash_timer > 0.0 else facing
		lunge = along * radius * 0.26 * burst
		RooftopSpace.footing(self, Vector2.ZERO, radius, stand_height, 1.0, burst * 0.7, along)
	else:
		Moonlight.ground_shadow(self, Vector2.ZERO, radius, 1.0)
	draw_set_transform_matrix(RooftopSpace.upright_basis(self, lift))
	draw_circle(Vector2.ZERO, radius + 7.0, Color(color, 0.13))
	_draw_tail(color)
	# The body tilts into a turn and stretches slightly along the direction of
	# travel. Both are small on purpose: the read has to be "that cat is turning",
	# not "that sprite is wobbling".
	var tilt := lean * LEAN_MAX
	# A running bob rather than a constant squash: tail_phase already speeds up
	# with movement, so reusing it keeps the body and the tail on one rhythm.
	var bob := sin(tail_phase * 2.0) * 0.05 * minf(1.0, current_input.length())
	draw_set_transform_matrix(RooftopSpace.upright_basis(self, lift + lunge) * Transform2D(tilt, Vector2.ZERO).scaled_local(Vector2(1.0 + bob, 1.0 - bob)))
	if portrait == null:
		draw_circle(Vector2.ZERO, radius, color)
		_draw_ears(color)
	# The identity colour used to survive only as a 6px ring: the inner disc
	# was darkened hard and a near-black weapon glyph covered the rest, so a
	# character read as a dark disc rather than as "the orange one". The disc
	# now keeps most of its colour and the glyph picks an ink that contrasts
	# with it.
	if portrait != null:
		draw_texture_rect(portrait, Rect2(-34, -37, 68, 68), false, Color(1.8, 1.8, 1.8) if flash else Color.WHITE)
	else:
		draw_circle(Vector2.ZERO, radius - 6.0, color.darkened(0.12))
	draw_set_transform_matrix(RooftopSpace.upright_basis(self, lift))
	var shown_index := display_index if display_index > 0 else player_index
	var badge_color := Color("43d9ff") if shown_index == 1 else Color("ff9f43")
	# The name rides above the head once the cat is standing off the roof. Below
	# is where it has always gone and where it can stay on a flat floor, but on a
	# floor with height that is exactly where the contact shadow lands — and the
	# shadow is the only thing saying where the cat is, so the label moves.
	var badge_y := -radius - 22.0 if stand_height > 0.0 else radius + 13.0
	draw_circle(Vector2(0.0, badge_y), 10.0, Color("07111f"))
	draw_string(UIFont, Vector2(-22.0, badge_y + 6.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 44.0, 13, badge_color)
	if downed:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color("ff5d8f"), 5.0, true)
		draw_line(Vector2(10, -10), Vector2(-10, 10), Color("ff5d8f"), 5.0, true)
		draw_arc(Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(revive_progress / 2.6, 0.0, 1.0), 28, Color("80ed99"), 4.0, true)
		var down_text := "구조 중 %.0f%%" % (revive_progress / 2.6 * 100.0) if revive_progress > 0.0 else "가까이 와서 구조    %.0f초" % bleedout_remaining
		draw_string(UIFont, Vector2(-92.0, -43.0), down_text, HORIZONTAL_ALIGNMENT_CENTER, 184.0, 16, Color("ffcfdf"))
		return
	draw_circle(facing * (radius + 5.0), 2.5, Color.WHITE)
	_draw_dash_state()
	if portrait == null:
		_draw_weapon_mark()


## The dash readout lives on the character rather than in the HUD: the play
## screen was deliberately stripped of text, and a cooldown is only useful where
## the player is already looking.
func _draw_dash_state() -> void:
	if dash_timer > 0.0:
		var trail := -dash_direction * (radius + 26.0)
		draw_line(Vector2.ZERO, trail, Color(Color.WHITE, 0.5), 8.0, true)
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 30, Color(Color.WHITE, 0.65), 3.0, true)
		return
	if dash_cooldown > 0.0:
		var filled := 1.0 - dash_cooldown / DASH_COOLDOWN
		draw_arc(Vector2.ZERO, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * filled, 24, Color(body_color, 0.55), 2.5, true)
		return
	draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 28, Color(Color.WHITE, 0.35), 2.0, true)
	if health < max_health:
		draw_rect(Rect2(-25.0, -36.0, 50.0, 5.0), Color("351d3c"))
		draw_rect(Rect2(-25.0, -36.0, 50.0 * health / max_health, 5.0), Color("80ed99"))


## The survivors are cats. Ears and a tail are drawn from the body rather than
## from a sprite so they inherit the character colour and the invulnerability
## flash for free, and so they read at the 24px the play field actually uses.
func _draw_ears(color: Color) -> void:
	var inner := color.darkened(0.35)
	for side: float in [-1.0, 1.0]:
		var base_x := side * radius * 0.62
		var outer := Vector2(base_x + side * radius * 0.34, -radius * 0.62)
		var tip := Vector2(base_x + side * radius * 0.18, -radius * 1.42)
		var inward := Vector2(base_x - side * radius * 0.24, -radius * 0.78)
		draw_colored_polygon(PackedVector2Array([outer, tip, inward]), color)
		draw_colored_polygon(PackedVector2Array([
			outer.lerp(inward, 0.32), tip.lerp(inward, 0.28), inward.lerp(outer, 0.28)
		]), inner)


## The tail sweeps opposite the way the cat is facing, so a survivor reads as
## turning even though the body is a circle.
func _draw_tail(color: Color) -> void:
	var heading := facing if facing.length_squared() > 0.001 else Vector2.RIGHT
	var back := -heading.normalized()
	# The tail trails the turn: it sways on its own clock and is bent further by
	# however hard the cat is currently turning, so a hard corner whips it.
	var sway := sin(tail_phase) * 0.55 + lean * 0.9
	var points := PackedVector2Array()
	for step in 6:
		var along := float(step) / 5.0
		var bend := back.rotated(sway * along * along)
		points.append(back * radius * 0.7 + bend * radius * (0.55 + along * 1.35))
	draw_polyline(points, color, 5.0, true)
	draw_circle(points[points.size() - 1], 4.0, color.lightened(0.25))


func _draw_weapon_mark() -> void:
	# get_luminance() works in linear space, where this palette lands between
	# roughly 0.24 and 0.70 — an sRGB-shaped threshold put white ink on bright
	# orange and turned Ignis into a dark disc.
	var ink := Color("07111f") if body_color.get_luminance() > 0.30 else Color("f2f9ff")
	match weapon_id:
		"homing":
			draw_line(Vector2(-8, 7), Vector2(8, -7), ink, 3.0, true)
			draw_line(Vector2(2, -8), Vector2(9, -7), ink, 3.0, true)
		"lightning":
			var points := PackedVector2Array([Vector2(-4, -11), Vector2(4, -3), Vector2(-2, 1), Vector2(6, 10)])
			draw_polyline(points, ink, 3.0, true)
		"flame":
			# Smaller than it was: filled at the old size the flame covered most
			# of the disc and swallowed the character's colour.
			draw_circle(Vector2(0, 3), 5.0, ink)
			draw_colored_polygon(PackedVector2Array([Vector2(-4, 2), Vector2(0, -9), Vector2(4, 2)]), ink)
		"frost":
			for angle in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
				draw_line(Vector2.from_angle(angle) * -10.0, Vector2.from_angle(angle) * 10.0, ink, 2.5, true)
		"scythe":
			draw_arc(Vector2.ZERO, 10.0, -1.7, 1.2, 16, ink, 3.0, true)
		"chain":
			draw_circle(Vector2(-6, 0), 5.0, ink, false, 2.5)
			draw_circle(Vector2(6, 0), 5.0, ink, false, 2.5)
