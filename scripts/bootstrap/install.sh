#!/usr/bin/env bash
set -euo pipefail

#                         ┌────────────────────┐
#                         │     install.sh     │
#                         └─────────┬──────────┘
#                     ┌─────────────┴─────────────┐
#                     ▼                           ▼
#        ┌────────────────────────┐  ┌────────────────────────┐
#        │ NixOS ISO              │  │ Installed NixOS        │
#        │ 1. Select host         │  │ 1. Detect / enter host │
#        │ 2. Clone master        │  │ 2. Bootstrap machine   │
#        │ 3. Prepare GPG + SOPS  │  │ 3. Rebuild host        │
#        │ 4. Preview Disko       │  └────────────────────────┘
#        └───────────┬────────────┘
#                    │
#              ┌─────┴─────┐
#              ▼           ▼
#        [--dry-run]  [ERASE host]
#              │           │
#              ▼           ▼
#            exit    [disko-install]

base_url="https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap"
repository_url="https://github.com/fbosch/nixos.git"
gpg_key_id="fbb.privacy+gpg@protonmail.com"
install_root="/mnt/disko-install-root"
install_user="fbb"
install_uid="1000"
install_gid="100"
downloaded_script=""
iso_work_dir=""
install_dry_run="${NIXOS_INSTALL_DRY_RUN:-false}"
install_host="${NIXOS_INSTALL_HOST:-}"
target_device=""
age_alias=""
sops_files=()
gpg_runtime_configured="false"

print_help() {
  cat <<'EOF_HELP'
Usage: install.sh [--dry-run] [--host HOST]

Run from a standard NixOS ISO to install a selected host, or from an installed
NixOS system to run the machine bootstrap.

Options:
  --dry-run  Exercise the ISO flow without requiring UEFI or the target disk.
             Stops after the Disko dry run and never formats a disk.
  --host HOST
             Select HOST without prompting. ISO installation supports rvn-pc.
  -h, --help Show this help.
EOF_HELP
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
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

  export NIXOS_INSTALL_DRY_RUN="$install_dry_run"
  export NIXOS_INSTALL_HOST="$install_host"
}

cleanup_iso_install() {
  cleanup_gpg_runtime
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
  printf 'pinentry-program %s\n' "$pinentry_binary" >"$gpg_home/gpg-agent.conf"
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

    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt "${secret_files[0]}" >/dev/null
    SOPS_AGE_KEY_FILE="$system_age_key" sops --decrypt secrets/common.yaml >/dev/null
    SOPS_AGE_KEY_FILE="$user_age_key" sops --decrypt secrets/common.yaml >/dev/null
  )
}

select_install_host() {
  local selected="$install_host"

  if [ -z "$selected" ]; then
    printf 'Select the host to install\n' >/dev/tty
    printf '  1. rvn-pc\n' >/dev/tty
    read -r -p 'Host: ' selected </dev/tty
  fi

  case "$selected" in
  1 | rvn-pc) printf '%s\n' rvn-pc ;;
  *)
    printf 'Error    Unsupported installation host: %s\n' "$selected" >&2
    return 1
    ;;
  esac
}

configure_install_host() {
  local host="$1"

  case "$host" in
  rvn-pc)
    target_device="/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746"
    age_alias="rvn-pc"
    sops_files=(
      "secrets/hosts/rvn-pc.yaml"
      "secrets/common.yaml"
      "secrets/apis.yaml"
      "secrets/development.yaml"
    )
    ;;
  *)
    printf 'Error    Missing installer configuration for host: %s\n' "$host" >&2
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
    printf 'Error    The ISO runtime must be launched as root.\n' >&2
    exit 1
  fi

  if is_iso_environment; then
    :
  else
    printf 'Error    ISO installation must run from the standard NixOS live ISO.\n' >&2
    exit 1
  fi

  if [ ! -d /sys/firmware/efi ]; then
    if [ "$install_dry_run" = "false" ]; then
      printf 'Error    The installer was not booted in UEFI mode.\n' >&2
      printf '  Reboot and select the UEFI entry for the installer media.\n' >&2
      exit 1
    fi
    printf 'Warning  UEFI firmware is unavailable; continuing because --dry-run is active.\n' >&2
  fi

  host="$(select_install_host)"
  configure_install_host "$host"
  if [ ! -b "$target_device" ] && [ "$install_dry_run" = "false" ]; then
    printf 'Error    Approved installation disk is unavailable.\n' >&2
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
  generate_identities "$identity_tree" "$install_user"

  export GNUPGHOME="$identity_tree/home/$install_user/.gnupg"
  export GH_CONFIG_DIR="$identity_tree/home/$install_user/.config/gh"
  install -d -m 0700 "$GNUPGHOME" "$GH_CONFIG_DIR"
  configure_gpg_for_sops "$GNUPGHOME"

  bash "$repository/scripts/bootstrap/bootstrap-gpg.sh"
  if ! gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
    printf 'Error    Required admin GPG key was not imported.\n' >&2
    exit 1
  fi

  rotate_sops_recipient "$repository" "$identity_tree" "$install_user" "$age_alias" "${sops_files[@]}"
  cleanup_gpg_runtime

  cp -a "$repository" "$identity_tree/home/$install_user/nixos"
  chown -R "$install_uid:$install_gid" "$identity_tree/home/$install_user"

  nix --accept-flake-config build --no-link "$repository#checks.x86_64-linux.${host}-disko-script"
  nix --accept-flake-config eval --raw "$repository#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null

  printf '\nDisko preview\n' >&2
  run_disko_install "$repository" "$identity_tree" "$host" --dry-run
  if [ "$install_dry_run" = "true" ]; then
    printf '\nSuccess  Dry run completed. No disk changes were made.\n'
    return
  fi

  printf '\nWarning  The next step permanently erases the target disk shown above.\n' >&2
  read -r -p "Type 'ERASE $host' to install: " confirmation </dev/tty
  if [ "$confirmation" != "ERASE $host" ]; then
    printf 'Info     Installation cancelled.\n'
    exit 0
  fi

  run_disko_install "$repository" "$identity_tree" "$host"
  printf '\nSuccess  Installation completed.\n'
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
    sudo --preserve-env=BOOTSTRAP_INSTALL_ISO_RUNTIME,GPG_KEY_GIST_ID,NIXOS_INSTALL_DRY_RUN,NIXOS_INSTALL_HOST \
      nix-shell -p "$@" --run "bash \"$downloaded_script\" </dev/tty"
    return
  fi

  nix-shell -p "$@" --run "bash \"$downloaded_script\" </dev/tty"
}

main() {
  parse_args "$@"

  if is_iso_environment; then
    if [ "${BOOTSTRAP_INSTALL_ISO_RUNTIME:-false}" = "true" ]; then
      run_iso_install "$@"
      return
    fi

    export BOOTSTRAP_INSTALL_ISO_RUNTIME=true
    run_downloaded_script root install.sh age gh git gnupg openssh pinentry-curses qrencode sops util-linux
    return
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
