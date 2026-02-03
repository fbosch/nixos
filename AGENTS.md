# Dendritic Nix Agent Playbook

This repository uses a dendritic-style Nix flake layout for NixOS and Home Manager modules.

Operator note: When command-line diagnostics are needed, ask whether you should run the commands instead of instructing the user to run them. Exception: if the command needs elevated permissions (sudo), instruct the user to run it.

## Container Services Policy

**IMPORTANT**: All container services MUST use Podman Quadlet (systemd container units), not custom build services or docker-compose.

- Use `environment.etc."containers/systemd/*.container"` for container definitions
- Reference pre-built images from registries (Docker Hub, ghcr.io, etc.) when they exist
- Follow the patterns in `modules/services/containers/komodo.nix` and `modules/services/containers/pihole.nix`
- Do NOT create custom systemd build services
- If upstream does not publish images, it is acceptable to ship a Nix-provided build helper command (not a systemd unit) that builds images from the upstream Dockerfiles

See the detailed guides:
- [Dendritic core concepts](docs/agents/dendritic-core.md)
- [Module authoring rules](docs/agents/module-authoring.md)
- [Dotfiles policy](docs/agents/dotfiles-policy.md)
- [SOPS secrets workflow](docs/agents/sops-secrets.md)
- [Linting rules (Statix)](docs/agents/linting-statix.md)
- [Tips and workflow](docs/agents/tips-and-workflow.md)
