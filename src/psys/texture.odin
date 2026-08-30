package psys

import "core:fmt"
import "core:strings"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

TextureFormat :: enum {
    R,
    RG,
    RGB,
    RGBA,
    R_Float,
    RG_Float,
    RGB_Float,
    RGBA_Float,
    Depth,
    DepthStencil,
}

TextureWrap :: enum u64 {
    Clamp = gl.CLAMP_TO_EDGE,
    Repeat = gl.REPEAT,
}

TextureFilter :: enum u64 {
    Nearest = gl.NEAREST,
    Linear = gl.LINEAR,
    NearestMipNearest = gl.NEAREST_MIPMAP_NEAREST,
    LinearMipLinear = gl.LINEAR_MIPMAP_LINEAR,
}

TextureParams :: struct {
    wrap: struct {
        s: TextureWrap,
        t: TextureWrap,
    },
    filter: struct {
        min: TextureFilter,
        mag: TextureFilter,
    },
}

DEFAULT_TEXTURE_PARAMS :: TextureParams {
    wrap = {s = .Repeat, t = .Repeat},
    filter = {min = .Linear, mag = .Linear},
}

Texture2D :: struct {
    width: u32,
    height: u32,
    handle: u32,
    format: TextureFormat,
}

@(private="file")
texture_get_format :: proc(fmt: TextureFormat) -> (internal: u64, format: u64, type: u64) {
    switch fmt {
        case .R: return gl.R8, gl.RED, gl.UNSIGNED_BYTE
        case .RG: return gl.RG8, gl.RG, gl.UNSIGNED_BYTE
        case .RGB: return gl.RGB8, gl.RGB, gl.UNSIGNED_BYTE
        case .RGBA: return gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE
        case .R_Float: return gl.R32F, gl.RED, gl.FLOAT
        case .RG_Float: return gl.RG32F, gl.RG, gl.FLOAT
        case .RGB_Float: return gl.RGB32F, gl.RGB, gl.FLOAT
        case .RGBA_Float: return gl.RGBA32F, gl.RGBA, gl.FLOAT
        case .Depth: return gl.DEPTH_COMPONENT24, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT
        case .DepthStencil: return gl.DEPTH24_STENCIL8, gl.DEPTH_STENCIL, gl.UNSIGNED_INT_24_8
        case: return gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE
    }
}

@(private="file")
texture_2d_init :: proc(tex: ^Texture2D, width: u32, height: u32, format: TextureFormat) {
    gl.GenTextures(1, &tex.handle)
    tex.width = width
    tex.height = height
    tex.format = format
}

texture_2d_create :: proc(
    width: u32, height: u32,
    format: TextureFormat,
    params: Maybe(TextureParams),
    data: [^]byte = nil,
) -> Texture2D {
    tex: Texture2D
    texture_2d_init(&tex, width, height, format)
    gl.BindTexture(gl.TEXTURE_2D, tex.handle)

    p := params.? or_else DEFAULT_TEXTURE_PARAMS
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(p.filter.min))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(p.filter.mag))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(p.wrap.s))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(p.wrap.t))

    internal, fmt, type := texture_get_format(format)
    gl.TexImage2D(gl.TEXTURE_2D, 0, i32(internal), i32(width), i32(height), 0, u32(fmt), u32(type), data)

    should_generate_mips :=
            p.filter.min == TextureFilter.NearestMipNearest ||
            p.filter.min == TextureFilter.LinearMipLinear
    if should_generate_mips {
        gl.GenerateMipmap(gl.TEXTURE_2D)
    }

    gl.BindTexture(gl.TEXTURE_2D, 0)

    return tex
}

texture_2d_set_params :: proc(tex: Texture2D, p: TextureParams) {
    gl.BindTexture(gl.TEXTURE_2D, tex.handle)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(p.filter.min))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(p.filter.mag))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(p.wrap.s))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(p.wrap.t))
    gl.BindTexture(gl.TEXTURE_2D, 0)
}

texture_2d_load_file :: proc(file_path: string, params: Maybe(TextureParams) = nil) -> (tex: Texture2D, ok: bool) #optional_ok {
    w, h, comp : i32 = 0, 0, 0

    cpath, _ := strings.clone_to_cstring(file_path, allocator = context.temp_allocator)

    data := stbi.load(cpath, &w, &h, &comp, 0)
    if data == nil {
        fmt.eprintln("failed to load texture:", file_path, "-", stbi.failure_reason())
        ok = false
        return
    }
    defer stbi.image_free(data)

    tfmt := TextureFormat.RGBA
    switch comp {
        case 1: tfmt = TextureFormat.R
        case 2: tfmt = TextureFormat.RG
        case 3: tfmt = TextureFormat.RGB
        case 4: tfmt = TextureFormat.RGBA
    }
    return texture_2d_create(u32(w), u32(h), tfmt, params, data), true
}

texture_2d_load_memory :: proc(data: rawptr, #any_int size: uint, params: Maybe(TextureParams) = nil) -> (tex: Texture2D, ok: bool) #optional_ok {
    w, h, comp : i32 = 0, 0, 0

    byte_ptr := ([^]byte)(data)   
    data := stbi.load_from_memory(byte_ptr, i32(size), &w, &h, &comp, 0)
    if data == nil {
        fmt.eprintln("failed to load texture:", stbi.failure_reason())
        ok = false
        return
    }
    defer stbi.image_free(data)

    tfmt := TextureFormat.RGBA
    switch comp {
        case 1: tfmt = TextureFormat.R
        case 2: tfmt = TextureFormat.RG
        case 3: tfmt = TextureFormat.RGB
        case 4: tfmt = TextureFormat.RGBA
    }
    return texture_2d_create(u32(w), u32(h), tfmt, params, data), true
}

texture_2d_destroy :: proc(tex: ^Texture2D) {
    if tex.handle == 0 do return
    gl.DeleteTextures(1, &tex.handle)
    tex.width = 0
    tex.height = 0
    tex.handle = 0
}

texture_2d_use :: proc(tex: Texture2D, slot: u32 = 0) {
    gl.ActiveTexture(gl.TEXTURE0 + slot)
    gl.BindTexture(gl.TEXTURE_2D, tex.handle)
}
