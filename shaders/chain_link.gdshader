shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Procedural chain-link (diamond) mesh. The quad's UV is expected in metres:
// x along the fence, y up. Up close the wires are cut out exactly; once a cell
// gets only a few pixels wide it fades to its average coverage (no moire).

uniform vec4 wire_color : source_color = vec4(0.17, 0.23, 0.19, 1.0);
uniform float cell = 0.06;
uniform float wire = 0.002;

void fragment() {
	vec2 p = UV / cell;
	vec2 d = vec2(p.x + p.y, p.x - p.y);
	float half_cell = 0.5 * cell * 0.7071;
	vec2 f = abs(fract(d) - 0.5) * cell * 0.7071;
	float dist = min(half_cell - f.x, half_cell - f.y);
	float aa = fwidth(dist);
	float pattern = 1.0 - smoothstep(wire - aa, wire + aa, dist);
	float coverage = 1.0 - pow(1.0 - wire / half_cell, 2.0);
	float cells_per_pixel = length(fwidth(UV)) / cell;
	ALPHA = mix(pattern, coverage * 0.8, smoothstep(0.2, 0.45, cells_per_pixel));
	ALBEDO = wire_color.rgb;
	METALLIC = 0.2;
	ROUGHNESS = 0.6;
}
