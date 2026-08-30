# `rvn-pc` Disk Encryption Rollout

## Status

Active. The final exit gate in
[`2026-08-28-preservation-disko-reinstall.md`](./2026-08-28-preservation-disko-reinstall.md)
has passed and its evidence has been recorded. Non-destructive contract and
layout work may proceed; production disk changes remain gated by the phases
below.

That prerequisite requires two cold boots, a normal rebuild, working SOPS and
login, stable machine and SSH identities, intact external disks, correct
Preservation behavior, and repeated hibernation on the plaintext baseline.

## Goal

Reinstall `rvn-pc` with encrypted persistent storage and encrypted hibernation
while retaining its proven tmpfs root, Preservation policy, Btrfs subvolumes,
machine identity, SSH identity, SOPS identities, user state, and protected NTFS
disks.

The rollout must first work with a LUKS passphrase. TPM2 unlock is a later,
reversible phase. Secure Boot is a separate project.

## Baseline

The prerequisite rollout establishes this layout on the approved target:

```text
GPT
├─ ESP      2 GiB, VFAT, /boot
├─ swap     48 GiB, plaintext resume device
└─ system   remaining space, Btrfs
   ├─ /nix
   └─ /persist

nodev
└─ /        tmpfs
```

The encryption rollout is another destructive reinstall. It is not a
`nixos-rebuild` migration, and generations from the plaintext layout are not
rollback targets after repartitioning.

## Decisions

| Area | Decision |
| --- | --- |
| Target host | `rvn-pc` only |
| Target disk | `/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746` |
| Encryption boundary | One LUKS2 container mapped as `cryptsystem`, covering persistent system storage and disk swap |
| Volume management | LVM volume group `rvnpc` inside LUKS2 |
| Persistent filesystem | Btrfs on `/dev/rvnpc/system`, with `/nix` and `/persist` subvolumes |
| Root | tmpfs, unchanged from the proven baseline |
| Swap | 48 GiB `/dev/rvnpc/swap` LV inside LUKS2, selected for resume |
| Boot | Existing UEFI GRUB and plaintext ESP |
| Initial unlock | Disko's direct, hidden interactive LUKS passphrase prompt |
| TPM2 | `systemd-analyze has-tpm2` reports `yes`; enrollment remains deferred until passphrase boot and encrypted resume pass |
| TPM2 PIN | None; the approved steady state is unattended TPM unlock with passphrase fallback |
| Recovery | A passphrase or recovery credential remains valid independently of TPM2 |
| Existing identities | Restore unchanged; do not generate or rotate during this reinstall |
| External NTFS disks | Connected, protected from Disko, plaintext, and out of scope |
| Secure Boot | Out of scope; plan separately after encryption and TPM behavior are stable |

## Questions To Resolve During Exploration

- [x] Select stable LUKS mapping, LVM volume group, Btrfs LV, and swap LV names.
- [x] Confirm the pinned Disko and nixpkgs option contracts for the complete
      partition to LUKS to LVM to Btrfs and swap chain.
- [x] Decide whether Disko prompts directly for the initial passphrase or reads
      a transient root-only file from installer tmpfs. Prefer the direct prompt
      unless automation has a tested need.
- [x] Use a systemd-generated recovery key stored in Bitwarden, independently
      of the target NVMe and TPM.
- [x] GPG-encrypt the LUKS header backup to admin key
      `5E0FEC74518ED5FEAA5EA33E5C49A562D850322A` before storing it under
      `/mnt/nas/backup/rvn-pc/luks/`. Do not place it in the existing plaintext
      recovery archive.
- [x] Decide whether the encryption reinstall gets a dedicated installer
      entrypoint or an explicit mode in the existing installer. Prefer a
      dedicated entrypoint if that is the clearest way to make identity
      generation and SOPS recipient rotation unreachable.
- [x] Defer the exact TPM2 PCR policy until the encrypted passphrase boot chain
      and update behavior can be measured. Do not copy a PCR list without
      testing its recovery consequences.
- [x] Do not require a TPM PIN; normal TPM boot must unlock unattended.
- [x] Bypass TPM non-destructively by selecting a retained passphrase-only GRUB
      generation and prove passphrase fallback. Do not clear or reset the TPM.
- [x] Retain the plaintext baseline and pre-encryption recovery set through
      Phase 10 and for 30 additional days.

