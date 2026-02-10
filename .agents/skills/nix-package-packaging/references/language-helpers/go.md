# Go Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native Builder First

- Prefer `buildGoModule` for new Go packaging in nixpkgs.
- `buildGoPackage` was removed in nixpkgs 25.05; do not design new packages around it.

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| Standard Go modules project with `go.mod` | `buildGoModule` | none |
| Native route is impractical due to dependency-graph constraints | keep package build in nix, generate module graph | `gomod2nix` |
| Maintaining legacy projects that already depend on older helper formats | preserve existing workflow while migrating | `go2nix`, `dep2nix`, `vgo2nix` |

## Helper Pointers

- Primary helper for modern module workflows: `gomod2nix`.
- Legacy migration helpers: `go2nix`, `dep2nix`, `vgo2nix`.

## Practical Guidance

- For new packages, start with `buildGoModule` and only escalate if logs or workflow constraints force it.
- If using helpers, commit generated artifacts only when repository policy requires it.
- Re-check helper maintenance status before adopting a helper for new projects.

## Example Implementation

```nix
{ buildGoModule, fetchFromGitHub }:
buildGoModule rec {
  pname = "my-go-app";
  version = "1.2.3";
  src = fetchFromGitHub {
    owner = "org";
    repo = "my-go-app";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  vendorHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
}
```

```nix
let
  pkgs = import <nixpkgs> {
    overlays = [ (self: super: { buildGoApplication = super.callPackage ./builder { }; }) ];
  };
in
pkgs.buildGoApplication {
  pname = "my-go-app";
  version = "1.2.3";
  src = ./.;
  modules = ./gomod2nix.toml;
}
```
