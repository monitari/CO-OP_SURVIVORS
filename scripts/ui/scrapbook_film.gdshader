shader_type canvas_item;

// Procedural film edge for the title scrapbook. TIME moves the perforations
// through UV space, so the strip can loop forever without a wide texture.
uniform vec4 ink : source_color = vec4(0.035, 0.039, 0.055, 0.94);
uniform vec4 paper : source_color = vec4(0.91, 0.84, 0.70, 0.92);
uniform float cells = 18.0;
uniform float speed = 0.42;

void fragment() {
	vec2 uv = UV;
	float cell = fract(uv.x * cells + TIME * speed);
	float hole_x = step(0.17, cell) * step(cell, 0.57);
	float upper_hole = step(0.10, uv.y) * step(uv.y, 0.36);
	float lower_hole = step(0.64, uv.y) * step(uv.y, 0.90);
	float hole = hole_x * min(1.0, upper_hole + lower_hole);
	COLOR = mix(ink, paper, hole);
}
