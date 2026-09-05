package src

import "core:fmt"
import "core:strings"

import mu "vendor:microui"

import "psys"

// Color editing for microui.
//
// `color_edit` draws a swatch that opens a picker popup holding a
// saturation/value square, a hue bar, an alpha bar over a checkerboard, a hex
// field, RGBA number boxes and a preset palette. Gradients are drawn as thin
// rectangles because the microui command list has no gradient command.
//
// `color_stops_edit` draws a horizontal track with one knob per color stop of
// a `psys.LerpValue(psys.Color)` ramp, plus the buttons that add and remove a
// stop and a `color_edit` swatch for the selected one.

// popup geometry, in pixels
@(private="file") SV_W         :: 200 // saturation/value square
@(private="file") SV_H         :: 140
@(private="file") BAR_W        :: 18  // hue and alpha bars
@(private="file") GRAD_STEP    :: 2   // thickness of one gradient slice
@(private="file") CHECKER_CELL :: 6
@(private="file") PRESET_COLS  :: 8
@(private="file") PRESET_H     :: 18

@(private="file")
POPUP_NAME :: "!color_picker"

@(private="file")
Picker :: struct {
    id:       mu.Id,  // color_edit that owns the open popup, 0 when none does
    hsv:      [3]f32, // hue and saturation live here, rgb loses them at s or v == 0
    original: [4]f32, // color when the popup was opened, used by Revert
    rgba255:  [4]f32, // scratch for the number boxes, their id is their address
    hex_buf:  [16]u8,
    hex_len:  int,
}

@(private="file")
g_picker: Picker

// Area the popup is kept inside. The window size, set once per frame.
@(private="file")
g_viewport := mu.Rect{0, 0, 1280, 720}

@(private="file")
PRESETS := [?][3]u8{
    {255, 255, 255}, {192, 192, 192}, {128, 128, 128}, {  0,   0,   0},
    {255,  64,  64}, {255, 140,  32}, {255, 210,  64}, {255, 250, 200},
    { 96, 255,  96}, { 32, 200, 128}, { 64, 240, 255}, { 48, 144, 255},
    { 96,  96, 255}, {168,  80, 255}, {255,  80, 220}, {255, 128, 160},
}

color_picker_set_viewport :: proc(w, h: i32) {
    g_viewport = mu.Rect{0, 0, w, h}
}

// Swatch of `col` that opens the picker popup when clicked. Takes one layout
// cell. `.CHANGE` is returned on every frame the color is edited.
color_edit :: proc(ui: ^mu.Context, col: ^[4]f32) -> (res: mu.Result_Set) {
    id := mu.get_id(ui, uintptr(col))
    r := mu.layout_next(ui)

    hex_buf: [16]u8
    hex_len := color_hex_text(col^, hex_buf[:])

    if swatch_button(ui, id, r, col^, string(hex_buf[:hex_len])) {
        picker_open(ui, id, col^, r)
    }

    if g_picker.id == id {
        res += picker_popup(ui, col)
    }
    return
}

// stop editor geometry, in pixels
@(private="file") STRIP_H    :: 26 // whole track row
@(private="file") TRACK_H    :: 8
@(private="file") KNOB_W     :: 13
@(private="file") KNOB_H     :: 20
@(private="file") STOP_BTN_W :: 26 // "+" and "-"
@(private="file") STOP_IDX_W :: 36 // "2/4"
@(private="file") STOP_NUM_W :: 54 // stop position
@(private="file") GRAB_PAD   :: 3  // extra pixels a knob can be grabbed by

@(private="file")
Stops_State :: struct {
    id:       mu.Id, // widget the slot belongs to, 0 when the slot is free
    selected: int,
    dragging: bool,
}

// One slot per stop editor on screen. A slot is taken on the first frame the
// editor is drawn and kept for as long as the program runs.
@(private="file")
g_stops_states: [4]Stops_State

// Scratch for the position number box, its id is its address.
@(private="file")
g_stop_pos: f32

