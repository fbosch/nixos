# Hyprland plugins

This directory contains eight local Hyprland plugins used by this NixOS
configuration. They add renderer effects and native hooks that are awkward or
too expensive to implement in Lua.

| Plugin                                                  | Version | Purpose                                                          |
| ------------------------------------------------------- | ------- | ---------------------------------------------------------------- |
| [`adaptive-soft-shadow`](adaptive-soft-shadow/)         | 0.2.2   | Draw backdrop-adaptive window shadows.                           |
| [`anr-tag-ignore`](anr-tag-ignore/)                     | 0.1.0   | Reset ANR state for clients whose windows carry configured tags. |
| [`cursor-outline`](cursor-outline/)                     | 0.1.0   | Draw a configurable outline around the cursor silhouette.        |
| [`custom-layout-resize`](custom-layout-resize/)         | 0.3.1   | Drive custom tiled-layout resizing from native pointer motion.   |
| [`focus-animation`](focus-animation/)                   | 0.1.10  | Add a scale-based `windowsFocus` animation leaf.                 |
| [`inset-border`](inset-border/)                         | 0.3.0   | Draw focus-aware keylines inside window content.                 |
| [`pointer-edge-hooks`](pointer-edge-hooks/)             | 0.1.0   | Emit pointer zones relative to the bottom monitor edge.          |
| [`window-interaction-hooks`](window-interaction-hooks/) | 0.2.0   | Emit live and completed native window move and resize events.    |

All plugins are MIT-licensed and currently packaged for `x86_64-linux`.

## Compatibility

Hyprland does not provide a stable plugin ABI. Each plugin is built against the
Hyprland flake input and refuses to load unless the running compositor has the
same commit hash. Rebuild these packages whenever the Hyprland input changes.
Mixing a plugin from one system generation with Hyprland from another is not
supported.

The packages use Hyprland's Nixpkgs input, GCC 16, CMake, and C++26. Each
package installs one shared library under `$out/lib`.

[`modules/desktop/hyprland.nix`](../../../modules/desktop/hyprland.nix) installs
the packages and publishes their library paths as session variables:

| Plugin                     | Session variable                       | Library                          |
| -------------------------- | -------------------------------------- | -------------------------------- |
| `adaptive-soft-shadow`     | `HYPR_ADAPTIVE_SOFT_SHADOW_PLUGIN`     | `libadaptive-soft-shadow.so`     |
| `anr-tag-ignore`           | `HYPR_ANR_TAG_IGNORE_PLUGIN`           | `libanr-tag-ignore.so`           |
| `cursor-outline`           | `HYPR_CURSOR_OUTLINE_PLUGIN`           | `libcursor-outline.so`           |
| `custom-layout-resize`     | `HYPR_CUSTOM_LAYOUT_RESIZE_PLUGIN`     | `libcustom-layout-resize.so`     |
| `focus-animation`          | `HYPR_FOCUS_ANIMATION_PLUGIN`          | `libfocus-animation.so`          |
| `inset-border`             | `HYPR_INSET_BORDER_PLUGIN`             | `libinset-border.so`             |
| `pointer-edge-hooks`       | `HYPR_POINTER_EDGE_HOOKS_PLUGIN`       | `libpointer-edge-hooks.so`       |
| `window-interaction-hooks` | `HYPR_WINDOW_INTERACTION_HOOKS_PLUGIN` | `libwindow-interaction-hooks.so` |

