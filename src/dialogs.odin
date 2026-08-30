package src;

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

import mu "vendor:microui"

FileDialogMode :: enum {
    OPEN,
    SAVE
}

FileDialogResult :: enum {
    NONE,   // dialog is still open, nothing decided this frame
    ACCEPT, // user picked a path
    CANCEL  // user dismissed the dialog
}

FileDialogEntry :: struct {
    name:   string,
    is_dir: bool,
}

// One entry of the file type picker. `extensions` are given without the dot and
// are matched case insensitively; an empty list matches every file.
FileFilter :: struct {
    name:       string,
    extensions: []string,
}

FILE_DIALOG_MAX_PATH :: 1024
FILE_DIALOG_MAX_NAME :: 256
// two clicks on the same row closer than this count as a double click
FILE_DIALOG_DOUBLE_CLICK :: 0.4

FileDialog :: struct {
    mode:    FileDialogMode,
    is_open: bool,
    raise:   bool, // bring the window to the front on the next frame

    dir:      string,                   // current folder, absolute, owned
    entries:  [dynamic]FileDialogEntry, // contents of dir, folders first, owned
    selected: int,                      // index into entries, -1 when nothing is selected

    filters:      []FileFilter, // file type picker, borrowed from the caller
    filter_index: int,          // index into filters

    show_hidden:       bool,
    confirm_overwrite: bool,

    path_buf: [FILE_DIALOG_MAX_PATH]u8,
    path_len: int,

    name_buf: [FILE_DIALOG_MAX_NAME]u8,
    name_len: int,

    search_buf: [FILE_DIALOG_MAX_NAME]u8,
    search_len: int,

    status_buf: [FILE_DIALOG_MAX_NAME]u8,
    status_len: int,

    result_buf: [FILE_DIALOG_MAX_PATH]u8,
    result_len: int,

    last_click:      int,
    last_click_time: time.Tick,
}

// Shows the dialog. `start_dir` defaults to the folder the dialog was last in,
// and to the working directory the first time it is opened. `filters` is stored
// as given, so it has to outlive the dialog; passing nothing lists every file.
file_dialog_open :: proc(
    dlg: ^FileDialog,
    mode: FileDialogMode,
    start_dir := "",
    filters: []FileFilter = nil,
) {
    dlg.mode = mode
    dlg.is_open = true
    dlg.raise = true
    dlg.confirm_overwrite = false
    dlg.selected = -1
    dlg.last_click = -1
    dlg.search_len = 0
    dlg.status_len = 0
    dlg.filters = filters
    dlg.filter_index = 0

    dir := start_dir
    if dir == "" do dir = dlg.dir
    if dir == "" {
        cwd, err := os.get_working_directory(context.temp_allocator)
        dir = cwd if err == nil else "."
    }
    file_dialog_navigate(dlg, dir)
}

file_dialog_close :: proc(dlg: ^FileDialog) {
    dlg.is_open = false
    dlg.confirm_overwrite = false
    dlg.status_len = 0
}

file_dialog_destroy :: proc(dlg: ^FileDialog) {
    file_dialog_clear_entries(dlg)
    delete(dlg.entries)
    delete(dlg.dir)
    dlg.dir = ""
}

// Reads `path` and makes it the current folder. On failure the current folder
// is kept and the reason is written to the status line.
file_dialog_navigate :: proc(dlg: ^FileDialog, path: string) {
    abs, abs_err := os.get_absolute_path(path, context.temp_allocator)
    if abs_err != nil {
        file_dialog_set_status(dlg, "cannot resolve %s: %v", path, abs_err)
        return
    }

    infos, read_err := os.read_all_directory_by_path(abs, context.temp_allocator)
    if read_err != nil {
        file_dialog_set_status(dlg, "cannot open %s: %v", abs, read_err)
        return
    }

    file_dialog_clear_entries(dlg)
    for info in infos {
        append(&dlg.entries, FileDialogEntry {
            name = strings.clone(info.name),
            is_dir = file_info_is_dir(info),
        })
    }
    slice.sort_by(dlg.entries[:], proc(a, b: FileDialogEntry) -> bool {
        if a.is_dir != b.is_dir do return a.is_dir
        return less_fold(a.name, b.name)
    })

    delete(dlg.dir)
    dlg.dir = strings.clone(abs)
    dlg.selected = -1
    dlg.last_click = -1
    dlg.status_len = 0
    buf_set(dlg.path_buf[:], &dlg.path_len, dlg.dir)
}

