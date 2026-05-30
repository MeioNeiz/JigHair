//! Native Win32 settings window: build a crosshair (with a live, pixel-exact
//! preview rendered by the real renderer), manage named presets, and choose the
//! target apps for foreground mode. Opened from the tray menu. A single instance
//! at a time; edits a working copy of Settings and commits on "Save & Apply".

const std = @import("std");
const win32 = @import("win32.zig");
const config = @import("config.zig");
const crosshair = @import("crosshair.zig");
const renderer_mod = @import("renderer.zig");
const window_mod = @import("window.zig");

fn L(comptime s: []const u8) win32.LPCWSTR {
    return std.unicode.utf8ToUtf16LeStringLiteral(s);
}

const CLASS = L("JigHairSettings");
const TITLE = L("JigHair — Settings");

const CLS_BUTTON = L("BUTTON");
const CLS_STATIC = L("STATIC");
const CLS_EDIT = L("EDIT");
const CLS_COMBO = L("COMBOBOX");
const CLS_LIST = L("LISTBOX");
const CLS_TRACK = L("msctls_trackbar32");

// Control IDs.
const ID_PRESET: u32 = 1001;
const ID_NEW: u32 = 1002;
const ID_DELETE: u32 = 1003;
const ID_NAME: u32 = 1004;
const ID_RENAME: u32 = 1005;

const ID_TB_OUTLINE: u32 = 1010;
const ID_TB_THICK: u32 = 1011;
const ID_TB_LENGTH: u32 = 1012;
const ID_TB_GAP: u32 = 1013;
const ID_TB_DOTSIZE: u32 = 1014;
const ID_TB_OFFX: u32 = 1015;
const ID_TB_OFFY: u32 = 1016;
const ID_CHK_DOT: u32 = 1020;
// Value labels live at trackbar id + 100.
const VAL_OFFSET: u32 = 100;

const ID_COLOR: u32 = 1040;
const ID_OCOLOR: u32 = 1041;
const ID_PREVIEW: u32 = 1042;

const ID_VISMODE: u32 = 1050;
const ID_APPS: u32 = 1051;
const ID_RUNNING: u32 = 1052;
const ID_ADDRUN: u32 = 1053;
const ID_REMOVE: u32 = 1054;
const ID_APPEDIT: u32 = 1055;
const ID_ADDTYPED: u32 = 1056;

const ID_SAVE: u32 = 1060;
const ID_CLOSE: u32 = 1061;

const PREVIEW_DIM: i32 = 170;

const Track = struct { id: u32, min: i32, max: i32 };
const TRACKS = [_]Track{
    .{ .id = ID_TB_OUTLINE, .min = 0, .max = 8 },
    .{ .id = ID_TB_THICK, .min = 1, .max = 20 },
    .{ .id = ID_TB_LENGTH, .min = 0, .max = 60 },
    .{ .id = ID_TB_GAP, .min = 0, .max = 40 },
    .{ .id = ID_TB_DOTSIZE, .min = 0, .max = 20 },
    .{ .id = ID_TB_OFFX, .min = -200, .max = 200 },
    .{ .id = ID_TB_OFFY, .min = -200, .max = 200 },
};

const Ui = struct {
    hwnd: win32.HWND = null,
    app: *window_mod.App = undefined,
    hinstance: win32.HINSTANCE = null,
    work: config.Settings = .{},
    edit: usize = 0,
    preview: ?renderer_mod.Renderer = null,
    font_w: usize = 0,
    custom_colors: [16]win32.COLORREF = [_]win32.COLORREF{0x00FFFFFF} ** 16,
    running: [64]config.Name = [_]config.Name{.{}} ** 64,
    running_count: usize = 0,
};

var ui: Ui = .{};
var is_open: bool = false;
var class_registered: bool = false;

fn editCh() *config.CrosshairConfig {
    return &ui.work.presets[ui.edit].crosshair;
}

