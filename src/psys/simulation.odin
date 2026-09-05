package psys

import "core:strings"
import "core:fmt"
import "core:os"
import "core:encoding/json"
import "core:math/rand"
import "core:mem"
import "core:math"
import gl "vendor:OpenGL"
import la "core:math/linalg"

Vertex :: struct {
    position: vec4,
    color: vec4,
    uv: vec4,
}

g_vertices_per_point :: 4
g_indices_per_quad :: 6 // triangles
g_friction_factor :: 0.99
g_max_trail_points :: 16
g_max_over_time_values :: 8
g_max_force_fields :: 16

@(private)
g_particle_mesh_gen_shader: Maybe(Shader)

@(private)
g_trail_mesh_gen_shader: Maybe(Shader)

@(private)
g_particle_shader: Maybe(Shader)

@(private)
g_trail_shader: Maybe(Shader)

TrailPoint :: struct {
    position: vec4,
    color: vec4,
}

TrailMeta :: struct {
    head, count: i32,
    alpha: f32,
    pad: f32,
}

Particle :: struct {
    position: vec3,
    prev_position: vec3,
    acceleration: vec3,

    color: Color,

    scale: f32,
    scale_over_time: f32,
    rotation: f32,

    age: f32,
    lifetime: f32,

    // trail
    trail: [g_max_trail_points]TrailPoint,
    trail_count: int,
    trail_head: int,
}

RenderableParticle :: struct {
    position: vec4,
    color: vec4,
    scale: f32,
    pad0: vec3,
}

@(private="file")
particle_init :: proc(
    p: ^Particle,
    position: vec3,
    velocity: vec3 = vec3{0, 0, 0},
    acceleration: vec3 = vec3{0, 0, 0},
    color: vec4 = vec4{1, 1, 1, 1},
    scale: f32 = 1.0,
    rotation: f32 = 0.0,
    start_life: f32 = 1.0, // one second
) {
    p.position = position
    p.prev_position = position - velocity
    p.acceleration = acceleration
    p.color = color
    p.scale = scale
    p.rotation = rotation
    p.lifetime = start_life
    p.trail_count = 0
    p.trail_head = 0
    for t in 0..<len(p.trail) {
        p.trail[t].position = {position.x, position.y, position.z, 0}
    }
    p.age = 0
}

particle_get_renderable :: proc(p: Particle) -> RenderableParticle {
    t := (p.age / (p.lifetime + 1e-5))
    return RenderableParticle {
        position = vec4{p.position.x, p.position.y, p.position.z, p.rotation},
        color = p.color,
        scale = p.scale * p.scale_over_time,
    }
}

EmitterShape :: enum {
    POINT,
    CIRCLE,
    SPHERE,
}

VelocityMode :: enum { DIRECTIONAL, RADIAL_OUT, RADIAL_IN }

FieldShape :: enum { SPHERE, TUBE }

ForceField :: struct {
    shape: FieldShape,
    repel: bool,

    position: vec3,
    direction: vec3,
    strength: f32,
    radius: f32,
}

Emitter :: struct {
    // spatial
    transform: Transform `json:"-"`,
    shape: EmitterShape,
    radius: f32,
    emit_from_surface: bool,

    // emission control
    particles_per_second: int,
    max_particles: int,
    timer: f32 `json:"-"`,

    // initial velocity
    direction_spread: f32,
    speed: [2]f32,
    velocity_mode: VelocityMode,

    // per-particle spawn ranges
    lifetime: [2]f32,
    rotation: [2]f32,
    scale: [2]f32,
    // TODO: Add angular velocity (maybe) later

    // simulation
    gravity: vec3,
    damping: f32,
    local_space: bool,

    // visual over lifetime
    colors: [g_max_over_time_values]LerpValue(Color),
    colors_count: int,

    scales: [g_max_over_time_values]LerpValue(f32),
    scales_count: int,

    // trail
    trail: struct {
        enabled: bool,
        length: int,
        min_point_distance: f32,
        width_start: f32,
        width_end: f32,
        color_start: Color,
        color_end: Color,
        texture_cap_fraction: f32,
        texture_tiles: f32,
    },

    // force fields
    force_fields: [g_max_force_fields]ForceField,
    force_fields_count: int,
}

