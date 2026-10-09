shader_type spatial;
// Arena dirt: PBR texture set mapped in world space on the XZ plane, with two
// samples at different scale/rotation blended by a low-frequency mask so the
// tiling doesn't show, plus large-scale brightness variation (packed vs loose
// dirt). Needs mesh normals + tangents aligned with world X/Z (ArenaTerrain).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile_size = 4.0; // metres per texture repeat
uniform float macro_size = 70.0; // metres per macro variation repeat
uniform float macro_strength = 0.35;
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_a = world_pos.xz / tile_size;
	vec2 uv_b = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * world_pos.xz / (tile_size * 2.3);
	float macro = texture(macro_tex, world_pos.xz / macro_size).r;
	float mask = smoothstep(0.35, 0.65, texture(macro_tex, world_pos.xz / (macro_size * 0.31)).r);

	vec3 albedo = mix(texture(albedo_tex, uv_a).rgb, texture(albedo_tex, uv_b).rgb, mask);
	ALBEDO = albedo * tint * mix(1.0 - macro_strength, 1.0 + macro_strength * 0.4, macro);

	vec3 orm = mix(texture(orm_tex, uv_a).rgb, texture(orm_tex, uv_b).rgb, mask);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;

	NORMAL_MAP = mix(texture(normal_tex, uv_a).rgb, texture(normal_tex, uv_b).rgb, mask);
	NORMAL_MAP_DEPTH = normal_strength;
}