No destructive work begins while any recovery, naming, installer, or unlock
policy question remains open.

## Candidate Layout

Validate this layout during exploration and disposable rehearsal before making
it the final contract:

```text
GPT
├─ ESP       2 GiB, VFAT, /boot, plaintext
└─ encrypted remaining space, LUKS2 mapping cryptsystem
   └─ LVM physical volume
      └─ rvnpc volume group
         ├─ swap    48 GiB LV, encrypted resume device
         └─ system  remaining space, Btrfs LV
            ├─ /nix
            └─ /persist

nodev
└─ /         tmpfs, unchanged
```

Only the ESP is intentionally plaintext on the target NVMe. The stable mapping
and volume names are `cryptsystem`, `rvnpc`, `swap`, and `system`.

## Rejected Alternatives

- **Encrypted Btrfs with plaintext swap:** rejected because hibernation writes
  memory contents, decrypted data, and credentials to plaintext swap.
- **Random-per-boot encrypted swap:** rejected because a new key cannot decrypt
  the previous hibernation image.
- **Btrfs swapfile:** rejected for this rollout because reliable hibernation
  adds physical offset management and Btrfs swapfile maintenance restrictions.
- **Two independent LUKS containers:** rejected as the default because one
  outer container guarantees one disk unlock and requires one TPM enrollment.
- **TPM-only unlocking:** rejected because firmware, TPM, policy, or motherboard
  changes must not make the disk unrecoverable.
- **SOPS key as the LUKS key:** rejected because the system SOPS identity is
  stored under `/persist`, which is unavailable until LUKS is already open.
- **In-place conversion:** rejected because the intended Disko topology and its
  failure recovery are easier to verify as a restore-based reinstall.

## Security Boundary

This rollout protects the target NVMe and its hibernation image against offline
reading while the LUKS container is closed.

It does not protect:

- the running system after LUKS has been unlocked;
- the plaintext ESP, kernel, initrd, or GRUB configuration from offline
  tampering;
- the external NTFS storage and games disks;
- secrets intentionally copied to other plaintext media;
- memory against a live attacker with equivalent privilege.

Without Secure Boot, a physical attacker can replace the plaintext boot chain
with code that records an entered LUKS passphrase. Secure Boot should address
that limitation in a separate plan after this rollout is stable.

## Safety Invariants

- Disko names exactly one physical disk: the approved WDS NVMe by-id path.
- Generated destructive commands never reference either protected NTFS disk,
  its partitions, its filesystem UUIDs, `/mnt/storage`, or `/mnt/games`.
- Expected mapper and LVM paths use exact allowlists. The current blanket
  rejection of `/dev/mapper` is not relaxed into a wildcard allowance.
- The ESP is the only intended plaintext filesystem on the target NVMe.
- Disk swap and the hibernation image remain inside the LUKS2 container.
- The evaluated resume device is the swap LV, never zram or a physical
  plaintext partition.
- LUKS unlock and LVM activation happen before resume and before `/nix` or
  `/persist` is mounted.
- `/persist` mounts before the initrd Preservation target and machine-ID
  validation, as in the proven baseline.
- The reinstall restores the existing machine ID, SSH host keys, system SOPS
  age identity, Home Manager SOPS age identity, repositories, and selected
  persistent state without changing their identities.
- The encryption installer cannot call `generate_identities`, rotate the
  `rvn-pc` SOPS recipient, or overwrite restored identity files.
- No LUKS passphrase, recovery key, token secret, or plaintext key file enters
  Git, a Nix expression, command-line arguments, shell history, logs, the Nix
  store, the generated initrd, or the existing plaintext recovery archive.
- At least one tested recovery credential remains independent of TPM2.
- TPM enrollment happens only after passphrase cold boot and encrypted
  hibernation pass.
- TPM tests never clear or reset the TPM.
- Partitioning, restoration, installation, and TPM enrollment remain separate
  actions with separate failure recovery.
- The same immutable Git revision supplies the reviewed layout and installed
  system configuration.
- No previous plaintext generation is described or presented as a rollback
  path after partitioning.

## Phase 0: Prove The Plaintext Baseline

**Outcome:** Disko, Btrfs, Preservation, SOPS, identity restoration, protected
disks, and hibernation are known to work without encryption.

