# jig+hair — Audit, Test Report & Improvement Plan

_Last updated: 2026-05-28 · Toolchain verified: Zig 0.16.0 (WinGet) · OS: Windows 11 26200_

This document is the result of a full read-through of the codebase, a live test of the
rendered overlay against several configs, and a design pass for the requested features
(presets / build-your-own crosshairs, and auto-show based on the foreground app), plus an
optimization plan.

---

## 0. TL;DR

- **It works.** Builds cleanly from source and renders a correctly-centered, click-through,
  always-on-top crosshair. I verified centering, colors, thickness/length/gap, the dot
  toggle, `offset_x/offset_y`, and the malformed-config fallback — all correct.
- **Biggest efficiency win:** the overlay is a **full-screen 1920×1080 layered window
  (~8.3 MB DIB)** drawing a ~30 px crosshair. Shrinking it to a small bounded window cuts
  the bitmap and compositor work by ~99%.
- **Biggest correctness gap:** **no DPI awareness** — on a scaled display the overlay can be
  mis-sized / off-center / blurry. One call at startup fixes it.
- **Ship Release builds:** Debug `JigHair.exe` is **1.9 MB**; `ReleaseSmall` is **417 KB**
  (−78%). The binary currently in `zig-out/` was a Debug build.
- **Doc bug:** README says "Requires Zig 0.14.0+", but the code uses Zig 0.16 APIs
  (`std.Io`, `std.process.Environ`) and `build.zig.zon` pins `minimum_zig_version = "0.16.0"`.
- Both requested features are very achievable on this architecture; designs + a
  backward-compatible config schema are below. **Read the anti-cheat caveat in §6 before
  shipping auto-show for online competitive games.**

---

## 1. What was verified (live)

| Check | Method | Result |
|---|---|---|
| Builds from source | `zig build` (0.16.0) | ✅ exit 0, ~6.4 s |
| Release builds | `-Doptimize=ReleaseSmall/ReleaseFast` | ✅ 417 KB / 726 KB |
| Default render & centering | run + screenshot of screen center | ✅ lime cross + outline + dot, centered |
| Color / thickness / length / gap / no-dot | thick red cross config | ✅ correct |
| Dot-only (`length: 0`, big `dot_size`) | yellow dot config | ✅ just the dot, no arms |
| Thin / long / no-outline | 1 px magenta, `outline: 0` | ✅ correct (but low-visibility — see §3) |
| `offset_x / offset_y` | cyan at `+200,-100`; captured offset **and** true center | ✅ appears at offset; true center empty |
| Malformed-config fallback | wrote invalid JSON | ✅ fell back to default green crosshair |
| Click-through / topmost | crosshair drew over the terminal | ✅ |
| Idle CPU | blocking `GetMessageW`, single static present | ✅ ~0% when idle |

Test artifacts (temporary configs + screenshots) were created under `%APPDATA%\JigHair\`
and in the repo root, then **cleaned up**; the machine was restored to its original
no-config state.

---

## 2. Architecture (as built today)

```
main.zig      → DPI? no. Registers class; creates a FULL-SCREEN layered/transparent/
                topmost/toolwindow/noactivate popup at (0,0, SM_CXSCREEN, SM_CYSCREEN).
                Registers Ctrl+Alt+F8 quit hotkey. Draws once, presents once, then
                blocks in GetMessage loop.
config.zig    → Loads %APPDATA%\JigHair\config.json via std.Io.Threaded; defaults on
                missing/malformed. Single `crosshair` object.
crosshair.zig → draw(): clear, compute center+offset, draw outline rects, arm rects,
                dot rect — all via renderer.fillRect.
renderer.zig  → 32-bit top-down DIB section (CreateDIBSection), premultiplied alpha,
                fillRect (clipped row memsets), present() = UpdateLayeredWindow(ULW_ALPHA).