ParticleSystem :: struct {
    particles: []Particle `json:"-"`,
    active_count: int `json:"-"`,
    emitter: Emitter,
    rendering: struct {
        particle_vao: u32,
        particle_vbo, particle_ibo: Buffer,
        particle_buffer: Buffer,
        particle_texture: Maybe(Texture2D),

        trail_vao: u32,
        trail_vbo, trail_ibo: Buffer,
        trail_points_buffer: Buffer,
        trail_metas_buffer: Buffer,
        trail_texture: Maybe(Texture2D),
    } `json:"-"`,
}

ParticleSystemFile :: struct {
    capacity: int,
    transform: struct {
        position: vec3,
        rotation: vec4,
    },
    emitter: Emitter,
    renderable: struct {
        texture_path: string,
        trail_texture_path: string,
    },
}

ParticleSetupCallback :: proc(p: ^Particle);

system_create :: proc(#any_int capacity: int) -> ParticleSystem {
    sys := ParticleSystem {
        particles = make([]Particle, capacity),
        active_count = 0,
    }

    p_vao, p_vbo, p_ibo, p_buf := system_create_particle_buffers(capacity)
    t_vao, t_vbo, t_ibo, t_pbuf, t_mbuf := system_create_trail_buffers(capacity)

    sys.rendering = {
        particle_vao = p_vao,
        particle_vbo = p_vbo,
        particle_ibo = p_ibo,
        particle_buffer = p_buf,
        trail_vao = t_vao,
        trail_vbo = t_vbo,
        trail_ibo = t_ibo,
        trail_points_buffer = t_pbuf,
        trail_metas_buffer = t_mbuf,
    }
    sys.emitter = emitter_default()

    return sys
}

@(private="file")
system_create_particle_buffers :: proc(capacity: int) -> (vao: u32, vbo: Buffer, ibo: Buffer, buf: Buffer) {
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    max_vertices := g_vertices_per_point * capacity
    max_indices := g_indices_per_quad * capacity
    vbo = buffer_create_empty(BufferType.ARRAY_BUFFER, max_vertices * size_of(Vertex))
    ibo = buffer_create_empty(BufferType.INDEX_BUFFER, max_indices * size_of(u32))

    buffer_bind(vbo)
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), 0)
    gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Vertex), 4 * size_of(f32))
    gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Vertex), 8 * size_of(f32))

    buffer_bind(ibo)
    gl.BindVertexArray(0)

    buf = buffer_create_empty(BufferType.SSBO, size_of(RenderableParticle) * capacity)

    return
}

@(private="file")
system_create_trail_buffers :: proc(capacity: int) -> (vao: u32, vbo: Buffer, ibo: Buffer, pbuf: Buffer, mbuf: Buffer) {
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    max_vertices := g_max_trail_points * 2 * capacity
    max_indices := (g_max_trail_points * 2 + 1) * capacity
    vbo = buffer_create_empty(BufferType.ARRAY_BUFFER, max_vertices * size_of(Vertex))
    ibo = buffer_create_empty(BufferType.INDEX_BUFFER, max_indices * size_of(u32))

    buffer_bind(vbo)
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), 0)
    gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Vertex), 4 * size_of(f32))
    gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Vertex), 8 * size_of(f32))

    buffer_bind(ibo)

    gl.BindVertexArray(0)

    pbuf = buffer_create_empty(BufferType.SSBO, size_of(TrailPoint) * g_max_trail_points * capacity)
    mbuf = buffer_create_empty(BufferType.SSBO, size_of(TrailMeta) * capacity)

    return
}

