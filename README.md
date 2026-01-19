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

<details>
<summary><code>desktop</code></summary>

| Group        | Entries                                                           |
| ------------ | ----------------------------------------------------------------- |
| Modules      | users, fonts, security, desktop, applications, development, shell |
| NixOS        | system, vpn                                                       |
| Home Manager | dotfiles                                                          |

</details>

<details>
<summary><code>server</code></summary>

| Group        | Entries                             |
| ------------ | ----------------------------------- |
| Modules      | users, security, development, shell |
| NixOS        | system, vpn                         |
| Home Manager | dotfiles                            |

</details>

<details>
<summary><code>homeManagerOnly</code></summary>

| Group        | Entries                                                |
| ------------ | ------------------------------------------------------ |
| Home Manager | users, dotfiles, security, development, shell |

</details>

## Credits

- Dendritic pattern — https://vic.github.io/dendrix/
- Inspiration — https://github.com/MrSom3body/dotfiles
- Inspiration — https://github.com/drupol/infra
- Fastfetch ANSI art — https://github.com/4DBug/nix-ansi