window.zig    → wndProc: WM_HOTKEY (quit), WM_DESTROY.
win32.zig     → Hand-rolled Win32 bindings.
```

The **draw-once / static** model is a good fit for a fixed crosshair: near-zero idle CPU,
no per-frame cost. It does mean any runtime change (preset switch, show/hide) must
re-`draw()` + re-`present()` — both cheap, so the features below build on it naturally.

---

## 3. Findings — correctness & docs

> Severity: 🔴 fix soon · 🟡 should fix · ⚪ minor / cosmetic

- 🔴 **No DPI awareness.** `main.zig` never sets a DPI context, so on a display with
  scaling > 100% `GetSystemMetrics(SM_CXSCREEN/SM_CYSCREEN)` returns *logical* pixels and
  Windows bitmap-stretches the layered window → crosshair is mis-sized, off-center, and
  blurry. **Fix:** call `SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)`
  (`= (HANDLE)-4`) **before** any UI / metrics call. Must be the first thing in `main`.
  _Verified against Microsoft docs._
- 🟡 **README Zig version is wrong.** README: "Requires Zig 0.14.0+". Reality: code uses
  `std.Io.Threaded`, `std.Io.Dir.openFileAbsolute`, `file.reader(io, ...)`,
  `allocRemaining(.limited(...))`, and `std.process.Environ` — all Zig 0.16 APIs.
  `build.zig.zon` correctly pins `minimum_zig_version = "0.16.0"`. **Fix README to 0.16.0.**
- 🟡 **README build command produces a Debug binary.** `zig build` defaults to Debug
  (1.9 MB, includes `DebugAllocator`). Document `zig build -Doptimize=ReleaseSmall` for
  distribution, or change the default in `build.zig`.
- 🟡 **Primary-monitor only.** `main.zig:27-29` hardcodes the primary monitor and places the
  window at `(0,0)`. On multi-monitor setups the crosshair is centered on the primary
  monitor only. `SM_X/Y/CX/CYVIRTUALSCREEN` are already declared in `win32.zig:121-124` but
  unused. The small-window optimization (§4) makes "center of the monitor under the
  cursor / foreground window" easy.
- ⚪ **No `WM_DISPLAYCHANGE` / `WM_DPICHANGED` handling.** Resolution or monitor-config
  changes won't recenter/resize until restart.
- ⚪ **`renderer.setPixel` is dead code** (`renderer.zig:81-85`) — nothing calls it. Remove,
  or repurpose it for a future circle rasterizer (§5).
- ⚪ **Redundant clear.** `Renderer.init` memsets the DIB (`renderer.zig:57`) and `draw()`
  immediately calls `clear()` again (`crosshair.zig:8`). One-shot, negligible.
- ⚪ **Even-thickness half-pixel bias.** With even `thickness`/`dot_size`, arms/dot are 1 px
  biased left/top (`cx - @divTrunc(t,2)`). Inherent to integer centering; cosmetic. Could
  document "odd values center perfectly" or add a center-rounding option.
- ⚪ **Low-visibility combo.** `thickness: 1` + `outline: 0` is nearly invisible on busy
  backgrounds (observed in testing). Consider a docs note or a minimum-contrast default.
- ⚪ **No config range validation.** Negative/huge values are accepted; `fillRect` clips
  safely so it won't crash, but results can be surprising. Optional clamp on load.

No memory-safety or resource-leak bugs found: DC/DIB/bitmap lifetimes use `errdefer` in
`init` and are released in `deinit`; the hotkey is unregistered on exit. Pixel layout
(`packed struct(u32)` B,G,R,A) correctly matches a 32-bit `BI_RGB` top-down DIB.

---

## 4. Findings — efficiency / "as optimal as possible"

Ranked by impact.

1. **Shrink the overlay window from full-screen → small bounded window.** _(Biggest win.)_
   - Today: `1920×1080×4 ≈ 8.3 MB` DIB; `UpdateLayeredWindow` composites a full-screen
     surface for a ~30 px shape.
   - Proposed: compute the crosshair's bounding box
     `R = outline + gap + length` (plus `dot_size/2`), make a window `~2R+margin` square
     (e.g. 128×128 → **64 KB** DIB), positioned at `screen_center + offset − half_window`.
     Reposition on config/preset change.
   - Wins: **~99% less bitmap memory**, far less compositor work per present, faster
     startup, and it makes per-monitor centering trivial.
   - Watch-outs: recompute bounds + window position when the preset/offset changes; clamp
     so a huge `offset` still lands the window on-screen.

2. **Ship Release builds.** `ReleaseSmall` = 417 KB vs Debug 1.9 MB (−78%); `ReleaseFast`
   = 726 KB. For a static overlay, `ReleaseSmall` is the right default.

3. **Drop `DebugAllocator` + `std.Io.Threaded` for config load.** The only heap use is
   one-shot config parsing (path join, file read, JSON). `std.Io.Threaded` spins up
   thread-pool machinery to read one small file. Use a stack `FixedBufferAllocator`
   (e.g. 8–16 KB) + a fixed read buffer, or `page_allocator`. Removes leak-tracking
   overhead and the threaded-IO layer; simpler and lighter. (`single_threaded = true` is
   already set in `build.zig` — good.)

4. **Keep idle cost at zero.** The blocking `GetMessageW` + single static present is
   already optimal. **Do not** add a polling timer for the foreground feature — use the
   event hook (§6) so idle CPU stays ~0%.

5. **(Optional) premultiply rounding.** `(x*a)/255` floors; `(x*a + 127)/255` rounds.
   Visually negligible for opaque crosshairs — skip unless adding translucency presets.

---

## 5. Feature A — multiple crosshairs / presets / build-your-own

Delivered in three phases, each shippable on its own.

### Phase A1 — Named presets + switch hotkey _(small, high value)_
Config gains a `presets` map and an `active` selector; a hotkey cycles them. Because
`draw()` + `present()` are cheap, switching at runtime is just "re-draw the new preset"
(plus reposition the window if using the small-window optimization).

- New win32: nothing (reuse `RegisterHotKey`). Add e.g. `Ctrl+Alt+X` = "next preset".
- This already satisfies "different crosshairs" **and** "build your own" — a user adds a
  named preset and cycles to it.

### Phase A2 — Shape kinds _(medium)_
Add `shape` to a preset: `cross` (current), `dot`, `circle`, `t` (no top arm), `x`
(diagonal), `chevron`. `crosshair.zig` dispatches on `shape`.
- `circle`/`x` need new rasterizers in `renderer.zig`: a midpoint-circle (outline + filled)
  and a thick line (Bresenham/`fillRect` along the diagonal). `setPixel` (currently dead)
  becomes the circle plotter — keep it.

### Phase A3 — Composable primitives ("true" build-your-own) _(larger)_
A preset may instead be a list of primitives, rendered in order:
```json
"shapes": [
  {"type":"rect",   "x":-1, "y":-15, "w":2, "h":10, "color":[0,255,0,255]},
  {"type":"circle", "cx":0, "cy":0,  "r":8, "thickness":2, "color":[0,255,0,180]},
  {"type":"line",   "x0":-10,"y0":-10,"x1":10,"y1":10, "thickness":2, "color":[...]}
]
```
Coordinates are relative to the crosshair center. The current cross+dot becomes one
built-in generator that emits rects, so old configs keep working. This is the fully
flexible path (T-shapes, rings, chevrons, dotted gaps, anything).

**Recommendation:** A1 now (cheap, covers the immediate ask), A2 next, A3 when there's
appetite for an in-repo "gallery" of community presets.

---

## 6. Feature B — auto-show based on the foreground app

> **Goal restated:** show the crosshair only when a chosen app is running — *or, better,
> only when it is the foreground (focused) window.* Foreground is the right signal and is
> fully event-driven (no polling).

### Mechanism (verified against MS docs)
1. At startup set DPI awareness (§3) and create the window **hidden** (`SW_HIDE`) when in
   foreground mode.
2. Install one accessibility hook:
   `SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL, &cb, 0, 0, WINEVENT_OUTOFCONTEXT)`.
   With `WINEVENT_OUTOFCONTEXT` the callback is delivered **on the thread that called
   `SetWinEventHook`** — i.e. our existing `GetMessage` loop, so no new thread and idle
   cost stays ~0%.
3. In the callback (and once at startup): `GetForegroundWindow()` →
   `GetWindowThreadProcessId(hwnd, &pid)` → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,…)`
   → `QueryFullProcessImageNameW(…)` → take the basename → case-insensitive match against
   the allowlist → `ShowWindow(overlay, match ? SW_SHOWNOACTIVATE : SW_HIDE)`.
   The overlay is `WS_EX_NOACTIVATE`, so showing it never steals focus and won't trigger a
   foreground event loop. _Note: the foreground window may already be gone by the time the
   event arrives — guard the handle calls._
