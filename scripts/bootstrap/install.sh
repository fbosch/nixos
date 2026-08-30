#!/usr/bin/env bash
set -euo pipefail

#                         ┌────────────────────┐
#                         │     install.sh     │
#                         └─────────┬──────────┘
#                     ┌─────────────┴─────────────┐
#                     ▼                           ▼
#        ┌────────────────────────┐  ┌────────────────────────┐
#        │ NixOS ISO              │  │ Installed NixOS        │
#        │ 1. Clone master        │  │ 1. Detect / enter host │
#        │ 2. Select host         │  │ 2. Bootstrap machine   │
#        │ 3. Prepare GPG + SOPS  │  │ 3. Rebuild host        │
#        │ 4. Preview Disko       │  └────────────────────────┘
#        └───────────┬────────────┘
#                    │
#              ┌─────┴─────┐
#              ▼           ▼
#        [--dry-run]  [ERASE host]
#              │           │
#              ▼           ▼
#            exit    [disko + nixos-install]

base_url="https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap"
repository_url="https://github.com/fbosch/nixos.git"
gpg_key_id=""
install_root="/mnt/disko-install-root"
install_user=""
install_uid=""
install_gid=""
downloaded_script=""
iso_work_dir=""
install_dry_run="${NIXOS_INSTALL_DRY_RUN:-false}"
install_host="${NIXOS_INSTALL_HOST:-}"
install_action="${NIXOS_INSTALL_ACTION:-install}"
target_device=""
target_swap_device=""
target_system_device=""
luks_device=""
luks_mapping=""
volume_group=""
disko_configuration=""
host_system=""
age_alias=""
sops_files=()
gpg_runtime_configured="false"
target_storage_active="false"
target_swap_active="false"
target_install_flake=""
resume_mountinfo_file="/proc/self/mountinfo"
resume_swaps_file="/proc/swaps"
nix_flake_args=(--extra-experimental-features "nix-command flakes" --accept-flake-config)
style_heading=""
style_erase=""
style_keep=""
style_warning=""
style_reset=""

print_help() {
  cat <<'EOF_HELP'
Usage: install.sh [resume] [--dry-run] [--host HOST]

Run from a standard NixOS ISO to install a selected host, or from an installed
NixOS system to run the machine bootstrap.

Actions:
  resume     Resume a failed encrypted ISO installation from existing storage.
             Opens and mounts the target without formatting it.

Options:
  --dry-run  Exercise the ISO flow without requiring UEFI or the target disk.
             Stops after the Disko dry run and never formats a disk.
  --host HOST
             Select an installable host from flake metadata without prompting.
  -h, --help Show this help.
EOF_HELP
}

parse_args() {
  local action_seen="false"

  while [ "$#" -gt 0 ]; do
    case "$1" in
    resume)
      if [ "$action_seen" = "true" ]; then
        printf 'Error    Only one installer action may be specified.\n' >&2
        exit 2
      fi
      install_action="$1"
      action_seen="true"
      ;;
    --dry-run) install_dry_run="true" ;;
    --host)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ $2 == -* ]]; then
        printf 'Error    --host requires a host name.\n' >&2
        exit 2
      fi
      install_host="$2"
      shift
      ;;
    --host=*)
      install_host="${1#*=}"
      if [ -z "$install_host" ]; then
        printf 'Error    --host requires a host name.\n' >&2
        exit 2
      fi
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    *)
      printf 'Error    Unknown option: %s\n' "$1" >&2
      printf '  Run with --help for usage.\n' >&2
      exit 2
      ;;
    esac
    shift
  done

  case "$install_dry_run" in
  true | false) ;;
  *)
    printf 'Error    NIXOS_INSTALL_DRY_RUN must be true or false.\n' >&2
    exit 2
    ;;
  esac

  case "$install_action" in
  install | resume) ;;
  *)
    printf 'Error    NIXOS_INSTALL_ACTION must be install or resume.\n' >&2
    exit 2
    ;;
  esac
  if [ "$install_action" = "resume" ] && [ "$install_dry_run" = "true" ]; then
    printf 'Error    --dry-run cannot be combined with resume.\n' >&2
    exit 2
  fi

  export NIXOS_INSTALL_DRY_RUN="$install_dry_run"
  export NIXOS_INSTALL_HOST="$install_host"
  export NIXOS_INSTALL_ACTION="$install_action"
}

cleanup_iso_install() {
  cleanup_gpg_runtime || true
  cleanup_target_storage || true
  if [ -n "$iso_work_dir" ]; then
    rm -rf -- "$iso_work_dir"
  fi
}

is_live_iso() {
  [ -d /iso ] &&
    [ -d /nix/.ro-store ] &&
    [ "$(findmnt --noheadings --output FSTYPE /iso 2>/dev/null || true)" = "iso9660" ] &&
    [ "$(findmnt --noheadings --output FSTYPE /nix/.ro-store 2>/dev/null || true)" = "squashfs" ]
}

is_iso_environment() {
  is_live_iso || [ "${BOOTSTRAP_INSTALL_TEST_MODE:-}" = "live-iso" ]
}

replace_age_recipient() {
  local sops_config="$1"
  local age_alias_name="$2"
  local age_recipient="$3"
  local output
  local recipient_replaced="false"

  output="$(mktemp "${sops_config}.XXXXXX")"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    "  - &$age_alias_name age1"*)
      printf '  - &%s %s\n' "$age_alias_name" "$age_recipient" >>"$output"
      recipient_replaced="true"
      ;;
    *) printf '%s\n' "$line" >>"$output" ;;
    esac
  done <"$sops_config"

  if [ "$recipient_replaced" = "false" ]; then
    rm -f "$output"
    printf 'Error    Expected %s age alias in %s.\n' "$age_alias_name" "$sops_config" >&2
    return 1
  fi

  chmod --reference="$sops_config" "$output"
  mv "$output" "$sops_config"
}

