extends RefCounted

## Writes to a Control only when the value actually changes.
##
## The HUD is refreshed every physics tick, and most of what it writes is the
## same as last tick. For a Label's text that is free — Godot compares and
## returns. For three other writes it is not, and together they were the single
## largest cost in a late-run frame:
##
##   add_theme_color_override   always notifies THEME_CHANGED. A Label takes
##                              that as "my font may have changed", throws its
##                              shaped text away and shapes it again — Korean
##                              text through HarfBuzz, sixteen-plus labels, sixty
##                              times a second, for a colour that had not moved.
##   StyleBoxFlat colours       always emit `changed`, and every Control drawing
##                              that stylebox redraws.
##   tooltip_text               always rebuilt.
##
## Measured on the late-run benchmark (tests/perf_bench_capture.gd): skipping the
## HUD refresh outright took the frame from 152ms to 28ms, most of it from the
## engine work these writes queue after the scripts have finished — which is why
## no script-level timer ever showed it.

static func font_color(control: Control, color: Color, name: StringName = &"font_color") -> void:
	if control.has_theme_color_override(name) and control.get_theme_color(name) == color:
		return
	control.add_theme_color_override(name, color)


static func bg_color(style: StyleBoxFlat, color: Color) -> void:
	if style != null and style.bg_color != color:
		style.bg_color = color


static func border_color(style: StyleBoxFlat, color: Color) -> void:
	if style != null and style.border_color != color:
		style.border_color = color


static func tooltip(control: Control, text: String) -> void:
	if control.tooltip_text != text:
		control.tooltip_text = text


static func texture(rect: TextureRect, value: Texture2D) -> void:
	if rect.texture != value:
		rect.texture = value
