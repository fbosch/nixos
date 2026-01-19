# ❄️ NixOS

This is my personal NixOS configuration.

It uses a dendritic module layout with flake-parts.

## Lint & format

```sh
nix run .#lint   # statix + deadnix
nix run .#fmt    # nixpkgs-fmt
```

## Dotfiles

My dotfiles (https://github.com/fbosch/dotfiles) are applied via a Home Manager module that runs GNU Stow.

Useful when you need the same dotfiles on non‑Nix hosts.

For reproducibility, the repository is initially pinned to a specific ref. You can switch to the default branch to iterate without rebuilding Nix every time.

## Layout

```text
modules/
  flake-parts/   host loader, overlays, meta
  hosts/         one file per machine → nixosConfigurations.<name>
  *.nix          single-purpose modules (desktop, apps, dev, shell, system)
pkgs/by-name/    local packages
```

```mermaid
flowchart TD
  root[flake.nix]
  modules[modules/]
  flakeparts[modules/flake-parts/]
  hosts[modules/hosts/]
  single[modules/*.nix]
  pkgs[pkgs/by-name/]
  configs[nixosConfigurations.<name>]

  root --> modules
  root --> pkgs
  modules --> flakeparts
  modules --> hosts
  modules --> single
  hosts --> configs
```

## Presets

```mermaid
flowchart TD
  presets[presets]

  desktop[desktop]
  server[server]
  minimal[minimal]
  homeonly[homeManagerOnly]

  modulesGroup[modules]
  nixosGroup[nixos]
  hmGroup[homeManager]

  desktopModules[users, fonts, security, desktop, applications, development, shell]
  serverModules[users, security, development, shell]
  minimalModules[users, security]
  homeModules[users, dotfiles, security, secrets, development, shell]

  desktopNixos[system, vpn]
  serverNixos[system, vpn]
  minimalNixos[system]

  desktopHm[dotfiles]
  serverHm[dotfiles]
  minimalHm[dotfiles]

  presets --> desktop
  presets --> server
  presets --> minimal
  presets --> homeonly

  desktop --> modulesGroup
  desktop --> nixosGroup
  desktop --> hmGroup

  server --> modulesGroup
  server --> nixosGroup
  server --> hmGroup

  minimal --> modulesGroup
  minimal --> nixosGroup
  minimal --> hmGroup

  homeonly --> hmGroup

  modulesGroup --> desktopModules
  modulesGroup --> serverModules
  modulesGroup --> minimalModules
  modulesGroup --> homeModules

  nixosGroup --> desktopNixos
  nixosGroup --> serverNixos
  nixosGroup --> minimalNixos

  hmGroup --> desktopHm
  hmGroup --> serverHm
  hmGroup --> minimalHm
```

## Credits

- Dendritic pattern — https://vic.github.io/dendrix/
- Inspiration — https://github.com/MrSom3body/dotfiles
- Inspiration — https://github.com/drupol/infra
- Fastfetch ANSI art — https://github.com/4DBug/nix-ansi