// Draws the dialog. Call it once per frame at root level, that is outside any
// other `mu.begin_window` block. On `.ACCEPT` the returned path stays valid
// until the next call that touches this dialog, so copy it if it must outlive
// the frame.
file_dialog :: proc(ui: ^mu.Context, dlg: ^FileDialog, title: string = "") -> (path: string, result: FileDialogResult) {
    if !dlg.is_open do return "", .NONE

    wtitle: string
    if len(title) > 0 {
        wtitle = fmt.tprintf("Open %s", title) if dlg.mode == .OPEN else fmt.tprintf("Save %s", title)
    } else {
        wtitle = "Open File" if dlg.mode == .OPEN else "Save File"
    }

    if !mu.begin_window(ui, wtitle, {160, 120, 480, 440}, {.NO_CLOSE}) {
        return "", .NONE
    }
    defer mu.end_window(ui)

    if dlg.raise {
        mu.bring_to_front(ui, mu.get_current_container(ui))
        dlg.raise = false
    }

    row_h := ui.style.size.y + ui.style.padding * 2
    // status line, file name row and button row sit below the list
    list_bottom := 3 * (row_h + ui.style.spacing)

    do_accept := false

    // current folder: parent button plus a path the user can type into
    mu.layout_row(ui, {32, -1})
    if .SUBMIT in mu.button(ui, "Up") {
        if parent, err := os.join_path({dlg.dir, ".."}, context.temp_allocator); err == nil {
            file_dialog_navigate(dlg, parent)
        }
    }
    if .SUBMIT in mu.textbox(ui, dlg.path_buf[:], &dlg.path_len) {
        file_dialog_submit_path(dlg, string(dlg.path_buf[:dlg.path_len]))
    }

    // name filter, file type picker and hidden files, over the current folder
    if len(dlg.filters) > 0 {
        mu.layout_row(ui, {32, -210, 120, -1})
    } else {
        mu.layout_row(ui, {32, -90, -1})
    }
    mu.label(ui, "Find")
    mu.textbox(ui, dlg.search_buf[:], &dlg.search_len)
    if len(dlg.filters) > 0 do file_dialog_filter_button(ui, dlg)
    mu.checkbox(ui, "Hidden", &dlg.show_hidden)

    panel_name := fmt.tprintf("files_%s", title)

    // folder contents
    navigate_to := ""
    mu.layout_row(ui, {-1}, -list_bottom)
    mu.begin_panel(ui, panel_name)
    {
        mu.layout_row(ui, {-1}, row_h)
        search := string(dlg.search_buf[:dlg.search_len])
        for entry, i in dlg.entries {
            if !dlg.show_hidden && strings.has_prefix(entry.name, ".") do continue
            if !contains_fold(entry.name, search) do continue
            if !entry.is_dir && !file_dialog_matches_filter(dlg, entry.name) do continue

            label := fmt.tprintf("%s/", entry.name) if entry.is_dir else entry.name
            if .SUBMIT not_in file_dialog_row(ui, label, i == dlg.selected) do continue

            now := time.tick_now()
            double_click := dlg.last_click == i &&
                time.duration_seconds(time.tick_diff(dlg.last_click_time, now)) < FILE_DIALOG_DOUBLE_CLICK

            dlg.last_click = i
            dlg.last_click_time = now
            dlg.selected = i
            dlg.confirm_overwrite = false

            if entry.is_dir {
                // entries are rebuilt by the navigation, so defer it past the loop
                if joined, err := os.join_path({dlg.dir, entry.name}, context.temp_allocator); err == nil {
                    navigate_to = joined
                }
            } else {
                buf_set(dlg.name_buf[:], &dlg.name_len, entry.name)
                do_accept = double_click
            }
        }
    }
    mu.end_panel(ui)

    if navigate_to != "" do file_dialog_navigate(dlg, navigate_to)

    mu.layout_row(ui, {-1})
    mu.label(ui, string(dlg.status_buf[:dlg.status_len]))

    mu.layout_row(ui, {32, -1})
    mu.label(ui, "File")
    name_res := mu.textbox(ui, dlg.name_buf[:], &dlg.name_len)
    if .CHANGE in name_res do dlg.confirm_overwrite = false
    if .SUBMIT in name_res do do_accept = true

    mu.layout_row(ui, {-160, 75, 75})
    mu.layout_next(ui) // spacer, pushes the buttons to the right edge
    if .SUBMIT in mu.button(ui, "Open" if dlg.mode == .OPEN else "Save") do do_accept = true
    if .SUBMIT in mu.button(ui, "Cancel") {
        file_dialog_close(dlg)
        return "", .CANCEL
    }

    if do_accept && file_dialog_accept(dlg) {
        return string(dlg.result_buf[:dlg.result_len]), .ACCEPT
    }

    return "", .NONE
}

