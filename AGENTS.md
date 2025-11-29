# Dendritic Nix Agent Playbook

## Purpose

- Capture reusable conventions observed in a dendritic-style flake configuration (see [Dendrix documentation](https://vic.github.io/dendrix/)).
- Serve as an onboarding guide for adopting the same dendritic-style flake structure in other projects.

## Core Concepts

- **Single tree of modules**: every feature file exports under `flake.*` (for example `flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`) and nothing imports siblings directly.
- **Central loader**: hosts or images are registered under `flake.modules.nixos."hosts/<id>"` or `"iso/<id>"`; a shared loader assembles `nixosConfigurations` and wires Home Manager.
- **Global metadata**: project-wide facts (URIs, user keys, UI defaults) live under `flake.meta` and are consumed through `config.flake.meta`.
- **perSystem outputs**: packages, dev shells, checks, and CI hooks are exposed through `perSystem` to keep architecture-specific logic in one place.
- **Context via specialArgs**: helper records such as `hostConfig` carry flags (`isInstall`, host name, etc.) instead of hard-coding conditions across modules.

## Authoring Rules

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
8. **Don't configure dotfiles-managed programs**
   - User dotfiles are managed in a separate repository at `~/dotfiles` using GNU Stow
   - **NEVER configure these programs** in this NixOS flake - they are managed exclusively through dotfiles:
     - **Shell configurations**: Fish, Zsh, Bash (aliases, functions, scripts, abbreviations)
     - **Editors**: Neovim, VSCode/Cursor
     - **Terminal emulators**: Kitty, Foot, WezTerm
     - **Desktop environment**: Hyprland, Hypr-dock, Waybar, Waycorner, Rofi, SwayNC
     - **CLI tools**: Bat, Btop, fd, ripgrep, Lazygit, Gitui, Tmux, Mprocs, Vivid
     - **Theming**: GTK-3.0, GTK-4.0, Starship
     - **Other**: AGS, Vicinae, Palettum, OpenCode, nwg-look, Zeal, Astro
   - Only install packages for these programs in NixOS; leave all configuration to dotfiles
   - If unsure whether a program is dotfiles-managed, check if it has a directory in `~/dotfiles/.config/`
9. **Don't update the readme unless specifically asked to**

## Common Linting Rules (Statix)

### W20: Avoid repeated keys in attribute sets
**Problem**: Using the same attribute key multiple times in one scope.
```nix
# ❌ Wrong - repeated 'inputs' key
winapps = {
  url = "...";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-utils.follows = "dedupe_flake-utils";
  inputs.flake-compat.follows = "dedupe_flake-compat";
};

# ✅ Correct - nested under single 'inputs' key
winapps = {
  url = "...";
  inputs = {
    nixpkgs.follows = "nixpkgs";
    flake-utils.follows = "dedupe_flake-utils";
    flake-compat.follows = "dedupe_flake-compat";
  };
};
```

### Other Common Rules
- **Avoid empty let blocks**: Remove `let` if no bindings are defined
- **Avoid legacy attribute syntax**: Use `inherit` instead of repeating names
- **Prefer `lib.mkIf` over nested if expressions**: Keep conditionals readable
- **Use `mkEnableOption` for boolean options**: Standard way to create enable flags
- **Use `stdenv.hostPlatform.system` instead of `system`**: The `system` parameter is deprecated
  ```nix
  # ❌ Wrong - deprecated 'system' parameter
  { pkgs, system, ... }:
  let
    package = inputs.self.packages.${system}.foo;
  in { }
  
  # ✅ Correct - use stdenv.hostPlatform.system
  { pkgs, ... }:
  let
    package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.foo;
  in { }
  ```

## Tips

- Start with a minimal set of modules (e.g. `base`, `shell`) and validate the loader before porting complex services.
- Use attribute name conventions (`nixos.<group>`, `homeManager.<group>`) to keep the tree discoverable.
- Document host-specific quirks inside their `hostConfig` record so modules remain generic.
- Keep secrets and credentials in SOPS or similar, and surface only references through metadata.
- Run linters (`statix`, `deadnix`) before committing to catch common issues early.