- [x] Complete every item in the prerequisite plan.
- [x] Record evidence for two cold boots and repeated hibernation.
- [x] Record the evaluated filesystems, swap devices, resume device, and
      Preservation initrd ordering.
- [x] Record machine ID and public SSH host-key fingerprints.
- [x] Verify system and Home Manager SOPS decryption without printing secrets.
- [x] Verify `/home/fbb`, NetworkManager, Tailscale, repositories, and selected
      service state survive the required boots.
- [x] Verify an undeclared root file disappears after reboot.
- [x] Verify `/mnt/storage` and `/mnt/games` retain their expected identities
      and contents.
- [x] Confirm the existing verified recovery set remains available and is the
      approved pre-encryption recovery set.
- [x] Stop if any failure remains unexplained. Do not attribute an unresolved
      baseline failure to the future encryption layer.

**User-run actions:** cold boots, login, SOPS verification, hibernation, and
privileged recovery copies.

**Exit gate:** the final exit gate in the prerequisite plan has passed with
recorded evidence and a verified recovery set.

**Good commit point:** baseline fixes and validation evidence, if repository
changes were needed.

## Phase 1: Freeze The Encryption Contract

**Outcome:** one reviewed layout, unlock model, recovery model, and threat
boundary are explicit before code changes begin.

### Storage contract

- [x] Evaluate the pinned Disko support for LUKS containing an LVM physical
      volume, a swap LV, and a Btrfs LV.
- [x] Select stable names for the LUKS mapping, volume group, swap LV, and
      Btrfs LV.
- [x] Confirm the 48 GiB swap LV remains sufficient for realistic hibernation
      on this machine.
- [x] Confirm zram remains higher priority for routine swapping but is never
      selected as the resume device.
- [x] Confirm UEFI GRUB can continue loading the kernel and initrd from the
      plaintext ESP without GRUB opening LUKS.
- [x] Confirm systemd initrd supplies cryptsetup, device mapper, LVM, resume,
      and Plymouth support in the required order.
- [x] Preserve `explicitBtrfsMountHook` while the pinned util-linux and Disko
      combination can misdetect stale filesystem metadata. Remove it only when
      an upstream change and generated-script validation make it unnecessary.

### Credential contract

- [x] Select the initial interactive passphrase workflow.
- [x] Define passphrase quality requirements without recording the passphrase:
      use at least six randomly generated Diceware words.
- [x] Define the independent recovery credential and custody process: store a
      systemd-generated recovery key in Bitwarden.
- [x] Define an encrypted, off-target LUKS header-backup destination: encrypt it
      to the admin GPG key before writing it under
      `/mnt/nas/backup/rvn-pc/luks/`.
- [x] Define how credential and header recovery are tested against disposable
      media without restoring a header over the live target.
- [x] Confirm the existing plaintext recovery archive remains useful for host
      identities but is not approved for LUKS credentials or header backups.

### TPM contract

- [x] Record the observed `systemd-analyze has-tpm2` result without storing TPM
      secrets.
- [x] Defer exact PCR selection until the encrypted GRUB, kernel, initrd,
      firmware-update, and configuration-update behavior can be measured.
- [x] Require a firmware, bootloader, kernel, initrd, or selected PCR
      measurement mismatch to trigger visible passphrase fallback.
- [x] Define a non-destructive TPM bypass test using a retained passphrase-only
      GRUB generation.
- [x] Keep TPM enrollment out of the first encrypted installation revision.

### Installer contract

- [x] Select a dedicated encryption entrypoint or an explicit fail-closed mode.
- [x] Require the dedicated encryption path to make identity generation and
      SOPS recipient rotation unreachable.
- [x] Keep `inspect`, partitioning, restore verification, installation, and TPM
      enrollment as distinct actions.
- [x] Require an exact destructive confirmation phrase naming the approved
      target disk and the encrypted layout.

**User-run actions:** decide recovery custody, passphrase policy, TPM policy,
and acceptable fallback behavior.

**Exit gate:** storage names, unlock behavior, recovery custody, installer
entrypoint, and TPM exploration decisions are recorded and reviewed.

**Good commit point:** this plan updated with the resolved contract and any ADR
needed for the storage or unlock decision.

## Phase 2: Model The Inactive Encrypted Layout

**Outcome:** the encrypted Disko topology evaluates and its generated scripts
are safe without changing the installed plaintext system.

### `modules/hosts/rvn-pc/disko.nix`

