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
pub const HMONITOR = ?*opaque {};
pub const HWINEVENTHOOK = ?*opaque {};
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

// ---- Tray / menu / shell messages ----
pub const WM_NULL: UINT = 0x0000;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_LBUTTONDBLCLK: UINT = 0x0203;
pub const WM_CONTEXTMENU: UINT = 0x007B;
pub const WM_APP: UINT = 0x8000;
pub const WM_TRAYICON: UINT = WM_APP + 1;

// ---- Window long pointers ----
pub const GWLP_USERDATA: INT = -21;

// ---- SetWindowPos flags ----
pub const SWP_NOSIZE: UINT = 0x0001;
pub const SWP_NOMOVE: UINT = 0x0002;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_NOACTIVATE: UINT = 0x0010;

// ---- Menus ----
pub const MF_STRING: UINT = 0x0000;
pub const MF_CHECKED: UINT = 0x0008;
pub const MF_UNCHECKED: UINT = 0x0000;
pub const MF_SEPARATOR: UINT = 0x0800;
pub const TPM_RIGHTBUTTON: UINT = 0x0002;

// ---- Stock icon / cursor ----
pub const IDI_APPLICATION: LPCWSTR = @ptrFromInt(32512);
pub const IDC_ARROW: LPCWSTR = @ptrFromInt(32512);
pub extern "user32" fn LoadCursorW(HINSTANCE, LPCWSTR) callconv(WINAPI) HCURSOR;

// ---- Shell_NotifyIcon ----
pub const NIM_ADD: DWORD = 0x0;
pub const NIM_MODIFY: DWORD = 0x1;
pub const NIM_DELETE: DWORD = 0x2;
pub const NIF_MESSAGE: UINT = 0x1;
pub const NIF_ICON: UINT = 0x2;
pub const NIF_TIP: UINT = 0x4;

// ---- ShellExecute ----
pub const SW_SHOWNORMAL: INT = 1;

// ---- CreateFile ----
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const CREATE_NEW: DWORD = 1;
pub const CREATE_ALWAYS: DWORD = 2;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

pub const GUID = extern struct {
    Data1: u32 = 0,
    Data2: u16 = 0,
    Data3: u16 = 0,
    Data4: [8]u8 = [_]u8{0} ** 8,
};

pub const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD = @sizeOf(NOTIFYICONDATAW),
    hWnd: HWND,
    uID: UINT = 0,
    uFlags: UINT = 0,
    uCallbackMessage: UINT = 0,
    hIcon: HICON = null,
    szTip: [128]u16 = [_]u16{0} ** 128,
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = [_]u16{0} ** 256,
    uVersion: UINT = 0,
    szInfoTitle: [64]u16 = [_]u16{0} ** 64,
    dwInfoFlags: DWORD = 0,
    guidItem: GUID = .{},
    hBalloonIcon: HICON = null,
};

