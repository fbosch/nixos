# ❄️ NixOS

It follows a dendritic layout with flake-parts:
modules export under `flake.modules.nixos.*` or `flake.modules.homeManager.*`, hosts live in `modules/hosts/<name>.nix`, and a shared loader turns those into `nixosConfigurations` and wires Home Manager.

## Layout

```text
modules/
  flake-parts/   host loader, overlays, meta
  hosts/         one file per machine → nixosConfigurations.<name>
  *.nix          single-purpose modules (desktop, apps, dev, shell, system)
pkgs/by-name/    local packages
```

## Lint & Format

```sh
nix run .#lint   # statix + deadnix
nix run .#fmt    # nixpkgs-fmt
```

## Dotfiles

Applied via a Home Manager module that runs stow.
Useful when you need the same dotfiles on non‑nix hosts and for tinkering with configs without having to rebuild all of the time.
Still made reproducible by cloning a specific ref.

## Credits

Dendritic pattern — https://vic.github.io/dendrix/
Inspiration — https://github.com/MrSom3body/dotfiles
Inspiration — https://github.com/drupol/infra
