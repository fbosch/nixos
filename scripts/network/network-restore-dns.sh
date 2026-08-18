#!/usr/bin/env bash

# Align running Mullvad settings with the declarative values in flake.meta.vpn.mullvad.

set -euo pipefail

# shellcheck source=SCRIPTDIR/../lib/output.sh
. "$(dirname "$0")/../lib/output.sh"

domain="${1:-example.com}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

if ! systemctl is-active --quiet mullvad-daemon.service; then
  info "mullvad-daemon is not running; nothing to align"
  exit 0
fi

if ! desired="$(nix eval --json "${repo_root}#meta.vpn.mullvad" 2>/dev/null)"; then
  fail "Cannot evaluate flake meta (nix eval failed)"
  hint "Run from the nixos repo, or fix the flake evaluation error."
  exit 1
fi

want_lan="$(printf '%s' "$desired" | python3 -c 'import json,sys; print("allow" if json.load(sys.stdin)["allowLan"] else "block")')"
want_lockdown="$(printf '%s' "$desired" | python3 -c 'import json,sys; print("on" if json.load(sys.stdin)["lockdownMode"] else "off")')"

section "Mullvad alignment with flake.meta.vpn.mullvad"
printf 'Mullvad: %s\n' "$(mullvad status 2>/dev/null | head -n 1)"

if mullvad lan get 2>/dev/null | grep -q ": ${want_lan}\$"; then
  ok "LAN sharing already ${want_lan}"
else
  printf 'Setting LAN sharing to %s...\n' "$want_lan"
  mullvad lan set "$want_lan"
  ok "LAN sharing set to ${want_lan}"
fi

if mullvad lockdown-mode get 2>/dev/null | grep -q ": ${want_lockdown}\$"; then
  ok "Lockdown mode already ${want_lockdown}"
else
  printf 'Setting lockdown mode to %s...\n' "$want_lockdown"
  mullvad lockdown-mode set "$want_lockdown"
  ok "Lockdown mode set to ${want_lockdown}"
fi

bash "$(dirname "$0")/network-recovery-check.sh" "$domain"
