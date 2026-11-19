// Плоские деревья из временного атласа. Белый фон исходного листа убирается
// только при выводе; исходное изображение остаётся нетронутым.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://view/map/shaders/fog.gdshaderinc"

uniform sampler2D forest_sheet : source_color, filter_nearest, repeat_disable;

varying flat float fog_state;
varying vec2 sprite_uv;

void vertex() {
	fog_state = fog_lookup(INSTANCE_CUSTOM.xy);
	// Верхние два ряда: шесть ячеек шириной 120 px, шаг ряда 185 px.
	sprite_uv = (vec2(floor(INSTANCE_CUSTOM.z * 5.0 + 0.5) * 120.0, 10.0 + INSTANCE_CUSTOM.w * 185.0)
		+ UV * vec2(120.0, 180.0)) / vec2(736.0, 1104.0);
}

void fragment() {
	if (fog_state < 0.25) {
		discard;
	}
	vec4 pixel = texture(forest_sheet, sprite_uv);
	float near_white = min(pixel.r, min(pixel.g, pixel.b));
	ALPHA = pixel.a * (1.0 - smoothstep(0.93, 0.995, near_white));
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	ALBEDO = apply_fog_tint(pixel.rgb, fog_state);
}
