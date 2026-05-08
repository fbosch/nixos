# Colocate Rvn-pc Host Modules Under Platform Namespace

**Status:** accepted
**Date:** 2026-04-01

## Context

The `rvn-pc` host configuration evolved from a `machine/`-oriented structure that mixed generated hardware concerns with hand-maintained host behavior. This made ownership boundaries unclear and increased friction when applying dendritic conventions. We also wanted to keep host-specific details colocated without over-fragmenting into too many tiny modules.

## Decision

Adopt a colocated host layout under `modules/hosts/rvn-pc/`, with clear host leaves (`boot`, `hardware`, `storage`, `home`) and a modular `platform/` namespace for system/networking/services/systemd concerns that all define `hosts/rvn-pc/platform`. Remove dependence on `machine/configuration.nix` and move retained hardware scan content into `hosts/rvn-pc/hardware`. Keep imports resolved through host namespaces so module identity matches import paths.

## Alternatives Considered

Keep the old `machine/` structure and only patch paths as needed; this was rejected because it preserved ambiguous ownership and onboarding artifacts as permanent structure. Collapse all host concerns into one monolithic host file; this was rejected because it reduces navigability and blurs concern boundaries. Split every concern into unique top-level host modules; this was rejected as too granular for this host and harder to maintain.

## Consequences

Host-specific behavior is now easier to discover, reason about, and evolve in one colocated subtree while still keeping modular separation by concern. Import naming and file layout are aligned, reducing cognitive overhead and evaluation surprises. Follow-on work includes applying the same pattern to other hosts and documenting lightweight naming conventions for `platform/*` leaves.
