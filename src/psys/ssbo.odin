package psys

import "core:slice"
import "core:strings"
import gl "vendor:OpenGL"

SSBO :: struct {
    using buffer: Buffer,
    binding_point: u32,
}

ssbo_create :: proc(binding: u32, data: []byte, static: bool = false) -> SSBO {
    return SSBO {
        buffer = buffer_create(BufferType.SSBO, data, static),
        binding_point = binding,
    }
}

ssbo_create_empty :: proc(binding: u32) -> SSBO {
    ssbo: SSBO
    ssbo.binding_point = binding
    buffer_init(&ssbo, BufferType.SSBO)
    return ssbo
}

ssbo_bind_to_shader :: proc(ssbo: SSBO, shader: Shader, block_name: string) {
    c_block_name := strings.clone_to_cstring(block_name, allocator = context.temp_allocator)
    index := gl.GetProgramResourceIndex(shader.handle, gl.SHADER_STORAGE_BLOCK, c_block_name)
    gl.ShaderStorageBlockBinding(shader.handle, index, ssbo.binding_point)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, ssbo.binding_point, ssbo.handle)
}

ssbo_read_back :: proc(ssbo: SSBO, #any_int byte_count: int) -> []byte {
    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, ssbo.handle)
    ptr := gl.MapBuffer(gl.SHADER_STORAGE_BUFFER, gl.READ_ONLY)
    data := slice.bytes_from_ptr(ptr, byte_count)
    gl.UnmapBuffer(gl.SHADER_STORAGE_BUFFER)
    return data
}
