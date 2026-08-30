package src;

import "core:fmt"
import "core:strings"
import "psys"

import sdl "vendor:sdl3"
import mu "vendor:microui"
import nvg "vendor:nanovg"
import nvg_gl "vendor:nanovg/gl"

@(private="file")
handle_input :: proc(e: sdl.Event, ud: rawptr) {
    ui := (^mu.Context)(ud)
    #partial switch e.type {
        case .MOUSE_MOTION: mu.input_mouse_move(ui, i32(e.motion.x), i32(e.motion.y))
        case .MOUSE_WHEEL: mu.input_scroll(ui, 0, i32(e.wheel.y * -30))
        case .TEXT_INPUT: {
            mu.input_text(ui, string(e.text.text))
        }
        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            button_map :: #force_inline proc(button: u8) -> (res: mu.Mouse, ok: bool) {
                ok = true;
                switch button {
                    case 1: res = .LEFT;
                    case 2: res = .MIDDLE;
                    case 3: res = .RIGHT;
                    case: ok = false;
                }
                return;
            }
            if btn, ok := button_map(e.button.button); ok {
                if e.button.down do mu.input_mouse_down(ui, i32(e.button.x), i32(e.button.y), btn)
                else do mu.input_mouse_up(ui, i32(e.button.x), i32(e.button.y), btn)
            }
        case .KEY_DOWN, .KEY_UP: {
            key_map :: #force_inline proc(x: u32) -> (res: mu.Key, ok: bool) {
                ok = true;
                switch x {
                    case sdl.K_LSHIFT:    res = .SHIFT;
                    case sdl.K_RSHIFT:    res = .SHIFT;
                    case sdl.K_LCTRL:     res = .CTRL;
                    case sdl.K_RCTRL:     res = .CTRL;
                    case sdl.K_LALT:      res = .ALT;
                    case sdl.K_RALT:      res = .ALT;
                    case sdl.K_RETURN:    res = .RETURN;
                    case sdl.K_KP_ENTER:  res = .RETURN;
                    case sdl.K_BACKSPACE: res = .BACKSPACE;
                    case sdl.K_DELETE:    res = .DELETE;
                    case sdl.K_LEFT:      res = .LEFT;
                    case sdl.K_RIGHT:     res = .RIGHT;
                    case sdl.K_HOME:      res = .HOME;
                    case sdl.K_END:       res = .END;
                    case sdl.K_A:         res = .A;
                    case sdl.K_X:         res = .X;
                    case sdl.K_C:         res = .C;
                    case sdl.K_V:         res = .V;
                    case: ok = false;
                }
                return;
            }
            if key, ok := key_map(u32(e.key.key)); ok {
                if e.key.down do mu.input_key_down(ui, key)
                else do mu.input_key_up(ui, key)
            }
        }
    }
}

microui_processor :: proc(ui: ^mu.Context) -> psys.InputProcessor {
    return psys.InputProcessor {
        handler = handle_input,
        user_ptr = ui,
    }
}

// rendering
MicroUI_NanoVG :: struct {
    ui: ^mu.Context,
    vg: ^nvg.Context,
    atlas: int,
}

microui_nanovg_create :: proc() -> MicroUI_NanoVG {
    ui := new(mu.Context); mu.init(ui)
    ctx := nvg_gl.Create({.ANTI_ALIAS, .STENCIL_STROKES})

    font_bytes := #load("assets/OpenSans-Regular.ttf")
    if nvg.CreateFontMem(ctx, "default", font_bytes, false) == -1 {
        fmt.eprintln("failed to load default font")
    }
    nvg.FontFace(ctx, "default")
    nvg.FontSize(ctx, 16)

    // Load default atlas
    pixels := make([]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT * 4)
    for alpha, i in mu.default_atlas_alpha {
        k := i * 4
        pixels[k + 0] = 255
        pixels[k + 1] = 255
        pixels[k + 2] = 255
        pixels[k + 3] = alpha
    }
    atlas := nvg.CreateImageRGBA(
        ctx,
        mu.DEFAULT_ATLAS_WIDTH,
        mu.DEFAULT_ATLAS_HEIGHT,
        {.NEAREST, .NO_DELETE},
        pixels,
    )
    text_width  :: #force_inline proc(font: mu.Font, str: string) -> i32 {
        vg := cast(^nvg.Context)context.user_ptr
        bounds: [4]f32
        nvg.TextBounds(vg, 0, 0, str, &bounds)
        return i32(bounds[2] - bounds[0])
    }
	text_height :: #force_inline proc(font: mu.Font) -> i32 {
        vg := cast(^nvg.Context)context.user_ptr
        _, _, lh := nvg.TextMetrics(vg)
        return i32(lh)
    }
	ui.text_width = text_width
	ui.text_height = text_height
    ui.textbox_state.set_clipboard = proc(ud: rawptr, text: string) -> (ok: bool) {
        txt, _ := strings.clone_to_cstring(text)
        sdl.SetClipboardText(txt)
        return true
    }
    ui.textbox_state.get_clipboard = proc(ud: rawptr) -> (text: string, ok: bool) {
        txt := sdl.GetClipboardText()
        return string(cstring(txt)), true
    }
    return MicroUI_NanoVG {
        atlas = atlas,
        vg = ctx,
        ui = ui,
    }
}

microui_nanovg_destroy :: proc(muvg: MicroUI_NanoVG) {
    nvg_gl.Destroy(muvg.vg)
    free(muvg.ui)
}

microui_nanovg_render :: proc(muvg: MicroUI_NanoVG, width, height: f32) {
    ui := muvg.ui
    vg := muvg.vg

    nvg.BeginFrame(vg, width, height, width / height)
    defer nvg.EndFrame(vg)

    cmd: ^mu.Command
    for mu.next_command(ui, &cmd) {
        #partial switch c in cmd.variant {
            case ^mu.Command_Text: {
                asc, _, _ := nvg.TextMetrics(vg)
                nvg.FillColor(vg, nvg.RGBA(c.color.r, c.color.g, c.color.b, c.color.a))
                nvg.Text(vg, f32(c.pos.x), f32(c.pos.y)+asc, c.str)
            }
            case ^mu.Command_Rect: {
                nvg.FillColor(vg, nvg.RGBA(c.color.r, c.color.g, c.color.b, c.color.a))
                nvg.BeginPath(vg)
                nvg.Rect(vg, f32(c.rect.x), f32(c.rect.y), f32(c.rect.w), f32(c.rect.h))
                nvg.Fill(vg)
            }
            case ^mu.Command_Clip: {
                nvg.Scissor(vg, f32(c.rect.x), f32(c.rect.y), f32(c.rect.w), f32(c.rect.h))
            }
            case ^mu.Command_Icon: {
                rect := mu.default_atlas[c.id]
                x := c.rect.x + (c.rect.w - rect.w) / 2
                y := c.rect.y + (c.rect.h - rect.h) / 2

                tw, th := mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT

                paint := nvg.ImagePattern(
                    f32(x - rect.x), f32(y - rect.y),
                    f32(tw), f32(th),
                    0.0,
                    muvg.atlas, 1.0
                )
                nvg.BeginPath(vg)
                nvg.Rect(
                    vg,
                    f32(x), f32(y),
                    f32(rect.w), f32(rect.h),
                )
                nvg.FillPaint(vg, paint)
                nvg.Fill(vg)
            }
            case:
        }
    }
}
