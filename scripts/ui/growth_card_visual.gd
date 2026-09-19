extends RefCounted

const Frame := preload("res://scripts/ui/neon_frame.gd")
const Palette := preload("res://scripts/ui/cat_theme.gd")

const CYAN := Color("35dbff")
const PARTNER := Color("ff9f43")
const CHEST := Color("ffd166")
const INK := Color("f1f7ff")
## The largest card the growth hand deals. A chest reward is the same card at the
## same size, scaled down as a whole when the box holds more than fits a row.
const CARD_SIZE := Vector2(224, 348)

## Colours a card's numbers are read in. The value the survivor has now and the
## value they will have after the card are both coloured, in different hues, so
## the eye finds the pair first and can tell which is which without reading the
## arrow between them.
const VALUE_NOW := Color("a9d8ff")
const VALUE_NEXT := Color("7dffc0")
const VALUE_ARROW := Color("5d7b96")
const TEXT_LABEL := Color("9fb6cc")
const TEXT_EFFECT := Color("d7e4f1")
const TEXT_NOTE := Color("7892ab")
const SYNERGY := Color("ffd27a")
## What kind of card it is, told apart by colour before a word is read: the chip
## at the top of the card wears it.
const KIND_COLORS := {
	"weapon": Color("35dbff"),
	"new_weapon": Color("7cf2a8"),
	"treasure": Color("ffd166"),
	"new_treasure": Color("ffb86b"),
	"tech": Color("c69cff"),
}
const TAG_COLORS := {
	"focus": Color("7dffc0"),
	"off": Color("ff9aa8"),
	"evolve": Color("ffd166"),
	"tech": Color("c69cff"),
	"max": Color("ffd166"),
	"shared": Color("7fd8ff"),
}
## Room kept under the body for the recommendation strip.
const BADGE_HEIGHT := 34.0
const BADGE_GAP := 8.0
## The smallest a card body is set before a phrase is broken over two lines.
const BODY_SMALLEST := 11


