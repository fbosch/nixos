# Persistent position

This native Hyprland plugin remembers position and size for selected floating windows. It reads its own versioned state at `configure()` time and injects saved size and monitor-local position before the first floating layout pass. A revision-pinned pre-map static-rule hook forces selected windows into the initial windowed state without a config reload, generated rule updates, or delayed moves. PiP accepted placement can also choose its saved monitor before layout; ordinary selectors retain normal routing.

The package is discovered by `pkgs.local."hyprland-plugins/persistent-position"`. The production configuration stages installation and loading; rebuilding and starting a new matching session are separate rollout steps. Do not hot-load this build over the running position-only plugin.

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

Selectors are evaluated in declaration order; the first matching, nonexcluded entry wins. Each entry needs a unique stable `id`, `matcher`, and RE2 `pattern`. `restore_size` and `force_windowed` default to `true`. Fields are `match:class`, `match:title`, `match:initial_class`, and `match:initial_title`; camel-case initial-field aliases also work. Regexes use Hyprland full-match semantics, including `negative:`. Exclusions reject only the current selector. `per_monitor = true` is the default; `false` shares monitor-relative state across outputs. Changing an ID starts a new cache identity.

Pointer-driven moves and resizes save their final settled layout position when the native drag completes. For a user-issued move or center action outside a native drag, call `hl.plugin.persistent_position.capture_focused()` **after** issuing that action. It returns `true` if an eligible focused window was queued for capture on the next event-loop turn, `false` otherwise. It cannot infer whether an arbitrary position change was a user action, so it does not observe all geometry updates. Close retries a pending save; it does not treat automatic placement or monitor evacuation as a new user move. Captures queued but not delivered when `configure()` replaces a policy are canceled, not replayed against the replacement.

Only a mapped, floating, windowed, nonmaximized window with finite geometry can be saved. Captures preserve a logical position, selected size, and selected windowed metadata. Existing explicit `move` or `center` rules take precedence at initial map; saved size overrides a static size rule, as did the legacy generated size rule. `force_windowed` sets initial fullscreen state to (0,0) before map routing, without permanently suppressing later client fullscreen requests. A missing monitor record uses normal placement. At map, the saved offset is clamped inside the monitor's usable logical box with `window_w` and `window_h` evaluated by the floating layout after final initial size selection; an oversized window anchors to the usable box's top-left without resizing. Records for disconnected monitors remain on disk.

The state format is `persistent-position-v2`: one bounded tab-separated record per hex-encoded selector/monitor key, with position x/y, size width/height, windowed (`0`, `1`), hex target-monitor, and placement (`free` or a corner name) fields. Each optional field uses `-` when absent; numeric pairs must be present or absent together. Position offsets are monitor-relative logical units. v1 position-only files remain readable; the first successful write atomically replaces v1 with v2 after preserving the original inode at `<state>.v1.bak` (a conflicting backup fails closed). `import_legacy()` accepts optional `width`, `height` (paired positive finite numbers), and `windowed` (boolean), and merges only missing fields; existing native positions are never overwritten. The v1 reader and backup can be removed once existing persisted v1 files have migrated and rollback no longer needs their originals. PiP placement is an explicit optional record field; generic position and size remain independent. `state_version()` returns `2` for the full-state API. `configure()` drains pending writes and rereads the state file even when the path is unchanged. Malformed or unsupported state returns `nil, error`, leaves the file untouched, and retains the previous configuration. Completed user captures queue immutable cache snapshots to one worker; the compositor callback does no disk I/O. The worker coalesces waiting snapshots and uses a private temporary file, `fsync`, atomic rename, and directory `fsync`. A failed write keeps the new value in memory for a later close or unload retry and logs a warning. If the unload retry also fails, that unsaved value is lost; the previous state file remains available. On unload, listeners and queued callbacks are removed before the worker drains and joins.

## PiP accepted placement

Configure one global selector with `geometry_authority = "pip"`,
`per_monitor = false`, `restore_size = false`, `force_windowed = false`, and
`restore_monitor = true`. Generic capture never changes this record.

```lua
local ok, err = hl.plugin.persistent_position.accept_pip_placement({
  kind = "corner",
  corner = "top-right",
  target_monitor = "DP-2",
  width = 400,
  height = 225,
})
assert(ok, err)
```

A free placement uses `kind = "free"` and finite `x,y` offsets instead of
`corner`. Paired positive dimensions are optional and do not override the PiP
client's size. Acceptance queues an asynchronous save; it does not promise that
fsync has completed. The existing PiP reducer remains responsible for observing
accepted geometry and excluding temporary Waybar avoidance.

At first map, the plugin selects the saved monitor silently if present, restores
the corner or free position, and restores one or no corner tags. Corners use a
15-logical-pixel margin and the final initial size. Missing monitors use normal
routing without erasing the record. No rule registration, config reload, or
post-map movement is involved. `import_legacy()` accepts the same placement
fields alongside stable `id` and `monitor` keys; generic imports may contain
size without position.

## Check

From the repo root, `just check-hyprland-plugins` builds this package with the matching Hyprland flake input and runs `persistent-position-test` and `persistent-position-storage-test`. For worktree-only, untracked edits, the Git flake will not discover the new package until tracked. Compile and run the CMake target in `nix develop .#hyprland-plugins` without loading it into the running compositor. The windowed hook is pinned to Hyprland 19fb395d and must be separately proven in an isolated nested compositor before session rollout; loading on any other revision fails closed.
