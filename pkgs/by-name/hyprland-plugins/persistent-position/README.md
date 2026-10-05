# Persistent position

This native Hyprland plugin remembers positions for selected floating windows. It reads its own versioned state file at `configure()` time and injects a monitor-local `position` expression on `window.openEarly`, before the first floating layout pass. It never changes size, floating state, focus, workspace, or monitor routing.

The package is discovered by `pkgs.local."hyprland-plugins/persistent-position"` and the plugin check. It is **not installed, loaded, or enabled** in the production session by this change.

## Lua API

After loading the library in an isolated session, configure it from the Lua config, including after each config reload:

```lua
local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local ok, err = hl.plugin.persistent_position.configure(
  state_home .. "/hyprland/persistent-position.state",
  {
    {
      id = "nemo-main",
      matcher = "match:class",
      pattern = "^nemo$",
      exclude = {
        matcher = "match:initial_title",
        patterns = { "^File Operations$", "^Preparing$" },
      },
    },
    { id = "calendar", matcher = "match:class", pattern = "^org\\.gnome\\.Calendar$", per_monitor = false },
  }
)
if not ok then error(err) end
```

Supply an absolute state-file path inside `XDG_STATE_HOME`, or inside `HOME/.local/state` when `XDG_STATE_HOME` is unset. The plugin rejects paths outside that state root and any symlink in the directory path or state-file name. It creates missing directories during `configure()`. It does not read or write a file when a window maps.

Selectors are evaluated in declaration order; the first matching, nonexcluded entry wins. Each entry needs a unique stable `id`, `matcher`, and RE2 `pattern`. Fields are `match:class`, `match:title`, `match:initial_class`, and `match:initial_title` (camel-case `initialClass` and `initialTitle` also work). Regexes use Hyprland's full-match semantics, including `negative:`; `exclude` accepts a matcher and array of regex patterns. Excluded entries do not prevent a later selector matching. Do not opt PiP windows into this slice. The default `per_monitor = true` keeps separate offsets by monitor name. `per_monitor = false` uses one monitor-relative offset on whichever monitor normal routing chooses. Changing an `id` starts a new cache key. The Lua handoff calls `import_legacy(path, records)` before `configure()` on enabled sessions; the import validates every record, merges only missing selector/monitor keys, and uses the same secure atomic state writer as native captures. A failed import leaves the old generated move rules active.

Pointer-driven moves and resizes save their final settled layout position when the native drag completes. For a user-issued move or center action outside a native drag, call `hl.plugin.persistent_position.capture_focused()` **after** issuing that action. It returns `true` if an eligible focused window was queued for capture on the next event-loop turn, `false` otherwise. It cannot infer whether an arbitrary position change was a user action, so it does not observe all geometry updates. Close retries a pending save; it does not treat automatic placement or monitor evacuation as a new user move. Captures queued but not delivered when `configure()` replaces a policy are canceled, not replayed against the replacement.

Only a mapped, floating, windowed, nonmaximized window with finite geometry can be saved. Existing explicit `move` or `center` rules take precedence at initial map. A missing monitor record uses normal placement. At map, the saved offset is clamped inside the monitor's usable logical box with `window_w` and `window_h` evaluated by the floating layout after final initial size selection; an oversized window anchors to the usable box's top-left without resizing. Records for disconnected monitors remain on disk.

The state format is `persistent-position-v1` with bounded hex-encoded selector and monitor keys and finite logical offsets. `configure()` drains pending writes and rereads the state file even when the path is unchanged. Malformed or unsupported state returns `nil, error`, leaves the file untouched, and retains the previous configuration. Completed user captures queue immutable cache snapshots to one worker; the compositor callback does no disk I/O. The worker coalesces waiting snapshots and uses a private temporary file, `fsync`, atomic rename, and directory `fsync`. A failed write keeps the new value in memory for a later close or unload retry and logs a warning. If the unload retry also fails, that unsaved value is lost; the previous state file remains available. On unload, listeners and queued callbacks are removed before the worker drains and joins.

## Check

From the repo root, `just check-hyprland-plugins` builds this package with the matching Hyprland flake input and runs `persistent-position-test` and `persistent-position-storage-test`. For worktree-only, untracked edits, the Git flake will not discover the new package until tracked. Compile and run the CMake target in `nix develop .#hyprland-plugins` without loading it into the running compositor.