/// Open (or focus) the settings window for `app`.
pub fn open(app: *window_mod.App) void {
    if (is_open and ui.hwnd != null and win32.IsWindow(ui.hwnd) != 0) {
        _ = win32.ShowWindow(ui.hwnd, win32.SW_SHOW);
        _ = win32.SetForegroundWindow(ui.hwnd);
        return;
    }

    ui = .{};
    ui.app = app;
    ui.hinstance = app.hinstance;
    ui.work = app.settings;
    ui.edit = if (ui.work.active < ui.work.preset_count) ui.work.active else 0;
    if (ui.work.preset_count == 0) ui.work = config.Settings.default();

    var icc = win32.INITCOMMONCONTROLSEX{ .dwICC = win32.ICC_BAR_CLASSES | win32.ICC_STANDARD_CLASSES };
    _ = win32.InitCommonControlsEx(&icc);
    registerClass();

    const f = win32.GetStockObject(win32.DEFAULT_GUI_FONT);
    ui.font_w = if (f) |ff| @intFromPtr(ff) else 0;

    // Desired client area -> outer window size.
    const cw: i32 = 600;
    const ch: i32 = 600;
    const style = win32.WS_CAPTION | win32.WS_SYSMENU | win32.WS_MINIMIZEBOX;
    var rc = win32.RECT{ .left = 0, .top = 0, .right = cw, .bottom = ch };
    _ = win32.AdjustWindowRect(&rc, style, win32.FALSE);

    const hwnd = win32.CreateWindowExW(
        win32.WS_EX_CONTROLPARENT,
        CLASS,
        TITLE,
        style,
        240,
        120,
        rc.right - rc.left,
        rc.bottom - rc.top,
        null,
        null,
        ui.hinstance,
        null,
    );
    if (hwnd == null) return;
    ui.hwnd = hwnd;
    ui.preview = renderer_mod.Renderer.init(PREVIEW_DIM, PREVIEW_DIM) catch null;

    is_open = true;
    buildControls();
    rebuildPresetCombo();
    rebuildAppsList();
    populateRunning();
    syncEditControls();
    syncVisMode();

    _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
}

fn registerClass() void {
    if (class_registered) return;
    var wc = win32.WNDCLASSEXW{
        .lpfnWndProc = settingsProc,
        .hInstance = win32.GetModuleHandleW(null),
        .lpszClassName = CLASS,
        // COLOR_BTNFACE + 1 so the dialog background matches standard controls.
        .hbrBackground = @ptrFromInt(16),
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
    };
    if (win32.RegisterClassExW(&wc) != 0) class_registered = true;
}

// ---- Control construction ----

fn setFont(h: win32.HWND) void {
    if (h != null and ui.font_w != 0) _ = win32.SendMessageW(h, win32.WM_SETFONT, ui.font_w, 1);
}

fn mk(class: win32.LPCWSTR, text: ?win32.LPCWSTR, style: win32.DWORD, x: i32, y: i32, w: i32, h: i32, id: u32) win32.HWND {
    const hwnd = win32.CreateWindowExW(
        0,
        class,
        text,
        win32.WS_CHILD | win32.WS_VISIBLE | style,
        x,
        y,
        w,
        h,
        ui.hwnd,
        @ptrFromInt(@as(usize, id)),
        ui.hinstance,
        null,
    );
    setFont(hwnd);
    return hwnd;
}

fn label(text: win32.LPCWSTR, x: i32, y: i32, w: i32) void {
    _ = mk(CLS_STATIC, text, win32.SS_LEFT, x, y, w, 18, 0);
}

fn mkTrack(id: u32, x: i32, y: i32, w: i32, min: i32, max: i32) void {
    const tb = mk(CLS_TRACK, null, win32.TBS_HORZ | win32.TBS_NOTICKS | win32.WS_TABSTOP, x, y, w, 28, id);
    _ = win32.SendMessageW(tb, win32.TBM_SETRANGEMIN, 0, @intCast(min));
    _ = win32.SendMessageW(tb, win32.TBM_SETRANGEMAX, 1, @intCast(max));
    // Value label to the right.
    _ = mk(CLS_STATIC, L("0"), win32.SS_LEFT, x + w + 6, y + 5, 42, 18, id + VAL_OFFSET);
}

