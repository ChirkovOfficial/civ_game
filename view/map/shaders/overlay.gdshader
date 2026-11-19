// Плоские наложения на карту (реки, вода). UV2 — координаты клетки в текстуре тумана.
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_opaque;

#include "res://view/map/shaders/fog.gdshaderinc"

uniform float alpha_mult = 1.0;
varying flat float fog_state;
varying flat float biome;
varying vec3 world_pos;
uniform bool textured_water = false;
uniform sampler2D biome_atlas : source_color, filter_linear, repeat_disable;

void vertex() {
	biome = UV.x;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fog_state = fog_lookup(UV2);
	if (fog_state < 0.25) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (fog_state < 0.25) {
		discard;
	}
	vec3 c = to_render_space(COLOR.rgb, OUTPUT_IS_SRGB);
	if (textured_water) {
		vec2 cell = vec2(mod(biome, 4.0), floor(biome / 4.0));
		vec2 local_uv = clamp(fract(world_pos.xz / 4.0), vec2(0.005), vec2(0.995));
		c = mix(c, texture(biome_atlas, (cell + local_uv) / vec2(4.0, 2.0)).rgb, 0.7);
	}
	c = apply_fog_tint(c, fog_state);
	ALBEDO = c;
	ALPHA = COLOR.a * alpha_mult;
}
