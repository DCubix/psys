package psys

import "core:fmt"
import "core:strings"

import gl "vendor:OpenGL"

@(private="file")
ShaderType :: enum {
    VS, FS, CS
}

Shader :: struct {
    handle: u32,
    shaders: map[ShaderType]u32,
    uniforms: map[string]u32,
}

shader_create :: proc() -> Shader {
    return Shader {
        uniforms = make(map[string]u32),
        shaders = make(map[ShaderType]u32),
    }
}

shader_destroy :: proc(s: ^Shader) {
    delete(s.uniforms)
    delete(s.shaders)
    if s.handle != 0 {
        gl.DeleteProgram(s.handle)
        s.handle = 0
    }
}

shader_load_vertex :: proc(s: ^Shader, src: string) -> (ok: bool) {
    shader_id, compile_ok := gl.compile_shader_from_source(src, gl.Shader_Type.VERTEX_SHADER)
    if !compile_ok {
        msg, _ := gl.get_last_error_message()
        fmt.eprintln("vertex shader compile failed:", msg)
        return false
    }
    s.shaders[ShaderType.VS] = shader_id
    return true
}

shader_load_fragment :: proc(s: ^Shader, src: string) -> (ok: bool) {
    shader_id, compile_ok := gl.compile_shader_from_source(src, gl.Shader_Type.FRAGMENT_SHADER)
    if !compile_ok {
        msg, _ := gl.get_last_error_message()
        fmt.eprintln("fragment shader compile failed:", msg)
        return false
    }
    s.shaders[ShaderType.FS] = shader_id
    return true
}

shader_load_compute :: proc(s: ^Shader, src: string) -> (ok: bool) {
    shader_id, compile_ok := gl.compile_shader_from_source(src, gl.Shader_Type.COMPUTE_SHADER)
    if !compile_ok {
        msg, _ := gl.get_last_error_message()
        fmt.eprintln("compute shader compile failed:", msg)
        return false
    }
    s.shaders[ShaderType.CS] = shader_id
    return true
}

shader_link :: proc(s: ^Shader) {
    shaders: [dynamic]u32
    defer delete(shaders)
    for _, sid in s.shaders do append(&shaders, sid)

    program_id, ok := gl.create_and_link_program(shaders[:])
    if ok {
        s.handle = program_id
    } else {
        _, _, msg, _ := gl.get_last_error_messages()
        fmt.eprintln("shader link failed:", msg)
        shader_destroy(s)
    }
    for sid in shaders do gl.DeleteShader(sid)
    clear(&s.shaders)
}

shader_get_uniform_location :: proc(s: ^Shader, name: string) -> Maybe(u32) {
    if name in s.uniforms {
        return s.uniforms[name]
    }

    cname, _ := strings.clone_to_cstring(name, allocator = context.temp_allocator)

    loc := gl.GetUniformLocation(s.handle, cname)
    if loc != -1 {
        s.uniforms[name] = u32(loc)
        return u32(loc)
    }

    return nil
}

shader_set_int :: proc(s: ^Shader, name: string, #any_int value: i32) {
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.Uniform1i(i32(loc), i32(value))
}

shader_set_float :: proc(s: ^Shader, name: string, value: f32) {
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.Uniform1f(i32(loc), value)
}

shader_set_vec2 :: proc(s: ^Shader, name: string, v0: f32, v1: f32) {
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.Uniform2f(i32(loc), v0, v1)
}

shader_set_vec3 :: proc(s: ^Shader, name: string, v0: f32, v1: f32, v2: f32) {
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.Uniform3f(i32(loc), v0, v1, v2)
}

shader_set_vec4 :: proc(s: ^Shader, name: string, v: vec4) {
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.Uniform4f(i32(loc), v.x, v.y, v.z, v.w)
}

shader_set_mat3 :: proc(s: ^Shader, name: string, m: mat3) {
    m_ptr := mat4(m)
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.UniformMatrix3fv(i32(loc), 1, false, raw_data(&m_ptr))
}

shader_set_mat4 :: proc(s: ^Shader, name: string, m: mat4) {
    m_ptr := mat4(m)
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.UniformMatrix4fv(i32(loc), 1, false, raw_data(&m_ptr))
}

shader_set_mat4_array :: proc(s: ^Shader, name: string, m: []mat4) {
    loc, ok := shader_get_uniform_location(s, name).?
    if ok do gl.UniformMatrix4fv(i32(loc), i32(len(m)), false, cast([^]f32)raw_data(m))
}

shader_use :: proc(s: Shader) {
    gl.UseProgram(s.handle)
}
