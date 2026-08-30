package psys

import "core:math"
import la "core:math/linalg"
import "core:mem"

import gl "vendor:OpenGL"

DebugVertex :: struct {
    position: vec3,
    color:    vec4,
}

g_max_debug_vertices :: 8192

@(private="file")
g_debug_vs :: #load("shaders/debug.vert", string)

@(private="file")
g_debug_fs :: #load("shaders/debug.frag", string)

@(private="file")
g_debug_color_red   :: vec4{1.0, 0.0, 0.0, 1.0}
@(private="file")
g_debug_color_green :: vec4{0.0, 1.0, 0.0, 1.0}
@(private="file")
g_debug_color_blue  :: vec4{0.0, 0.0, 1.0, 1.0}

DebugDraw :: struct {
    shader:   Shader,
    vao:      u32,
    vbo:      Buffer,
    vertices: [g_max_debug_vertices]DebugVertex,
    count:    int,
}

debug_draw_init :: proc(dd: ^DebugDraw) -> bool {
    dd.shader = shader_create()
    if !shader_load_vertex(&dd.shader, g_debug_vs) do return false
    if !shader_load_fragment(&dd.shader, g_debug_fs) do return false
    shader_link(&dd.shader)
    if dd.shader.handle == 0 do return false

    dd.vbo = buffer_create_empty(BufferType.ARRAY_BUFFER, g_max_debug_vertices * size_of(DebugVertex))

    gl.GenVertexArrays(1, &dd.vao)
    gl.BindVertexArray(dd.vao)
    buffer_bind(dd.vbo)

    stride := size_of(DebugVertex)
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, i32(stride), 0)
    gl.VertexAttribPointer(1, 4, gl.FLOAT, false, i32(stride), 3 * size_of(f32))

    gl.BindVertexArray(0)
    return true
}

debug_draw_destroy :: proc(dd: ^DebugDraw) {
    shader_destroy(&dd.shader)
    buffer_destroy(&dd.vbo)
    if dd.vao != 0 {
        gl.DeleteVertexArrays(1, &dd.vao)
        dd.vao = 0
    }
    dd.count = 0
}

@(private="file")
debug_draw_push :: proc(dd: ^DebugDraw, a, b: vec3, color: Color) {
    if dd.count + 2 > g_max_debug_vertices {
        return
    }
    dd.vertices[dd.count] = DebugVertex{a, color}
    dd.vertices[dd.count + 1] = DebugVertex{b, color}
    dd.count += 2
}

debug_draw_line :: proc(dd: ^DebugDraw, a, b: vec3, color: Color) {
    debug_draw_push(dd, a, b, color)
}

debug_draw_cross :: proc(dd: ^DebugDraw, pos: vec3, size: f32, color: Color) {
    half := size * 0.5
    debug_draw_push(dd, pos + vec3{-half, 0, 0}, pos + vec3{half, 0, 0}, color)
    debug_draw_push(dd, pos + vec3{0, -half, 0}, pos + vec3{0, half, 0}, color)
    debug_draw_push(dd, pos + vec3{0, 0, -half}, pos + vec3{0, 0, half}, color)
}

debug_draw_axes :: proc(dd: ^DebugDraw, xf: Transform, size: f32) {
    forward, up, right := transform_basis(xf)
    debug_draw_push(dd, xf.position, xf.position + right * size, g_debug_color_red)
    debug_draw_push(dd, xf.position, xf.position + up * size, g_debug_color_green)
    debug_draw_push(dd, xf.position, xf.position + forward * size, g_debug_color_blue)
}

// Draws a single arrow starting at origin, pointing along normal, of the given
// length. A negative length points the arrow the other way. normal does not
// have to be normalized. segments is the number of sides of the head, clamped
// to a minimum of 3.
debug_draw_arrow :: proc(dd: ^DebugDraw, origin, normal: vec3, length: f32, color: Color, segments := 4) {
    n_len := la.length(normal)
    if n_len <= 0.0 || length == 0.0 do return

    n := normal / n_len
    dir := length < 0.0 ? -n : n
    tip := origin + n * length
    debug_draw_push(dd, origin, tip, color)

    head_len := math.abs(length) * 0.2
    head_radius := head_len * 0.5
    base := tip - dir * head_len

    t0, t1 := debug_draw_basis_from_normal(dir)
    sides := max(segments, 3)
    for i in 0..<sides {
        a0 := (f32(i) / f32(sides)) * (math.PI * 2.0)
        a1 := (f32(i + 1) / f32(sides)) * (math.PI * 2.0)
        p0 := base + (t0 * math.cos(a0) + t1 * math.sin(a0)) * head_radius
        p1 := base + (t0 * math.cos(a1) + t1 * math.sin(a1)) * head_radius
        debug_draw_push(dd, p0, tip, color)
        debug_draw_push(dd, p0, p1, color)
    }
}

