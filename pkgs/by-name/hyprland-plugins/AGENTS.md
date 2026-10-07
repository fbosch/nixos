# Hyprland plugins

- Do not hardcode supported Hyprland commit hashes or release allowlists. Build against the current flake input; use Hyprland's plugin API/build-runtime compatibility checks and verify required symbols and hook installation. A build-derived hash comparison is an ABI check, not a supported-commit pin.
- Internal hooks can compile while lifecycle behavior changes. After hook changes or Hyprland updates, run `just check-hyprland-plugins` from the repository root and verify affected behavior in an isolated nested compositor using the matching compositor and plugin build.
- Never load an experimental plugin into the production compositor or activate a system generation without explicit authorization. A successful build does not authorize rollout.
- When loading fails, report the failure rather than silently treating a configured plugin as disabled; distinguish deferred registration during config parsing from rejected loading.
- Read [README.md](README.md) for build commands, Lua integration, and reload lifecycle constraints.