system_destroy :: proc(sys: ^ParticleSystem) {
    delete(sys.particles)
    sys.particles = nil

    buffer_destroy(&sys.rendering.particle_vbo)
    buffer_destroy(&sys.rendering.particle_ibo)
    buffer_destroy(&sys.rendering.particle_buffer)

    buffer_destroy(&sys.rendering.trail_vbo)
    buffer_destroy(&sys.rendering.trail_ibo)
    buffer_destroy(&sys.rendering.trail_points_buffer)
    buffer_destroy(&sys.rendering.trail_metas_buffer)

    if sys.rendering.particle_vao != 0 {
        gl.DeleteVertexArrays(1, &sys.rendering.particle_vao)
        sys.rendering.particle_vao = 0
    }

    if sys.rendering.trail_vao != 0 {
        gl.DeleteVertexArrays(1, &sys.rendering.trail_vao)
        sys.rendering.trail_vao = 0
    }

    if tex, ok := &sys.rendering.particle_texture.?; ok {
        texture_2d_destroy(tex)
        sys.rendering.particle_texture = nil
    }

    if tex, ok := &sys.rendering.trail_texture.?; ok {
        texture_2d_destroy(tex)
        sys.rendering.trail_texture = nil
    }

    sys.active_count = 0
}

system_save :: proc(sys: ParticleSystemFile, file_name: string) {
    opt := json.Marshal_Options{
        pretty = true,
        use_enum_names = true,
        use_spaces = true,
        spaces = 4,
    }

    file := sys
    file.transform.position = sys.emitter.transform.position

    rot := sys.emitter.transform.rotation
    file.transform.rotation = {rot.x, rot.y, rot.z, rot.w}

    if data, err := json.marshal(file, opt); err == nil {
        _ = os.write_entire_file(file_name, data)
    }
}

system_load :: proc(file: ParticleSystemFile) -> ParticleSystem {
    tex_params := TextureParams {
        filter = {
            min = .LinearMipLinear,
            mag = .Linear,
        },
        wrap = DEFAULT_TEXTURE_PARAMS.wrap,
    }
    sys := system_create(file.capacity)
    sys.emitter = file.emitter

    transform_init(
        &sys.emitter.transform,
        position = file.transform.position,
        rotation = quaternion(
            imag = file.transform.rotation.x,
            jmag = file.transform.rotation.y,
            kmag = file.transform.rotation.z,
            real = file.transform.rotation.w,
        )
    )

    if len(strings.trim_space(file.renderable.texture_path)) > 0 {
        sys.rendering.particle_texture = texture_2d_load_file(file.renderable.texture_path, tex_params)
    }

    if len(strings.trim_space(file.renderable.trail_texture_path)) > 0 {
        sys.rendering.trail_texture = texture_2d_load_file(file.renderable.trail_texture_path, tex_params)
    }
    return sys
}

system_load_file :: proc(file_name: string) -> ParticleSystemFile {
    file: ParticleSystemFile
    
    if data, err := os.read_entire_file(file_name, context.temp_allocator); err == nil {
        json.unmarshal(data, &file)
    }

    return file
}

system_emit_one :: proc(sys: ^ParticleSystem, dt: f32) {
    if sys.active_count >= len(sys.particles) do return
    if sys.active_count >= sys.emitter.max_particles do return

    p := &sys.particles[sys.active_count]
    
    e := &sys.emitter
    local_pos := emitter_spawn_local_position(e)
    
    spawn_pos := local_pos if e.local_space else transform_point(&e.transform, local_pos)
    init_vel := emitter_spawn_velocity(e, local_pos)

    particle_init(p, spawn_pos)
    p.prev_position = spawn_pos - init_vel * dt
    p.acceleration = e.gravity
    p.rotation = random_range(e.rotation)
    p.scale = random_range(e.scale)
    p.scale_over_time = e.scales[0].value if e.scales_count > 0 else 1.0
    p.color = e.colors[0].value if e.colors_count > 0 else {1, 1, 1, 1}
    p.age = 0
    p.lifetime = random_range(e.lifetime)

    sys.active_count += 1
}

system_update :: proc(sys: ^ParticleSystem, dt: f32) {
    emitter_update(sys, dt)

    e := &sys.emitter
    i := 0
    for i < sys.active_count {
        p := &sys.particles[i]
        p.age += dt

        if p.age >= p.lifetime {
            sys.active_count -= 1
            sys.particles[i] = sys.particles[sys.active_count]
            continue
        }

        p.acceleration = e.gravity

        // apply force fields
        apply_force_fields(p, e, dt)

        velocity := (p.position - p.prev_position) * (1.0 - e.damping * dt)
        new_position := p.position + velocity + p.acceleration * dt * dt

        p.prev_position = p.position
        p.position = new_position

        t := p.age / (p.lifetime + 1e-5)
        p.color = interpolate(e.colors[:e.colors_count], t)
        p.scale_over_time = interpolate(e.scales[:e.scales_count], t)

        update_particle_trail(p, e)

        i += 1
    }
}

