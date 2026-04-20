# Use kernel ntfs driver for rvn-pc mounts

**Status:** accepted
**Date:** 2026-04-20

## Context

`rvn-pc` mounts `/mnt/storage` and `/mnt/games` from NTFS volumes shared with Windows. The host was previously pinned to `ntfs-3g` after earlier reliability concerns, but the current CachyOS 7 kernel line introduces a reworked kernel `ntfs` path worth adopting on this machine.

We already run `pkgs.cachyosKernels.linuxPackages-cachyos-latest` on `rvn-pc`, so testing the in-kernel NTFS path is directly relevant to the active kernel stack.

## Decision

Switch `modules/hosts/rvn-pc/storage.nix` mount `fsType` values for `/mnt/storage` and `/mnt/games` from `ntfs-3g` to `ntfs`. Keep `boot.supportedFilesystems = [ "ntfs" ];` and remove `big_writes` from mount options because it is specific to `ntfs-3g`.

## Alternatives Considered

Keep `ntfs-3g` for maximum conservatism. This was not chosen because the goal of this change is to use the current CachyOS kernel NTFS driver path and validate it under real host usage.

Switch only one mount and keep the other on `ntfs-3g`. This was not chosen because both volumes serve the same host and should share one clear NTFS driver policy unless a concrete per-disk issue appears.

## Consequences

NTFS mounts on `rvn-pc` now use the kernel `ntfs` driver path, reducing dependence on FUSE for these two volumes. Future debugging should focus on kernel-driver behavior first, with a known fallback of reverting mount `fsType` to `ntfs-3g` if regressions appear.

This decision supersedes the earlier `ntfs-3g` direction from `0002` for the current `rvn-pc` storage configuration.
