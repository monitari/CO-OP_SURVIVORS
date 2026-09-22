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
## A reward's trip out of the box: an arc up and over into its place in the row,
## then a short landing. Flight plus landing stays under half a second so the
## next reward (REWARD_STAGGER) never leaves before the last one has settled.
const REWARD_FLIGHT := 0.36
const REWARD_LANDING := 0.12
## How high above the straight line the arc peaks, in screen pixels.
const REWARD_ARC := 250.0
## Coins and confetti fall under this, in screen pixels per second squared.
const BIT_GRAVITY := 1500.0
const MAX_BITS := 260
const COIN := Color("ffd166")
const CONFETTI := [Color("ffd166"), Color("43d9ff"), Color("c77dff"), Color("ff9fbd"), Color("80ed99")]

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
## Drawn over the reward cards: the shine that sweeps a card once it lands.
## Everything else a chest draws is under them, because the cards are what the
## player is reading.
var overlay: Control
## Screen-space flecks: coins and confetti out of the burst, twinkles behind a
## card in flight. {position, velocity, age, life, kind, color, spin}
var bits: Array = []
var _burst_thrown := false


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
		card.set_meta("tint", tint)
		# Every card leaves the box face down and turns over in the air: the
		# reward is revealed by the throw, not listed.
		var back := Control.new()
		back.name = "CardBack"
		back.size = card.size
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.draw.connect(_paint_card_back.bind(back, tint))
		card.add_child(back)
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
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


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
			_step_bits(delta)
	queue_redraw()
	if overlay != null:
		overlay.queue_redraw()
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


## When reward `index` has finished landing and lies in the row.
func _reward_landed(index: int) -> float:
	return _reward_beat(index) + REWARD_FLIGHT + REWARD_LANDING


## Horizontal step between reward cards at full size: the growth card plus a
## gutter. One row always, like a dealt hand; a box too full for the row deals
## the same cards smaller rather than a second, differently shaped layout.
const REWARD_PITCH := CardVisual.CARD_SIZE.x + 14.0
const REWARD_ROW_Y := 414.0
const REWARD_ROW_SPAN := 1240.0


func reward_scale() -> float:
	return minf(1.0, REWARD_ROW_SPAN / (float(maxi(1, reward_cards.size())) * REWARD_PITCH))


func _reward_target(index: int) -> Vector2:
	var width := size.x if size.x > 0.0 else 1280.0
	var x := width * 0.5 + (float(index) - float(reward_cards.size() - 1) * 0.5) * REWARD_PITCH * reward_scale()
	return Vector2(x, REWARD_ROW_Y)


## Where the rewards leave from: the mouth of the open box.
func _mouth() -> Vector2:
	return _centre() + Vector2(0.0, -34.0)


## A card's centre `travel` of the way along its throw: up out of the box, over
## the top of an arc, and down into its place.
func _flight_point(index: int, travel: float) -> Vector2:
	var start := _mouth()
	var target := _reward_target(index)
	var peak := (start + target) * 0.5 + Vector2((target.x - start.x) * 0.12, -REWARD_ARC)
	var inverse := 1.0 - travel
	return start * inverse * inverse + peak * 2.0 * inverse * travel + target * travel * travel


