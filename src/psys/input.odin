package psys

import sdl "vendor:sdl3"

InputState :: bit_field u8 {
    pressed: bool | 1,
    released: bool | 1,
    held: bool | 1,
}

Key :: enum u16 {
    None = 0,

    Space = u16(sdl.Scancode.SPACE),
    Comma = u16(sdl.Scancode.COMMA),
    Minus = u16(sdl.Scancode.MINUS),
    Period = u16(sdl.Scancode.PERIOD),
    OEM2 = u16(sdl.Scancode.SLASH),
    Slash = OEM2,
    K0 = u16(sdl.Scancode._0),
    K1 = u16(sdl.Scancode._1),
    K2 = u16(sdl.Scancode._2),
    K3 = u16(sdl.Scancode._3),
    K4 = u16(sdl.Scancode._4),
    K5 = u16(sdl.Scancode._5),
    K6 = u16(sdl.Scancode._6),
    K7 = u16(sdl.Scancode._7),
    K8 = u16(sdl.Scancode._8),
    K9 = u16(sdl.Scancode._9),
    OEM1 = u16(sdl.Scancode.SEMICOLON),
    Semicolon = OEM1,
    Equals = u16(sdl.Scancode.EQUALS),
    Apostrophe = u16(sdl.Scancode.APOSTROPHE),
    LeftBracket = u16(sdl.Scancode.LEFTBRACKET),
    RightBracket = u16(sdl.Scancode.RIGHTBRACKET),
    Backslash = u16(sdl.Scancode.BACKSLASH),
    Grave = u16(sdl.Scancode.GRAVE),

    A = u16(sdl.Scancode.A),
    B = u16(sdl.Scancode.B),
    C = u16(sdl.Scancode.C),
    D = u16(sdl.Scancode.D),
    E = u16(sdl.Scancode.E),
    F = u16(sdl.Scancode.F),
    G = u16(sdl.Scancode.G),
    H = u16(sdl.Scancode.H),
    I = u16(sdl.Scancode.I),
    J = u16(sdl.Scancode.J),
    K = u16(sdl.Scancode.K),
    L = u16(sdl.Scancode.L),
    M = u16(sdl.Scancode.M),
    N = u16(sdl.Scancode.N),
    O = u16(sdl.Scancode.O),
    P = u16(sdl.Scancode.P),
    Q = u16(sdl.Scancode.Q),
    R = u16(sdl.Scancode.R),
    S = u16(sdl.Scancode.S),
    T = u16(sdl.Scancode.T),
    U = u16(sdl.Scancode.U),
    V = u16(sdl.Scancode.V),
    W = u16(sdl.Scancode.W),
    X = u16(sdl.Scancode.X),
    Y = u16(sdl.Scancode.Y),
    Z = u16(sdl.Scancode.Z),

    OEM4 = LeftBracket,
    OEM5 = Backslash,
    OEM6 = RightBracket,
    OEM3 = Grave,
    OEM7 = Apostrophe,
    OEM8 = u16(sdl.Scancode.NONUSBACKSLASH),

    F1 = u16(sdl.Scancode.F1),
    F2 = u16(sdl.Scancode.F2),
    F3 = u16(sdl.Scancode.F3),
    F4 = u16(sdl.Scancode.F4),
    F5 = u16(sdl.Scancode.F5),
    F6 = u16(sdl.Scancode.F6),
    F7 = u16(sdl.Scancode.F7),
    F8 = u16(sdl.Scancode.F8),
    F9 = u16(sdl.Scancode.F9),
    F10 = u16(sdl.Scancode.F10),
    F11 = u16(sdl.Scancode.F11),
    F12 = u16(sdl.Scancode.F12),

    Up = u16(sdl.Scancode.UP),
    Down = u16(sdl.Scancode.DOWN),
    Left = u16(sdl.Scancode.LEFT),
    Right = u16(sdl.Scancode.RIGHT),

    Tab = u16(sdl.Scancode.TAB),
    Shift = u16(sdl.Scancode.LSHIFT),
    LeftShift = Shift,
    RightShift = u16(sdl.Scancode.RSHIFT),
    Ctrl = u16(sdl.Scancode.LCTRL),
    LeftCtrl = Ctrl,
    RightCtrl = u16(sdl.Scancode.RCTRL),
    Alt = u16(sdl.Scancode.LALT),
    LeftAlt = Alt,
    RightAlt = u16(sdl.Scancode.RALT),
    Super = u16(sdl.Scancode.LGUI),
    LeftSuper = Super,
    RightSuper = u16(sdl.Scancode.RGUI),
    Menu = u16(sdl.Scancode.APPLICATION),
    Ins = u16(sdl.Scancode.INSERT),
    Del = u16(sdl.Scancode.DELETE),
    Home = u16(sdl.Scancode.HOME),
    End = u16(sdl.Scancode.END),
    PgUp = u16(sdl.Scancode.PAGEUP),
    PgDn = u16(sdl.Scancode.PAGEDOWN),

    Back = u16(sdl.Scancode.BACKSPACE),
    Escape = u16(sdl.Scancode.ESCAPE),
    Return = u16(sdl.Scancode.RETURN),
    Enter = Return,
    Pause = u16(sdl.Scancode.PAUSE),
    Scroll = u16(sdl.Scancode.SCROLLLOCK),
    PrintScreen = u16(sdl.Scancode.PRINTSCREEN),
    NumLock = u16(sdl.Scancode.NUMLOCKCLEAR),
    Apps = Menu,

    Np0 = u16(sdl.Scancode.KP_0),
    Np1 = u16(sdl.Scancode.KP_1),
    Np2 = u16(sdl.Scancode.KP_2),
    Np3 = u16(sdl.Scancode.KP_3),
    Np4 = u16(sdl.Scancode.KP_4),
    Np5 = u16(sdl.Scancode.KP_5),
    Np6 = u16(sdl.Scancode.KP_6),
    Np7 = u16(sdl.Scancode.KP_7),
    Np8 = u16(sdl.Scancode.KP_8),
    Np9 = u16(sdl.Scancode.KP_9),

    NpDiv = u16(sdl.Scancode.KP_DIVIDE),
    NpMul = u16(sdl.Scancode.KP_MULTIPLY),
    NpSub = u16(sdl.Scancode.KP_MINUS),
    NpAdd = u16(sdl.Scancode.KP_PLUS),
    NpEnter = u16(sdl.Scancode.KP_ENTER),
    NpEqual = u16(sdl.Scancode.KP_EQUALS),
    NpDecimal = u16(sdl.Scancode.KP_PERIOD),

    CapsLock = u16(sdl.Scancode.CAPSLOCK),
}

