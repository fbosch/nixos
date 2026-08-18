#!/usr/bin/env bash

set -uo pipefail

# shellcheck source=SCRIPTDIR/../lib/output.sh
. "$(dirname "$0")/../lib/output.sh"

domain="${1:-example.com}"

section "Resolver configuration"
readlink -f /etc/resolv.conf 2>&1 || true
cat /etc/resolv.conf 2>&1 || true

section "DNS services"
systemctl --no-pager --plain status dnsmasq.service nextdns.service 2>&1 || true

section "Local DNS listeners"
ss -lntup '( sport = :53 or sport = :5553 )' 2>&1 || true

section "System resolver lookup: ${domain}"
if addresses="$(timeout 10 getent ahosts "$domain")" && [ -n "$addresses" ]; then
  ok "System resolver resolves ${domain}"
  printf '%s\n' "$addresses"
else
  fail "System resolver cannot resolve ${domain}"
fi

section "NextDNS lookup: ${domain}"
if timeout 10 dig @127.0.0.1 -p 5553 "$domain" A +time=2 +tries=1 +short 2>&1 | grep -q .; then
  ok "NextDNS resolves ${domain}"
  timeout 10 dig @127.0.0.1 -p 5553 "$domain" A +time=2 +tries=1 +short 2>&1 || true
else
  fail "NextDNS cannot resolve ${domain}"
fi

section "Mullvad DNS impact"
if systemctl is-active --quiet mullvad-daemon.service && command -v mullvad >/dev/null 2>&1; then
  mullvad status 2>&1 | head -n 1 || true
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
else
  info "mullvad-daemon is not running"
fi

section "Recent DNS service logs"
journalctl -u dnsmasq.service -u nextdns.service -n 30 --no-pager 2>&1 || true
