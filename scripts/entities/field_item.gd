class_name FieldItem
extends Node2D

## A pickup that has to be walked over — unlike experience gems it is never
## magnetised, because deciding whether a drop is worth straining the chain to
## reach is the point of it existing.

var item_id := "heal"
var item_color := Color("80ed99")
var active := false
var lifetime := 0.0

## Drops linger long enough to be worth a detour but not forever, so the field
## does not slowly fill with ignored pickups over a long run.
const ITEM_LIFETIME := 22.0
const FADE_WARNING := 5.0 ## Blinks over the last stretch before it expires.


func activate(spawn_position: Vector2, id: String, color: Color) -> void:
	position = spawn_position
	item_id = id
	item_color = color
	lifetime = ITEM_LIFETIME
	active = true
	visible = true
	scale = Vector2.ONE
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false


## Returns true once the drop has timed out and should be recycled.
func step(delta: float) -> bool:
	if not active:
		return false
	var was_blinking := lifetime <= FADE_WARNING
	lifetime -= delta
	if lifetime <= 0.0:
		return true
	# Only redraw while the expiry blink is actually running; a drop sitting
	# with plenty of time left never changes appearance.
	if lifetime <= FADE_WARNING:
		queue_redraw()
	elif was_blinking:
		queue_redraw()
	return false


func _draw() -> void:
	var alpha := 1.0
	if lifetime <= FADE_WARNING:
		alpha = 0.45 + absf(sin(lifetime * 6.0)) * 0.55
	var body := Color(item_color, alpha)
	var ink := Color(0.03, 0.05, 0.1, alpha)
	if item_id == "chest":
		# A chunky cat-faced coffer breaks the circular pickup silhouette so it
		# stays recognisable inside a carpet of experience gems.
		draw_circle(Vector2.ZERO, 26.0, Color(item_color, 0.13 * alpha))
		draw_rect(Rect2(-17.0, -7.0, 34.0, 22.0), body, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-17.0, -7.0), Vector2(-12.0, -17.0), Vector2(-5.0, -10.0),
			Vector2(5.0, -10.0), Vector2(12.0, -17.0), Vector2(17.0, -7.0),
		]), body.lightened(0.12))
		draw_line(Vector2(-17.0, 0.0), Vector2(17.0, 0.0), ink, 2.5, true)
		draw_circle(Vector2(-6.0, -5.0), 2.0, ink)
		draw_circle(Vector2(6.0, -5.0), 2.0, ink)
		draw_line(Vector2(-3.0, 5.0), Vector2(3.0, 5.0), ink, 3.0, true)
		return
	draw_circle(Vector2.ZERO, 17.0, Color(item_color, 0.16 * alpha))
	draw_circle(Vector2.ZERO, 12.0, body)
	match item_id:
		"heal":
			draw_rect(Rect2(-6.0, -2.0, 12.0, 4.0), ink)
			draw_rect(Rect2(-2.0, -6.0, 4.0, 12.0), ink)
		"magnet":
			draw_arc(Vector2(0.0, 2.0), 6.0, PI, TAU, 14, ink, 3.0, true)
			draw_line(Vector2(-6.0, 2.0), Vector2(-6.0, 7.0), ink, 3.0, true)
			draw_line(Vector2(6.0, 2.0), Vector2(6.0, 7.0), ink, 3.0, true)
		"chain_ward":
			# Two chain links inside a closed ward, so it reads as protection
			# rather than as the repair kit it used to be.
			draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 20, ink, 2.0, true)
			draw_circle(Vector2(-3.5, 0.0), 3.6, ink, false, 2.0)
			draw_circle(Vector2(3.5, 0.0), 3.6, ink, false, 2.0)
		"guard":
			# A bell inside a shield: the thing that makes you untouchable.
			draw_arc(Vector2(0.0, -1.0), 8.5, PI, TAU, 16, ink, 2.2, true)
			draw_line(Vector2(-8.5, -1.0), Vector2(0.0, 8.0), ink, 2.2, true)
			draw_line(Vector2(8.5, -1.0), Vector2(0.0, 8.0), ink, 2.2, true)
			draw_circle(Vector2(0.0, -1.0), 2.6, ink)
		"frenzy":
			# A sprig of matatabi: three leaves off one stem.
			draw_line(Vector2(0.0, 8.0), Vector2(0.0, -4.0), ink, 2.4, true)
			for leaf in 3:
				var lean := (float(leaf) - 1.0) * 0.85
				draw_colored_polygon(PackedVector2Array([
					Vector2(0.0, -3.0 + absf(lean) * 3.0),
					Vector2.from_angle(-PI * 0.5 + lean) * 10.0,
					Vector2.from_angle(-PI * 0.5 + lean * 1.6) * 5.0,
				]), ink)
		"time_stop":
			# A pocket watch with its hands stopped.
			draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, ink, 2.2, true)
			draw_line(Vector2(0.0, -8.5), Vector2(0.0, -11.0), ink, 2.4, true)
			draw_line(Vector2.ZERO, Vector2(0.0, -5.5), ink, 2.0, true)
			draw_line(Vector2.ZERO, Vector2(4.2, 1.6), ink, 2.0, true)
		"purge":
			for index in 6:
				var angle := TAU * float(index) / 6.0
				draw_line(Vector2.from_angle(angle) * 3.0, Vector2.from_angle(angle) * 8.0, ink, 2.5, true)