MAX_KEY_CODE :: 512

InputProcessor :: struct {
    user_ptr: rawptr,
    handler: proc(e: sdl.Event, ptr: rawptr),
}

InputHandler :: struct {
    window: ^sdl.Window,
    quit_requested: bool,
    mouse_button_state: [3]InputState,
    keyboard_state: [MAX_KEY_CODE]InputState,
    wheel: vec2,
    processors: []InputProcessor,
    processor_count: int,
}

input_handler_create :: proc(window: ^sdl.Window) -> InputHandler {
    return InputHandler {
        window = window,
        processor_count = 0,
        processors = make([]InputProcessor, 16),
    }
}

input_handler_destroy :: proc(ih: ^InputHandler) {
    delete(ih.processors)
    ih.processors = nil
    ih.processor_count = 0
}

input_handler_register_processor :: proc(ih: ^InputHandler, ip: InputProcessor) {
    if ih.processor_count >= len(ih.processors) do return
    ih.processors[ih.processor_count] = ip
    ih.processor_count += 1
}

input_handler_end_frame :: proc(ih: ^InputHandler) {
    for &s in ih.keyboard_state {
        s.pressed = false
        s.released = false
    }
    for &s in ih.mouse_button_state {
        s.pressed = false
        s.released = false
    }
    ih.wheel = vec2{0,0}
}

input_handler_poll :: proc(ih: ^InputHandler) {
    e: sdl.Event
    for sdl.PollEvent(&e) {
        for ip in 0..<ih.processor_count {
            ih.processors[ip].handler(e, ih.processors[ip].user_ptr)
        }
        #partial switch e.type {
            case .QUIT: ih.quit_requested = true
            case .KEY_DOWN, .KEY_UP: {
                if e.key.repeat do continue
                idx := int(e.key.scancode)
                if idx < len(ih.keyboard_state) {
                    s := &ih.keyboard_state[idx]
                    if e.key.down {
                        s.pressed = true
                        s.held = true
                    } else {
                        s.released = true
                        s.held = false
                    }
                }
            }
            case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP: {
                btn := int(e.button.button)
                if btn >= 1 && btn <= len(ih.mouse_button_state) {
                    s := &ih.mouse_button_state[btn - 1]
                    if e.button.down {
                        s.pressed = true
                        s.held = true
                    } else {
                        s.released = true
                        s.held = false
                    }
                }
            }
            case .MOUSE_WHEEL: {
                delta := vec2{e.wheel.x, e.wheel.y}
                if e.wheel.direction == sdl.MouseWheelDirection.FLIPPED {
                    delta *= -1.0
                }
                ih.wheel += delta
            }
            case:
        }
    }
}

is_key_pressed :: proc(ih: InputHandler, key: Key) -> bool {
    return ih.keyboard_state[key].pressed
}

is_key_released :: proc(ih: InputHandler, key: Key) -> bool {
    return ih.keyboard_state[key].released
}

is_key_held :: proc(ih: InputHandler, key: Key) -> bool {
    return ih.keyboard_state[key].held
}

is_button_pressed :: proc(ih: InputHandler, btn: int) -> bool {
    return ih.mouse_button_state[btn % 3].pressed
}

is_button_released :: proc(ih: InputHandler, btn: int) -> bool {
    return ih.mouse_button_state[btn % 3].released
}

is_button_held :: proc(ih: InputHandler, btn: int) -> bool {
    return ih.mouse_button_state[btn % 3].held
}

get_mouse_position :: proc() -> vec2 {
    x, y: f32
    _ = sdl.GetMouseState(&x, &y)
    return vec2{x, y}
}

set_mouse_position :: proc(ih: InputHandler, pos: vec2) {
    sdl.WarpMouseInWindow(ih.window, pos.x, pos.y)
}
