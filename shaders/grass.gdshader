shader_type spatial;
// Lawn around the court: two texture scales blended to hide tiling, plus a
// low-frequency colour variation (patches of drier / greener grass).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear, repeat_enable;
uniform float scale = 0.42;
uniform vec4 tint : source_color = vec4(0.82, 0.92, 0.72, 1.0);
uniform vec4 dry_tint : source_color = vec4(0.95, 0.88, 0.62, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv_a = p * scale;
	vec2 uv_b = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * scale * 0.31;
	float blend = texture(macro_noise, p * 0.013).r;
	vec3 a = texture(albedo_tex, uv_a).rgb;
	vec3 b = texture(albedo_tex, uv_b).rgb;
	vec3 grass = mix(a, b, smoothstep(0.35, 0.65, blend));
	float dry = smoothstep(0.55, 0.85, texture(macro_noise, p * 0.006 + 0.37).r);
	ALBEDO = grass * mix(tint.rgb, dry_tint.rgb, dry * 0.6);
	ROUGHNESS = texture(roughness_tex, uv_a).g * 0.2 + 0.8;
	NORMAL_MAP = mix(texture(normal_tex, uv_a).rgb, texture(normal_tex, uv_b).rgb, 0.5);
	NORMAL_MAP_DEPTH = 1.0;
}
