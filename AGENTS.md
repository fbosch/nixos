# Dendritic Nix Agent Playbook

This repository uses a dendritic-style Nix flake layout for NixOS and Home Manager modules.

Operator note: When command-line diagnostics are needed, ask whether you should run the commands instead of instructing the user to run them. Exception: if the command needs elevated permissions (sudo), instruct the user to run it.

Operator note: Do not run `sops` commands directly; they break the TUI. Instruct the user to run them.

## Nix Linting Hygiene

- Avoid repeated top-level keys in a single attrset (Statix W20), especially `sops.*`.
- Prefer grouping related values under one key, for example `sops = { secrets.<name> = ...; templates.<name> = ...; };`.

## Library Helpers

- Reusable helper functions live in `lib/`.
- `config.flake.lib.iconOverrides`: icon theme override utilities from `lib/icon-overrides.nix`.
- `config.flake.lib.resolve`: resolve NixOS module paths from string names.
- `config.flake.lib.resolveHm`: resolve Home Manager module paths from string names.
- `config.flake.lib.resolveDarwin`: resolve Darwin module paths from string names.
- `config.flake.lib.sopsHelpers`: SOPS helper set with `rootOnly`, `wheelReadable`, `worldReadable`, `mkSecrets`, `mkSecretsWithOpts`, and `mkSecret`.

## Container Services Policy

**IMPORTANT**: All container services MUST use Podman Quadlet (systemd container units), not custom build services or docker-compose.

- Use `environment.etc."containers/systemd/*.container"` for container definitions
- Reference pre-built images from registries (Docker Hub, ghcr.io, etc.) when they exist
- Follow the patterns in `modules/services/containers/komodo.nix` and `modules/services/containers/pihole.nix`
- Do NOT create custom systemd build services
- If upstream does not publish images, it is acceptable to ship a Nix-provided build helper command (not a systemd unit) that builds images from the upstream Dockerfiles

## Port Allocation

**IMPORTANT**: When adding new services that expose ports, always validate against existing port assignments to avoid collisions.

Check for conflicts by searching the codebase for existing port usage before assigning a new port:
```bash
rg "port = [0-9]+" --type nix
rg "listen.*:[0-9]+" --type nix
```

Port map reference:
- [Service ports](docs/agents/service-ports.md)

See the detailed guides:
- [Dendritic core concepts](docs/agents/dendritic-core.md)
- [Module authoring rules](docs/agents/module-authoring.md)
- [Dotfiles policy](docs/agents/dotfiles-policy.md)
- [SOPS secrets workflow](docs/agents/sops-secrets.md)
- [Linting rules (Statix)](docs/agents/linting-statix.md)
- [Tips and workflow](docs/agents/tips-and-workflow.md)
- [Service ports](docs/agents/service-ports.md)
