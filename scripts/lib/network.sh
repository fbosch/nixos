#!/usr/bin/env bash
# Shared network helpers for diagnostic scripts.
# Source this file: . "$(dirname "$0")/lib/network.sh"

# Local split-horizon domain that should resolve to a LAN address.
DEFAULT_LOCAL_DOMAIN="glance.corvus-corax.synology.me"

# Whether an IPv4 address is RFC1918 private (LAN-routable).
is_private_ipv4() {
  case "$1" in
  10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
  *) return 1 ;;
  esac
}
