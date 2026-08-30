#version 460 core
out vec4 fragColor;

uniform sampler2D uTexture;
uniform bool uHasTexture;

in VO {
    vec2 uv;
    vec4 color;
} vi;

void main() {
    fragColor = vi.color;
    if (uHasTexture) {
        fragColor *= texture(uTexture, vi.uv);
    }
    if (fragColor.a < 0.01) {
        discard;
    }
}