static func surface(tint: Color, selected := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("09182f")
	style.border_color = tint
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(tint, 0.3 if selected else 0.12)
	style.shadow_size = 12 if selected else 6
	return style


static func decorate(card: Control, tint: Color, selected := false, ears := false, paws := true, apply_surface := true) -> void:
	var style_key := "normal" if card is Label else "panel"
	if apply_surface:
		card.add_theme_stylebox_override(style_key, surface(tint, selected))
	card.set_meta("growth_card_visual", true)
	var frame := card.get_node_or_null("NeonTrim")
	if frame == null:
		frame = Frame.new()
		frame.name = "NeonTrim"
		card.add_child(frame)
	frame.accent = tint
	frame.active = selected
	frame.ears = ears
	frame.paws = paws
	frame.queue_redraw()


## An empty card carrying every child `paint` fills in. The level-up hand builds
## its cards in main.gd with the same node names; the chest showcase builds them
## here. Both are painted by `paint`, so a chest reward and a growth choice are
## one card rather than two cards kept in step by hand.
static func create_card() -> Label:
	var card := Label.new()
	card.size = CARD_SIZE
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_theme_color_override("font_color", Palette.INK)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["Icon", "FusionMark"]:
		var art := TextureRect.new()
		art.name = key
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
	for key in ["Scope", "Category", "CardTitle", "Recommendation"]:
		var text := Label.new()
		text.name = key
		text.clip_text = true
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_color_override("font_color", Palette.INK)
		if key == "CardTitle":
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(text)
	# The sectioned face (see _paint_sections): the line under the name that says
	# what the card applies to, a hairline, and the body with its coloured
	# numbers. Rich text because a body is several kinds of text in one box.
	for key in ["Subject", "Body"]:
		var rich := RichTextLabel.new()
		rich.name = key
		rich.bbcode_enabled = true
		rich.scroll_active = false
		rich.fit_content = false
		rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rich.visible = false
		card.add_child(rich)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.visible = false
	card.add_child(rule)
	return card


## Lays out and fills one card. `model` is what the card says, independent of
## where it came from: category, title, icon, fusion (texture or null), tech
## (compact layout), advice ("recommended" / "discouraged" / "neutral"), reason,
## and either `sections` (main._card_sections — a growth option) or a flat
## `body` (a resonance, a chest's fish).
static func paint(card: Label, model: Dictionary, tint: Color, selected: bool, width: float, height: float) -> void:
	var sectioned := model.has("sections") and card.has_node("Body")
	if sectioned:
		_paint_sections(card, model, tint, selected, width, height)
	else:
		_paint_flat(card, model, tint, selected, width, height)
	card.get_node("Scope").visible = false
	var fusion: TextureRect = card.get_node("FusionMark")
	fusion.texture = model.get("fusion") as Texture2D
	fusion.visible = fusion.texture != null
	fusion.position = Vector2(width - 45, 44 if sectioned else 52)
	fusion.size = Vector2(32, 32)
	# The seal is an icon in a corner, and an icon on its own says "these two go
	# together" without saying which two or what happens. It used to carry the
	# sentence; that was lost when the chest and growth cards were collapsed onto
	# this one component, and a mark nobody can interrogate is just decoration.
	#
	# It marks a synergy, not a recipe. While treasures gated enhancement the
	# sentence said 합치면 무기가 강화됩니다, which was an instruction; nothing
	# gates an enhancement now, so it describes a good fit instead.
	var partner := String(model.get("fusion_name", ""))
	fusion.tooltip_text = "%s와(과) 시너지가 좋습니다" % partner if not partner.is_empty() else ""
	fusion.mouse_filter = Control.MOUSE_FILTER_PASS if fusion.visible else Control.MOUSE_FILTER_IGNORE
	var badge: Label = card.get_node("Recommendation")
	var advice := String(model.get("advice", "neutral"))
	# A card can carry its own badge line in place of a recommendation. The
	# resonance vote uses it for the two survivors' cursors: that strip is where
	# a card says what to do about itself, and on a screen where the two players
	# are negotiating, who is pointing at what *is* that sentence — while a 👍 or
	# a 👎 there would mean nothing at all.
	# Keyed on presence, not on content: a card that carries its own badge and
	# has nothing to say right now wants an empty strip, not the recommendation
	# line it was replacing.
	var badge_color: Color = model.get("badge_color", recommendation_color(advice))
	badge.text = String(model["badge"]) if model.has("badge") \
		else recommendation_text(advice, String(model.get("reason", "무난한 성장")))
	badge.visible = not badge.text.is_empty()
	badge.position = Vector2(10, height - 10 - BADGE_HEIGHT)
	badge.size = Vector2(width - 20, BADGE_HEIGHT)
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# One line where it fits at all, like the body above it: a reason set a size
	# smaller reads better than the same reason broken after its first word.
	badge.add_theme_font_size_override("font_size", _fitting_size(badge.get_theme_font("font"),
		[[[badge.text, 0, INK]]], badge.size.x - 16.0, 13, 11))
	# The strip takes the colour of what it says: green for a card worth taking,
	# red for one to pass on, and a quiet slate for everything in between — a
	# neutral card no longer wears the same border as a starred one.
	var strip := surface(tint.darkened(0.3))
	strip.set_corner_radius_all(9)
	strip.shadow_size = 0
	if advice == "neutral" and not model.has("badge"):
		strip.bg_color = Color("0d1d33")
		strip.border_color = Color("2c4561")
	else:
		strip.bg_color = Color(badge_color.darkened(0.78), 0.92)
		strip.border_color = Color(badge_color, 0.55)
	badge.add_theme_stylebox_override("normal", strip)
	badge.add_theme_color_override("font_color", badge_color)
	decorate(card, tint, selected, false, true, false)


## The card as one paragraph of body text — a resonance's three lines of who
## supplies what, a chest's fish. The layout every card had before growth cards
## were split into sections.
static func _paint_flat(card: Label, model: Dictionary, tint: Color, selected: bool, width: float, height: float) -> void:
	# `compact` is the route card's layout — smaller art, title higher, more room
	# for words — asked for by name. A resonance card wants it for the same
	# reason a route card does: what it has to say is three lines of who supplies
	# what, not a number, and the tall art a growth card leads with would push
	# that off the bottom.
	var tech := bool(model.get("tech", false)) or bool(model.get("compact", false))
	var style := surface(tint, selected)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 178 if tech else (214 if height > 330 else 190)
	# Cards that put something of their own below the body — the resonance vote's
	# two confirm buttons — reserve the room here rather than letting the text
	# run under it.
	style.content_margin_bottom = float(model.get("body_bottom", 56))
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_font_size_override("font_size", 13 if tech else (16 if width > 190 else 14))
	card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# Not clip_text: a clipping Label clips its whole canvas item to the
	# screen-space bounds of its rectangle, which cut the selection glow and the
	# drop shadow off every card — straight across, at the height of the highest
	# corner of a tilted one. Trimming the overflowing lines keeps the body inside
	# the card without clipping anything drawn around it.
	card.clip_text = false
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.text = String(model.get("body", ""))
	for key in ["Subject", "Body", "Rule"]:
		var part := card.get_node_or_null(key) as CanvasItem
		if part != null:
			part.visible = false
	_paint_chip(card.get_node("Category"), String(model.get("category", "")), tint, width, 13 if width > 190 else 11)
	var icon: TextureRect = card.get_node("Icon")
	icon.texture = model.get("icon") as Texture2D
	var art := 80.0 if tech else (106.0 if height > 330 else 86.0)
	icon.position = Vector2((width - art) * 0.5, 45)
	icon.size = Vector2.ONE * art
	var title: Label = card.get_node("CardTitle")
	title.text = String(model.get("title", ""))
	title.position = Vector2(13, 123 if tech else (155 if height > 330 else 132))
	title.size = Vector2(width - 26, 52)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21 if width > 190 else 17)
	title.add_theme_color_override("font_color", Palette.INK)