@(private="file")
apply_force_fields :: proc(p: ^Particle, e: ^Emitter, dt: f32) {
    if e.force_fields_count <= 0 do return

    for i in 0..<e.force_fields_count {
        ff := &e.force_fields[i]

        diff := ff.position - p.position
        dist := la.length(diff)
        if dist > ff.radius do continue

        vec := diff / dist

        // TODO: Vortex and wind need to apply the force in a tube shape. So base = radius * 2 and heght = distance, oriented at direction.
        // TODO: Implement TUBE shape
        p.acceleration += vec * ff.strength * (-1.0 if ff.repel else 1.0) * dt
    }
}

@(private="file")
update_particle_trail :: proc(p: ^Particle, e: ^Emitter) {
    max_count := min(e.trail.length, g_max_trail_points)
    if !e.trail.enabled || max_count <= 0 do return

    pos := vec4{p.position.x, p.position.y, p.position.z, 0}

    if p.trail_count == 0 {
        p.trail[0].position = pos
        p.trail[1].position = pos
        p.trail_head = 0
        p.trail_count = min(2, max_count)
        return
    }

    anchor_id := (p.trail_head - 1 + g_max_trail_points) % g_max_trail_points
    anchor := p.trail[anchor_id].position.xyz

    if la.length(p.position - anchor) >= e.trail.min_point_distance {
        p.trail_head = (p.trail_head + 1) % g_max_trail_points
        p.trail_count = min(p.trail_count + 1, max_count)
    }

    p.trail[p.trail_head].position = pos
}

system_render :: proc(sys: ^ParticleSystem, proj: mat4, view: mat4) {
    if sys.active_count == 0 do return

    stride := g_max_trail_points

    // Upload to GPU
    system_render_upload_gpu_particles(sys)
    system_render_upload_gpu_trails(sys, stride)

    // Generate meshes
    system_render_generate_particles_mesh(sys, view)
    system_render_generate_trails_mesh(sys, view, stride)
    
    // Draw
    system_render_draw_trails(sys, proj, view, stride)
    system_render_draw_particles(sys, proj, view)
}

@(private="file")
system_render_upload_gpu_particles :: proc(sys: ^ParticleSystem) {
    renderables: [dynamic]RenderableParticle
    defer delete(renderables)

    if sys.emitter.local_space {
        to_world := transform_world_matrix(&sys.emitter.transform)
        for i in 0..<sys.active_count {
            r := particle_get_renderable(sys.particles[i])
            wp := to_world * vec4{r.position.x, r.position.y, r.position.z, 1.0}
            r.position = vec4{wp.x, wp.y, wp.z, r.position.w}
            append(&renderables, r)
        }
    } else {
        for i in 0..<sys.active_count {
            r := particle_get_renderable(sys.particles[i])
            append(&renderables, r)
        }
    }

    buffer_bind(sys.rendering.particle_buffer)
    buffer_update(
        sys.rendering.particle_buffer,
        mem.slice_to_bytes(renderables[:]),
    )
}

@(private="file")
system_render_upload_gpu_trails :: proc(sys: ^ParticleSystem, stride: int) {
    e := &sys.emitter
    if !e.trail.enabled || e.trail.length <= 0 do return

    n := sys.active_count
    points := make([]TrailPoint, n * stride)
    metas := make([]TrailMeta, n)
    defer delete(points)
    defer delete(metas)

    for i in 0..<n {
        p := &sys.particles[i]
        dst := points[i * stride : (i + 1) * stride]
        src := p.trail[:stride]
        
        if e.local_space {
            to_world := transform_world_matrix(&sys.emitter.transform)
            for k in 0..<stride {
                sp := src[k].position
                wp := to_world * vec4{sp.x, sp.y, sp.z, 1.0}
                dst[k].position = vec4{wp.x, wp.y, wp.z, sp.w}
                dst[k].color = src[k].color
            }
        } else {
            copy(dst, src)
        }

        life_t := p.age / (p.lifetime + 1e-5)
        metas[i] = {
            head = i32(p.trail_head),
            count = i32(min(p.trail_count, e.trail.length, stride)),
            alpha = math.lerp(p.color.a, p.color.a, life_t),
        }
    }

    buffer_bind(sys.rendering.trail_points_buffer)
    buffer_update(sys.rendering.trail_points_buffer, mem.slice_to_bytes(points[:]))
    buffer_bind(sys.rendering.trail_metas_buffer)
    buffer_update(sys.rendering.trail_metas_buffer, mem.slice_to_bytes(metas[:]))
}