// ---- user32 (tray / menu / window state) ----
pub extern "user32" fn LoadIconW(HINSTANCE, LPCWSTR) callconv(WINAPI) HICON;
pub extern "user32" fn CreatePopupMenu() callconv(WINAPI) HMENU;
pub extern "user32" fn AppendMenuW(HMENU, UINT, UINT_PTR, ?LPCWSTR) callconv(WINAPI) BOOL;
pub extern "user32" fn TrackPopupMenu(HMENU, UINT, INT, INT, INT, HWND, ?*const RECT) callconv(WINAPI) BOOL;
pub extern "user32" fn DestroyMenu(HMENU) callconv(WINAPI) BOOL;
pub extern "user32" fn SetForegroundWindow(HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn GetCursorPos(*POINT) callconv(WINAPI) BOOL;
pub extern "user32" fn PostMessageW(HWND, UINT, WPARAM, LPARAM) callconv(WINAPI) BOOL;
pub extern "user32" fn DestroyWindow(HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn SetWindowLongPtrW(HWND, INT, LONG_PTR) callconv(WINAPI) LONG_PTR;
pub extern "user32" fn GetWindowLongPtrW(HWND, INT) callconv(WINAPI) LONG_PTR;
pub extern "user32" fn SetWindowPos(HWND, HWND, INT, INT, INT, INT, UINT) callconv(WINAPI) BOOL;

// ---- shell32 ----
pub extern "shell32" fn Shell_NotifyIconW(DWORD, *NOTIFYICONDATAW) callconv(WINAPI) BOOL;
pub extern "shell32" fn ShellExecuteW(HWND, ?LPCWSTR, LPCWSTR, ?LPCWSTR, ?LPCWSTR, INT) callconv(WINAPI) HINSTANCE;

// ---- kernel32 (config dir / file) ----
pub extern "kernel32" fn CreateDirectoryW(LPCWSTR, ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn CreateFileW(LPCWSTR, DWORD, DWORD, ?*anyopaque, DWORD, DWORD, HANDLE) callconv(WINAPI) HANDLE;
pub extern "kernel32" fn WriteFile(HANDLE, [*]const u8, DWORD, *DWORD, ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn CloseHandle(HANDLE) callconv(WINAPI) BOOL;

// ---- Foreground detection (WinEvent hook + process query + monitor) ----
pub const EVENT_SYSTEM_FOREGROUND: UINT = 0x0003;
pub const WINEVENT_OUTOFCONTEXT: UINT = 0x0000;
pub const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;
pub const MONITOR_DEFAULTTONEAREST: DWORD = 0x00000002;

/// Out-of-context WinEvent callbacks are delivered on the thread that called
/// SetWinEventHook — i.e. our GetMessage loop — so no extra thread or locking.
pub const WINEVENTPROC = *const fn (HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD) callconv(WINAPI) void;

pub const MONITORINFO = extern struct {
    cbSize: DWORD = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    rcWork: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    dwFlags: DWORD = 0,
};

pub extern "user32" fn SetWinEventHook(UINT, UINT, HINSTANCE, WINEVENTPROC, DWORD, DWORD, UINT) callconv(WINAPI) HWINEVENTHOOK;
pub extern "user32" fn UnhookWinEvent(HWINEVENTHOOK) callconv(WINAPI) BOOL;
pub extern "user32" fn GetForegroundWindow() callconv(WINAPI) HWND;
pub extern "user32" fn GetWindowThreadProcessId(HWND, *DWORD) callconv(WINAPI) DWORD;
pub extern "user32" fn MonitorFromWindow(HWND, DWORD) callconv(WINAPI) HMONITOR;
pub extern "user32" fn GetMonitorInfoW(HMONITOR, *MONITORINFO) callconv(WINAPI) BOOL;
pub extern "kernel32" fn OpenProcess(DWORD, BOOL, DWORD) callconv(WINAPI) HANDLE;
pub extern "kernel32" fn QueryFullProcessImageNameW(HANDLE, DWORD, [*]u16, *DWORD) callconv(WINAPI) BOOL;

// ============================================================================
// Settings UI: child controls, common dialog, GDI compositing
// ============================================================================

pub const COLORREF = DWORD; // 0x00BBGGRR
pub const HFONT = HGDIOBJ;

// ---- Window styles for the settings window + children ----
pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_TABSTOP: DWORD = 0x00010000;
pub const WS_GROUP: DWORD = 0x00020000;
pub const WS_VSCROLL: DWORD = 0x00200000;
pub const WS_BORDER: DWORD = 0x00800000;
pub const WS_CAPTION: DWORD = 0x00C00000;
pub const WS_SYSMENU: DWORD = 0x00080000;
pub const WS_MINIMIZEBOX: DWORD = 0x00020000;
pub const WS_EX_CONTROLPARENT: DWORD = 0x00010000;

// ---- Control styles ----
pub const BS_PUSHBUTTON: DWORD = 0x00000000;
pub const BS_AUTOCHECKBOX: DWORD = 0x00000003;
pub const BS_GROUPBOX: DWORD = 0x00000007;
pub const BS_OWNERDRAW: DWORD = 0x0000000B;
pub const SS_LEFT: DWORD = 0x00000000;
pub const SS_RIGHT: DWORD = 0x00000002;
pub const ES_AUTOHSCROLL: DWORD = 0x00000080;
pub const CBS_DROPDOWNLIST: DWORD = 0x00000003;
pub const CBS_HASSTRINGS: DWORD = 0x00000200;
pub const LBS_NOTIFY: DWORD = 0x00000001;
pub const LBS_HASSTRINGS: DWORD = 0x00000040;
pub const LBS_NOINTEGRALHEIGHT: DWORD = 0x00000100;
pub const TBS_HORZ: DWORD = 0x00000000;
pub const TBS_NOTICKS: DWORD = 0x00000010;
pub const TBS_BOTH: DWORD = 0x00000008;

// ---- Messages ----
pub const WM_CREATE: UINT = 0x0001;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_SETFONT: UINT = 0x0030;
pub const WM_HSCROLL: UINT = 0x0114;
pub const WM_DRAWITEM: UINT = 0x002B;
pub const WM_NCDESTROY: UINT = 0x0082;
pub const WM_CTLCOLORSTATIC: UINT = 0x0138;

// Button
pub const BM_GETCHECK: UINT = 0x00F0;
pub const BM_SETCHECK: UINT = 0x00F1;
pub const BST_UNCHECKED: WPARAM = 0;
pub const BST_CHECKED: WPARAM = 1;
// ComboBox
pub const CB_ADDSTRING: UINT = 0x0143;
pub const CB_RESETCONTENT: UINT = 0x014B;
pub const CB_GETCURSEL: UINT = 0x0147;
pub const CB_SETCURSEL: UINT = 0x014E;
// ListBox
pub const LB_ADDSTRING: UINT = 0x0180;
pub const LB_RESETCONTENT: UINT = 0x0184;
pub const LB_GETCURSEL: UINT = 0x0188;
pub const LB_DELETESTRING: UINT = 0x0182;
pub const LB_GETCOUNT: UINT = 0x018B;
// Trackbar
pub const TBM_GETPOS: UINT = 0x0400;
pub const TBM_SETPOS: UINT = 0x0405;
pub const TBM_SETRANGEMIN: UINT = 0x0407; // WM_USER+7
pub const TBM_SETRANGEMAX: UINT = 0x0408; // WM_USER+8

// ---- Notification codes (HIWORD of WM_COMMAND wParam) ----
pub const BN_CLICKED: u16 = 0;
pub const CBN_SELCHANGE: u16 = 1;

// ---- GetStockObject / fonts ----
pub const DEFAULT_GUI_FONT: INT = 17;

// ---- BitBlt raster op ----
pub const SRCCOPY: DWORD = 0x00CC0020;

// ---- Common controls init ----
pub const ICC_BAR_CLASSES: DWORD = 0x00000004;
pub const ICC_STANDARD_CLASSES: DWORD = 0x00004000;

pub const INITCOMMONCONTROLSEX = extern struct {
    dwSize: DWORD = @sizeOf(INITCOMMONCONTROLSEX),
    dwICC: DWORD,
};

pub const DRAWITEMSTRUCT = extern struct {
    CtlType: UINT,
    CtlID: UINT,
    itemID: UINT,
    itemAction: UINT,
    itemState: UINT,
    hwndItem: HWND,
    hDC: HDC,
    rcItem: RECT,
    itemData: ULONG_PTR,
};

// ---- ChooseColor (comdlg32) ----
pub const CC_RGBINIT: DWORD = 0x00000001;
pub const CC_FULLOPEN: DWORD = 0x00000002;
pub const CC_ANYCOLOR: DWORD = 0x00000100;

pub const CHOOSECOLORW = extern struct {
    lStructSize: DWORD = @sizeOf(CHOOSECOLORW),
    hwndOwner: HWND = null,
    hInstance: HWND = null,
    rgbResult: COLORREF = 0,
    lpCustColors: [*]COLORREF,
    Flags: DWORD = 0,
    lCustData: LPARAM = 0,
    lpfnHook: ?*anyopaque = null,
    lpTemplateName: ?LPCWSTR = null,
};

pub const WNDENUMPROC = *const fn (HWND, LPARAM) callconv(WINAPI) BOOL;

// ---- user32 ----
pub extern "user32" fn SendMessageW(HWND, UINT, WPARAM, LPARAM) callconv(WINAPI) LRESULT;
pub extern "user32" fn SetWindowTextW(HWND, LPCWSTR) callconv(WINAPI) BOOL;
pub extern "user32" fn GetWindowTextW(HWND, [*]u16, INT) callconv(WINAPI) INT;
pub extern "user32" fn GetWindowTextLengthW(HWND) callconv(WINAPI) INT;
pub extern "user32" fn EnableWindow(HWND, BOOL) callconv(WINAPI) BOOL;
pub extern "user32" fn InvalidateRect(HWND, ?*const RECT, BOOL) callconv(WINAPI) BOOL;
pub extern "user32" fn IsWindowVisible(HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn EnumWindows(WNDENUMPROC, LPARAM) callconv(WINAPI) BOOL;
pub extern "user32" fn GetClientRect(HWND, *RECT) callconv(WINAPI) BOOL;
pub extern "user32" fn FillRect(HDC, *const RECT, HBRUSH) callconv(WINAPI) INT;
pub extern "user32" fn IsWindow(HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn GetDlgItem(HWND, INT) callconv(WINAPI) HWND;
pub extern "user32" fn GetDlgCtrlID(HWND) callconv(WINAPI) INT;
pub extern "user32" fn AdjustWindowRect(*RECT, DWORD, BOOL) callconv(WINAPI) BOOL;

// ---- gdi32 ----
pub extern "gdi32" fn CreateSolidBrush(COLORREF) callconv(WINAPI) HBRUSH;
pub extern "gdi32" fn BitBlt(HDC, INT, INT, INT, INT, HDC, INT, INT, DWORD) callconv(WINAPI) BOOL;
pub extern "gdi32" fn GetStockObject(INT) callconv(WINAPI) HGDIOBJ;

// ---- comctl32 / comdlg32 / msimg32 ----
pub extern "comctl32" fn InitCommonControlsEx(*const INITCOMMONCONTROLSEX) callconv(WINAPI) BOOL;
pub extern "comdlg32" fn ChooseColorW(*CHOOSECOLORW) callconv(WINAPI) BOOL;
pub extern "msimg32" fn AlphaBlend(HDC, INT, INT, INT, INT, HDC, INT, INT, INT, INT, BLENDFUNCTION) callconv(WINAPI) BOOL;
