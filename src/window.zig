const std = @import("std");
const win32 = @import("win32.zig");
const renderer_mod = @import("renderer.zig");
const crosshair_mod = @import("crosshair.zig");
const config_mod = @import("config.zig");
const settings_ui = @import("settings_ui.zig");

const Renderer = renderer_mod.Renderer;

pub const HOTKEY_QUIT: i32 = 1;
const TRAY_UID: u32 = 1;

const ID_SHOW: u32 = 1;
const ID_RELOAD: u32 = 2;
const ID_OPENCFG: u32 = 3;
const ID_QUIT: u32 = 4;
const ID_SETTINGS: u32 = 5;

const TIP = std.unicode.utf8ToUtf16LeStringLiteral("JigHair");

// Mirrors config.example.json; seeded into %APPDATA% on first "Open config folder".
const default_config =
    \\{
    \\  "active": "default",
    \\  "visibility": { "mode": "always", "match": "process_name", "apps": [] },
    \\  "presets": {
    \\    "default": { "color": [0, 255, 0, 255], "outline_color": [0, 0, 0, 255], "outline": 1, "thickness": 2, "length": 10, "gap": 4, "dot": true, "dot_size": 2, "offset_x": 0, "offset_y": 0 }
    \\  }
    \\}
    \\
;

/// Shared runtime state, reached from the control window via GWLP_USERDATA.
pub const App = struct {
    overlay: win32.HWND,
    renderer: *Renderer,
    settings: config_mod.Settings,
    visible: bool,
    hinstance: win32.HINSTANCE,
    /// Primary monitor; used in "always" mode and as a fallback.
    primary: crosshair_mod.MonitorRect,
    /// Monitor the crosshair is currently placed on (== primary in "always" mode;
    /// follows the focused target app in "foreground_apps" mode).
    mon: crosshair_mod.MonitorRect,
};

/// Set in main when foreground mode is active, so the WinEvent callback (which
/// carries no user pointer) can reach the single App. Single-threaded — the hook
/// fires on our message loop — so a plain global is safe.
pub var foreground_app: ?*App = null;

/// The installed EVENT_SYSTEM_FOREGROUND hook, or null when not in foreground mode.
var fg_hook: win32.HWINEVENTHOOK = null;

