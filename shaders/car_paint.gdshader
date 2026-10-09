shader_type spatial;
// Car livery on the chassis box, drawn from local position/normal (the
// chassis has no UVs). Mirror-symmetric top/bottom like the rest of the car:
// twin racing stripes over roof and floor (continuing over nose and tail),
// a side band on the axle line with a roundel, and worn paint at the edges.

uniform vec3 base_color : source_color = vec3(0.75, 0.08, 0.06);
uniform vec3 stripe_color : source_color = vec3(0.92, 0.92, 0.9);
uniform vec3 accent_color : source_color = vec3(0.05, 0.05, 0.06);
uniform float stripe_width = 0.16;
uniform float stripe_gap = 0.1;
uniform float band_height = 0.07;
uniform vec2 roundel_centre = vec2(0.35, 0.0); // z, y on the side faces
uniform float roundel_radius = 0.24;
uniform float wear_amount = 0.6;
uniform sampler2D wear_noise : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(local_normal);
	bool roof_or_floor = n.y > 0.7;
	bool nose_or_tail = n.z > 0.7;
	bool side = n.x > 0.7;

	vec3 colour = base_color;
	float ax = abs(local_pos.x);
	float stripe = step(stripe_gap * 0.5, ax) * step(ax, stripe_gap * 0.5 + stripe_width);
	if (roof_or_floor || nose_or_tail) {
		colour = mix(colour, stripe_color, stripe);
	}
	if (side) {
		float band = 1.0 - step(band_height, abs(local_pos.y));
		colour = mix(colour, accent_color, band);
		float d = length(vec2(local_pos.z, local_pos.y) - roundel_centre);
		colour = mix(colour, stripe_color, 1.0 - step(roundel_radius, d));
		colour = mix(colour, accent_color, 1.0 - step(roundel_radius * 0.72, d));
	}

	// Worn paint: noise patches, much more likely on bevelled edges (whose
	// normals point diagonally) — bare metal shows through.
	float edge = 1.0 - max(n.x, max(n.y, n.z));
	vec2 wear_uv = local_pos.xz * 0.9 + local_pos.y * 0.7;
	float noise = texture(wear_noise, wear_uv).r;
	float wear = smoothstep(0.62, 0.8, noise + edge * 1.4) * wear_amount;
	vec3 bare_metal = vec3(0.42, 0.42, 0.44);

	ALBEDO = mix(colour, bare_metal, wear);
	METALLIC = mix(0.25, 0.95, wear);
	ROUGHNESS = mix(0.35, 0.55, wear);
	CLEARCOAT = 1.0 - wear;
	CLEARCOAT_ROUGHNESS = 0.15;
}
