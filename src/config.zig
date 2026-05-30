const std = @import("std");
const win32 = @import("win32.zig");

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

pub const MAX_PRESETS = 16;
pub const MAX_APPS = 16;
pub const NAME_CAP = 64;

/// Fixed-capacity, inline string so `Settings` stays a plain copyable value
/// with no heap ownership — safe to hold by value and pass around freely.
pub const Name = struct {
    buf: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
    len: usize = 0,

    pub fn slice(self: *const Name) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *Name, s: []const u8) void {
        const n = @min(s.len, NAME_CAP);
        @memcpy(self.buf[0..n], s[0..n]);
        self.len = n;
    }

    pub fn eqlIgnoreCase(self: *const Name, other: []const u8) bool {
        return std.ascii.eqlIgnoreCase(self.slice(), other);
    }
};

pub const Preset = struct {
    name: Name = .{},
    crosshair: CrosshairConfig = .{},
};

pub const VisibilityMode = enum { always, foreground_apps };

/// Runtime settings model. Fixed capacity, no heap; the whole struct is a value
/// that can be copied, stored in `App`, and serialized back out.
pub const Settings = struct {
    presets: [MAX_PRESETS]Preset = [_]Preset{.{}} ** MAX_PRESETS,
    preset_count: usize = 0,
    active: usize = 0,
    visibility_mode: VisibilityMode = .always,
    /// Process basenames (e.g. "cs2.exe") matched case-insensitively in
    /// foreground mode. Stored as the user wrote them.
    apps: [MAX_APPS]Name = [_]Name{.{}} ** MAX_APPS,
    app_count: usize = 0,

    /// A `Settings` with one preset named "default" and stock crosshair.
    pub fn default() Settings {
        var s = Settings{};
        s.presets[0].name.set("default");
        s.presets[0].crosshair = .{};
        s.preset_count = 1;
        return s;
    }

    pub fn activeCrosshair(self: *const Settings) CrosshairConfig {
        if (self.preset_count == 0) return .{};
        const i = if (self.active < self.preset_count) self.active else 0;
        return self.presets[i].crosshair;
    }

    pub fn activePreset(self: *Settings) *Preset {
        const i = if (self.active < self.preset_count and self.preset_count > 0) self.active else 0;
        return &self.presets[i];
    }
};

// JSON parse-target DTOs. Optional fields let us accept both the legacy
// top-level `crosshair` and the v2 `presets`/`active`/`visibility` schema.
const VisDto = struct {
    mode: ?[]const u8 = null,
    apps: ?[]const []const u8 = null,
    match: ?[]const u8 = null,
};

const ConfigDto = struct {
    crosshair: ?CrosshairConfig = null,
    active: ?[]const u8 = null,
    presets: ?std.json.ArrayHashMap(CrosshairConfig) = null,
    visibility: ?VisDto = null,
};

/// Loads %APPDATA%\JigHair\config.json into a `Settings`.
/// Falls back to a single default preset if missing or malformed.
pub fn load() Settings {
    // page_allocator, not FBA: getAlloc allocs+frees a whole env-map; an FBA never
    // reclaims and OOMs. All borrowed JSON strings are copied into fixed buffers
    // before the parse arena is freed, so nothing dangles past this function.
    const allocator = std.heap.page_allocator;

    const path = configPath(allocator) catch return .default();
    defer allocator.free(path);

    var io_threaded: std.Io.Threaded = .init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return .default();
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const contents = file_reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch return .default();
    defer allocator.free(contents);

    const parsed = std.json.parseFromSlice(
        ConfigDto,
        allocator,
        contents,
        .{ .ignore_unknown_fields = true },
    ) catch return .default();
    defer parsed.deinit();

    return fromDto(parsed.value);
}

fn fromDto(dto: ConfigDto) Settings {
    var s = Settings{};

    if (dto.presets) |p| {
        const keys = p.map.keys();
        const vals = p.map.values();
        var i: usize = 0;
        while (i < keys.len and s.preset_count < MAX_PRESETS) : (i += 1) {
            s.presets[s.preset_count].name.set(keys[i]);
            s.presets[s.preset_count].crosshair = vals[i];
            s.preset_count += 1;
        }
    }

    // Legacy / empty fallback: wrap the top-level `crosshair` as preset "default".
    if (s.preset_count == 0) {
        s.presets[0].name.set("default");
        s.presets[0].crosshair = dto.crosshair orelse .{};
        s.preset_count = 1;
    }

    if (dto.active) |a| {
        var i: usize = 0;
        while (i < s.preset_count) : (i += 1) {
            if (std.mem.eql(u8, s.presets[i].name.slice(), a)) {
                s.active = i;
                break;
            }
        }
    }
    if (s.active >= s.preset_count) s.active = 0;

    if (dto.visibility) |v| {
        if (v.mode) |m| {
            if (std.mem.eql(u8, m, "foreground_apps")) s.visibility_mode = .foreground_apps;
        }
        if (v.apps) |apps| {
            for (apps) |app| {
                if (s.app_count >= MAX_APPS) break;
                if (app.len == 0) continue;
                s.apps[s.app_count].set(app);
                s.app_count += 1;
            }
        }
    }

    return s;
}