fn buildControls() void {
    // Preset row.
    label(L("Preset"), 12, 16, 50);
    _ = mk(CLS_COMBO, null, win32.CBS_DROPDOWNLIST | win32.CBS_HASSTRINGS | win32.WS_TABSTOP | win32.WS_VSCROLL, 64, 12, 168, 240, ID_PRESET);
    _ = mk(CLS_BUTTON, L("New"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 240, 11, 50, 26, ID_NEW);
    _ = mk(CLS_BUTTON, L("Delete"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 296, 11, 60, 26, ID_DELETE);

    // Name row.
    label(L("Name"), 12, 50, 50);
    _ = mk(CLS_EDIT, null, win32.ES_AUTOHSCROLL | win32.WS_BORDER | win32.WS_TABSTOP, 64, 46, 168, 24, ID_NAME);
    _ = mk(CLS_BUTTON, L("Rename"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 240, 45, 116, 26, ID_RENAME);

    // Trackbar block.
    var y: i32 = 86;
    label(L("Outline"), 12, y + 5, 64);
    mkTrack(ID_TB_OUTLINE, 80, y, 200, 0, 8);
    y += 32;
    label(L("Thickness"), 12, y + 5, 64);
    mkTrack(ID_TB_THICK, 80, y, 200, 1, 20);
    y += 32;
    label(L("Length"), 12, y + 5, 64);
    mkTrack(ID_TB_LENGTH, 80, y, 200, 0, 60);
    y += 32;
    label(L("Gap"), 12, y + 5, 64);
    mkTrack(ID_TB_GAP, 80, y, 200, 0, 40);
    y += 32;
    _ = mk(CLS_BUTTON, L("Dot"), win32.BS_AUTOCHECKBOX | win32.WS_TABSTOP, 12, y + 4, 60, 20, ID_CHK_DOT);
    mkTrack(ID_TB_DOTSIZE, 80, y, 200, 0, 20);
    y += 32;
    label(L("Offset X"), 12, y + 5, 64);
    mkTrack(ID_TB_OFFX, 80, y, 200, -200, 200);
    y += 32;
    label(L("Offset Y"), 12, y + 5, 64);
    mkTrack(ID_TB_OFFY, 80, y, 200, -200, 200);

    // Colors.
    label(L("Color"), 12, 300, 50);
    _ = mk(CLS_BUTTON, null, win32.BS_OWNERDRAW, 64, 296, 70, 26, ID_COLOR);
    label(L("Outline"), 150, 300, 50);
    _ = mk(CLS_BUTTON, null, win32.BS_OWNERDRAW, 206, 296, 70, 26, ID_OCOLOR);

    // Live preview (owner-draw button, click ignored).
    label(L("Preview"), 396, 14, 80);
    _ = mk(CLS_BUTTON, null, win32.BS_OWNERDRAW, 396, 34, PREVIEW_DIM, PREVIEW_DIM, ID_PREVIEW);

    // Visibility.
    label(L("Show crosshair:"), 12, 348, 110);
    _ = mk(CLS_COMBO, null, win32.CBS_DROPDOWNLIST | win32.CBS_HASSTRINGS | win32.WS_TABSTOP, 128, 344, 228, 120, ID_VISMODE);

    label(L("Target apps (foreground mode)"), 12, 380, 260);
    label(L("Chosen"), 12, 400, 80);
    _ = mk(CLS_LIST, null, win32.LBS_NOTIFY | win32.LBS_HASSTRINGS | win32.LBS_NOINTEGRALHEIGHT | win32.WS_BORDER | win32.WS_VSCROLL | win32.WS_TABSTOP, 12, 420, 200, 120, ID_APPS);
    label(L("Running"), 384, 400, 80);
    _ = mk(CLS_LIST, null, win32.LBS_NOTIFY | win32.LBS_HASSTRINGS | win32.LBS_NOINTEGRALHEIGHT | win32.WS_BORDER | win32.WS_VSCROLL | win32.WS_TABSTOP, 384, 420, 182, 120, ID_RUNNING);
    _ = mk(CLS_BUTTON, L("\u{2190} Add"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 224, 430, 148, 26, ID_ADDRUN);
    _ = mk(CLS_BUTTON, L("Remove"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 224, 462, 148, 26, ID_REMOVE);

    label(L("Add by name"), 12, 548, 90);
    _ = mk(CLS_EDIT, null, win32.ES_AUTOHSCROLL | win32.WS_BORDER | win32.WS_TABSTOP, 104, 545, 160, 24, ID_APPEDIT);
    _ = mk(CLS_BUTTON, L("Add"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 270, 544, 70, 26, ID_ADDTYPED);

    // Save / Close.
    _ = mk(CLS_BUTTON, L("Save && Apply"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 384, 544, 110, 28, ID_SAVE);
    _ = mk(CLS_BUTTON, L("Close"), win32.BS_PUSHBUTTON | win32.WS_TABSTOP, 500, 544, 66, 28, ID_CLOSE);
}

// ---- Wide-string helpers ----

var wbuf: [256]u16 = undefined;

fn toW(s: []const u8) win32.LPARAM {
    const n = std.unicode.utf8ToUtf16Le(wbuf[0 .. wbuf.len - 1], s) catch 0;
    wbuf[n] = 0;
    return @bitCast(@intFromPtr(&wbuf));
}

fn addString(ctl: win32.HWND, msg: win32.UINT, s: []const u8) void {
    _ = win32.SendMessageW(ctl, msg, 0, toW(s));
}

// ---- Sync UI <- working state ----

fn rebuildPresetCombo() void {
    const combo = win32.GetDlgItem(ui.hwnd, @intCast(ID_PRESET));
    _ = win32.SendMessageW(combo, win32.CB_RESETCONTENT, 0, 0);
    var i: usize = 0;
    while (i < ui.work.preset_count) : (i += 1) {
        addString(combo, win32.CB_ADDSTRING, ui.work.presets[i].name.slice());
    }
    _ = win32.SendMessageW(combo, win32.CB_SETCURSEL, ui.edit, 0);
}

fn rebuildAppsList() void {
    const list = win32.GetDlgItem(ui.hwnd, @intCast(ID_APPS));
    _ = win32.SendMessageW(list, win32.LB_RESETCONTENT, 0, 0);
    var i: usize = 0;
    while (i < ui.work.app_count) : (i += 1) {
        addString(list, win32.LB_ADDSTRING, ui.work.apps[i].slice());
    }
}

fn syncVisMode() void {
    const combo = win32.GetDlgItem(ui.hwnd, @intCast(ID_VISMODE));
    _ = win32.SendMessageW(combo, win32.CB_RESETCONTENT, 0, 0);
    addString(combo, win32.CB_ADDSTRING, "Always");
    addString(combo, win32.CB_ADDSTRING, "Only when a chosen app is focused");
    const sel: usize = if (ui.work.visibility_mode == .foreground_apps) 1 else 0;
    _ = win32.SendMessageW(combo, win32.CB_SETCURSEL, sel, 0);
}

fn setTrack(id: u32, val: i32) void {
    _ = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(id)), win32.TBM_SETPOS, 1, @intCast(val));
    setValueLabel(id, val);
}

fn setValueLabel(id: u32, val: i32) void {
    var nbuf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&nbuf, "{d}", .{val}) catch "?";
    _ = win32.SetWindowTextW(win32.GetDlgItem(ui.hwnd, @intCast(id + VAL_OFFSET)), @ptrCast(toWZ(s)));
}

/// toW that returns a null-terminated pointer for SetWindowTextW.
fn toWZ(s: []const u8) [*:0]u16 {
    const n = std.unicode.utf8ToUtf16Le(wbuf[0 .. wbuf.len - 1], s) catch 0;
    wbuf[n] = 0;
    return @ptrCast(&wbuf);
}

fn syncEditControls() void {
    const c = editCh();
    setTrack(ID_TB_OUTLINE, c.outline);
    setTrack(ID_TB_THICK, c.thickness);
    setTrack(ID_TB_LENGTH, c.length);
    setTrack(ID_TB_GAP, c.gap);
    setTrack(ID_TB_DOTSIZE, c.dot_size);
    setTrack(ID_TB_OFFX, c.offset_x);
    setTrack(ID_TB_OFFY, c.offset_y);
    _ = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(ID_CHK_DOT)), win32.BM_SETCHECK, if (c.dot) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
    _ = win32.SetWindowTextW(win32.GetDlgItem(ui.hwnd, @intCast(ID_NAME)), @ptrCast(toWZ(ui.work.presets[ui.edit].name.slice())));
    refreshPreview();
    invalidate(ID_COLOR);
    invalidate(ID_OCOLOR);
}

fn invalidate(id: u32) void {
    _ = win32.InvalidateRect(win32.GetDlgItem(ui.hwnd, @intCast(id)), null, win32.TRUE);
}

fn refreshPreview() void {
    if (ui.preview) |*pv| crosshair.draw(pv, editCh().*);
    invalidate(ID_PREVIEW);
}

// ---- Colors ----

fn cref(c: [4]u8) win32.COLORREF {
    return @as(u32, c[0]) | (@as(u32, c[1]) << 8) | (@as(u32, c[2]) << 16);
}

fn chooseColor(outline: bool) void {
    const c = editCh();
    const cur = if (outline) c.outline_color else c.color;
    var cc = win32.CHOOSECOLORW{
        .hwndOwner = ui.hwnd,
        .rgbResult = cref(cur),
        .lpCustColors = &ui.custom_colors,
        .Flags = win32.CC_RGBINIT | win32.CC_FULLOPEN | win32.CC_ANYCOLOR,
    };
    if (win32.ChooseColorW(&cc) == 0) return;
    const rgb = cc.rgbResult;
    const r: u8 = @truncate(rgb & 0xFF);
    const g: u8 = @truncate((rgb >> 8) & 0xFF);
    const b: u8 = @truncate((rgb >> 16) & 0xFF);
    if (outline) {
        c.outline_color = .{ r, g, b, c.outline_color[3] };
        invalidate(ID_OCOLOR);
    } else {
        c.color = .{ r, g, b, c.color[3] };
        invalidate(ID_COLOR);
    }
    refreshPreview();
}

// ---- Preset operations ----

fn onSelectPreset() void {
    const sel = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(ID_PRESET)), win32.CB_GETCURSEL, 0, 0);
    if (sel < 0) return;
    const idx: usize = @intCast(sel);
    if (idx >= ui.work.preset_count) return;
    ui.edit = idx;
    syncEditControls();
}

fn onNew() void {
    if (ui.work.preset_count >= config.MAX_PRESETS) return;
    const i = ui.work.preset_count;
    ui.work.presets[i].crosshair = editCh().*; // clone current
    var nbuf: [32]u8 = undefined;
    const nm = std.fmt.bufPrint(&nbuf, "preset {d}", .{i + 1}) catch "preset";
    ui.work.presets[i].name = .{};
    ui.work.presets[i].name.set(nm);
    ui.work.preset_count += 1;
    ui.edit = i;
    rebuildPresetCombo();
    syncEditControls();
}

fn onDelete() void {
    if (ui.work.preset_count <= 1) return;
    var i = ui.edit;
    while (i + 1 < ui.work.preset_count) : (i += 1) {
        ui.work.presets[i] = ui.work.presets[i + 1];
    }
    ui.work.preset_count -= 1;
    if (ui.edit >= ui.work.preset_count) ui.edit = ui.work.preset_count - 1;
    rebuildPresetCombo();
    syncEditControls();
}

fn onRename() void {
    var u8buf: [config.NAME_CAP]u8 = undefined;
    const name = getText(ID_NAME, &u8buf);
    if (name.len == 0) return;
    ui.work.presets[ui.edit].name = .{};
    ui.work.presets[ui.edit].name.set(name);
    rebuildPresetCombo();
}

// ---- Apps ----

fn appExists(name: []const u8) bool {
    var i: usize = 0;
    while (i < ui.work.app_count) : (i += 1) {
        if (ui.work.apps[i].eqlIgnoreCase(name)) return true;
    }
    return false;
}

fn addApp(name: []const u8) void {
    if (name.len == 0 or ui.work.app_count >= config.MAX_APPS or appExists(name)) return;
    ui.work.apps[ui.work.app_count] = .{};
    ui.work.apps[ui.work.app_count].set(name);
    ui.work.app_count += 1;
    rebuildAppsList();
}

fn onAddTyped() void {
    var u8buf: [config.NAME_CAP]u8 = undefined;
    const name = getText(ID_APPEDIT, &u8buf);
    addApp(name);
    _ = win32.SetWindowTextW(win32.GetDlgItem(ui.hwnd, @intCast(ID_APPEDIT)), L(""));
}

fn onAddRunning() void {
    const sel = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(ID_RUNNING)), win32.LB_GETCURSEL, 0, 0);
    if (sel < 0) return;
    const idx: usize = @intCast(sel);
    if (idx >= ui.running_count) return;
    addApp(ui.running[idx].slice());
}

