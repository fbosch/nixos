# Dendritic Core Concepts

- **Single tree of modules**: Every feature file exports under `flake.*` (e.g. `flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`); nothing imports siblings directly.
- **Central loader**: Hosts or images are registered under `flake.modules.nixos."hosts/<id>"` or `"iso/<id>"`; a shared loader assembles `nixosConfigurations` and wires Home Manager.
- **Global metadata**: Project-wide facts (URIs, user keys, UI defaults) live under `flake.meta` and are consumed through `config.flake.meta`.
- **perSystem outputs**: Packages, dev shells, checks, and CI hooks are exposed through `perSystem` to keep architecture-specific logic in one place.
- **Context via specialArgs**: Helper records such as `hostConfig` carry flags (`isInstall`, host name, etc.) instead of hard-coded conditions across modules.
