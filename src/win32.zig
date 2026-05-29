const std = @import("std");

pub const WINAPI = std.builtin.CallingConvention.winapi;

pub const BOOL = i32;
pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;
pub const BYTE = u8;
pub const WORD = u16;
pub const DWORD = u32;
pub const LONG = i32;
pub const LONG_PTR = isize;
pub const ULONG_PTR = usize;
pub const UINT_PTR = usize;
pub const UINT = u32;
pub const INT = i32;
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*opaque {};
pub const HINSTANCE = ?*opaque {};
pub const HDC = ?*opaque {};
pub const HBITMAP = ?*opaque {};
pub const HGDIOBJ = ?*opaque {};
pub const HBRUSH = ?*opaque {};
pub const HICON = ?*opaque {};
pub const HCURSOR = HICON;
pub const HMENU = ?*opaque {};
pub const WPARAM = UINT_PTR;
pub const LPARAM = LONG_PTR;
pub const LRESULT = LONG_PTR;
pub const LPCWSTR = [*:0]const u16;
pub const LPVOID = ?*anyopaque;

pub const POINT = extern struct { x: LONG, y: LONG };
pub const SIZE = extern struct { cx: LONG, cy: LONG };
pub const RECT = extern struct { left: LONG, top: LONG, right: LONG, bottom: LONG };

pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(WINAPI) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: INT = 0,
    cbWndExtra: INT = 0,
    hInstance: HINSTANCE,
    hIcon: HICON = null,
    hCursor: HCURSOR = null,
    hbrBackground: HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: HICON = null,
};

pub const RGBQUAD = extern struct {
    rgbBlue: BYTE = 0,
    rgbGreen: BYTE = 0,
    rgbRed: BYTE = 0,
    rgbReserved: BYTE = 0,
};

pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
    biWidth: LONG,
    biHeight: LONG,
    biPlanes: WORD = 1,
    biBitCount: WORD,
    biCompression: DWORD = 0,
    biSizeImage: DWORD = 0,
    biXPelsPerMeter: LONG = 0,
    biYPelsPerMeter: LONG = 0,
    biClrUsed: DWORD = 0,
    biClrImportant: DWORD = 0,
};

pub const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD = .{.{}},
};

pub const BLENDFUNCTION = extern struct {
    BlendOp: BYTE,
    BlendFlags: BYTE,
    SourceConstantAlpha: BYTE,
    AlphaFormat: BYTE,
};

// ---- Window styles ----
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_VISIBLE: DWORD = 0x10000000;

pub const WS_EX_LAYERED: DWORD = 0x00080000;
pub const WS_EX_TRANSPARENT: DWORD = 0x00000020;
pub const WS_EX_TOPMOST: DWORD = 0x00000008;
pub const WS_EX_TOOLWINDOW: DWORD = 0x00000080;
pub const WS_EX_NOACTIVATE: DWORD = 0x08000000;

// ---- ShowWindow ----
pub const SW_HIDE: INT = 0;
pub const SW_SHOW: INT = 5;
pub const SW_SHOWNOACTIVATE: INT = 4;

// ---- Messages ----
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_QUIT: UINT = 0x0012;
pub const WM_HOTKEY: UINT = 0x0312;

// ---- GetSystemMetrics ----
pub const SM_CXSCREEN: INT = 0;
pub const SM_CYSCREEN: INT = 1;
pub const SM_XVIRTUALSCREEN: INT = 76;
pub const SM_YVIRTUALSCREEN: INT = 77;
pub const SM_CXVIRTUALSCREEN: INT = 78;
pub const SM_CYVIRTUALSCREEN: INT = 79;

// ---- DIB / bitmap ----
pub const BI_RGB: DWORD = 0;
pub const DIB_RGB_COLORS: UINT = 0;

// ---- Layered window ----
pub const AC_SRC_OVER: BYTE = 0x00;
pub const AC_SRC_ALPHA: BYTE = 0x01;
pub const ULW_ALPHA: DWORD = 0x00000002;

// ---- Hotkey ----
pub const MOD_ALT: UINT = 0x0001;
pub const MOD_CONTROL: UINT = 0x0002;
pub const MOD_SHIFT: UINT = 0x0004;
pub const MOD_NOREPEAT: UINT = 0x4000;
pub const VK_F8: UINT = 0x77;

// ---- DPI awareness ----
pub const DPI_AWARENESS_CONTEXT = HANDLE;
pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: DPI_AWARENESS_CONTEXT =
    @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));

// ---- kernel32 ----
pub extern "kernel32" fn GetModuleHandleW(?LPCWSTR) callconv(WINAPI) HINSTANCE;
pub extern "kernel32" fn GetLastError() callconv(WINAPI) DWORD;

// ---- user32 ----
pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(WINAPI) u16;
pub extern "user32" fn CreateWindowExW(DWORD, LPCWSTR, ?LPCWSTR, DWORD, INT, INT, INT, INT, HWND, HMENU, HINSTANCE, LPVOID) callconv(WINAPI) HWND;
pub extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(WINAPI) LRESULT;
pub extern "user32" fn ShowWindow(HWND, INT) callconv(WINAPI) BOOL;
pub extern "user32" fn GetMessageW(*MSG, HWND, UINT, UINT) callconv(WINAPI) BOOL;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(WINAPI) BOOL;
pub extern "user32" fn DispatchMessageW(*const MSG) callconv(WINAPI) LRESULT;
pub extern "user32" fn PostQuitMessage(INT) callconv(WINAPI) void;
pub extern "user32" fn GetSystemMetrics(INT) callconv(WINAPI) INT;
pub extern "user32" fn SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT) callconv(WINAPI) BOOL;
pub extern "user32" fn GetDC(HWND) callconv(WINAPI) HDC;
pub extern "user32" fn ReleaseDC(HWND, HDC) callconv(WINAPI) INT;
pub extern "user32" fn UpdateLayeredWindow(HWND, HDC, ?*POINT, ?*SIZE, HDC, ?*POINT, DWORD, ?*const BLENDFUNCTION, DWORD) callconv(WINAPI) BOOL;
pub extern "user32" fn RegisterHotKey(HWND, INT, UINT, UINT) callconv(WINAPI) BOOL;
pub extern "user32" fn UnregisterHotKey(HWND, INT) callconv(WINAPI) BOOL;

// ---- gdi32 ----
pub extern "gdi32" fn CreateCompatibleDC(HDC) callconv(WINAPI) HDC;
pub extern "gdi32" fn DeleteDC(HDC) callconv(WINAPI) BOOL;
pub extern "gdi32" fn CreateDIBSection(HDC, *const BITMAPINFO, UINT, *?*anyopaque, HANDLE, DWORD) callconv(WINAPI) HBITMAP;
pub extern "gdi32" fn SelectObject(HDC, HGDIOBJ) callconv(WINAPI) HGDIOBJ;
pub extern "gdi32" fn DeleteObject(HGDIOBJ) callconv(WINAPI) BOOL;
