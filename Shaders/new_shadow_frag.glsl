#version 450
#extension GL_ARB_shader_viewport_layer_array : require

layout(location = 0) out vec4 frag_color;

void main() {
    float depth = gl_FragCoord.z;

    frag_color = vec4(depth, 1.0, 1.0, 1.0);
   
}