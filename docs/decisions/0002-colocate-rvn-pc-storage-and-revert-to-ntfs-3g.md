# Colocate rvn-pc storage and revert to ntfs-3g

**Status:** proposed
**Date:** 2026-04-01

## Context

The storage mount configuration for `rvn-pc` uses host-specific NTFS UUIDs and mount points (`/mnt/storage`, `/mnt/games`). Keeping this in the shared `modules/hardware/storage.nix` path made ownership and scope ambiguous, and increased the chance of accidental reuse on other hosts.

An attempted switch away from `ntfs-3g` did not behave reliably in this environment, so mount behavior needed to return to the previously working NTFS userspace driver setup.

## Decision

Move the storage mount definitions to a host-local module at `modules/hosts/rvn-pc/storage.nix` and import it from `modules/hosts/rvn-pc/default.nix`. Standardize both mounts on `ntfs-3g` with the existing stable options profile, and remove the now-orphaned shared module `modules/hardware/storage.nix` so `rvn-pc` storage behavior has a single authoritative source.

## Alternatives Considered

Keep storage in the shared hardware module and treat it as a reusable baseline. This was rejected because the UUIDs and mount semantics are specific to one machine and do not represent a cross-host concern. Keep both shared and host-local modules temporarily; this was rejected because duplicate definitions create drift and make future debugging harder.

Keep the alternative non-`ntfs-3g` mounting approach. This was rejected because it was not working reliably on this host during rebuild/runtime validation, while `ntfs-3g` restored expected behavior.

## Consequences

Host-specific storage configuration is easier to discover and maintain next to the `rvn-pc` host module. The tree more clearly reflects dendritic scope boundaries between shared and host-local concerns. Follow-on work includes moving remaining `machines/desktop/*` host-coupled files into the same host directory structure in a staged migration.

Using `ntfs-3g` prioritizes stable host behavior over experimenting with alternate NTFS drivers in this path.
