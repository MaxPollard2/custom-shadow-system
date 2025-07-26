#version 450

layout(location = 0) in vec3 a_position;

layout(std140, set = 0, binding = 0) uniform TransformData {
    mat4 view_proj;
};

layout(set = 1, binding = 1) uniform Model {
	mat4 model;
};

void main() {
    //int idx = gl_VertexIndex;
    gl_Position = view_proj * model * vec4(a_position, 1.0);// * vec4(1.0, 1.0, -1.0, 1.0);

}