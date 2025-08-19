shader_type spatial;
render_mode unshaded;

global uniform vec3 light_dir;

#include "res://shadow_system/ShadowUtils.gdshaderinc"
//


uniform int albedo_type;
uniform sampler2D albedo_texture : filter_nearest;
uniform vec3 albedo_color = vec3(0.255, 0.357, 0.451);

varying vec3 world_position;

const float RADIUS_SCALE = 1.0;

vec3 sRGB_to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

float compute_shadow_pcf(sampler2D shadow_tex, vec2 uv, float compare_depth, float radius) {
	float shadow = 0.0;
	for (int x = -SAMPLES; x <= SAMPLES; x++) {
		for (int y = -SAMPLES; y <= SAMPLES; y++) {
			vec2 offset = vec2(float(x), float(y)) * radius;
			float sampled = texture(shadow_tex, clamp(uv + offset, vec2(0.01), vec2(0.99))).r;
			if (compare_depth > sampled) {
				shadow += 1.0;
			}
		}
	}
	return shadow;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float light_amount = max(dot(light_dir, world_normal), 0.0);

	vec3 debug = vec3(0.0);
	float shadow_factor = get_shadow(world_normal, light_dir, VIEW_MATRIX, world_position, debug);
	//shadow_factor = 1.0;

	vec3 base_color = albedo_color;

	if (albedo_type == 0) { //texture
		base_color = sRGB_to_linear(texture(albedo_texture, UV).rgb);
	}
	else if (albedo_type == 1) {
		base_color = sRGB_to_linear(COLOR.rgb);
	}

	ALBEDO = base_color * light_amount * shadow_factor;
}
