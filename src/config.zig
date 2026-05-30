const std = @import("std");

pub const CrosshairConfig = struct {
    /// RGBA, 0-255. Default is bright lime green.
    color: [4]u8 = .{ 0, 255, 0, 255 },
    /// Outline color, used when `outline > 0`. Default opaque black.
    outline_color: [4]u8 = .{ 0, 0, 0, 255 },
    /// Outline thickness in pixels around the arms and dot. 0 = no outline.
    outline: i32 = 1,
    /// Thickness of each arm.
    thickness: i32 = 2,
    /// Length of each arm.
    length: i32 = 10,
    /// Empty space between center and the inner edge of each arm.
    gap: i32 = 4,
    /// Draw a square dot at the center.
    dot: bool = true,
    /// Size of the center dot in pixels.
    dot_size: i32 = 2,
    /// Offset from screen center, in pixels.
    offset_x: i32 = 0,
    offset_y: i32 = 0,
};

pub const Config = struct {
    crosshair: CrosshairConfig = .{},
};

/// Loads the JSON config from %APPDATA%\JigHair\config.json.
/// Falls back to defaults if missing or malformed.
pub fn load() Config {
    // page_allocator, not FBA: getAlloc allocs+frees a whole env-map; an FBA never
    // reclaims and OOMs. Config has no slices, so the returned value survives deinit.
    const allocator = std.heap.page_allocator;

    const path = configPath(allocator) catch return .{};
    defer allocator.free(path);

    var io_threaded: std.Io.Threaded = .init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return .{};
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const contents = file_reader.interface.allocRemaining(allocator, .limited(16 * 1024)) catch return .{};
    defer allocator.free(contents);

    const parsed = std.json.parseFromSlice(
        Config,
        allocator,
        contents,
        .{ .ignore_unknown_fields = true },
    ) catch return .{};
    defer parsed.deinit();

    return parsed.value;
}

fn configPath(allocator: std.mem.Allocator) ![]u8 {
    const environ: std.process.Environ = .{ .block = .global };
    const appdata = environ.getAlloc(allocator, "APPDATA") catch {
        return try allocator.dupe(u8, "config.json");
    };
    defer allocator.free(appdata);
    return try std.fs.path.join(allocator, &.{ appdata, "JigHair", "config.json" });
}

pub const Paths = struct { dir: [:0]u16, file: [:0]u16 };

/// Wide, null-terminated %APPDATA%\JigHair dir + config.json paths. One getAlloc.
/// Caller frees both `dir` and `file`.
pub fn pathsW(allocator: std.mem.Allocator) !Paths {
    const environ: std.process.Environ = .{ .block = .global };
    const appdata = try environ.getAlloc(allocator, "APPDATA");
    defer allocator.free(appdata);
    const dir = try std.fs.path.join(allocator, &.{ appdata, "JigHair" });
    defer allocator.free(dir);
    const file = try std.fs.path.join(allocator, &.{ dir, "config.json" });
    defer allocator.free(file);

    const dir_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, dir);
    errdefer allocator.free(dir_w);
    const file_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, file);
    return .{ .dir = dir_w, .file = file_w };
}
