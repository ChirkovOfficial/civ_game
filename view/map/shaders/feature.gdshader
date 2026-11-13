// Объекты на клетках (деревья, горы, маркеры ресурсов) через MultiMesh.
// INSTANCE_CUSTOM.xy — координаты клетки в текстуре тумана.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://view/map/shaders/fog.gdshaderinc"

varying flat float fog_state;

void vertex() {
	fog_state = fog_lookup(INSTANCE_CUSTOM.xy);
	if (fog_state < 0.25) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (fog_state < 0.25) {
		discard;
	}
	ALBEDO = apply_fog_tint(to_render_space(COLOR.rgb, OUTPUT_IS_SRGB), fog_state);
	ROUGHNESS = 1.0;
}