// Horizontal track carrying one knob per stop of `stops[:count^]`, with the
// buttons that add and remove a stop and a picker for the selected one. The
// stops stay sorted by `stop`, which is what `psys.interpolate` needs.
//
// `len(stops)` is the number of stops that fit, `count^` how many are in use.
// Takes two layout rows: the track, then the buttons. `.CHANGE` is returned on every frame a stop moves
// or its color is edited.
color_stops_edit :: proc(ui: ^mu.Context, stops: []psys.LerpValue(psys.Color), count: ^int) -> (res: mu.Result_Set) {
    if len(stops) == 0 {
        return
    }

    mu.push_id(ui, uintptr(&stops[0]))
    defer mu.pop_id(ui)

    n := clamp(count^, 0, len(stops))
    count^ = n

    id := mu.get_id(ui, "!stops")
    st := stops_state(id)
    st.selected = clamp(st.selected, 0, max(n - 1, 0))

    // track and knobs
    mu.layout_row(ui, {-1}, STRIP_H)
    strip := mu.layout_next(ui)
    track := stops_track(strip)

    mu.update_control(ui, id, strip, {})
    if ui.focus_id == id && ui.mouse_pressed_bits == {.LEFT} {
        if i, ok := stops_hit(stops[:n], strip, track, ui.mouse_pos.x); ok {
            st.selected = i
            st.dragging = true
        }
    }
    if st.dragging {
        if ui.focus_id == id && .LEFT in ui.mouse_down_bits {
            t := axis_value(ui.mouse_pos.x, track.x, track.w)
            if t != stops[st.selected].stop {
                stops[st.selected].stop = t
                st.selected = stops_sort_one(stops[:n], st.selected)
                res += {.CHANGE}
            }
        } else {
            st.dragging = false
        }
    }

    hovered := -1
    if ui.hover_id == id && !st.dragging {
        if i, ok := stops_hit(stops[:n], strip, track, ui.mouse_pos.x); ok {
            hovered = i
        }
    }

    mu.draw_rect(ui, track, ui.style.colors[.BASE])
    mu.draw_box(ui, track, ui.style.colors[.BORDER])
    for i in 0..<n {
        if i != st.selected {
            draw_stop_knob(ui, stops_knob_rect(stops[i].stop, strip, track), stops[i].value, false, i == hovered)
        }
    }
    if n > 0 { // the selected knob goes on top of the ones it overlaps
        i := st.selected
        draw_stop_knob(ui, stops_knob_rect(stops[i].stop, strip, track), stops[i].value, true, i == hovered)
    }

    // add, remove, which stop is selected, where it sits
    mu.layout_row(ui, {STOP_BTN_W, STOP_BTN_W, STOP_IDX_W, STOP_NUM_W, -1})

    if (.SUBMIT in mu.button(ui, "+")) && n < len(stops) {
        index, value := stops_new(stops[:n], st.selected, psys.Color{1, 1, 1, 1})
        stops_insert(stops, n, index, value)
        n += 1
        count^ = n
        st.selected = index
        res += {.CHANGE}
    }
    if (.SUBMIT in mu.button(ui, "-")) && n > 1 {
        stops_remove(stops[:n], st.selected)
        n -= 1
        count^ = n
        st.selected = clamp(st.selected, 0, n - 1)
        res += {.CHANGE}
    }

    if n == 0 {
        mu.label(ui, "0/0")
        mu.label(ui, "")
        mu.label(ui, "no stops")
        return
    }

    mu.label(ui, fmt.tprintf("%d/%d", st.selected + 1, n))

    g_stop_pos = stops[st.selected].stop
    if mu.number(ui, &g_stop_pos, 0.01, "%.2f") & {.CHANGE, .SUBMIT} != {} {
        stops[st.selected].stop = clamp(g_stop_pos, 0, 1)
        st.selected = stops_sort_one(stops[:n], st.selected)
        res += {.CHANGE}
    }

    res += color_edit(ui, &stops[st.selected].value)
    return
}

