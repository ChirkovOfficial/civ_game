shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://view/map/shaders/fog.gdshaderinc"

varying flat float fog_state;
varying vec3 world_pos;
varying flat vec2 biome;
uniform sampler2D biome_atlas : source_color, filter_linear, repeat_disable;

void vertex() {
	biome = UV;
	fog_state = fog_lookup(UV2);
	// Неразведанные клетки — ровная «пелена» без рельефа, чтобы не выдавать карту.
	if (fog_state < 0.25) {
		VERTEX.y = 0.0;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = to_render_space(COLOR.rgb, OUTPUT_IS_SRGB);
	if (fog_state < 0.25) {
		float n = sin(world_pos.x * 0.9) * sin(world_pos.z * 1.1) * 0.5 + 0.5;
		c = to_render_space(unexplored_color * (0.85 + n * 0.3), OUTPUT_IS_SRGB);
		NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	} else {
		if (biome.y < 0.5) {
			vec2 cell = vec2(mod(biome.x, 4.0), floor(biome.x / 4.0));
			vec2 local_uv = clamp(fract(world_pos.xz / 3.5), vec2(0.005), vec2(0.995));
			vec3 ground = texture(biome_atlas, (cell + local_uv) / vec2(4.0, 2.0)).rgb;
			float edge_blend = mix(0.7, 1.0, smoothstep(0.0, 0.32, COLOR.a));
			c = mix(c, ground, 0.62 * edge_blend);
		}
		c = apply_fog_tint(c, fog_state);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
