#version 450

layout(location = 0) in vec3 a_position;

layout(std140, set = 0, binding = 0) uniform TransformData {
    mat4 view_proj;
};

layout(std430, set = 1, binding = 0) readonly buffer Models {
    mat4 model[];
};


layout(push_constant) uniform Push {
    uint model_index;
} pc;


void main() {
    //int idx = gl_VertexIndex;
    mat4 M = model[pc.model_index];
    gl_Position = view_proj * M * vec4(a_position, 1.0);
}