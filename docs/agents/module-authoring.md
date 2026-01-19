# Module Authoring Rules

1. **Declare modules, don't import paths**
   - Each module file exports the configuration snippet under its desired key in `flake.modules.*`.
   - Consumers reference `config.flake.modules.<namespace>.<name>` by attribute path only.
2. **Keep NixOS and Home Manager siblings together when related**
   - Co-locate system-level and user-level logic in the same file by populating both `flake.modules.nixos.*` and `flake.modules.homeManager.*` entries.
3. **Derive host builds from module lists**
   - Host definitions only list module keys; the loader handles expansion, Home Manager wiring, and installer-specific extras.
4. **Use metadata instead of literals**
   - Pull shared strings, secrets, and UI options from `config.flake.meta` so replacements propagate automatically.
5. **Route dependencies through the tree**
   - When a feature depends on another, import it using `config.flake.modules` (e.g. `imports = [ config.flake.modules.nixos.<other> ];`) rather than relative file paths.
6. **Expose automation through perSystem**
   - Checks, formatters, dev shells, and packages should be defined under `perSystem` so every supported platform gets consistent tooling.
7. **Prefer data over conditionals**
   - Pass environment-specific values (host role, install mode, usernames) in `specialArgs` to keep modules declarative and easily testable.
8. **Keep comments minimal**
   - Only add comments that explain "why", not "what"; remove obvious restatements.
   - Avoid section headers unless the file is complex enough to warrant them; brief inline comments for non-obvious values are acceptable.
