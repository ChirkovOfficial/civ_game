// Плоские наложения на карту (реки, вода). UV2 — координаты клетки в текстуре тумана.
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_opaque;

#include "res://view/map/shaders/fog.gdshaderinc"

uniform float alpha_mult = 1.0;
varying flat float fog_state;

void vertex() {
	fog_state = fog_lookup(UV2);
	if (fog_state < 0.25) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (fog_state < 0.25) {
		discard;
	}
	vec3 c = apply_fog_tint(to_render_space(COLOR.rgb, OUTPUT_IS_SRGB), fog_state);
	ALBEDO = c;
	ALPHA = COLOR.a * alpha_mult;
}