- [x] Add an inactive `rvn-pc-encrypted` Disko output with one LUKS2 partition
      containing an LVM physical volume; keep the imported `rvn-pc` output on
      the proven plaintext layout.
- [x] Define one volume group with a 48 GiB swap LV and a remaining-space
      Btrfs LV.
- [x] Keep `/nix` and `/persist` as the only Btrfs subvolumes required by the
      current layout.
- [x] Keep tmpfs `/` and the ESP contract unchanged.
- [x] Set `resumeDevice = true` only on the encrypted swap LV.
- [x] Do not use random swap encryption or a swapfile.
- [x] Preserve the explicit Btrfs mount type workaround where required.
- [x] Update `approvedDevices` to distinguish physical target paths from exact
      derived mapper and LVM paths.
- [x] Parameterize the generated-script safety check with exact expected
      physical and logical device allowlists for each layout.
- [x] Keep every protected-disk identifier forbidden.
- [x] Add focused tests for the interactive LUKS topology, evaluated
      filesystems, encrypted swap and resume, and initrd LUKS/LVM support.
- [x] Add assertions that the ESP is the only plaintext target filesystem and
      that no physical partition is selected for resume.

### Generated-script review

- [x] Build both generated Disko script checks on `x86_64-linux`.
- [x] Inspect every emitted `sgdisk`, `wipefs`, `cryptsetup`, LVM, `mkfs`, `mkswap`,
      `mount`, `swapon`, and cleanup command.
- [x] Confirm destructive commands touch only the approved NVMe and expected
      logical descendants.
- [x] Confirm the protected SATA disks and their UUIDs never appear.
- [x] Confirm no credential value or credential-file contents appear.
- [x] Run Disko dry-run and save only non-secret review evidence.
- [x] Evaluate the existing installed plaintext configuration separately and
      prove this inactive work has not changed its boot behavior.

**User-run actions:** none. Do not run a mutating Disko mode in this phase.

**Exit gate:** the inactive encrypted layout evaluates, generated commands pass
the exact allowlists, and the running baseline remains unchanged.

**Good commit point:** inactive encrypted Disko topology and focused evaluation
coverage.

## Phase 3: Prove Initrd, Resume, And Preservation Ordering

**Outcome:** the evaluated boot graph unlocks storage and resumes safely before
mounting persistent filesystems.

### Boot contract

- [ ] Keep UEFI GRUB, the plaintext ESP, and existing kernel/initrd placement.
- [ ] Confirm `dm_mod`, NVMe, keyboard, cryptsetup, and LVM support are present
      in the initrd.
- [ ] Confirm systemd initrd generates the expected cryptsetup unit for the
      approved LUKS mapping.
- [ ] Confirm the LVM swap and Btrfs LVs activate after LUKS unlock.
- [ ] Confirm `boot.resumeDevice` resolves to the swap LV.
- [ ] Confirm resume runs before `/nix` and `/persist` are mounted.
- [ ] Confirm `/persist` still mounts before machine-ID validation and
      `initrd-preservation.target`.
- [ ] Confirm the SOPS age key under `/persist` is consumed only after the
      volume is unlocked and mounted.
- [ ] Confirm Plymouth presents the cryptsetup prompt and retains a usable
      console fallback.
- [ ] Do not enable TPM auto-unlock yet.

### Evaluation coverage

- [ ] Extend the Disko tests with the evaluated LUKS, LVM, swap, and resume
      contract.
- [ ] Extend the Preservation tests with the unlock to LVM to mount to
      Preservation dependency chain.
- [ ] Assert the system SOPS and SSH identity paths remain under `/persist`.
- [ ] Assert automatic SOPS key generation remains disabled.
- [ ] Assert the initrd does not contain a plaintext LUKS password or key file.
- [ ] Inspect the generated initrd contents and kernel command line for secret
      leakage and stale physical resume paths.

**User-run actions:** none until disposable boot testing. Any SOPS inspection
remains user-run and discards plaintext output.

**Exit gate:** evaluation proves unlock, LVM activation, resume, filesystem
mounting, and Preservation ordering without TPM dependence.

**Good commit point:** encrypted initrd, resume, Preservation, and identity
contract with focused tests.

## Phase 4: Build The Encryption Reinstall Workflow

**Outcome:** a guarded installer can inspect, partition, restore, install, and
clean up the encrypted target without generating new host identities.

