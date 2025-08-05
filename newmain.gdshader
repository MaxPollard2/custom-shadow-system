shader_type spatial;
render_mode unshaded;

global uniform vec3 light_dir;

global uniform sampler2D cascade_1_map;
global uniform vec3 cascade_1_range;
global uniform mat4 cascade_1_view_proj;

global uniform sampler2D cascade_2_map;
global uniform vec3 cascade_2_range;
global uniform mat4 cascade_2_view_proj;
//
//global uniform sampler2D cascade_3_map;
//global uniform vec2 cascade_3_range;
//global uniform mat4 cascade_3_view_proj;

uniform int albedo_type;
uniform sampler2D albedo_texture : filter_nearest;
uniform vec3 albedo_color = vec3(0.255, 0.357, 0.451);

varying vec3 world_position;

const int SAMPLES = 2;
const float RADIUS_SCALE = 1.0;
const float RESOLUTION = 4096.0;

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

	float shadow = 0.0;
	float total_samples = float((2 * SAMPLES + 1) * (2 * SAMPLES + 1));
//
	float slope = 1.0 - dot(world_normal, -light_dir);

	float eye_depth  = -(VIEW_MATRIX * vec4(world_position, 1.0)).z;

	if (eye_depth < cascade_1_range.y)
	{
	    vec4 light_space_pos = cascade_1_view_proj * vec4(world_position, 1.0);
	    vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
	    vec2 uv = shadow_coord.xy * 0.5 + 0.5;

		// m00 = 2 / (right - left) → right - left = 2 / m00
		float world_width_casc1 = 2.0 / cascade_1_view_proj[0][0];
		float texel_world_casc1 = (world_width_casc1 / RESOLUTION);
		//float radius_casc1 = texel_world_casc1 * RADIUS_SCALE;

		//uv = floor(uv * RESOLUTION) / RESOLUTION;
		float _radius = 1.0 / (RESOLUTION * 2.0);
//
		float light_depth = cascade_1_range.z;
		float bias = (texel_world_casc1 / (light_depth * 5.0)) * max(slope, 1.0);
//
	    shadow = compute_shadow_pcf(cascade_1_map, uv, shadow_coord.z + bias, _radius);
	}
	else if (eye_depth < cascade_2_range.y)
	{
	    vec4 light_space_pos = cascade_2_view_proj * vec4(world_position, 1.0);
	    vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
	    vec2 uv = shadow_coord.xy * 0.5 + 0.5;

		float world_width_casc2 = 2.0 / cascade_2_view_proj[0][0];
		float texel_world_casc2 = (world_width_casc2 / RESOLUTION);
		//float radius_casc2 = texel_world_casc2 * RADIUS_SCALE;

		//uv = floor(uv * RESOLUTION) / RESOLUTION;
		float _radius = 1.0 / (RESOLUTION * 2.0);

		float light_depth = cascade_2_range.z;
		float bias = (texel_world_casc2 / (light_depth * 5.0)) * max(slope, 1.0);

	    shadow = compute_shadow_pcf(cascade_2_map, uv, shadow_coord.z + bias, _radius);
	}
	else
	{
		shadow = 0.0;
	}

	float shadow_factor = 1.0 - (shadow / total_samples);
	if (shadow == 0.0) {
		shadow_factor = 1.0; // fully lit
	}

	vec3 base_color = albedo_color;

	if (albedo_type == 0) { //texture
		base_color = sRGB_to_linear(texture(albedo_texture, UV).rgb);
	}
	else if (albedo_type == 1) {
		base_color = sRGB_to_linear(COLOR.rgb);
	}

	ALBEDO = base_color * light_amount * shadow_factor;
}
