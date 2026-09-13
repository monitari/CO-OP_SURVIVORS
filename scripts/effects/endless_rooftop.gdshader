shader_type canvas_item;
render_mode unshaded;

// One projection for the entire battlefield, including telegraphs and loot.
// The overscan texture supplies the corners instead of stretching edge pixels.
//
// The projection is a resample, and a resample is only as good as the filter
// under it. Hardware bilinear alone is wrong in both directions here: the top
// of the screen reads about one and a half source rows per output row, which
// aliases into a crawling shimmer on every thin bright line the game draws,
// while the bottom used to read less than one and blurred instead. The view
// script fixes the "less than one" half by sizing the source buffer so the
// sparsest point on screen still has a full texel to give; this shader fixes
// the other half by measuring its own footprint and filtering across it.
uniform vec2 overscan = vec2(1.14, 1.33);
uniform float tilt = 0.86;
uniform float perspective = 0.18;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float row = 1.0 + perspective * p.y / tilt;
	vec2 ground = vec2(p.x / row, p.y / (tilt + perspective * p.y));
	vec2 source = vec2(0.5) + ground / overscan;

	// Screen-space derivatives of the mapping, which is exactly the source
	// footprint of this output pixel — including the sideways shear the taper
	// puts into every row but the middle one. Taken before anything branches,
	// because a derivative asked for inside divergent control flow is not
	// defined.
	vec2 along_x = dFdx(source);
	vec2 along_y = dFdy(source);
	float density = max(length(along_x / TEXTURE_PIXEL_SIZE),
		length(along_y / TEXTURE_PIXEL_SIZE));

	// How far the taps open up. Zero where the footprint is a single texel —
	// there is nothing to average and spreading would only soften a row that
	// is already as sharp as the source can be — and full where the footprint
	// has grown to two, which is the worst the taper reaches at the horizon.
	// A SubViewport's texture carries no mip chain, so there is no cheaper
	// level to fall back on and this is the filter.
	float spread = clamp(density - 1.0, 0.0, 1.0);
	vec2 a = (along_x * 0.375 + along_y * 0.125) * spread;
	vec2 b = (along_x * 0.125 - along_y * 0.375) * spread;

	// A rotated-grid four-tap rather than a square one: four samples on a
	// tilted lattice cover the near-horizontal and near-vertical edges this
	// game is built out of far better than four samples in a box would.
	COLOR = 0.25 * (
		texture(TEXTURE, source + a) + texture(TEXTURE, source - a) +
		texture(TEXTURE, source + b) + texture(TEXTURE, source - b));
}