@(private="file")
system_render_generate_particles_mesh :: proc(sys: ^ParticleSystem, view: mat4) {
    inv_view := la.inverse(view)

    particle_gen_shader := particle_mesh_gen_shader_get()

    shader_use(particle_gen_shader^)
    shader_set_mat4(particle_gen_shader, "uInvView", inv_view)
    shader_set_int(particle_gen_shader, "uParticleCount", sys.active_count)

    buffer_bind_base(sys.rendering.particle_vbo, BufferBaseTarget.SSBO, 0)
    buffer_bind_base(sys.rendering.particle_ibo, BufferBaseTarget.SSBO, 1)
    buffer_bind_base(sys.rendering.particle_buffer, BufferBaseTarget.SSBO, 2)

    num_groups := (sys.active_count + 255) / 256
    gl.DispatchCompute(u32(num_groups), 1, 1)

    gl.MemoryBarrier(gl.VERTEX_ATTRIB_ARRAY_BARRIER_BIT | gl.ELEMENT_ARRAY_BARRIER_BIT)
}

@(private="file")
system_render_generate_trails_mesh :: proc(sys: ^ParticleSystem, view: mat4, stride: int) {
    e := &sys.emitter
    if !e.trail.enabled || e.trail.length <= 0 do return

    inv_view := la.inverse(view)

    trail_gen_shader := trail_mesh_gen_shader_get()

    shader_use(trail_gen_shader^)
    shader_set_mat4(trail_gen_shader, "uInvView", inv_view)
    shader_set_int(trail_gen_shader, "uParticleCount", sys.active_count)
    shader_set_int(trail_gen_shader, "uTrailLength", stride)
    shader_set_float(trail_gen_shader, "uWidthStart", e.trail.width_start)
    shader_set_float(trail_gen_shader, "uWidthEnd", e.trail.width_end)
    shader_set_vec4(trail_gen_shader, "uColorStart", e.trail.color_start)
    shader_set_vec4(trail_gen_shader, "uColorEnd", e.trail.color_end)

    buffer_bind_base(sys.rendering.trail_vbo, BufferBaseTarget.SSBO, 0)
    buffer_bind_base(sys.rendering.trail_ibo, BufferBaseTarget.SSBO, 1)
    buffer_bind_base(sys.rendering.trail_points_buffer, BufferBaseTarget.SSBO, 2)
    buffer_bind_base(sys.rendering.trail_metas_buffer, BufferBaseTarget.SSBO, 3)

    num_groups := (sys.active_count + 255) / 256
    gl.DispatchCompute(u32(num_groups), 1, 1)

    gl.MemoryBarrier(gl.VERTEX_ATTRIB_ARRAY_BARRIER_BIT | gl.ELEMENT_ARRAY_BARRIER_BIT)
}

@(private="file")
system_render_draw_particles :: proc(sys: ^ParticleSystem, proj: mat4, view: mat4) {
    part_shader := particle_shader_get()

    shader_use(part_shader^)
    if tex, ok := sys.rendering.particle_texture.?; ok {
        texture_2d_use(tex, 0)
        shader_set_int(part_shader, "uTexture", 0)
        shader_set_int(part_shader, "uHasTexture", 1)
    } else {
        gl.BindTexture(gl.TEXTURE_2D, 0)
        shader_set_int(part_shader, "uHasTexture", 0)
    }

    shader_set_mat4(part_shader, "uProj", proj)
    shader_set_mat4(part_shader, "uView", view)

    gl.BindVertexArray(sys.rendering.particle_vao)

    gl.DepthMask(false)

    indices_count := g_indices_per_quad * sys.active_count
    gl.DrawElements(gl.TRIANGLES, i32(indices_count), gl.UNSIGNED_INT, nil)

    gl.DepthMask(true)
}

