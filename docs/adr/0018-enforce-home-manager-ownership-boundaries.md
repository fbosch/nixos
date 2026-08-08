# Enforce Home Manager Ownership Boundaries

**Status:** accepted
**Date:** 2026-08-08

## Context

The flake combines NixOS, nix-darwin, Home Manager, and mutable GNU Stow dotfiles. Package and file ownership had drifted across those layers, creating duplicate package closures, conflicting paths, and unclear service lifecycles. The migration proposed in ADR 0017 is now implemented and activated.

## Decision

NixOS and nix-darwin own machine state and generally available packages. Home Manager owns user services, generated user files, session state, and packages required directly by those behaviors. Stow owns portable, hand-maintained dotfiles, and automated activation must not use `stow --adopt`. Static checks enforce the remaining Home Manager package-owner allowlist and known path boundaries.

## Alternatives Considered

Moving all dotfiles into Home Manager was rejected because the Stow checkout must remain mutable and independently usable. Keeping general packages in Home Manager was rejected because it duplicates system-owned closures and obscures host package availability. Letting system modules write user configuration was rejected because it mixes machine and user lifecycles.

## Consequences

Package availability is defined by each host's system profile, while Home Manager package ownership stays limited to concrete user lifecycle dependencies. Ownership transfers require an explicit destination and validation before the old owner is removed. Some features remain split across system and user aspects, but each aspect has a narrower contract and no two owners may write the same path.