generate_identities() {
  local identity_tree="$1"
  local user="$2"
  local system_age_key="$identity_tree/var/lib/sops-nix/key.txt"
  local user_age_key="$identity_tree/home/$user/.config/sops/age/keys.txt"

  install -d -m 0755 "$identity_tree/etc/ssh" "$identity_tree/var/lib/sops-nix"
  install -d -m 0700 "$identity_tree/home/$user" "$identity_tree/home/$user/.config/sops/age"

  tr -d '\n-' </proc/sys/kernel/random/uuid >"$identity_tree/etc/machine-id"
  printf '\n' >>"$identity_tree/etc/machine-id"
  chmod 0444 "$identity_tree/etc/machine-id"

  ssh-keygen -q -t ed25519 -N '' -f "$identity_tree/etc/ssh/ssh_host_ed25519_key"
  ssh-keygen -q -t rsa -b 4096 -N '' -f "$identity_tree/etc/ssh/ssh_host_rsa_key"
  chmod 0600 "$identity_tree/etc/ssh/ssh_host_ed25519_key" "$identity_tree/etc/ssh/ssh_host_rsa_key"
  chmod 0644 "$identity_tree/etc/ssh/ssh_host_ed25519_key.pub" "$identity_tree/etc/ssh/ssh_host_rsa_key.pub"

  age-keygen -o "$system_age_key" >/dev/null
  # This single-user host deliberately uses one host identity at both SOPS key paths.
  install -m 0600 "$system_age_key" "$user_age_key"
}

configure_gpg_for_sops() {
  local gpg_home="$1"
  local gpg_binary
  local gpg_tty
  local pinentry_binary

  gpg_binary="$(command -v gpg)"
  gpg_tty="$(tty)"
  pinentry_binary="$(command -v pinentry-curses)"

  export GPG_TTY="$gpg_tty"
  export SOPS_GPG_EXEC="$gpg_binary"
  printf 'pinentry-program %s\nallow-preset-passphrase\n' "$pinentry_binary" >"$gpg_home/gpg-agent.conf"
  gpg_runtime_configured="true"
}

cleanup_gpg_runtime() {
  if [ "$gpg_runtime_configured" = "false" ]; then
    return
  fi

  gpgconf --kill all >/dev/null 2>&1 || true
  rm -f "$GNUPGHOME/gpg-agent.conf" "$GNUPGHOME"/S.gpg-agent*
  gpg_runtime_configured="false"
}

cleanup_target_storage() {
  local cleanup_failed="false"
  local mapper_device
  local pv_name
  local pv_vg

  if [ "$target_storage_active" = "false" ]; then
    return
  fi
  if [ -z "$volume_group" ] && [ -n "$luks_mapping" ] && [ -b "/dev/mapper/$luks_mapping" ]; then
    mapper_device="$(readlink -f -- "/dev/mapper/$luks_mapping")"
    while read -r pv_name pv_vg; do
      [ -n "$pv_name" ] || continue
      if [ "$(readlink -f -- "$pv_name")" = "$mapper_device" ]; then
        volume_group="$pv_vg"
        break
      fi
    done < <(pvs --noheadings --options pv_name,vg_name 2>/dev/null || true)
  fi
  if [ -z "$volume_group" ] && [ -n "$target_system_device" ] && [ -b "$target_system_device" ]; then
    volume_group="$(lvs --noheadings --options vg_name "$target_system_device" 2>/dev/null || true)"
    volume_group="${volume_group//[[:space:]]/}"
  fi

  if [ -n "$target_install_flake" ]; then
    if rm -rf -- "$target_install_flake"; then
      target_install_flake=""
    else
      printf 'Warning  Failed to remove temporary installation flake: %s\n' "$target_install_flake" >&2
      cleanup_failed="true"
    fi
  fi
  if [ "$target_swap_active" = "true" ]; then
    if swapoff "$target_swap_device"; then
      target_swap_active="false"
    else
      printf 'Warning  Failed to disable target swap: %s\n' "$target_swap_device" >&2
      cleanup_failed="true"
    fi
  fi
  if mountpoint -q "$install_root" && ! umount -R "$install_root"; then
    printf 'Warning  Failed to unmount installation root: %s\n' "$install_root" >&2
    cleanup_failed="true"
  fi
  if [ -n "$volume_group" ] && vgs "$volume_group" >/dev/null 2>&1; then
    if ! vgchange -an "$volume_group"; then
      printf 'Warning  Failed to deactivate target volume group: %s\n' "$volume_group" >&2
      cleanup_failed="true"
    fi
  fi
  if [ -n "$luks_mapping" ] && [ -b "/dev/mapper/$luks_mapping" ]; then
    if ! cryptsetup close "$luks_mapping"; then
      printf 'Warning  Failed to close target LUKS mapping: %s\n' "$luks_mapping" >&2
      cleanup_failed="true"
    fi
  fi

  if [ "$cleanup_failed" = "true" ]; then
    return 1
  fi
  target_storage_active="false"
}

acquire_install_lock() {
  exec 9>"/run/nixos-bootstrap-install.lock"
  if ! flock --nonblock 9; then
    printf 'Error    Another NixOS installer is already running.\n' >&2
    return 1
  fi
}

