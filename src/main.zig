const std = @import("std");
const win32 = @import("win32.zig");
const window_mod = @import("window.zig");
const renderer_mod = @import("renderer.zig");
const crosshair_mod = @import("crosshair.zig");
const config_mod = @import("config.zig");

const OVERLAY_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("JigHairWindow");
const CONTROL_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("JigHairControl");
const TITLE = std.unicode.utf8ToUtf16LeStringLiteral("JigHair");

pub fn main() !void {
    // Must run before any window/metrics call, else SM_CXSCREEN etc. return
    // logical pixels and the overlay is mis-sized/blurry on scaled displays.
    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    const cfg = config_mod.load();
    const hinstance = win32.GetModuleHandleW(null);

    var overlay_wc = win32.WNDCLASSEXW{
        .lpfnWndProc = window_mod.overlayProc,
        .hInstance = hinstance,
        .lpszClassName = OVERLAY_CLASS,
    };
    if (win32.RegisterClassExW(&overlay_wc) == 0) return error.RegisterClassFailed;

    var control_wc = win32.WNDCLASSEXW{
        .lpfnWndProc = window_mod.controlProc,
        .hInstance = hinstance,
        .lpszClassName = CONTROL_CLASS,
    };
    if (win32.RegisterClassExW(&control_wc) == 0) return error.RegisterClassFailed;

    const screen_w = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    const screen_h = win32.GetSystemMetrics(win32.SM_CYSCREEN);
    const place = crosshair_mod.placement(cfg.crosshair, screen_w, screen_h);

    // Small bounded overlay window: far less surface for DWM to composite than a
    // full-screen layered window. Click-through + no-activate = zero input lag.
    const ex_style =
        win32.WS_EX_LAYERED |
        win32.WS_EX_TRANSPARENT |
        win32.WS_EX_TOPMOST |
        win32.WS_EX_TOOLWINDOW |
        win32.WS_EX_NOACTIVATE;
    const overlay = win32.CreateWindowExW(
        ex_style,
        OVERLAY_CLASS,
        TITLE,
        win32.WS_POPUP | win32.WS_VISIBLE,
        place.x,
        place.y,
        place.dim,
        place.dim,
        null,
        null,
        hinstance,
        null,
    );
    if (overlay == null) return error.CreateWindowFailed;

    // Hidden control window: never shown; just receives tray/menu/hotkey messages.
    const control = win32.CreateWindowExW(
        0,
        CONTROL_CLASS,
        TITLE,
        win32.WS_POPUP,
        0,
        0,
        0,
        0,
        null,
        null,
        hinstance,
        null,
    );
    if (control == null) return error.CreateWindowFailed;

    _ = win32.RegisterHotKey(
        control,
        window_mod.HOTKEY_QUIT,
        win32.MOD_CONTROL | win32.MOD_ALT | win32.MOD_NOREPEAT,
        win32.VK_F8,
    );
    defer _ = win32.UnregisterHotKey(control, window_mod.HOTKEY_QUIT);

    var renderer = try renderer_mod.Renderer.init(place.dim, place.dim);
    defer renderer.deinit();

    var app = window_mod.App{
        .overlay = overlay,
        .renderer = &renderer,
        .cfg = cfg,
        .visible = true,
        .screen_w = screen_w,
        .screen_h = screen_h,
    };
    _ = win32.SetWindowLongPtrW(control, win32.GWLP_USERDATA, @bitCast(@intFromPtr(&app)));

    window_mod.addTray(control);
    defer window_mod.removeTray(control);

    crosshair_mod.draw(&renderer, cfg.crosshair);
    try renderer.present(overlay);
    _ = win32.ShowWindow(overlay, win32.SW_SHOWNOACTIVATE);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}
