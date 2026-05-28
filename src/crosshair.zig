const std = @import("std");
const renderer_mod = @import("renderer.zig");
const Renderer = renderer_mod.Renderer;
const Pixel = renderer_mod.Pixel;
const CrosshairConfig = @import("config.zig").CrosshairConfig;

pub fn draw(r: *Renderer, cfg: CrosshairConfig) void {
    r.clear();

    const cx = @divTrunc(r.width, 2) + cfg.offset_x;
    const cy = @divTrunc(r.height, 2) + cfg.offset_y;

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