## A growth card in sections, top to bottom:
##
##   [category chip]      what kind of card, by colour
##   icon
##   NAME                 the upgrade itself
##   subject · Lv a → b   what it applies to, and the level it takes it to
##   ───────────
##   stat rows            now → after, both coloured
##   effect               one line in words
##   tag chips            테크 특화 · 이 카드로 진화 · 팀 공유 …
##   ✦ synergy            advice about the build, in gold
##   note                 small print
##   [recommendation]
##
## The name and the weapon used to share one two-line title ("마력 증폭\n화염
## 지팡이") in one size and colour, and everything else was one paragraph. Each
## now has its own place, size and colour, so a card is read in the order it is
## decided on: what kind, what, on which weapon, how much.
static func _paint_sections(card: Label, model: Dictionary, tint: Color, selected: bool, width: float, height: float) -> void:
	var sections: Dictionary = model["sections"]
	var tech := bool(model.get("tech", false))
	var wide := width > 190.0
	var tall := height > 330.0
	var style := surface(tint, selected)
	card.add_theme_stylebox_override("normal", style)
	card.clip_text = false
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.text = ""

	var kind_color: Color = KIND_COLORS.get(String(model.get("kind", "weapon")), tint)
	_paint_chip(card.get_node("Category"), String(model.get("category", "")), kind_color, width, 12 if wide else 11)

	var icon: TextureRect = card.get_node("Icon")
	icon.texture = model.get("icon") as Texture2D
	var art := (64.0 if tech else 80.0) if tall else (54.0 if tech else 62.0)
	icon.position = Vector2((width - art) * 0.5, 40)
	icon.size = Vector2.ONE * art

	var font := card.get_theme_font("font")
	var title: Label = card.get_node("CardTitle")
	title.text = String(sections.get("name", model.get("title", "")))
	var title_y := 40.0 + art + 4.0
	title.position = Vector2(12, title_y)
	title.size = Vector2(width - 24, 28)
	# One line, always. The name is a few words; the weapon it applies to moved
	# to its own line underneath, which is what used to make titles wrap. A name
	# too long for the card is set smaller rather than cut off.
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _fitting_size(font,
		[[[title.text, 0, INK]]], title.size.x - 4.0, 20 if wide else 17, 13))
	title.add_theme_color_override("font_color", Palette.INK)

	var subject: RichTextLabel = card.get_node("Subject")
	subject.visible = true
	subject.position = Vector2(10, title_y + 28)
	subject.size = Vector2(width - 20, 20)
	subject.autowrap_mode = TextServer.AUTOWRAP_OFF
	var subject_line := _subject_line(sections, tint)
	var subject_size := _fitting_size(font, [subject_line], subject.size.x - 4.0, 13 if wide else 12, 10)
	subject.add_theme_font_size_override("normal_font_size", subject_size)
	subject.text = "[center]%s[/center]" % _render_line(subject_line, subject_size)

	var rule: ColorRect = card.get_node("Rule")
	rule.visible = true
	rule.color = Color(tint, 0.28)
	rule.position = Vector2(22, title_y + 52)
	rule.size = Vector2(width - 44, 1)

	var body: RichTextLabel = card.get_node("Body")
	body.visible = true
	var body_top := title_y + 60.0
	body.position = Vector2(15, body_top)
	body.size = Vector2(width - 30, height - BADGE_HEIGHT - 10.0 - BADGE_GAP - body_top)
	# Every line of the body is one phrase (a stat row, the effect, the tags) and
	# the body reads as a block only while each phrase stays on its own line. So
	# it is set at the largest size at which none of them wraps, and a phrase that
	# still would at the smallest size is broken once, at a word, into two even
	# halves rather than left to spill one word onto a line of its own.
	var largest := (14 if wide else 13) if tall else 12
	var lines := _body_lines(sections)
	var room := body.size.x - 2.0
	var body_font := _fitting_size(font, lines, room, largest, BODY_SMALLEST)
	if _widest(font, lines, body_font) > room:
		lines = _balanced(font, lines, room, body_font)
	body.add_theme_font_size_override("normal_font_size", body_font)
	body.add_theme_constant_override("line_separation", 4)
	# A two-line body under a tall card used to sit at the top of a mostly empty
	# box; centred, the sections read as one block between the rule and the badge.
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var rendered: Array[String] = []
	for line: Array in lines:
		rendered.append(_render_line(line, body_font))
	body.text = "\n".join(rendered)


