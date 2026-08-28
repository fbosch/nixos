# `rvn-pc` Preservation and Disko Reinstall

## Goal

Reinstall `rvn-pc` onto a declarative Disko layout with a tmpfs root, persistent Btrfs storage, hibernation, and `nix-community/preservation`. Preserve the machine identity, SSH host identity, SOPS identities, declarative login, and the entire future `/home/fbb`. Restore selected personal state from the current installation.

The installation must erase only:

```text
/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746
```

The NTFS storage and games disks remain connected during installation, but are protected by an explicit hardware inventory and must never appear in Disko's generated commands.

## Decisions

| Area | Decision |
| --- | --- |
| Target host | `rvn-pc` only |
| Target disk | `nvme-WDS200T3X0C-00SJG0_21031B801746` |
| Partitioning | Disko |
| Boot | UEFI GRUB, 2 GiB FAT32 ESP at `/boot` |
| Root | tmpfs at `/`, `mode=755`, `size=25%` |
| Persistent storage | Btrfs subvolumes mounted at `/nix` and `/persist` |
| Swap | 48 GiB unencrypted partition, explicit resume device |
| Runtime swap | Keep zram with a higher priority than disk swap |
| Encryption | None |
| Persistence | `nix-community/preservation` |
| Initrd | systemd initrd |
| Login | SOPS-encrypted yescrypt hash, immutable users, `fbb` UID 1000 |
| Home persistence | Bind-mount the entire `/home/fbb` from `/persist/home/fbb` |
| State migration | Identities and selected personal state only |
| Remote installer | Separate `rvn-pc` endpoint and flake app |
| Existing bootstrap | Keep `nix.fbb.sh/install` unchanged |
| Recovery archive | Plaintext tar on `//rvn-nas/backup`; accepted local-network and NAS access risk |

The unencrypted swap partition can expose memory-resident secrets after hibernation. This is an accepted consequence of the no-encryption decision.

The current fixed-disk inventory is:

| Role | Stable whole-disk ID | Model | Serial | Capacity in bytes | Protected filesystem UUID |
| --- | --- | --- | --- | --- | --- |
| Target | `/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746` | `WDS200T3X0C-00SJG0` | `21031B801746` | `2000398934016` | Not applicable; this disk will be erased |
| Games | `/dev/disk/by-id/ata-KINGSTON_SA400S37960G_50026B7783A2013B` | `KINGSTON SA400S37960G` | `50026B7783A2013B` | `960197124096` | `B86CB0876CB04244` |
| Storage | `/dev/disk/by-id/ata-ST2000DM001-1ER164_Z4Z13XS1` | `ST2000DM001-1ER164` | `Z4Z13XS1` | `2000398934016` | `AC7674097673D316` |

## Safety Invariants

- Disko names exactly one disk by its stable `/dev/disk/by-id` path.
- Disko addresses the ESP, swap, and Btrfs partitions through that disk's exact `-part1`, `-part2`, and `-part3` by-id aliases. Formatting and mounting never use global partition-label aliases.
- The generated-script check covers static device references. Disko's deactivation helper canonicalizes the approved by-id path at runtime, so the installer still verifies the resolved hardware immediately before invoking Disko.
- Disko never accepts a user-supplied target-device override.
- `/mnt/storage` and `/mnt/games` remain UUID-mounted by `modules/hosts/rvn-pc/storage.nix` and never appear in `disko.devices`.
- The installer requires the recorded target and protected disks to resolve to the expected model, serial, capacity, partition table, and filesystem UUIDs.
- The installer refuses to partition when a protected disk is missing, has changed identity, or appears in Disko's generated commands.
- Additional fixed disks are an error. Removable installer media must be identified and reported separately.
- Formatting and installation are separate actions. State is restored and SOPS is verified between them.
- The same immutable Git revision supplies the Disko layout and `nixos-install` configuration.
- Until the guarded installer exists, the standalone Disko output is supported only for evaluation and dry-run inspection.
- The current installation is never switched to the final cutover revision.
- The existing machine ID, SSH host keys, and system and Home Manager age keys are restored. Missing identities fail loudly instead of being regenerated.
- Secret values, password hashes, and private keys never enter unencrypted source files or command output.
- Recovery archives contain plaintext private keys by explicit decision. CIFS access control is the confidentiality boundary, and SHA-256 checks detect corruption rather than malicious replacement.
- Existing unrelated worktree changes are preserved and excluded from this work.
- The recovery backup remains available until cold boot and hibernation validation pass.