f32_stops_edit :: proc(
    ui: ^mu.Context,
    stops: []psys.LerpValue(f32),
    count: ^int,
    min_value: f32 = -1.0,
    max_value: f32 = -1.0,
) -> (res: mu.Result_Set) {
    if len(stops) == 0 {
        return
    }

    min_max_valid := min_value != max_value && min_value < max_value

    mu.push_id(ui, uintptr(&stops[0]))
    defer mu.pop_id(ui)

    n := clamp(count^, 0, len(stops))
    count^ = n

    id := mu.get_id(ui, "!stops")
    st := stops_state(id)
    st.selected = clamp(st.selected, 0, max(n - 1, 0))

    // track and knobs
    mu.layout_row(ui, {-1}, STRIP_H)
    strip := mu.layout_next(ui)
    track := stops_track(strip)

    mu.update_control(ui, id, strip, {})
    if ui.focus_id == id && ui.mouse_pressed_bits == {.LEFT} {
        if i, ok := stops_hit(stops[:n], strip, track, ui.mouse_pos.x); ok {
            st.selected = i
            st.dragging = true
        }
    }
    if st.dragging {
        if ui.focus_id == id && .LEFT in ui.mouse_down_bits {
            t := axis_value(ui.mouse_pos.x, track.x, track.w)
            if t != stops[st.selected].stop {
                stops[st.selected].stop = t
                st.selected = stops_sort_one(stops[:n], st.selected)
                res += {.CHANGE}
            }
        } else {
            st.dragging = false
        }
    }

    hovered := -1
    if ui.hover_id == id && !st.dragging {
        if i, ok := stops_hit(stops[:n], strip, track, ui.mouse_pos.x); ok {
            hovered = i
        }
    }

    mu.draw_rect(ui, track, ui.style.colors[.BASE])
    mu.draw_box(ui, track, ui.style.colors[.BORDER])
    for i in 0..<n {
        if i != st.selected {
            val := stops[i].value
            fac := 1.0 if !min_max_valid else (val - min_value) / (max_value - min_value)
            draw_f32_knob(ui, stops_knob_rect(stops[i].stop, strip, track), fac, false, i == hovered)
        }
    }
    if n > 0 { // the selected knob goes on top of the ones it overlaps
        i := st.selected
        val := stops[i].value
        fac := 1.0 if !min_max_valid else (val - min_value) / (max_value - min_value)
        draw_f32_knob(ui, stops_knob_rect(stops[i].stop, strip, track), fac, true, i == hovered)
    }

    // add, remove, which stop is selected, where it sits
    mu.layout_row(ui, {STOP_BTN_W, STOP_BTN_W, STOP_IDX_W, STOP_NUM_W, -1})

    if (.SUBMIT in mu.button(ui, "+")) && n < len(stops) {
        index, value := stops_new(stops[:n], st.selected, 0.0)
        stops_insert(stops, n, index, value)
        n += 1
        count^ = n
        st.selected = index
        res += {.CHANGE}
    }
    if (.SUBMIT in mu.button(ui, "-")) && n > 1 {
        stops_remove(stops[:n], st.selected)
        n -= 1
        count^ = n
        st.selected = clamp(st.selected, 0, n - 1)
        res += {.CHANGE}
    }

    if n == 0 {
        mu.label(ui, "0/0")
        mu.label(ui, "")
        mu.label(ui, "no stops")
        return
    }

    mu.label(ui, fmt.tprintf("%d/%d", st.selected + 1, n))

    g_stop_pos = stops[st.selected].stop
    if mu.number(ui, &g_stop_pos, 0.01, "%.2f") & {.CHANGE, .SUBMIT} != {} {
        stops[st.selected].stop = clamp(g_stop_pos, 0, 1)
        st.selected = stops_sort_one(stops[:n], st.selected)
        res += {.CHANGE}
    }

    if min_max_valid {
        res += mu.slider(ui, &stops[st.selected].value, min_value, max_value, 0.01)
    } else {
        res += mu.number(ui, &stops[st.selected].value, 0.01)
    }
    return
}

@(private="file")
stops_state :: proc(id: mu.Id) -> ^Stops_State {
    free := -1
    for &s, i in g_stops_states {
        if s.id == id {
            return &s
        }
        if s.id == 0 && free < 0 {
            free = i
        }
    }
    // out of slots: share one, the editors then share a selection
    slot := free if free >= 0 else int(id) % len(g_stops_states)
    g_stops_states[slot] = Stops_State{id = id}
    return &g_stops_states[slot]
}

// The part of the strip a knob center can sit on, inset so that no knob is cut
// off at either end.
@(private="file")
stops_track :: proc(strip: mu.Rect) -> mu.Rect {
    inset := i32(KNOB_W / 2 + 1)
    return mu.Rect{
        strip.x + inset,
        strip.y + (strip.h - TRACK_H) / 2,
        max(strip.w - inset * 2, 1),
        TRACK_H,
    }
}

@(private="file")
stops_knob_rect :: proc(t: f32, strip, track: mu.Rect) -> mu.Rect {
    cx := track.x + i32(clamp(t, 0, 1) * f32(max(track.w - 1, 1)))
    return mu.Rect{cx - KNOB_W / 2, strip.y + (strip.h - KNOB_H) / 2, KNOB_W, KNOB_H}
}

