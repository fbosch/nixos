# Dendritic Nix Agent Playbook

## Purpose

- Capture reusable conventions observed in a dendritic-style flake configuration (see [Dendrix documentation](https://vic.github.io/dendrix/)).
- Serve as an onboarding guide for adopting the same dendritic-style flake structure in other projects.

## Core Concepts

- **Single tree of modules**: every feature file exports under `flake.*` (for example `flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`) and nothing imports siblings directly.
- **Central loader**: hosts or images are registered under `flake.modules.nixos."hosts/<id>"` or `"iso/<id>"`; a shared loader assembles `nixosConfigurations` and wires Home Manager.
- **Global metadata**: project-wide facts (URIs, user keys, UI defaults) live under `flake.meta` and are consumed through `config.flake.meta`.
- **perSystem outputs**: packages, dev shells, checks, and CI hooks are exposed through `perSystem` to keep architecture-specific logic in one place.
- **Context via specialArgs**: helper records such as `hostConfig` carry flags (`isInstall`, host name, etc.) instead of hard-coding conditions across modules.

## Authoring Rules

1. **Declare modules, don’t import paths**
   - Each module file exports the configuration snippet under its desired key in `flake.modules.*`.
   - Consumers reference `config.flake.modules.<namespace>.<name>` by attribute path only.
2. **Keep NixOS and Home Manager siblings together when related**
   - Co-locate system-level and user-level logic in the same file by populating both `flake.modules.nixos.*` and `flake.modules.homeManager.*` entries.
3. **Derive host builds from module lists**
   - Host definitions only list module keys; the loader handles expansion, Home Manager wiring, and installer-specific extras.
4. **Use metadata instead of literals**
   - Pull shared strings, secrets, and UI options from `config.flake.meta` so replacements propagate automatically.
5. **Route dependencies through the tree**
   - When a feature depends on another, import it using `config.flake.modules` (e.g. `imports = [ config.flake.modules.nixos.<other> ];`) rather than relative file paths.
6. **Expose automation through perSystem**
   - Checks, formatters, dev shells, and packages should be defined under `perSystem` so every supported platform gets consistent tooling.
7. **Prefer data over conditionals**
   - Pass environment-specific values (host role, install mode, usernames) in `specialArgs` to keep modules declarative and easily testable.

## Migration Checklist

- [ ] Mirror the `flake.nix` pattern: delegate outputs to `flake-parts.lib.mkFlake … (inputs.import-tree ./modules)`.
- [ ] Recreate the `modules/flake` helpers (hosts loader, overlays, checks, treefmt, shell, systems, images) and adjust inputs as needed.
- [ ] Populate `flake.meta` with project-wide appearance, program defaults, and user credentials; audit modules to read from metadata instead of literals.
- [ ] Port feature modules by rewriting them to export under the dendritic keys and consume dependencies via `config.flake.modules`.
- [ ] Define host or ISO entries that simply list module names and rely on the loader for assembly.
- [ ] Ensure any packages, dev shells, or CI hooks are moved under `perSystem`.

## Tips

- Start with a minimal set of modules (e.g. `base`, `shell`) and validate the loader before porting complex services.
- Use attribute name conventions (`nixos.<group>`, `homeManager.<group>`) to keep the tree discoverable.
- Document host-specific quirks inside their `hostConfig` record so modules remain generic.
- Keep secrets and credentials in SOPS or similar, and surface only references through metadata.