## Phase 1: Protect Current Work

**Outcome:** all source changes and identity material can survive an immediate disk loss.

- [ ] Record `git status --short`, `git diff`, and the current commit before editing.
- [ ] Preserve the existing unrelated changes in the browser, productivity, input, and webapp files.
- [ ] Confirm every required repository commit is pushed to a remote reachable from the installer.
- [ ] Record the model, serial, capacity, partition table, stable by-id path, and filesystem UUIDs for the target and both protected SATA disks.
- [ ] Record `/etc/machine-id` and public SSH host-key fingerprints without copying private contents into the repository.
- [ ] Confirm recovery copies exist for `/var/lib/sops-nix/key.txt` and `/home/fbb/.config/sops/age/keys.txt`.
- [ ] Confirm the external backup location is readable from standard NixOS installer media.
- [ ] Run `just check-recovery` and resolve every missing source or destination mismatch.
- [ ] Run `just backup-recovery` and record the returned backup ID outside the target NVMe.
- [ ] Run `just list-recovery` and confirm the recorded backup appears first with the expected age.
- [ ] Run `just verify-latest-recovery` as the routine newest-backup check.
- [ ] Run `just verify-recovery <backup-id>` against the completed archive.

**User-run actions:** privileged backup copies and all SOPS inspection commands.

**Exit gate:** source work, both age identities, machine identity, and SSH host identity have verified recovery copies.

**Good commit point:** none. This phase records evidence and creates external backups.

## Phase 2: Make Login Declarative on the Current System

**Outcome:** the existing installation proves that SOPS can provide the `fbb` password before user creation.

### Repository changes

- [ ] Add `modules/hosts/rvn-pc/login.nix` as a host-specific NixOS aspect.
- [ ] Add the login aspect to `hosts.rvn-pc.modules` in `modules/hosts/rvn-pc/default.nix`.
- [ ] Pin `users.users.fbb.uid = 1000` for compatibility with the existing NTFS ownership mapping.
- [ ] Set `users.mutableUsers = false` for `rvn-pc`.
- [ ] Declare `sops.secrets.user-password-hash.neededForUsers = true`.
- [ ] Set `users.users.fbb.hashedPasswordFile` to the resulting SOPS secret path.
- [ ] Keep the current system age-key path, `/var/lib/sops-nix/key.txt`, during this phase.

### Secret preparation

- [ ] Generate a yescrypt password hash interactively.
- [ ] Add `user-password-hash` to `secrets/hosts/rvn-pc.yaml` with SOPS.
- [ ] Confirm the encrypted file remains decryptable by the existing `rvn-pc` and recovery recipients.
- [ ] Do not store the plaintext password or decrypted hash in a shell history, plan, test fixture, or Git diff.

### Validation

- [ ] Evaluate `users.users.fbb.uid`, `users.mutableUsers`, `hashedPasswordFile`, and `neededForUsers` from `nixosConfigurations.rvn-pc`.
- [ ] Build the current `rvn-pc` configuration.
- [ ] Switch the current system to this preparation revision.
- [ ] Verify TTY and display-manager login with the configured password.
- [ ] Cold reboot and verify login again.

**User-run actions:** SOPS editing, the privileged switch, logout, login, and reboot.

**Exit gate:** password login works after a cold reboot, `fbb` is UID 1000, and no mutable password state is required.

**Good commit point:** declarative `rvn-pc` login and encrypted password-hash declaration.

## Phase 3: Add Disko Without Affecting the Running Host

**Outcome:** the future disk layout is a standalone flake output that can be inspected and tested without changing the current filesystem configuration.

### Repository changes

- [ ] Add `nix-community/disko` to `flake.nix` and update `flake.lock` without discarding existing lockfile changes.
- [ ] Add `modules/hosts/rvn-pc/disko.nix` as a flake-parts module.
- [ ] Import `inputs.disko.flakeModules.disko` from the owning flake-parts module.
- [ ] Define one canonical raw `disko.devices` value.
- [ ] Export the value as `flake.diskoConfigurations.rvn-pc`.
- [ ] Declare `flake.modules.nixos."hosts/rvn-pc/disko"` from the same value for later use.
- [ ] Do not add `"hosts/rvn-pc/disko"` to the host module list yet.