// ---- Serialization ----

/// Small fixed JSON build buffer. 16 presets * ~200 bytes fits comfortably.
const Buf = struct {
    data: [16 * 1024]u8 = undefined,
    len: usize = 0,

    fn raw(self: *Buf, s: []const u8) void {
        const n = @min(s.len, self.data.len - self.len);
        @memcpy(self.data[self.len..][0..n], s[0..n]);
        self.len += n;
    }

    fn print(self: *Buf, comptime fmt: []const u8, args: anytype) void {
        const out = std.fmt.bufPrint(self.data[self.len..], fmt, args) catch return;
        self.len += out.len;
    }

    /// Quoted, JSON-escaped string.
    fn str(self: *Buf, s: []const u8) void {
        self.raw("\"");
        for (s) |c| switch (c) {
            '"' => self.raw("\\\""),
            '\\' => self.raw("\\\\"),
            '\n' => self.raw("\\n"),
            '\r' => self.raw("\\r"),
            '\t' => self.raw("\\t"),
            else => if (c < 0x20) self.print("\\u{x:0>4}", .{c}) else self.raw(&[_]u8{c}),
        };
        self.raw("\"");
    }

    fn slice(self: *const Buf) []const u8 {
        return self.data[0..self.len];
    }
};

fn writeColor(buf: *Buf, c: [4]u8) void {
    buf.print("[{d}, {d}, {d}, {d}]", .{ c[0], c[1], c[2], c[3] });
}

fn writeCrosshair(buf: *Buf, c: CrosshairConfig) void {
    buf.raw("\"color\": ");
    writeColor(buf, c.color);
    buf.raw(", \"outline_color\": ");
    writeColor(buf, c.outline_color);
    buf.print(", \"outline\": {d}, \"thickness\": {d}, \"length\": {d}, \"gap\": {d}", .{ c.outline, c.thickness, c.length, c.gap });
    buf.print(", \"dot\": {s}, \"dot_size\": {d}, \"offset_x\": {d}, \"offset_y\": {d}", .{
        if (c.dot) "true" else "false",
        c.dot_size,
        c.offset_x,
        c.offset_y,
    });
}

/// Serialize `s` to the v2 schema and write it to %APPDATA%\JigHair\config.json,
/// creating the directory if needed. Returns false on any I/O failure.
pub fn save(s: *const Settings) bool {
    var buf = Buf{};
    buf.raw("{\n");

    const active_name = if (s.preset_count > 0)
        s.presets[if (s.active < s.preset_count) s.active else 0].name.slice()
    else
        "default";
    buf.raw("  \"active\": ");
    buf.str(active_name);
    buf.raw(",\n");

    buf.raw("  \"visibility\": { \"mode\": ");
    buf.str(if (s.visibility_mode == .foreground_apps) "foreground_apps" else "always");
    buf.raw(", \"match\": \"process_name\", \"apps\": [");
    {
        var i: usize = 0;
        while (i < s.app_count) : (i += 1) {
            if (i > 0) buf.raw(", ");
            buf.str(s.apps[i].slice());
        }
    }
    buf.raw("] },\n");

    buf.raw("  \"presets\": {\n");
    {
        var i: usize = 0;
        while (i < s.preset_count) : (i += 1) {
            buf.raw("    ");
            buf.str(s.presets[i].name.slice());
            buf.raw(": { ");
            writeCrosshair(&buf, s.presets[i].crosshair);
            buf.raw(" }");
            if (i + 1 < s.preset_count) buf.raw(",");
            buf.raw("\n");
        }
    }
    buf.raw("  }\n}\n");

    return writeFileAbsolute(buf.slice());
}

/// Create %APPDATA%\JigHair if needed and (over)write config.json with `bytes`.
fn writeFileAbsolute(bytes: []const u8) bool {
    const allocator = std.heap.page_allocator;
    const paths = pathsW(allocator) catch return false;
    defer allocator.free(paths.dir);
    defer allocator.free(paths.file);

    _ = win32.CreateDirectoryW(paths.dir, null);

    const h = win32.CreateFileW(
        paths.file,
        win32.GENERIC_WRITE,
        0,
        null,
        win32.CREATE_ALWAYS,
        win32.FILE_ATTRIBUTE_NORMAL,
        null,
    );
    if (h == win32.INVALID_HANDLE_VALUE) return false;
    defer _ = win32.CloseHandle(h);

    var written: win32.DWORD = 0;
    return win32.WriteFile(h, bytes.ptr, @intCast(bytes.len), &written, null) != 0;
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
