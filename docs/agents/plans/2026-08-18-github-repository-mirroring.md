# GitHub Repository Mirroring and Recovery

## Goal

Create an independently recoverable local mirror of the GitHub repositories owned by `fbosch` without changing the primary development workflow:

- GitHub remains the authoritative remote.
- Forgejo runs natively on `rvn-srv` and provides local browsing and cloning.
- Forgejo pull mirrors preserve Git commits, branches, and tags.
- Live Forgejo state stays on the local `rvn-srv` ext4 filesystem.
- Consistent backup archives are exported to `/mnt/nas/cloud-backup/forgejo`.
- Synology provides versioned off-host and cloud retention.
- Recovery is verified by restoring into a disposable instance and cloning from it.

Do not place live Forgejo state, SQLite, repositories, or LFS objects on CIFS. Do not treat GitHub issues, pull requests, Actions artifacts, packages, secrets, repository settings, or protection rules as covered by the initial mirror.

Phase one mirrors `fbosch`-owned repositories only. Third-party upstreams such as `NixOS/nixpkgs` require an explicit selection rule and are deferred.

## Decisions Required Before Implementation

1. GitHub remains the source of truth; Forgejo is a pull-only mirror and recovery target.
2. Mirror every repository visible to the dedicated credential whose owner is exactly `fbosch`, including private, archived, and forked repositories unless explicitly denied.
3. Discover repositories from the GitHub API rather than maintaining a hand-written repository list.
4. Defer third-party repository mirroring until the owned-repository workflow is proven; add those repositories through a later explicit allowlist.
5. Reconcile hourly because this environment is behind CGNAT and should not depend on inbound GitHub webhooks.
6. Never delete or overwrite a Forgejo repository merely because the upstream repository disappears, becomes inaccessible, or is renamed.
7. Keep `services.forgejo.stateDir`, `repositoryRoot`, SQLite, and LFS content on local `rvn-srv` storage under `/var/lib/forgejo`.
8. Use the native NixOS `services.forgejo` module and its pinned `forgejo-lts` package rather than downloading release binaries.
9. Use SQLite while Forgejo remains a small single-user mirror instance.
10. Use a dedicated read-only fine-grained GitHub PAT; do not reuse the existing `github-token` consumed by Nix.
11. Disable public registration and expose Forgejo only through existing LAN/Tailscale access. Public exposure and a public reverse proxy are out of scope.
12. Treat Git data as the required initial coverage. GitHub-native metadata migration is a separate feature and must not be represented as continuously synchronized.
13. Enable LFS support, but do not claim LFS coverage until a repository with real LFS objects passes a restore test.
14. Perform a daily consistent backup during a short Forgejo maintenance window, then export the completed archive to Synology in a separate step.
15. Target a one-hour Git mirror recovery point and a 24-hour off-host backup recovery point.
16. Require a successful restore drill before describing the system as a backup.

## Slice 1: Record the Backup Contract and Inventory

**Outcome:** The required recovery coverage is explicit before service implementation begins.

**Changes**

- Add an ADR recording the authority, storage, credential, deletion, and backup boundaries from this plan.
- Define the repository selection rule as GitHub owner ID/login equality, not repository-name matching or affiliation alone.
- Inventory the current repositories through the GitHub API and record counts by:
  - public/private visibility;
  - active/archived state;
  - original/fork state;
  - LFS usage;
  - wiki presence.
- Define runtime reconciliation state that maps the stable GitHub repository ID to the Forgejo repository path.
- Define the initial coverage boundary:
  - required: commits, branches, tags, repository visibility, and cloneability;
  - conditional: LFS after explicit verification;
  - excluded: continuously updated GitHub issues, pull requests, releases, Actions data, packages, secrets, settings, and protection rules.
- Define recovery objectives and alert thresholds for repository discovery, mirror freshness, local backup freshness, and NAS export freshness.

**Acceptance criteria**

