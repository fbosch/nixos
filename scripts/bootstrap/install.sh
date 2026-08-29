#!/usr/bin/env bash
set -euo pipefail

# +------------------+
# | Environment      |
# +--------+---------+
#          |
#          +-- NixOS ISO
#          |     |
#          |     +-> [select host] -> [clone master] -> [import GPG]
#          |                                               |
#          |                                               v
#          |     [disko-install] <- [confirm erase] <- [SOPS + age key]
#          |
#          +-- Installed NixOS
#                |
#                +-> [bootstrap-machine] -> [rebuild selected host]

base_url="https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap"
repository_url="https://github.com/fbosch/nixos.git"
gpg_key_id="fbb.privacy+gpg@protonmail.com"
install_root="/mnt/disko-install-root"
downloaded_script=""
iso_work_dir=""

cleanup_iso_install() {
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

replace_age_recipient() {
  local sops_config="$1"
  local system_alias="$2"
  local system_recipient="$3"
  local output
  local system_replaced="false"

  output="$(mktemp "${sops_config}.XXXXXX")"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    "  - &$system_alias age1"*)
      printf '  - &%s %s\n' "$system_alias" "$system_recipient" >>"$output"
      system_replaced="true"
      ;;
    *) printf '%s\n' "$line" >>"$output" ;;
    esac
  done <"$sops_config"

  if [ "$system_replaced" = "false" ]; then
    rm -f "$output"
    printf 'Error: expected %s age alias in %s\n' "$system_alias" "$sops_config" >&2
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
  # This single-user host deliberately uses one host identity at both SOPS key paths.
  install -m 0600 "$system_age_key" "$user_age_key"
}

rotate_sops_recipients() {
  local repository="$1"
  local identity_tree="$2"
  local system_alias="$3"
  shift 3
  local system_age_key="$identity_tree/var/lib/sops-nix/key.txt"
  local user_age_key="$identity_tree/home/fbb/.config/sops/age/keys.txt"
  local system_recipient
  local secret_file
  local -a secret_files=("$@")

  system_recipient="$(age-keygen -y "$system_age_key")"
  replace_age_recipient "$repository/.sops.yaml" "$system_alias" "$system_recipient"

  (
    cd "$repository"
    if [ "${#secret_files[@]}" -eq 0 ]; then
      printf 'Error: no SOPS files configured for %s\n' "$system_alias" >&2
      return 1
    fi

    for secret_file in "${secret_files[@]}"; do
      if [ ! -f "$secret_file" ]; then
        printf 'Error: configured SOPS file does not exist: %s\n' "$secret_file" >&2
        return 1
      fi
      sops updatekeys --yes "$secret_file"
    done

    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt "${secret_files[0]}" >/dev/null
    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt secrets/common.yaml >/dev/null
    SOPS_AGE_KEY_FILE="$user_age_key" sops --decrypt secrets/common.yaml >/dev/null
  )
}

select_install_host() {
  local selected="${NIXOS_INSTALL_HOST:-}"

  if [ -z "$selected" ]; then
    printf 'Select the host to install:\n' >/dev/tty
    printf '  1) rvn-pc\n' >/dev/tty
    read -r -p 'Host: ' selected </dev/tty
  fi

  case "$selected" in
  1 | rvn-pc) printf '%s\n' rvn-pc ;;
  *)
    printf 'Error: unsupported installation host: %s\n' "$selected" >&2
    return 1
    ;;
  esac
}

configure_install_host() {
  local host="$1"

  case "$host" in
  rvn-pc)
    target_device="/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746"
    system_alias="rvn-pc"
    sops_files=(
      "secrets/hosts/rvn-pc.yaml"
      "secrets/common.yaml"
      "secrets/apis.yaml"
      "secrets/development.yaml"
    )
    ;;
  *)
    printf 'Error: missing installer configuration for host: %s\n' "$host" >&2
    return 1
    ;;
  esac
}

run_disko_install() {
  local repository="$1"
  local identity_tree="$2"
  local host="$3"
  shift 3

  nix --accept-flake-config run "$repository#disko-install" -- \
    "$@" \
    --flake "$repository#$host" \
    --disk system "$target_device" \
    --mount-point "$install_root" \
    --write-efi-boot-entries \
    --extra-files "$identity_tree/." persist
}

