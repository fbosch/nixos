# AGENTS

Nix derivation for the `monoarch-refined` Plymouth theme with a NixOS logo override.

## Landmines

- Keep logo resize to `128x128` in `buildPhase`; upstream theme layout expects that size.
- Keep boot-mode compatibility patch in `monoarch-refined.script` for `boot`, `boot-up`, and `startup`; Plymouth mode names vary by version.
- Keep no-op message callbacks appended in `installPhase`; removing them re-enables console-style scrolling text on splash.
- Keep `.plymouth` path rewrite from `/usr/share/...` to `$out/share/...`; absolute FHS paths break inside Nix store outputs.

## Commands

- Preview current theme manually: `plymouthd; plymouth --show-splash; sleep 5; plymouth --quit`

## References

- ArchWiki Plymouth: https://wiki.archlinux.org/title/Plymouth
- Upstream theme: https://github.com/iam-vasanth/monoarch-refined
