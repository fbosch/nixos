# Package Updates

- Keep `scripts/update-local-package.sh` package-agnostic.
- Add `passthru.updateScript` only when a package needs custom update discovery or arguments. Use `nix-update-script` with `--flake` in `extraArgs` so it works through `just update-local-package`.
