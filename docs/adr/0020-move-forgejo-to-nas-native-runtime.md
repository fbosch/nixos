# Move Forgejo to NAS-Native Runtime

**Status:** accepted
**Date:** 2026-09-05

## Context

ADR 0019 placed the Forgejo pull mirror, SQLite database, repositories, LFS content, and backup creation on `rvn-srv`. The active state grew beyond the practical capacity of that host's root filesystem. A complete Forgejo `15.0.7` archive is already stored in the NAS `backup` shared folder and has passed a Zstandard integrity check.

The NAS is suitable for hosting the application only when Forgejo writes to a filesystem local to the NAS. Mounting the NAS share back onto `rvn-srv` would make SQLite, Git locking, and atomic filesystem operations depend on CIFS semantics and would retain the capacity problem on the source host.

## Decision

Move Forgejo to a NAS-native runtime and store all of its persistent state on a local NAS volume. The runtime is managed manually on the NAS rather than by this NixOS flake. `docs/agents/forgejo-nas-migration.md` defines the Container Manager restore procedure to use when that NAS runtime is confirmed.

Restore the existing archive with the archive-producing Forgejo version before considering an upgrade. Preserve the source `app.ini` security values while adapting data paths, the listener, and reverse-proxy configuration to the NAS. Keep the existing HTTPS hostname and expose no WAN port by default.

Remove the Forgejo aspect, health checks, firewall rule, port declaration, backup jobs, and local administration command from `rvn-srv`. Delete `/var/lib/forgejo`, `/var/backup/forgejo`, and the obsolete encrypted administrator-password entry only after the NAS instance passes restore, login, clone, repository-integrity, LFS where applicable, and new-backup validation.

## Alternatives Considered

Continue running Forgejo on `rvn-srv`. Rejected because the service state and recovery artifacts caused recurring root-volume exhaustion.

Store live Forgejo data on the CIFS-mounted NAS share. Rejected because the application requires reliable local filesystem behavior for SQLite and Git operations.

Manage the NAS runtime through the NixOS Podman Quadlet convention. Rejected because the NAS appliance owns this runtime outside the flake; its deployment and backup policy must be operated and verified directly on the NAS.

## Consequences

The NixOS repository no longer deploys or monitors Forgejo on `rvn-srv`. NAS backup, snapshots, reverse-proxy configuration, and container lifecycle become explicit operational responsibilities. The imported archive remains a recovery source until a NAS-native backup has been created and verified.

ADR 0019 is superseded. Its repository-mirroring scope and history remain relevant, but its local-host storage and runtime decision no longer applies.
