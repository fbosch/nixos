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
flowchart LR
  flake[flake.nix]
  meta[flake.meta]
  modules[flake.modules]
  lib[flake.lib.mkHost]
  hostConfigs[flake.hostConfigs]
  presets[meta.presets]

  subgraph moduleTree[modules/]
    hosts[hosts/*]
    moduleset[other modules]
  end

  flake --> meta
  flake --> modules
  flake --> lib
  flake --> hostConfigs

  meta --> presets
  presets --> lib

  modules --> moduleTree
  hosts --> lib
  hostConfigs --> lib

  lib --> nixosConfigs[nixosConfigurations]
  lib --> darwinConfigs[darwinConfigurations]
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
flowchart LR
  preset[preset]
  mkHost[mkHost]

  subgraph inputs[inputs]
    presetModules[preset.modules]
    presetNixos[preset.nixos]
    presetHm[preset.homeManager]
    extraNixos[extraNixos]
    extraHm[extraHomeManager]
    hostImports[hostImports]
  end

  subgraph outputs[expanded lists]
    nixosModules[nixos module list]
    hmModules[home-manager module list]
  end

  preset --> presetModules
  preset --> presetNixos
  preset --> presetHm

  presetModules --> nixosModules
  presetNixos --> nixosModules
  extraNixos --> nixosModules
  hostImports --> nixosModules

  presetModules --> hmModules
  presetHm --> hmModules
  extraHm --> hmModules

  mkHost --> nixosModules
  mkHost --> hmModules
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
