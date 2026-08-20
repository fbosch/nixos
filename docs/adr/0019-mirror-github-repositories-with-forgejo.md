# Mirror GitHub Repositories With Forgejo

**Status:** accepted
**Date:** 2026-08-20

## Context

GitHub holds the primary copies of the repositories, but it is not a recovery location under local control. A local mirror must remain usable when GitHub is unavailable and must have an off-host recovery path without putting live state on the CIFS-backed NAS.

## Decision

Run Forgejo natively on `rvn-srv` as a pull-only mirror and recovery target. Keep live application state, SQLite, repositories, and LFS content under `/var/lib/forgejo` on local ext4 storage. Expose the HTTP service on the LAN only; public exposure and a public reverse proxy are out of scope.

Phase one discovers and mirrors repositories whose GitHub owner is exactly `fbosch`. It uses a dedicated fine-grained, read-only GitHub PAT and does not reuse the root-only Nix `github-token`. Third-party upstream repositories require a later explicit allowlist.

Reconciliation reports unavailable, renamed, and removed upstream repositories but never deletes or overwrites local repositories automatically. Daily consistent Forgejo dumps are stored locally, then completed archives are exported independently to `/mnt/nas/cloud-backup/forgejo` for Synology-managed retention.

The initial recovery claim covers commits, branches, tags, visibility, and cloneability. LFS is covered only after a restore test with real LFS content. Issues, pull requests, releases, Actions data, packages, secrets, repository settings, and protection rules are excluded from continuous synchronization.

## Consequences

GitHub remains the development remote while Forgejo provides a local read path and a recovery source. The service does not depend on NAS availability, but off-host recovery has a 24-hour objective rather than the one-hour Git mirror objective. A successful disposable restore drill is required before the system is described as a backup.