### Layout contract

```text
GPT
├─ ESP      2 GiB, type EF00, FAT32, /boot, umask=0077
├─ swap     48 GiB, unencrypted, resumeDevice=true
└─ system   remaining space, Btrfs
   ├─ /nix      compress=zstd, noatime
   └─ /persist  compress=zstd, noatime

nodev
└─ /        tmpfs, mode=755, size=25%
```

The partition device aliases are part of the layout contract:

```text
ESP      /dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part1
swap     /dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part2
system   /dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part3
```

### Validation

- [ ] Evaluate `diskoConfigurations.rvn-pc`.
- [ ] Build `checks.x86_64-linux.rvn-pc-disko-script`; it must inspect the generated script without executing it.
- [ ] Run Disko in `--dry-run` mode against the standalone output using the Disko revision recorded in `flake.lock`.
- [ ] Use a `git+file://` flake URI for local dirty-worktree inspection so Git's fsmonitor socket is excluded from the flake source.
- [ ] Treat Disko's dry-run result as a script path. Open the script and inspect its contents.
- [ ] Assert that the only disk device is the approved WDS NVMe by-id path.
- [ ] Assert that every static partition reference uses the approved `-part1`, `-part2`, or `-part3` alias.
- [ ] Reject global partlabel, partuuid, UUID, by-path, kernel, mapped, and protected-disk device references in the generated script.
- [ ] Assert that no LUKS device, NTFS disk, `/mnt/storage`, or `/mnt/games` appears.
- [ ] Rebuild the current `nixosConfigurations.rvn-pc` and confirm its existing root, boot, and swap declarations remain unchanged.
- [ ] Add focused evaluation coverage in the owning module for disk identity, partition sizes, filesystem types, subvolumes, tmpfs options, and resume selection.
- [ ] Do not run `destroy`, `format`, `mount`, or combined mutating modes before the guarded installer and disposable rehearsal are complete.

**Exit gate:** the standalone Disko output evaluates and dry-runs, while the current host still builds against its existing ext4 root.

**Good commit point:** Disko input and inactive standalone `rvn-pc` layout.

## Phase 4: Add the Inactive Preservation Contract

**Outcome:** the future system and user state policy evaluates without affecting the current installation.

### Repository changes

- [ ] Add `nix-community/preservation` to `flake.nix` and update `flake.lock`.
- [ ] Add `modules/hosts/rvn-pc/preservation.nix`.
- [ ] Declare `flake.modules.nixos."hosts/rvn-pc/preservation"` and import `inputs.preservation.nixosModules.preservation`.
- [ ] Enable `boot.initrd.systemd.enable` in the future aspect.
- [ ] Enable Preservation and declare `preservation.preserveAt."/persist"`.
- [ ] Mark `/nix` and `/persist` as needed for boot.
- [ ] Do not add the Preservation aspect to `hosts.rvn-pc.modules` yet.
- [ ] Do not import a Home Manager persistence module. Preservation owns user bind mounts through its NixOS options.

### System state

- [ ] Preserve `/etc/machine-id` with `inInitrd = true`.
- [ ] Fail the initrd when the restored machine ID is missing, empty, symlinked, all-zero, or malformed.
- [ ] Suppress `systemd-machine-id-commit.service` for the restored fixed machine ID.
- [ ] Preserve `/var/lib/nixos` with `inInitrd = true`.
- [ ] Preserve `/var/lib/NetworkManager`.
- [ ] Preserve `/etc/NetworkManager/system-connections` with root-only directory permissions.
- [ ] Preserve `/var/lib/tailscale` with mode `0700`.
- [ ] Preserve `/var/lib/systemd/timers`.
- [ ] Preserve `/var/lib/systemd/random-seed` as an initrd symlink with its parent created explicitly.
- [ ] Preserve `/var/log` during the stabilization period.
- [ ] Exclude Bluetooth, rootful Podman, system Flatpak, Waydroid, libvirt VM data, caches, and coredumps unless the state inventory later provides a specific reason to retain them.

### Direct persistent identities

