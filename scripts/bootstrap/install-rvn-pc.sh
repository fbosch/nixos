#!/usr/bin/env bash
set -euo pipefail

target_device="/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746"
repository_url="https://github.com/fbosch/nixos.git"
gpg_key_id="fbb.privacy+gpg@protonmail.com"
install_root="/mnt/disko-install-root"

is_live_iso() {
  [ -d /iso ] &&
    [ -d /nix/.ro-store ] &&
    [ "$(findmnt --noheadings --output FSTYPE /iso 2>/dev/null || true)" = "iso9660" ] &&
    [ "$(findmnt --noheadings --output FSTYPE /nix/.ro-store 2>/dev/null || true)" = "squashfs" ]
}

replace_age_recipients() {
  local sops_config="$1"
  local system_recipient="$2"
  local user_recipient="$3"
  local output
  local rvn_pc_replaced="false"
  local user_replaced="false"

  output="$(mktemp "${sops_config}.XXXXXX")"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    "  - &rvn-pc age1"*)
      printf '  - &rvn-pc %s\n' "$system_recipient" >>"$output"
      rvn_pc_replaced="true"
      ;;
    "  - &fbb-user age1"*)
      printf '  - &fbb-user %s\n' "$user_recipient" >>"$output"
      user_replaced="true"
      ;;
    *) printf '%s\n' "$line" >>"$output" ;;
    esac
  done <"$sops_config"

  if [ "$rvn_pc_replaced" = "false" ] || [ "$user_replaced" = "false" ]; then
    rm -f "$output"
    printf 'Error: expected rvn-pc and fbb-user age aliases in %s\n' "$sops_config" >&2
    return 1
  fi

  chmod --reference="$sops_config" "$output"
  mv "$output" "$sops_config"
}

generate_identities() {
  local identity_tree="$1"
  local system_age_key="$identity_tree/var/lib/sops-nix/key.txt"
  local user_age_key="$identity_tree/home/fbb/.config/sops/age/keys.txt"

  install -d -m 0755 "$identity_tree/etc/ssh" "$identity_tree/var/lib/sops-nix"
  install -d -m 0700 "$identity_tree/home/fbb" "$identity_tree/home/fbb/.config/sops/age"

  tr -d '-' </proc/sys/kernel/random/uuid >"$identity_tree/etc/machine-id"
  printf '\n' >>"$identity_tree/etc/machine-id"
  chmod 0444 "$identity_tree/etc/machine-id"

  ssh-keygen -q -t ed25519 -N '' -f "$identity_tree/etc/ssh/ssh_host_ed25519_key"
  ssh-keygen -q -t rsa -b 4096 -N '' -f "$identity_tree/etc/ssh/ssh_host_rsa_key"
  chmod 0600 "$identity_tree/etc/ssh/ssh_host_ed25519_key" "$identity_tree/etc/ssh/ssh_host_rsa_key"
  chmod 0644 "$identity_tree/etc/ssh/ssh_host_ed25519_key.pub" "$identity_tree/etc/ssh/ssh_host_rsa_key.pub"

  age-keygen -o "$system_age_key" >/dev/null
  age-keygen -o "$user_age_key" >/dev/null
  chmod 0600 "$system_age_key" "$user_age_key"
}

rotate_sops_recipients() {
  local repository="$1"
  local identity_tree="$2"
  local system_age_key="$identity_tree/var/lib/sops-nix/key.txt"
  local user_age_key="$identity_tree/home/fbb/.config/sops/age/keys.txt"
  local system_recipient
  local user_recipient
  local -a secret_files

  system_recipient="$(age-keygen -y "$system_age_key")"
  user_recipient="$(age-keygen -y "$user_age_key")"
  replace_age_recipients "$repository/.sops.yaml" "$system_recipient" "$user_recipient"

  (
    cd "$repository"
    shopt -s globstar nullglob
    secret_files=(secrets/**/*.yaml)
    if [ "${#secret_files[@]}" -eq 0 ]; then
      printf 'Error: no encrypted YAML files found under %s/secrets\n' "$repository" >&2
      return 1
    fi

    for secret_file in "${secret_files[@]}"; do
      sops updatekeys --yes "$secret_file"
    done

    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt secrets/hosts/rvn-pc.yaml >/dev/null
    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt secrets/common.yaml >/dev/null
    SOPS_AGE_KEY_FILE="$user_age_key" sops --decrypt secrets/common.yaml >/dev/null
  )
}