- Every repository is either selected or has an explicit exclusion reason.
- The plan does not imply that imported GitHub metadata remains synchronized.
- Repository renames and upstream deletion are represented as drift states rather than deletion instructions.
- The recovery objectives are measurable from local state and systemd unit results.

**Risk:** Low. Documentation and inventory only.

## Slice 2: Add a Native Forgejo Service Module

**Outcome:** `rvn-srv` hosts an internal Forgejo instance whose availability does not depend on the NAS.

**Changes**

- Add a self-contained `modules/services/forgejo/default.nix` aspect following the import-to-enable pattern.
- Use the native NixOS Forgejo module with:
  - SQLite;
  - local `/var/lib/forgejo` state and repositories;
  - LFS support enabled;
  - public registration disabled;
  - installation locked;
  - Forgejo Actions disabled unless a later requirement justifies them;
  - migration destinations restricted to GitHub domains with local-network migrations denied.
- Verify all Forgejo settings against the Forgejo version pinned by the repository's current `nixpkgs`; do not copy settings from unpinned release documentation without evaluation.
- Use port `3000/tcp` only after the implementation branch re-runs the repository's port conflict checks.
- Declare the port in `services.exposedPorts`, colocate the firewall rule, and update `docs/agents/service-ports.md`.
- Register `forgejo.service` as a background application in `services.startupPolicy`.
- Add `"services/forgejo"` to the `rvn-srv` host module list.
- Extend the server healthcheck with Forgejo service and HTTP checks.
- Keep NAS mount dependencies out of `forgejo.service`.

**Acceptance criteria**

- `rvn-srv` evaluates with the Forgejo aspect imported.
- The existing port validation accepts the assigned port.
- Forgejo starts with SQLite and stores all live data below local `/var/lib/forgejo`.
- Registration is disabled and Forgejo Actions are not enabled.
- The UI and a test repository remain available while `/mnt/nas/cloud-backup` is unavailable.
- Forgejo appears in the startup-policy background tier and the server healthcheck.

**Risk:** Medium. This adds a stateful network service and an SSH/HTTP Git endpoint.

## Slice 3: Bootstrap the Local Identity and Credentials

**Outcome:** Automation can create private pull mirrors without broadening the existing Nix GitHub credential boundary.

**Changes**

- Add a separate SOPS secret for a GitHub credential dedicated to mirroring.
- Scope the GitHub credential to read-only repository contents and metadata for the repositories being mirrored.
- Do not reuse or change the permissions of the existing `github-token`.
- Bootstrap the local Forgejo owner account idempotently with the Forgejo administrative CLI.
- Generate a dedicated Forgejo API token with the minimum scope required to inspect and create repositories.
- Store the Forgejo API token in a root-readable runtime state file outside generated shell configuration.
- Ensure bootstrap commands do not print passwords or tokens into the journal.
- Pass the GitHub credential only to the reconciliation process. Accept that Forgejo must persist the remote authentication material inside its protected state to refresh private mirrors.
- Add assertions or tests that keep the mirror credential distinct from the Nix credential and keep both out of world- or wheel-readable paths.

**Acceptance criteria**

- A private repository can be created as a pull mirror without interactive setup.
- The existing Nix credential configuration is unchanged.
- Secret files and generated automation state have explicit least-privilege ownership and modes.
- Re-running bootstrap does not create duplicate users or tokens.
- No credential value appears in evaluated configuration, command arguments visible to other users, or ordinary journal output.

**Risk:** High. The GitHub credential grants read access to private source repositories and will be included in protected Forgejo state backups.

## Slice 4: Reconcile GitHub Repositories into Forgejo

**Outcome:** Existing and newly created GitHub repositories become Forgejo pull mirrors without manual per-repository administration.

**Changes**

