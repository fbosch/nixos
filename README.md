# NixOS Configuration

Dendritic-style flake configuration using [import-tree](https://github.com/vic/import-tree) and [flake-parts](https://flake.parts) for automatic module discovery.

## Architecture

```
flake.nix                    # Entry point ? delegates to import-tree
??? modules/
?   ??? flake-parts/        # Infrastructure (host loader, overlays, meta)
?   ??? hosts/              # Per-machine definitions (? nixosConfigurations)
?   ??? applications/       # Browser, productivity, gaming apps
?   ??? desktop/            # Hyprland, GNOME, audio, theming
?   ??? development/        # Languages, editors, AI tools
?   ??? shell/              # Fish, bash, CLI utilities
?   ??? system/             # Core system config
?   ??? users/fbb/          # User-specific NixOS + Home Manager
?   ??? *.nix               # Single-purpose modules
??? pkgs/by-name/           # Custom packages
```

## Module System

Each file exports under `flake.modules.nixos.*` or `flake.modules.homeManager.*`.
No direct imports between modules.

Host definitions list module names; the loader in `modules/flake-parts/hosts.nix` assembles configurations and wires Home Manager automatically.

## Dotfiles Integration

The `dotfiles.nix` module clones [fbosch/dotfiles](https://github.com/fbosch/dotfiles) and applies it via GNU Stow:

```nix
# modules/dotfiles.nix
home.activation.stowDotFiles = ...
  stow --adopt --restow -t "$HOME" .
```

