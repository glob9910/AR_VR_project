shader_type spatial;
render_mode cull_disabled;
// Hoop net. UV.y = 0 at the ring, 1 at the bottom. Two effects:
//  * swish - damped wave after a made shot,
//  * the ball pushes the cords outward while it passes through.

uniform vec4 cord_color : source_color = vec4(0.94, 0.94, 0.90, 1.0);
uniform float swish = 0.0;
uniform float phase = 0.0;
uniform vec3 ball_local = vec3(0.0, 10.0, 0.0);
uniform float ball_radius = 0.12;

void vertex() {
	float t = UV.y;
	vec3 p = VERTEX;
	float r = length(p.xz);
	vec2 radial = r > 0.0001 ? p.xz / r : vec2(0.0);

	float wave = swish * sin(phase * 21.0 - t * 4.0);
	p.y -= swish * t * 0.07 + wave * t * 0.03;
	p.xz += radial * wave * t * 0.025;

	float dy = p.y - ball_local.y;
	float section = sqrt(max(ball_radius * ball_radius - dy * dy, 0.0)) + 0.012;
	vec2 away = p.xz - ball_local.xz;
	float dist = length(away);
	if (section > 0.012 && dist < section && t > 0.02) {
		vec2 dir = dist > 0.0001 ? away / dist : radial;
		p.xz = ball_local.xz + dir * mix(dist, section, smoothstep(0.0, 0.25, t));
	}
	VERTEX = p;
}

void fragment() {
	ALBEDO = cord_color.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25);
}
