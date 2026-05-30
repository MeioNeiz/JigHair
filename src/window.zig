const std = @import("std");
const win32 = @import("win32.zig");
const renderer_mod = @import("renderer.zig");
const crosshair_mod = @import("crosshair.zig");
const config_mod = @import("config.zig");

const Renderer = renderer_mod.Renderer;

pub const HOTKEY_QUIT: i32 = 1;
const TRAY_UID: u32 = 1;

const ID_SHOW: u32 = 1;
const ID_RELOAD: u32 = 2;
const ID_OPENCFG: u32 = 3;
const ID_QUIT: u32 = 4;

const TIP = std.unicode.utf8ToUtf16LeStringLiteral("JigHair");

// Mirrors config.example.json; seeded into %APPDATA% on first "Open config folder".
const default_config =
    \\{
    \\  "crosshair": {
    \\    "color": [0, 255, 0, 255],
    \\    "outline_color": [0, 0, 0, 255],
    \\    "outline": 1,
    \\    "thickness": 2,
    \\    "length": 10,
    \\    "gap": 4,
    \\    "dot": true,
    \\    "dot_size": 2,
    \\    "offset_x": 0,
    \\    "offset_y": 0
    \\  }
    \\}
    \\
;

/// Shared runtime state, reached from the control window via GWLP_USERDATA.
pub const App = struct {
    overlay: win32.HWND,
    renderer: *Renderer,
    cfg: config_mod.Config,
    visible: bool,
    screen_w: i32,
    screen_h: i32,
};

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

/// Re-read the config and re-apply: resize/reposition the window, rebuild the
/// DIB at the new size, redraw, present. Keeps the old renderer on failure.
fn reload(app: *App) void {
    const new_cfg = config_mod.load();
    const place = crosshair_mod.placement(new_cfg.crosshair, app.screen_w, app.screen_h);
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

    crosshair_mod.draw(app.renderer, new_cfg.crosshair);
    app.renderer.present(app.overlay) catch {};
    app.cfg = new_cfg;
    if (app.visible) _ = win32.ShowWindow(app.overlay, win32.SW_SHOWNOACTIVATE);
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
