## NixOS

A compact, fast-to-navigate NixOS + Home Manager setup built around a single tree of modules and a central loader.

### Quick start

```bash
# Switch this machine to host <name>
sudo nixos-rebuild switch --flake .#<name>

# Example
sudo nixos-rebuild switch --flake .#rvn-vm
```

### Layout

- **modules/**: NixOS and Home Manager feature modules
  - **flake-parts/**: host loader, nixpkgs/overlays, project metadata
  - **hosts/**: one file per machine (becomes `nixosConfigurations.<name>`)
  - other `*.nix`: single-purpose modules (desktop, apps, dev tools, security, etc.)
- **pkgs/by-name/**: custom packages

### Dendritic pattern (with flake-parts)

- **Single module tree**: each file exports under `flake.modules.nixos.*` or `flake.modules.homeManager.*`.
- **Central loader**: `modules/flake-parts/hosts.nix` assembles `nixosConfigurations` and wires Home Manager.
- **Global metadata**: shared facts live under `flake.meta` and are read as `config.flake.meta`.
- **perSystem tooling**: exposes `.#lint`, `.#fmt`, dev shells, and checks uniformly across platforms.

### Lint and format

```bash
nix run .#lint   # statix + deadnix
nix run .#fmt    # nixpkgs-fmt
```

### Dotfiles integration

Home Manager module applies external dotfiles via stow for portability.

### Resources & inspiration

- Dendritic pattern: `https://vic.github.io/dendrix/`
- Inspiration: `https://github.com/MrSom3body/dotfiles`
- Inspiration: `https://github.com/drupol/infra`

