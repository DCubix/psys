package psys

import gl "vendor:OpenGL"

BufferType :: enum {
    ARRAY_BUFFER = gl.ARRAY_BUFFER,
    INDEX_BUFFER = gl.ELEMENT_ARRAY_BUFFER,
    UNIFORM_BUFFER = gl.UNIFORM_BUFFER,
    SSBO = gl.SHADER_STORAGE_BUFFER,
}

BufferBaseTarget :: enum {
    UNIFORM_BUFFER = gl.UNIFORM_BUFFER,
    SSBO = gl.SHADER_STORAGE_BUFFER,
}

Buffer :: struct {
    handle: u32,
    type: BufferType,
    static: bool,
}

@(private)
buffer_init :: proc(b: ^Buffer, type: BufferType) {
    gl.CreateBuffers(1, &b.handle)
    gl.BindBuffer(u32(type), b.handle)
    b.type = type
}

buffer_create :: proc(type: BufferType, data: []byte, static: bool = false) -> Buffer {
    buffer: Buffer
    buffer.static = static
    buffer_init(&buffer, type)
    gl.BufferData(u32(type), len(data), raw_data(data), static ? gl.STATIC_DRAW : gl.DYNAMIC_DRAW)
    return buffer
}

buffer_create_empty :: proc(type: BufferType, #any_int byte_size: int, static: bool = false) -> Buffer {
    buffer: Buffer
    buffer.static = static
    buffer_init(&buffer, type)
    gl.BufferData(u32(type), byte_size, nil, static ? gl.STATIC_DRAW : gl.DYNAMIC_DRAW)
    return buffer
}

buffer_destroy :: proc(buf: ^Buffer) {
    gl.DeleteBuffers(1, &buf.handle)
    buf.handle = 0
}

buffer_bind :: proc(buf: Buffer) {
    gl.BindBuffer(u32(buf.type), buf.handle)
}

buffer_bind_base :: proc(buf: Buffer, target: BufferBaseTarget, #any_int index: u32) {
    gl.BindBufferBase(u32(target), index, buf.handle);
}

buffer_resize :: proc(buf: Buffer, #any_int byte_size: int) {
    gl.BufferData(u32(buf.type), byte_size, nil, buf.static ? gl.STATIC_DRAW : gl.DYNAMIC_DRAW)
}

buffer_update :: proc(buf: Buffer, data: []byte, #any_int offset: int = 0) {
    gl.BufferSubData(u32(buf.type), offset, len(data), raw_data(data))
}
