class_name Showcase
extends Control

const CardVisual := preload("res://scripts/ui/growth_card_visual.gd")
const L := preload("res://scripts/systems/loc.gd")
var player_labels: Array = ["나", "동료"]

## The three moments a run is actually about, given the screen for a few seconds.
##
## A fusion, a resonance and a chest were all resolved the same way: a line of
## text in the message banner and a small shockwave. Ten level-ups of "+25%
## damage" looked exactly like the one that reworked how a weapon attacks, so
## the biggest thing in the tech tree landed as the smallest thing on screen.
##
## Each mode is deliberately a different *shape*, not the same animation in a
## different colour — a player has to be able to tell what happened from across
## the room:
##
##   FUSION     two things converge and become one. Symmetric, inward, one flash.
##   RESONANCE  two things orbit and stay two, joined by a tether. Circular,
##              outward, repeated waves — it is the pair's move, not one cat's.
##   CHEST      a box resists, bursts, and throws its contents out one at a
##              time. Asymmetric, staggered, no idea what is coming next.
##
## The node runs on PROCESS_MODE_ALWAYS and drives everything from `age`, so it
## plays identically whether the tree is paused behind it (level-up) or not
## (a chest picked up mid-fight). It never touches gameplay state; main.gd
## freezes the run while one is on screen and resumes when `finished` fires.

signal finished

enum Mode { FUSION, RESONANCE, CHEST }

const FUSION_DURATION := 2.15
const RESONANCE_DURATION := 2.45
const CHEST_DURATION := 2.9
## Each reward gets its own beat. The old stagger was a quarter second, which
## on a four-item chest read as everything arriving at once — the exact thing
## the stagger exists to avoid. A full chest now takes twice as long to open as
## a single-item one, which is the difference the player is being told about.
const REWARD_STAGGER := 0.5
const CHEST_BURST_AT := 0.72
## Same weight as CatPanel's veil over the growth and pause screens.
const CHEST_VEIL := 0.22

var mode := Mode.FUSION
var age := 0.0
var duration := FUSION_DURATION
var accent := Color("ffd166")
var headline := ""
var subtitle := ""
var sources: Array[TextureRect] = []
var result_icon: TextureRect
var rewards: Array = [] ## For CHEST: [{icon, label, color}]
var reward_icons: Array[TextureRect] = []
var reward_cards: Array[Control] = []
var caption: Label
var sub_caption: Label
var reward_summary: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 60


## Two ingredients become one weapon. `first` and `second` are the weapon and
## treasure that paid for it; `result` is what they became.
## One weapon reaching its final form. `second` used to be the treasure that
## unlocked it and is now optional, because nothing unlocks an enhancement any
## more — it is the seventh level of the weapon itself.
func play_fusion(first: Texture2D, second: Texture2D, result: Texture2D, display_name: String, tint: Color) -> void:
	mode = Mode.FUSION
	duration = FUSION_DURATION
	accent = tint
	headline = display_name
	subtitle = "진화 완성"
	_add_source(first)
	if second != null:
		_add_source(second)
	result_icon = _add_icon(result, 160.0)
	result_icon.modulate.a = 0.0


## The pair's move. Both weapons stay on screen because a resonance is not one
## of them becoming the other.
func play_resonance(first: Texture2D, second: Texture2D, display_name: String, tint: Color) -> void:
	mode = Mode.RESONANCE
	duration = RESONANCE_DURATION
	accent = tint
	headline = display_name
	subtitle = "공명"
	_add_source(first)
	_add_source(second)


