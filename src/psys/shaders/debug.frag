#version 460 core
out vec4 fragColor;

in VO {
    vec4 color;
} vi;

void main() {
    fragColor = vi.color;
}
