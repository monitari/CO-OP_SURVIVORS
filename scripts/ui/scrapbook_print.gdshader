shader_type canvas_item;

// Keeps the original transparent silhouette while making the clean mascot art
// feel screen-printed into the paper collage.
uniform float color_steps = 6.0;
uniform float grain_strength = 0.055;
uniform vec3 ink_tint = vec3(0.94, 0.96, 1.0);

float paper_noise(vec2 uv) {
	return fract(sin(dot(floor(uv * vec2(280.0, 190.0)), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 printed = floor(source.rgb * color_steps + 0.5) / color_steps;
	float grain = (paper_noise(UV) - 0.5) * grain_strength;
	printed = clamp(printed * ink_tint + grain, vec3(0.0), vec3(1.0));
	COLOR = vec4(printed, source.a);
}
