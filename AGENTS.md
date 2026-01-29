# Dendritic Nix Agent Playbook

This repository uses a dendritic-style Nix flake layout for NixOS and Home Manager modules.

Operator note: When command-line diagnostics are needed, ask whether you should run the commands instead of instructing the user to run them. Exception: if the command needs elevated permissions (sudo), instruct the user to run it.

See the detailed guides:
- [Dendritic core concepts](docs/agents/dendritic-core.md)
- [Module authoring rules](docs/agents/module-authoring.md)
- [Dotfiles policy](docs/agents/dotfiles-policy.md)
- [SOPS secrets workflow](docs/agents/sops-secrets.md)
- [Linting rules (Statix)](docs/agents/linting-statix.md)
- [Tips and workflow](docs/agents/tips-and-workflow.md)