4. `UnhookWinEvent` on exit.

### New win32 bindings needed
`HWINEVENTHOOK`, `WINEVENTPROC`, `SetWinEventHook`, `UnhookWinEvent`,
`GetForegroundWindow`, `GetWindowThreadProcessId`, `OpenProcess`, `CloseHandle`,
`QueryFullProcessImageNameW`, and constants `EVENT_SYSTEM_FOREGROUND = 0x0003`,
`WINEVENT_OUTOFCONTEXT = 0x0000`, `PROCESS_QUERY_LIMITED_INFORMATION = 0x1000`.

### Config
```json
"visibility": {
  "mode": "always",                // "always" | "foreground_apps"
  "apps": ["cs2.exe", "notepad.exe"],
  "match": "process_name"          // future: "window_title_substring"
}
```
`"running anywhere"` (not just foreground) is a weaker variant — it needs polling or a
process-creation WMI/ETW watch; **foreground mode is both simpler and more optimal**, so
make it the primary mode.

### ⚠️ Anti-cheat / ToS caveat (please read)
A static center crosshair is a legitimate, common accessibility aid (many monitors ship one
in firmware), and this app reads no game memory and injects nothing. **However**, an
external always-on-top overlay that auto-targets specific online competitive games
(e.g. titles using VAC, Vanguard, EasyAntiCheat) can be flagged by anti-cheat as a
disallowed overlay, and an aiming aid may violate the game's Terms of Service — which can
get accounts banned. The feature is general (it matches any process name), but if you point
it at protected online games, that's your risk to accept. Recommend: ship it app-agnostic,
document this clearly, and don't preset it to specific anti-cheat-protected titles.

