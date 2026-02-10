# Haskell Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native Builder First

- Haskell package sets use `haskellPackages.mkDerivation` as the core builder model.
- Generated expressions should be consumed via `haskellPackages.callPackage`.

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| Standard package in nixpkgs Haskell set | native `haskellPackages` flow | none |
| Need to generate expression from Cabal metadata | generate and then call via haskellPackages | `cabal2nix` |
| Complex dependency override workflow during development | native flow plus targeted overrides | `haskell-overridez` |
| Incremental build-oriented workflows outside nixpkgs norms | specialized development model | `snack` |

## Helpers (Catalog)

- `cabal2nix` - Generate Nix build instructions from Cabal metadata. Upstream: https://github.com/NixOS/cabal2nix
- `haskell-overridez` - Simplify dependency override workflows in Haskell development. Upstream: https://github.com/adetokunbo/haskell-overridez
- `snack` - Nix-based incremental build tooling for Haskell projects. Upstream: https://github.com/nmattia/snack

## Practical Guidance

- Start with native `haskellPackages` conventions and only add helpers for clear workflow gains.
- Keep generated expressions and overrides easy to audit.

## Example Implementation

```nix
{ pkgs }:
pkgs.haskellPackages.callPackage ./my-haskell-lib.nix { }
```

```bash
# Generate once from Cabal metadata, then maintain in-tree.
cabal2nix . > my-haskell-lib.nix
```