// Knob nearest to `x` that is close enough to be grabbed.
@(private="file")
stops_hit :: proc(stops: []psys.LerpValue($T), strip, track: mu.Rect, x: i32) -> (index: int, ok: bool) {
    best := i32(KNOB_W / 2 + GRAB_PAD)
    for s, i in stops {
        k := stops_knob_rect(s.stop, strip, track)
        d := abs(x - (k.x + k.w / 2))
        if d <= best {
            best = d
            index, ok = i, true
        }
    }
    return
}

// Where a new stop goes: in the gap after the selected one, or in the gap
// before it when the selected one is last. The color is the one the ramp
// already has there, so adding a stop does not change what it looks like.
@(private="file")
stops_new :: proc(stops: []psys.LerpValue($T), selected: int, default_value: T) -> (index: int, value: psys.LerpValue(T)) {
    n := len(stops)
    lo, hi: f32

    switch {
    case n == 0:
        return 0, {stop = 0, value = default_value}
    case selected < n - 1:
        lo, hi = stops[selected].stop, stops[selected + 1].stop
        index = selected + 1
    case n > 1:
        lo, hi = stops[selected - 1].stop, stops[selected].stop
        index = selected
    case stops[0].stop < 1: // one stop only, take the room next to it
        lo, hi = stops[0].stop, 1
        index = 1
    case:
        lo, hi = 0, stops[0].stop
        index = 0
    }

    value.stop = (lo + hi) * 0.5
    value.value = psys.interpolate(stops, value.stop)
    return
}

@(private="file")
stops_insert :: proc(stops: []psys.LerpValue($T), n, index: int, value: psys.LerpValue(T)) {
    for i := n; i > index; i -= 1 {
        stops[i] = stops[i - 1]
    }
    stops[index] = value
}

@(private="file")
stops_remove :: proc(stops: []psys.LerpValue($T), index: int) {
    for i := index; i < len(stops) - 1; i += 1 {
        stops[i] = stops[i + 1]
    }
}

// Moves the stop at `index` to where its position puts it and returns the
// index it ended up at. Everything else is already in order, so walking it to
// one side is enough.
@(private="file")
stops_sort_one :: proc(stops: []psys.LerpValue($T), index: int) -> int {
    i := index
    for i > 0 && stops[i].stop < stops[i - 1].stop {
        stops[i], stops[i - 1] = stops[i - 1], stops[i]
        i -= 1
    }
    for i < len(stops) - 1 && stops[i].stop > stops[i + 1].stop {
        stops[i], stops[i + 1] = stops[i + 1], stops[i]
        i += 1
    }
    return i
}

@(private="file")
draw_stop_knob :: proc(ui: ^mu.Context, r: mu.Rect, col: psys.Color, selected, hovered: bool) {
    if selected {
        mu.draw_box(ui, mu.Rect{r.x - 2, r.y - 2, r.w + 4, r.h + 4}, mu.Color{20, 20, 20, 255})
        mu.draw_box(ui, mu.Rect{r.x - 1, r.y - 1, r.w + 2, r.h + 2}, mu.Color{255, 255, 255, 255})
    }
    draw_color_fill(ui, r, col)

    border := ui.style.colors[.BORDER]
    if selected {
        border = mu.Color{255, 255, 255, 255}
    } else if hovered {
        border = mu.Color{220, 220, 220, 255}
    }
    mu.draw_box(ui, r, border)
}

@(private="file")
draw_f32_knob :: proc(ui: ^mu.Context, r: mu.Rect, fac: f32, selected, hovered: bool) {
    if selected {
        mu.draw_box(ui, mu.Rect{r.x - 2, r.y - 2, r.w + 4, r.h + 4}, mu.Color{20, 20, 20, 255})
        mu.draw_box(ui, mu.Rect{r.x - 1, r.y - 1, r.w + 2, r.h + 2}, mu.Color{255, 255, 255, 255})
    }
    draw_f32_fill(ui, r, fac)

    border := ui.style.colors[.BORDER]
    if selected {
        border = mu.Color{255, 255, 255, 255}
    } else if hovered {
        border = mu.Color{220, 220, 220, 255}
    }
    mu.draw_box(ui, r, border)
}

