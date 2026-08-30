package psys

import "core:encoding/json"
import la "core:math/linalg"
import "core:math"

Transform :: struct {
    position: vec3,
    scale: vec3,
    rotation: quat `json:"-"`,
    parent: ^Transform `json:"-"`,

    // caching
    old_position: vec3 `json:"-"`,
    old_scale: vec3 `json:"-"`,
    old_rotation: quat `json:"-"`,
    world_matrix: mat4 `json:"-"`,
}

transform_init :: proc(xf: ^Transform, position := vec3{0,0,0}, scale := vec3{1,1,1}, rotation := quat(1)) {
    xf.position = position
    xf.scale = scale
    xf.rotation = rotation
    xf.old_scale = vec3{math.nan_f32(), 0, 0}
}

transform_is_dirty :: proc(xf: Transform) -> bool {
    return xf.position != xf.old_position ||
        xf.scale != xf.old_scale ||
        xf.rotation != xf.old_rotation
}

transform_local_matrix :: proc(xf: Transform) -> mat4 {
    tmat := la.matrix4_translate(xf.position)
    rmat := la.matrix4_from_quaternion(xf.rotation)
    smat := la.matrix4_scale(xf.scale)
    return tmat * rmat * smat
}

transform_world_matrix :: proc(xf: ^Transform) -> mat4 {
    local_changed := transform_is_dirty(xf^)

    parent := la.MATRIX4F32_IDENTITY
    parent_changed := false
    if xf.parent != nil {
        prev_parent_world := xf.parent.world_matrix
        parent = transform_world_matrix(xf.parent) // always recurse
        parent_changed = parent != prev_parent_world
    }

    if local_changed || parent_changed {
        local := transform_local_matrix(xf^)
        xf.old_position = xf.position
        xf.old_rotation = xf.rotation
        xf.old_scale = xf.scale
        xf.world_matrix = parent * local
    }
    
    return xf.world_matrix
}

transform_view_matrix :: proc(xf: Transform) -> mat4 {
    nxf := Transform { // ensure no non-uniform scale
        position = xf.position,
        rotation = xf.rotation,
        scale = {1.0, 1.0, 1.0},
        parent = xf.parent,
    }
    world := transform_world_matrix(&nxf)
    return la.matrix4_inverse(world)
}

transform_world_position :: proc(xf: Transform) -> vec3 {
    if xf.parent != nil {
        parent_mat := transform_world_matrix(xf.parent)
        return (parent_mat * vec4{xf.position.x, xf.position.y, xf.position.z, 1}).xyz
    }
    return xf.position
}

transform_world_rotation :: proc(xf: Transform) -> quat {
    if xf.parent != nil {
        return transform_world_rotation(xf.parent^) * xf.rotation
    }
    return xf.rotation
}

transform_forward :: proc(xf: Transform, local: bool = false) -> vec3 {
    q := local ? xf.rotation : transform_world_rotation(xf)
    return la.quaternion_mul_vector3(q, vec3{0.0, 0.0, -1.0})
}

transform_up :: proc(xf: Transform, local: bool = false) -> vec3 {
    q := local ? xf.rotation : transform_world_rotation(xf)
    return la.quaternion_mul_vector3(q, vec3{0.0, 1.0, 0.0})
}

transform_right :: proc(xf: Transform, local: bool = false) -> vec3 {
    q := local ? xf.rotation : transform_world_rotation(xf)
    return la.quaternion_mul_vector3(q, vec3{1.0, 0.0, 0.0})
}

transform_basis :: proc(xf: Transform, local: bool = false) -> (forward, up, right: vec3) {
    q := local ? xf.rotation : transform_world_rotation(xf)
    m := la.matrix4_from_quaternion(q)
    right   = vec3{m[0,0], m[1,0], m[2,0]}
    up      = vec3{m[0,1], m[1,1], m[2,1]}
    forward = -vec3{m[0,2], m[1,2], m[2,2]}
    return
}

transform_look_at :: proc(xf: ^Transform, target: vec3, world_up: vec3 = vec3{0.0, 1.0, 0.0}) {
    world_pos := transform_world_position(xf^)
    fwd := la.normalize(target - world_pos)

    up := world_up
    if abs(la.dot(fwd, up)) > 0.999 {
        up = vec3{1.0, 0.0, 0.0}
    }

    right := la.normalize(la.cross(fwd, up))
    real_up := la.cross(right, fwd)

    m := matrix[3,3]f32{
        right.x, real_up.x, -fwd.x,
        right.y, real_up.y, -fwd.y,
        right.z, real_up.z, -fwd.z,
    }
    world_rot := la.quaternion_from_matrix3(m)

    if xf.parent != nil {
        parent_rot := transform_world_rotation(xf.parent^)
        xf.rotation = la.quaternion_inverse(parent_rot) * world_rot
    } else {
        xf.rotation = world_rot
    }
}

transform_lerp :: proc(a: Transform, b: Transform, t: f32) -> Transform {
    return Transform {
        position = la.lerp(a.position, b.position, t),
        scale = la.lerp(a.scale, b.scale, t),
        rotation = la.quaternion_slerp_f32(a.rotation, b.rotation, t),
    }
}

transform_point_vec4 :: proc(xf: ^Transform, point: vec4) -> vec4 {
    return transform_world_matrix(xf) * point
}

transform_point :: proc(xf: ^Transform, point: vec3, w: f32 = 1.0) -> vec3 {
    pt := transform_point_vec4(xf, vec4{point.x, point.y, point.z, w})
    return vec3{pt.x, pt.y, pt.z}
}