### Installer changes

- [ ] Update or replace `configure_install_host` so swap and Btrfs sources are
      exact logical devices rather than `${target_device}-part2` and
      `${target_device}-part3`.
- [ ] Update `print_install_plan` to show the ESP, LUKS2 container, volume
      group, encrypted swap LV, Btrfs LV, and plaintext external disks.
- [ ] Keep `verify_disko_target` anchored to the approved physical NVMe.
- [ ] Extend target verification to the exact expected LUKS mapping, volume
      group, and logical volumes after partitioning.
- [ ] Update `verify_target_mount` calls for `/nix` and `/persist` to use the
      Btrfs LV and expected subvolume roots.
- [ ] Replace `target_swap_device`, direct physical `swapon`, and direct
      physical `swapoff` assumptions with the exact swap LV.
- [ ] Make cleanup disable swap, unmount the target, deactivate LVM, and close
      LUKS in a tested order without hiding the original failure.
- [ ] Keep the installer lock and immutable flake revision checks.
- [ ] Preserve the separation between partitioning and installation so failed
      restoration never causes Disko to run again.

### Identity restoration

- [ ] Do not call `generate_identities` from the encryption workflow.
- [ ] Do not call `rotate_sops_recipient` from the encryption workflow.
- [ ] Restore the installed machine ID, SSH host keys, system age key, Home
      Manager age key, repositories, and selected state from the verified
      pre-encryption recovery set.
- [ ] Verify checksums, ownership, modes, and public SSH fingerprints before
      installation.
- [ ] Refuse installation when any required identity is missing, changed, or
      symlinked unexpectedly.

### Credential handling

- [ ] Prefer Disko's interactive initial LUKS prompt.
- [ ] If a transient password file is required, create it only in installer
      tmpfs with mode `0600`, never pass the value on a command line, and remove
      it on every exit path.
- [ ] Never use an installer-only file as a runtime initrd key-file setting.
- [ ] Verify no credential value reaches command traces or logs.
- [ ] Create the LUKS header backup only after the encrypted container is
      created and only to the approved encrypted off-target destination.

### `scripts/ci/check-bootstrap-install.sh`

- [ ] Update the expected installation plan and logical device paths.
- [ ] Replace direct part2 swapoff assertions with swap-LV cleanup assertions.
- [ ] Update mount verification from physical part3 to the Btrfs LV.
- [ ] Add tests for passphrase cancellation, failed LUKS creation, failed LVM
      activation, failed restore verification, and cleanup after each failure.
- [ ] Prove the encryption path cannot call identity generation or SOPS
      recipient rotation.
- [ ] Prove inspect mode cannot prompt for or create a credential.
- [ ] Prove install mode cannot format, repartition, or enroll TPM.
- [ ] Prove protected-disk and unexpected-logical-device mismatches fail closed.

**User-run actions:** any real credential entry, cryptsetup operation, recovery
copy, header backup, SOPS verification, Disko action, or `nixos-install` run.

**Exit gate:** shell contract tests prove physical and logical device safety,
credential non-disclosure, identity preservation, action separation, and
ordered cleanup.

**Good commit point:** guarded encryption reinstall workflow, contract tests,
and operator instructions.

## Phase 5: Rehearse On Disposable Storage

**Outcome:** the complete encrypted install, unlock, Preservation, and resume
flow works without touching the workstation NVMe or production credentials.

- [ ] Use a VM disk or disposable physical device with a test-only target
      override that cannot enter the production output.
- [ ] Use disposable machine, SSH, and SOPS identities.
- [ ] Exercise inspect, partition, restore verification, install, cleanup, and
      cancellation as separate actions.
- [ ] Verify the ESP is plaintext and all swap and Btrfs data devices are below
      the LUKS mapping.
- [ ] Verify one passphrase opens the single LUKS container.
- [ ] Verify a wrong passphrase produces visible feedback and another attempt.
- [ ] Verify a hidden or failed Plymouth prompt has a documented, usable
      emergency console fallback.
- [ ] Verify LVM activation creates only the expected logical volumes.
- [ ] Verify `/` is tmpfs and `/nix` and `/persist` are the intended Btrfs
      subvolumes.
