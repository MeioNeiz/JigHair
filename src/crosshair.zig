const std = @import("std");
const renderer_mod = @import("renderer.zig");
const Renderer = renderer_mod.Renderer;
const Pixel = renderer_mod.Pixel;
const CrosshairConfig = @import("config.zig").CrosshairConfig;

pub fn draw(r: *Renderer, cfg: CrosshairConfig) void {
    r.clear();

    // Centered in the window; offset is applied to the window position (main.zig).
    const cx = @divTrunc(r.width, 2);
    const cy = @divTrunc(r.height, 2);

    const color = Pixel{
        .r = cfg.color[0],
        .g = cfg.color[1],
        .b = cfg.color[2],
        .a = cfg.color[3],
    };

    const t = cfg.thickness;
    const half_t = @divTrunc(t, 2);
    const gap = cfg.gap;
    const len = cfg.length;

    // Outline (drawn first so the main color sits on top).
    if (cfg.outline > 0) {
        const o = cfg.outline;
        const outline_color = Pixel{
            .r = cfg.outline_color[0],
            .g = cfg.outline_color[1],
            .b = cfg.outline_color[2],
            .a = cfg.outline_color[3],
        };
        // Horizontal arms outline.
        r.fillRect(cx - gap - len - o, cy - half_t - o, len + 2 * o, t + 2 * o, outline_color);
        r.fillRect(cx + gap - o, cy - half_t - o, len + 2 * o, t + 2 * o, outline_color);
        // Vertical arms outline.
        r.fillRect(cx - half_t - o, cy - gap - len - o, t + 2 * o, len + 2 * o, outline_color);
        r.fillRect(cx - half_t - o, cy + gap - o, t + 2 * o, len + 2 * o, outline_color);
        // Center dot outline.
        if (cfg.dot) {
            const ds = cfg.dot_size;
            r.fillRect(cx - @divTrunc(ds, 2) - o, cy - @divTrunc(ds, 2) - o, ds + 2 * o, ds + 2 * o, outline_color);
        }
    }

    // Horizontal arms.
    if (len > 0) {
        r.fillRect(cx - gap - len, cy - half_t, len, t, color);
        r.fillRect(cx + gap, cy - half_t, len, t, color);
        // Vertical arms.
        r.fillRect(cx - half_t, cy - gap - len, t, len, color);
        r.fillRect(cx - half_t, cy + gap, t, len, color);
    }

    // Center dot.
    if (cfg.dot) {
        const ds = cfg.dot_size;
        r.fillRect(cx - @divTrunc(ds, 2), cy - @divTrunc(ds, 2), ds, ds, color);
    }
}

/// Breathing room around the bounding box; absorbs integer-centering bias.
const MARGIN: i32 = 2;

/// Max distance, in px, any drawn pixel sits from the crosshair center for `cfg`.
pub fn extent(cfg: CrosshairConfig) i32 {
    const o: i32 = if (cfg.outline > 0) cfg.outline else 0;
    var half: i32 = 0;
    if (cfg.length > 0) {
        half = @max(half, cfg.gap + cfg.length + o);
        half = @max(half, ceilHalf(cfg.thickness) + o);
    }
    if (cfg.dot) half = @max(half, ceilHalf(cfg.dot_size) + o);
    return @max(0, half);
}

/// Square side, in px, of the overlay window needed to hold the crosshair.
pub fn windowSize(cfg: CrosshairConfig) i32 {
    return @max(2, (extent(cfg) + MARGIN) * 2);
}

fn ceilHalf(v: i32) i32 {
    return if (v > 0) @divTrunc(v + 1, 2) else 0;
}

pub const Placement = struct { x: i32, y: i32, dim: i32 };

/// A monitor's pixel rectangle (virtual-desktop coordinates).
pub const MonitorRect = struct { x: i32 = 0, y: i32 = 0, w: i32, h: i32 };

/// Window square + top-left so the crosshair sits at the centre of `mon` + offset,
/// clamped to stay within that monitor.
pub fn placement(cfg: CrosshairConfig, mon: MonitorRect) Placement {
    const dim = windowSize(cfg);
    const cx = mon.x + @divTrunc(mon.w, 2) + cfg.offset_x;
    const cy = mon.y + @divTrunc(mon.h, 2) + cfg.offset_y;
    return .{
        .x = std.math.clamp(cx - @divTrunc(dim, 2), mon.x, mon.x + @max(0, mon.w - dim)),
        .y = std.math.clamp(cy - @divTrunc(dim, 2), mon.y, mon.y + @max(0, mon.h - dim)),
        .dim = dim,
    };
}
