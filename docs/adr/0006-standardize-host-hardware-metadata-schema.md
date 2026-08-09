# Standardize Host System And Hardware Metadata

**Status:** accepted
**Date:** 2026-04-09

## Context

Host declarations need durable machine-readable facts for configuration assembly, cross-host access, and hardware-aware decisions. Each host keeps those values alongside its own module list, but they must share one schema so consumers do not depend on comments or ad hoc records.

Platform identity also needs to be authoritative. Separate OS and architecture fields can drift from the Nix system that builds the host, while runtime observations such as firmware revisions, temperatures, peripherals, and uptime do not belong in static configuration metadata.

## Decision

Each `modules/hosts/<name>/default.nix` contributes a `hosts.<name>` declaration with `metadata` and `modules`. The declaration key supplies `metadata.name`.

`lib/host-metadata.nix` defines the shared metadata type used by both `hosts.<name>.metadata` and `flake.meta.hosts`. `system` is the required platform identity. `lib/host-system.nix` accepts only canonical Nix system identifiers for Linux and Darwin.

`hardware` is optional. When present, it records durable vendor and model information plus optional memory, CPU, and GPU fields defined by the shared type. Runtime-observed state remains outside host metadata.

`modules/flake-parts/host-configurations.nix` uses `system` to select the NixOS or nix-darwin builder, publishes normalized metadata through `flake.meta.hosts`, and provides the record to system and Home Manager modules as `hostMeta`.

## Alternatives Considered

Centralizing host values in one global file would weaken locality and increase drift from the host declarations that use them. Keeping hardware details only in prose would make them difficult for tooling to consume. Requiring hardware metadata for every host would block incremental adoption, including virtual hosts where a durable hardware record is not currently needed.

Separate OS and architecture fields were rejected because canonical Nix `system` directly drives the platform builder and prevents those fields from diverging. Runtime observations were rejected because they are diagnostics to collect on the host, not static intent to encode in the flake.

## Consequences

Host metadata is available to configuration modules and cross-host consumers through one validated contract. Missing, malformed, noncanonical, or unsupported `system` values fail evaluation. Hardware-aware decisions can use structured facts when they are present without treating runtime state as configuration.

Maintainers keep durable metadata accurate as hosts change. Hardware remains optional, so a host such as `rvn-vm` can declare its role and system without a hardware record. Runtime validation remains an operational responsibility.