- [ ] Verify the swap LV is active, encrypted, 48 GiB, and selected for resume.
- [ ] Verify zram remains active but is not the resume target.
- [ ] Verify resume occurs before persistent filesystems are used.
- [ ] Verify declared state survives and undeclared root state disappears.
- [ ] Cold boot twice using only the passphrase path.
- [ ] Hibernate and resume repeatedly with idle and realistic memory use.
- [ ] Inspect repository files, derivations, store paths, generated initrd,
      process arguments, and retained logs for credential leakage using only
      non-secret markers in the test fixture.
- [ ] Create a disposable LUKS header backup and prove recovery against a clone
      of the disposable device. Never restore a header over the live fixture
      without a second untouched recovery copy.
- [ ] Exercise partial failures and prove rerunning installation does not
      repartition an already restored target.

**User-run actions:** disposable cryptsetup, Disko, installation, reboot,
hibernate, and header-recovery operations.

**Exit gate:** a disposable target completes two passphrase cold boots,
repeated encrypted resume, Preservation validation, failure cleanup, and cloned
header recovery with no credential leakage.

**Good commit point:** rehearsal fixes and expanded validation coverage.

## Phase 6: Prepare Recovery And The Immutable Revision

**Outcome:** the working plaintext installation can be restored onto the final
encrypted layout from one reviewed and remotely available revision.

### Recovery set

- [ ] Refresh the `rvn-pc` recovery archive from the working baseline.
- [ ] Verify machine ID, SSH host keys, both age identities, repositories, and
      selected persistent state.
- [ ] Record checksums, ownership, modes, and public SSH fingerprints.
- [ ] Verify the recovery set from standard installer media.
- [ ] Keep at least one identity recovery copy outside the target NVMe.
- [ ] Prepare the separately protected LUKS recovery credential destination.
- [ ] Prepare the separately encrypted LUKS header-backup destination.
- [ ] Do not create the production header backup before the production LUKS
      header exists.

### Final revision

- [ ] Resolve every Phase 1 question in this document.
- [ ] Build the final `rvn-pc` system closure.
- [ ] Build the focused Disko, initrd, Preservation, installer, and recovery
      checks on `x86_64-linux`.
- [ ] Run repository formatting, linting, and required flake checks.
- [ ] Inspect the generated destructive script and final diff.
- [ ] Confirm the protected disks remain absent from all generated commands.
- [ ] Confirm the final initrd contains no storage credential.
- [ ] Push the reviewed commit so installer media can fetch it by full revision.
- [ ] Do not activate the encrypted-layout revision on the plaintext installed
      system.

**User-run actions:** privileged recovery copies, SOPS checks, and verification
of the independent recovery destinations.

**Exit gate:** recovery material is verified, the immutable revision builds and
dry-runs, credentials have approved destinations, and installer media can fetch
the exact revision.

**Good commit point:** final encrypted cutover revision and pinned installer
payload.

## Phase 7: Perform The Encrypted Reinstall

All firmware, Disko, cryptsetup, LVM, SOPS, recovery-copy, `nixos-install`, and
reboot actions in this phase are user-run.

### Preflight

1. Boot standard NixOS installer media in UEFI mode with the protected disks
   connected.
2. Confirm TPM2 remains available, but do not enroll or require it.
3. Inspect the target, protected disks, removable media, immutable Git revision,
   and generated command plan.
4. Mount recovery sources outside Disko's installation root.
5. Verify the complete recovery set before any disk write.
6. Verify the independent LUKS recovery and header-backup destinations are
   available without exposing their contents in logs.
7. Stop on any disk identity, capacity, filesystem UUID, command allowlist, or
   revision mismatch.

### Partition and encrypt

1. Invoke the reviewed encryption partition action from the immutable revision.
2. Review the final physical and logical layout.
3. Enter the exact destructive confirmation phrase.
4. Enter and confirm the initial LUKS passphrase through the approved prompt.
5. Let Disko create the GPT, ESP, LUKS2 container, volume group, swap LV,
   Btrfs LV, subvolumes, and target mounts.
6. Verify only the ESP is plaintext on the target NVMe.
7. Verify the active Btrfs and swap sources are descendants of the expected
   LUKS mapping.
8. Create the production LUKS header backup at the approved encrypted off-target
   destination.
9. Do not rerun partitioning after this point unless intentionally restarting
   the encrypted installation from zero.

### Restore and install

1. Restore the machine ID, SSH host keys, system age key, Home Manager age key,
   repositories, and selected persistent state.