@(private="file")
picker_open :: proc(ui: ^mu.Context, id: mu.Id, col: [4]f32, anchor: mu.Rect) {
    g_picker.id = id
    g_picker.original = col
    g_picker.hsv = {0, 0, 0}
    picker_sync_hsv(col)
    g_picker.hex_len = color_hex_text(col, g_picker.hex_buf[:])

    cnt := mu.get_container(ui, POPUP_NAME)
    if cnt == nil {
        g_picker.id = 0
        return
    }

    // below the swatch, pushed back inside the window when it does not fit
    w, h := popup_size(ui)
    x := min(anchor.x, g_viewport.w - w)
    y := anchor.y + anchor.h + 2
    if y + h > g_viewport.h {
        y = anchor.y - h - 2
    }
    cnt.rect = mu.Rect{max(x, 0), max(y, 0), w, h}
    cnt.open = true

    // keep the click that opened the popup from closing it again
    ui.hover_root = cnt
    ui.next_hover_root = cnt
    mu.bring_to_front(ui, cnt)
}

@(private="file")
picker_popup :: proc(ui: ^mu.Context, col: ^[4]f32) -> (res: mu.Result_Set) {
    opt := mu.Options{.POPUP, .NO_RESIZE, .NO_SCROLL, .NO_TITLE, .CLOSED}
    if !mu.begin_window(ui, POPUP_NAME, mu.Rect{}, opt) {
        g_picker.id = 0 // clicked away
        return
    }
    defer mu.end_window(ui)

    p := &g_picker
    row_h := ui.style.size.y + ui.style.padding * 2
    spacing := ui.style.spacing
    content_w := popup_content_width(ui)

    // saturation/value square, hue bar, alpha bar
    mu.layout_row(ui, {SV_W, BAR_W, BAR_W}, SV_H)

    sv := mu.layout_next(ui)
    sv_id := mu.get_id(ui, "!sv")
    mu.update_control(ui, sv_id, sv, {})
    if ui.focus_id == sv_id && .LEFT in ui.mouse_down_bits {
        p.hsv[1] = axis_value(ui.mouse_pos.x, sv.x, sv.w)
        p.hsv[2] = 1 - axis_value(ui.mouse_pos.y, sv.y, sv.h)
        res += {.CHANGE}
    }

    hue := mu.layout_next(ui)
    hue_id := mu.get_id(ui, "!hue")
    mu.update_control(ui, hue_id, hue, {})
    if ui.focus_id == hue_id && .LEFT in ui.mouse_down_bits {
        p.hsv[0] = axis_value(ui.mouse_pos.y, hue.y, hue.h)
        res += {.CHANGE}
    }

    if .CHANGE in res {
        rgb := hsv_to_rgb(p.hsv[0], p.hsv[1], p.hsv[2])
        col[0], col[1], col[2] = rgb[0], rgb[1], rgb[2]
    }

    alpha := mu.layout_next(ui)
    alpha_id := mu.get_id(ui, "!alpha")
    mu.update_control(ui, alpha_id, alpha, {})
    if ui.focus_id == alpha_id && .LEFT in ui.mouse_down_bits {
        col[3] = 1 - axis_value(ui.mouse_pos.y, alpha.y, alpha.h)
        res += {.CHANGE}
    }

    draw_sv_square(ui, sv, p.hsv[0])
    draw_sv_cursor(ui, sv, p.hsv[1], p.hsv[2])
    draw_hue_bar(ui, hue)
    draw_bar_marker(ui, hue, p.hsv[0])
    draw_alpha_bar(ui, alpha, col^)
    draw_bar_marker(ui, alpha, 1 - col[3])

    // preview and hex
    left := (content_w - spacing) / 2
    mu.layout_row(ui, {left, content_w - spacing - left}, row_h)

    preview := mu.layout_next(ui)
    draw_color_fill(ui, preview, col^)
    mu.draw_box(ui, preview, ui.style.colors[.BORDER])

    hex_id := mu.get_id(ui, uintptr(&p.hex_buf[0]))
    if ui.focus_id != hex_id {
        p.hex_len = color_hex_text(col^, p.hex_buf[:])
    }
    if mu.textbox(ui, p.hex_buf[:], &p.hex_len) & {.CHANGE, .SUBMIT} != {} {
        if parse_hex_color(string(p.hex_buf[:p.hex_len]), col) {
            picker_sync_hsv(col^)
            res += {.CHANGE}
        }
    }

    // r, g, b, a in 0..255: drag to change, shift click to type
    quarter := (content_w - spacing * 3) / 4
    mu.layout_row(ui, {quarter, quarter, quarter, content_w - spacing * 3 - quarter * 3}, row_h)

    p.rgba255 = {col[0] * 255, col[1] * 255, col[2] * 255, col[3] * 255}
    fmts := [4]string{"R %.0f", "G %.0f", "B %.0f", "A %.0f"}
    typed := false
    for i in 0..<4 {
        if mu.number(ui, &p.rgba255[i], 1, fmts[i]) & {.CHANGE, .SUBMIT} != {} {
            typed = true
        }
    }
    if typed {
        for i in 0..<4 {
            col[i] = clamp(p.rgba255[i] / 255, 0, 1)
        }
        picker_sync_hsv(col^)
        res += {.CHANGE}
    }

    // presets, they set rgb and leave alpha alone
    widths: [PRESET_COLS]i32
    cell := (content_w - spacing * (PRESET_COLS - 1)) / PRESET_COLS
    for i in 0..<PRESET_COLS {
        widths[i] = cell
    }
    widths[PRESET_COLS - 1] = content_w - (cell + spacing) * (PRESET_COLS - 1)

    for i in 0..<len(PRESETS) {
        if i % PRESET_COLS == 0 {
            mu.layout_row(ui, widths[:], PRESET_H)
        }
        preset := [4]f32{
            f32(PRESETS[i][0]) / 255,
            f32(PRESETS[i][1]) / 255,
            f32(PRESETS[i][2]) / 255,
            1,
        }
        id := mu.get_id(ui, uintptr(&PRESETS[i]))
        if swatch_button(ui, id, mu.layout_next(ui), preset) {
            col[0], col[1], col[2] = preset[0], preset[1], preset[2]
            picker_sync_hsv(col^)
            res += {.CHANGE}
        }
    }

    mu.layout_row(ui, {left, content_w - spacing - left}, row_h)
    if .SUBMIT in mu.button(ui, "Revert") {
        col^ = p.original
        picker_sync_hsv(col^)
        res += {.CHANGE}
    }
    if .SUBMIT in mu.button(ui, "Done") {
        mu.get_current_container(ui).open = false
        p.id = 0
    }
    return
}

