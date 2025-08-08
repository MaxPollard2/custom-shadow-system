global uniform sampler2D cascade_1_map;
global uniform mat4 cascade_1_view_proj;
global uniform vec3 cascade_1_range;

global uniform sampler2D cascade_2_map;
global uniform mat4 cascade_2_view_proj;
global uniform vec3 cascade_2_range;

global uniform sampler2D cascade_3_map;
global uniform mat4 cascade_3_view_proj;
global uniform vec3 cascade_3_range;

global uniform sampler2D cascade_4_map;
global uniform mat4 cascade_4_view_proj;
global uniform vec3 cascade_4_range;

global uniform sampler2D cascade_5_map;
global uniform mat4 cascade_5_view_proj;
global uniform vec3 cascade_5_range;

global uniform sampler2DArray cascade_maps;

const float RESOLUTION = 4096.0;
const int SAMPLES = 1;

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

float compute_shadow_pcf_2(float map_index, vec2 uv, float compare_depth, float radius) {
	float shadow = 0.0;
	for (int x = -SAMPLES; x <= SAMPLES; x++) {
		for (int y = -SAMPLES; y <= SAMPLES; y++) {
			vec2 offset = vec2(float(x), float(y)) * radius;
			float sampled = texture(cascade_maps, vec3(clamp(uv + offset, vec2(0.01), vec2(0.99)), map_index)).r;
			if (compare_depth > sampled) {
				shadow += 1.0;
			}
		}
	}
	return shadow;
}

float get_shadow_from_cascade(vec3 in_world_position, float slope, sampler2D map, mat4 view_proj, float light_depth)
{
	vec4 light_space_pos = view_proj * vec4(in_world_position, 1.0);
	vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
	vec2 uv = shadow_coord.xy * 0.5 + 0.5;

	float world_width = 2.0 / abs(view_proj[0][0]);
	float texel_width = (world_width / RESOLUTION);

	float _radius = 1.0 / (RESOLUTION * 2.0);
	
	float bias = (texel_width / (light_depth * 1.0)) * max(slope, 1.0);
	bias *= 0.5;
//
    return compute_shadow_pcf(map, uv, shadow_coord.z - bias, _radius);
}

float get_shadow_from_cascade_2(vec3 in_world_position, float slope, float map_index, mat4 view_proj, float light_depth)
{
	vec4 light_space_pos = view_proj * vec4(in_world_position, 1.0);
	vec3 shadow_coord = light_space_pos.xyz / light_space_pos.w;
	vec2 uv = shadow_coord.xy * 0.5 + 0.5;

	float world_width = 2.0 / abs(view_proj[0][0]);
	float texel_width = (world_width / RESOLUTION);

	float _radius = 1.0 / (RESOLUTION * 2.0);
	
	float bias = (texel_width / (light_depth * 1.0)) * max(slope, 1.0);
	bias *= 0.5;
//
    return compute_shadow_pcf_2(map_index, uv, shadow_coord.z - bias, _radius);
}

float get_shadow(vec3 world_normal, vec3 light_dir, mat4 view_matrix, vec3 in_world_position, out vec3 debug_colour)
{
	float shadow = 0.0;
	float total_samples = float((2 * SAMPLES + 1) * (2 * SAMPLES + 1));
	
	float slope = 1.0 - abs(dot(world_normal, light_dir));
	slope = 1.0;

	float eye_depth  = -(view_matrix * vec4(in_world_position, 1.0)).z;
	//eye_depth = abs(length(in_world_position));

	if (eye_depth < cascade_1_range.y)
	{
		shadow = get_shadow_from_cascade_2(in_world_position, slope, 0.1, cascade_1_view_proj, cascade_1_range.z);
		debug_colour = vec3(1.0, 0.0, 0.0); // RED
	}
	else if (eye_depth < cascade_2_range.y)
	{
		shadow = get_shadow_from_cascade_2(in_world_position, slope, 1.0, cascade_2_view_proj, cascade_2_range.z);
		debug_colour = vec3(0.0, 1.0, 0.0); // GREEN
	}
	else if (eye_depth < cascade_3_range.y)
	{
		shadow = get_shadow_from_cascade_2(in_world_position, slope, 2.0, cascade_3_view_proj, cascade_3_range.z);
		debug_colour = vec3(0.0, 0.0, 1.0); // BLUE
	}
	else if (eye_depth < cascade_4_range.y)
	{
		shadow = get_shadow_from_cascade_2(in_world_position, slope, 3.0, cascade_4_view_proj, cascade_4_range.z);
		debug_colour = vec3(1.0, 1.0, 0.0); // YELLOW
	}
	else if (eye_depth < cascade_5_range.y)
	{
		shadow = get_shadow_from_cascade_2(in_world_position, slope, 4.0, cascade_5_view_proj, cascade_5_range.z);
		debug_colour = vec3(0.0, 1.0, 1.0); // CYAN
	}
	else
	{
		shadow = 0.0;
		debug_colour = vec3(5.0, 0.0, 5.0); // BLACK (outside cascades)
	}
	
	float shadow_factor = 1.0 - (shadow / total_samples);
	
	return shadow_factor;
}