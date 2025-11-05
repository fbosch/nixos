# ❄️ NixOS

This is my personal nix configuration repository.

It contains configurations for my machines and follows the dendritic pattern for modularity.

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

My dotfiles (https://github.com/fbosch/dotfiles) are applied via a Home Manager module that runs stow.

This is useful when you need the same dotfiles on non‑nix hosts and for tinkering with configs.

Still made reproducible by initially cloning a specific ref but can then be switched to master and modified without rebuiling.

## Credits

- Dendritic pattern — https://vic.github.io/dendrix/

### Inspiration

- https://github.com/MrSom3body/dotfiles
- https://github.com/drupol/infra