@(private="file")
system_render_draw_trails :: proc(sys: ^ParticleSystem, proj: mat4, view: mat4, stride: int) {
    if !sys.emitter.trail.enabled || sys.emitter.trail.length <= 0 do return

    trail_shader := trail_shader_get()

    shader_use(trail_shader^)
    if tex, ok := sys.rendering.trail_texture.?; ok {
        texture_2d_use(tex, 0)
        shader_set_int(trail_shader, "uTexture", 0)
        shader_set_int(trail_shader, "uHasTexture", 1)
    } else {
        gl.BindTexture(gl.TEXTURE_2D, 0)
        shader_set_int(trail_shader, "uHasTexture", 0)
    }

    shader_set_mat4(trail_shader, "uProj", proj)
    shader_set_mat4(trail_shader, "uView", view)

    shader_set_float(trail_shader, "uCapFraction", sys.emitter.trail.texture_cap_fraction)
    shader_set_float(trail_shader, "uTiles", sys.emitter.trail.texture_tiles)

    gl.BindVertexArray(sys.rendering.trail_vao)

    gl.DepthMask(false)
    gl.Enable(gl.PRIMITIVE_RESTART_FIXED_INDEX)

    count := sys.active_count * (stride * 2 + 1) // 2 vertices + 1 restart idx
    gl.DrawElements(gl.TRIANGLE_STRIP, i32(count), gl.UNSIGNED_INT, nil)

    gl.Disable(gl.PRIMITIVE_RESTART_FIXED_INDEX)
    gl.DepthMask(true)
}

@(private="file")
particle_mesh_gen_shader_get :: proc() -> ^Shader {
    shader, ok := &g_particle_mesh_gen_shader.?
    if !ok {
        src := #load("shaders/particle_mesh_gen.comp", string)
        g_particle_mesh_gen_shader = shader_create()
        shader_load_compute(&g_particle_mesh_gen_shader.(Shader), src)
        shader_link(&g_particle_mesh_gen_shader.(Shader))
        return &g_particle_mesh_gen_shader.(Shader)
    }
    return shader
}

@(private="file")
trail_mesh_gen_shader_get :: proc() -> ^Shader {
    shader, ok := &g_trail_mesh_gen_shader.?
    if !ok {
        src := #load("shaders/trail_mesh_gen.comp", string)
        g_trail_mesh_gen_shader = shader_create()
        shader_load_compute(&g_trail_mesh_gen_shader.(Shader), src)
        shader_link(&g_trail_mesh_gen_shader.(Shader))
        return &g_trail_mesh_gen_shader.(Shader)
    }
    return shader
}

@(private="file")
particle_shader_get :: proc() -> ^Shader {
    shader, ok := &g_particle_shader.?
    if !ok {
        vsrc := #load("shaders/particle.vert", string)
        fsrc := #load("shaders/particle.frag", string)
        g_particle_shader = shader_create()
        shader_load_vertex(&g_particle_shader.(Shader), vsrc)
        shader_load_fragment(&g_particle_shader.(Shader), fsrc)
        shader_link(&g_particle_shader.(Shader))
        return &g_particle_shader.(Shader)
    }
    return shader
}

@(private="file")
trail_shader_get :: proc() -> ^Shader {
    shader, ok := &g_trail_shader.?
    if !ok {
        vsrc := #load("shaders/particle.vert", string)
        fsrc := #load("shaders/trail.frag", string)
        g_trail_shader = shader_create()
        shader_load_vertex(&g_trail_shader.(Shader), vsrc)
        shader_load_fragment(&g_trail_shader.(Shader), fsrc)
        shader_link(&g_trail_shader.(Shader))
        return &g_trail_shader.(Shader)
    }
    return shader
}

