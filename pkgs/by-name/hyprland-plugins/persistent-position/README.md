# Persistent position

This native Hyprland plugin remembers position and size for opted-in floating windows. It reads its own versioned state at `configure()` time and injects saved size and monitor-local position before the first floating layout pass. A revision-pinned pre-map static-rule hook forces selected windows into the initial windowed state without a config reload, generated rule updates, or delayed moves. PiP accepted placement can also choose its saved monitor before layout; ordinary rules retain normal routing.

The package is discovered by `pkgs.local."hyprland-plugins/persistent-position"`. The production configuration stages installation and loading; rebuilding and starting a new matching session are separate rollout steps. Do not hot-load this build over the running position-only plugin.

## Lua API

After loading the library, declare native `hl.window_rule` effects and configure the state path (also after config reload):

```lua
hl.window_rule({
  match = { class = "^nemo$", initial_title = "negative:^(File Operations|Preparing)$" },
  float = true,
  ["persistent_position:remember"] = "nemo-main",
})
hl.window_rule({
  match = { initial_title = "^Picture-in-Picture$" },
  float = true,
  ["persistent_position:remember"] = "picture-in-picture",
  ["persistent_position:profile"] = "pip",
})
local api = hl.plugin.persistent_position
assert(api.state_version() == 2 and api.rule_api_version() == 1)
local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local ok, err = api.configure(state_home .. "/hyprland/persistent-position.state")
assert(ok, err)
```

Declare rules only after the plugin has loaded and registered its effects. The rule API version is `1`; it is available only after effect registration. A named rule's `enabled = false` disables it without deleting its record. Hyprland evaluates all match fields together, including `negative:` regexes, and later matching rule effects win. The plugin uses the compositor's rule engine rather than a separate selector list. An invalid remember key or profile makes that window ineligible; a remember key must be 1 to 256 printable bytes without DEL or controls. The only profile values are `pip` and `ordinary` (the default). A rule may override ordinary defaults with boolean `persistent_position:per_monitor` (default `true`), `persistent_position:restore_size` or `persistent_position:force_windowed` (both default `true`). PiP has fixed global, no generic capture, no initial size/windowed override, and saved-monitor routing semantics; conflicting overrides disable persistence for that window.

Supply an absolute state-file path inside `XDG_STATE_HOME`, or inside `HOME/.local/state` when `XDG_STATE_HOME` is unset. The plugin rejects paths outside that state root and any symlink in the directory path or state-file name. It creates missing directories during `configure()`. It does not read or write a file when a window maps.

Pointer-driven moves and resizes save their final settled layout position when the native drag completes. For a user-issued move or center action outside a native drag, call `hl.plugin.persistent_position.capture_focused()` **after** issuing that action. It returns `true` if an eligible focused window was queued for capture on the next event-loop turn, `false` otherwise. It cannot infer whether an arbitrary position change was a user action, so it does not observe all geometry updates. Close retries a pending save; it does not treat automatic placement or monitor evacuation as a new user move. Captures queued but not delivered when `configure()` replaces a policy are canceled, not replayed against the replacement.

Only a mapped, floating, windowed, nonmaximized window with finite geometry can be saved. Captures preserve a logical position, selected size, and selected windowed metadata. Existing explicit `move` or `center` rules take precedence at initial map; saved size overrides a static size rule, as did the legacy generated size rule. `persistent_position:force_windowed` sets initial fullscreen state to (0,0) before map routing, without permanently suppressing later client fullscreen requests. A missing monitor record uses normal placement. At map, the saved offset is clamped inside the monitor's usable logical box with `window_w` and `window_h` evaluated by the floating layout after final initial size selection; an oversized window anchors to the usable box's top-left without resizing. Records for disconnected monitors remain on disk.

The state format is `persistent-position-v2`: one bounded tab-separated record per hex-encoded remember-key/monitor key, with position x/y, size width/height, windowed (`0`, `1`), hex target-monitor, and placement (`free` or a corner name) fields. Each optional field uses `-` when absent; numeric pairs must be present or absent together. Position offsets are monitor-relative logical units. Only v2 is supported. Older files are rejected without being overwritten; there is no migration API or automatic backup creation. PiP placement is an explicit optional record field; generic position and size remain independent. `state_version()` returns `2` for the full-state API. `configure()` drains pending writes and rereads the state file even when the path is unchanged. Malformed or unsupported state returns `nil, error`, leaves the file untouched, and retains the previous configuration. Completed user captures queue immutable cache snapshots to one worker; the compositor callback does no disk I/O. The worker coalesces waiting snapshots and uses a private temporary file, `fsync`, atomic rename, and directory `fsync`. A failed write keeps the new value in memory for a later close or unload retry and logs a warning. If the unload retry also fails, that unsaved value is lost; the previous state file remains available. On unload, listeners and queued callbacks are removed before the worker drains and joins.

## PiP accepted placement

Declare one enabled PiP rule with `persistent_position:remember` and `persistent_position:profile = "pip"`. `accept_pip_placement` takes no ID, so it rejects missing or ambiguous enabled PiP authorities. Generic capture never changes a PiP record.

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
routing without erasing the record. No config reload or
post-map movement is involved.

## Check

From the repo root, `just check-hyprland-plugins` builds this package with the matching Hyprland flake input and runs `persistent-position-test` and `persistent-position-storage-test`. For worktree-only, untracked edits, the Git flake will not discover the new package until tracked. Compile and run the CMake target in `nix develop .#hyprland-plugins` without loading it into the running compositor. The plugin checks that build headers match the running Hyprland and that required hooks resolve and install. There is no hardcoded supported commit. Verify lifecycle behavior in an isolated nested compositor after Hyprland updates before session rollout.
