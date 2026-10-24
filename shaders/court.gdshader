shader_type spatial;
// Outdoor acrylic court. FIBA markings are drawn analytically (signed distances),
// so they stay sharp at any distance and match the gameplay constants exactly.

uniform vec4 runoff_color : source_color = vec4(0.20, 0.39, 0.27, 1.0);
uniform vec4 court_color : source_color = vec4(0.13, 0.30, 0.50, 1.0);
uniform vec4 key_color : source_color = vec4(0.55, 0.20, 0.17, 1.0);
uniform vec4 line_color : source_color = vec4(0.93, 0.93, 0.90, 1.0);
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_roughness : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform sampler2D wear_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.75;

uniform vec2 court_half = vec2(7.5, 14.0);
uniform float line_width = 0.05;
uniform float rim_from_endline = 1.575;
uniform float three_radius = 6.75;
uniform float three_side = 0.90;
uniform float key_half_width = 2.45;
uniform float free_throw = 5.80;
uniform float circle_radius = 1.80;
uniform float no_charge = 1.25;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float box_sd(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Distance to a line drawn with its outer edge on the given shape boundary.
float stroke(float sd_outer_edge) {
	return abs(sd_outer_edge + line_width * 0.5);
}

float end_markings(vec2 p, float side, out float in_key) {
	// Work in a frame where the endline is at z = court_half.y and the court is toward -z.
	vec2 q = vec2(p.x, p.y * side);
	float endline = court_half.y;
	vec2 rim = vec2(0.0, endline - rim_from_endline);
	float d = 1e3;

	// Restricted area (key) and free-throw line.
	float ft = endline - free_throw;
	vec2 key_center = vec2(0.0, (endline + ft) * 0.5);
	float key_box = box_sd(q - key_center, vec2(key_half_width, (endline - ft) * 0.5));
	in_key = step(key_box, 0.0);
	d = min(d, stroke(key_box));

	// Free-throw semicircle (court side).
	float ft_circle = abs(length(q - vec2(0.0, ft)) - circle_radius + line_width * 0.5);
	d = min(d, q.y < ft ? ft_circle : 1e3);

	// Three-point line: straight parts then the arc.
	float corner_x = court_half.x - three_side - line_width * 0.5;
	float r = three_radius - line_width * 0.5;
	float corner_z = rim.y - sqrt(r * r - corner_x * corner_x);
	float arc = abs(length(q - rim) - r);
	float straight = abs(abs(q.x) - corner_x);
	d = min(d, q.y > corner_z ? (q.y < endline ? straight : 1e3) : arc);

	// No-charge semicircle.
	float nc = abs(length(q - rim) - no_charge - line_width * 0.5);
	d = min(d, (q.y < rim.y && abs(q.x) < no_charge + line_width) ? nc : 1e3);
	return d;
}

void fragment() {
	vec2 p = world_pos.xz;
	float court_box = box_sd(p, court_half);
	float d = abs(court_box - line_width * 0.5);                // boundary (outside the court)
	d = min(d, abs(p.y));                                       // centre line
	d = min(d, abs(length(p) - circle_radius + line_width * 0.5)); // centre circle
	float key_a;
	float key_b;
	d = min(d, end_markings(p, 1.0, key_a));
	d = min(d, end_markings(p, -1.0, key_b));

	// Pixel footprint from the position, not from fwidth(d): d folds at the line centre,
	// so its derivative vanishes exactly where it is needed. Lines narrower than a pixel
	// would break up at grazing angles - keep them ~1 px wide and dim them instead.
	vec2 footprint = fwidth(p);
	float px = max(footprint.x, footprint.y) * 0.7 + 0.0005;
	float half_width = line_width * 0.5;
	float w = max(half_width, px * 0.6);
	float line = (1.0 - smoothstep(w - px * 0.5, w + px * 0.5, d)) * clamp(half_width / w, 0.4, 1.0);
	line *= step(court_box, line_width);

	vec3 base = court_box > 0.0 ? runoff_color.rgb : court_color.rgb;
	base = mix(base, key_color.rgb, max(key_a, key_b) * step(court_box, 0.0));

	vec2 uv = p * detail_scale;
	float grain = dot(texture(detail_albedo, uv).rgb, vec3(0.333));
	float wear = dot(texture(wear_albedo, p * 0.045).rgb, vec3(0.333));
	vec3 surface = base * (0.78 + grain * 0.55) * (0.88 + wear * 0.3);
	ALBEDO = mix(surface, line_color.rgb * (0.92 + grain * 0.15), line);
	ROUGHNESS = mix(texture(detail_roughness, uv).g * 0.35 + 0.55, 0.5, line);
	NORMAL_MAP = texture(detail_normal, uv).rgb;
	NORMAL_MAP_DEPTH = mix(0.6, 0.25, line);
}