## `entries` are {icon: Texture2D, label: String, color: Color}, thrown out in
## order. The stagger is the whole point: a chest that revealed everything at
## once would be a list.
func play_chest(entries: Array) -> void:
	mode = Mode.CHEST
	rewards = entries
	# Leave a readable final beat after the last reward lands.
	duration = maxf(CHEST_DURATION, CHEST_BURST_AT + 0.5 + float(entries.size()) * REWARD_STAGGER + 2.2)
	accent = Color("ffd166")
	headline = "행운 상자"
	subtitle = L.f("%d개 획득", entries.size())
	for entry: Dictionary in entries:
		# The very card the growth hand deals, painted by the same function at the
		# same size — a reward out of a box is a growth choice somebody else made.
		var card := CardVisual.create_card()
		card.tooltip_text = String(entry.get("label", "보상")) + "\n" + String(entry.get("detail", "")) + "\n" + String(entry.get("advice_reason", ""))
		card.pivot_offset = card.size * 0.5
		var owner := int(entry.get("slot", -1))
		var tint: Color = entry.get("tint", CardVisual.CYAN if owner == 0 else (CardVisual.PARTNER if owner == 1 else CardVisual.CHEST))
		var model: Dictionary = entry.get("card", {
			"category": "상자 보상",
			"title": String(entry.get("label", "보상")),
			"body": String(entry.get("detail", "획득")),
			"icon": entry.get("icon"),
			"advice": String(entry.get("advice", "neutral")),
			"reason": String(entry.get("advice_reason", "무난한 선택")),
		})
		CardVisual.paint(card, model, tint, true, card.size.x, card.size.y)
		# The box has already decided; advice on something already taken is noise.
		card.get_node("Recommendation").visible = false
		add_child(card)
		card.modulate.a = 0.0
		_add_owner_tag(card, owner, tint)
		reward_icons.append(card.get_node("Icon"))
		reward_cards.append(card)


## Who the reward went to, above the card rather than on it: the card itself
## stays exactly the growth card, and the owner is the one thing a chest adds.
func _add_owner_tag(card: Control, slot: int, tint: Color) -> void:
	if slot < 0 or slot >= player_labels.size():
		return
	var tag := Label.new()
	tag.name = "Owner"
	tag.text = String(player_labels[slot])
	tag.position = Vector2(0.0, -34.0)
	tag.size = Vector2(card.size.x, 28.0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_size_override("font_size", 19)
	tag.add_theme_color_override("font_color", tint.lightened(0.3))
	tag.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.95))
	tag.add_theme_constant_override("outline_size", 6)
	card.add_child(tag)


func _ready() -> void:
	# Lightened: the headline is drawn over a veil in the accent colour, and a
	# violet resonance title in violet on violet was nearly invisible.
	caption = _make_label(34, accent.lightened(0.35))
	sub_caption = _make_label(18, Color("f4efe2"))
	caption.text = headline
	sub_caption.text = subtitle


func _make_label(font_size: int, ink: Color) -> Label:
	var item := Label.new()
	item.size = Vector2(900.0, 48.0)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", ink)
	# Outlined: over the lightly veiled rooftop a chest's caption has no dark
	# stage of its own to sit on.
	item.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.9))
	item.add_theme_constant_override("outline_size", 7)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.modulate.a = 0.0
	add_child(item)
	return item


func _add_source(texture: Texture2D) -> void:
	sources.append(_add_icon(texture, 112.0))


func _add_icon(texture: Texture2D, span: float) -> TextureRect:
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = texture
	art.size = Vector2(span, span)
	art.pivot_offset = art.size * 0.5
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	return art


func _process(delta: float) -> void:
	age += delta
	match mode:
		Mode.FUSION:
			_step_fusion()
		Mode.RESONANCE:
			_step_resonance()
		Mode.CHEST:
			_step_chest()
	queue_redraw()
	if age >= duration:
		finished.emit()
		queue_free()


func _centre() -> Vector2:
	return size * 0.5 - Vector2(0.0, 40.0)


## 0 at both ends, 1 through the middle: everything here fades in and out.
func _veil() -> float:
	return minf(smoothstep(0.0, 0.28, age), smoothstep(0.0, 0.3, duration - age))


