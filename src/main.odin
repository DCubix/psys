#+feature dynamic-literals

package src

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:math"
import "core:fmt"

import la "core:math/linalg"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"
import mu "vendor:microui"

import "psys"

g_time_step :: 1.0 / 60.0

g_grid_size :: 16
g_max_points :: 8192

shape_type_options := map[psys.EmitterShape]string{
    .POINT = "Point",
    .CIRCLE = "Circle",
    .SPHERE = "Sphere",
}

velocity_mode_options := map[psys.VelocityMode]string{
    .DIRECTIONAL = "Directional",
    .RADIAL_IN = "Radial In",
    .RADIAL_OUT = "Radial Out",
}

// what the texture picker offers, stb_image's formats first
texture_file_filters := [?]FileFilter{
    {
        name = "Images",
        extensions = {"png", "jpg", "jpeg", "bmp", "tga", "psd", "gif", "hdr", "pic", "pnm", "ppm", "pgm"},
    },
}

psys_file_filters := [?]FileFilter{
    {
        name = "Particle Systems",
        extensions = {"psys"},
    },
}

proj_file_filters := [?]FileFilter{
    {
        name = "PSYS Projects",
        extensions = {"psysproj"},
    },
}

PSYS :: struct {
    name: string,
    sys: psys.ParticleSystem,
    file: psys.ParticleSystemFile,
}

PSYS_FileEntry :: struct {
    name: string,
    psys_file: psys.ParticleSystemFile,
}

ProjectFile :: struct {
    systems: []PSYS_FileEntry,
}

App :: struct {
    systems: []PSYS,
    systems_count: int,
    selected: string,
}

app_create :: proc() -> App {
    return App {
        systems = make([]PSYS, 64),
        selected = ""
    }
}

app_load :: proc(file: ProjectFile) -> App {
    app := app_create()
    for i in 0..<len(file.systems) {
        pe := file.systems[i]
        ps := app_add_system(&app, pe.name)
        ps.file = pe.psys_file
        psys.system_destroy(&ps.sys)
        ps.sys = psys.system_load(ps.file)
    }
    return app
}

app_destroy :: proc (app: ^App) {
    for i in 0..<app.systems_count {
        app_delete_system(app, app.systems[i].name)
    }
    delete(app.systems)
    app.systems_count = 0
}

app_get_system :: proc(app: ^App, name: string) -> (ps: ^PSYS, idx: int, ok: bool) {
    for i in 0..<app.systems_count {
        if app.systems[i].name == name {
            return &app.systems[i], i, true
        }
    }
    return nil, -1, false
}

app_add_system :: proc(app: ^App, name: string) -> ^PSYS {
    if app.systems_count >= len(app.systems) do return nil
    app.systems[app.systems_count] = PSYS {
        name = name,
        sys = psys.system_create(g_max_points),
        file = {
            capacity = g_max_points,
        }
    }
    app.systems_count += 1
    return &app.systems[app.systems_count-1]
}

app_delete_system :: proc(app: ^App, name: string) {
    ps, idx, ok := app_get_system(app, name)
    if !ok do return

    delete(ps.name)
    psys.system_destroy(&ps.sys)

    app.systems[idx] = app.systems[app.systems_count-1]
    app.systems_count -= 1
}

