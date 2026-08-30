#version 460 core
out vec4 fragColor;

uniform sampler2D uTexture;
uniform bool uHasTexture;
uniform float uCapFraction;
uniform float uTiles;

in VO {
    vec2 uv;
    vec4 color;
} vi;

const float THIRD = 1.0 / 3.0;

void main() {
    fragColor = vi.color;
    if (uHasTexture) {
        float s = vi.uv.x; // 0 = head, 1 = tail
        float cap = clamp(uCapFraction, 1e-4, 0.4999); // never overlaps
        float u;

        if (s < cap) { // start cap
            u = (s / cap) * THIRD;
        } else if (s > 1.0 - cap) { // end cap
            u = 2.0 * THIRD + ((s - (1.0 - cap)) / cap) * THIRD;
        } else {
            float m = (s - cap) / (1.0 - 2.0 * cap); // 0..1 across the middle
            u = THIRD + fract(m * max(uTiles, 1e-4)) * THIRD;
        }

        fragColor *= texture(uTexture, vec2(u, vi.uv.y));
    }
    if (fragColor.a < 0.01) {
        discard;
    }
}