configure_output_style() {
  style_heading=""
  style_erase=""
  style_keep=""
  style_warning=""
  style_reset=""
  if [ -t 2 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    style_heading=$'\033[1;36m'
    style_erase=$'\033[1;31m'
    style_keep=$'\033[1;32m'
    style_warning=$'\033[1;33m'
    style_reset=$'\033[0m'
  fi
}

print_install_plan() {
  local host="$1"
  local revision="$2"
  local target_kernel_device
  local target_size
  local disk_device
  local disk_size
  local disk_type
  local layout_line
  local kept_disks="0"

  configure_output_style
  if [ -b "$target_device" ]; then
    target_kernel_device="$(readlink -f -- "$target_device")"
    target_size="$(lsblk --noheadings --nodeps --raw --output SIZE "$target_device")"
  else
    target_kernel_device="unavailable"
    target_size="unavailable"
  fi

  printf '\n%bInstallation plan%b\n' "$style_heading" "$style_reset" >&2
  printf '  Host      %s\n' "$host" >&2
  printf '  Revision  %s\n' "$revision" >&2
  printf '  Target    %s\n' "$target_device" >&2
  printf '  Device    %s\n' "$target_kernel_device" >&2
  printf '  Size      %s\n' "$target_size" >&2

  printf '\n%bCurrent target contents%b\n' "$style_heading" "$style_reset" >&2
  printf '  %b[ERASE]%b All existing partitions and data on this disk\n' "$style_erase" "$style_reset" >&2
  if [ -b "$target_device" ]; then
    while IFS= read -r layout_line; do
      printf '    %s\n' "$layout_line" >&2
    done < <(lsblk --list --paths --output NAME,SIZE,TYPE,FSTYPE "$target_device")
  else
    printf '    Target disk unavailable in dry-run mode.\n' >&2
  fi

  printf '\n%bEvaluated Disko plan%b\n' "$style_heading" "$style_reset" >&2
  printf '  Configuration  diskoConfigurations.%s\n' "$host" >&2
  printf '  Target disk    %s\n' "$target_device" >&2
  printf '  LUKS mapping   %s -> /dev/mapper/%s\n' "$luks_device" "$luks_mapping" >&2
  printf '  System device  %s\n' "$target_system_device" >&2
  printf '  Resume device  %s\n' "$target_swap_device" >&2
  printf '  Exact create, format, and mount operations were validated by Disko dry-run.\n' >&2

  printf '\n%bOther detected disks%b\n' "$style_heading" "$style_reset" >&2
  while read -r disk_device disk_type; do
    case "$disk_device" in
    /dev/loop* | /dev/ram* | /dev/zram*) continue ;;
    esac
    if [ "$disk_type" != "disk" ] || [ "$(readlink -f -- "$disk_device")" = "$target_kernel_device" ]; then
      continue
    fi
    disk_size="$(lsblk --noheadings --nodeps --raw --output SIZE "$disk_device")"
    printf '  %b[KEEP]%b  %s  %s\n' "$style_keep" "$style_reset" "$disk_device" "$disk_size" >&2
    kept_disks=$((kept_disks + 1))
  done < <(lsblk --noheadings --nodeps --paths --output NAME,TYPE)
  if [ "$kept_disks" -eq 0 ]; then
    printf '  [KEEP]  No other whole disks detected.\n' >&2
  fi

  printf '\n%bWarning%b  Only the [ERASE] disk above will be modified. [KEEP] disks will not be touched.\n' \
    "$style_warning" "$style_reset" >&2
}

rotate_sops_recipient() {
  local repository="$1"
  local identity_tree="$2"
  local user="$3"
  local age_alias_name="$4"
  shift 4
  local system_age_key="$identity_tree/var/lib/sops-nix/key.txt"
  local user_age_key="$identity_tree/home/$user/.config/sops/age/keys.txt"
  local age_recipient
  local secret_file
  local -a secret_files=("$@")

  age_recipient="$(age-keygen -y "$system_age_key")"
  replace_age_recipient "$repository/.sops.yaml" "$age_alias_name" "$age_recipient"

  (
    cd "$repository"
    if [ "${#secret_files[@]}" -eq 0 ]; then
      printf 'Error    No SOPS files configured for %s.\n' "$age_alias_name" >&2
      return 1
    fi

    for secret_file in "${secret_files[@]}"; do
      if [ ! -f "$secret_file" ]; then
        printf 'Error    Configured SOPS file does not exist: %s\n' "$secret_file" >&2
        return 1
      fi
      sops updatekeys --yes "$secret_file"
    done

    for secret_file in "${secret_files[@]}"; do
      SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt "$secret_file" >/dev/null
    done
    SOPS_AGE_KEY_FILE="$user_age_key" sops --decrypt "${secret_files[0]}" >/dev/null
  )
}

discover_install_hosts() {
  local repository="$1"

  # Keep Nix attribute interpolation literal until --apply evaluates it.
  # shellcheck disable=SC2016
  nix "${nix_flake_args[@]}" eval --raw "$repository#meta.hosts" \
    --apply 'hosts: builtins.concatStringsSep "\n" (builtins.filter (name: hosts.${name}.installation != null) (builtins.attrNames hosts))'
}

select_install_host() {
  local repository="$1"
  local selected="$install_host"
  local index
  local -a hosts=()

  mapfile -t hosts < <(discover_install_hosts "$repository")
  if [ "${#hosts[@]}" -eq 0 ]; then
    printf 'Error    No hosts with installation metadata were found.\n' >&2
    return 1
  fi

  if [ -z "$selected" ]; then
    printf 'Select the host to install\n' >/dev/tty
    for index in "${!hosts[@]}"; do
      printf '  %s. %s\n' "$((index + 1))" "${hosts[$index]}" >/dev/tty
    done
    read -r -p 'Host: ' selected </dev/tty
  fi

  if [[ $selected =~ ^[0-9]+$ ]] && [ "$selected" -ge 1 ] && [ "$selected" -le "${#hosts[@]}" ]; then
    selected="${hosts[$((selected - 1))]}"
  fi
  for index in "${!hosts[@]}"; do
    if [ "$selected" = "${hosts[$index]}" ]; then
      printf '%s\n' "$selected"
      return
    fi
  done

  printf 'Error    Unsupported installation host: %s\n' "$selected" >&2
  return 1
}