// Keeps hue and saturation when rgb no longer carries them, so the cursor of
// the square stays put while dragging through black or white.
@(private="file")
picker_sync_hsv :: proc(col: [4]f32) {
    h, s, v := rgb_to_hsv({col[0], col[1], col[2]})
    if s > 0 {
        g_picker.hsv[0] = h
    }
    if v > 0 {
        g_picker.hsv[1] = s
    }
    g_picker.hsv[2] = v
}

@(private="file")
popup_content_width :: proc(ui: ^mu.Context) -> i32 {
    return SV_W + BAR_W * 2 + ui.style.spacing * 2
}

@(private="file")
popup_size :: proc(ui: ^mu.Context) -> (w, h: i32) {
    row_h := ui.style.size.y + ui.style.padding * 2
    w = popup_content_width(ui) + ui.style.padding * 2
    // square, preview, numbers, two preset rows, buttons
    h = ui.style.padding * 2 + SV_H + row_h * 3 + PRESET_H * 2 + ui.style.spacing * 5
    return
}

// Position of `pos` inside a `length` long axis starting at `origin`, as 0..1.
@(private="file")
axis_value :: proc(pos, origin, length: i32) -> f32 {
    return clamp(f32(pos - origin) / f32(max(length - 1, 1)), 0, 1)
}

@(private="file")
swatch_button :: proc(ui: ^mu.Context, id: mu.Id, r: mu.Rect, col: [4]f32, label := "") -> bool {
    mu.update_control(ui, id, r, {})
    clicked := ui.mouse_pressed_bits == {.LEFT} && ui.focus_id == id

    draw_color_fill(ui, r, col)
    if len(label) > 0 {
        draw_text_centered(ui, label, r, contrast_color(col))
    }

    border := ui.style.colors[.BORDER]
    if ui.hover_id == id {
        border = mu.Color{220, 220, 220, 255}
    }
    mu.draw_box(ui, r, border)
    return clicked
}

@(private="file")
draw_color_fill :: proc(ui: ^mu.Context, r: mu.Rect, col: [4]f32) {
    if col[3] < 1 {
        draw_checkerboard(ui, r)
    }
    mu.draw_rect(ui, r, mu_color(col))
}

@(private="file")
draw_f32_fill :: proc(ui: ^mu.Context, r: mu.Rect, fac: f32) {
    if fac < 1 {
        draw_checkerboard(ui, r)
    }
    nr := r
    nr.h = i32(fac * f32(r.h))
    nr.y = r.y + (r.h - i32(fac * f32(r.h)))
    mu.draw_rect(ui, nr, mu_color({0.0, 0.5, 1.0, 1.0}))
}