func _step_fusion() -> void:
	var centre := _centre()
	var closing := clampf(age / 0.62, 0.0, 1.0)
	var eased := ease(closing, 2.4)
	for index in sources.size():
		var art := sources[index]
		var side := -1.0 if index == 0 else 1.0
		var from := centre + Vector2(side * 320.0, 0.0)
		art.position = from.lerp(centre, eased) - art.size * 0.5
		art.scale = Vector2.ONE * lerpf(1.0, 0.45, eased)
		art.rotation = side * eased * 0.6
		art.modulate.a = 1.0 - smoothstep(0.58, 0.72, age)
	if result_icon != null:
		var reveal := smoothstep(0.66, 1.05, age)
		result_icon.position = centre - result_icon.size * 0.5
		result_icon.scale = Vector2.ONE * lerpf(0.3, 1.0, ease(reveal, -2.2))
		result_icon.modulate.a = reveal * minf(1.0, smoothstep(0.0, 0.25, duration - age) * 3.0)
	_place_captions(centre, smoothstep(0.82, 1.15, age))


func _step_resonance() -> void:
	var centre := _centre()
	var arrive := ease(clampf(age / 0.7, 0.0, 1.0), 2.0)
	var spin := age * 2.1
	for index in sources.size():
		var art := sources[index]
		var side := -1.0 if index == 0 else 1.0
		# They orbit rather than converge: two weapons stay two weapons. Same
		# direction and exactly opposite, so the pair reads as one turning
		# system — counter-rotating made them drift into each other and clump.
		var orbit := 210.0 - 60.0 * arrive
		var angle := spin + (0.0 if index == 0 else PI)
		var home := centre + Vector2(side * 340.0, 0.0)
		art.position = home.lerp(centre + Vector2.from_angle(angle) * orbit, arrive) - art.size * 0.5
		art.scale = Vector2.ONE * lerpf(1.0, 0.86, arrive)
		art.modulate.a = minf(1.0, smoothstep(0.0, 0.2, age)) * minf(1.0, smoothstep(0.0, 0.3, duration - age) * 2.0)
	# Above the orbit rather than inside it: the ring passes through the middle
	# of the screen and the two weapons are on it.
	_place_captions(centre - Vector2(0.0, 236.0), smoothstep(0.9, 1.3, age))


## When reward `index` leaves the box.
func _reward_beat(index: int) -> float:
	return CHEST_BURST_AT + 0.18 + float(index) * REWARD_STAGGER


## Horizontal step between reward cards at full size: the growth card plus a
## gutter. One row always, like a dealt hand; a box too full for the row deals
## the same cards smaller rather than a second, differently shaped layout.
const REWARD_PITCH := CardVisual.CARD_SIZE.x + 14.0
const REWARD_ROW_Y := 414.0
const REWARD_ROW_SPAN := 1240.0


func reward_scale() -> float:
	return minf(1.0, REWARD_ROW_SPAN / (float(maxi(1, reward_cards.size())) * REWARD_PITCH))


func _step_chest() -> void:
	var centre := _centre()
	var settle := reward_scale()
	var width := size.x if size.x > 0.0 else 1280.0
	for index in reward_cards.size():
		var card := reward_cards[index]
		var pop := smoothstep(_reward_beat(index), _reward_beat(index) + 0.34, age)
		var x := width * 0.5 + (float(index) - float(reward_cards.size() - 1) * 0.5) * REWARD_PITCH * settle
		var target := Vector2(x, REWARD_ROW_Y)
		card.position = centre.lerp(target, pop) - card.size * 0.5
		card.scale = Vector2.ONE * lerpf(0.1, settle, pop)
		card.rotation = (1.0 - pop) * 0.3
		card.modulate.a = pop * minf(1.0, smoothstep(0.0, 0.25, duration - age) * 3.0)
	# Under the top HUD rather than over it, and above the row of cards.
	_place_captions(Vector2(centre.x, 22.0), smoothstep(0.5, 0.85, age))


