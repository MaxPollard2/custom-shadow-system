#version 450

layout(location = 0) out vec4 frag_color;

void main() {
    float depth = gl_FragCoord.z;

    //frag_color = vec4(depth, fract(depth * 100.0), 0.0, 1.0);

    frag_color = vec4(depth, fract(depth * 100.0), 0.0, 0.0);
}