@(private="file")
draw_checkerboard :: proc(ui: ^mu.Context, r: mu.Rect) {
    mu.draw_rect(ui, r, mu.Color{70, 70, 70, 255})

    cols := (r.w + CHECKER_CELL - 1) / CHECKER_CELL
    rows := (r.h + CHECKER_CELL - 1) / CHECKER_CELL
    for iy in 0..<rows {
        for ix in 0..<cols {
            if (ix + iy) % 2 == 0 {
                continue
            }
            x := r.x + ix * CHECKER_CELL
            y := r.y + iy * CHECKER_CELL
            mu.draw_rect(ui, mu.Rect{
                x, y,
                min(CHECKER_CELL, r.x + r.w - x),
                min(CHECKER_CELL, r.y + r.h - y),
            }, mu.Color{110, 110, 110, 255})
        }
    }
}

// White to the pure hue left to right, full value to black top to bottom.
@(private="file")
draw_sv_square :: proc(ui: ^mu.Context, r: mu.Rect, hue: f32) {
    pure := hsv_to_rgb(hue, 1, 1)

    for x := r.x; x < r.x + r.w; x += GRAD_STEP {
        w := min(i32(GRAD_STEP), r.x + r.w - x)
        t := (f32(x - r.x) + f32(w) * 0.5) / f32(r.w)
        c := [3]f32{
            1 + (pure[0] - 1) * t,
            1 + (pure[1] - 1) * t,
            1 + (pure[2] - 1) * t,
        }
        mu.draw_rect(ui, mu.Rect{x, r.y, w, r.h}, mu_color({c[0], c[1], c[2], 1}))
    }

    for y := r.y; y < r.y + r.h; y += GRAD_STEP {
        h := min(i32(GRAD_STEP), r.y + r.h - y)
        t := (f32(y - r.y) + f32(h) * 0.5) / f32(r.h)
        mu.draw_rect(ui, mu.Rect{r.x, y, r.w, h}, mu.Color{0, 0, 0, u8(t * 255)})
    }
}

@(private="file")
draw_sv_cursor :: proc(ui: ^mu.Context, r: mu.Rect, s, v: f32) {
    x := r.x + i32(clamp(s, 0, 1) * f32(r.w - 1))
    y := r.y + i32((1 - clamp(v, 0, 1)) * f32(r.h - 1))
    mu.draw_box(ui, mu.Rect{x - 5, y - 5, 11, 11}, mu.Color{0, 0, 0, 200})
    mu.draw_box(ui, mu.Rect{x - 4, y - 4, 9, 9}, mu.Color{255, 255, 255, 230})
}

@(private="file")
draw_hue_bar :: proc(ui: ^mu.Context, r: mu.Rect) {
    for y := r.y; y < r.y + r.h; y += GRAD_STEP {
        h := min(i32(GRAD_STEP), r.y + r.h - y)
        t := (f32(y - r.y) + f32(h) * 0.5) / f32(r.h)
        c := hsv_to_rgb(t, 1, 1)
        mu.draw_rect(ui, mu.Rect{r.x, y, r.w, h}, mu_color({c[0], c[1], c[2], 1}))
    }
}

// Opaque at the top, transparent at the bottom.
@(private="file")
draw_alpha_bar :: proc(ui: ^mu.Context, r: mu.Rect, col: [4]f32) {
    draw_checkerboard(ui, r)
    for y := r.y; y < r.y + r.h; y += GRAD_STEP {
        h := min(i32(GRAD_STEP), r.y + r.h - y)
        t := (f32(y - r.y) + f32(h) * 0.5) / f32(r.h)
        mu.draw_rect(ui, mu.Rect{r.x, y, r.w, h}, mu_color({col[0], col[1], col[2], 1 - t}))
    }
}

@(private="file")
draw_bar_marker :: proc(ui: ^mu.Context, r: mu.Rect, t: f32) {
    y := r.y + i32(clamp(t, 0, 1) * f32(r.h - 1))
    mu.draw_box(ui, mu.Rect{r.x - 2, y - 3, r.w + 4, 7}, mu.Color{0, 0, 0, 200})
    mu.draw_box(ui, mu.Rect{r.x - 1, y - 2, r.w + 2, 5}, mu.Color{255, 255, 255, 230})
}

