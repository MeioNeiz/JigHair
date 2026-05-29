const std = @import("std");
const win32 = @import("win32.zig");
const window_mod = @import("window.zig");
const renderer_mod = @import("renderer.zig");
const crosshair_mod = @import("crosshair.zig");
const config_mod = @import("config.zig");

const CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("JigHairWindow");
const TITLE = std.unicode.utf8ToUtf16LeStringLiteral("jig+hair");

pub fn main() !void {
    // Must run before any window/metrics call, else SM_CXSCREEN etc. return
    // logical pixels and the overlay is mis-sized/blurry on scaled displays.
    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = config_mod.load(allocator);

    const hinstance = win32.GetModuleHandleW(null);

    var wc = win32.WNDCLASSEXW{
        .lpfnWndProc = window_mod.wndProc,
        .hInstance = hinstance,
        .lpszClassName = CLASS_NAME,
    };
    if (win32.RegisterClassExW(&wc) == 0) return error.RegisterClassFailed;

    // Small bounded window sized to the crosshair, centered (+offset) on the primary
    // monitor. Far less surface for DWM to composite than a full-screen overlay.
    const screen_w = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    const screen_h = win32.GetSystemMetrics(win32.SM_CYSCREEN);

    const dim = crosshair_mod.windowSize(cfg.crosshair);
    const center_x = @divTrunc(screen_w, 2) + cfg.crosshair.offset_x;
    const center_y = @divTrunc(screen_h, 2) + cfg.crosshair.offset_y;
    const win_x = std.math.clamp(center_x - @divTrunc(dim, 2), 0, @max(0, screen_w - dim));
    const win_y = std.math.clamp(center_y - @divTrunc(dim, 2), 0, @max(0, screen_h - dim));

    const ex_style =
        win32.WS_EX_LAYERED |
        win32.WS_EX_TRANSPARENT |
        win32.WS_EX_TOPMOST |
        win32.WS_EX_TOOLWINDOW |
        win32.WS_EX_NOACTIVATE;
    const style = win32.WS_POPUP | win32.WS_VISIBLE;

    const hwnd = win32.CreateWindowExW(
        ex_style,
        CLASS_NAME,
        TITLE,
        style,
        win_x,
        win_y,
        dim,
        dim,
        null,
        null,
        hinstance,
        null,
    );
    if (hwnd == null) return error.CreateWindowFailed;

    // Ctrl+Alt+F8 to quit (no tray icon yet).
    _ = win32.RegisterHotKey(
        hwnd,
        window_mod.HOTKEY_QUIT,
        win32.MOD_CONTROL | win32.MOD_ALT | win32.MOD_NOREPEAT,
        win32.VK_F8,
    );

    var renderer = try renderer_mod.Renderer.init(dim, dim);
    defer renderer.deinit();

    crosshair_mod.draw(&renderer, cfg.crosshair);
    try renderer.present(hwnd);

    _ = win32.ShowWindow(hwnd, win32.SW_SHOWNOACTIVATE);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }

    _ = win32.UnregisterHotKey(hwnd, window_mod.HOTKEY_QUIT);
}
