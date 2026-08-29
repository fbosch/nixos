# rvn-pc Reinstall

The standard NixOS graphical ISO installs `rvn-pc` through the same entrypoint used for ordinary host bootstrap:

```sh
curl -fsSL https://nix.fbb.sh/install | bash
```

The launcher detects the live ISO and downloads `scripts/bootstrap/install-rvn-pc.sh` from `master`. On an installed NixOS system, it continues to run the generic machine bootstrap instead.

## What It Does

The ISO installer:

1. Requires a live NixOS ISO booted in UEFI mode.
2. Refuses to continue unless the approved Western Digital NVMe exists at its fixed by-id path.
3. Clones `master` into a root-only temporary directory.
4. Generates fresh machine ID, SSH host keys, system age key, and Home Manager age key.
5. Imports the admin GPG recovery key from its encrypted gist.
6. Replaces the `rvn-pc` and `fbb-user` age recipients in `.sops.yaml` and runs `sops updatekeys` for every encrypted YAML file.
7. Verifies that both fresh age keys can decrypt the secrets needed by the final system.
8. Runs the repository-pinned upstream `disko-install` app against `.#rvn-pc`.
9. Copies the identities and modified repository to `/persist` before `nixos-install` activates the final configuration.

The installation does not use NAS credentials or a recovery archive. It creates a fresh machine identity, so SSH host fingerprints and age recipients change.

## Disk Layout

Only this device may be formatted:

```text
/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746
```

Disko creates:

- A 2 GiB FAT32 ESP.
- A 48 GiB unencrypted swap partition.
- Btrfs `/nix` and `/persist` subvolumes.
- A tmpfs root filesystem.

The Kingston games disk and Seagate storage disk are not part of the Disko configuration.

## Before Running

- Merge the installer, Disko, Preservation, and final `rvn-pc` composition to `master`.
- Do not activate that final composition on the legacy filesystem.
- Confirm the encrypted GPG gist is accessible and its passphrase is available.
- Move any personal files that must survive the reinstall separately. This installer deliberately does not restore them.

## Installation

Boot the standard graphical NixOS ISO in UEFI mode with network access, open a terminal, and run:

```sh
curl -fsSL https://nix.fbb.sh/install | bash
```

The script displays the target disk and performs a Disko dry run before asking for the exact confirmation text `ERASE rvn-pc`. Review the device path before confirming.

After `disko-install` succeeds, remove the ISO and reboot. The first boot is the full `rvn-pc` system. There is no temporary bootstrap configuration or second installation stage.

The installed repository at `~/nixos` contains the new `.sops.yaml` recipients and re-encrypted secret files as local changes. Review and commit those changes after boot so subsequent clones use the new identities.

## Failure Boundary

Failures before the final confirmation do not modify disks. The root-owned temporary directory is deleted when the script exits.

Once formatting starts, rerunning the normal installer will format the target again. Diagnose a failed post-format installation with Disko mount mode instead of confirming another format operation.