/// Visual overlay window: draws once, no interaction.
pub fn overlayProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(win32.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

/// Hidden control window: owns the tray icon, context menu, and quit hotkey.
pub fn controlProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(win32.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_TRAYICON => {
            const event: u32 = @truncate(@as(usize, @bitCast(lparam)));
            switch (event & 0xFFFF) {
                win32.WM_RBUTTONUP, win32.WM_CONTEXTMENU => showMenu(hwnd),
                win32.WM_LBUTTONDBLCLK => {
                    if (appOf(hwnd)) |a| toggleVisible(a);
                },
                else => {},
            }
            return 0;
        },
        win32.WM_COMMAND => {
            const id: u32 = @truncate(wparam & 0xFFFF);
            if (appOf(hwnd)) |a| {
                switch (id) {
                    ID_SETTINGS => settings_ui.open(a),
                    ID_SHOW => toggleVisible(a),
                    ID_RELOAD => reload(a),
                    ID_OPENCFG => openConfigFolder(),
                    ID_QUIT => win32.PostQuitMessage(0),
                    else => {},
                }
            }
            return 0;
        },
        win32.WM_HOTKEY => {
            if (@as(i32, @intCast(wparam)) == HOTKEY_QUIT) win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn appOf(hwnd: win32.HWND) ?*App {
    const v = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
    if (v == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(v)));
}

fn toggleVisible(app: *App) void {
    app.visible = !app.visible;
    _ = win32.ShowWindow(app.overlay, if (app.visible) win32.SW_SHOWNOACTIVATE else win32.SW_HIDE);
}

/// Re-read the config from disk and re-apply the active preset.
fn reload(app: *App) void {
    app.settings = config_mod.load();
    redraw(app);
}

/// Resize/reposition the overlay for the active preset, rebuild the DIB at the
/// new size, draw, and present. Keeps the old renderer on allocation failure.
/// Reused by config reload and (later) the settings UI.
pub fn redraw(app: *App) void {
    const cfg = app.settings.activeCrosshair();
    const place = crosshair_mod.placement(cfg, app.mon);
    _ = win32.SetWindowPos(
        app.overlay,
        null,
        place.x,
        place.y,
        place.dim,
        place.dim,
        win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
    );

    const new_renderer = Renderer.init(place.dim, place.dim) catch return;
    app.renderer.deinit();
    app.renderer.* = new_renderer;

    crosshair_mod.draw(app.renderer, cfg);
    app.renderer.present(app.overlay) catch {};
    if (app.visible) _ = win32.ShowWindow(app.overlay, win32.SW_SHOWNOACTIVATE);
}

// ---- Foreground auto-show ----

/// WinEvent callback for EVENT_SYSTEM_FOREGROUND. Re-evaluates on every focus
/// change. Args beyond the global App are unused.
pub fn winEventProc(
    hook: win32.HWINEVENTHOOK,
    event: win32.DWORD,
    hwnd: win32.HWND,
    id_object: win32.LONG,
    id_child: win32.LONG,
    id_thread: win32.DWORD,
    time: win32.DWORD,
) callconv(win32.WINAPI) void {
    _ = hook;
    _ = event;
    _ = hwnd;
    _ = id_object;
    _ = id_child;
    _ = id_thread;
    _ = time;
    if (foreground_app) |app| evaluateForeground(app);
}

/// Show the crosshair (on the focused window's monitor) iff the foreground
/// process matches the allowlist; hide it otherwise.
pub fn evaluateForeground(app: *App) void {
    const fg = win32.GetForegroundWindow();
    if (fg != null and processMatches(app, fg)) {
        app.mon = monitorOf(fg) orelse app.primary;
        app.visible = true;
        redraw(app); // repositions onto app.mon and shows (visible == true)
    } else {
        app.visible = false;
        _ = win32.ShowWindow(app.overlay, win32.SW_HIDE);
    }
}

/// True if `hwnd`'s owning process basename is in the app allowlist.
/// The foreground window can vanish between event and query, so every call is guarded.
fn processMatches(app: *App, hwnd: win32.HWND) bool {
    if (app.settings.app_count == 0) return false;

    var pid: win32.DWORD = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0) return false;

    const h = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, win32.FALSE, pid);
    if (h == null) return false;
    defer _ = win32.CloseHandle(h);

    var wbuf: [260]u16 = undefined;
    var size: win32.DWORD = wbuf.len;
    if (win32.QueryFullProcessImageNameW(h, 0, &wbuf, &size) == 0) return false;
    const wpath = wbuf[0..@min(@as(usize, size), wbuf.len)];

    // Basename = text after the last path separator.
    var start: usize = 0;
    for (wpath, 0..) |c, i| {
        if (c == '\\' or c == '/') start = i + 1;
    }

    var u8buf: [260]u8 = undefined;
    const n = std.unicode.utf16LeToUtf8(&u8buf, wpath[start..]) catch return false;
    const base = u8buf[0..n];

    var k: usize = 0;
    while (k < app.settings.app_count) : (k += 1) {
        if (app.settings.apps[k].eqlIgnoreCase(base)) return true;
    }
    return false;
}

/// Pixel rect of the monitor displaying `hwnd`, or null if it can't be resolved.
fn monitorOf(hwnd: win32.HWND) ?crosshair_mod.MonitorRect {
    const hmon = win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONEAREST);
    if (hmon == null) return null;
    var mi = win32.MONITORINFO{};
    if (win32.GetMonitorInfoW(hmon, &mi) == 0) return null;
    const r = mi.rcMonitor;
    return .{ .x = r.left, .y = r.top, .w = r.right - r.left, .h = r.bottom - r.top };
}

/// Install/uninstall the foreground hook to match the current visibility mode and
/// (re)apply visibility. Safe to call repeatedly — e.g. after the settings UI
/// changes the mode at runtime. Call once at startup and on every config change.
pub fn applyVisibilityMode(app: *App) void {
    if (app.settings.visibility_mode == .foreground_apps) {
        foreground_app = app;
        if (fg_hook == null) {
            fg_hook = win32.SetWinEventHook(
                win32.EVENT_SYSTEM_FOREGROUND,
                win32.EVENT_SYSTEM_FOREGROUND,
                null,
                winEventProc,
                0,
                0,
                win32.WINEVENT_OUTOFCONTEXT,
            );
        }
        evaluateForeground(app); // sync to whatever is focused right now
    } else {
        removeForegroundHook();
        app.mon = app.primary;
        app.visible = true;
        redraw(app);
        _ = win32.ShowWindow(app.overlay, win32.SW_SHOWNOACTIVATE);
    }
}