// Validates the current folder plus file name and, when it is usable, stores it
// as the result. Returns false when the dialog has to stay open.
@(private="file")
file_dialog_accept :: proc(dlg: ^FileDialog) -> bool {
    name := strings.trim_space(string(dlg.name_buf[:dlg.name_len]))
    if name == "" {
        file_dialog_set_status(dlg, "enter a file name")
        return false
    }

    full := expand_path(name)
    if !os.is_absolute_path(full) {
        joined, err := os.join_path({dlg.dir, full}, context.temp_allocator)
        if err != nil {
            file_dialog_set_status(dlg, "cannot build path: %v", err)
            return false
        }
        full = joined
    }

    // a folder typed into the name box navigates instead of accepting
    if os.is_directory(full) {
        file_dialog_navigate(dlg, full)
        dlg.name_len = 0
        return false
    }

    switch dlg.mode {
    case .OPEN:
        if !os.exists(full) {
            file_dialog_set_status(dlg, "no such file: %s", full)
            return false
        }
    case .SAVE:
        if os.exists(full) && !dlg.confirm_overwrite {
            dlg.confirm_overwrite = true
            file_dialog_set_status(dlg, "%s exists, press Save again to overwrite", name)
            return false
        }
    }

    buf_set(dlg.result_buf[:], &dlg.result_len, full)
    file_dialog_close(dlg)
    return true
}

// Handles a path typed into the path box. A folder is opened, a file path opens
// its folder and fills the file name box.
@(private="file")
file_dialog_submit_path :: proc(dlg: ^FileDialog, text: string) {
    path := expand_path(strings.trim_space(text))
    if path == "" do return

    if os.is_directory(path) {
        file_dialog_navigate(dlg, path)
        return
    }

    dir, name := os.split_path(path)
    if dir == "" do dir = "."
    if !os.is_directory(dir) {
        file_dialog_set_status(dlg, "no such folder: %s", dir)
        return
    }

    file_dialog_navigate(dlg, dir)
    buf_set(dlg.name_buf[:], &dlg.name_len, name)
    dlg.confirm_overwrite = false
}

file_dialog_row :: proc(ui: ^mu.Context, label: string, selected: bool) -> (res: mu.Result_Set) {
    id := mu.get_id(ui, label)
    r := mu.layout_next(ui)
    mu.update_control(ui, id, r, {})

    if ui.mouse_pressed_bits == {.LEFT} && ui.focus_id == id {
        res += {.SUBMIT}
    }

    if selected {
        mu.draw_rect(ui, r, ui.style.colors[.BASE_FOCUS])
    } else if ui.hover_id == id {
        mu.draw_rect(ui, r, ui.style.colors[.BUTTON_HOVER])
    }
    mu.draw_control_text(ui, label, r, .TEXT)
    return
}