2. Verify checksums, modes, ownership, and SSH fingerprints.
3. Verify SOPS decryption with plaintext output discarded.
4. Verify no identity was generated or rotated by the encryption workflow.
5. Run only the install action against the same immutable revision.
6. Inspect the installed initrd, kernel command line, mount sources, resume
   device, and system closure before rebooting.
7. Close and reopen the target once from installer media using the recovery
   passphrase before relying on the installed boot path.

**Exit gate:** the encrypted target reopens with the recovery passphrase,
identities match the baseline, SOPS works, installation completes, and the
mounted target has the expected encrypted sources and resume configuration.

## Phase 8: Validate Passphrase Boot And Encrypted Resume

**Outcome:** the system is fully usable without TPM enrollment.

### First cold boot

- [ ] Confirm GRUB loads in UEFI mode from the plaintext ESP.
- [ ] Confirm Plymouth presents exactly one LUKS prompt.
- [ ] Confirm a deliberately wrong passphrase produces visible feedback and a
      safe retry.
- [ ] Confirm the console fallback can accept the passphrase if the Plymouth
      prompt is unavailable.
- [ ] Confirm the display manager appears only after storage unlock and then
      performs the separate user login.
- [ ] Verify `/` is tmpfs.
- [ ] Verify `/nix` and `/persist` are the expected Btrfs subvolumes on the
      Btrfs LV below LUKS.
- [ ] Verify disk swap is the 48 GiB LV below LUKS.
- [ ] Verify `boot.resumeDevice` names that LV and never zram.
- [ ] Verify machine ID, SSH fingerprints, SOPS identities, home state, and
      selected service state match the plaintext baseline.
- [ ] Verify `/mnt/storage` and `/mnt/games` retain their identities and data.

### Persistence and hibernation

- [ ] Create declared and undeclared state markers.
- [ ] Cold boot twice through the passphrase path.
- [ ] Confirm declared state survives and undeclared root state disappears.
- [ ] Hibernate from an idle graphical session.
- [ ] On power-up, enter the LUKS passphrase and verify the existing session
      resumes before normal filesystem use.
- [ ] Verify NVIDIA displays, audio, networking, input, and user services after
      resume.
- [ ] Repeat with realistic memory use.
- [ ] Repeat hibernation and cold boot enough times to distinguish a stable
      path from a one-off success.
- [ ] Inspect persistent logs for cryptsetup, LVM, resume, mount, Preservation,
      SOPS, and NVIDIA errors without retaining entered credentials.
- [ ] Build and validate the installed configuration from `~/nixos`.

**User-run actions:** passphrase entry, login, cold boots, SOPS checks,
hibernation, resume, and hardware validation.

**Exit gate:** two passphrase cold boots, normal rebuild, stable identities,
correct Preservation behavior, intact protected disks, and repeated encrypted
hibernation all pass without TPM.

**Good commit point:** passphrase-baseline fixes and validation coverage, if any
were needed.

## Phase 9: Enroll TPM2 As An Optional Unlock Path

**Outcome:** normal boot can unlock through TPM2 while the tested passphrase
remains a working recovery path.

### Enrollment

- [ ] Reconfirm the selected PCR policy and expected update behavior.
- [ ] Reconfirm the recovery passphrase opens the production LUKS container.
- [ ] Record current LUKS keyslot and token metadata without printing secrets.
- [ ] Enroll TPM2 into an additional LUKS2 token or keyslot using the approved
      policy.
- [ ] Do not remove or replace the recovery passphrase slot.
- [ ] Do not clear or reset the TPM.
- [ ] Record only non-secret token metadata and recovery instructions.

### Validation

- [ ] Cold boot and confirm TPM unlock reaches the display manager without a
      LUKS passphrase prompt.
- [ ] Confirm the display manager still requires the normal user login unless
      a separately approved login policy says otherwise.
- [ ] Hibernate and confirm TPM unlock permits encrypted resume.
- [ ] Use the approved non-destructive bypass to make TPM unlock unavailable.
- [ ] Confirm the machine falls back to the recovery passphrase with visible
      feedback.
- [ ] Restore normal TPM use without changing LUKS recovery slots.
- [ ] Test an expected configuration or kernel update and record whether the
      selected policy unlocks automatically or falls back as designed.
- [ ] Verify no TPM enrollment secret appears in Git, logs, the Nix store, or
      the initrd.