- [ ] Override the future system SOPS key path to `/persist/var/lib/sops-nix/key.txt`.
- [ ] Set future `sops.age.generateKey = false`.
- [ ] Configure OpenSSH host keys at `/persist/etc/ssh/ssh_host_ed25519_key` and `/persist/etc/ssh/ssh_host_rsa_key`.
- [ ] Disable automatic OpenSSH host-key generation so missing restored keys fail instead of replacing the host identity.
- [ ] Keep the system SOPS key and SSH host keys outside Preservation bind mounts because consumers can read them directly from `/persist`.
- [ ] Add a matching Home Manager aspect only to set `sops.age.generateKey = false`; do not add Home Manager persistence options.

### Home state

- [ ] Preserve `/home/fbb` as one bind-mounted directory owned by `fbb:users` with mode `0700`.
- [ ] Mount the persistent home before Home Manager and user services start so Home Manager and Stow write to the durable home.
- [ ] Treat the whole-home policy as a post-install reboot contract. It does not decide which files from the current installation are copied into the new home.
- [ ] Keep current-state migration explicit in the recovery manifest; files not backed up before Disko cannot be recovered by Preservation.

### Validation

- [ ] Evaluate the future Preservation options without importing the aspect into the active host.
- [ ] Assert the machine ID and `/var/lib/nixos` are prepared in the initrd.
- [ ] Test machine-ID validation against missing, empty, malformed, all-zero, symlinked, and valid files.
- [ ] Assert the system SOPS key and SSH host keys use direct `/persist` paths.
- [ ] Assert OpenSSH host-key generation is disabled.
- [ ] Assert automatic age-key generation is disabled in the future NixOS and Home Manager configurations.
- [ ] Assert `/persist/home/fbb` is bind-mounted at `/home/fbb` with `fbb:users` ownership before `preservation.target`.
- [ ] Check generated systemd mount and tmpfiles units for ownership, mode, and ordering.

**Exit gate:** the entire future home is durable by explicit policy, early identities have deterministic paths, and no broad system directory is preserved accidentally.

**Good commit point:** inactive Preservation, SOPS, SSH identity, and selected-state contract.

## Phase 5: Add the Guarded Installer

**Outcome:** a separate flake app can inspect, partition, and install `rvn-pc` through distinct fail-closed actions.

### Repository changes

- [ ] Add `scripts/reinstall/rvn-pc-install.sh`.
- [ ] Add a `perSystem` flake app such as `install-rvn-pc` using `pkgs.writeShellApplication` and explicit runtime inputs.
- [ ] Add `modules/hosts/rvn-pc/README.md` as the operator runbook and link it briefly from the top-level README.
- [ ] Keep `scripts/bootstrap/install.sh`, `scripts/bootstrap/bootstrap-machine.sh`, and the existing `install` app unchanged.
- [ ] Add shell contract tests under `scripts/ci/` and include them in the existing lint workflow.

### CLI contract

```text
install-rvn-pc inspect
install-rvn-pc partition
install-rvn-pc install
```

- [ ] `inspect` performs no writes and reports installer mode, UEFI state, flake revision, target identity, current partitions, and expected layout.
- [ ] `partition` repeats all inspection checks, refuses device overrides, requires a controlling terminal, and asks for the exact target confirmation phrase.
- [ ] `partition` acquires an exclusive installer lock before repeating inspection and retains it until Disko exits.
- [ ] `partition` runs only Disko `destroy,format,mount` and then stops for restoration.
- [ ] `partition` refuses non-target mounts below `/mnt`; Disko begins by recursively unmounting that tree. Mount recovery sources outside `/mnt` during partitioning.
- [ ] `install` refuses to partition, checks the expected target mounts, checks required restored files and modes, and runs `nixos-install` against the same immutable revision.
- [ ] Record the partition revision in the installer environment and require `install` to use the same full Git commit.
- [ ] Non-interactive destructive use requires an explicit automation proof designed and tested separately. Do not treat `--yes` as sufficient proof for this severe operation.
- [ ] Cancellation exits without mutation.
- [ ] Errors name the failed check and the safest recovery action.
- [ ] Child Disko and `nixos-install` output, exit status, and signals remain intact.

### Disk inventory checks

