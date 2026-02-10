# Scala Helpers

Sources:
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native-First Baseline

- Prefer existing nixpkgs JVM/Scala packaging conventions first.
- Use helper tooling when SBT dependency translation is repeatedly costly.

## Decision Playbook

| Signal | Action |
|---|---|
| SBT dependency graph translation is main blocker | use `sbt-derivation` or `sbtix` |
| Project is small and dependencies are stable | package directly |
| Generated SBT wiring requires frequent manual repair | limit helper usage to dependency bootstrap only |

## Helpers

- `sbtix` - SBT-oriented Nix packaging support. Upstream: https://gitlab.com/nightkr/Sbtix
- `sbt-derivation` - Nix library for building Scala SBT projects. Upstream: https://github.com/zaninime/sbt-derivation

## Failure Signatures and Fixes

- Signature: generated expressions build but miss expected runtime artifacts.
  - First fix: verify produced JAR/classpath outputs under `$out`.
  - Second fix: adjust install logic and keep helper-generated dependency layer only.
- Signature: Java toolchain mismatch causes non-reproducible SBT behavior.
  - First fix: pin JDK/SBT versions in derivation inputs.
  - Second fix: rerun with clean build shell and phase debugging.

## Abandon Helper When

- Helper output is less stable than direct packaging over multiple updates.
- Reviewers cannot reason about generated diffs without manual normalization.

## Example Implementation

```nix
{ pkgs, ... }:
let
  # Example: generated SBT dependency layer.
  scalaPackagesGenerated = import ./sbt-packages-generated.nix { inherit pkgs; };
in
scalaPackagesGenerated.my-scala-app
```
