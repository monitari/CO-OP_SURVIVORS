extends Control

## 공명, as slots rather than as a fraction.
##
## Resonance sits below the compact shared panel as two circular sockets. A
## filled socket is active and a pulsing gold socket is a core waiting to be
## spent, so this shared power no longer competes with the two horizontal chain
## meters for room inside the paper panel.

const ACTIVE := Color("c77dff")
const EMPTY := Color("3d5578")
const HELD := Color("fff275")

var slots := 2
var active := 0
var held_cores := 0
var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func report(active_count: int, slot_count: int, cores: int) -> void:
	active = active_count
	slots = maxi(1, slot_count)
	held_cores = cores
	queue_redraw()


func _process(delta: float) -> void:
	# Only an unspent core animates. A settled readout that keeps moving is a
	# thing the eye returns to for no reason.
	if not visible or held_cores <= 0:
		return
	pulse = fposmod(pulse + delta * 2.6, TAU)
	queue_redraw()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:resonance_pips", probe_started)


func _probed_draw() -> void:
	var radius := minf(14.0, size.y * 0.42)
	for index in slots:
		var x := radius + 2.0 if slots == 1 else lerpf(radius + 2.0, size.x - radius - 2.0,
			float(index) / float(slots - 1))
		var centre := Vector2(x, size.y * 0.5)
		var filled := index < active
		var awaiting := not filled and index < active + held_cores
		var tint := ACTIVE if filled else EMPTY
		if awaiting:
			tint = EMPTY.lerp(HELD, 0.45 + 0.35 * sin(pulse))
		draw_circle(centre, radius, Color("101a2dcc"))
		draw_arc(centre, radius, 0.0, TAU, 40, tint, 3.0, true)
		if filled:
			draw_circle(centre, radius - 5.0, Color(ACTIVE, 0.8))
			draw_circle(centre - Vector2(3.5, 4.0), 2.5, Color(ACTIVE.lightened(0.65), 0.9))
		elif awaiting:
			draw_circle(centre, radius - 6.0, Color(tint, 0.45))
