# OCaml Helpers

Sources:
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native-First Baseline

- Start from existing nixpkgs OCaml packaging patterns.
- Use helper generation when opam metadata translation is repeated and error-prone.

## Decision Playbook

| Signal | Action |
|---|---|
| opam dependency metadata is the primary input | use `opam2nix` |
| Package has minimal dependencies and stable updates | package directly using current OCaml conventions |
| Generated graph conflicts with existing package-set structure | keep only generated seed data, then maintain expressions directly |

## Helper

- `opam2nix` - Generate Nix expressions from opam packages. Upstream: https://github.com/timbertson/opam2nix

## Failure Signatures and Fixes

- Signature: generated dependency graph pulls incompatible versions.
  - First fix: constrain versions in source metadata and regenerate.
  - Second fix: pin critical dependencies manually in package expression.
- Signature: generated expressions do not align with nixpkgs OCaml call conventions.
  - First fix: normalize callPackage boundaries.
  - Second fix: maintain package directly without full regeneration.

## Abandon Helper When

- Regeneration repeatedly produces non-reviewable diffs.
- Manual package maintenance is lower effort than keeping generator output in sync.

## Example Implementation

```nix
{ pkgs, ... }:
let
  # Example: generated from opam metadata.
  ocamlPackagesGenerated = import ./opam-packages-generated.nix { inherit pkgs; };
in
ocamlPackagesGenerated.my-ocaml-package
```