debug_draw_box :: proc(dd: ^DebugDraw, center, half_extents: vec3, color: Color) {
    x, y, z := half_extents.x, half_extents.y, half_extents.z

    p: [8]vec3
    p[0] = center + vec3{-x, -y, -z}
    p[1] = center + vec3{ x, -y, -z}
    p[2] = center + vec3{ x,  y, -z}
    p[3] = center + vec3{-x,  y, -z}
    p[4] = center + vec3{-x, -y,  z}
    p[5] = center + vec3{ x, -y,  z}
    p[6] = center + vec3{ x,  y,  z}
    p[7] = center + vec3{-x,  y,  z}

    debug_draw_push(dd, p[0], p[1], color)
    debug_draw_push(dd, p[1], p[2], color)
    debug_draw_push(dd, p[2], p[3], color)
    debug_draw_push(dd, p[3], p[0], color)

    debug_draw_push(dd, p[4], p[5], color)
    debug_draw_push(dd, p[5], p[6], color)
    debug_draw_push(dd, p[6], p[7], color)
    debug_draw_push(dd, p[7], p[4], color)

    debug_draw_push(dd, p[0], p[4], color)
    debug_draw_push(dd, p[1], p[5], color)
    debug_draw_push(dd, p[2], p[6], color)
    debug_draw_push(dd, p[3], p[7], color)
}

debug_draw_circle :: proc(dd: ^DebugDraw, center: vec3, radius: f32, normal: vec3, color: Color, segments := 32) {
    t0, t1 := debug_draw_basis_from_normal(normal)

    prev := center + t0 * radius
    for i in 1..=segments {
        angle := (f32(i) / f32(segments)) * (math.PI * 2.0)
        pos := center + (t0 * math.cos(angle) + t1 * math.sin(angle)) * radius
        debug_draw_push(dd, prev, pos, color)
        prev = pos
    }
}

debug_draw_sphere :: proc(dd: ^DebugDraw, center: vec3, radius: f32, color: Color, segments := 24) {
    debug_draw_circle(dd, center, radius, vec3{1.0, 0.0, 0.0}, color, segments)
    debug_draw_circle(dd, center, radius, vec3{0.0, 1.0, 0.0}, color, segments)
    debug_draw_circle(dd, center, radius, vec3{0.0, 0.0, 1.0}, color, segments)
}

debug_draw_flush :: proc(dd: ^DebugDraw, proj, view: mat4) {
    if dd.count == 0 do return

    blend_src, blend_dst: i32
    gl.GetIntegerv(gl.BLEND_SRC_ALPHA, &blend_src)
    gl.GetIntegerv(gl.BLEND_DST_ALPHA, &blend_dst)

    blend_was_enabled := gl.IsEnabled(gl.BLEND)
    depth_was_enabled := gl.IsEnabled(gl.DEPTH_TEST)
    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    gl.BindVertexArray(dd.vao)
    buffer_bind(dd.vbo)
    buffer_update(dd.vbo, mem.slice_to_bytes(dd.vertices[:dd.count]))

    shader_use(dd.shader)
    shader_set_mat4(&dd.shader, "uProj", proj)
    shader_set_mat4(&dd.shader, "uView", view)

    gl.DrawArrays(gl.LINES, 0, i32(dd.count))

    gl.BindVertexArray(0)
    if !depth_was_enabled do gl.Disable(gl.DEPTH_TEST)
    if !blend_was_enabled do gl.Disable(gl.BLEND)
    else do gl.BlendFunc(u32(blend_src), u32(blend_dst))

    dd.count = 0
}

@(private="file")
debug_draw_basis_from_normal :: proc(normal: vec3) -> (t0, t1: vec3) {
    n := la.normalize(normal)
    helper := math.abs(n.y) < 0.999 ? vec3{0.0, 1.0, 0.0} : vec3{1.0, 0.0, 0.0}
    t0 = la.normalize(la.cross(n, helper))
    t1 = la.cross(n, t0)
    return
}
