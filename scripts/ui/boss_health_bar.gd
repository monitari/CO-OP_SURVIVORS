extends Control

## The boss bar, drawn rather than themed.
##
## It used to be a `ProgressBar` with a number over it, which is the same widget
## the chain meter and the XP bar use — so the one enemy the whole run is built
## around announced itself in exactly the visual language of a passive stat. A
## boss is the loudest thing on the roof and its bar should be too.
##
## Four things this draws that a ProgressBar cannot:
##
##   - **a lagging ghost.** A burst of damage drops the red fill instantly and
##     leaves a pale bar behind it that catches up over half a second. That gap
##     is the readout of "how much did that just do", which is the question a
##     player actually asks during a boss fight and which a single sliding edge
##     cannot answer.
##   - **phase notches.** The bar is divided into segments, so "a quarter left"
##     is something you see rather than something you compute from two numbers.
##   - **rank pips.** How far into the run's five bosses this one is, next to its
##     name instead of spelled out as "2/5" in a separate label.
##   - **an enrage state.** Crossing half health changes how the fight is played
##     (ChaserEnemy.enraged), so it changes how the bar looks: hotter colour and
##     a slow pulse along the fill.
##
## Colours come from the danger palette rather than CatTheme's menu tokens: this
## is combat ownership, and the memory of which colours mean "something is about
## to hurt you" is built during the fight, not in the menus.

const CatTheme := preload("res://scripts/ui/cat_theme.gd")

const TRACK := Color("0a1122e6")
const OUTLINE := Color("7596bd66")
const FILL := Color("ef476f")
const FILL_ENRAGED := Color("ff334f")
const GHOST := Color("ffd6de")
const PIP_ON := Color("fff275")
const PIP_OFF := Color("7596bd55")
const NAME_INK := Color("ffe9c9")

## How fast the pale trailing bar closes on the real one, in fractions of the
## remaining gap per second. Slow enough to read a burst, fast enough that it is
## never still lagging when the next one lands.
const GHOST_CATCHUP := 3.4
## Segments the track is notched into. Five reads as "phases" at a glance and
## still leaves each segment wide enough to see partially drained.
const SEGMENTS := 5
const CORNER := 4.0

var ratio := 1.0
var ghost_ratio := 1.0
var enraged := false
var boss_name := ""
var rank := 1
var rank_total := 5
var health_text := ""
var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `health` and `maximum` are the live numbers; everything else is presentation.
func report(health: float, maximum: float, is_enraged: bool) -> void:
	ratio = clampf(health / maxf(1.0, maximum), 0.0, 1.0)
	# The ghost only ever lags *behind*. A boss that heals or a new boss that
	# arrives at full health snaps it forward rather than crawling up, because a
	# pale bar climbing would read as damage the player did not do.
	if ratio > ghost_ratio:
		ghost_ratio = ratio
	enraged = is_enraged
	health_text = "%d / %d" % [int(ceil(maxf(0.0, health))), int(ceil(maxf(1.0, maximum)))]
	queue_redraw()


func reset(name_text: String, boss_rank: int, total: int, maximum: float) -> void:
	boss_name = name_text
	rank = boss_rank
	rank_total = total
	ratio = 1.0
	ghost_ratio = 1.0
	enraged = false
	pulse = 0.0
	health_text = "%d / %d" % [int(ceil(maximum)), int(ceil(maximum))]
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if ghost_ratio > ratio:
		ghost_ratio = maxf(ratio, ghost_ratio - (ghost_ratio - ratio) * GHOST_CATCHUP * delta - 0.02 * delta)
		queue_redraw()
	if enraged:
		pulse = fposmod(pulse + delta * 2.2, TAU)
		queue_redraw()


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:boss_health_bar", probe_started)


func _probed_draw() -> void:
	var bar_height := 20.0
	var top := size.y - bar_height
	var track := Rect2(0.0, top, size.x, bar_height)
	draw_rect(track, TRACK, true)

	# Ghost first, so the live fill sits on top of it and the gap between the two
	# edges is what the eye lands on.
	if ghost_ratio > ratio:
		draw_rect(Rect2(track.position, Vector2(track.size.x * ghost_ratio, bar_height)), Color(GHOST, 0.5), true)
	var fill_color := FILL_ENRAGED if enraged else FILL
	if enraged:
		fill_color = fill_color.lerp(Color("ffb4a2"), 0.18 + 0.18 * sin(pulse))
	if ratio > 0.0:
		draw_rect(Rect2(track.position, Vector2(track.size.x * ratio, bar_height)), fill_color, true)
		# A brighter lip along the top of the fill, which is what keeps a dark
		# red bar legible over the equally dark roof behind the HUD.
		draw_rect(Rect2(track.position, Vector2(track.size.x * ratio, 3.0)), fill_color.lightened(0.35), true)

	# Notches are drawn over the fill rather than under it, so they keep marking
	# the same places as the bar drains.
	for segment in range(1, SEGMENTS):
		var x := track.position.x + track.size.x * float(segment) / float(SEGMENTS)
		draw_line(Vector2(x, top + 2.0), Vector2(x, top + bar_height - 2.0), Color(TRACK, 0.85), 2.0)
	draw_rect(track, OUTLINE, false, 1.0)

	# The readout face, not the theme's handwriting: this strip is a name, a rank
	# and two numbers read while the boss is swinging.
	var font: Font = CatTheme.READOUT
	# The strip above the bar reads left to right in one pass: name, then the
	# pips that say which boss this is, then the numbers. Laying the pips out
	# from the end of the name rather than centring them is what keeps a long
	# Korean boss name from running through them.
	var baseline := top - 7.0
	var cursor := 2.0
	if not boss_name.is_empty():
		draw_string(font, Vector2(cursor, baseline), boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, NAME_INK)
		cursor += font.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0
	var pip_gap := 12.0
	for index in rank_total:
		var filled := index < rank
		var centre := Vector2(cursor + pip_gap * float(index), baseline - 5.0)
		draw_circle(centre, 4.0 if filled else 3.0, PIP_ON if filled else PIP_OFF, true, -1.0, true)
	if not health_text.is_empty():
		draw_string(font, Vector2(size.x - 150.0, baseline), health_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 148.0, 14, Color("d9e6f5"))