- [ ] Resolve `/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746`.
- [ ] Verify model `WDS200T3X0C-00SJG0`, serial `21031B801746`, and expected approximate capacity.
- [ ] Verify the target is an NVMe whole-disk device rather than a partition.
- [ ] Before partitioning, verify that any existing approved `-partN` aliases resolve below the target NVMe. After Disko exits, repeat the check against the recreated partitions.
- [ ] Resolve the protected games disk as `/dev/disk/by-id/ata-KINGSTON_SA400S37960G_50026B7783A2013B` and verify its model, serial, capacity, partition table, and filesystem UUID `B86CB0876CB04244`.
- [ ] Resolve the protected storage disk as `/dev/disk/by-id/ata-ST2000DM001-1ER164_Z4Z13XS1` and verify its model, serial, capacity, partition table, and filesystem UUID `AC7674097673D316`.
- [ ] Refuse operation when any required stable ID is missing, ambiguous, duplicated, or resolves to unexpected hardware.
- [ ] Refuse duplicate matching PARTUUID or PARTLABEL links even though production formatting uses by-id partition aliases.
- [ ] Refuse unexpected fixed disks while identifying removable installer media separately.
- [ ] Inspect Disko's generated commands and refuse operation if any whole-disk path, by-id alias, partition, or filesystem UUID belonging to a protected disk appears.
- [ ] Require the phrase `ERASE nvme-WDS200T3X0C-00SJG0_21031B801746` immediately before Disko runs.
- [ ] Refuse `--yes-wipe-all-disks` in the interactive workflow.
- [ ] Invoke Disko from the reviewed flake lock. Do not fetch or execute an independent mutable Disko revision.

### Cloudflare endpoints

- [ ] Keep `https://nix.fbb.sh/install` mapped to the current post-install bootstrap.
- [ ] Map `https://nix.fbb.sh/hosts/rvn-pc/disko.nix` to the reviewed Disko module for inspection only.
- [ ] Map `https://nix.fbb.sh/hosts/rvn-pc/install` to a small launcher that names one reviewed immutable Git commit.
- [ ] Ensure the launcher runs `install-rvn-pc` from that commit rather than from `master`.
- [ ] Make a no-argument launcher invocation default to `inspect`; require an explicit `partition` argument for disk mutation.
- [ ] Support `curl -fsSL https://nix.fbb.sh/hosts/rvn-pc/install | bash -s -- inspect`, with `partition` and `install` as the other explicit actions.
- [ ] Print the pinned full commit before running the flake app and verify the recorded partition revision before installation.
- [ ] Update the Cloudflare route only after the reviewed commit is pushed.
- [ ] Keep Cloudflare credentials and route management outside this repository unless its authoritative configuration is deliberately moved here later.

### Operator documentation

- [ ] Explain why `nix.fbb.sh/install` remains the generic post-install bootstrap and must not be used for this disk installation.
- [ ] Document installer-media prerequisites, recovery verification, the three direct launcher commands, and the required restoration stop between `partition` and `install`.
- [ ] Record the approved target and protected disk identities without including secrets.
- [ ] Document the direct `nix run github:fbosch/nixos/<commit>#install-rvn-pc -- <action>` fallback.
- [ ] Document cancellation, partial-failure recovery, `/mnt` mount restrictions, and the fact that pre-cutover ext4 generations cannot boot after partitioning.

### Validation

- [ ] Test `--help`, inspection success, inspection failure, cancellation, missing TTY, wrong disk, missing disk, wrong model, wrong serial, wrong capacity, missing protected disk, changed protected UUID, unexpected fixed disk, and protected-disk references in generated commands.
- [ ] Stub Disko, `nixos-install`, `sudo`, and block-device commands in shell contract tests.
- [ ] Prove `inspect` cannot reach a mutating command.
- [ ] Prove `install` cannot reach Disko formatting.
- [ ] Prove `partition` cannot continue without the exact confirmation phrase.
- [ ] Prove `partition` refuses protected or recovery mounts below `/mnt` and a second concurrent installer process.
- [ ] Prove `install` rejects a revision different from the one recorded by `partition`.
- [ ] Test the no-argument launcher default and each explicit `curl | bash -s -- <action>` form with a stubbed flake app.
- [ ] Run `shfmt` and `shellcheck` on the new scripts.

**Exit gate:** the installer fails closed in every tested mismatch and cannot combine partitioning with installation.

**Good commit point:** guarded installer app, contract tests, and documented immutable endpoint payload.

## Phase 6: Rehearse Before The Real Disk

