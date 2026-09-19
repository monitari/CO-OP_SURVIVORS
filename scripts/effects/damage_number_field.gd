class_name DamageNumberField
extends Node2D

## Every floating damage number, drawn from one node.
##
## A number used to be its own Label with its own Tween: created on the hit,
## shaped, parented, animated and freed six tenths of a second later. The per-tick
## cap held that to eight new numbers a tick, which is still four hundred and
## eighty nodes a second built and torn down in a late run — and every one of
## them shaped its text on arrival, in the engine's deferred work after the
## scripts had finished, where no script timer could see it. On the late-run
## benchmark turning numbers off entirely saved a third of the frame.
##
## Here a number is four entries in packed arrays. The text goes through
## Font.draw_string, whose shaped-line cache means a "34" that has already been
## drawn is not shaped again; in a fight the same few values repeat constantly.
## The motion is the Label's, reproduced: it rises thirty pixels over 0.48s and
## fades over the last 0.48s of a 0.6s life.

const UIFont := preload("res://assets/fonts/Jua-Regular.ttf")
const FONT_SIZE := 18
const LIFE := 0.6
const RISE := 30.0
const RISE_TIME := 0.48
const FADE_DELAY := 0.12
## More than a tick's worth of the feedback cap many times over, so the ring
## never overwrites a number that is still readable.
const CAPACITY := 96
## The Label's own box: numbers were centred in a 56px-wide label whose top-left
## sat 28px left of and 34px above the hit.
const BOX_WIDTH := 56.0
const BOX_OFFSET := Vector2(-28.0, -34.0)

var _origin := PackedVector2Array()
var _text := PackedStringArray()
var _color := PackedColorArray()
var _age := PackedFloat32Array()
var _next := 0
var _live := 0


func _ready() -> void:
	z_index = 20
	_origin.resize(CAPACITY)
	_text.resize(CAPACITY)
	_color.resize(CAPACITY)
	_age.resize(CAPACITY)
	_age.fill(LIFE)


func add(world_position: Vector2, text: String, color: Color) -> void:
	if _age[_next] >= LIFE:
		_live += 1
	_origin[_next] = world_position
	_text[_next] = text
	_color[_next] = color
	_age[_next] = 0.0
	_next = (_next + 1) % CAPACITY
	queue_redraw()


## Numbers currently on screen.
func live_count() -> int:
	return _live


func clear() -> void:
	_age.fill(LIFE)
	_live = 0
	queue_redraw()


func _process(delta: float) -> void:
	if _live <= 0:
		return
	var live := 0
	for index in CAPACITY:
		if _age[index] >= LIFE:
			continue
		_age[index] += delta
		if _age[index] < LIFE:
			live += 1
	_live = live
	queue_redraw()


func _draw() -> void:
	var ascent := UIFont.get_ascent(FONT_SIZE)
	for index in CAPACITY:
		var age := _age[index]
		if age >= LIFE:
			continue
		var rise := RISE * minf(1.0, age / RISE_TIME)
		var alpha := 1.0 - clampf((age - FADE_DELAY) / (LIFE - FADE_DELAY), 0.0, 1.0)
		var at := _origin[index] + BOX_OFFSET + Vector2(0.0, ascent - rise)
		draw_string(UIFont, at, _text[index], HORIZONTAL_ALIGNMENT_CENTER, BOX_WIDTH,
			FONT_SIZE, Color(_color[index], _color[index].a * alpha))
