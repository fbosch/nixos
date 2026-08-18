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

ensure_mullvad_dns() {
  if ! systemctl is-active --quiet mullvad-daemon.service; then
    if ip link show wg0-mullvad >/dev/null 2>&1; then
      printf 'Removing leftover wg0-mullvad link (mullvad-daemon is not running).\n'
      ip link delete wg0-mullvad
    fi
    return 0
  fi

  printf 'Mullvad: %s\n' "$(mullvad status 2>/dev/null | head -n 1)"

  # Lockdown mode blocks all traffic (including DNS) while disconnected,
  # blocked LAN sharing makes the dnsmasq LAN upstreams unreachable, and
  # custom DNS makes mullvad-daemon block plain port-53 to the LAN resolvers.
  # Recovery enforces the known-good values for all three.
  if mullvad lockdown-mode get 2>/dev/null | grep -q ': on$'; then
    printf 'Disabling Mullvad lockdown-mode (blocks all traffic while disconnected).\n'
    mullvad lockdown-mode set off
  fi

  if mullvad lan get 2>/dev/null | grep -q ': block$'; then
    printf 'Allowing Mullvad LAN sharing (LAN DNS upstreams must be reachable).\n'
    mullvad lan set allow
  fi

  if mullvad dns get 2>/dev/null | grep -q '^Custom DNS: yes$'; then
    printf 'Setting Mullvad DNS to default (custom DNS blocks LAN resolvers).\n'
    mullvad dns set default
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

wait_for_dns() {
  for _ in {1..15}; do
    if timeout 5 getent ahosts "$domain" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

case "$mode" in
dns)
  ensure_mullvad_dns
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
  ensure_mullvad_dns
  restart_dns_services
  ;;
*)
  printf 'Usage: %s <dns|full> [domain]\n' "$0" >&2
  exit 64
  ;;
esac

if wait_for_dns; then
  printf 'System resolver recovered.\n'
else
  printf 'System resolver did not recover within 15 seconds.\n' >&2
fi

bash "$(dirname "$0")/network-recovery-check.sh" "$domain"
