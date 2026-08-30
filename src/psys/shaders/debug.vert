#version 460 core
layout (location = 0) in vec3 vPosition;
layout (location = 1) in vec4 vColor;

uniform mat4 uProj;
uniform mat4 uView;

out VO {
    vec4 color;
} vo;

void main() {
    vo.color = vColor;
    gl_Position = uProj * uView * vec4(vPosition, 1.0);
}
