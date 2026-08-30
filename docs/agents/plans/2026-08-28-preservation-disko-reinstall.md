# `rvn-pc` Reinstall: Current State and Post-Install Verification

**Audience:** maintainers validating the completed `rvn-pc` Disko and Preservation reinstall.

The workstation is installed and operational. It now uses a tmpfs root, persistent Btrfs storage, a 48 GiB disk-swap partition for hibernation, and `nix-community/preservation`. The reinstall used the generic resumable bootstrap installer, not a dedicated host installer.

Encryption remains intentionally out of scope for this installation. The follow-up is tracked in [2026-08-30-rvn-pc-disk-encryption-rollout.md](2026-08-30-rvn-pc-disk-encryption-rollout.md).

## Verified state

Read-only LAN diagnostics and repository checks verified the following:

- UEFI GRUB boots a tmpfs `/`; Btrfs provides `/nix` and `/persist`; `/persist/home/fbb` is mounted at `/home/fbb`.
- Disk swap is active at 48 GiB with priority `0`. zram is active with priority `5`. The kernel resume argument selects the approved NVMe swap partition.
- `fbb` has UID `1000`. The preserved machine ID, system and Home Manager age keys, SOPS-managed password hash, and persistent SSH host keys exist with their intended ownership and modes.
- Home Manager, Preservation, NetworkManager, Tailscale, and the SSH socket are active. Hyprland has a live instance and reports no configuration errors.
- The protected Kingston and Seagate disks retain their recorded model, serial, capacity, filesystem UUID, NTFS automount declarations, partition layout, and expected contents.
- Two operator-confirmed true cold boots used distinct boot IDs. On both, a sentinel on the tmpfs root disappeared while a persistent-home sentinel retained the same SHA-256 digest.
- Idle graphical hibernation succeeded. The kernel entered and exited hibernation in the same boot session using NVMe disk resume, created a snapshot of about 12.9 GiB, and completed the NVIDIA hibernate and resume units without errors.

The `rvn-pc` closure from commit `17b7dd05` builds. The Disko generated-script check, machine-ID check, all 78 Nix unit tests, and the bootstrap-installer contract test pass in the audited worktree. The `nixos` checkout on `rvn-pc` matches `origin/master`, with existing encrypted SOPS edits still uncommitted. The `dotfiles` checkout is clean and tracks its upstream revision.

Repository lint is fully green: Statix, Deadnix, formatting, Actionlint, service-port validation, bootstrap and recovery checks, and ShellCheck pass. The portable recovery fixture correction canonicalizes its macOS temporary directory and substitutes metadata flags only for Darwin's `tar`; Linux still exercises the production ACL and xattr options. Do not add another broad flake check to this document or rerun one merely as routine validation.

## Fixed disk inventory

| Role               | Stable whole-disk ID                                         | Model                   | Serial             | Capacity in bytes | Protected filesystem UUID |
| ------------------ | ------------------------------------------------------------ | ----------------------- | ------------------ | ----------------- | ------------------------- |
| System target      | `/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746`       | `WDS200T3X0C-00SJG0`    | `21031B801746`     | `2000398934016`   | Not applicable            |
| Games, protected   | `/dev/disk/by-id/ata-KINGSTON_SA400S37960G_50026B7783A2013B` | `KINGSTON SA400S37960G` | `50026B7783A2013B` | `960197124096`    | `B86CB0876CB04244`        |
| Storage, protected | `/dev/disk/by-id/ata-ST2000DM001-1ER164_Z4Z13XS1`            | `ST2000DM001-1ER164`    | `Z4Z13XS1`         | `2000398934016`   | `AC7674097673D316`        |

## Enduring safety and ownership contracts

