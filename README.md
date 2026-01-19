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
classDiagram
  class FlakeNix {
    inputs
    outputs
  }

  class Inputs {
    core: nixpkgs, flake-parts, import-tree, home-manager, nix-darwin
    pkgs: pkgs-by-name-for-flake-parts, nix-webapps
    dotfiles: dotfiles
    desktop: hyprland, hyprland-plugins, split-monitor-workspaces, hyprland-contrib, hyprlock, hypridle, hyprsunset, hyprpaper
    secrets: sops-nix
    apps: flatpaks, vicinae, winapps, ags
    boot: grub2-themes, distro-grub-themes
    dedupe: dedupe_systems, dedupe_flake-utils, dedupe_flake-compat
  }

  class Outputs {
    flake.meta
    flake.modules
    flake.lib.mkHost
    flake.hostConfigs
    nixosConfigurations
    darwinConfigurations
    packages (pkgs/by-name)
  }

  class Modules {
    flake-parts/
    hosts/
    applications/
    desktop/
    development/
    hardware/
    shell/
    system/
    users.nix
    fonts.nix
    security.nix
    dotfiles.nix
    virtualization.nix
    vpn.nix
    sops.nix
    nas.nix
    homebrew.nix
  }

  class FlakeParts {
    flake-parts.nix
    hosts.nix
    meta.nix
    mkHost.nix
    nixpkgs.nix
    dev-shell.nix
    overlays/*.nix
  }

  class Hosts {
    rvn-mac.nix
    rvn-pc.nix
    rvn-vm.nix
  }

  class ModuleTree {
    nixos/*
    homeManager/*
    darwin/*
  }

  class Meta {
    user
    dotfiles
    bitwarden
    ui
    displayManager
    presets
    versions
    unfree
  }

  class Presets {
    desktop
    server
    minimal
    homeManagerOnly
  }

  class PackagesByName {
    pkgs/by-name/
  }

  class Lib {
    lib/icon-overrides.nix
  }

  class NixosConfigurations
  class DarwinConfigurations

  FlakeNix --> Inputs
  FlakeNix --> Outputs
  FlakeNix --> Modules
  Modules --> FlakeParts
  Modules --> Hosts
  Outputs --> ModuleTree
  Outputs --> Meta
  Meta --> Presets
  Outputs --> PackagesByName
  Outputs --> Lib
  Outputs --> NixosConfigurations
  Outputs --> DarwinConfigurations
```

## Presets

| Preset            | modules                                                           | nixos       | homeManager                                            |
| ----------------- | ----------------------------------------------------------------- | ----------- | ------------------------------------------------------ |
| `desktop`         | users, fonts, security, desktop, applications, development, shell | system, vpn | dotfiles                                               |
| `server`          | users, security, development, shell                               | system, vpn | dotfiles                                               |
| `minimal`         | users, security                                                   | system      | dotfiles                                               |
| `homeManagerOnly` | -                                                                 | -           | users, dotfiles, security, secrets, development, shell |

## Credits

- Dendritic pattern — https://vic.github.io/dendrix/
- Inspiration — https://github.com/MrSom3body/dotfiles
- Inspiration — https://github.com/drupol/infra
- Fastfetch ANSI art — https://github.com/4DBug/nix-ansi
