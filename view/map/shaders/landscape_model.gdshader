// UV моделей Blender сохранены. INSTANCE_CUSTOM.xy задаёт клетку тумана войны.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_disabled;
#include "res://view/map/shaders/fog.gdshaderinc"
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float material_roughness = 0.9;
varying flat float fog_state;

void vertex() {
	fog_state = fog_lookup(INSTANCE_CUSTOM.xy);
	if (fog_state < 0.25) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (fog_state < 0.25) { discard; }
	vec3 color = base_color.rgb;
	if (has_texture) { color *= texture(albedo_texture, UV).rgb; }
	ALBEDO = apply_fog_tint(color, fog_state);
	ROUGHNESS = material_roughness;
}
