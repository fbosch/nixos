# Packaging Debug Loop

Sources:
- https://nixos.wiki/wiki/Packaging/Tutorial
- https://nixos.wiki/wiki/Create_and_debug_nix_packages
- https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/README.md
- https://nixos.org/nixpkgs/manual/#sec-stdenv-phases

`Packaging/Tutorial` is marked outdated; prefer `Create_and_debug_nix_packages` for current guidance.
For package-contribution quick start, use `pkgs/README.md`.
Keep the loop below as the operational baseline, adapted to modern `nix build` workflows.

## Fast Loop

1. Classify package category (language/build system/runtime).
2. Find a close package example in nixpkgs and copy structure.
3. Build unchanged once to establish baseline behavior.
4. Update source URL/rev and hashes.
5. Debug per phase in shell: unpack, patch, configure, build, install.
6. Fix one failure category at a time (deps, patches, paths, phase args).
7. Re-enter shell and re-run until the current phase passes.
8. Validate install output tree and completeness.
9. Run resulting binaries to catch runtime issues.
10. Add final metadata and cleanup.

## Commands

- Preferred (modern): `nix build .#<pkg> --print-build-logs`
- Preferred (modern shell): `nix develop .#<devShell>`
- Legacy fallback build: `nix-build -A <pkgAttr>`
- Legacy fallback shell: `nix-shell '<nixpkgs>' -A <pkgAttr>`
- Manually run phases in shell: `unpackPhase`, `patchPhase`, `configurePhase`, `buildPhase`, `installPhase`
- For interactive failure breakpoints, add `breakpointHook` to `nativeBuildInputs` and rebuild.

If a phase variable is shell code, run:

```bash
eval "$configurePhase"
```

## Failure Categories

Map failures to fix categories quickly:

- Missing headers/libs/tools -> add dependency inputs
- Wrong source layout -> `sourceRoot` or `cd` into subdir before configure
- Build system mismatch -> set proper configure/build toolchain
- Missing shebang rewrites -> run `patchShebangs`
- Empty or wrong install output -> fix `installPhase` and inspect `$out`
- Runtime library lookup errors -> patch RPATH/wrap binaries as needed
- Broken custom phase override -> restore `runHook pre<Phase>` / `runHook post<Phase>` and avoid overriding `phases` wholesale

## Practical Heuristics

- Prefer existing nixpkgs patterns over inventing new phase logic.
- Keep changes minimal between rebuilds to isolate cause and effect.
- Fix build reproducibility first, style cleanup second.
- Record why each override exists.
- Prefer hook-based edits (`pre*`/`post*`) before replacing full phase definitions.

## Done Criteria

Treat package as done when all are true:

- Builds without manual intervention.
- Installs expected files under `$out`.
- Primary executable/library works at runtime.
- Hashes are correct and reproducible.
- Metadata is complete enough for target repository policy.