fn onRemoveApp() void {
    const sel = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(ID_APPS)), win32.LB_GETCURSEL, 0, 0);
    if (sel < 0) return;
    var i: usize = @intCast(sel);
    if (i >= ui.work.app_count) return;
    while (i + 1 < ui.work.app_count) : (i += 1) {
        ui.work.apps[i] = ui.work.apps[i + 1];
    }
    ui.work.app_count -= 1;
    rebuildAppsList();
}

fn getText(id: u32, out: []u8) []const u8 {
    var w: [256]u16 = undefined;
    const n = win32.GetWindowTextW(win32.GetDlgItem(ui.hwnd, @intCast(id)), &w, 256);
    if (n <= 0) return out[0..0];
    const len = std.unicode.utf16LeToUtf8(out, w[0..@intCast(n)]) catch return out[0..0];
    return out[0..len];
}

// ---- Running apps enumeration ----

fn runningExists(name: []const u8) bool {
    var i: usize = 0;
    while (i < ui.running_count) : (i += 1) {
        if (ui.running[i].eqlIgnoreCase(name)) return true;
    }
    return false;
}

fn enumProc(hwnd: win32.HWND, lparam: win32.LPARAM) callconv(win32.WINAPI) win32.BOOL {
    _ = lparam;
    if (win32.IsWindowVisible(hwnd) == 0) return win32.TRUE;
    if (win32.GetWindowTextLengthW(hwnd) == 0) return win32.TRUE;
    if (ui.running_count >= ui.running.len) return win32.FALSE;

    var pid: win32.DWORD = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0) return win32.TRUE;

    const h = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, win32.FALSE, pid);
    if (h == null) return win32.TRUE;
    defer _ = win32.CloseHandle(h);

    var wpath: [260]u16 = undefined;
    var size: win32.DWORD = wpath.len;
    if (win32.QueryFullProcessImageNameW(h, 0, &wpath, &size) == 0) return win32.TRUE;
    const path = wpath[0..@min(@as(usize, size), wpath.len)];

    var start: usize = 0;
    for (path, 0..) |ch, i| {
        if (ch == '\\' or ch == '/') start = i + 1;
    }
    var u8buf: [260]u8 = undefined;
    const n = std.unicode.utf16LeToUtf8(&u8buf, path[start..]) catch return win32.TRUE;
    const base = u8buf[0..n];
    if (base.len == 0 or runningExists(base)) return win32.TRUE;

    ui.running[ui.running_count] = .{};
    ui.running[ui.running_count].set(base);
    ui.running_count += 1;
    return win32.TRUE;
}

