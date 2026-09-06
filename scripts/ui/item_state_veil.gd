class_name ItemStateVeil
extends Control

## Full-screen tell for the timed field items.
##
## 멈춘 털실시계, 아홉 목숨 방울, 광란의 마타타비 and 황금 목줄 each change the rules of
## the fight for a few seconds, and each said so with one line of text that had
## already scrolled off the screen by the time it mattered. A player standing in
## a crowd of six hundred cannot read a message log. They can read the colour of
## their own screen.
##
## Every one of these states now washes the world in a tone of its own, pulls a
## vignette in from the edges so the effect reads even where the middle of the
## screen is busy, and puts a named bar along the bottom that visibly runs out —
## so "this is happening" and "this is nearly over" are two different pictures.

## The states this can show, in the order their bars stack. `wash` tints the
## whole field, `edge` is the vignette pulled in from the border, and `weight`
## decides which tone wins when two are running at once — stopping time is the
## loudest thing that can happen, so it takes the screen.
const STATES := [
	{"id": "time_stop", "name": "시간 정지", "wash": Color("2f6bff"), "edge": Color("8fd4ff"), "weight": 3.0},
	{"id": "frenzy", "name": "광란", "wash": Color("ff5a2b"), "edge": Color("ffb08a"), "weight": 2.0},
	{"id": "guard", "name": "무적", "wash": Color("6fe3ff"), "edge": Color("d6f7ff"), "weight": 1.5},
	{"id": "chain_ward", "name": "황금 목줄", "wash": Color("ffe066"), "edge": Color("fff4c2"), "weight": 1.0},
]

const SCREEN := Vector2(1280.0, 720.0)
## How dark the wash gets at full strength. Deliberately low: this sits over the
## play field, and a tint a player cannot see past is a tint that gets them hit.
const WASH_ALPHA := 0.14
const EDGE_ALPHA := 0.34
## Bands used to fake a vignette. Enough steps that the falloff reads as a
## gradient rather than as four rectangles, few enough to stay a rounding error.
const EDGE_BANDS := 14
const EDGE_DEPTH := 150.0
## A state with less than this fraction of its window left flashes, so running
## out is something a player notices before it happens rather than after.
const EXPIRY_WARNING := 0.28

## id -> [remaining, total]. Only ids currently running appear.
var running: Dictionary = {}

var _chips: Dictionary = {}


func _ready() -> void:
	position = Vector2.ZERO
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -1 # under the HUD text, over the play field
	for entry in STATES:
		_chips[String(entry["id"])] = _build_chip(entry)


## Called once per HUD refresh with every window's remaining and total time. A
## state whose remaining time is zero simply stops being handed in.
func refresh(windows: Dictionary) -> void:
	running = windows
	visible = not running.is_empty()
	var shown := 0
	for entry in STATES:
		var id := String(entry["id"])
		var chip: Control = _chips[id]
		var window: Array = running.get(id, [])
		chip.visible = window.size() == 2 and float(window[0]) > 0.0
		if not chip.visible:
			continue
		var remaining := float(window[0])
		var total := maxf(0.01, float(window[1]))
		var ratio := clampf(remaining / total, 0.0, 1.0)
		# Chips are laid out as they are found rather than by their index in the
		# table, so a single running state sits in the middle of the screen
		# instead of wherever its row happens to be.
		chip.position = Vector2(SCREEN.x * 0.5 - 96.0, 596.0 + float(shown) * 34.0)
		var label := chip.get_node("Name") as Label
		label.text = "%s  %.1f초" % [String(entry["name"]), remaining]
		var fill := chip.get_node("Fill") as ColorRect
		fill.size = Vector2(188.0 * ratio, 4.0)
		var urgent := ratio <= EXPIRY_WARNING
		var pulse := 1.0 if not urgent else 0.45 + absf(sin(float(Time.get_ticks_msec()) * 0.011)) * 0.55
		chip.modulate.a = pulse
		shown += 1
	queue_redraw()


## The loudest running state, and how strongly it should read. Strength is the
## window's own fraction eased up quickly, so a wash arrives the moment an item
## is taken and thins out as it expires instead of cutting off.
func _dominant() -> Dictionary:
	var best: Dictionary = {}
	var best_weight := 0.0
	for entry in STATES:
		var window: Array = running.get(String(entry["id"]), [])
		if window.size() != 2 or float(window[0]) <= 0.0:
			continue
		var weight := float(entry["weight"])
		if weight <= best_weight:
			continue
		best_weight = weight
		var ratio := clampf(float(window[0]) / maxf(0.01, float(window[1])), 0.0, 1.0)
		best = {"entry": entry, "strength": minf(1.0, 0.35 + ratio * 0.65)}
	return best


func _draw() -> void:
	var dominant := _dominant()
	if dominant.is_empty():
		return
	var entry: Dictionary = dominant["entry"]
	var strength := float(dominant["strength"])
	var wash: Color = entry["wash"]
	var edge: Color = entry["edge"]
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(wash, WASH_ALPHA * strength))
	# Four bands per step rather than a shader: this is a 2D game on the
	# compatibility renderer, and fifty-six thin rectangles cost nothing next to
	# pulling in a whole material for a border glow.
	for band in EDGE_BANDS:
		var into := float(band) / float(EDGE_BANDS)
		var depth := EDGE_DEPTH * (1.0 - into)
		var alpha := EDGE_ALPHA * strength * into * into / float(EDGE_BANDS) * 4.0
		var tint := Color(edge, alpha)
		draw_rect(Rect2(0.0, 0.0, SCREEN.x, depth), tint)
		draw_rect(Rect2(0.0, SCREEN.y - depth, SCREEN.x, depth), tint)
		draw_rect(Rect2(0.0, 0.0, depth, SCREEN.y), tint)
		draw_rect(Rect2(SCREEN.x - depth, 0.0, depth, SCREEN.y), tint)


## Name over a draining bar, on a plate dark enough to stay legible against the
## wash it is sitting on top of.
func _build_chip(entry: Dictionary) -> Control:
	var chip := Control.new()
	chip.name = "Chip_" + String(entry["id"])
	chip.size = Vector2(192.0, 30.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.visible = false
	add_child(chip)

	var plate := ColorRect.new()
	plate.name = "Plate"
	plate.position = Vector2(-2.0, -2.0)
	plate.size = Vector2(196.0, 30.0)
	plate.color = Color(0.03, 0.05, 0.09, 0.62)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(plate)

	var label := Label.new()
	label.name = "Name"
	label.position = Vector2(0.0, 0.0)
	label.size = Vector2(188.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", entry["edge"])
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	chip.add_child(label)

	var track := ColorRect.new()
	track.name = "Track"
	track.position = Vector2(0.0, 22.0)
	track.size = Vector2(188.0, 4.0)
	track.color = Color(1.0, 1.0, 1.0, 0.14)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(track)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2(0.0, 22.0)
	fill.size = Vector2(188.0, 4.0)
	fill.color = entry["wash"]
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(fill)
	return chip
