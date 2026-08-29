#!/usr/bin/env bash
set -euo pipefail

base_url="https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap"
tmp_script="$(mktemp)"

cleanup() {
  rm -f "$tmp_script"
}
trap cleanup EXIT

is_live_iso() {
  [ -d /iso ] &&
    [ -d /nix/.ro-store ] &&
    [ "$(findmnt --noheadings --output FSTYPE /iso 2>/dev/null || true)" = "iso9660" ] &&
    [ "$(findmnt --noheadings --output FSTYPE /nix/.ro-store 2>/dev/null || true)" = "squashfs" ]
}

if [ "${BOOTSTRAP_INSTALL_TEST_MODE:-}" = "live-iso" ] || is_live_iso; then
  install_host="${NIXOS_INSTALL_HOST:-}"
  if [ -z "$install_host" ]; then
    printf 'Select the host to install:\n' >/dev/tty
    printf '  1) rvn-pc\n' >/dev/tty
    read -r -p 'Host: ' install_host </dev/tty
  fi

  case "$install_host" in
  1 | rvn-pc) script_name="install-rvn-pc.sh" ;;
  *)
    printf 'Error: unsupported installation host: %s\n' "$install_host" >&2
    exit 1
    ;;
  esac
  packages=(age gh git gnupg openssh sops util-linux)
else
  script_name="bootstrap-machine.sh"
  packages=(gh git gum openssh qrencode)
fi

curl -fsSL "$base_url/$script_name" -o "$tmp_script"

nix-shell -p "${packages[@]}" --run "bash \"$tmp_script\" </dev/tty >/dev/tty"
