extends Control

## 공명, as slots rather than as a fraction.
##
## The shared HUD strip carries three readings and two of them were meters — how
## far apart the pair is, how much chain integrity is left — while the third was
## the bare string "공명 1/3" parked beside them. So the one reading that is a
## *count of things the pair owns* was the one you had to read rather than see,
## and it sat in a row that had taught the eye to expect bars.
##
## It is drawn as its slots now: one cell per resonance slot, filled for each
## active resonance, with a held 공명핵 shown as a cell that is waiting to be
## spent. That last state is the point — a core the pair has not used is a
## decision they owe themselves, and it belongs next to the count rather than
## only in a notice that scrolled away.

const CELL_GAP := 5.0
const CELL_HEIGHT := 6.0
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
	var cell_width := (size.x - CELL_GAP * float(slots - 1)) / float(slots)
	for index in slots:
		var cell := Rect2(float(index) * (cell_width + CELL_GAP), size.y - CELL_HEIGHT,
			cell_width, CELL_HEIGHT)
		var filled := index < active
		var awaiting := not filled and index < active + held_cores
		var tint := ACTIVE if filled else EMPTY
		if awaiting:
			tint = EMPTY.lerp(HELD, 0.45 + 0.35 * sin(pulse))
		draw_rect(cell, tint, true)
		# An empty slot still gets a lid, so the column reads as a meter at 0/2
		# rather than as two smudges the eye skips over.
		draw_rect(Rect2(cell.position, Vector2(cell.size.x, 1.0)), Color(tint.lightened(0.5), 0.8), true)
		if filled:
			draw_rect(Rect2(cell.position, Vector2(cell.size.x, 2.0)), ACTIVE.lightened(0.4), true)