run_disko_install() {
  local repository="$1"
  local identity_tree="$2"
  shift 2

  nix --accept-flake-config run "$repository#disko-install" -- \
    "$@" \
    --flake "$repository#rvn-pc" \
    --disk system "$target_device" \
    --mount-point "$install_root" \
    --write-efi-boot-entries \
    --extra-files "$identity_tree/." persist
}

main() {
  local work_dir
  local repository
  local identity_tree
  local confirmation

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    exec sudo --preserve-env=GPG_KEY_GIST_ID bash "$0" "$@"
  fi

  if is_live_iso; then
    :
  else
    printf 'Error: rvn-pc installation must run from the standard NixOS live ISO.\n' >&2
    exit 1
  fi

  if [ ! -d /sys/firmware/efi ]; then
    printf 'Error: the installer was not booted in UEFI mode.\n' >&2
    exit 1
  fi

  if [ ! -b "$target_device" ]; then
    printf 'Error: approved installation disk is unavailable: %s\n' "$target_device" >&2
    exit 1
  fi

  printf 'rvn-pc fresh installation\n\n'
  printf 'Target disk: %s\n' "$target_device"
  lsblk --output NAME,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS "$target_device"
  printf '\nThis creates fresh machine, SSH host, and SOPS age identities.\n'
  printf 'No recovery archive or NAS credentials are used.\n\n'

  work_dir="$(mktemp -d -t rvn-pc-install.XXXXXX)"
  chmod 0700 "$work_dir"
  repository="$work_dir/nixos"
  identity_tree="$work_dir/persist"
  cleanup() {
    rm -rf -- "$work_dir"
  }
  trap cleanup EXIT

  printf 'Cloning master...\n'
  git clone --branch master --single-branch "$repository_url" "$repository"

  generate_identities "$identity_tree"
  export GNUPGHOME="$identity_tree/home/fbb/.gnupg"
  export GH_CONFIG_DIR="$identity_tree/home/fbb/.config/gh"
  install -d -m 0700 "$GNUPGHOME" "$GH_CONFIG_DIR"

  printf '\nImporting the admin GPG recovery key for SOPS rotation...\n'
  bash "$repository/scripts/bootstrap/bootstrap-gpg.sh"
  if ! gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
    printf 'Error: required admin GPG key was not imported.\n' >&2
    exit 1
  fi

  printf '\nUpdating encrypted files for the fresh age identities...\n'
  rotate_sops_recipients "$repository" "$identity_tree"

  gpgconf --kill all >/dev/null 2>&1 || true
  rm -f "$GNUPGHOME"/S.gpg-agent*

  cp -a "$repository" "$identity_tree/home/fbb/nixos"
  chown -R 1000:100 "$identity_tree/home/fbb"

  printf '\nValidating the pinned Disko script and final host evaluation...\n'
  nix --accept-flake-config build --no-link "$repository#checks.x86_64-linux.rvn-pc-disko-script"
  nix --accept-flake-config eval --raw "$repository#nixosConfigurations.rvn-pc.config.system.build.toplevel.drvPath" >/dev/null

  printf '\nDisko dry run:\n'
  run_disko_install "$repository" "$identity_tree" --dry-run

  printf '\nWARNING: the next step permanently erases the target disk shown above.\n'
  read -r -p "Type 'ERASE rvn-pc' to install: " confirmation </dev/tty
  if [ "$confirmation" != "ERASE rvn-pc" ]; then
    printf 'Installation cancelled.\n'
    exit 0
  fi

  run_disko_install "$repository" "$identity_tree"

  printf '\nrvn-pc installation completed. Remove the ISO and reboot.\n'
}

if [ "${RVN_PC_INSTALL_LIB_ONLY:-false}" != "true" ]; then
  main "$@"
fi