func _step_chest() -> void:
	var settle := reward_scale()
	var tail := minf(1.0, smoothstep(0.0, 0.25, duration - age) * 3.0)
	for index in reward_cards.size():
		var card := reward_cards[index]
		var since := age - _reward_beat(index)
		if since < 0.0:
			card.modulate.a = 0.0
			continue
		var flight := clampf(since / REWARD_FLIGHT, 0.0, 1.0)
		# Fast out of the box, slowing into place: a throw, not a slide.
		var travel := 1.0 - pow(1.0 - flight, 3.0)
		var at := _flight_point(index, travel)
		var target := _reward_target(index)
		var side := -1.0 if target.x < _mouth().x else 1.0
		# Grows as it comes toward the viewer and overshoots its size a little,
		# so the landing has something to settle out of.
		var span := lerpf(0.22, settle * 1.1, travel)
		var squash := Vector2.ONE
		if flight >= 1.0:
			var land := clampf((since - REWARD_FLIGHT) / REWARD_LANDING, 0.0, 1.0)
			var bounce := sin(land * PI) * (1.0 - land * 0.5)
			span = lerpf(settle * 1.1, settle, ease(land, 0.6))
			squash = Vector2(1.0 + 0.08 * bounce, 1.0 - 0.1 * bounce)
			if land >= 1.0:
				span = settle
				squash = Vector2.ONE
				# At rest it floats a little, each card on its own beat.
				at.y += sin((since - REWARD_FLIGHT - REWARD_LANDING) * 2.4 + float(index) * 1.3) * 3.0
		# Face down leaving the box, turned over by the top of the arc. The turn
		# is a squeeze of the width through zero, which is what a card flipping
		# edge-on to the viewer looks like.
		var turn := clampf(flight / 0.8, 0.0, 1.0)
		var face := absf(cos(turn * PI))
		var face_down := turn < 0.5
		var back := card.get_node_or_null("CardBack")
		if back != null:
			back.visible = face_down
		var owner_tag := card.get_node_or_null("Owner")
		if owner_tag != null:
			owner_tag.visible = not face_down
		card.rotation = (1.0 - travel) * 0.5 * side
		card.scale = Vector2(span * maxf(0.03, face) * squash.x, span * squash.y)
		card.position = at - card.size * 0.5
		card.modulate.a = minf(1.0, since / 0.06) * tail
	# Under the top HUD rather than over it, and above the row of cards.
	_place_captions(Vector2(_centre().x, 22.0), smoothstep(0.5, 0.85, age))


## Coins, confetti and the sparkle each card trails in flight.
func _step_bits(delta: float) -> void:
	if not _burst_thrown and age >= CHEST_BURST_AT:
		_burst_thrown = true
		_throw_burst()
	for index in reward_cards.size():
		var since := age - _reward_beat(index)
		if since >= 0.0 and since < REWARD_FLIGHT:
			var at := _flight_point(index, 1.0 - pow(1.0 - since / REWARD_FLIGHT, 3.0))
			_add_bit({"position": at + Vector2(randf_range(-30.0, 30.0), randf_range(-40.0, 40.0)),
				"velocity": Vector2(randf_range(-40.0, 40.0), randf_range(-60.0, 10.0)),
				"age": 0.0, "life": randf_range(0.35, 0.55), "kind": "twinkle",
				"color": (reward_cards[index].get_meta("tint", accent) as Color).lightened(0.4), "spin": 0.0})
	var alive: Array = []
	for bit in bits:
		bit["age"] = float(bit["age"]) + delta
		if float(bit["age"]) >= float(bit["life"]):
			continue
		var velocity := bit["velocity"] as Vector2
		if String(bit["kind"]) != "twinkle":
			velocity.y += BIT_GRAVITY * delta
			velocity.x *= maxf(0.0, 1.0 - delta * 0.9)
		bit["velocity"] = velocity
		bit["position"] = (bit["position"] as Vector2) + velocity * delta
		bit["spin"] = float(bit["spin"]) + delta * 9.0
		alive.append(bit)
	bits = alive


## The haul announces itself before the first card lands: more in the box, more
## thrown out of it.
func _throw_burst() -> void:
	var count := 22 + reward_cards.size() * 6
	for index in count:
		var coin := index % 5 < 3
		var colour: Color = COIN if coin else CONFETTI[index % CONFETTI.size()]
		_add_bit({"position": _mouth() + Vector2(randf_range(-40.0, 40.0), 0.0),
			"velocity": Vector2(randf_range(-460.0, 460.0), randf_range(-1050.0, -560.0)),
			"age": 0.0, "life": randf_range(1.3, 1.9), "kind": "coin" if coin else "confetti",
			"color": colour, "spin": randf() * TAU})


func _add_bit(bit: Dictionary) -> void:
	if bits.size() >= MAX_BITS:
		return
	bits.append(bit)


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