// The file type picker. Opens a popup listing every filter.
@(private="file")
file_dialog_filter_button :: proc(ui: ^mu.Context, dlg: ^FileDialog) {
    dlg.filter_index = clamp(dlg.filter_index, 0, len(dlg.filters) - 1)

    if .SUBMIT in mu.button(ui, dlg.filters[dlg.filter_index].name) {
        mu.open_popup(ui, "file_dialog_filter")
    }
    if mu.begin_popup(ui, "file_dialog_filter") {
        defer mu.end_popup(ui)
        for filter, i in dlg.filters {
            if .SUBMIT in mu.button(ui, filter.name) {
                dlg.filter_index = i
                dlg.selected = -1
                dlg.last_click = -1
                mu.get_current_container(ui).open = false
            }
        }
    }
}

// Folders are always listed, only files go through the picked filter.
@(private="file")
file_dialog_matches_filter :: proc(dlg: ^FileDialog, name: string) -> bool {
    if len(dlg.filters) == 0 do return true

    filter := dlg.filters[clamp(dlg.filter_index, 0, len(dlg.filters) - 1)]
    if len(filter.extensions) == 0 do return true

    for ext in filter.extensions {
        if has_extension_fold(name, ext) do return true
    }
    return false
}

// Case insensitive ".ext" suffix test, ASCII only. A name that is nothing but
// the extension, such as ".png", does not match.
@(private="file")
has_extension_fold :: proc(name, ext: string) -> bool {
    if len(name) < len(ext) + 2 do return false
    if name[len(name) - len(ext) - 1] != '.' do return false

    tail := name[len(name) - len(ext):]
    for i in 0..<len(ext) {
        if lower(tail[i]) != lower(ext[i]) do return false
    }
    return true
}

@(private="file")
file_dialog_clear_entries :: proc(dlg: ^FileDialog) {
    for entry in dlg.entries {
        delete(entry.name)
    }
    clear(&dlg.entries)
}

@(private="file")
file_dialog_set_status :: proc(dlg: ^FileDialog, format: string, args: ..any) {
    dlg.status_len = len(fmt.bprintf(dlg.status_buf[:], format, ..args))
}

@(private="file")
file_info_is_dir :: proc(info: os.File_Info) -> bool {
    #partial switch info.type {
        case .Directory: return true
        case .Symlink: {
            target, err := os.stat(info.fullpath, context.temp_allocator)
            return err == nil && target.type == .Directory
        }
    }
    return false
}

// Replaces a leading "~" with $HOME. The result may be backed by the temporary
// allocator.
@(private="file")
expand_path :: proc(path: string) -> string {
    if path != "~" && !strings.has_prefix(path, "~/") do return path

    home := os.get_env("HOME", context.temp_allocator)
    if home == "" do return path

    joined, err := os.join_path({home, path[1:]}, context.temp_allocator)
    return path if err != nil else joined
}

@(private="file")
buf_set :: proc(buf: []u8, length: ^int, text: string) {
    length^ = copy(buf, text)
}

@(private="file")
lower :: proc(c: u8) -> u8 {
    return c + ('a' - 'A') if c >= 'A' && c <= 'Z' else c
}

// Case insensitive name ordering, ASCII only.
@(private="file")
less_fold :: proc(a, b: string) -> bool {
    for i in 0..<min(len(a), len(b)) {
        ca, cb := lower(a[i]), lower(b[i])
        if ca != cb do return ca < cb
    }
    return len(a) < len(b)
}

// Case insensitive substring test, ASCII only. An empty needle matches.
@(private="file")
contains_fold :: proc(haystack, needle: string) -> bool {
    if len(needle) == 0 do return true
    if len(needle) > len(haystack) do return false

    for i in 0..=len(haystack) - len(needle) {
        matched := true
        for j in 0..<len(needle) {
            if lower(haystack[i + j]) != lower(needle[j]) {
                matched = false
                break
            }
        }
        if matched do return true
    }
    return false
}
