# Define Home Manager Ownership Boundaries

**Status:** proposed
**Date:** 2026-08-08

## Context

This flake uses NixOS, nix-darwin, Home Manager, and a separately maintained GNU Stow checkout. Feature modules intentionally colocate system and Home Manager aspects, but ownership had drifted: Home Manager installed general packages, system modules wrote user files, and generated files appeared below Stow-linked directories.

The dotfiles checkout must remain mutable and usable on its own. Replacing it with fully declarative Home Manager configuration would remove that property without addressing the actual path and lifecycle conflicts.

## Decision

NixOS and nix-darwin own machine state and generally available packages. Home Manager owns user state, sessions, generated user files, user services, and material user program configuration. Stow owns portable, hand-maintained dotfiles.

Package installation is independent from configuration ownership. Keep related NixOS, Darwin, and Home Manager aspects colocated in feature modules, while each aspect owns only its appropriate lifecycle.

No two owners may write the same file. Home Manager avoids child files below Stow-linked directories unless the leaf is an explicitly documented, ignored generated-file handoff; `~/.config/fish/private.fish` is the supported Fish handoff. Machine SSH login authorization is system-owned; Home Manager owns SSH client configuration, user key material, and the selected user-session agent.

The Nix and dotfiles repositories may be upgraded independently. Every ownership transfer needs a documented old/new compatibility window, guarded migration behavior, tests, and a removal condition. Automated Stow activation must not use `--adopt`.

## Consequences

Existing package-only Home Manager lists move to system package destinations only after every active host has a destination. Home Manager retains packages that directly support its services, activations, generated commands, or material `programs.*` configuration.

GTK configuration and Git platform configuration require staged migrations. `rvn-srv` uses GPG SSH support, while other hosts use Home Manager `ssh-agent`. `rvn-mac` manages Remote Login and machine login keys; `kmd-mac` does not. The Darwin Podman LaunchAgent discovers and publishes `DOCKER_HOST` for the user session, while Fish derives it only when the session value is absent. The credential helper, Surge output-root, server development-package, and standalone GTK policies remain explicit implementation decisions.