---

## 7. Proposed config schema v2 (backward-compatible)

Old top-level `crosshair` keeps working (treated as the sole preset named `"default"`).

```json
{
  "active": "default",
  "switch_hotkey": "ctrl+alt+x",
  "quit_hotkey": "ctrl+alt+f8",
  "visibility": { "mode": "always", "apps": [], "match": "process_name" },
  "presets": {
    "default": {
      "color": [0,255,0,255], "outline_color": [0,0,0,255], "outline": 1,
      "thickness": 2, "length": 10, "gap": 4, "dot": true, "dot_size": 2,
      "offset_x": 0, "offset_y": 0
    }
  }
}
```
`config.zig` loads `presets`/`active` if present, else wraps a legacy top-level `crosshair`.
Keep `ignore_unknown_fields = true` for forward-compat.

---

## 8. Roadmap (suggested order)

| # | Item | Type | Effort | Payoff |
|---|---|---|---|---|
| 1 | `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` at startup | fix | XS | Correct on scaled displays |
| 2 | Fix README (Zig 0.16; document `-Doptimize=ReleaseSmall`) | docs | XS | Accurate build instructions |
| 3 | Default/distribute `ReleaseSmall` | build | XS | 1.9 MB → 417 KB |
| 4 | Small bounded window instead of full-screen | perf | S–M | ~99% less bitmap/compositor work |
| 5 | Replace `DebugAllocator`+`std.Io.Threaded` with `FixedBufferAllocator` | perf | S | Lighter, simpler config load |
| 6 | Phase A1: presets + cycle hotkey | feature | S | "Different crosshairs" + build-your-own |
| 7 | Feature B: foreground auto-show (event hook) | feature | M | The headline feature |
| 8 | Phase A2: shape kinds (circle/t/x/chevron) | feature | M | Variety |
| 9 | Multi-monitor centering (center under cursor/foreground) | feature | S–M | Correct on multi-mon (rides on #4) |
| 10 | Phase A3: composable primitives | feature | M–L | Full custom crosshairs |
| 11 | `WM_DISPLAYCHANGE`/`WM_DPICHANGED` recenter; remove dead `setPixel`; optional range clamp | polish | S | Robustness |

Items 1–5 are low-risk hardening/optimization. 6–7 deliver the requested features. 8–11
are enhancements.

---

## 9. Decisions I need from you

1. **Scope of this pass:** want me to start *implementing* from the top of §8 (I can build
   and visually re-verify each change with Zig 0.16), or keep this as a plan first?
2. **Quick wins now?** I'd suggest doing #1–#3 immediately (tiny, pure wins). OK to proceed?
3. **Auto-show target apps:** which apps do you actually want it for? (This affects the
   anti-cheat note in §6 — if any are online competitive games, let's talk about the risk.)
4. **Preset switching UX:** cycle-with-hotkey (simplest), or also a small config-driven
   menu? Any preferred default hotkey other than `Ctrl+Alt+X`?
5. **Custom depth:** is Phase A1 (named presets) enough for "build your own" for now, or do
   you want the A3 composable-primitives path on the near roadmap?

---

_Notes on environment: Zig 0.16.0 is installed via WinGet but not on PATH
(`…\WinGet\Packages\zig.zig_…\zig-x86_64-windows-0.16.0\zig.exe`). Consider adding it to
PATH, or I can keep invoking it by full path._
