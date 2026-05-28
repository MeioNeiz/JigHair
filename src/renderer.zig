const std = @import("std");
const win32 = @import("win32.zig");

pub const Pixel = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
};

/// Premultiplied alpha: UpdateLayeredWindow with ULW_ALPHA requires it.
fn premultiply(c: Pixel) Pixel {
    const a: u16 = c.a;
    return .{
        .b = @intCast((@as(u16, c.b) * a) / 255),
        .g = @intCast((@as(u16, c.g) * a) / 255),
        .r = @intCast((@as(u16, c.r) * a) / 255),
        .a = c.a,
    };
}

pub const Renderer = struct {
    width: i32,
    height: i32,
    screen_dc: win32.HDC,
    mem_dc: win32.HDC,
    bitmap: win32.HBITMAP,
    old_bitmap: win32.HGDIOBJ,
    pixels: []Pixel,

    pub fn init(width: i32, height: i32) !Renderer {
        const screen_dc = win32.GetDC(null) orelse return error.GetDCFailed;
        errdefer _ = win32.ReleaseDC(null, screen_dc);

        const mem_dc = win32.CreateCompatibleDC(screen_dc) orelse return error.CreateCompatibleDCFailed;
        errdefer _ = win32.DeleteDC(mem_dc);

        const bmi = win32.BITMAPINFO{
            .bmiHeader = .{
                .biWidth = width,
                .biHeight = -height, // negative = top-down DIB
                .biBitCount = 32,
                .biCompression = win32.BI_RGB,
            },
        };

        var bits: ?*anyopaque = null;
        const bitmap = win32.CreateDIBSection(mem_dc, &bmi, win32.DIB_RGB_COLORS, &bits, null, 0) orelse
            return error.CreateDIBSectionFailed;
        errdefer _ = win32.DeleteObject(@ptrCast(bitmap));

        const old_bitmap = win32.SelectObject(mem_dc, @ptrCast(bitmap));

        const pixel_count: usize = @intCast(width * height);
        const pixels_ptr: [*]Pixel = @ptrCast(@alignCast(bits.?));
        const pixels = pixels_ptr[0..pixel_count];
        @memset(pixels, .{ .b = 0, .g = 0, .r = 0, .a = 0 });

        return .{
            .width = width,
            .height = height,
            .screen_dc = screen_dc,
            .mem_dc = mem_dc,
            .bitmap = bitmap,
            .old_bitmap = old_bitmap,
            .pixels = pixels,
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = win32.SelectObject(self.mem_dc, self.old_bitmap);
        _ = win32.DeleteObject(@ptrCast(self.bitmap));
        _ = win32.DeleteDC(self.mem_dc);
        _ = win32.ReleaseDC(null, self.screen_dc);
    }

    pub fn clear(self: *Renderer) void {
        @memset(self.pixels, .{ .b = 0, .g = 0, .r = 0, .a = 0 });
    }

    pub fn setPixel(self: *Renderer, x: i32, y: i32, color: Pixel) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        const idx: usize = @intCast(y * self.width + x);
        self.pixels[idx] = premultiply(color);
    }

    pub fn fillRect(self: *Renderer, x: i32, y: i32, w: i32, h: i32, color: Pixel) void {
        if (w <= 0 or h <= 0) return;
        const pre = premultiply(color);
        const x0 = @max(0, x);
        const y0 = @max(0, y);
        const x1 = @min(self.width, x + w);
        const y1 = @min(self.height, y + h);
        var py = y0;
        while (py < y1) : (py += 1) {
            const row_start: usize = @intCast(py * self.width + x0);
            const row_len: usize = @intCast(x1 - x0);
            @memset(self.pixels[row_start .. row_start + row_len], pre);
        }
    }

    /// Push the current bitmap to the layered window.
    pub fn present(self: *Renderer, hwnd: win32.HWND) !void {
        var pt_src = win32.POINT{ .x = 0, .y = 0 };
        var size = win32.SIZE{ .cx = self.width, .cy = self.height };
        const blend = win32.BLENDFUNCTION{
            .BlendOp = win32.AC_SRC_OVER,
            .BlendFlags = 0,
            .SourceConstantAlpha = 255,
            .AlphaFormat = win32.AC_SRC_ALPHA,
        };
        if (win32.UpdateLayeredWindow(
            hwnd,
            null,
            null,
            &size,
            self.mem_dc,
            &pt_src,
            0,
            &blend,
            win32.ULW_ALPHA,
        ) == 0) {
            return error.UpdateLayeredWindowFailed;
        }
    }
};
