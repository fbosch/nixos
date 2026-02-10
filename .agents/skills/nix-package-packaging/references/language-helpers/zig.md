# Zig Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native Builder First

- Prefer `zig.hook` as the default nixpkgs path for Zig package builds.
- `zig.hook` handles default build/check/install phase behavior for Zig projects.

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| Standard Zig project in nixpkgs | `zig.hook` | none |
| Need lock/dependency translation from `build.zig.zon` into Nix data | keep native build but generate dependency metadata | `zon2nix` |

## Helpers (Catalog)

- `zon2nix` - Convert `build.zig.zon` dependency definitions into Nix expressions. Upstream: https://github.com/nix-community/zon2nix

## Practical Guidance

- Start with `zig.hook`; add generation tooling only when dependency metadata needs explicit Nix representation.
- Re-run helper generation when `build.zig.zon` changes.

## Example Implementation

```nix
{ stdenv, zig }:
stdenv.mkDerivation {
  pname = "my-zig-app";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ zig zig.hook ];
}
```

```nix
{ pkgs, ... }:
let
  zonDepsGenerated = import ./zon-deps-generated.nix { inherit pkgs; };
in
pkgs.callPackage ./package.nix { inherit zonDepsGenerated; }
```