- Add a reconciliation script beside the Forgejo module; because it will exceed the inline-script threshold, keep it under a sibling `scripts/` directory and package it with `writeShellApplication`.
- Query the authenticated GitHub repository API with pagination.
- Select only repositories whose owner is exactly `fbosch`.
- Query Forgejo for existing repositories and their mirror state.
- Create missing repositories through Forgejo's migration API with pull mirroring enabled.
- Preserve upstream visibility and repository name.
- Track the stable GitHub repository ID so a rename is reported explicitly rather than interpreted as delete-and-create.
- Refuse to convert or overwrite an existing non-mirror Forgejo repository with the same path.
- Report, but do not automatically remove:
  - repositories no longer returned by GitHub;
  - authentication failures;
  - upstream renames;
  - visibility drift;
  - repositories that exist locally but are not pull mirrors.
- Run reconciliation from a hardened root-owned systemd oneshot and timer with an hourly interval and randomized delay.
- Keep Forgejo's own periodic mirror update enabled; reconciliation is responsible for inventory convergence, not for reimplementing Git fetch.
- Persist a machine-readable reconciliation report containing selected, created, unchanged, stale, and failed repositories.

**Acceptance criteria**

- The first run creates mirrors for all selected public and private repositories.
- A newly created GitHub repository appears after one reconciliation interval.
- Re-running reconciliation is idempotent.
- A new commit and tag become available from Forgejo within the mirror recovery objective.
- An upstream repository deletion or temporary access failure leaves the local repository intact and produces a visible drift result.
- A colliding non-mirror repository causes a targeted failure without modification.

**Risk:** High. Incorrect reconciliation logic could expose private repositories, create duplicates, or destroy the intended archive boundary.

## Slice 5: Create Consistent Local Backups

**Outcome:** Forgejo state can be restored from a coherent local archive rather than from independently copied live files.

**Changes**

- Store backup archives outside live state, for example under `/var/backup/forgejo`.
- Use Forgejo's dump command, but do not rely on an unsynchronized hot copy while mirror updates may be writing.
- Add a dedicated daily backup unit that:
  - prevents reconciliation from starting;
  - stops Forgejo for the dump window because `rvn-srv` uses ext4 and has no filesystem snapshot boundary;
  - runs the dump as the Forgejo service account;
  - validates that a new non-empty archive was produced;
  - starts Forgejo again even when the dump fails;
  - records the archive path and result for monitoring.
- Use a compressed archive format supported by the pinned Forgejo package.
- Keep one complete local archive; replace it only after a new dump succeeds.
- Keep local backup success independent from NAS availability.

**Acceptance criteria**

- No mirror or Forgejo process writes live state while the consistent dump is taken.
- A failed dump restarts Forgejo and leaves the previous valid backup untouched.
- A successful dump produces one complete archive outside `/var/lib/forgejo`.
- A failed dump leaves the previous complete local archive unchanged.
- Forgejo downtime remains limited to the backup operation and is observable in the journal.

**Risk:** High. A backup that has never restored successfully is not evidence of recoverability.

## Slice 6: Export Backups to Synology and Cloud Retention

**Outcome:** Completed Forgejo archives leave `rvn-srv` without making the application depend on CIFS.

**Changes**

- Add a separate root-owned export service and timer for `/mnt/nas/cloud-backup/forgejo`.
- Require `/mnt/nas/cloud-backup` only for the export unit.
- Create the destination directory through the export unit or a root-owned tmpfiles rule after the mount is available.
- Copy only the completed local archive.
- Stage each transfer under a temporary name and rename it after a successful copy so Synology never observes a partially named final archive.
- Do not use destructive synchronization or `--delete`.
- Preserve the local archive when the NAS is unavailable and retry export independently.
- Keep Synology snapshots as the only version-history layer; do not retain dated archive sets locally or on the share.
- Document the required Synology configuration:
  - versioned Hyper Backup or equivalent, not plain synchronization;
  - client-side encryption;
  - retained recovery key outside the NAS;
  - daily and monthly retention;
  - immutable snapshots where supported.
- Treat Synology configuration as an operational dependency outside this repository and record its verification date in the recovery runbook.

**Acceptance criteria**