main :: proc() {
    if !sdl.Init({ .VIDEO, .EVENTS }) {
        fmt.eprintfln("SDL initialization failed: %s", sdl.GetError())
        return
    }
    defer sdl.Quit()

    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 6)
    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GL_CONTEXT_PROFILE_CORE))

    sdl.GL_SetAttribute(.RED_SIZE, 8)
    sdl.GL_SetAttribute(.GREEN_SIZE, 8)
    sdl.GL_SetAttribute(.BLUE_SIZE, 8)
    sdl.GL_SetAttribute(.ALPHA_SIZE, 8)
    sdl.GL_SetAttribute(.DEPTH_SIZE, 24)

    window := sdl.CreateWindow("PSYS", 1280, 720, {.OPENGL})
    if window == nil {
        fmt.eprintfln("Failed to create window: %s", sdl.GetError())
        return
    }
    defer sdl.DestroyWindow(window)

    _ = sdl.StartTextInput(window)

    ctx := sdl.GL_CreateContext(window)
    if ctx == nil {
        fmt.eprintfln("Failed to create OpenGL context: %s", sdl.GetError())
        return
    }
    defer sdl.GL_DestroyContext(ctx)

    sdl.GL_MakeCurrent(window, ctx)

    gl.load_up_to(4, 6, sdl.gl_set_proc_address)

    current_time :: proc() -> f64 {
        return f64(sdl.GetTicksNS()) * 1e-9
    }

    // MicroUI
    muvg := microui_nanovg_create()
    defer microui_nanovg_destroy(muvg)
    ui := muvg.ui; vg := muvg.vg

    // Input handler setup
    ih := psys.input_handler_create(window)
    defer psys.input_handler_destroy(&ih)
    psys.input_handler_register_processor(&ih, microui_processor(ui))

    // App setup
    app := app_create()
    defer app_destroy(&app)

    // Setup camera
    cam := psys.Camera {
        fov = math.to_radians_f32(60.0),
        aspect = 1280.0 / 720.0,
        z_near = 0.01,
        z_far = 500.0,
    }
    psys.transform_init(&cam, psys.vec3{ 0.0, 0.0, 10.0 })

    pivot: psys.Transform
    psys.transform_init(&pivot)
    pivot.rotation =
        la.quaternion_angle_axis(math.to_radians_f32(45.0), psys.vec3{0,1,0}) *
        la.quaternion_angle_axis(math.to_radians_f32(-30.0), psys.vec3{1,0,0})

    cam.parent = &pivot

    // Setup debug draw
    dd := psys.DebugDraw{}
    if !psys.debug_draw_init(&dd) {
        fmt.eprintln("debug draw init failed")
        return
    }
    defer psys.debug_draw_destroy(&dd)

    // Setup texture
    tex_params := psys.TextureParams {
        filter = {
            min = psys.TextureFilter.LinearMipLinear,
            mag = psys.TextureFilter.Linear,
        },
        wrap = psys.DEFAULT_TEXTURE_PARAMS.wrap,
    }

    // File dialog state
    particle_texture_dlg: FileDialog
    defer file_dialog_destroy(&particle_texture_dlg)

    trail_texture_dlg: FileDialog
    defer file_dialog_destroy(&trail_texture_dlg)

    psys_dlg: FileDialog
    defer file_dialog_destroy(&psys_dlg)

    project_dlg: FileDialog
    defer file_dialog_destroy(&project_dlg)

    // Game loop
    last_time := current_time()
    accumulator := 0.0

    mouse_pos := psys.vec2{0,0}
    prev_mouse_pos := psys.vec2{0,0}

    for !ih.quit_requested {
        can_render := false
        current_time := current_time()
        delta := current_time - last_time
        last_time = current_time
        accumulator += delta

        psys.input_handler_poll(&ih)

        for accumulator >= g_time_step {
            accumulator -= g_time_step

            mouse_pos = psys.get_mouse_position()

            // camera input handling
            if psys.is_button_held(ih, 1) {
                md := mouse_pos - prev_mouse_pos
                pivot.rotation = la.quaternion_angle_axis(
                    math.to_radians_f32(-md.x * 0.6), psys.vec3{0,1,0}
                ) * pivot.rotation
                pivot.rotation = pivot.rotation * la.quaternion_angle_axis(
                    math.to_radians_f32(-md.y * 0.6), psys.vec3{1,0,0}
                )
            }

            if math.abs(ih.wheel.y) > 0.0 {
                cam.position.z -= ih.wheel.y * 0.25
            }

            for i in 0..<app.systems_count {
                ps := &app.systems[i]
                psys.system_update(&ps.sys, f32(g_time_step))
            }

            prev_mouse_pos = mouse_pos
            psys.input_handler_end_frame(&ih)
            can_render = true
        }

        if can_render {
            proj := psys.camera_projection_matrix(cam)
            view := psys.transform_view_matrix(cam)

            gl.Disable(gl.CULL_FACE)
            gl.Enable(gl.DEPTH_TEST)
            gl.Enable(gl.BLEND)
            gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)
            gl.BlendEquation(gl.FUNC_ADD)
            
            gl.ClearColor(0.0, 0.0, 0.1, 1.0)
            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

            /// Debug draw
            half_grid := g_grid_size / 2
            for i in 0..=g_grid_size {
                j := i - g_grid_size / 2
                col := psys.Color{0.25, 0.25, 0.25, 1.0}
                if j == 0 || j == half_grid || j == -half_grid {
                    col = psys.Color{0.35, 0.35, 0.35, 1.0}
                }
                psys.debug_draw_line(
                    &dd,
                    psys.vec3{f32(j), 0.0, -f32(half_grid)},
                    psys.vec3{f32(j), 0.0,  f32(half_grid)},
                    col
                )
                psys.debug_draw_line(
                    &dd,
                    psys.vec3{-f32(half_grid), 0.0, f32(j)},
                    psys.vec3{ f32(half_grid), 0.0, f32(j)},
                    col
                )
            }

            if ps, _, ok := app_get_system(&app, app.selected); ok {
                e := &ps.sys.emitter
                emitter_pos := psys.transform_world_position(e.transform)
                
                // Debug draw emitter
                switch e.shape {
                    case .POINT: {
                        n := psys.transform_up(e.transform)
                        psys.debug_draw_cross(&dd, emitter_pos, 0.2, {0,1,1,0.7})
                        psys.debug_draw_arrow(
                            &dd,
                            emitter_pos,
                            n,
                            1.0,
                            {1,1,0,0.7}
                        )
                    }
                    case .CIRCLE: {
                        n := psys.transform_up(e.transform)
                        psys.debug_draw_circle(
                            &dd,
                            emitter_pos,
                            e.radius,
                            n,
                            {0,1,1,0.7}
                        )
                        psys.debug_draw_arrow(
                            &dd,
                            emitter_pos,
                            n,
                            1.0,
                            {1,1,0,0.7}
                        )
                    }
                    case .SPHERE: {
                        psys.debug_draw_sphere(
                            &dd,
                            emitter_pos,
                            e.radius,
                            {0,1,1,0.7}
                        )
                    }
                }

                for i in 0..<ps.sys.active_count {
                    p := ps.sys.particles[i]
                    xf: psys.Transform
                    psys.transform_init(&xf, p.position)
                    psys.debug_draw_axes(&dd, xf, 0.2)
                }
            }

            psys.debug_draw_flush(&dd, proj, view)

            for i in 0..<app.systems_count {
                ps := &app.systems[i]
                psys.system_render(&ps.sys, proj, view)
            }

            context.user_ptr = vg
            mu.begin(ui)

            w, h: i32
            sdl.GetWindowSize(window, &w, &h)
            color_picker_set_viewport(w, h)

            opt: mu.Options = {.NO_CLOSE}
            if mu.begin_window(ui, "Particle Systems", {w - 220, 20, 200, 500}, opt) {
                defer mu.end_window(ui)

                mu.layout_row_items(ui, 2)
                if .SUBMIT in mu.button(ui, "Add") {
                    tag := fmt.aprintf("System#%d", app.systems_count)
                    app_add_system(&app, tag)
                    app.selected = tag
                }
                if .SUBMIT in mu.button(ui, "Delete") && len(app.selected) > 0 {
                    app_delete_system(&app, app.selected)
                }

                row_h := ui.style.size.y + ui.style.padding * 2
                list_bottom := (row_h + ui.style.spacing + 2)
                mu.layout_row(ui, {-1}, -list_bottom)
                mu.begin_panel(ui, "systems")
                mu.layout_row(ui, {-1}, row_h)

                for i in 0..<app.systems_count {
                    ps := &app.systems[i]
                    if .SUBMIT in file_dialog_row(ui, ps.name, app.selected == ps.name) {
                        app.selected = ps.name
                    }
                }

                if app.systems_count == 0 {
                    mu.label(ui, "No particle systems added.")
                }
                mu.end_panel(ui)

                bw := slice_width(ui, 2, 0, 0)
                mu.layout_row(ui, {bw, bw})
                if .SUBMIT in mu.button(ui, "Open Project") {
                    file_dialog_open(&project_dlg, .OPEN, filters = proj_file_filters[:])
                }
                if .SUBMIT in mu.button(ui, "Save Project") {
                    file_dialog_open(&project_dlg, .SAVE, filters = proj_file_filters[:])
                }
            }
            
            if ps, _, ok := app_get_system(&app, app.selected); ok {
                e := &ps.sys.emitter
                opt = {}
                if mu.begin_window(ui, "Selected Settings", {20, 20, 300, 680}, opt) {
                    defer mu.end_window(ui)

                    col_width :: 100
                    if mu.header(ui, "Spatial", {.EXPANDED}) != {} {
                        sw := slice_width(ui, 3, col_width, 1)
                        mu.layout_row(ui, {col_width, sw, sw, sw})
                        mu.label(ui, "Position")
                        mu.number(ui, &e.transform.position.x, 0.01)
                        mu.number(ui, &e.transform.position.y, 0.01)
                        mu.number(ui, &e.transform.position.z, 0.01)

                        rx, ry, rz := la.euler_angles_from_quaternion(e.transform.rotation, .XYZ)
                        mu.layout_row(ui, {col_width, sw, sw, sw})
                        mu.label(ui, "Rotation (euler)")
                        crx := mu.number(ui, &rx, 0.01)
                        cry := mu.number(ui, &ry, 0.01)
                        crz := mu.number(ui, &rz, 0.01)

                        if crx & {.SUBMIT, .CHANGE} != {} ||
                        cry & {.SUBMIT, .CHANGE} != {} ||
                        crz & {.SUBMIT, .CHANGE} != {} {
                            e.transform.rotation = la.quaternion_from_euler_angles(rx, ry, rz, .XYZ)
                        }

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Shape")
                        menu_button(ui, "shape_type", &e.shape, shape_type_options)

                        if e.shape != .POINT {
                            mu.layout_row(ui, {col_width, -1})
                            mu.label(ui, "Radius")
                            mu.number(ui, &e.radius, 0.01)
                        }

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "")
                        mu.checkbox(ui, "Emit from surface", &e.emit_from_surface)
                    }

                    if mu.header(ui, "Particle", {.EXPANDED}) != {} {
                        sw := slice_width(ui, 2, col_width, 1)
                        mu.layout_row(ui, {col_width, i32(sw), i32(sw)})
                        mu.label(ui, "Lifetime (lo/hi)")
                        mu.number(ui, &e.lifetime[0], 0.1, "%.1f")
                        mu.number(ui, &e.lifetime[1], 0.1, "%.1f")
                        if e.lifetime[0] > e.lifetime[1] {
                            e.lifetime[0], e.lifetime[1] = e.lifetime[1], e.lifetime[0]
                        }

                        mu.layout_row(ui, {col_width, i32(sw), i32(sw)})
                        mu.label(ui, "Rotation (lo/hi rad.)")
                        mu.number(ui, &e.rotation[0], 0.1, "%.1f")
                        mu.number(ui, &e.rotation[1], 0.1, "%.1f")
                        if e.rotation[0] > e.rotation[1] {
                            e.rotation[0], e.rotation[1] = e.rotation[1], e.rotation[0]
                        }

                        mu.layout_row(ui, {col_width, i32(sw), i32(sw)})
                        mu.label(ui, "Scale (lo/hi)")
                        mu.number(ui, &e.scale_start, 0.01, "%.2f")
                        mu.number(ui, &e.scale_end, 0.01, "%.2f")

                        mu.layout_row(ui, {-1})
                        mu.label(ui, "Color over Lifetime")
                        color_stops_edit(ui, e.colors[:], &e.colors_count)

                        mu.push_id(ui, "particle_texture")
                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Texture")
                        if .SUBMIT in mu.button(ui, "Browse...") {
                            file_dialog_open(&particle_texture_dlg, .OPEN, filters = texture_file_filters[:])
                        }
                        mu.pop_id(ui)
                    }

                    if mu.header(ui, "Emission", {.EXPANDED}) != {} {
                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Particles/Sec.")

                        pps := f32(e.particles_per_second)
                        if mu.number(ui, &pps, 1.0, "%.0f") & {.SUBMIT, .CHANGE} != {} {
                            e.particles_per_second = int(pps)
                        }

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Max. Particles")

                        mp := f32(e.max_particles)
                        if mu.number(ui, &mp, 1.0, "%.0f") & {.SUBMIT, .CHANGE} != {} {
                            e.max_particles = int(mp)
                        }

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Dir. Spread")
                        mu.number(ui, &e.direction_spread, 0.01)

                        sw := slice_width(ui, 2, col_width, 1)
                        mu.layout_row(ui, {col_width, i32(sw), i32(sw)})
                        mu.label(ui, "Speed (lo/hi)")
                        mu.number(ui, &e.speed[0], 0.1, "%.1f")
                        mu.number(ui, &e.speed[1], 0.1, "%.1f")
                        if e.speed[0] > e.speed[1] do e.speed[0], e.speed[1] = e.speed[1], e.speed[0]

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Velocity Mode")
                        menu_button(ui, "vel_mode", &e.velocity_mode, velocity_mode_options)

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "")
                        mu.checkbox(ui, "Trails", &e.trail.enabled)

                        if e.trail.enabled {
                            tlen := f32(e.trail.length)
                            mu.layout_row(ui, {col_width, -1})
                            mu.label(ui, "Trail Length")
                            if mu.number(ui, &tlen, 1.0, "%.0f") & {.SUBMIT, .CHANGE} != {} {
                                e.trail.length = clamp(int(tlen), 1, psys.g_max_trail_points)
                            }

                            mu.layout_row(ui, {col_width, -1})
                            mu.label(ui, "Min. Point Distance")
                            mu.number(ui, &e.trail.min_point_distance, 0.01)
                            e.trail.min_point_distance = math.max(0.0, e.trail.min_point_distance)

                            nw := slice_width(ui, 2, col_width, 1)
                            mu.layout_row(ui, {col_width, nw, nw})
                            mu.label(ui, "Width (lo/hi)")
                            mu.number(ui, &e.trail.width_start, 0.01)
                            mu.number(ui, &e.trail.width_end, 0.01)
                            e.trail.width_start = math.max(0.0, e.trail.width_start)
                            e.trail.width_end = math.max(0.0, e.trail.width_end)

                            mu.layout_row(ui, {col_width, -1})
                            mu.label(ui, "Start Color")
                            color_edit(ui, &e.trail.color_start)

                            mu.layout_row(ui, {col_width, -1})
                            mu.label(ui, "End Color")
                            color_edit(ui, &e.trail.color_end)

                            mu.push_id(ui, "trail_texture")
                            mu.layout_row(ui, {col_width, -1})
                            mu.label(ui, "Texture")
                            if .SUBMIT in mu.button(ui, "Browse...") {
                                file_dialog_open(&trail_texture_dlg, .OPEN, filters = texture_file_filters[:])
                            }
                            
                            if tx, ok := &ps.sys.rendering.trail_texture.?; ok {
                                mu.layout_row(ui, {col_width, -1})
                                mu.label(ui, "")
                                if .SUBMIT in mu.button(ui, "Remove") {
                                    psys.texture_2d_destroy(tx)
                                    ps.sys.rendering.trail_texture = nil
                                }

                                mu.layout_row(ui, {col_width, -1})
                                mu.label(ui, "Cap Frac.")
                                mu.slider(ui, &e.trail.texture_cap_fraction, 0.0, 0.5, 0.01)

                                mu.layout_row(ui, {col_width, -1})
                                mu.label(ui, "Tiling")
                                mu.number(ui, &e.trail.texture_tiles, 0.1)
                            }
                            mu.pop_id(ui)
                        }
                    }

                    if mu.header(ui, "Simulation", {.EXPANDED}) != {} {
                        sw := slice_width(ui, 3, col_width, 1)
                        mu.layout_row(ui, {col_width, i32(sw), i32(sw), i32(sw)})
                        mu.label(ui, "Gravity (xyz)")
                        mu.number(ui, &e.gravity[0], 0.1, "%.1f")
                        mu.number(ui, &e.gravity[1], 0.1, "%.1f")
                        mu.number(ui, &e.gravity[2], 0.1, "%.1f")

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "Damping")
                        mu.slider(ui, &e.damping, 0.0, 1.0, 0.01)

                        mu.layout_row(ui, {col_width, -1})
                        mu.label(ui, "")
                        mu.checkbox(ui, "Local space", &e.local_space)
                    }

                    mu.layout_row(ui, {-1})
                    mu.label(ui, "Load/Save a single Particle System")

                    aw := slice_width(ui, 2, 0, 0)
                    mu.layout_row(ui, {aw, aw})
                    if .SUBMIT in mu.button(ui, "Load") {
                        file_dialog_open(&psys_dlg, .OPEN, filters = psys_file_filters[:])
                    }
                    if .SUBMIT in mu.button(ui, "Save") {
                        file_dialog_open(&psys_dlg, .SAVE, filters = psys_file_filters[:])
                    }
                }

                if file_name, res := file_dialog(ui, &particle_texture_dlg, "Particle Texture"); res == .ACCEPT {
                    if new_tex, ok := psys.texture_2d_load_file(file_name, tex_params); ok {
                        ps.sys.rendering.particle_texture = new_tex
                        ps.file.renderable.texture_path = file_name
                    } else {
                        fmt.eprintfln("failed to load texture: %s", file_name)
                    }
                }

                if file_name, res := file_dialog(ui, &trail_texture_dlg, "Trail Texture"); res == .ACCEPT {
                    if new_tex, ok := psys.texture_2d_load_file(file_name, tex_params); ok {
                        ps.sys.rendering.trail_texture = new_tex
                        ps.file.renderable.trail_texture_path = file_name
                    } else {
                        fmt.eprintfln("failed to load texture: %s", file_name)
                    }
                }

                if file_name, res := file_dialog(ui, &psys_dlg, "Particle System"); res == .ACCEPT {
                    if psys_dlg.mode == .SAVE {
                        if len(filepath.ext(file_name)) == 0 {
                            file_name = fmt.tprint(file_name, ".psys", sep="")
                        }
                        ps.file.emitter = ps.sys.emitter
                        psys.system_save(ps.file, file_name)
                    } else {
                        psys.system_destroy(&ps.sys)
                        ps.file = psys.system_load_file(file_name)
                        ps.sys = psys.system_load(ps.file)
                    }
                }
            }

            if file_name, res := file_dialog(ui, &project_dlg, "Project"); res == .ACCEPT {
                if project_dlg.mode == .SAVE {
                    if len(filepath.ext(file_name)) == 0 {
                        file_name = fmt.tprint(file_name, ".psysproj", sep="")
                    }
                    
                    opt := json.Marshal_Options{
                        pretty = true,
                        use_enum_names = true,
                        use_spaces = true,
                        spaces = 4,
                    }
                    proj_file := ProjectFile {
                        systems = make([]PSYS_FileEntry, app.systems_count),
                    }
                    for i in 0..<app.systems_count {
                        psy := &proj_file.systems[i]
                        asy := &app.systems[i]

                        psy.name = asy.name

                        psy.psys_file = asy.file
                        psy.psys_file.emitter = asy.sys.emitter
                    }
                    if data, err := json.marshal(proj_file, opt); err == nil {
                        _ = os.write_entire_file(file_name, data)
                    }
                } else {
                    if data, err := os.read_entire_file(file_name, context.temp_allocator); err == nil {
                        proj_file: ProjectFile
                        jerr := json.unmarshal(data, &proj_file)
                        if jerr == nil {
                            app_destroy(&app)
                            app = app_load(proj_file)
                        }
                    }
                }
            }

            mu.end(ui)

            microui_nanovg_render(muvg, 1280.0, 720.0)

            sdl.GL_SwapWindow(window)
        }

        free_all(context.temp_allocator)
    }
}

menu_button :: proc(ui: ^mu.Context, name: string, value: ^$T, options: map[T]string) {
    if .SUBMIT in mu.button(ui, options[value^]) do mu.open_popup(ui, name)
    if mu.begin_popup(ui, name) {
        defer mu.end_popup(ui)
        for k, v in options {
            if .SUBMIT in mu.button(ui, v) {
                value^ = k
            }
        }
    }
}

slice_width :: proc(ui: ^mu.Context, #any_int n: i32, #any_int fixed_sum: i32, #any_int other_items: i32) -> i32 {
    body := mu.get_current_container(ui).body
    w := body.w - ui.style.padding * 2
    spacing := ui.style.spacing
    total_items := other_items + n;
    return (w - fixed_sum - (total_items - 1) * spacing) / n
}

