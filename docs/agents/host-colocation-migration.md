# Host Colocation Migration Guide

This guide describes how to migrate a host from `machines/<machine>/` files to colocated modules under `modules/hosts/<host>/`.

## Why migrate

- Keeps host-specific behavior next to the host aggregator module.
- Reduces ambiguity between shared feature modules and machine-local details.
- Makes host refactors safer by aligning module keys, paths, and imports.

## Target layout

Use a host-local subtree like:

```text
modules/hosts/<host>/
  default.nix
  boot.nix
  hardware.nix
  storage.nix
  home.nix
  platform/
    system.nix
    networking.nix
    services.nix
    systemd.nix
```

Notes:
- `hardware.nix` should keep generated hardware-scan content.
- `platform/*` files can all define the same module key (`hosts/<host>/platform`) and merge by option semantics.

## Module key alignment rule

Keep names aligned across all three layers:

- File location: `modules/hosts/<host>/platform/services.nix`
- Module key: `flake.modules.nixos."hosts/<host>/platform"`
- Import in host aggregator: `"hosts/<host>/platform"`

If these drift, resolution and maintenance become error-prone.

## Migration checklist

1. Create host-local files under `modules/hosts/<host>/` (and `platform/` if used).
2. Move content from `machines/<machine>/configuration.nix` into host leaves (`boot`, `platform`, `home`, `storage`) based on concern boundaries.
3. Move generated hardware scan content into `modules/hosts/<host>/hardware.nix`.
4. Update module keys to `hosts/<host>/...` and keep import names aligned.
5. Update `modules/hosts/<host>/default.nix` imports to host-local modules.
6. Remove obsolete `machines/<machine>/` files and empty directories.
7. Stage new files before evaluation: `git add -A modules/hosts/<host>`.
8. Run eval checks (below).

## Validation

Use focused eval commands after each migration step:

```bash
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath --raw
nix eval .#nixosConfigurations.<host>.config.fileSystems --json
```

If evaluation fails with missing module attributes for newly created files, ensure they are tracked by git (`git add`) before rebuilding.

## Split guidance

- Prefer a few meaningful leaves over many micro-modules.
- Split by concern boundaries (`boot`, `hardware`, `storage`, `home`, `platform`) rather than by every option namespace.
- Only create additional leaves when they clearly improve ownership or reuse.

## Related decision

For the concrete `rvn-pc` migration this guide is based on, see `docs/decisions/0003-colocate-rvn-pc-host-modules-under-platform-namespace.md`.