## A box that resists, then gives. It shivers, crouches, springs, and the lid is
## thrown off; the cards come out of the open box one at a time.
func _draw_chest(centre: Vector2, veil: float) -> void:
	var burst_at := CHEST_BURST_AT
	var since := age - burst_at
	var bottom := centre + Vector2(0.0, 58.0)
	# Light turning behind everything once the box is open.
	if since > 0.0:
		var rise := smoothstep(0.0, 0.35, since)
		for ray in 12:
			var angle := since * 0.35 + TAU * float(ray) / 12.0
			var spread := 0.07 if ray % 2 == 0 else 0.045
			draw_colored_polygon(PackedVector2Array([_mouth(),
				_mouth() + Vector2.from_angle(angle - spread) * 760.0,
				_mouth() + Vector2.from_angle(angle + spread) * 760.0]),
				Color(accent.lightened(0.3), 0.07 * rise * veil))
	# Coins and confetti, under the cards.
	for bit in bits:
		_draw_bit(self, bit, veil)
	if age < burst_at:
		var struggle := clampf(age / burst_at, 0.0, 1.0)
		var rattle := Vector2(sin(age * 46.0), cos(age * 39.0)) * (1.5 + struggle * 7.0)
		# Crouch, then spring: the squash before the stretch is what sells the
		# burst as the box's own effort.
		var crouch := smoothstep(0.55, 0.84, struggle)
		var spring := smoothstep(0.84, 1.0, struggle)
		var squash := Vector2(1.0 + 0.16 * crouch, 1.0 - 0.2 * crouch).lerp(Vector2(0.9, 1.2), spring)
		var hop := -26.0 * spring
		_draw_box(bottom + rattle * (1.0 - crouch * 0.6) + Vector2(0.0, hop), squash, veil, true, struggle)
		return
	# The box, open, and its lid flying off and falling away.
	var settle := 1.0 - clampf(since / 0.18, 0.0, 1.0)
	_draw_box(bottom, Vector2(1.0 - 0.08 * settle, 1.0 + 0.1 * settle), veil, false, 1.0)
	var lid_age := since
	if lid_age < 1.1:
		var lid_at := bottom + Vector2(-76.0, -116.0) + Vector2(-190.0 * lid_age, -640.0 * lid_age + 0.5 * BIT_GRAVITY * lid_age * lid_age)
		draw_set_transform(lid_at + Vector2(76.0, 17.0), -lid_age * 7.0, Vector2.ONE)
		var lid_alpha := veil * (1.0 - smoothstep(0.7, 1.1, lid_age))
		draw_rect(Rect2(-76.0, -17.0, 152.0, 34.0), Color("a9713a", lid_alpha))
		draw_rect(Rect2(-11.0, -17.0, 22.0, 34.0), Color(accent, 0.9 * lid_alpha))
		draw_rect(Rect2(-76.0, -17.0, 152.0, 34.0), Color(0.1, 0.06, 0.03, 0.7 * lid_alpha), false, 3.0)
		draw_set_transform(Vector2.ZERO)
	var flash := 1.0 - clampf(since / 0.2, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(_mouth(), 40.0 + flash * 460.0, Color(1.0, 1.0, 1.0, 0.42 * flash))
	# The shock of the burst: rays thrown out, reporting the haul by how many.
	var spokes := 18 + reward_cards.size() * 6
	var rays := clampf(1.0 - since / 0.8, 0.0, 1.0)
	if rays > 0.0:
		for index in spokes:
			var angle := TAU * float(index) / float(spokes) + since * 1.4
			var length := 60.0 + (1.0 - rays) * (520.0 + reward_cards.size() * 60.0)
			draw_line(_mouth() + Vector2.from_angle(angle) * 40.0,
				_mouth() + Vector2.from_angle(angle) * length,
				Color(accent.lightened(0.3), rays * 0.7 * veil), 6.0 * rays + 1.0, true)
	for wave in 3:
		var phase := fmod(since * 0.7 + float(wave) / 3.0, 1.0)
		draw_arc(_mouth(), 50.0 + phase * 300.0, 0.0, TAU, 48,
			Color(accent, (1.0 - phase) * 0.28 * veil), 4.0 * (1.0 - phase) + 1.0, true)
	# Each card's arrival: a glow behind the landed card and a halo where it hit.
	for index in reward_cards.size():
		var landed := _reward_beat(index) + REWARD_FLIGHT
		if age < landed:
			continue
		var card := reward_cards[index]
		var tint: Color = card.get_meta("tint", accent)
		var drawn := Rect2(card.position + card.size * 0.5 * (Vector2.ONE - card.scale), card.size * card.scale)
		var breathe := 0.75 + 0.25 * sin(age * 3.0 + float(index))
		for glow in 3:
			draw_rect(drawn.grow(6.0 + float(glow) * 7.0), Color(tint, 0.1 * breathe * veil * (1.0 - float(glow) * 0.28)), false, 7.0)
		var pulse := 1.0 - clampf((age - landed) / 0.42, 0.0, 1.0)
		if pulse <= 0.0:
			continue
		var at := drawn.get_center()
		draw_arc(at, 40.0 + (1.0 - pulse) * 130.0, 0.0, TAU, 40,
			Color(Color.WHITE, pulse * 0.7 * veil), 6.0 * pulse + 1.0, true)
		for spark in 10:
			var angle := TAU * float(spark) / 10.0 + float(index)
			var reach := 50.0 + (1.0 - pulse) * 110.0
			draw_line(at + Vector2.from_angle(angle) * reach * 0.6,
				at + Vector2.from_angle(angle) * reach,
				Color(tint.lightened(0.4), pulse * 0.85 * veil), 3.5 * pulse + 0.6, true)


## The chest itself, standing on `bottom` and scaled about it. `closed` draws the
## lid on; `strain` is how close the seam is to giving.
func _draw_box(bottom: Vector2, squash: Vector2, veil: float, closed: bool, strain: float) -> void:
	draw_set_transform(bottom, 0.0, squash)
	var body := Rect2(-76.0, -116.0, 152.0, 116.0)
	draw_rect(Rect2(-70.0, -4.0, 140.0, 10.0), Color(0.0, 0.0, 0.0, 0.3 * veil))
	draw_rect(body, Color("8a5a2b", veil))
	for plank in 3:
		var y := -84.0 + float(plank) * 28.0
		draw_line(Vector2(-76.0, y), Vector2(76.0, y), Color(0.25, 0.14, 0.06, 0.55 * veil), 2.0)
	draw_rect(Rect2(-11.0, -116.0, 22.0, 116.0), Color(accent, 0.9 * veil))
	if closed:
		draw_rect(Rect2(-76.0, -116.0, 152.0, 34.0), Color("a9713a", veil))
		draw_rect(Rect2(-11.0, -116.0, 22.0, 34.0), Color(accent.lightened(0.1), veil))
		draw_circle(Vector2(0.0, -64.0), 13.0, Color("f2dcae", veil))
		# Light escaping from the seam, and in the last moments through it.
		draw_rect(Rect2(-76.0, -84.0, 152.0, 4.0), Color(1.0, 0.96, 0.8, strain * strain * veil))
		if strain > 0.5:
			var leak := (strain - 0.5) * 2.0
			for beam in 5:
				var x := -60.0 + float(beam) * 30.0
				draw_line(Vector2(x, -82.0), Vector2(x * 1.6, -82.0 - 60.0 * leak), Color(1.0, 0.95, 0.75, 0.35 * leak * veil), 3.0, true)
	else:
		# Open: the inside glowing with whatever is still in there.
		draw_rect(Rect2(-68.0, -116.0, 136.0, 16.0), Color("2a1a0c", veil))
		draw_rect(Rect2(-68.0, -116.0, 136.0, 16.0), Color(accent.lightened(0.4), 0.55 * veil))
	draw_rect(body, Color(0.1, 0.06, 0.03, 0.7 * veil), false, 3.0)
	draw_set_transform(Vector2.ZERO)


static func _draw_bit(canvas: CanvasItem, bit: Dictionary, veil: float) -> void:
	var progress := float(bit["age"]) / float(bit["life"])
	var fade := (1.0 - smoothstep(0.7, 1.0, progress)) * veil
	var at := bit["position"] as Vector2
	var colour := bit["color"] as Color
	var spin := float(bit["spin"])
	match String(bit["kind"]):
		"coin":
			# A spinning coin is an ellipse whose width follows the spin.
			var width := 9.0 * absf(cos(spin)) + 1.5
			canvas.draw_set_transform(at, 0.0, Vector2(width / 9.0, 1.0))
			canvas.draw_circle(Vector2.ZERO, 9.0, Color(colour.darkened(0.25), fade))
			canvas.draw_circle(Vector2(-1.5, -1.5), 6.5, Color(colour, fade))
			canvas.draw_set_transform(Vector2.ZERO)
		"confetti":
			var turn := Vector2.from_angle(spin) * 6.0
			var side := turn.orthogonal() * 0.45 * absf(sin(spin * 0.7))
			canvas.draw_colored_polygon(PackedVector2Array([at + turn + side, at - turn + side, at - turn - side, at + turn - side]),
				Color(colour, fade))
		_:
			var twinkle := sin(progress * PI)
			var reach := 7.0 * twinkle + 1.0
			canvas.draw_line(at - Vector2(reach, 0.0), at + Vector2(reach, 0.0), Color(colour, fade * twinkle), 2.0, true)
			canvas.draw_line(at - Vector2(0.0, reach), at + Vector2(0.0, reach), Color(colour, fade * twinkle), 2.0, true)


## Over the cards: a band of light sweeping across each card once it has landed,
## the moment it becomes a thing you own rather than a thing in the air.
func _draw_overlay() -> void:
	if mode != Mode.CHEST:
		return
	var veil := _veil()
	for index in reward_cards.size():
		var shine := (age - _reward_landed(index) + 0.04) / 0.5
		if shine <= 0.0 or shine >= 1.0:
			continue
		var card := reward_cards[index]
		var drawn := Rect2(card.position + card.size * 0.5 * (Vector2.ONE - card.scale), card.size * card.scale)
		var edge := PackedVector2Array([drawn.position, Vector2(drawn.end.x, drawn.position.y), drawn.end, Vector2(drawn.position.x, drawn.end.y)])
		var x := drawn.position.x + lerpf(-0.5, 1.5, ease(shine, 0.7)) * drawn.size.x
		var lean := drawn.size.y * 0.35
		for band: Vector2 in [Vector2(0.0, 34.0), Vector2(46.0, 12.0)]:
			var left := x + band.x
			var strip := PackedVector2Array([Vector2(left + lean, drawn.position.y), Vector2(left + lean + band.y, drawn.position.y),
				Vector2(left - lean + band.y, drawn.end.y), Vector2(left - lean, drawn.end.y)])
			for piece in Geometry2D.intersect_polygons(strip, edge):
				overlay.draw_colored_polygon(piece, Color(1.0, 1.0, 1.0, 0.3 * sin(shine * PI) * veil))


## The face-down side every reward shows as it leaves the box.
static func _paint_card_back(back: Control, tint: Color) -> void:
	var area := Rect2(Vector2.ZERO, back.size)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("16213d")
	panel.border_color = tint.lightened(0.15)
	panel.set_border_width_all(5)
	panel.set_corner_radius_all(14)
	back.draw_style_box(panel, area)
	var inner := area.grow(-16.0)
	back.draw_rect(inner, Color("e8c98a", 0.55), false, 2.0)
	# A lattice, so the back is a pattern and not an empty panel.
	var step := 28.0
	var lines := PackedVector2Array()
	var y := inner.position.y
	while y < inner.end.y:
		var x := inner.position.x
		while x < inner.end.x:
			var centre := Vector2(x + step * 0.5, y + step * 0.5)
			if inner.has_point(centre):
				lines.append_array([centre + Vector2(0.0, -6.0), centre + Vector2(6.0, 0.0),
					centre + Vector2(6.0, 0.0), centre + Vector2(0.0, 6.0),
					centre + Vector2(0.0, 6.0), centre + Vector2(-6.0, 0.0),
					centre + Vector2(-6.0, 0.0), centre + Vector2(0.0, -6.0)])
			x += step
		y += step
	back.draw_multiline(lines, Color(tint, 0.25), 1.5)
	# The paw seal in the middle.
	var mid := area.get_center()
	back.draw_circle(mid, 46.0, Color("16213d"))
	back.draw_arc(mid, 46.0, 0.0, TAU, 40, Color("e8c98a", 0.9), 3.0, true)
	back.draw_circle(mid + Vector2(0.0, 8.0), 16.0, Color("e8c98a"))
	for toe: Vector2 in [Vector2(-17.0, -12.0), Vector2(-6.0, -21.0), Vector2(6.0, -21.0), Vector2(17.0, -12.0)]:
		back.draw_circle(mid + toe, 7.0, Color("e8c98a"))