run_iso_install() {
  local host
  local repository
  local identity_tree
  local confirmation

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf 'Error: the ISO runtime must be launched as root.\n' >&2
    exit 1
  fi

  if is_live_iso || [ "${BOOTSTRAP_INSTALL_TEST_MODE:-}" = "live-iso" ]; then
    :
  else
    printf 'Error: ISO installation must run from the standard NixOS live ISO.\n' >&2
    exit 1
  fi

  if [ ! -d /sys/firmware/efi ]; then
    printf 'Error: the installer was not booted in UEFI mode.\n' >&2
    exit 1
  fi

  host="$(select_install_host)"
  configure_install_host "$host"
  if [ ! -b "$target_device" ]; then
    printf 'Error: approved installation disk is unavailable: %s\n' "$target_device" >&2
    exit 1
  fi

  printf '%s fresh installation\n\n' "$host"
  printf 'Target disk: %s\n' "$target_device"
  lsblk --output NAME,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS "$target_device"

  iso_work_dir="$(mktemp -d -t nixos-install.XXXXXX)"
  chmod 0700 "$iso_work_dir"
  repository="$iso_work_dir/nixos"
  identity_tree="$iso_work_dir/persist"
  trap cleanup_iso_install EXIT

  git clone --branch master --single-branch "$repository_url" "$repository"
  if ! cmp -s "$0" "$repository/scripts/bootstrap/install.sh"; then
    printf 'Error: master changed while the installer was starting; rerun the command.\n' >&2
    exit 1
  fi
  generate_identities "$identity_tree"

  export GNUPGHOME="$identity_tree/home/fbb/.gnupg"
  export GH_CONFIG_DIR="$identity_tree/home/fbb/.config/gh"
  install -d -m 0700 "$GNUPGHOME" "$GH_CONFIG_DIR"

  bash "$repository/scripts/bootstrap/bootstrap-gpg.sh"
  if ! gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
    printf 'Error: required admin GPG key was not imported.\n' >&2
    exit 1
  fi

  rotate_sops_recipients "$repository" "$identity_tree" "$system_alias" "${sops_files[@]}"
  gpgconf --kill all >/dev/null 2>&1 || true
  rm -f "$GNUPGHOME"/S.gpg-agent*

  cp -a "$repository" "$identity_tree/home/fbb/nixos"
  chown -R 1000:100 "$identity_tree/home/fbb"

  nix --accept-flake-config build --no-link "$repository#checks.x86_64-linux.${host}-disko-script"
  nix --accept-flake-config eval --raw "$repository#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null

  printf '\nDisko dry run:\n'
  run_disko_install "$repository" "$identity_tree" "$host" --dry-run

  printf '\nWARNING: the next step permanently erases the target disk shown above.\n'
  read -r -p "Type 'ERASE $host' to install: " confirmation </dev/tty
  if [ "$confirmation" != "ERASE $host" ]; then
    printf 'Installation cancelled.\n'
    exit 0
  fi

  run_disko_install "$repository" "$identity_tree" "$host"
  printf '\nInstallation completed. Remove the ISO and reboot.\n'
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
    sudo --preserve-env=BOOTSTRAP_INSTALL_ISO_RUNTIME,GPG_KEY_GIST_ID,NIXOS_INSTALL_HOST \
      nix-shell -p "$@" --run "bash \"$downloaded_script\" </dev/tty >/dev/tty"
    return
  fi

  nix-shell -p "$@" --run "bash \"$downloaded_script\" </dev/tty >/dev/tty"
}

main() {
  if is_live_iso || [ "${BOOTSTRAP_INSTALL_TEST_MODE:-}" = "live-iso" ]; then
    if [ "${BOOTSTRAP_INSTALL_ISO_RUNTIME:-false}" = "true" ]; then
      run_iso_install "$@"
      return
    fi

    export BOOTSTRAP_INSTALL_ISO_RUNTIME=true
    run_downloaded_script root install.sh age gh git gnupg openssh sops util-linux
    return
  fi

  run_downloaded_script user bootstrap-machine.sh gh git gum openssh qrencode
}

if [ "${BOOTSTRAP_INSTALL_LIB_ONLY:-false}" != "true" ]; then
  main "$@"
fi
