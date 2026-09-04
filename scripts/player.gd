class_name ChainPlayer
extends Node2D

signal damaged(player: ChainPlayer, amount: float)
signal downed_started(player: ChainPlayer)
signal revived_player(player: ChainPlayer)
signal dashed(player: ChainPlayer)

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

var player_index := 0
var move_speed := 230.0
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

## Personal attributes, applied across this player's whole weapon loadout
## rather than to a single weapon. Multipliers start neutral at 1.0; `amount`
## and `armor` are additive. These live on the player node alongside
## move_speed/max_health because that is already where per-survivor stats are
## kept, and hurt() needs armor without reaching back into main.gd.
var might := 1.0 ## damage multiplier
var area := 1.0 ## radius / range / arc / width multiplier
var projectile_speed := 1.0 ## projectile travel speed multiplier
var amount := 0 ## extra projectiles per volley
var haste := 1.0 ## cooldown multiplier, lower is faster
var armor := 0.0 ## flat damage subtracted from every hit
var recovery := 0.0 ## health per second regenerated while standing
var dash_timer := 0.0 ## remaining burst time
var dash_cooldown := 0.0
var dash_direction := Vector2.RIGHT


func setup(index: int, color: Color) -> void:
	player_index = index
	body_color = color
	queue_redraw()


func apply_character(character: Dictionary) -> void:
	character_name = String(character["name"])
	weapon_id = String(character["weapon_id"])
	body_color = Color(character["color"])
	max_health = float(character["health"])
	health = max_health
	move_speed = float(character["speed"])
	downed = false
	bleedout_remaining = 18.0
	revive_progress = 0.0
	might = 1.0
	area = 1.0
	projectile_speed = 1.0
	amount = 0
	haste = 1.0
	armor = 0.0
	recovery = 0.0
	dash_timer = 0.0
	dash_cooldown = 0.0
	queue_redraw()


func step_movement(delta: float) -> void:
	var was_invulnerable := invulnerability > 0.0
	invulnerability = maxf(0.0, invulnerability - delta)
	var was_dashing := dash_timer > 0.0
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	if was_invulnerable or was_dashing or dash_cooldown > 0.0:
		queue_redraw()
	var prefix := "p1_" if player_index == 1 else "p2_"
	var input_vector := Input.get_vector(
		prefix + "left", prefix + "right", prefix + "up", prefix + "down"
	)
	if input_vector.length_squared() > 0.01:
		last_input = input_vector.normalized()
	if Input.is_action_just_pressed(prefix + "dash"):
		try_dash()

	if dash_timer > 0.0:
		dash_timer = maxf(0.0, dash_timer - delta)
		# The chain resolves by who is straining outward, so a dashing survivor
		# has to read as pushing that way or the leash would settle the wrong
		# player back.
		current_input = dash_direction
		position += dash_direction * move_speed * DASH_SPEED_MULTIPLIER * delta
		return

	current_input = input_vector
	var speed_multiplier := 0.28 if downed else 1.0
	position += input_vector * move_speed * speed_multiplier * delta


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
func hurt(amount: float) -> bool:
	if invulnerability > 0.0 or downed:
		return false
	health = maxf(0.0, health - maxf(1.0, amount - armor))
	invulnerability = 0.55
	damaged.emit(self, amount)
	if health <= 0.0:
		downed = true
		bleedout_remaining = 18.0
		revive_progress = 0.0
		downed_started.emit(self)
	queue_redraw()
	return true


func heal(amount: float) -> void:
	if downed:
		return
	health = minf(max_health, health + amount)
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
	bleedout_remaining = 18.0
	revive_progress = 0.0
	invulnerability = 1.5
	revived_player.emit(self)
	queue_redraw()


func _draw() -> void:
	var flash := invulnerability > 0.0 and int(invulnerability * 18.0) % 2 == 0
	var color := Color.WHITE if flash else body_color
	draw_circle(Vector2.ZERO, radius + 7.0, Color(color, 0.13))
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius - 6.0, color.darkened(0.3))
	var badge_color := Color("43d9ff") if player_index == 1 else Color("b892ff")
	draw_circle(Vector2(0.0, radius + 13.0), 10.0, Color("07111f"))
	draw_string(ThemeDB.fallback_font, Vector2(-7.0, radius + 19.0), str(player_index), HORIZONTAL_ALIGNMENT_CENTER, 14.0, 15, badge_color)
	if downed:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color("ff5d8f"), 5.0, true)
		draw_line(Vector2(10, -10), Vector2(-10, 10), Color("ff5d8f"), 5.0, true)
		draw_arc(Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(revive_progress / 2.6, 0.0, 1.0), 28, Color("80ed99"), 4.0, true)
		var down_text := "구조 중 %.0f%%" % (revive_progress / 2.6 * 100.0) if revive_progress > 0.0 else "가까이 와서 구조 · %.0f초" % bleedout_remaining
		draw_string(ThemeDB.fallback_font, Vector2(-92.0, -43.0), down_text, HORIZONTAL_ALIGNMENT_CENTER, 184.0, 16, Color("ffcfdf"))
		return
	draw_line(Vector2.ZERO, last_input * 17.0, Color.WHITE, 5.0, true)
	draw_circle(last_input * 17.0, 4.0, Color.WHITE)
	_draw_dash_state()
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


func _draw_weapon_mark() -> void:
	var ink := Color("07111f")
	match weapon_id:
		"homing":
			draw_line(Vector2(-8, 7), Vector2(8, -7), ink, 3.0, true)
			draw_line(Vector2(2, -8), Vector2(9, -7), ink, 3.0, true)
		"lightning":
			var points := PackedVector2Array([Vector2(-4, -11), Vector2(4, -3), Vector2(-2, 1), Vector2(6, 10)])
			draw_polyline(points, ink, 3.0, true)
		"flame":
			draw_circle(Vector2(0, 2), 7.0, ink)
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 1), Vector2(0, -12), Vector2(6, 1)]), ink)
		"frost":
			for angle in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
				draw_line(Vector2.from_angle(angle) * -10.0, Vector2.from_angle(angle) * 10.0, ink, 2.5, true)
		"scythe":
			draw_arc(Vector2.ZERO, 10.0, -1.7, 1.2, 16, ink, 3.0, true)
		"chain":
			draw_circle(Vector2(-6, 0), 5.0, ink, false, 2.5)
			draw_circle(Vector2(6, 0), 5.0, ink, false, 2.5)
