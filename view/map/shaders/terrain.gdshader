shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://view/map/shaders/fog.gdshaderinc"

varying flat float fog_state;
varying vec3 world_pos;

void vertex() {
	fog_state = fog_lookup(UV2);
	// Неразведанные клетки — ровная «пелена» без рельефа, чтобы не выдавать карту.
	if (fog_state < 0.25) {
		VERTEX.y = 0.02;
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
		c = apply_fog_tint(c, fog_state);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