**Outcome:** the complete filesystem, boot, Preservation, and installer flow has been exercised without touching the workstation NVMe.

- [ ] Evaluate and build the future `rvn-pc` system closure.
- [ ] Run Disko dry-run and inspect every generated destructive command.
- [ ] Exercise the layout against a disposable VM disk or loopback-backed test fixture with a test-only device override that cannot enter the production output.
- [ ] Verify tmpfs `/`, persistent `/nix`, persistent `/persist`, the ESP, and the 48 GiB resume swap in the rehearsal environment.
- [ ] Fill the tmpfs root to its 25 percent limit and verify predictable `ENOSPC` behavior without losing persistent state.
- [ ] Restore disposable test identities into the rehearsal `/persist`; never copy production private keys into a shared test image.
- [ ] Verify Preservation creates the expected bind mounts, ownership, modes, and initrd paths.
- [ ] Verify an undeclared test file disappears after a cold reboot and a declared file survives.
- [ ] Verify the installer stops after partitioning and can resume at installation without formatting again.
- [ ] Run targeted checks first, then the repository lint and flake checks required by the current validation guidance.

**Exit gate:** a disposable environment completes partition, restore, install, and two cold boots with the expected persistence behavior.

**Good commit point:** rehearsal fixes and validation coverage, if any were required.

## Phase 7: Create the Recovery Set

**Outcome:** every retained identity and personal path has a checked source, destination, owner, mode, and checksum.

### Recovery manifest

- [ ] Treat `scripts/recovery/manifests/rvn-pc.tsv` as the checked-in identity allowlist and add personal-state paths only after inventory review.
- [ ] Record `/etc/machine-id` to `/persist/etc/machine-id`.
- [ ] Record `/var/lib/sops-nix/key.txt` to `/persist/var/lib/sops-nix/key.txt` with `root:root` and mode `0600`.
- [ ] Record SSH host private and public keys to `/persist/etc/ssh/` with private keys mode `0600` and public keys mode `0644`.
- [ ] Record the Home Manager age key under `/persist/home/fbb/.config/sops/age/` with user ownership and mode `0600`.
- [ ] Record the exact selected user-state source and destination paths.
- [ ] Record checksums for fixed identity files and archives.
- [ ] Record current public SSH host-key fingerprints for post-install comparison.

### Backup validation

- [ ] Mount or open the backup from installer media.
- [ ] Run `local-host-recovery.sh verify --host rvn-pc <backup-id>` because installer media normally uses a different hostname.
- [ ] Verify ownership and mode metadata can be restored.
- [ ] Verify the system age key can decrypt `secrets/common.yaml` and `secrets/hosts/rvn-pc.yaml` with plaintext discarded.
- [ ] Verify `user-password-hash` exists and decrypts without printing its value.
- [ ] Verify `nixos` and `dotfiles` repositories contain all required commits and untracked work.
- [ ] Inspect archives and restore representative files into a temporary location.
- [ ] Keep at least one recovery copy outside the target NVMe.

**User-run actions:** all privileged copies and SOPS verification.

**Exit gate:** the manifest is complete and an installer session can read and restore the recovery set.

**Good commit point:** none. Recovery data and evidence stay outside Git.

## Phase 8: Build the Final Cutover Revision

**Outcome:** one pushed immutable revision represents the exact system that `nixos-install` will install.

### Repository changes

- [ ] Add `"hosts/rvn-pc/disko"` to `hosts.rvn-pc.modules`.
- [ ] Add `"hosts/rvn-pc/preservation"` to `hosts.rvn-pc.modules`.
- [ ] Remove only the obsolete root, `/boot`, and empty `swapDevices` declarations from `modules/hosts/rvn-pc/hardware.nix`.
- [ ] Retain hardware detection and NVMe initrd modules from `hardware.nix`.
- [ ] Keep the external NTFS mounts in `modules/hosts/rvn-pc/storage.nix` unchanged.
- [ ] Keep UEFI GRUB and disable OS probing because Windows will no longer exist.
- [ ] Remove the Windows dual-boot RTC override unless another installed OS still requires local-time RTC.
- [ ] Keep NVIDIA power management enabled.
- [ ] Keep zram enabled and set explicit disk/zram priorities after verifying the evaluated option contract.
- [ ] Ensure Disko is the single owner of `/`, `/boot`, `/nix`, `/persist`, and disk swap.
- [ ] Ensure the future Preservation aspect supplies the direct persistent SOPS and SSH paths.

