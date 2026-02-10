---
name: nix-package-packaging
description: Package software into reproducible Nix derivations for local flakes and nixpkgs contributions. Use when creating or updating package expressions, debugging build/install/runtime failures, resolving source hash mismatches, selecting native language builders (buildGoModule, buildRustPackage, buildPythonPackage, buildNpmPackage, bundlerApp, zig.hook), or deciding when helper generators are justified.
---

# Nix Package Packaging

Package upstream software into reproducible derivations, then iterate with a strict debug loop until build and runtime behavior are correct.

## Workflow

Run this sequence in order:

1. Identify inputs and target repository.
2. Choose packaging path (native builder first).
3. Start from a minimal derivation.
4. Resolve all fixed-output hashes.
5. Debug phase-by-phase until build/install pass.
6. Validate runtime behavior and output shape.
7. Finalize metadata, tests, and contribution quality.

## Routing (Progressive Disclosure)

Use references conditionally. Do not load everything by default.

MANDATORY:
- Always read [references/packaging-foundations.md](references/packaging-foundations.md) before changing derivation structure.

Conditional:
- If any phase fails or output is incomplete, read [references/packaging-debug-loop.md](references/packaging-debug-loop.md).
- If selecting language tooling or lockfile strategy, read [references/language-helpers/index.md](references/language-helpers/index.md), then only the relevant language file.

Do NOT load:
- Do not load all `references/language-helpers/*.md` files for a single-package task.
- Do not start from helper generators when a native nixpkgs builder already fits the project lockfile/build model.

## 1) Identify Inputs

Collect:
- upstream source of truth (release archive/tag/commit)
- build system and lockfile model
- dependency surface (build vs runtime)
- expected outputs (binary/library/plugin/service)
- target context (local flake vs nixpkgs PR)

Decision heuristics before writing code:
- If upstream publishes immutable release archives, prefer them over floating branches because hash churn and review noise drop sharply.
- If a native builder can consume the existing lockfile, use it first because generated helper layers add long-term maintenance cost.
- If upstream build steps rely on ad-hoc scripts, map those scripts to standard phases early because hidden phase coupling causes fragile overrides later.
- If targeting nixpkgs, optimize for reviewer readability over local convenience because unclear overrides are frequently rejected or regress later.

## 2) Choose Packaging Path

Choose in this order:
1. Native nixpkgs language builder.
2. Helper generator only when native path is impractical.
3. `stdenv.mkDerivation` with minimal explicit overrides for unusual builds.

Use [references/language-helpers/index.md](references/language-helpers/index.md) for builder/helper decisions.

## 3) Start Minimal

Create the smallest derivation that can validate source fetch and baseline build assumptions.

Minimal means proving risk in this order:
- source is reproducible
- builder can start without custom phases
- install produces expected artifact class (bin/lib/plugin)

Only add complexity after one of those proofs fails in logs.

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

  # Add inputs only when logs prove they are needed.
}
```

## 4) Resolve Hashes

For each fetched artifact (`src`, vendored deps, lockfile exports):
- set a fake hash
- build once
- replace with reported real hash
- rebuild

Never stop after fixing only one hash when multiple fetchers are present.

## 5) Debug Phases

Use the tight loop:
- build with logs
- identify first failing phase
- reproduce in build shell
- apply one targeted fix
- rebuild

Load [references/packaging-debug-loop.md](references/packaging-debug-loop.md) when phase behavior is unclear.

## 6) Validate Runtime and Output

After successful install:
- inspect `$out` contents
- run primary executables/entrypoints
- apply wrappers or runtime path fixes only when failures demand them
- verify closure stays minimal

## 7) Finalize for Review

Before done:
- complete `meta` fields and maintainer quality expected by target repo
- add at least one executable smoke check when full upstream tests are impractical
- keep overrides narrow, and document why each non-default flag exists
- re-check helper choice: if many overrides are accumulating, switch back to native builder or a better-fitting helper
- align structure and naming with target repository conventions before submission

## NEVER Do This

- NEVER override `phases` wholesale when hooks (`pre*`/`post*`) can solve the issue, because you can silently drop fixup behavior and ship broken outputs.
- NEVER override a phase without preserving `runHook pre<Phase>` and `runHook post<Phase>`, because downstream hooks and setup hooks stop executing.
- NEVER pick helper generators first when a native nixpkgs builder already fits, because generated layers increase diff noise and long-term drift risk.
- NEVER leave fake hashes in committed derivations, because CI/review builds fail immediately and invalidate reproducibility.
- NEVER add wrappers/patchelf changes before reproducing a concrete runtime failure, because premature patching hides root causes and bloats closures.
- NEVER assume third-party helper maintenance status from memory, because stale assumptions lead to dead-end tooling choices.

## Reference Map

- Foundations and stdenv guardrails: [references/packaging-foundations.md](references/packaging-foundations.md)
- Phase debugging and failure taxonomy: [references/packaging-debug-loop.md](references/packaging-debug-loop.md)
- Native builder vs helper routing: [references/language-helpers/index.md](references/language-helpers/index.md)
- Ecosystem-specific helper notes: `references/language-helpers/*.md`
