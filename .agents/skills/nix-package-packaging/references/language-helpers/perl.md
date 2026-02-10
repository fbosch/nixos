# Perl Helpers

Sources:
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native-First Baseline

- Prefer existing nixpkgs Perl packaging infrastructure for straightforward modules.
- Use helper generation when CPAN dependency translation is large or frequently changing.

## Decision Playbook

| Signal | Action |
|---|---|
| Many CPAN dependencies and frequent lock/metadata changes | use `cpan2nix` |
| Small stable dependency set | package directly in existing Perl package-set style |
| Generated dependency set drifts from maintained nixpkgs Perl packages | keep direct packaging for critical dependencies |

## Helper

- `cpan2nix` - Generate Nix expressions for CPAN-based Perl dependencies. Upstream: https://gitee.com/volth/cpan2nix/

## Failure Signatures and Fixes

- Signature: generated expressions include unexpected CPAN transitive versions.
  - First fix: regenerate with cleaned metadata inputs.
  - Second fix: pin sensitive deps manually.
- Signature: build succeeds but runtime module resolution fails.
  - First fix: verify module install paths in `$out`.
  - Second fix: align package graph with nixpkgs Perl conventions.

## Abandon Helper When

- Runtime correctness requires frequent manual post-generation edits.
- Dependency graph is stable enough for direct maintenance.

## Example Implementation

```bash
# Generate CPAN dependency expressions.
cpan2nix --module Some::Module > cpan-packages-generated.nix
```

```nix
{ pkgs, ... }:
pkgs.callPackage ./cpan-packages-generated.nix { }
```
