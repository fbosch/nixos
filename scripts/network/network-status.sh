#!/usr/bin/env bash

set -uo pipefail

# shellcheck source=SCRIPTDIR/../lib/output.sh
. "$(dirname "$0")/../lib/output.sh"
# shellcheck source=SCRIPTDIR/../lib/network.sh
. "$(dirname "$0")/../lib/network.sh"

domain="${1:-example.com}"
local_domain="${LOCAL_DOMAIN:-$DEFAULT_LOCAL_DOMAIN}"
failures=0

check_fail() {
  failures=$((failures + 1))
  fail "$1"
}

section "Link and addressing"
ip -brief link
ip -brief address

section "Default route"
if default_route="$(ip route show default)" && [ -n "$default_route" ]; then
  ok "$default_route"
else
  check_fail "No IPv4 default route"
fi

section "Internet transport"
if curl --connect-timeout 5 --max-time 10 --fail --silent --show-error \
  --resolve one.one.one.one:443:1.1.1.1 \
  --output /dev/null https://one.one.one.one/cdn-cgi/trace; then
  ok "HTTPS reachable without DNS"
else
  check_fail "HTTPS unreachable without DNS"
fi

section "DNS"
if addresses="$(timeout 10 getent ahosts "$domain")" && [ -n "$addresses" ]; then
  ok "${domain} resolves"
  printf '%s\n' "$addresses"
else
  check_fail "${domain} does not resolve through the system resolver"
fi

section "DNS services"
for service in dnsmasq.service nextdns.service; do
  if systemctl is-active --quiet "$service"; then
    ok "$service is active"
  else
    check_fail "$service is inactive"
  fi
done

section "Local split-horizon DNS"
if local_addresses="$(timeout 10 dig @127.0.0.1 "$local_domain" A +time=2 +tries=1 +short)" &&
  [ -n "$local_addresses" ]; then
  first_local="$(printf '%s\n' "$local_addresses" | head -n 1)"
  if is_private_ipv4 "$first_local"; then
    ok "dnsmasq resolves ${local_domain} to LAN address ${first_local}"
  else
    check_fail "dnsmasq resolves ${local_domain} to public address ${first_local}"
    hint "dnsmasq must forward the local zone to the LAN upstreams, not NextDNS."
  fi
else
  check_fail "dnsmasq cannot resolve ${local_domain}"
  hint "The LAN DNS upstreams or dnsmasq domain rules may be the problem."
fi

section "VPN"
for service in mullvad-daemon.service tailscaled.service; do
  if systemctl is-active --quiet "$service"; then
    ok "$service is active"
  else
    info "$service is inactive"
  fi
done
if systemctl is-active --quiet mullvad-daemon.service && command -v mullvad >/dev/null 2>&1; then
  mullvad status 2>/dev/null | head -n 1 || true
  if mullvad lockdown-mode get 2>/dev/null | grep -q ': on$'; then
    info "Lockdown mode is on: all traffic is blocked while disconnected"
    hint "fix: mullvad lockdown-mode set off"
  else
    ok "Lockdown mode is off"
  fi
  if mullvad lan get 2>/dev/null | grep -q ': block$'; then
    info "LAN sharing is blocked: LAN DNS upstreams are unreachable"
    hint "fix: mullvad lan set allow"
  else
    ok "LAN sharing is allowed"
  fi
fi
ip -brief link show type wireguard 2>/dev/null || true

section "Summary"
if [ "$failures" -eq 0 ]; then
  ok "Network checks passed"
else
  check_fail "${failures} issue(s) detected"
fi