- Disko names only the approved WDS NVMe through its stable `/dev/disk/by-id` path. Its ESP, swap, and Btrfs partitions use that disk's exact `-part1`, `-part2`, and `-part3` aliases. It does not use global partition-label aliases.
- `/mnt/storage` and `/mnt/games` are UUID-mounted by `modules/hosts/rvn-pc/storage.nix`; they must never appear in `disko.devices` or Disko-generated commands.
- Disko owns `/`, `/boot`, `/nix`, `/persist`, and disk swap. Preservation owns declared persistent state and bind-mounts the complete persistent home at `/home/fbb` before Home Manager and user services start.
- The system SOPS key and SSH host keys live directly under `/persist`. They are not regenerated: a missing restored identity must fail loudly. SOPS secrets, password hashes, and private keys must not enter unencrypted source files or command output.
- The 48 GiB swap partition is unencrypted. Hibernation can expose memory-resident secrets to someone with disk access. This is an accepted risk of the current no-encryption decision.
- Recovery archives intentionally contain plaintext private keys. CIFS access control is their confidentiality boundary. SHA-256 checks detect corruption, not a malicious replacement.
- Keep the recovery backup until the remaining cold-boot, persistence, protected-disk, journal, and repeated hibernation checks complete.

## Configuration cleanup

These configuration cleanup changes are active and verified:

- [x] Legacy ext4 filesystem declarations are removed.
- [x] GRUB OS probing is disabled.
- [x] The Windows RTC override is removed.
- [x] zram priority is explicitly `5`.
- [x] Activate the configuration and verify the next boot retains the tmpfs and Btrfs filesystems, disk and zram priorities, UTC hardware clock, and UEFI GRUB boot.
- [x] Confirm visually that GRUB no longer includes an OS-prober entry.

## Runtime verification

These runtime checks are complete based on observed runtime and operator evidence, not inferred from successful builds, boots, or hibernation alone.

### Identity and login

- [x] Verify password login unless it is explicitly proven elsewhere.
- [x] Compare the machine ID and SSH host-key fingerprints against an external recovery record. Do not treat files on the reinstalled system as the comparison source.

### Persistence and protected disks

- [x] Across at least two true cold boots, confirm an undeclared root-path test file disappears and a declared persistent-path test file survives.
- [x] Confirm the machine ID, SOPS keys, NetworkManager and Tailscale state, repositories, selected personal paths, and the persistent home survive those cold boots.
- [x] Review the protected Kingston and Seagate disks again for the recorded identity, partition layout, filesystem UUID, automount behavior, and expected content.

### Hibernation and stability

- [x] After hibernation resume, verify displays, audio, input devices, and networking.
- [x] Cold boot after a completed resume and confirm the tmpfs root resets normally.
- [x] Repeat hibernation and cold-boot cycles before treating resume as stable.
- [x] Activate the lifecycle fixes and verify Home Manager succeeds, the standard XDG PolicyKit agent is the sole owner, the stale Gamescope service is removed, and the Steam patcher skips an uninitialized Steam profile.
- [x] Declare the `plugdev` group required by the packaged U2F rules and verify a fresh boot no longer logs missing-group errors.
- [x] Activate the corrected `system/networkmanager` aspect and verify a fresh boot no longer exposes initrd-only NetworkManager units or duplicate D-Bus ownership metadata.
- [x] Confirm `//nas/encrypted` is intentionally unavailable while its backing NAS drive is unmounted; its automount failure on access is expected in that state.
- [x] Retain the recovery backup until all checks above pass.

## Recovery rules

- If an identity comparison fails, stop remote use and restore the recorded machine-ID or SSH host-key files before continuing.
- If a persistence check fails, keep the recovery backup and inspect Preservation mounts, ordering, ownership, and the path declaration before changing unrelated state.
- If hibernation fails, retain normal cold-boot operation and persistent logs. Diagnose resume, kernel, and NVIDIA behavior without weakening persistence or login checks.
- If protected-disk content or identity differs from the fixed inventory, stop and investigate before any storage-related change.
- Do not delete the recovery archive until the remaining runtime checks are complete.