The matching Lua integrations live in the
[`dotfiles` repository](https://github.com/fbosch/dotfiles/tree/master/.config/hypr/plugins).
They load each library with `hl.plugin.load()` and configure or subscribe to the
interfaces described below.

## Renderer plugins

### `adaptive-soft-shadow`

[`adaptive-soft-shadow/main.cpp`](adaptive-soft-shadow/main.cpp) attaches a
soft-shadow decoration to mapped, decorated windows. It skips windows that
disable borders, decoration, or shadows.

Configuration uses the `plugin:adaptive_soft_shadow` namespace:

| Key            | Type     | Default      | Constraint                                                  |
| -------------- | -------- | ------------ | ----------------------------------------------------------- |
| `enabled`      | boolean  | `true`       | Enables the decoration.                                     |
| `range`        | integer  | `20`         | Shadow extent in logical pixels, from 1 to 80.              |
| `render_power` | integer  | `3`          | Falloff exponent, from 1 to 4.                              |
| `offset`       | vector   | `1 1`        | Finite logical-pixel offsets from -250 to 250 on each axis. |
| `strength`     | float    | `0.30`       | Shadow strength, from 0 to 1.                               |
| `color`        | gradient | opaque black | Solid color or gradient with at most 10 colors.             |
| `blend_mode`   | string   | `soft-light` | Advanced blend equation.                                    |

`blend_mode` accepts `multiply`, `screen`, `overlay`, `darken`, `lighten`,
`color-dodge`, `color-burn`, `hard-light`, `soft-light`, `difference`,
`exclusion`, `hsl-hue`, `hsl-saturation`, `hsl-color`, or `hsl-luminosity`.
Invalid values are rejected.

Advanced blending requires the necessary OpenGL blend extensions. Unsupported
framebuffer formats, output transforms, mirror-copy paths, or missing blend
support use Hyprland's normal shadow renderer instead. The plugin reports the
capability fallback through a Hyprland notification. Gradients longer than 10
colors are truncated and reported once.

This plugin does not expose Lua functions or custom events.

### `cursor-outline`

[`cursor-outline/main.cpp`](cursor-outline/main.cpp) renders an alpha-dilated
outline around RGBA software cursor textures. It locks software cursor rendering
for eligible monitors while enabled.

Configuration uses the `plugin:cursor_outline` namespace:

| Key         | Type    | Default      | Constraint                                                                       |
| ----------- | ------- | ------------ | -------------------------------------------------------------------------------- |
| `thickness` | integer | `3`          | Logical pixels, from 1 to 4. The rendered radius is capped at 8 physical pixels. |
| `color`     | color   | `0xF56099C0` | Hyprland color value.                                                            |

Lua API under `hl.plugin.cursor_outline`:

| Function   | Result                                                 |
| ---------- | ------------------------------------------------------ |
| `toggle()` | Toggle the outline.                                    |
| `on()`     | Enable the outline and lock software cursors.          |
| `off()`    | Disable the outline and release software cursor locks. |

These functions return no values. The plugin requires Hyprland's OpenGL
renderer and only handles RGBA cursor textures. It skips mirrored, disabled,
and DPMS-off monitors. A shader initialization failure disables outline
rendering until the plugin is reloaded.

### `focus-animation`

[`focus-animation/main.cpp`](focus-animation/main.cpp) adds a `windowsFocus`
animation leaf beneath Hyprland's `windows` animation. Supported keyboard and
dispatcher focus changes scale the focused window from the configured `popin`
percentage to its full size while keeping it centered.

Lua API under `hl.plugin.focus_animation`:

| Function    | Result                                                         |
| ----------- | -------------------------------------------------------------- |
| `prepare()` | Recreate the `windowsFocus` leaf after a configuration reload. |

`prepare()` returns no values. It raises an error when the parent `windows`
animation is unavailable.

The leaf starts with style `popin 96%`, speed `1`, and disabled state. A
configured `popin N%` start scale is clamped to 50 through 100 percent;
unsupported or malformed styles use 96 percent. No focus animation runs when
the window's position or size is already animated, or when the start scale is
100 percent.

The implementation modifies Hyprland's internal animation tree because the
plugin API cannot add animation leaves. This makes the exact-commit requirement
especially important.

### `inset-border`

[`inset-border/main.cpp`](inset-border/main.cpp) draws a focus-aware keyline
inside the client area rather than adding another outer border.

Configuration uses the `plugin:inset_border` namespace:

| Key              | Type     | Default      | Constraint                                                 |
| ---------------- | -------- | ------------ | ---------------------------------------------------------- |
| `enabled`        | boolean  | `true`       | Enables the decoration.                                    |
| `thickness`      | integer  | `1`          | Logical pixels, from 1 to 4.                               |
| `inset`          | integer  | `0`          | Distance from the client edge, from 0 to 8 logical pixels. |
| `active_color`   | gradient | `0x73FFFFFF` | Color for the focused window.                              |
| `inactive_color` | gradient | `0x1AFFFFFF` | Color for unfocused windows.                               |
| `blend_mode`     | string   | `normal`     | Keyline blend equation.                                    |

`blend_mode` accepts `normal` and every advanced mode listed for
`adaptive-soft-shadow`. Invalid values are rejected. Advanced gradients are
limited to 10 colors.

Normal blending uses Hyprland's standard border pass. Advanced blending needs
framebuffer-fetch or texture-barrier support and an internal Hyprland transform
hook. Missing capabilities, unsupported framebuffer formats, opaque targets,
or mirror-copy rendering fall back to normal blending. Hook and capability
failures are reported through Hyprland notifications.

This plugin does not expose Lua functions or custom events.

## Policy plugins

### `anr-tag-ignore`

[`anr-tag-ignore/main.cpp`](anr-tag-ignore/main.cpp) hooks Hyprland's internal
ANR timer. Before and after each normal ANR pass, it resets missed pings, closes
an existing ANR dialog, and clears the unresponsive tint for matching clients.
A client matches only when every mapped window belonging to it carries at least
one configured ignored tag.

Configuration uses the `plugin:anr_tag_ignore` namespace:

| Key            | Type   | Default | Constraint                                                            |
| -------------- | ------ | ------- | --------------------------------------------------------------------- |
| `ignored_tags` | string | empty   | Comma-separated window tag names. Whitespace around names is ignored. |

The dotfiles config sets `ignored_tags` to `intentionally-frozen`. The gaming
watchdog adds that tag before `wl-freeze` stops a process, then resumes the
process before removing the tag.

This plugin hooks the private `CANRManager::onTick()` method because Hyprland
does not expose an ANR interception API. Exact-commit validation prevents it
from loading against a different Hyprland build.

## Interaction plugins

### `custom-layout-resize`

[`custom-layout-resize/main.cpp`](custom-layout-resize/main.cpp) converts native
pointer movement into resize commands for selected tiled custom layouts. It can
retarget and focus another eligible tiled window under the pointer during a
resize session.

Lua API under `hl.plugin.custom_layout_resize`:

| Function                                                              | Result                                                                    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `start(ultrawideLayout, portraitLayout, portraitMonitor, blockedTag)` | Returns `started, handled`.                                               |
| `stop()`                                                              | Returns whether a resize session was active.                              |
| `rebind()`                                                            | Re-registers the custom event and returns whether registration succeeded. |

All four `start()` arguments are strings. The plugin resizes vertically for the
named portrait layout. For the named ultrawide layout, it resizes vertically on
`portraitMonitor` and horizontally elsewhere. Floating windows, unsupported
layouts, and windows carrying `blockedTag` are ineligible.

`start()` distinguishes three outcomes:

| Return values  | Meaning                                                |
| -------------- | ------------------------------------------------------ |
| `false, false` | Required compositor state is unavailable.              |
| `false, true`  | The compositor is ready, but the target is ineligible. |
| `true, true`   | The resize session started.                            |

The plugin emits `custom_layout_resize.command` with one string payload. During
pointer movement, the value has one of these forms:

```text
resize-x-at address:0x<window> <left|right> <coordinate>
resize-y-at address:0x<window> <up|down> <coordinate>
```

Updates are rate-limited to the target monitor's refresh interval, clamped
between 6 and 17 milliseconds, and deduplicated by rounded coordinate. `stop()`
emits the final position followed by `save-resize`. A configuration reload
stops the current session without saving.

Call `rebind()` after a config reload. Hyprland replaces Lua event handlers
without notifying an already-loaded plugin, so the custom event must be
re-registered for the new Lua state.

### `pointer-edge-hooks`

[`pointer-edge-hooks/main.cpp`](pointer-edge-hooks/main.cpp) classifies the
pointer by its vertical distance from the bottom of the current monitor.

Lua API under `hl.plugin.pointer_edge_hooks`:

| Function                              | Result                                                                      |
| ------------------------------------- | --------------------------------------------------------------------------- |
| `start(showThreshold, hideThreshold)` | Start tracking and return whether the initial zone was emitted.             |
| `stop()`                              | Stop tracking and return whether tracking was active.                       |
| `sync()`                              | Force the current zone to be emitted and return whether emission succeeded. |
| `rebind()`                            | Re-registers the custom event and returns whether registration succeeded.   |

Thresholds are integers measured in logical pixels. `showThreshold` must be
non-negative and `hideThreshold` must be greater than `showThreshold`. The
internal defaults are 20 and 60.

The plugin emits `pointer_edge_hooks.zone` with two string fields:

| Position | Field     | Value                        |
| -------- | --------- | ---------------------------- |
| 1        | `zone`    | `show`, `neutral`, or `hide` |
| 2        | `monitor` | Hyprland monitor name.       |

`show` covers distances through `showThreshold`, `neutral` covers distances
through `hideThreshold`, and larger distances produce `hide`. Mouse movement
emits only when the zone or monitor changes. `start()` and `sync()` force an
event. A pointer outside known monitor rectangles produces no event.

Call `rebind()` after a config reload for the same reason as
`custom-layout-resize`.

### `window-interaction-hooks`

[`window-interaction-hooks/main.cpp`](window-interaction-hooks/main.cpp) observes
Hyprland's native interactive move and resize controller. After the drag
threshold is reached, it streams deduplicated geometry updates and emits a final
completion event when the controller releases its target.

Lua API under `hl.plugin.window_interaction_hooks`:

| Function             | Result                                                                      |
| -------------------- | --------------------------------------------------------------------------- |
| `rebind()`           | Re-registers both custom events and returns whether registration succeeded. |
| `supports_updates()` | Returns `true` when live update delivery is available.                      |

The plugin emits `window_interaction_hooks.updated` and
`window_interaction_hooks.finished` with the same fields in order:

| Position | Field    | Type   | Value                                     |
| -------- | -------- | ------ | ----------------------------------------- |
| 1        | `window` | window | The affected Hyprland window.             |
| 2        | `kind`   | string | `move` or `resize`.                       |
| 3        | `x`      | double | Current or final layout-box x coordinate. |
| 4        | `y`      | double | Current or final layout-box y coordinate. |
| 5        | `width`  | double | Current or final layout-box width.        |
| 6        | `height` | double | Current or final layout-box height.       |

Live updates are captured from `render.pre` for the interacted window's current
monitor after Hyprland applies pointer-driven geometry. At most one changed
layout box is retained per render cycle, and unchanged geometry is discarded.
Lua callbacks and Socket2 writes are queued for the next event-loop turn rather
than running inside the render callback. This follows the monitor's actual frame
scheduling instead of applying a hardcoded or calculated millisecond interval.

When an interaction ends, any pending or newer final geometry is delivered
before `window_interaction_hooks.finished`, preserving update-before-finish
ordering even when the release occurs before an idle delivery.

The same update is mirrored to Socket2 for long-lived external consumers:

```text
windowinteractionupdated>>0x<window>,<move|resize>,<monitor-id>,<x>,<y>,<width>,<height>
```

The plugin recognizes normal moves and normal, forced-ratio, and
blocked-ratio resizes. It ignores other mouse-bind modes and does not emit if
the captured window is unmapped before delivery or completion.

Call `rebind()` after a config reload so the new Lua state receives both custom
events.

## Reload behavior

Loading a plugin can cause Hyprland to reload its configuration. The dotfiles
integrations account for that reload before applying plugin configuration or
calling Lua functions.

Custom events belong to the Lua state in which they were registered. After a
configuration reload, call `rebind()` on:

- `hl.plugin.custom_layout_resize`
- `hl.plugin.pointer_edge_hooks`
- `hl.plugin.window_interaction_hooks`

Call `hl.plugin.focus_animation.prepare()` after reload to restore its animation
leaf. Renderer plugin configuration is read from the current Hyprland config
state and does not need a separate rebind call.