## The kind-of-card chip at the top of every card, growth or resonance alike.
static func _paint_chip(category: Label, text: String, color: Color, width: float, font_size: int) -> void:
	category.text = text
	category.add_theme_font_size_override("font_size", font_size)
	category.add_theme_color_override("font_color", color.lightened(0.25))
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chip_width := category.get_theme_font("font").get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 26.0
	chip_width = minf(width - 70.0, chip_width)
	category.size = Vector2(chip_width, 21)
	category.position = Vector2((width - chip_width) * 0.5, 12)
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(color.darkened(0.72), 0.95)
	chip.border_color = Color(color, 0.6)
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(10)
	category.add_theme_stylebox_override("normal", chip)


## A line is an array of segments, [text, size step, colour, chip]: the text,
## how many points it is set above or below the body, its colour, and for a tag
## the chip colour behind it. Kept as data rather than as BBCode so that a line
## can be measured before it is set.
static func _subject_line(sections: Dictionary, tint: Color) -> Array:
	var line: Array = []
	var subject := String(sections.get("subject", ""))
	if not subject.is_empty():
		line.append([subject, 0, tint.lightened(0.45)])
	var level: Array = sections.get("level", [])
	if level.size() == 2:
		if not line.is_empty():
			line.append(["  ·  ", 0, VALUE_ARROW])
		if int(level[0]) <= 0:
			line.append(["신규", 0, VALUE_NEXT])
		elif int(level[0]) == int(level[1]):
			line.append(["Lv.%d" % int(level[1]), 0, VALUE_NOW])
		else:
			line.append_array(_change("Lv.%d" % int(level[0]), "%d" % int(level[1]), 0))
	return line


static func _body_lines(sections: Dictionary) -> Array:
	var lines: Array = []
	for row: Dictionary in sections.get("stats", []):
		var line: Array = [[String(row.get("label", "")) + "  ", 0, TEXT_LABEL]]
		line.append_array(_change(String(row.get("from", "")), String(row.get("to", "")), 2))
		lines.append(line)
		# The rest of the sentence (", 구조 속도 증가") on a line of its own, so the
		# numbers above it are never what gets pushed onto a new line.
		var post := String(row.get("post", "")).trim_prefix(",").trim_prefix("·").strip_edges()
		if not post.is_empty():
			lines.append([[post, -2, TEXT_LABEL]])
	var effect := String(sections.get("effect", ""))
	if not effect.is_empty():
		lines.append([[effect, 0, TEXT_EFFECT]])
	var tags: Array = sections.get("tags", [])
	if not tags.is_empty():
		var line: Array = []
		for tag: Dictionary in tags:
			if not line.is_empty():
				line.append(["  ", -1, TEXT_EFFECT])
			var color: Color = TAG_COLORS.get(String(tag.get("kind", "")), TEXT_EFFECT)
			line.append([" %s " % String(tag["text"]), -1, color, Color(color.darkened(0.7), 0.95)])
		lines.append(line)
	var synergy := String(sections.get("synergy", ""))
	if not synergy.is_empty():
		lines.append([["✦ " + synergy, 0, SYNERGY]])
	# The small print one fact to a line: "where the routes go" and "which slot
	# this takes" joined together were the longest line any card had.
	for part in String(sections.get("note", "")).split("  ·  ", false):
		lines.append([[part, -2, TEXT_NOTE]])
	return lines