fn populateRunning() void {
    ui.running_count = 0;
    _ = win32.EnumWindows(enumProc, 0);
    const list = win32.GetDlgItem(ui.hwnd, @intCast(ID_RUNNING));
    _ = win32.SendMessageW(list, win32.LB_RESETCONTENT, 0, 0);
    var i: usize = 0;
    while (i < ui.running_count) : (i += 1) {
        addString(list, win32.LB_ADDSTRING, ui.running[i].slice());
    }
}

// ---- Save ----

fn onSave() void {
    ui.work.active = ui.edit;
    ui.app.settings = ui.work;
    _ = config.save(&ui.app.settings);
    window_mod.applyVisibilityMode(ui.app);
}

// ---- Painting ----

fn drawSwatch(dis: *win32.DRAWITEMSTRUCT, color: [4]u8) void {
    const border = win32.CreateSolidBrush(0x00404040);
    _ = win32.FillRect(dis.hDC, &dis.rcItem, border);
    _ = win32.DeleteObject(@ptrCast(border));
    var inner = dis.rcItem;
    inner.left += 2;
    inner.top += 2;
    inner.right -= 2;
    inner.bottom -= 2;
    const br = win32.CreateSolidBrush(cref(color));
    _ = win32.FillRect(dis.hDC, &inner, br);
    _ = win32.DeleteObject(@ptrCast(br));
}