configure_install_host() {
  local repository="$1"
  local host="$2"
  local install_group
  local persist_device
  local sops_file

  disko_configuration="$host"
  host_system="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#meta.hosts.$host.system"
  )"
  install_user="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#meta.user.username"
  )"
  [[ $install_user =~ ^[a-z_][a-z0-9_-]*$ ]] || {
    printf 'Error    Global user metadata contains an invalid installation username.\n' >&2
    return 1
  }
  install_uid="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.users.users.$install_user.uid" \
      --apply builtins.toString
  )"
  install_group="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.users.users.$install_user.group"
  )"
  install_gid="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.users.groups.$install_group.gid" \
      --apply builtins.toString
  )"
  gpg_key_id="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#meta.user.gpg.fingerprint"
  )"
  age_alias="$host"
  mapfile -t sops_files < <(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#meta.hosts.$host.installation.sopsFiles" \
      --apply 'builtins.concatStringsSep "\n"'
  )
  for sops_file in "${sops_files[@]}"; do
    [ -f "$repository/$sops_file" ] || {
      printf 'Error    Host installation metadata references a missing SOPS file: %s\n' "$sops_file" >&2
      return 1
    }
  done

  target_device="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#diskoConfigurations.$disko_configuration.disko.devices.disk" \
      --apply 'disks: let names = builtins.attrNames disks; in if builtins.length names == 1 then (builtins.getAttr (builtins.head names) disks).device else throw "installer requires exactly one Disko disk"'
  )"
  luks_mapping="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.boot.initrd.luks.devices" \
      --apply 'devices: let names = builtins.attrNames devices; in if builtins.length names == 1 then builtins.head names else throw "installer requires exactly one initrd LUKS mapping"'
  )"
  luks_device="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.boot.initrd.luks.devices" \
      --apply 'devices: let names = builtins.attrNames devices; in if builtins.length names == 1 then (builtins.getAttr (builtins.head names) devices).device else throw "installer requires exactly one initrd LUKS mapping"'
  )"
  target_swap_device="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.boot.resumeDevice"
  )"
  target_system_device="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.fileSystems" \
      --apply 'fileSystems: fileSystems."/nix".device'
  )"
  persist_device="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#nixosConfigurations.$host.config.fileSystems" \
      --apply 'fileSystems: fileSystems."/persist".device'
  )"

  [[ $target_device == /dev/disk/by-id/* ]] || {
    printf 'Error    Disko target must use an approved /dev/disk/by-id path: %s\n' "$target_device" >&2
    return 1
  }
  [[ $luks_device == "$target_device"-part* ]] || {
    printf 'Error    Evaluated LUKS device is not a partition of the Disko target: %s\n' "$luks_device" >&2
    return 1
  }
  if [ "$target_system_device" != "$persist_device" ]; then
    printf 'Error    /nix and /persist must use the same persistent system device.\n' >&2
    return 1
  fi
  if [ -z "$target_swap_device" ] || [ "$target_swap_device" = "$target_system_device" ]; then
    printf 'Error    The evaluated resume device is missing or aliases the system device.\n' >&2
    return 1
  fi

}

run_disko() {
  local repository="$1"
  local _host="$2"
  shift 2

  DISKO_SKIP_SWAP=1 nix "${nix_flake_args[@]}" run "$repository#disko" -- \
    "$@" \
    --mode destroy,format,mount \
    --flake "$repository#$disko_configuration" \
    --root-mountpoint "$install_root"
}

mount_disko() {
  local repository="$1"
  local _host="$2"

  DISKO_SKIP_SWAP=1 nix "${nix_flake_args[@]}" run "$repository#disko" -- \
    --mode mount \
    --flake "$repository#$disko_configuration" \
    --root-mountpoint "$install_root"
}

verify_disko_target() {
  local repository="$1"
  local _host="$2"
  local evaluated_target

  # Keep Nix interpolation literal until --apply evaluates it.
  # shellcheck disable=SC2016
  evaluated_target="$(
    nix "${nix_flake_args[@]}" eval --raw \
      "$repository#diskoConfigurations.$disko_configuration.disko.devices.disk" \
      --apply 'disks: builtins.concatStringsSep "\n" (map (name: disks.${name}.device) (builtins.attrNames disks))'
  )"
  if [ "$evaluated_target" != "$target_device" ]; then
    printf 'Error    Installer target does not match the evaluated Disko target.\n' >&2
    printf '  Installer  %s\n' "$target_device" >&2
    printf '  Disko      %s\n' "$evaluated_target" >&2
    return 1
  fi
}

verify_target_mount() {
  local mount_path="$1"
  local expected_source="$2"
  local expected_type="$3"
  local expected_root="$4"
  local actual_root
  local actual_source

  if ! read -r actual_source actual_root < <(
    findmnt \
      --noheadings \
      --target "$mount_path" \
      --types "$expected_type" \
      --output SOURCE,FSROOT
  ); then
    printf 'Error    Unexpected source or filesystem at %s.\n' "$mount_path" >&2
    return 1
  fi
  actual_source="${actual_source%%\[*}"
  actual_root="${actual_root//[[:space:]]/}"
  if [[ $expected_source == /dev/* ]]; then
    if [ "$(readlink -f -- "$actual_source")" != "$(readlink -f -- "$expected_source")" ]; then
      printf 'Error    Unexpected filesystem source at %s: %s\n' "$mount_path" "$actual_source" >&2
      return 1
    fi
  elif [ "$actual_source" != "$expected_source" ]; then
    printf 'Error    Unexpected filesystem source at %s: %s\n' "$mount_path" "$actual_source" >&2
    return 1
  fi
  if [ "$actual_root" != "$expected_root" ]; then
    printf 'Error    Unexpected filesystem root at %s: %s\n' "$mount_path" "$actual_root" >&2
    return 1
  fi
}

verify_encrypted_storage() {
  local backing_device
  local mapper_device
  local pv_name
  local pv_rows
  local pv_vg
  local system_vg
  local swap_vg
  local pv_count=0

  cryptsetup isLuks "$luks_device" || {
    printf 'Error    Evaluated LUKS device is not a LUKS container: %s\n' "$luks_device" >&2
    return 1
  }
  if [ ! -b "/dev/mapper/$luks_mapping" ]; then
    printf 'Error    Evaluated LUKS mapping is unavailable: %s\n' "$luks_mapping" >&2
    return 1
  fi
  backing_device="$(cryptsetup status "$luks_mapping" | sed -nE 's/^[[:space:]]*device:[[:space:]]*(.*)$/\1/p')"
  if [ -z "$backing_device" ] || [ "$(readlink -f -- "$backing_device")" != "$(readlink -f -- "$luks_device")" ]; then
    printf 'Error    LUKS mapping is not backed by the evaluated target partition.\n' >&2
    return 1
  fi

  system_vg="$(lvs --noheadings --options vg_name "$target_system_device")" || {
    printf 'Error    Evaluated system device is not an active LVM logical volume: %s\n' "$target_system_device" >&2
    return 1
  }
  swap_vg="$(lvs --noheadings --options vg_name "$target_swap_device")" || {
    printf 'Error    Evaluated resume device is not an active LVM logical volume: %s\n' "$target_swap_device" >&2
    return 1
  }
  system_vg="${system_vg//[[:space:]]/}"
  swap_vg="${swap_vg//[[:space:]]/}"
  if [ -z "$system_vg" ] || [ "$system_vg" != "$swap_vg" ]; then
    printf 'Error    Evaluated system and resume devices do not share one LVM volume group.\n' >&2
    return 1
  fi
  volume_group="$system_vg"

  mapper_device="$(readlink -f -- "/dev/mapper/$luks_mapping")"
  pv_rows="$(pvs --noheadings --options pv_name,vg_name --select "vg_name=$volume_group")" || {
    printf 'Error    Failed to inspect physical volumes for volume group: %s\n' "$volume_group" >&2
    return 1
  }
  while read -r pv_name pv_vg; do
    [ -n "$pv_name" ] || continue
    pv_count=$((pv_count + 1))
    if [ "$pv_vg" != "$volume_group" ] || [ "$(readlink -f -- "$pv_name")" != "$mapper_device" ]; then
      printf 'Error    Target volume group is not backed only by the evaluated LUKS mapping.\n' >&2
      return 1
    fi
  done <<<"$pv_rows"
  if [ "$pv_count" -ne 1 ]; then
    printf 'Error    Target volume group must contain exactly one physical volume; found %s.\n' "$pv_count" >&2
    return 1
  fi
}

verify_nixos_install_interface() {
  local help_output

  if ! help_output="$(nixos-install --help 2>&1)"; then
    printf 'Error    Failed to inspect nixos-install in the ISO runtime.\n' >&2
    return 1
  fi
  for required_option in --root --flake --no-root-password --no-channel-copy --option; do
    if ! grep -Fq -- "$required_option" <<<"$help_output"; then
      printf 'Error    nixos-install does not support required option: %s\n' "$required_option" >&2
      return 1
    fi
  done
}

resolve_flake_store_path() {
  local repository="$1"
  local flake_store_path

  flake_store_path="$(
    GIT_CONFIG_COUNT=1 \
      GIT_CONFIG_KEY_0=safe.directory \
      GIT_CONFIG_VALUE_0="$repository" \
      nix "${nix_flake_args[@]}" flake metadata --json "$repository" |
      sed -nE 's/.*"path": ?"([^"]+)".*/\1/p'
  )"
  if [ -z "$flake_store_path" ] || [ ! -f "$flake_store_path/flake.nix" ]; then
    printf 'Error    Failed to resolve the installation flake to the Nix store.\n' >&2
    return 1
  fi

  printf '%s\n' "$flake_store_path"
}

