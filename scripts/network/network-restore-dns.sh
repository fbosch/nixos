#!/usr/bin/env bash

# Align running Mullvad settings with the declarative values in
# services.mullvad-vpn.runtimeSettings (modules/vpn.nix).

set -euo pipefail

# shellcheck disable=SC1091
# shellcheck source=SCRIPTDIR/../lib/output.sh
. "$(dirname "$0")/../lib/output.sh"

domain="${1:-example.com}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

if ! systemctl is-active --quiet mullvad-daemon.service; then
  info "mullvad-daemon is not running; nothing to align"
  exit 0
fi

host="$(hostname)"
if ! desired="$(nix eval --json "${repo_root}#nixosConfigurations.${host}.config.services.mullvad-vpn.runtimeSettings" 2>/dev/null)"; then
  fail "Cannot evaluate mullvad-vpn runtimeSettings (nix eval failed)"
  hint "Run from the nixos repo, or fix the flake evaluation error."
  exit 1
fi

want_lan="$(printf '%s' "$desired" | python3 -c 'import json,sys; print("allow" if json.load(sys.stdin)["allowLan"] else "block")')"
want_lockdown="$(printf '%s' "$desired" | python3 -c 'import json,sys; print("on" if json.load(sys.stdin)["lockdownMode"] else "off")')"
want_dns="$(printf '%s' "$desired" | python3 -c 'import json,sys; print(json.load(sys.stdin)["dnsMode"])')"

section "Mullvad alignment with services.mullvad-vpn.runtimeSettings"
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

if mullvad dns get 2>/dev/null | grep -qi "^${want_dns} DNS: yes\$"; then
  ok "DNS mode already ${want_dns}"
else
  printf 'Setting DNS mode to %s...\n' "$want_dns"
  mullvad dns set "$want_dns"
  ok "DNS mode set to ${want_dns}"
fi

bash "$(dirname "$0")/network-recovery-check.sh" "$domain"