### Validation

- [ ] Format only the files changed by this work.
- [ ] Evaluate all `rvn-pc` filesystem, swap, resume, initrd, bootloader, SOPS, SSH, user, and Preservation options.
- [ ] Build `nixosConfigurations.rvn-pc.config.system.build.toplevel`.
- [ ] Run Disko dry-run from the final revision.
- [ ] Run the focused Nix and shell tests.
- [ ] Run repository lint and flake checks.
- [ ] Inspect the final diff and confirm unrelated worktree changes are absent.
- [ ] Push the reviewed revision so the installer can fetch it.
- [ ] Point the Cloudflare install endpoint at this exact commit.
- [ ] Do not run `nixos-rebuild switch` or `nixos-rebuild boot` from this revision on the old installation.
- [ ] Record that pre-cutover generations reference the ext4 filesystem erased by Disko and are not rollback targets after partitioning.

**Exit gate:** the immutable revision builds, dry-runs, is remotely fetchable, and is not activated on the old filesystem.

**Good commit point:** final host cutover and validated installer revision.

## Phase 9: Perform the Reinstall

All commands that use `sudo`, Disko, SOPS, or `nixos-install` in this phase are user-run.

### Installer preflight

1. Leave the NTFS storage and games disks connected and boot standard NixOS installer media in UEFI mode.
2. Confirm the installer reports its removable boot media separately from the three fixed disks.
3. Connect networking and verify the approved Git revision is reachable.
4. Run `curl -fsSL https://nix.fbb.sh/hosts/rvn-pc/install | bash -s -- inspect`; verify that it reports the approved full Git commit.
5. Use `nix run github:fbosch/nixos/<commit>#install-rvn-pc -- inspect` as the fallback when the custom endpoint is unavailable.
6. Compare the target and protected disks' model, serial, capacity, by-id path, partition table, and filesystem UUIDs with the recovery record.
7. Mount the recovery source outside `/mnt` and verify that the recovery set is readable before any disk write.
8. Confirm that no protected or recovery filesystem is mounted below `/mnt`; Disko recursively unmounts that tree before partitioning.
9. Stop if any required identity differs, a protected disk is missing, an unexpected fixed disk is present, or Disko's generated commands reference anything except the target NVMe.

### Partition

1. Run `curl -fsSL https://nix.fbb.sh/hosts/rvn-pc/install | bash -s -- partition`.
2. Review the final disk summary.
3. Enter `ERASE nvme-WDS200T3X0C-00SJG0_21031B801746` exactly.
4. Let Disko destroy, format, and mount the target.
5. Verify `/mnt/boot`, `/mnt/nix`, and `/mnt/persist` are mounted from the expected target partitions and subvolumes.
6. Verify the swap partition is 48 GiB and unencrypted.
7. Do not rerun the partition action after this point unless intentionally restarting the installation from zero.

### Restore identities and state

1. Restore the system age key to `/mnt/persist/var/lib/sops-nix/key.txt`.
2. Restore `/etc/machine-id` to `/mnt/persist/etc/machine-id`.
3. Restore SSH host keys to `/mnt/persist/etc/ssh/`.
4. Restore the Home Manager age key and selected personal state under `/mnt/persist/home/fbb/`.
5. Restore `nixos` and `dotfiles` checkouts from the reviewed revision and selected local state.
6. Apply UID 1000, group `users`, root ownership, and restrictive modes according to the recovery manifest.
7. Verify checksums and SSH host-key fingerprints.

### Verify SOPS

1. Confirm `/mnt/persist` is the expected Btrfs mount.
2. Confirm the system age key is a non-empty regular file owned by root with mode `0600`.
3. Run SOPS decryption checks against `secrets/common.yaml` and `secrets/hosts/rvn-pc.yaml` with output discarded.
4. Verify the `user-password-hash` field decrypts without printing it.
5. Confirm the final configuration points to `/persist/var/lib/sops-nix/key.txt`, sets `generateKey = false`, and marks the password secret `neededForUsers`.
6. Stop if any check fails. Do not reboot and do not rerun Disko.

### Install