run_as_install_user() {
  setpriv \
    --reuid "$install_uid" \
    --regid "$install_gid" \
    --clear-groups \
    env HOME="$install_root/persist/home/$install_user" \
    "$@"
}

validate_resume_checkout() {
  local repository="$1"
  local status
  local status_line
  local expected_path
  local actual_path
  local allowed="false"
  local -a expected_paths=(.sops.yaml "${sops_files[@]}")

  status="$(run_as_install_user git -C "$repository" status --porcelain=v1 --untracked-files=all)"
  for expected_path in "${expected_paths[@]}"; do
    if ! grep -Fqx -- " M $expected_path" <<<"$status"; then
      printf 'Error    Preserved checkout is missing the expected SOPS rotation: %s\n' "$expected_path" >&2
      return 1
    fi
  done

  while IFS= read -r status_line; do
    [ -n "$status_line" ] || continue
    actual_path="${status_line:3}"
    allowed="false"
    for expected_path in "${expected_paths[@]}"; do
      if [ "$actual_path" = "$expected_path" ] && [ "${status_line:0:2}" = " M" ]; then
        allowed="true"
        break
      fi
    done
    if [ "$allowed" = "false" ]; then
      printf 'Error    Preserved checkout contains an unexpected change: %s\n' "$status_line" >&2
      return 1
    fi
  done <<<"$status"
}