- Forgejo continues running when the NAS is offline.
- A NAS outage fails only the export unit and does not invalidate the local backup.
- The completed archive appears below `/mnt/nas/cloud-backup/forgejo` without a partial final filename.
- Synology snapshots retain historical versions after the latest archive is replaced.
- At least one archive can be retrieved from the cloud destination independently of `rvn-srv`.

**Risk:** Medium. The NixOS side cannot guarantee that Synology cloud versioning or encryption is configured correctly.

## Slice 7: Encode Monitoring and Safety Checks

**Outcome:** Loss of mirror or backup coverage becomes visible before a recovery event.

**Changes**

- Extend `system-healthcheck` to verify:
  - `forgejo.service` is active;
  - the internal Forgejo HTTP endpoint responds;
  - the last reconciliation completed within its threshold;
  - no selected repository has a stale or failed mirror beyond the threshold;
  - the newest local backup is recent and non-empty;
  - the newest successful NAS export is recent.
- Check export freshness from recorded unit state or marker data rather than requiring Forgejo itself to mount the NAS.
- Add feature-owned Nix unit tests or assertions for:
  - live Forgejo paths not being under `/mnt/nas`;
  - registration being disabled;
  - Forgejo Actions remaining disabled by default;
  - the dedicated mirror credential not aliasing `github-token`;
  - reconciliation having no automatic deletion path;
  - the service port being declared consistently.
- Add the relevant `rvn-srv` evaluation and existing repository checks to each implementation slice.

**Acceptance criteria**

- An intentionally stopped Forgejo service fails the healthcheck.
- An expired reconciliation report and expired local backup are reported separately.
- NAS export failure does not report Forgejo itself as unavailable.
- Static checks reject a future move of live Forgejo state onto `/mnt/nas`.
- The full repository check suite passes after the service is enabled.

**Risk:** Low. Keep monitoring checks focused on recoverability rather than general Forgejo internals.

## Slice 8: Prove Restore and Recovery

**Outcome:** The mirror is demonstrated to be usable without GitHub or the original `rvn-srv` state.

**Changes**

- Add a recovery runbook covering:
  - provisioning a disposable Forgejo instance;
  - restoring the latest local archive;
  - restoring an older archive retrieved from Synology/cloud;
  - validating users, repositories, SQLite, LFS, and clone URLs;
  - promoting a pull mirror to a writable repository only during an explicit recovery event.
- Select representative repositories:
  - one public repository;
  - one private repository;
  - one archived or forked repository;
  - one repository using LFS when available.
- Compare branches, tags, and commit object reachability between GitHub and the restored Forgejo instance.
- Run `git fsck --full` on clones from the restored instance.
- Record the restore date, source archive, duration, failures, and uncovered data.
- Repeat the restore drill after material Forgejo upgrades and at least quarterly.

**Acceptance criteria**

- A fresh machine can restore Forgejo from a NAS/cloud archive without the original `/var/lib/forgejo`.
- Public and private repositories clone successfully from the restored instance.
- Branches and tags match the selected recovery point.
- LFS objects are present and usable before LFS is marked covered.
- The runbook identifies every excluded GitHub data class rather than implying full account backup.
- The restore drill is completed before the implementation is considered done.

**Risk:** Medium. The drill may reveal gaps in LFS, credentials, clone URLs, or version compatibility that require revisiting earlier slices.

## Rollout Order

1. Slice 1: record the contract and create the dedicated credential needed for the authoritative private-repository inventory.
2. Slice 2: deploy Forgejo with one manually created public canary mirror.
3. Slice 3: bootstrap the local automation identity and produce the inventory.
4. Slice 4: reconcile the canary, then private repositories, then the full inventory.
5. Slice 5: produce and validate consistent local backups.
6. Slice 6: export archives to Synology and verify cloud versioning.
7. Slice 7: enable freshness monitoring and static safety checks.
8. Slice 8: restore from local and cloud archives and record the result.

Keep the slices independently reviewable. Do not declare coverage for private repositories, LFS, NAS export, or cloud recovery until the corresponding acceptance criteria have passed.
