# Rust Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers
- https://raw.githubusercontent.com/nix-community/naersk/master/README.md
- https://raw.githubusercontent.com/nix-community/crate2nix/master/README.md
- https://raw.githubusercontent.com/cargo2nix/cargo2nix/master/README.md
- https://raw.githubusercontent.com/ipetkov/crane/master/README.md

## Native Builder First

- Prefer `rustPlatform.buildRustPackage` for standard nixpkgs packaging.
- Use `cargoHash` for dependency source hashing (`cargoSha256` is deprecated).

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| Standard Rust package for nixpkgs | `rustPlatform.buildRustPackage` | none |
| Need composable incremental CI/lint/test pipelines without generated lock-expression files | keep Cargo-native workflow in Nix | `crane` |
| Need generated per-crate derivation graph committed in repo | generated `Cargo.nix` workflow | `crate2nix` or `cargo2nix` |
| Need simple pure-Nix lock parsing path with no IFD for Hydra-sensitive environments | minimal wrapper model | `naersk` |

## Helper Pointers

- Incremental CI-friendly workflow: `crane`.
- Generated derivation graph workflow: `crate2nix`, `cargo2nix`.
- Pure Nix minimal wrapper path: `naersk`.

## Practical Guidance

- Start with `buildRustPackage` unless there is a clear reason not to.
- Choose helper based on code-generation policy, caching model, and CI topology.
- For generated workflows, keep generated files deterministic and commit policy explicit.

## Example Implementation

```nix
{ rustPlatform, fetchFromGitHub }:
rustPlatform.buildRustPackage rec {
  pname = "my-rust-app";
  version = "1.2.3";
  src = fetchFromGitHub {
    owner = "org";
    repo = "my-rust-app";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  cargoHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
}
```

```nix
# crane example pattern
{ pkgs, craneLib }:
craneLib.buildPackage {
  src = ./.;
}
```

```bash
# crate2nix/cargo2nix generation pattern
crate2nix generate
# or
cargo2nix
```
