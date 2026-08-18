#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"
domain="${2:-example.com}"

wait_for_default_route() {
  for _ in {1..20}; do
    if [ -n "$(ip route show default)" ]; then
      return 0
    fi
    sleep 1
  done

  return 1
}

report_mullvad_state() {
  if ! systemctl is-active --quiet mullvad-daemon.service; then
    if ip link show wg0-mullvad >/dev/null 2>&1; then
      printf 'Removing leftover wg0-mullvad link (mullvad-daemon is not running).\n'
      ip link delete wg0-mullvad
    fi
    return 0
  fi

  printf 'Mullvad: %s\n' "$(mullvad status 2>/dev/null | head -n 1)"

  if mullvad lockdown-mode get 2>/dev/null | grep -q ': on$'; then
    printf 'Mullvad lockdown-mode is on: all traffic is blocked while disconnected.\n' >&2
    printf 'Fix with: mullvad lockdown-mode set off\n' >&2
  fi

  if mullvad lan get 2>/dev/null | grep -q ': block$'; then
    printf 'Mullvad LAN sharing is blocked: LAN DNS upstreams are unreachable.\n' >&2
    printf 'Fix with: mullvad lan set allow\n' >&2
  fi
}

restart_dns_services() {
  printf 'Restarting local DNS services...\n'
  # nextdns first: it wedges on stale tunnel sockets after Mullvad reconnects,
  # and dnsmasq must not forward to it before it is fresh.
  systemctl restart nextdns.service
  systemctl restart dnsmasq.service
  resolvectl flush-caches
}

case "$mode" in
dns)
  report_mullvad_state
  restart_dns_services
  ;;
full)
  printf 'Restarting NetworkManager...\n'
  systemctl restart NetworkManager.service
  if wait_for_default_route; then
    printf 'Default route restored.\n'
  else
    printf 'No default route after 20 seconds.\n' >&2
  fi
  report_mullvad_state
  restart_dns_services
  ;;
*)
  printf 'Usage: %s <dns|full> [domain]\n' "$0" >&2
  exit 64
  ;;
esac

bash "$(dirname "$0")/network-recovery-check.sh" "$domain"
