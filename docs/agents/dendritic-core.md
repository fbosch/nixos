# Dendritic Core Concepts

- **Single tree of modules**: Every feature file exports under `flake.*` (e.g. `flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`); nothing imports siblings directly.
- **Host declarations**: Each `modules/hosts/<id>/default.nix` contributes a `hosts.<id>` record with `metadata` and `modules`. Hosts list named aspects in `modules`; the collector resolves the NixOS or Darwin aspect and automatically adds any matching Home Manager aspect through `home-manager.sharedModules`.
- **Global metadata**: Project-wide facts (URIs, user keys, UI defaults) live under `flake.meta` and are consumed through `config.flake.meta`.
- **perSystem outputs**: Packages, dev shells, checks, and CI hooks are exposed through `perSystem`. Feature-specific nix-unit tests are contributed by their owning module; central test files are reserved for pure helpers and cross-feature invariants.
- **Context via specialArgs**: The collector passes `hostMeta` and `hostKey` to NixOS/Darwin and Home Manager modules. `hostMeta` is the static metadata record; `hostKey` is the declaration key.