pub fn removeForegroundHook() void {
    if (fg_hook != null) {
        _ = win32.UnhookWinEvent(fg_hook);
        fg_hook = null;
    }
}

fn label(comptime s: []const u8) win32.LPCWSTR {
    return std.unicode.utf8ToUtf16LeStringLiteral(s);
}

fn showMenu(owner: win32.HWND) void {
    const app = appOf(owner) orelse return;
    var pt: win32.POINT = undefined;
    _ = win32.GetCursorPos(&pt);

    const menu = win32.CreatePopupMenu() orelse return;
    defer _ = win32.DestroyMenu(menu);

    _ = win32.AppendMenuW(menu, win32.MF_STRING, ID_SETTINGS, label("Settings\u{2026}"));
    const show_flag: win32.UINT = win32.MF_STRING | (if (app.visible) win32.MF_CHECKED else win32.MF_UNCHECKED);
    _ = win32.AppendMenuW(menu, show_flag, ID_SHOW, label("Show crosshair"));
    _ = win32.AppendMenuW(menu, win32.MF_STRING, ID_RELOAD, label("Reload config"));
    _ = win32.AppendMenuW(menu, win32.MF_STRING, ID_OPENCFG, label("Open config folder"));
    _ = win32.AppendMenuW(menu, win32.MF_SEPARATOR, 0, null);
    _ = win32.AppendMenuW(menu, win32.MF_STRING, ID_QUIT, label("Quit JigHair"));

    // Foreground + trailing WM_NULL so the menu dismisses on click-away (KB135788).
    _ = win32.SetForegroundWindow(owner);
    _ = win32.TrackPopupMenu(menu, win32.TPM_RIGHTBUTTON, pt.x, pt.y, 0, owner, null);
    _ = win32.PostMessageW(owner, win32.WM_NULL, 0, 0);
}

/// Open %APPDATA%\JigHair in Explorer, seeding a default config.json if absent.
fn openConfigFolder() void {
    const allocator = std.heap.page_allocator;
    const paths = config_mod.pathsW(allocator) catch return;
    defer allocator.free(paths.dir);
    defer allocator.free(paths.file);

    _ = win32.CreateDirectoryW(paths.dir, null);

    // CREATE_NEW writes only when the file does not exist, so an existing user
    // config is never clobbered.
    const h = win32.CreateFileW(
        paths.file,
        win32.GENERIC_WRITE,
        0,
        null,
        win32.CREATE_NEW,
        win32.FILE_ATTRIBUTE_NORMAL,
        null,
    );
    if (h != win32.INVALID_HANDLE_VALUE) {
        var written: win32.DWORD = 0;
        _ = win32.WriteFile(h, default_config, @intCast(default_config.len), &written, null);
        _ = win32.CloseHandle(h);
    }

    _ = win32.ShellExecuteW(null, label("open"), paths.dir, null, null, win32.SW_SHOWNORMAL);
}

pub fn addTray(owner: win32.HWND) void {
    var nid = win32.NOTIFYICONDATAW{ .hWnd = owner };
    nid.uID = TRAY_UID;
    nid.uFlags = win32.NIF_MESSAGE | win32.NIF_ICON | win32.NIF_TIP;
    nid.uCallbackMessage = win32.WM_TRAYICON;
    nid.hIcon = win32.LoadIconW(null, win32.IDI_APPLICATION);
    @memcpy(nid.szTip[0..TIP.len], TIP[0..TIP.len]);
    _ = win32.Shell_NotifyIconW(win32.NIM_ADD, &nid);
}

pub fn removeTray(owner: win32.HWND) void {
    var nid = win32.NOTIFYICONDATAW{ .hWnd = owner };
    nid.uID = TRAY_UID;
    _ = win32.Shell_NotifyIconW(win32.NIM_DELETE, &nid);
}