// Emitter
emitter_default :: proc() -> Emitter {
    e := Emitter{
        shape             = .POINT,
        radius            = 1.0,
        emit_from_surface = false,

        particles_per_second = 1,
        max_particles         = 100,
        timer                 = 0,

        direction_spread = 0,
        speed            = {1.0, 2.0},
        velocity_mode    = .DIRECTIONAL,

        lifetime = {0.1, 1.0},
        rotation = {0, 0},
        scale = {1, 0},

        gravity      = {0, 0, 0},
        damping      = 0.0,
        local_space  = false,

        colors = { // fade to transparent, a common sane default
            {stop = 0.0, value = {1, 1, 1, 1}},
            {stop = 1.0, value = {1, 1, 1, 0}},
            {}, {}, {}, {}, {}, {},
        },
        colors_count = 2,

        trail = {
            enabled = false,
            color_start = {1, 1, 1, 1},
            color_end = {1, 1, 1, 0},
            width_start = 0.1,
            width_end = 0.1,
            length = 16,
            min_point_distance = 0.2,
            texture_cap_fraction = 0.25,
            texture_tiles = 4.0,
        }
    }
    transform_init(&e.transform)
    return e
}

@(private)
rand_unit_vec3 :: proc() -> vec3 {
    z := rand.float32_range(-1, 1)
    a := rand.float32_range(0, math.TAU)
    r := math.sqrt(max(0, 1 - z*z))
    return vec3{r * math.cos(a), r * math.sin(a), z}
}

@(private)
random_range :: proc(range: [2]f32) -> f32 {
    return rand.float32_uniform(range[0], range[1])
}

@(private)
emitter_spawn_local_position :: proc(e: ^Emitter) -> vec3 {
    switch e.shape {
        case .POINT: return vec3{0,0,0}
        case .CIRCLE: {
            angle := rand.float32_uniform(0, math.TAU)
            r := e.radius
            if !e.emit_from_surface {
                r *= math.sqrt(rand.float32_uniform(0, 1))
            }
            return vec3{
                math.cos(angle) * r, 0, math.sin(angle) * r
            }
        }
        case .SPHERE: {
            dir := rand_unit_vec3()
            r := e.radius
            if !e.emit_from_surface {
                r *= math.pow(rand.float32_uniform(0, 1), 1.0 / 3.0)
            }
            return dir * r
        }
    }
    return {0,0,0}
}

@(private)
emitter_spawn_velocity :: proc(e: ^Emitter, local_pos: vec3) -> vec3 {
    speed := random_range(e.speed)

    // local_pos is in emitter space, so the direction is built there too and
    // then rotated into world space unless the particle stays in local space.
    // The emitter's own forward axis in that space is -Z; transform_forward
    // must not be used here, it reports the axis in the parent's space.
    fwd := vec3{0, 1, 0}

    dir: vec3
    switch e.velocity_mode {
        case .DIRECTIONAL: dir = spread_direction(fwd, e.direction_spread)
        case .RADIAL_OUT: dir = la.normalize(local_pos) if local_pos != {0,0,0} else fwd
        case .RADIAL_IN: dir = la.normalize(-local_pos) if local_pos != {0,0,0} else -fwd
    }

    if !e.local_space {
        dir = la.quaternion_mul_vector3(transform_world_rotation(e.transform), dir)
    }

    return dir * speed
}

@(private)
spread_direction :: proc(base: vec3, spread: f32) -> vec3 {
    if spread == 0 do return la.normalize(base)

    base_n := la.normalize(base)

    up := vec3{0,1,0}
    if math.abs(la.dot(base_n, up)) > 0.99 do up = vec3{1,0,0}

    right := la.normalize(la.cross(up, base_n))
    fwd_up := la.cross(base_n, right)

    theta := rand.float32_uniform(0, spread)
    phi := rand.float32_uniform(0, math.TAU)
    s := math.sin(theta)

    return la.normalize(
        base_n * math.cos(theta) +
        right * (s * math.cos(phi)) +
        fwd_up * (s * math.sin(phi)),
    )
}

@(private)
emitter_update :: proc(sys: ^ParticleSystem, dt: f32) {
    e := &sys.emitter

    if e.particles_per_second <= 0 do return

    e.timer += dt
    spawn_interval := 1.0 / f32(e.particles_per_second)

    for e.timer >= spawn_interval {
        e.timer -= spawn_interval
        system_emit_one(sys, dt)
    }
}
