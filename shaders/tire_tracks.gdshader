shader_type spatial;
// Tyre mark segments (TireTracks MultiMesh). INSTANCE_CUSTOM.x holds the time
// each segment was laid; it fades out over the end of its lifetime.
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D tread : source_color, filter_linear_mipmap;
uniform float now = 0.0;
uniform float lifetime = 20.0;
uniform float fade_time = 6.0;

varying float age;

void vertex() {
	age = now - INSTANCE_CUSTOM.x;
	if (age > lifetime) {
		VERTEX = vec3(0.0); // collapse expired segments: no fill cost
	}
}

void fragment() {
	vec4 print = texture(tread, UV);
	float life = 1.0 - smoothstep(lifetime - fade_time, lifetime, age);
	ALBEDO = print.rgb;
	ALPHA = print.a * life;
	ROUGHNESS = 1.0;
}
