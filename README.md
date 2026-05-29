# jig+hair

A lightweight, always-on-top crosshair overlay for Windows, written in [Zig](https://ziglang.org).
Draws a customizable crosshair at the center of your screen — no console window, no dependencies beyond the Win32 API.

## Build

Requires Zig 0.16.0+.

```sh
zig build                    # ReleaseSmall by default -> zig-out/bin/JigHair.exe
zig build run                # build and run the overlay
zig build -Doptimize=Debug   # debug build with safety checks
```

## Configuration

On startup, `jig+hair` looks for a config file at:

```
%APPDATA%\JigHair\config.json
```

If it's missing or malformed, sensible defaults are used. Copy `config.example.json`
to that location and edit to taste:

```json
{
  "crosshair": {
    "color": [0, 255, 0, 255],
    "outline_color": [0, 0, 0, 255],
    "outline": 1,
    "thickness": 2,
    "length": 10,
    "gap": 4,
    "dot": true,
    "dot_size": 2,
    "offset_x": 0,
    "offset_y": 0
  }
}
```

| Field | Meaning |
|---|---|
| `color` | Crosshair color, `[r, g, b, a]` (0–255). |
| `outline_color` | Outline color, `[r, g, b, a]`. |
| `outline` | Outline thickness in pixels (`0` = no outline). |
| `thickness` | Line thickness of each arm. |
| `length` | Length of each arm. |
| `gap` | Gap between the center and the start of each arm. |
| `dot` | Draw a center dot. |
| `dot_size` | Size of the center dot. |
| `offset_x` / `offset_y` | Pixel offset from screen center. |