## "now → after", both coloured. A value that is only gained (a new treasure, a
## bonus that starts from nothing) is the after half alone.
static func _change(now: String, after: String, after_step := 0) -> Array:
	var next: Array = [after, after_step, VALUE_NEXT]
	if now.is_empty():
		return [next]
	return [[now, 0, VALUE_NOW], [" → ", 0, VALUE_ARROW], next]


static func _render_line(line: Array, base: int) -> String:
	var out := ""
	for segment: Array in line:
		var text := "[color=#%s]%s[/color]" % [(segment[2] as Color).to_html(false), _escape(String(segment[0]))]
		if segment.size() > 3:
			text = "[bgcolor=#%s]%s[/bgcolor]" % [(segment[3] as Color).to_html(true), text]
		if int(segment[1]) != 0:
			text = "[font_size=%d]%s[/font_size]" % [base + int(segment[1]), text]
		out += text
	return out


static func _line_width(font: Font, line: Array, base: int) -> float:
	var total := 0.0
	for segment: Array in line:
		total += font.get_string_size(String(segment[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, base + int(segment[1])).x
	return total


static func _widest(font: Font, lines: Array, base: int) -> float:
	var widest := 0.0
	for line: Array in lines:
		widest = maxf(widest, _line_width(font, line, base))
	return widest


## The largest size from `largest` down to `smallest` at which every line fits
## in `room`; `smallest` when none does.
static func _fitting_size(font: Font, lines: Array, room: float, largest: int, smallest: int) -> int:
	for size in range(largest, smallest - 1, -1):
		if _widest(font, lines, size) <= room:
			return size
	return smallest


## Breaks each one-segment line that is still too wide into two lines of about
## the same width, at the space nearest its middle: two even lines instead of a
## long one with a stray word under it.
static func _balanced(font: Font, lines: Array, room: float, base: int) -> Array:
	var result: Array = []
	for line: Array in lines:
		if _line_width(font, line, base) <= room:
			result.append(line)
			continue
		if line.size() > 1:
			# A stat row whose label is a whole clause ("레벨업마다 둘 다 최대
			# 체력의"): the label on one line and the numbers on the next, which
			# keeps the now → after pair together.
			var label: Array = (line[0] as Array).duplicate()
			label[0] = String(label[0]).strip_edges()
			result.append([label])
			result.append(line.slice(1))
			continue
		var segment: Array = line[0]
		var text := String(segment[0])
		var middle := text.length() / 2
		var best := -1
		# A clause break (" · ") is where the sentence already divides itself, so
		# it wins over any plain space.
		for mark in [" · ", " "]:
			for index in text.length():
				if text.substr(index, mark.length()) == mark and (best < 0 or absi(index - middle) < absi(best - middle)):
					best = index
			if best > 0:
				break
		if best <= 0:
			result.append(line)
			continue
		var first := segment.duplicate()
		first[0] = text.substr(0, best).strip_edges().trim_suffix("·").strip_edges()
		var second := segment.duplicate()
		second[0] = text.substr(best + 1).strip_edges().trim_prefix("·").strip_edges()
		result.append([first])
		result.append([second])
	return result


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func recommendation_text(advice: String, reason: String) -> String:
	match advice:
		"recommended":
			return "👍 " + reason
		"discouraged":
			return "👎 " + reason
		_:
			return reason


static func recommendation_color(advice: String) -> Color:
	match advice:
		"discouraged":
			return Color("ffafbd")
		"recommended":
			return Color("71ffcd")
		_:
			return Color("a9bfd4")
