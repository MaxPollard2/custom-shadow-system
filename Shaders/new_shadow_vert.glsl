#version 450
#extension GL_ARB_shader_viewport_layer_array : require

layout(location = 0) in vec3 a_position;

const uint NUM_CASCADES = 5;

layout(std140, set = 0, binding = 0) uniform TransformData {
    mat4 view_proj[NUM_CASCADES]; // e.g., 5
};

layout(std430, set = 1, binding = 0) readonly buffer Models {
    mat4 model[];
};


layout(push_constant) uniform Push {
    uint model_index;
} pc;


void main() {
    uint cascade_index = gl_InstanceIndex % NUM_CASCADES;

    mat4 VP = view_proj[cascade_index];
    //mat4 VP = view_proj[1];
    mat4 M = model[pc.model_index];

    gl_Position = VP * M * vec4(a_position, 1.0);
    gl_Layer = int(cascade_index);
}