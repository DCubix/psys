#version 460 core
layout (location = 0) in vec3 vPosition;
layout (location = 1) in vec4 vColor;
layout (location = 2) in vec2 vUV;

uniform mat4 uProj;
uniform mat4 uView;

out VO {
    vec2 uv;
    vec4 color;
} vo;

void main() {
    gl_Position = uProj * uView * vec4(vPosition, 1.0);
    vo.uv = vUV;
    vo.color = vColor;
}
