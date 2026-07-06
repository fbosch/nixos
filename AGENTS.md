# Dendritic Nix Agent Playbook

This repository uses a dendritic-style Nix flake layout for NixOS and Home Manager modules.

When command-line diagnostics are needed, ask whether you should run the commands instead of instructing the user to run them. Exception: if the command needs elevated permissions (sudo), instruct the user to run it.

Before running or instructing diagnostic commands, check which machine the agent is currently on by running `hostname`. Run local commands directly if already on the target host; use SSH only if on a different machine.

Do not run `sops` commands directly; they break the TUI. Instruct the user to run them.

## Network Context

- This environment is behind CGNAT.
- Do not assume direct public inbound reachability by default; prioritize LAN/Tailscale/internal exposure in security assessments unless explicit port forwarding or reverse tunnels are configured.

## Nix Linting Hygiene

- Avoid repeated top-level keys in a single attrset (Statix W20), especially `sops.*`.
- Prefer grouping related values under one key, for example `sops = { secrets.<name> = ...; templates.<name> = ...; };`.

## Library Helpers

- Reusable helper functions live in `lib/`.
- `config.flake.lib.iconOverrides`: icon theme override utilities from `lib/icon-overrides.nix`.
- `config.flake.lib.resolve`: resolve NixOS module paths from string names.
- `config.flake.lib.resolveHm`: resolve Home Manager module paths from string names.
- `config.flake.lib.resolveDarwin`: resolve Darwin module paths from string names.
- `config.flake.lib.lazyApp`: wrap rarely used direct package entries for on-demand realization.
- `config.flake.lib.sopsHelpers`: SOPS helper set with `rootOnly`, `wheelReadable`, `worldReadable`, `mkSecrets`, `mkSecretsWithOpts`, and `mkSecret`.

## Lazy Packages

- Use `config.flake.lib.lazyApp` only for rarely used direct entries in `environment.systemPackages` or `home.packages`.
- Do not lazify services, libraries, activation-script inputs, desktop/session infrastructure, auth/security tools, or module `package` options.
- See [ADR 0013](docs/adr/0013-use-lazy-apps-for-rarely-used-packages.md) for tradeoffs and examples.

## Host Machine Metadata

- Host machine details are defined in each host module under `hostMeta` and exported via `flake.meta.hosts`.
- Primary location pattern: `modules/hosts/**`.
- Use `hostname` to identify the current machine, then find the matching record in `flake.meta.hosts` by `name`.
- Treat `hostMeta` as the source of static intent (model/fleet metadata, addressing, role-oriented fields).
- Treat runtime facts (current firmware, live microcode revision, active peripherals, temperatures, uptime) as diagnostics to check on-host, not static metadata.

## Container Services Policy

**IMPORTANT**: All container services MUST use Podman Quadlet (systemd container units), not custom build services or docker-compose.

- Use `environment.etc."containers/systemd/*.container"` for container definitions
- Reference pre-built images from registries (Docker Hub, ghcr.io, etc.) when they exist
- Do NOT create custom systemd build services; if upstream has no images, ship a build helper command instead
- Declare ports in `services.exposedPorts` AND open them with `networking.firewall.*` in the same module — keep firewall rules colocated with the service that needs them
- Use native Quadlet fields for resource limits (`Memory=`, `PidsLimit=`, `CPUQuota=`), not `PodmanArgs=`

See the full authoring guide: [Container module authoring](docs/agents/container-modules.md)

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
- [Firejail profile guidance](docs/agents/firejail.md)
- [Linting rules (Statix)](docs/agents/linting-statix.md)
- [Tips and workflow](docs/agents/tips-and-workflow.md)
- [Service ports](docs/agents/service-ports.md)


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
