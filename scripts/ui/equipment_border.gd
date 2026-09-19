extends Control

## A carried item's socket edge, which is also its cooldown readout.
##
## The ring used to be a square path traced two pixels in from the socket's
## corners while the socket under it was a rounded box with its own outline, so
## every socket showed two borders that disagreed at all four corners, and the
## level number sat on top of the art. The ring now *is* the socket's border: it
## follows the same rounded rectangle, a dim track all the way round with the
## charged part lit over it, and the time still to wait is also a shade drawn
## down over the icon, so a glance at the art says how close the next shot is
## without tracing the ring.
##
## Drawn above the icon (z_index), which is what lets the shade cover it; the
## level chip is lifted above this in turn.

const UIWrite := preload("res://scripts/ui/ui_write.gd")

const SILVER := Color("d4dde7")
## A weapon slot feeding an active resonance is marked in gold. One weapon backs
## at most one resonance (ResonanceSystem.is_bound), so with two slots and two
## cores this is the pair's readout of what they have already spent — the same
## fact the core-selection card states as 공명 슬롯 점유 여부.
const GOLD := Color("fff275")
## Treasures have no cooldown; their edge is a still, warm line so the second
## row reads as a different kind of thing from the weapons above it.
const TREASURE := Color("e9c98a")
## The shade over an icon still waiting to fire.
const SHADE := Color(0.02, 0.04, 0.09, 0.62)
const CORNER_RADIUS := 8.0
const LINE_WIDTH := 2.0
## Steps around the ring. The drawing and the "does it need drawing again" test
## are both quantised to this, so a redraw happens exactly when a step changes.
const SEGMENTS := 48
var game: Node
var owner_slot := 0
var item_slot := 0
var weapon := true
var progress := 0.0
var continuous := false
var resonating := false
var phase := 0.0
## What the ring looked like when it was last drawn.
var _drawn_key := -1
## The rounded path for the current size, as a dense polyline with the running
## length at each point, built once per size.
var _path := PackedVector2Array()
var _lengths := PackedFloat32Array()
var _path_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1

func refresh() -> void:
	var loadout: Array = game.weapon_loadouts[owner_slot] if weapon else game.treasure_loadouts[owner_slot]
	visible = item_slot < loadout.size()
	if not visible:
		return
	var state: Dictionary = loadout[item_slot]
	continuous = not weapon or String(state.get("weapon_id", "")) == "frost"
	var art: TextureRect = get_parent().get_parent().get_node("%s%d" % ["Weapon" if weapon else "Treasure", item_slot])
	var tier: Label = art.get_node("Tier")
	resonating = weapon and game.resonance_system.is_bound(owner_slot, item_slot)
	tier.text = str(int(state.get("tier", 1)))
	# Guarded: an unconditional colour override re-shapes the label's text, and
	# this runs every frame for sixteen sockets (see UIWrite).
	UIWrite.font_color(tier, GOLD if resonating else SILVER)
	# The ring is this weapon's own cooldown, always. It used to switch to the
	# resonance's cooldown for a weapon a resonance was firing for, because that
	# weapon had stopped attacking and its own timer meant nothing. Weapons keep
	# attacking through a resonance now, so the ring showing anything but their
	# own next shot would be the ring lying about when they fire.
	if weapon and not continuous:
		var timers: Array = game.attack_timers[owner_slot]
		var remaining: float = float(timers[item_slot]) if item_slot < timers.size() else 0.0
		progress = 1.0 - remaining / maxf(0.01, game._weapon_interval(owner_slot, item_slot))
	else:
		progress = 1.0
	phase = fposmod(float(game.elapsed) * 0.45, 1.0)
	progress = clampf(progress, 0.0, 1.0)
	# Redrawn only when the ring would look different. Every socket used to
	# redraw every frame whether its ring had moved a pixel or not.
	var key := _visual_key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()

