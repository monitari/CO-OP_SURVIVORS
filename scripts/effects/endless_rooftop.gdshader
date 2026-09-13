shader_type canvas_item;
render_mode unshaded;

// One projection for the entire battlefield, including telegraphs and loot.
// The overscan texture supplies the corners instead of stretching edge pixels.
uniform float overscan = 1.5;
uniform float tilt = 0.86;
uniform float perspective = 0.18;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float scale_at_row = 1.0 + perspective * p.y / tilt;
	vec2 ground = vec2(p.x / scale_at_row, p.y / (tilt + perspective * p.y));
	vec2 source_uv = vec2(0.5) + ground / overscan;
	COLOR = texture(TEXTURE, source_uv);
}
