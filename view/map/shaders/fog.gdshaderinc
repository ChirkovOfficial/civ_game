// Общие функции тумана войны для шейдеров карты.
// fog_tex: R = состояние клетки (0 — не разведана, 0.5 — разведана, 1 — видна).

uniform sampler2D fog_tex : filter_nearest, repeat_disable;
uniform bool reveal_all = false;
uniform vec3 unexplored_color = vec3(0.17, 0.19, 0.23);

float fog_lookup(vec2 tile_uv) {
	return reveal_all ? 1.0 : textureLod(fog_tex, tile_uv, 0.0).r;
}

// Вершинные цвета заданы в sRGB. Рендерер Forward+ считает свет в линейном
// пространстве — переводим; рендерер Compatibility работает в sRGB — оставляем.
// Вызывать как to_render_space(c, OUTPUT_IS_SRGB).
vec3 to_render_space(vec3 c, bool output_is_srgb) {
	if (output_is_srgb) {
		return c;
	}
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// Разведанные, но не видимые клетки — приглушённые и обесцвеченные.
vec3 apply_fog_tint(vec3 lin_color, float fog) {
	if (fog < 0.75) {
		float g = dot(lin_color, vec3(0.2126, 0.7152, 0.0722));
		return mix(lin_color, vec3(g), 0.6) * 0.55;
	}
	return lin_color;
}