@(private="file")
draw_text_centered :: proc(ui: ^mu.Context, str: string, r: mu.Rect, col: mu.Color) {
    font := ui.style.font
    pos := mu.Vec2{
        r.x + (r.w - ui.text_width(font, str)) / 2,
        r.y + (r.h - ui.text_height(font)) / 2,
    }
    mu.draw_text(ui, font, str, pos, col)
}

// Black or white, whichever stays readable on top of `col`. Transparent colors
// are measured over the checkerboard they are drawn on.
@(private="file")
contrast_color :: proc(col: [4]f32) -> mu.Color {
    a := clamp(col[3], 0, 1)
    r := clamp(col[0], 0, 1) * a + 0.35 * (1 - a)
    g := clamp(col[1], 0, 1) * a + 0.35 * (1 - a)
    b := clamp(col[2], 0, 1) * a + 0.35 * (1 - a)
    if 0.299 * r + 0.587 * g + 0.114 * b > 0.55 {
        return mu.Color{20, 20, 20, 255}
    }
    return mu.Color{235, 235, 235, 255}
}

@(private="file")
mu_color :: proc(col: [4]f32) -> mu.Color {
    return mu.Color{
        u8(clamp(col[0], 0, 1) * 255 + 0.5),
        u8(clamp(col[1], 0, 1) * 255 + 0.5),
        u8(clamp(col[2], 0, 1) * 255 + 0.5),
        u8(clamp(col[3], 0, 1) * 255 + 0.5),
    }
}

@(private="file")
hsv_to_rgb :: proc(h, s, v: f32) -> [3]f32 {
    hh := clamp(h, 0, 1) * 6
    i := int(hh)
    f := hh - f32(i)
    p := v * (1 - s)
    q := v * (1 - s * f)
    t := v * (1 - s * (1 - f))

    switch i % 6 {
    case 0: return {v, t, p}
    case 1: return {q, v, p}
    case 2: return {p, v, t}
    case 3: return {p, q, v}
    case 4: return {t, p, v}
    }
    return {v, p, q}
}

@(private="file")
rgb_to_hsv :: proc(c: [3]f32) -> (h, s, v: f32) {
    r, g, b := c[0], c[1], c[2]
    mx := max(r, g, b)
    mn := min(r, g, b)
    d := mx - mn

    v = mx
    s = d / mx if mx > 0 else 0
    if d <= 0 {
        return
    }

    switch {
    case mx == r: h = (g - b) / d + (6 if g < b else 0)
    case mx == g: h = (b - r) / d + 2
    case:         h = (r - g) / d + 4
    }
    h /= 6
    return
}

// "#RRGGBB", or "#RRGGBBAA" when the color is not opaque. Returns the length
// written into `buf`.
@(private="file")
color_hex_text :: proc(col: [4]f32, buf: []u8) -> int {
    c := mu_color(col)
    if c.a == 255 {
        return len(fmt.bprintf(buf, "#%02X%02X%02X", c.r, c.g, c.b))
    }
    return len(fmt.bprintf(buf, "#%02X%02X%02X%02X", c.r, c.g, c.b, c.a))
}

// Reads "#RGB", "#RGBA", "#RRGGBB" or "#RRGGBBAA", with the "#" optional. The
// alpha of `col` is kept when the text carries none.
@(private="file")
parse_hex_color :: proc(text: string, col: ^[4]f32) -> bool {
    s := strings.trim_space(text)
    if len(s) > 0 && s[0] == '#' {
        s = s[1:]
    }
    if len(s) != 3 && len(s) != 4 && len(s) != 6 && len(s) != 8 {
        return false
    }

    digits: [8]u8
    for i in 0..<len(s) {
        d, ok := hex_digit(s[i])
        if !ok {
            return false
        }
        digits[i] = d
    }

    out := col^
    if len(s) <= 4 {
        for i in 0..<len(s) {
            out[i] = f32(digits[i] * 16 + digits[i]) / 255
        }
    } else {
        for i in 0..<len(s) / 2 {
            out[i] = f32(digits[i * 2] * 16 + digits[i * 2 + 1]) / 255
        }
    }
    col^ = out
    return true
}

@(private="file")
hex_digit :: proc(c: u8) -> (u8, bool) {
    switch c {
    case '0'..='9': return c - '0', true
    case 'a'..='f': return c - 'a' + 10, true
    case 'A'..='F': return c - 'A' + 10, true
    }
    return 0, false
}