func _process(_delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_process(_delta)
	FrameProbe.add(&"render_hud_borders", probe_started)


func _probed_process(_delta: float) -> void:
	if is_instance_valid(game) and get_parent().is_visible_in_tree():
		refresh()


## Only an aura weapon (always on) breathes; a treasure's edge holds still.
func _breathing() -> bool:
	return weapon and continuous


func _visual_key() -> int:
	var step := 0
	if _breathing():
		step = int(round(phase * float(SEGMENTS)))
	elif not continuous:
		step = int(round(progress * float(SEGMENTS)))
	return step * 8 + (4 if not weapon else 0) + (2 if continuous else 0) + (1 if resonating else 0)


## One polyline for the lit run and one for the track under it, plus a single
## rectangle of shade. It was ninety-six separate antialiased draw_line calls,
## each its own canvas command, so sixteen sockets issued over fifteen hundred
## commands a frame for a readout two pixels wide.
func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:equipment_border", probe_started)


func _probed_draw() -> void:
	_ensure_path()
	if not weapon:
		draw_polyline(_path, Color(TREASURE, 0.55), LINE_WIDTH, true)
		return
	var tint := GOLD if resonating else SILVER
	if continuous:
		var colors := PackedColorArray()
		var total := _lengths[_lengths.size() - 1]
		for i in _path.size():
			var t := _lengths[i] / total
			colors.append(Color(tint, 0.3 + 0.7 * (1.0 - fposmod(phase - t, 1.0))))
		draw_polyline_colors(_path, colors, LINE_WIDTH, true)
		return
	var charged := float(clampi(int(round(progress * float(SEGMENTS))), 0, SEGMENTS)) / float(SEGMENTS)
	# The remaining-time shade sits on the icon. Draw it first so the moving
	# cooldown edge remains fully visible above it for both survivors.
	if charged < 1.0:
		var inner := Rect2(Vector2.ONE * LINE_WIDTH, size - Vector2.ONE * LINE_WIDTH * 2.0)
		var shade_height := inner.size.y * (1.0 - charged)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, shade_height)), SHADE)
	draw_polyline(_path, Color(tint, 0.16), LINE_WIDTH, true)
	if charged >= 1.0:
		draw_polyline(_path, tint, LINE_WIDTH, true)
		return
	if charged > 0.0:
		draw_polyline(_cut(charged), tint, LINE_WIDTH, true)


## The path from the top centre, clockwise, as far as `fraction` of the way.
func _cut(fraction: float) -> PackedVector2Array:
	var total := _lengths[_lengths.size() - 1]
	var target := total * fraction
	var points := PackedVector2Array()
	for i in _path.size():
		if _lengths[i] >= target:
			if i > 0:
				var span := _lengths[i] - _lengths[i - 1]
				var t := (target - _lengths[i - 1]) / maxf(0.0001, span)
				points.append(_path[i - 1].lerp(_path[i], t))
			break
		points.append(_path[i])
	return points


## The socket's own rounded rectangle, a line's half-width in from its edge so
## the stroke lies exactly where the box's border would, starting at the top
## centre and running clockwise back to it.
func _ensure_path() -> void:
	if _path_size == size and not _path.is_empty():
		return
	_path_size = size
	_path.clear()
	var inset := LINE_WIDTH * 0.5
	var box := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
	var radius := minf(CORNER_RADIUS - inset, minf(box.size.x, box.size.y) * 0.5)
	var arc_steps := 6
	_path.append(Vector2(box.position.x + box.size.x * 0.5, box.position.y))
	# Corner centres clockwise from the top right, and the angle each arc starts at.
	var corners := [
		[Vector2(box.end.x - radius, box.position.y + radius), -PI * 0.5],
		[Vector2(box.end.x - radius, box.end.y - radius), 0.0],
		[Vector2(box.position.x + radius, box.end.y - radius), PI * 0.5],
		[Vector2(box.position.x + radius, box.position.y + radius), PI],
	]
	for corner: Array in corners:
		var centre: Vector2 = corner[0]
		var start: float = corner[1]
		for step in arc_steps + 1:
			_path.append(centre + Vector2.from_angle(start + PI * 0.5 * float(step) / float(arc_steps)) * radius)
	_path.append(_path[0])
	_lengths.resize(_path.size())
	_lengths[0] = 0.0
	for i in range(1, _path.size()):
		_lengths[i] = _lengths[i - 1] + _path[i - 1].distance_to(_path[i])