**User-run actions:** all `systemd-cryptenroll` or cryptsetup operations,
reboots, hibernation, and fallback tests.

**Exit gate:** TPM cold boot and encrypted resume work, deliberate TPM bypass
falls back to the retained passphrase, and update behavior matches the recorded
PCR policy.

**Good commit point:** declarative TPM initrd settings and non-secret recovery
documentation, if repository changes were required.

## Phase 10: Stabilize And Hand Off Boot Integrity

**Outcome:** encryption recovery remains tested, provisional artifacts are
removed, and boot-chain hardening has a clear boundary.

- [ ] Keep the pre-encryption recovery set until passphrase and TPM paths have
      passed repeated cold boots and hibernation cycles.
- [ ] Verify the off-target LUKS header backup and recovery credential remain
      readable under their approved custody controls.
- [ ] Repeat header recovery only against disposable cloned media.
- [ ] Remove installer-only credentials, temporary mounts, and nonessential
      diagnostic artifacts.
- [ ] Review logs and the Nix store one final time for credential leakage.
- [ ] Record the final disk, mapping, LVM, filesystem, resume, keyslot, and token
      metadata without secrets.
- [ ] Record the exact recovery procedure for TPM failure, firmware change,
      damaged initrd, and unavailable Plymouth prompt.
- [ ] Open a separate Secure Boot plan if protection against offline boot-chain
      tampering is required.
- [ ] Do not represent TPM auto-unlock without authenticated boot as protection
      against a modified plaintext bootloader or initrd.

**User-run actions:** recovery-material verification, disposable header test,
and any future firmware or Secure Boot work.

**Exit gate:** passphrase and TPM recovery paths remain tested, no credential
leak is found, recovery metadata is current, and Secure Boot remains explicitly
separate.

## Recovery Rules

- If baseline validation fails, stop this rollout and repair the plaintext
  baseline before adding encryption.
- If Disko dry-run or generated-script review references an unexpected physical
  or logical device, stop. Do not weaken the allowlist.
- If LUKS formatting fails, remain in installer media and inspect the approved
  target. Do not retry an unchanged destructive action.
- If LVM or Btrfs creation fails after LUKS succeeds, retain the original error
  and inspect the partial mapping before cleanup.
- If identity restoration or SOPS verification fails, repair the mounted
  encrypted target. Do not rerun partitioning.
- If `nixos-install` fails, keep the target mounted, correct the restored state
  or configuration, and rerun only installation.
- If the first boot prompt is invisible, use the documented console fallback.
  Do not assume the machine is hung while a hidden password request is active.
- If passphrase boot fails, return to installer media, open LUKS with the
  independent recovery credential, activate LVM, and inspect the installed
  initrd and crypttab contract.
- If encrypted resume fails, retain cold-boot operation and diagnose unlock,
  LVM activation, resume ordering, swap selection, kernel, and NVIDIA behavior.
  Do not move swap outside encryption to obtain a pass.
- If TPM unlock fails, enter the retained passphrase. Do not clear the TPM or
  delete the recovery keyslot while diagnosing policy mismatch.
- If the LUKS header is damaged, test recovery against a cloned device before
  any header restore against the production target.
- If the target was repartitioned, rollback means restore and reinstall from
  recovery media. Selecting an old plaintext generation is not a rollback.
- If a protected NTFS disk changes identity or contents, stop all target-disk
  work and treat it as a safety incident.

## Implementation Order

```text
Complete and prove the plaintext Preservation baseline
  -> freeze encryption, recovery, naming, installer, and TPM contracts
  -> model the inactive LUKS2 and LVM Disko layout
  -> prove initrd unlock, resume, mount, and Preservation ordering
  -> build the identity-preserving encryption installer
  -> rehearse with disposable storage and identities
  -> refresh recovery material and push one immutable revision
  -> partition and encrypt the approved NVMe
  -> back up the production LUKS header off-target
  -> restore existing identities and persistent state
  -> install and prove passphrase cold boot
  -> prove repeated encrypted hibernation
  -> enroll TPM2 without removing the recovery passphrase
  -> prove TPM bypass and passphrase fallback
  -> stabilize recovery evidence
  -> plan Secure Boot separately if required
```

No encrypted-layout implementation begins until the plaintext prerequisite
gate passes. No production TPM enrollment begins until passphrase boot and
encrypted hibernation pass.