validate_resume_identities() {
  local repository="$1"
  local system_age_key="$install_root/persist/var/lib/sops-nix/key.txt"
  local user_age_key="$install_root/persist/home/$install_user/.config/sops/age/keys.txt"
  local machine_id="$install_root/persist/etc/machine-id"
  local age_recipient
  local required_file
  local secret_file
  local machine_id_value
  local machine_id_size
  local derived_public_key
  local stored_public_key
  local -a required_files=(
    "$machine_id"
    "$system_age_key"
    "$user_age_key"
    "$install_root/persist/etc/ssh/ssh_host_ed25519_key"
    "$install_root/persist/etc/ssh/ssh_host_ed25519_key.pub"
    "$install_root/persist/etc/ssh/ssh_host_rsa_key"
    "$install_root/persist/etc/ssh/ssh_host_rsa_key.pub"
  )

  for required_file in "${required_files[@]}"; do
    if [ ! -f "$required_file" ] || [ -L "$required_file" ] || [ ! -s "$required_file" ]; then
      printf 'Error    Cannot resume because a persisted identity is missing or invalid: %s\n' "$required_file" >&2
      return 1
    fi
  done
  machine_id_value="$(<"$machine_id")"
  machine_id_size="$(wc -c <"$machine_id")"
  if [ "$machine_id_size" -ne 33 ] || [[ ! $machine_id_value =~ ^[0-9a-f]{32}$ ]]; then
    printf 'Error    Cannot resume because the persisted machine ID is malformed.\n' >&2
    return 1
  fi
  if ! cmp -s "$system_age_key" "$user_age_key"; then
    printf 'Error    Cannot resume because the system and user age identities differ.\n' >&2
    return 1
  fi

  if [ "$(stat -c '%a' "$machine_id")" != "444" ] ||
    [ "$(stat -c '%a' "$system_age_key")" != "600" ] ||
    [ "$(stat -c '%a' "$user_age_key")" != "600" ]; then
    printf 'Error    Cannot resume because persisted identity permissions are unsafe.\n' >&2
    return 1
  fi
  for required_file in \
    "$install_root/persist/etc/ssh/ssh_host_ed25519_key" \
    "$install_root/persist/etc/ssh/ssh_host_rsa_key"; do
    if [ "$(stat -c '%a' "$required_file")" != "600" ]; then
      printf 'Error    Cannot resume because an SSH private key has unsafe permissions: %s\n' \
        "$required_file" >&2
      return 1
    fi
  done

  for required_file in ed25519 rsa; do
    derived_public_key="$(
      ssh-keygen -y -f "$install_root/persist/etc/ssh/ssh_host_${required_file}_key" | cut -d ' ' -f 1,2
    )"
    stored_public_key="$(cut -d ' ' -f 1,2 \
      "$install_root/persist/etc/ssh/ssh_host_${required_file}_key.pub")"
    if [ "$derived_public_key" != "$stored_public_key" ]; then
      printf 'Error    Cannot resume because an SSH public key does not match its private key: %s\n' \
        "$required_file" >&2
      return 1
    fi
  done
  if [[ $derived_public_key != ssh-rsa\ * ]]; then
    printf 'Error    Cannot resume because the persisted RSA host key has the wrong type.\n' >&2
    return 1
  fi
  derived_public_key="$(
    ssh-keygen -y -f "$install_root/persist/etc/ssh/ssh_host_ed25519_key" | cut -d ' ' -f 1,2
  )"
  if [[ $derived_public_key != ssh-ed25519\ * ]]; then
    printf 'Error    Cannot resume because the persisted Ed25519 host key has the wrong type.\n' >&2
    return 1
  fi

  age_recipient="$(age-keygen -y "$system_age_key")"
  if ! grep -Fqx -- "  - &$age_alias $age_recipient" "$repository/.sops.yaml"; then
    printf 'Error    Cannot resume because the persisted age identity does not match .sops.yaml.\n' >&2
    return 1
  fi
  for secret_file in "${sops_files[@]}"; do
    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt "$repository/$secret_file" >/dev/null
  done
  SOPS_AGE_KEY_FILE="$user_age_key" sops --decrypt "$repository/secrets/common.yaml" >/dev/null
}

