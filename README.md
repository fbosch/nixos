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
  flake[flake.nix]

  meta[flake.meta]
  modules[flake.modules]
  lib[flake.lib.mkHost]
  hostConfigs[flake.hostConfigs]

  hosts[modules/hosts/*]
  moduleTree[modules/*]

  presets[meta.presets]

  nixosConfigs[nixosConfigurations]
  darwinConfigs[darwinConfigurations]

  flake --> meta
  flake --> modules
  flake --> lib
  flake --> hostConfigs

  modules --> hosts
  modules --> moduleTree

  meta --> presets
  presets --> lib
  hostConfigs --> lib
  hosts --> lib

  lib --> nixosConfigs
  lib --> darwinConfigs
```

## Presets

| Preset            | modules                                                           | nixos       | homeManager                                            |
| ----------------- | ----------------------------------------------------------------- | ----------- | ------------------------------------------------------ |
| `desktop`         | users, fonts, security, desktop, applications, development, shell | system, vpn | dotfiles                                               |
| `server`          | users, security, development, shell                               | system, vpn | dotfiles                                               |
| `minimal`         | users, security                                                   | system      | dotfiles                                               |
| `homeManagerOnly` | -                                                                 | -           | users, dotfiles, security, secrets, development, shell |

## Preset expansion

```mermaid
flowchart TD
  preset[preset]
  mkHost[mkHost]

  presetModules[preset.modules]
  presetNixos[preset.nixos]
  presetHm[preset.homeManager]
  extraNixos[extraNixos]
  extraHm[extraHomeManager]
  hostImports[hostImports]

  nixosModules[nixos module list]
  hmModules[home-manager module list]

  preset --> presetModules
  preset --> presetNixos
  preset --> presetHm

  mkHost --> nixosModules
  mkHost --> hmModules

  presetModules --> nixosModules
  presetNixos --> nixosModules
  extraNixos --> nixosModules
  hostImports --> nixosModules

  presetModules --> hmModules
  presetHm --> hmModules
  extraHm --> hmModules
```

## Hosts

| Host | platform | preset | extra modules |
| --- | --- | --- | --- |
| `rvn-pc` | nixos | `desktop` | modules: secrets, nas, gaming, windows, virtualization<br>extraNixos: hardware/storage, hardware/fingerprint, hardware/fancontrol<br>extraHM: dotfiles, flatpaks, vicinae, custom xdg |
| `rvn-vm` | nixos | `desktop` | extraNixos: secrets, nas<br>extraHM: dotfiles, flatpaks, vicinae |
| `rvn-mac` | darwin | `homeManagerOnly` | darwin imports: security, homebrew |

## Credits

- Dendritic pattern — https://vic.github.io/dendrix/
- Inspiration — https://github.com/MrSom3body/dotfiles
- Inspiration — https://github.com/drupol/infra
- Fastfetch ANSI art — https://github.com/4DBug/nix-ansi
