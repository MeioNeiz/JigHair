const std = @import("std");
const win32 = @import("win32.zig");

pub const HOTKEY_QUIT: i32 = 1;

pub fn wndProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(win32.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_HOTKEY => {
            const id: i32 = @intCast(wparam);
            if (id == HOTKEY_QUIT) {
                win32.PostQuitMessage(0);
            }
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
