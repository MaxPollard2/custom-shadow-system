shader_type spatial;
render_mode unshaded;

global uniform vec3 light_pos;

global uniform sampler2D shadow_map;
global uniform mat4 shadow_view_proj;
global uniform float shadow_tier_1_size;

global uniform sampler2D shadow_tier_2_map;
global uniform float shadow_tier_2_size;

varying vec3 world_position;

const int SAMPLES = 4;
const float TEXEL_SIZE = 1.0 / 4096.0;
const float RADIUS_SCALE = 2.0 * 0.2;

float compute_shadow_pcf(sampler2D shadow_tex, vec2 uv, float compare_depth, float radius) {
	float shadow = 0.0;
	for (int x = -SAMPLES; x <= SAMPLES; x++) {
		for (int y = -SAMPLES; y <= SAMPLES; y++) {
			vec2 offset = vec2(float(x), float(y)) * radius;
			float sampled = texture(shadow_tex, clamp(uv + offset, vec2(0.001), vec2(0.999))).r;
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
	vec3 light_dir = normalize(light_pos - world_position);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float light_amount = max(dot(light_dir, world_normal), 0.0);

	float bias = max(0.000005 * (1.0 - dot(world_normal, light_dir)), 0.0000005);
	float radius = TEXEL_SIZE * RADIUS_SCALE;

	// Project into shadow tier 1 space
	vec4 light_space_pos = shadow_view_proj * vec4(world_position, 1.0);
	vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
	vec2 shadow_uv = shadow_coord.xy; // in range [-1, 1]

	float shadow = 0.0;
	float total_samples = float((2 * SAMPLES + 1) * (2 * SAMPLES + 1));

	// Try tier 1
	if (all(lessThan(abs(shadow_uv), vec2(1.0)))) {
		vec2 uv = shadow_uv * 0.5 + 0.5;
		shadow = compute_shadow_pcf(shadow_map, uv, shadow_coord.z - bias, radius);
	}
	// Fallback to tier 2
	else {
		float scale = shadow_tier_1_size / shadow_tier_2_size;
		vec2 uv_tier_2 = shadow_uv * scale;
		if (all(lessThan(abs(uv_tier_2), vec2(1.0)))) {
			vec2 uv = uv_tier_2 * 0.5 + 0.5;
			shadow = compute_shadow_pcf(shadow_tier_2_map, uv, shadow_coord.z - bias, radius);
		}
	}

	// Light/shadow mix
	float shadow_factor = 1.0 - (shadow / total_samples);
	if (shadow == 0.0) {
		shadow_factor = 1.0; // fully lit
	}

	vec3 base_color = vec3(0.255, 0.357, 0.451);
	ALBEDO = base_color * light_amount * shadow_factor;
}