func _place_captions(centre: Vector2, reveal: float) -> void:
	if caption == null:
		return
	caption.position = Vector2(centre.x - caption.size.x * 0.5, centre.y + 108.0 - reveal * 8.0)
	sub_caption.position = Vector2(centre.x - sub_caption.size.x * 0.5, centre.y + 154.0)
	var tail := minf(1.0, smoothstep(0.0, 0.25, duration - age) * 3.0)
	caption.modulate.a = reveal * tail
	sub_caption.modulate.a = reveal * tail


func _draw() -> void:
	var probe_started := FrameProbe.mark()
	_probed_draw()
	FrameProbe.add(&"draw:showcase", probe_started)


func _probed_draw() -> void:
	var veil := _veil()
	# A chest opens over the live rooftop, veiled as lightly as the growth and
	# pause screens are; the fusion and resonance moments keep their dark stage.
	var darkness := CHEST_VEIL if mode == Mode.CHEST else 0.78
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, darkness * veil))
	var centre := _centre()
	match mode:
		Mode.FUSION:
			_draw_fusion(centre, veil)
		Mode.RESONANCE:
			_draw_resonance(centre, veil)
		Mode.CHEST:
			_draw_chest(centre, veil)


## Inward: converging spokes, then one hard flash, then a steady halo.
func _draw_fusion(centre: Vector2, veil: float) -> void:
	var closing := clampf(age / 0.62, 0.0, 1.0)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var outer := 520.0 * (1.0 - ease(closing, 2.0)) + 90.0
		draw_line(centre + Vector2.from_angle(angle) * outer,
			centre + Vector2.from_angle(angle) * (outer * 0.62 + 40.0),
			Color(accent, 0.45 * veil * (1.0 - closing * 0.4)), 4.0, true)
	var flash := 1.0 - clampf(absf(age - 0.66) / 0.14, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(centre, 60.0 + flash * 480.0, Color(1.0, 1.0, 1.0, 0.55 * flash))
	var halo := smoothstep(0.66, 1.1, age)
	if halo > 0.0:
		for ring in 3:
			var radius := 120.0 + float(ring) * 34.0 + sin(age * 3.0 + float(ring)) * 6.0
			draw_arc(centre, radius, age * (1.4 + ring), age * (1.4 + ring) + 4.4, 26,
				Color(accent, (0.5 - ring * 0.12) * halo * veil), 5.0 - ring, true)


## Outward: a tether between the two, and waves that keep leaving.
func _draw_resonance(centre: Vector2, veil: float) -> void:
	var arrive := ease(clampf(age / 0.7, 0.0, 1.0), 2.0)
	if sources.size() == 2 and arrive > 0.05:
		var a := sources[0].position + sources[0].size * 0.5
		var b := sources[1].position + sources[1].size * 0.5
		var link := PackedVector2Array()
		for step in 17:
			var ratio := float(step) / 16.0
			var point := a.lerp(b, ratio)
			point += (b - a).orthogonal().normalized() * sin(ratio * PI * 3.0 + age * 9.0) * 22.0 * arrive
			link.append(point)
		draw_polyline(link, Color(accent.lightened(0.3), 0.85 * veil), 5.0, true)
	# Three waves on their own phases, always leaving rather than arriving.
	for wave in 3:
		var phase := fmod(age * 0.85 + float(wave) / 3.0, 1.0)
		draw_arc(centre, 60.0 + phase * 430.0, 0.0, TAU, 64,
			Color(accent, (1.0 - phase) * 0.5 * veil), 6.0 * (1.0 - phase) + 1.0, true)
	for index in 20:
		var angle := TAU * float(index) / 20.0 + age * 0.6
		var reach := 250.0 + sin(age * 4.0 + index) * 18.0
		draw_circle(centre + Vector2.from_angle(angle) * reach, 3.0, Color(accent, 0.55 * veil))


## A box that resists, then gives. The shake is on the drawn lid, not on the
## camera, so it reads as the chest struggling rather than as an impact.
func _draw_chest(centre: Vector2, veil: float) -> void:
	var burst_at := CHEST_BURST_AT
	var struggle := clampf(age / burst_at, 0.0, 1.0)
	if age < burst_at:
		var shake := Vector2(sin(age * 46.0), cos(age * 39.0)) * (2.0 + struggle * 9.0)
		var box := Rect2(centre - Vector2(76.0, 58.0) + shake, Vector2(152.0, 116.0))
		draw_rect(box, Color("8a5a2b", veil))
		draw_rect(Rect2(box.position, Vector2(box.size.x, 34.0)), Color("a9713a", veil))
		draw_rect(Rect2(box.position + Vector2(box.size.x * 0.5 - 11.0, 0.0), Vector2(22.0, box.size.y)),
			Color(accent, 0.9 * veil))
		draw_circle(box.get_center() + Vector2(0.0, -6.0), 13.0, Color("f2dcae", veil))
		# Light escaping from the seam, brighter the closer it is to opening.
		draw_rect(Rect2(box.position + Vector2(0.0, 32.0), Vector2(box.size.x, 4.0)),
			Color(1.0, 0.96, 0.8, struggle * struggle * veil))
		return
	var since := age - burst_at
	# More in the box, more coming out of it: the burst itself reports the haul
	# before the first icon has even landed.
	var spokes := 18 + reward_icons.size() * 6
	var rays := clampf(1.0 - since / 0.8, 0.0, 1.0)
	if rays > 0.0:
		for index in spokes:
			var angle := TAU * float(index) / float(spokes) + since * 1.4
			var length := 60.0 + (1.0 - rays) * (520.0 + reward_icons.size() * 60.0)
			draw_line(centre + Vector2.from_angle(angle) * 40.0,
				centre + Vector2.from_angle(angle) * length,
				Color(accent.lightened(0.3), rays * 0.75 * veil), 6.0 * rays + 1.0, true)
	var flash := 1.0 - clampf(since / 0.2, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(centre, 40.0 + flash * 460.0, Color(1.0, 1.0, 1.0, 0.5 * flash))
	# A soft column the rewards rise out of, and three rings still leaving it.
	draw_rect(Rect2(centre.x - 90.0, centre.y - 40.0, 180.0, 260.0), Color(accent, 0.07 * veil))
	for wave in 3:
		var phase := fmod(since * 0.7 + float(wave) / 3.0, 1.0)
		draw_arc(centre, 50.0 + phase * 300.0, 0.0, TAU, 48,
			Color(accent, (1.0 - phase) * 0.3 * veil), 4.0 * (1.0 - phase) + 1.0, true)
	# One halo per reward, fired on that reward's own beat, so a four-item chest
	# is four distinct moments rather than one long one.
	for index in reward_icons.size():
		var at := _reward_beat(index)
		var pulse := 1.0 - clampf((age - at) / 0.42, 0.0, 1.0)
		if pulse <= 0.0 or age < at:
			continue
		var card := reward_cards[index]
		var landing := card.position + card.size * 0.5
		draw_arc(landing, 26.0 + (1.0 - pulse) * 70.0, 0.0, TAU, 32,
			Color(Color.WHITE, pulse * 0.75 * veil), 5.0 * pulse + 1.0, true)
		for spark in 8:
			var angle := TAU * float(spark) / 8.0 + float(index)
			var reach := 30.0 + (1.0 - pulse) * 54.0
			draw_line(landing + Vector2.from_angle(angle) * reach * 0.55,
				landing + Vector2.from_angle(angle) * reach,
				Color(accent.lightened(0.4), pulse * 0.8 * veil), 3.0 * pulse + 0.6, true)
