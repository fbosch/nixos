# PureScript Helpers

Sources:
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native-First Baseline

- Start with existing nixpkgs PureScript packaging patterns when dependency sets are small.
- Use helper workflows when package graph/tooling integration must be generated repeatedly.

## Decision Playbook

| Signal | Action |
|---|---|
| Project relies on purs-specific package graph tooling | use `purs-nix` |
| Simple project with low update frequency | package directly |
| Generated output mismatches current build tooling assumptions | keep helper for discovery, maintain final expressions manually |

## Helper

- `purs-nix` - Manage PureScript projects with Nix-native workflows. Upstream: https://github.com/purs-nix/purs-nix

## Failure Signatures and Fixes

- Signature: generated package graph fails during build tool invocation.
  - First fix: verify project metadata used for generation is current.
  - Second fix: constrain helper scope to dependency export only.
- Signature: toolchain binaries resolve in dev shell but not package build.
  - First fix: move required tools to `nativeBuildInputs`.
  - Second fix: reproduce with phase debug loop and capture first missing executable.

## Abandon Helper When

- Helper-generated graph churn dominates review cost.
- Direct expressions are smaller and more stable than generated outputs.

## Example Implementation

```nix
{ pkgs, ... }:
let
  # Example: generated purs-nix output imported as package set.
  pursPackagesGenerated = import ./purs-packages-generated.nix { inherit pkgs; };
in
pursPackagesGenerated.my-purescript-app
```
