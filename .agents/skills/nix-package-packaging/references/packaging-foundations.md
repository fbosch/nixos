# Nix Packaging Foundations

Sources:
- https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/README.md
- https://nixos.org/nixpkgs/manual/#sec-stdenv-phases
- https://nixos.org/nixpkgs/manual/#chap-language-support

Use this reference for durable packaging principles and contribution-safe defaults.

## Canonical Entry Points

- Quick-start guidance for adding packages now lives in `pkgs/README.md` (not in the old manual quick-start section).
- Use the language-support chapter to select native builders before external helpers.
- Use stdenv phase documentation for phase behavior and hook semantics.

## Derivation Contract

A package derivation should define:
- identity (`pname`, `version`)
- deterministic source acquisition (`src` + fixed hash)
- dependency/toolchain model
- transformation to a valid `$out`

Treat derivations as reproducible build contracts, not ad-hoc shell scripts.

## Source Strategy

Prefer deterministic and reviewable inputs:
- release archives/tags/commits
- fixed hashes for every fetcher
- minimal patching surface

Prefer fetchers that match upstream release shape and keep custom glue low.

## Dependency Semantics

Separate roles clearly:
- `nativeBuildInputs`: build-time tools on the build platform
- `buildInputs`: runtime/linked dependencies for target artifacts

Add dependencies from evidence in logs, not speculation.

## Native Builder First

Prefer this order:
1. native nixpkgs language builder/hook
2. helper generator only when native route is impractical
3. raw `stdenv.mkDerivation` with explicit overrides

This usually improves maintainability, reviewability, and long-term compatibility.

## Phase Model and Override Safety

stdenv builds are phase-based. Default phases are usually correct.

Rules:
- Prefer `pre*`/`post*` hooks over replacing full phase definitions.
- If overriding a phase, preserve hook behavior (`runHook pre<Phase>` and `runHook post<Phase>`).
- Avoid setting the `phases` variable directly unless unavoidable; it is easy to skip critical defaults.

Common problems from unsafe overrides:
- missing fixup behavior
- missing shebang patching
- brittle install logic

## Output Model

A package is not done when it only builds:
- expected files exist under `$out`
- primary executables/libraries run successfully
- wrappers/path fixes are only added when justified by runtime failures

## Reproducibility Rules

Always ensure:
- all fixed-output hashes are correct
- builds do not depend on host-local state
- outputs are deterministic across rebuilds

When convenience conflicts with reproducibility, choose reproducibility.

## Local Flake vs nixpkgs Contribution

Use stricter standards for nixpkgs:
- follow current package layout conventions
- provide complete `meta` and maintainer data
- keep non-obvious overrides justified with comments

For local flakes, optimize for your maintenance burden but keep derivations deterministic.

## Minimal Skeleton

```nix
{ stdenv
, fetchFromGitHub
, ...
}:

stdenv.mkDerivation rec {
  pname = "example";
  version = "1.2.3";

  src = fetchFromGitHub {
    owner = "org";
    repo = "example";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Add nativeBuildInputs/buildInputs only when logs require them.
}
```

Start minimal, then iterate via the debug-loop reference.