fn drawPreview(dis: *win32.DRAWITEMSTRUCT) void {
    // Neutral dark backdrop so any crosshair colour reads well.
    const bg = win32.CreateSolidBrush(0x00202020);
    _ = win32.FillRect(dis.hDC, &dis.rcItem, bg);
    _ = win32.DeleteObject(@ptrCast(bg));
    if (ui.preview) |*pv| {
        const blend = win32.BLENDFUNCTION{
            .BlendOp = win32.AC_SRC_OVER,
            .BlendFlags = 0,
            .SourceConstantAlpha = 255,
            .AlphaFormat = win32.AC_SRC_ALPHA,
        };
        _ = win32.AlphaBlend(
            dis.hDC,
            dis.rcItem.left,
            dis.rcItem.top,
            PREVIEW_DIM,
            PREVIEW_DIM,
            pv.mem_dc,
            0,
            0,
            PREVIEW_DIM,
            PREVIEW_DIM,
            blend,
        );
    }
}

// ---- Window procedure ----

fn settingsProc(hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) callconv(win32.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_COMMAND => {
            const id: u32 = @truncate(wparam & 0xFFFF);
            const code: u16 = @truncate((wparam >> 16) & 0xFFFF);
            switch (id) {
                ID_PRESET => if (code == win32.CBN_SELCHANGE) onSelectPreset(),
                ID_VISMODE => if (code == win32.CBN_SELCHANGE) {
                    const sel = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(ID_VISMODE)), win32.CB_GETCURSEL, 0, 0);
                    ui.work.visibility_mode = if (sel == 1) .foreground_apps else .always;
                },
                ID_NEW => onNew(),
                ID_DELETE => onDelete(),
                ID_RENAME => onRename(),
                ID_CHK_DOT => {
                    const checked = win32.SendMessageW(win32.GetDlgItem(ui.hwnd, @intCast(ID_CHK_DOT)), win32.BM_GETCHECK, 0, 0);
                    editCh().dot = (checked == @as(win32.LRESULT, @intCast(win32.BST_CHECKED)));
                    refreshPreview();
                },
                ID_COLOR => chooseColor(false),
                ID_OCOLOR => chooseColor(true),
                ID_ADDRUN => onAddRunning(),
                ID_REMOVE => onRemoveApp(),
                ID_ADDTYPED => onAddTyped(),
                ID_SAVE => onSave(),
                ID_CLOSE => _ = win32.DestroyWindow(hwnd),
                else => {},
            }
            return 0;
        },
        win32.WM_HSCROLL => {
            const tb: win32.HWND = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const id: u32 = @intCast(win32.GetDlgCtrlID(tb));
            const pos: i32 = @intCast(win32.SendMessageW(tb, win32.TBM_GETPOS, 0, 0));
            const c = editCh();
            switch (id) {
                ID_TB_OUTLINE => c.outline = pos,
                ID_TB_THICK => c.thickness = pos,
                ID_TB_LENGTH => c.length = pos,
                ID_TB_GAP => c.gap = pos,
                ID_TB_DOTSIZE => c.dot_size = pos,
                ID_TB_OFFX => c.offset_x = pos,
                ID_TB_OFFY => c.offset_y = pos,
                else => return 0,
            }
            setValueLabel(id, pos);
            refreshPreview();
            return 0;
        },
        win32.WM_DRAWITEM => {
            const dis: *win32.DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            switch (dis.CtlID) {
                ID_PREVIEW => drawPreview(dis),
                ID_COLOR => drawSwatch(dis, editCh().color),
                ID_OCOLOR => drawSwatch(dis, editCh().outline_color),
                else => {},
            }
            return 1;
        },
        win32.WM_CLOSE => {
            _ = win32.DestroyWindow(hwnd);
            return 0;
        },
        win32.WM_DESTROY => {
            // Closing settings must NOT quit the app — just release UI resources.
            if (ui.preview) |*pv| pv.deinit();
            ui.preview = null;
            ui.hwnd = null;
            is_open = false;
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
