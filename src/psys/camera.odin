package psys

import la "core:math/linalg"

Camera :: struct {
    using transform: Transform,
    fov: f32,
    aspect: f32,
    z_near, z_far: f32,
}

camera_projection_matrix :: proc(c: Camera) -> mat4 {
    return la.matrix4_perspective(c.fov, c.aspect, c.z_near, c.z_far)
}