verify_resume_storage_inactive() {
  local mount_line
  local mounted_device
  local mounted_target
  local swap_device
  local canonical_source
  local canonical_target
  local esp_device_id
  local luks_device_id

  if [ ! -r "$resume_mountinfo_file" ]; then
    printf 'Error    Cannot resume because the kernel mount inventory is unavailable: %s\n' \
      "$resume_mountinfo_file" >&2
    return 1
  fi
  if [ ! -r "$resume_swaps_file" ]; then
    printf 'Error    Cannot resume because the kernel swap inventory is unavailable: %s\n' \
      "$resume_swaps_file" >&2
    return 1
  fi
  if ! esp_device_id="$(lsblk --noheadings --nodeps --raw --output MAJ:MIN "${target_device}-part1")" ||
    ! luks_device_id="$(lsblk --noheadings --nodeps --raw --output MAJ:MIN "$luks_device")"; then
    printf 'Error    Cannot resume because target partition identities are unavailable.\n' >&2
    return 1
  fi
  if [ -b "/dev/mapper/$luks_mapping" ]; then
    printf 'Error    Cannot resume while the target LUKS mapping is already open: %s\n' "$luks_mapping" >&2
    return 1
  fi

  while IFS= read -r mount_line; do
    read -r _ _ mounted_device _ mounted_target _ <<<"$mount_line"
    case "$mounted_target" in
    "$install_root" | "$install_root"/*)
      printf 'Error    Cannot resume while a filesystem is mounted below the installation root: %s\n' \
        "$mounted_target" >&2
      return 1
      ;;
    esac
    if [ "$mounted_device" = "$esp_device_id" ] || [ "$mounted_device" = "$luks_device_id" ]; then
      printf 'Error    Cannot resume while a target partition is mounted elsewhere: %s\n' \
        "$mounted_target" >&2
      return 1
    fi
  done <"$resume_mountinfo_file"

  canonical_target="$(readlink -f -- "$target_swap_device" 2>/dev/null || true)"
  while read -r swap_device _; do
    [ "$swap_device" != "Filename" ] || continue
    canonical_source="$(readlink -f -- "$swap_device")"
    if { [ -n "$canonical_target" ] && [ "$canonical_source" = "$canonical_target" ]; } ||
      [ "$swap_device" = "$target_swap_device" ]; then
      printf 'Error    Cannot resume while the target swap is already active: %s\n' "$target_swap_device" >&2
      return 1
    fi
  done <"$resume_swaps_file"
}

install_nixos() {
  local repository="$1"
  local host="$2"

  nixos-install \
    --root "$install_root" \
    --flake "$repository#$host" \
    --no-root-password \
    --no-channel-copy \
    --option experimental-features "nix-command flakes" \
    --option accept-flake-config true
}

run_iso_install() {
  local host
  local repository
  local repository_flake
  local identity_tree
  local confirmation
  local repository_revision
  local disko_preflight_output

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf 'Error    The ISO runtime must be launched as root.\n' >&2
    exit 1
  fi

  if is_iso_environment; then
    :
  else
    printf 'Error    ISO installation must run from the standard NixOS live ISO.\n' >&2
    exit 1
  fi

  if ! command -v nixos-install >/dev/null 2>&1; then
    printf 'Error    nixos-install is unavailable in the ISO runtime.\n' >&2
    exit 1
  fi
  verify_nixos_install_interface
  acquire_install_lock

  if [ ! -d /sys/firmware/efi ]; then
    if [ "$install_dry_run" = "false" ]; then
      printf 'Error    The installer was not booted in UEFI mode.\n' >&2
      printf '  Reboot and select the UEFI entry for the installer media.\n' >&2
      exit 1
    fi
    printf 'Warning  UEFI firmware is unavailable; continuing because --dry-run is active.\n' >&2
  fi

  iso_work_dir="$(mktemp -d -t nixos-install.XXXXXX)"
  chmod 0700 "$iso_work_dir"
  repository="$iso_work_dir/nixos"
  identity_tree="$iso_work_dir/persist"
  trap cleanup_iso_install EXIT

  git clone --branch master --single-branch "$repository_url" "$repository"
  if ! cmp -s "$0" "$repository/scripts/bootstrap/install.sh"; then
    printf 'Error    Master changed while the installer was starting.\n' >&2
    printf '  Rerun the install command to use one consistent revision.\n' >&2
    exit 1
  fi
  repository_revision="$(git -C "$repository" rev-parse HEAD)"
  repository_flake="$(resolve_flake_store_path "$repository")"
  host="$(select_install_host "$repository")"
  configure_install_host "$repository_flake" "$host"
  if [ ! -b "$target_device" ] && [ "$install_dry_run" = "false" ]; then
    printf 'Error    Evaluated installation disk is unavailable.\n' >&2
    printf '  Expected  %s\n' "$target_device" >&2
    exit 1
  fi

  printf 'NixOS installation\n' >&2
  printf '  Host    %s\n' "$host" >&2
  printf '  Target  %s\n' "$target_device" >&2
  if [ -b "$target_device" ]; then
    lsblk --output NAME,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS "$target_device" >&2
  else
    printf 'Warning  Target disk is unavailable; continuing because --dry-run is active.\n' >&2
  fi

  generate_identities "$identity_tree" "$install_user"

  export GNUPGHOME="$identity_tree/home/$install_user/.gnupg"
  export GH_CONFIG_DIR="$identity_tree/home/$install_user/.config/gh"
  install -d -m 0700 "$GNUPGHOME" "$GH_CONFIG_DIR"
  configure_gpg_for_sops "$GNUPGHOME"

  BOOTSTRAP_GPG_CACHE_FOR_SOPS=true bash "$repository/scripts/bootstrap/bootstrap-gpg.sh"
  if ! gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
    printf 'Error    Required admin GPG key was not imported.\n' >&2
    exit 1
  fi

  rotate_sops_recipient "$repository" "$identity_tree" "$install_user" "$age_alias" "${sops_files[@]}"
  cleanup_gpg_runtime

  cp -a "$repository" "$identity_tree/home/$install_user/nixos"
  chown -R "$install_uid:$install_gid" "$identity_tree/home/$install_user"
  repository_flake="$(resolve_flake_store_path "$repository")"
  verify_disko_target "$repository_flake" "$host"

  nix "${nix_flake_args[@]}" build --no-link \
    "$repository_flake#checks.$host_system.${disko_configuration}-disko-script"
  nix "${nix_flake_args[@]}" eval --raw "$repository_flake#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null

  printf '\nWorking  Validating disk plan...\n' >&2
  if ! disko_preflight_output="$(run_disko "$repository_flake" "$host" --dry-run 2>&1)"; then
    printf 'Error    Failed to validate the Disko plan.\n' >&2
    printf '%s\n' "$disko_preflight_output" >&2
    exit 1
  fi
  printf 'Success  Validated disk plan.\n' >&2
  printf '%s\n' "$disko_preflight_output" >&2
  print_install_plan "$host" "$repository_revision"
  if [ "$install_dry_run" = "true" ]; then
    printf '\nSuccess  Dry run completed. No disk changes were made.\n'
    return
  fi

  printf '\n%bErase target disk%b\n' "$style_erase" "$style_reset" >&2
  printf '  This permanently deletes all data on %s.\n' "$target_device" >&2
  read -r -p "Type 'ERASE $host' to install: " confirmation </dev/tty
  if [ "$confirmation" != "ERASE $host" ]; then
    printf 'Info     Installation cancelled.\n'
    exit 0
  fi

  target_storage_active="true"
  run_disko "$repository_flake" "$host" --yes-wipe-all-disks
  verify_encrypted_storage
  verify_target_mount "$install_root" tmpfs tmpfs /
  verify_target_mount "$install_root/boot" "${target_device}-part1" vfat /
  verify_target_mount "$install_root/nix" "$target_system_device" btrfs /nix
  verify_target_mount "$install_root/persist" "$target_system_device" btrfs /persist
  printf '%s\n' "$repository_revision" >"$install_root/persist/.nixos-install-revision"
  chmod 0444 "$install_root/persist/.nixos-install-revision"

  swapon "$target_swap_device"
  target_swap_active="true"
  cp -a "$identity_tree/." "$install_root/persist/"
  target_install_flake="$install_root/persist/.nixos-install-flake"
  cp -a "$repository_flake" "$target_install_flake"
  install_nixos "$target_install_flake" "$host"
  if ! cleanup_target_storage; then
    printf 'Error    Installation completed, but target storage cleanup failed.\n' >&2
    exit 1
  fi
  printf '\nSuccess  Installation completed.\n'
  printf '  Remove the ISO and reboot.\n'
}

run_iso_resume() {
  local host
  local repository
  local repository_flake
  local repository_revision
  local resume_repository
  local resume_flake
  local rotation_snapshot
  local required_device
  local rotated_file
  local updated_revision

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf 'Error    The ISO runtime must be launched as root.\n' >&2
    exit 1
  fi
  if ! is_iso_environment; then
    printf 'Error    Installation can only be resumed from the standard NixOS live ISO.\n' >&2
    exit 1
  fi
  if ! command -v nixos-install >/dev/null 2>&1; then
    printf 'Error    nixos-install is unavailable in the ISO runtime.\n' >&2
    exit 1
  fi

  verify_nixos_install_interface
  acquire_install_lock

  iso_work_dir="$(mktemp -d -t nixos-install-resume.XXXXXX)"
  chmod 0700 "$iso_work_dir"
  repository="$iso_work_dir/nixos"
  trap cleanup_iso_install EXIT

  git clone --branch master --single-branch "$repository_url" "$repository"
  if ! cmp -s "$0" "$repository/scripts/bootstrap/install.sh"; then
    printf 'Error    Master changed while the installer was starting.\n' >&2
    printf '  Rerun the resume command to use one consistent revision.\n' >&2
    exit 1
  fi
  repository_revision="$(git -C "$repository" rev-parse HEAD)"
  repository_flake="$(resolve_flake_store_path "$repository")"
  host="$(select_install_host "$repository")"
  configure_install_host "$repository_flake" "$host"
  for required_device in "$target_device" "${target_device}-part1" "$luks_device"; do
    if [ ! -b "$required_device" ]; then
      printf 'Error    Cannot resume because the expected target device is unavailable: %s\n' "$required_device" >&2
      exit 1
    fi
  done
  verify_resume_storage_inactive
  verify_disko_target "$repository_flake" "$host"

  printf 'Working  Mounting the existing target filesystems...\n' >&2
  target_storage_active="true"
  mount_disko "$repository_flake" "$host"
  verify_encrypted_storage
  verify_target_mount "$install_root" tmpfs tmpfs /
  verify_target_mount "$install_root/boot" "${target_device}-part1" vfat /
  verify_target_mount "$install_root/nix" "$target_system_device" btrfs /nix
  verify_target_mount "$install_root/persist" "$target_system_device" btrfs /persist
  if [ ! -f "$install_root/persist/.nixos-install-revision" ] ||
    [ "$(<"$install_root/persist/.nixos-install-revision")" != "$repository_revision" ]; then
    printf 'Error    Resume revision does not match the revision that created the encrypted target.\n' >&2
    exit 1
  fi
  swapon "$target_swap_device"
  target_swap_active="true"

  resume_repository="$install_root/persist/home/$install_user/nixos"
  if [ ! -d "$resume_repository/.git" ]; then
    printf 'Error    Cannot resume because the preserved NixOS checkout is missing: %s\n' "$resume_repository" >&2
    exit 1
  fi

  validate_resume_checkout "$resume_repository"
  rotation_snapshot="$iso_work_dir/rotations"
  install -d -m 0700 \
    "$rotation_snapshot/secrets/hosts" \
    "$rotation_snapshot/secrets"
  for rotated_file in .sops.yaml "${sops_files[@]}"; do
    cp -- "$resume_repository/$rotated_file" "$rotation_snapshot/$rotated_file"
  done
  validate_resume_identities "$rotation_snapshot"

  printf 'Working  Updating the preserved NixOS checkout...\n' >&2
  run_as_install_user git \
    -c core.hooksPath=/dev/null \
    -c core.fsmonitor=false \
    -C "$resume_repository" \
    fetch origin "$repository_revision"
  run_as_install_user git \
    -c core.hooksPath=/dev/null \
    -c core.fsmonitor=false \
    -C "$resume_repository" \
    merge --ff-only "$repository_revision"
  updated_revision="$(run_as_install_user git -C "$resume_repository" rev-parse HEAD)"
  if [ "$updated_revision" != "$repository_revision" ]; then
    printf 'Error    Preserved checkout did not reach the selected installation revision.\n' >&2
    printf '  Expected  %s\n' "$repository_revision" >&2
    printf '  Found     %s\n' "$updated_revision" >&2
    return 1
  fi
  validate_resume_checkout "$resume_repository"
  for rotated_file in .sops.yaml "${sops_files[@]}"; do
    cp -- "$rotation_snapshot/$rotated_file" "$repository/$rotated_file"
  done

  resume_flake="$(resolve_flake_store_path "$repository")"
  verify_disko_target "$resume_flake" "$host"
  target_install_flake="$install_root/persist/.nixos-install-flake"
  rm -rf -- "$target_install_flake"
  cp -a "$resume_flake" "$target_install_flake"

  printf 'Working  Resuming nixos-install at revision %s...\n' "$repository_revision" >&2
  install_nixos "$target_install_flake" "$host"
  if ! cleanup_target_storage; then
    printf 'Error    Installation completed, but target storage cleanup failed.\n' >&2
    exit 1
  fi
  printf '\nSuccess  Installation resumed successfully.\n'
  printf '  Remove the ISO and reboot.\n'
}

run_downloaded_script() {
  local privilege="$1"
  local script_name="$2"
  shift 2

  downloaded_script="$(mktemp)"
  cleanup_download() {
    rm -f "$downloaded_script"
  }
  trap cleanup_download EXIT

  curl -fsSL "$base_url/$script_name" -o "$downloaded_script"
  if [ "$privilege" = "root" ]; then
    sudo --preserve-env=BOOTSTRAP_INSTALL_ISO_RUNTIME,GPG_KEY_GIST_ID,NIXOS_INSTALL_ACTION,NIXOS_INSTALL_DRY_RUN,NIXOS_INSTALL_HOST \
      nix-shell -p "$@" --run "bash \"$downloaded_script\" </dev/tty"
    return
  fi

  nix-shell -p "$@" --run "bash \"$downloaded_script\" </dev/tty"
}

main() {
  parse_args "$@"

  if is_iso_environment; then
    if [ "${BOOTSTRAP_INSTALL_ISO_RUNTIME:-false}" = "true" ]; then
      if [ "$install_action" = "resume" ]; then
        run_iso_resume
      else
        run_iso_install
      fi
      return
    fi

    export BOOTSTRAP_INSTALL_ISO_RUNTIME=true
    run_downloaded_script root install.sh age cryptsetup gh git gnupg lvm2 openssh pinentry-curses qrencode sops util-linux
    return
  fi

  if [ "$install_action" = "resume" ]; then
    printf 'Error    resume is only available from the NixOS ISO.\n' >&2
    exit 2
  fi

  if [ "$install_dry_run" = "true" ]; then
    printf 'Error    --dry-run is only available from the NixOS ISO.\n' >&2
    exit 2
  fi

  run_downloaded_script user bootstrap-machine.sh gh git gum openssh qrencode
}

if [ "${BOOTSTRAP_INSTALL_LIB_ONLY:-false}" != "true" ]; then
  main "$@"
fi
