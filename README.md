# JigHair

A lightweight, always-on-top crosshair overlay for Windows, written in [Zig](https://ziglang.org).
Draws a customizable crosshair at the center of your screen — no console window, no dependencies
beyond the Win32 API. Includes a native **settings window** to build your crosshair, manage
presets, and optionally show the crosshair only when a chosen app is focused.

## Build

Requires Zig 0.16.0+.

```sh
zig build -Doptimize=ReleaseSmall   # recommended -> zig-out/bin/JigHair.exe (~470 KB)
zig build                           # ReleaseSmall is the default optimize mode too
zig build run                       # build and run the overlay
zig build -Doptimize=Debug          # debug build with safety checks
```

## Usage

Run `JigHair.exe`. A crosshair appears at the center of your monitor and a **tray icon** is added.
Right-click the tray icon for:

| Menu item | Action |
|---|---|
| **Settings…** | Open the settings window (build crosshairs, manage presets, choose target apps). |
| **Show crosshair** | Toggle the overlay on/off (also: double-click the tray icon). |
| **Reload config** | Re-read `config.json` from disk and re-apply. |
| **Open config folder** | Open `%APPDATA%\JigHair` (seeds a default `config.json` if missing). |
| **Quit JigHair** | Exit. (Hotkey: `Ctrl+Alt+F8`.) |

## Settings window

Opened from the tray menu. Everything updates a **live, pixel-exact preview** (it uses the real
renderer), and **Save & Apply** writes `config.json` and applies the change to the live overlay.

- **Presets** — pick from the dropdown, **New** to clone the current one, **Rename**, **Delete**.
  The selected preset becomes the active one on save.
- **Crosshair** — sliders for outline, thickness, length, gap, dot size, and X/Y offset; a **Dot**
  toggle; and **Color** / **Outline** color swatches (click to open the system color picker).
- **Show crosshair** — `Always`, or `Only when a chosen app is focused`.
- **Target apps** — add apps by name, or pick one from the **Running** list. In foreground mode the
  crosshair appears only while one of these apps is focused, and is placed on **that app's monitor**.

## Configuration

On startup `JigHair` reads `%APPDATA%\JigHair\config.json`. If it's missing or malformed, sensible
defaults are used. You can edit it by hand or use the settings window. Copy `config.example.json`
to that location to get started.

```json
{
  "active": "default",
  "visibility": { "mode": "always", "match": "process_name", "apps": ["cs2.exe"] },
  "presets": {
    "default": {
      "color": [0, 255, 0, 255],
      "outline_color": [0, 0, 0, 255],
      "outline": 1, "thickness": 2, "length": 10, "gap": 4,
      "dot": true, "dot_size": 2, "offset_x": 0, "offset_y": 0
    }
  }
}
```

| Field | Meaning |
|---|---|
| `active` | Name of the preset to display. |
| `visibility.mode` | `"always"`, or `"foreground_apps"` (show only when a chosen app is focused). |
| `visibility.apps` | Process names (e.g. `"cs2.exe"`), matched case-insensitively, for foreground mode. |
| `visibility.match` | Match strategy. Currently `"process_name"`. |
| `presets` | Map of preset name → crosshair definition (see below). |

Each preset:

| Field | Meaning |
|---|---|
| `color` | Crosshair color, `[r, g, b, a]` (0–255). |
| `outline_color` | Outline color, `[r, g, b, a]`. |
| `outline` | Outline thickness in pixels (`0` = no outline). |
| `thickness` | Line thickness of each arm. |
| `length` | Length of each arm (`0` = dot only). |
| `gap` | Gap between the center and the start of each arm. |
| `dot` | Draw a center dot. |
| `dot_size` | Size of the center dot. |
| `offset_x` / `offset_y` | Pixel offset from the monitor center. |

> Legacy configs with a single top-level `"crosshair"` object still load — they're treated as the
> sole preset named `"default"`.

## ⚠️ Anti-cheat / Terms-of-Service note

A static center crosshair is a common accessibility aid (many monitors ship one in firmware), and
JigHair reads no game memory and injects nothing. However, an external always-on-top overlay pointed
at an online competitive game protected by anti-cheat (VAC, Vanguard, EasyAntiCheat) may be flagged,
and an aiming aid can violate that game's Terms of Service — which can get accounts banned. The
foreground feature is app-agnostic; pointing it at protected online games is at your own risk.