1. Run `curl -fsSL https://nix.fbb.sh/hosts/rvn-pc/install | bash -s -- install`; it must match the immutable revision recorded by `partition`.
2. Treat every SOPS warning, missing password file, activation failure, or nonzero exit as an installation failure.
3. If installation fails, repair the mounted target or restored state and rerun only the install action.
4. Before rebooting, inspect `/mnt/boot`, `/mnt/nix`, `/mnt/persist`, the swap resume configuration, and the installed system closure.

**Exit gate:** `nixos-install` completes cleanly and the mounted target contains the expected boot files, identities, system closure, and persistent state.

## Phase 10: Validate the Installed System

### First cold boot

- [ ] Boot with the protected NTFS disks connected.
- [ ] Verify GRUB starts in UEFI mode.
- [ ] Verify `/` is tmpfs with the intended limit.
- [ ] Verify `/nix` and `/persist` are the expected Btrfs subvolumes.
- [ ] Verify the 48 GiB disk swap is active and selected for resume.
- [ ] Verify zram remains active with the intended higher priority.
- [ ] Verify `fbb` is UID 1000 and password login succeeds.
- [ ] Verify the machine ID matches the recovery manifest.
- [ ] Verify SSH host-key fingerprints match.
- [ ] Verify system and Home Manager SOPS decryption.
- [ ] Verify selected user state is present with correct ownership.

### Persistence behavior

- [ ] Create one test file in an undeclared root path.
- [ ] Create one test file in a declared persistent path.
- [ ] Cold reboot twice.
- [ ] Confirm the undeclared file disappears and the declared file survives.
- [ ] Confirm machine ID, SOPS keys, login, NetworkManager state, Tailscale state, repositories, and selected personal paths survive.
- [ ] Inspect persistent logs for Preservation, mount, SOPS, user creation, and boot errors.

### Protected disks

- [ ] Verify the protected disks still have their recorded identities, partition tables, filesystem UUIDs, and contents.
- [ ] Verify `/mnt/storage` and `/mnt/games` retain their existing automount behavior.
- [ ] Verify Disko did not modify either disk.

### Hibernation

- [ ] Test hibernation from an idle graphical session.
- [ ] Verify NVIDIA displays, audio, networking, and input devices after resume.
- [ ] Test hibernation with realistic memory use.
- [ ] Verify the disk resume device is used instead of zram.
- [ ] Cold boot after a completed resume and confirm the tmpfs root resets normally.
- [ ] Keep the recovery backup until several hibernation and cold-boot cycles pass.

### Final validation

- [ ] Build the installed `rvn-pc` configuration from `~/nixos`.
- [ ] Run focused Disko, Preservation, login, SOPS, and installer tests.
- [ ] Run repository lint and flake checks.
- [ ] Review persistent paths and remove `/var/log` or other provisional state only after diagnostics are no longer needed.

**Exit gate:** two cold boots, normal rebuild, SOPS login, identity checks, external disks, and repeated hibernation all pass.

## Recovery Rules

- If Disko fails before formatting completes, remain in the installer and inspect the target. Do not retry unchanged.
- If the custom installer endpoint changes revision between actions, stop and invoke the recorded commit directly with `nix run`.
- If formatting succeeds but restoration or SOPS verification fails, repair `/mnt/persist`. Do not rerun Disko.
- If `nixos-install` fails, keep the target mounted, correct the configuration or restored state, and rerun only installation.
- If the first boot cannot decrypt secrets or create the user, boot installer media, mount `/persist`, restore the correct age key, and rerun installation or activation from the pinned revision.
- If machine ID or SSH fingerprints differ unexpectedly, stop remote use and restore the recorded identity files before continuing.
- If hibernation fails, retain normal cold-boot operation and persistent logs. Diagnose resume, kernel, and NVIDIA behavior without weakening the persistence or login checks.

## Implementation Order

```text
Protect current work
  -> prove declarative SOPS login on current system
  -> add inactive standalone Disko output
  -> add inactive Preservation contract
  -> build and test guarded installer
  -> rehearse on disposable storage
  -> verify recovery set
  -> create and push final cutover revision
  -> update immutable Cloudflare endpoint
  -> partition NVMe
  -> restore identities and selected state
  -> verify SOPS
  -> install NixOS
  -> validate cold boots and hibernation
```

No destructive step begins until every preceding exit gate passes.
