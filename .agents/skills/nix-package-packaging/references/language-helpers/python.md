# Python Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers
- https://raw.githubusercontent.com/nix-community/poetry2nix/master/README.md
- https://pyproject-nix.github.io/uv2nix/

## Native Builder First

- For nixpkgs packages, prefer `buildPythonPackage` and `buildPythonApplication` first.
- Use helper generators when translating lockfiles/workspaces is materially faster than hand-maintained packaging.

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| Regular library/app packaging for nixpkgs | `buildPythonPackage` / `buildPythonApplication` | none |
| Upstream uses `uv` workspace and lock translation is required | keep workspace model and generate derivations | `uv2nix` |
| Existing Poetry project where migration is not immediate | maintain current lockfile path | `poetry2nix` (with maintenance caution) |
| Bulk package onboarding/overlay generation workflows | specialized tooling as needed | `nixpkgs-pytools`, `pynixify`, `pip2nix` |

## Current Cautions

- `poetry2nix` upstream README marks the project as unmaintained and recommends considering `uv` + `uv2nix` for new projects.
- Treat legacy helper choices as migration paths rather than defaults for new packaging.

## Helper Pointers

- Preferred modern helper path: `uv2nix`.
- Existing Poetry lock workflow: `poetry2nix` (maintenance caution).
- Bulk onboarding/overlay tooling: `nixpkgs-pytools`, `pynixify`, `pip2nix`.

## Legacy Helpers (Migration Only)

- Per source wiki "Abandoned / discontinued": `pypi2nix`, `python2nix`, `nix-pip`, `mach-nix`.

## Practical Guidance

- Prefer native nixpkgs Python builders when packaging can be expressed directly.
- Prefer `uv2nix` for new lockfile-driven Python workflows.
- Re-check upstream status before adopting helper tooling for long-lived package maintenance.

## Example Implementation

```nix
{ buildPythonApplication, fetchPypi }:
buildPythonApplication rec {
  pname = "my-python-app";
  version = "1.2.3";
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
}
```

```nix
# Example Poetry workflow (legacy maintenance path)
{ pkgs }:
pkgs.poetry2nix.mkPoetryApplication {
  projectDir = ./.;
}
```

```nix
# Example uv2nix-style generated package import pattern
{ pkgs, ... }:
let
  uvPackagesGenerated = import ./uv-packages-generated.nix { inherit pkgs; };
in
uvPackagesGenerated.my-python-app
```
