#!/usr/bin/env bash

set -uo pipefail

# shellcheck source=SCRIPTDIR/../lib/output.sh
. "$(dirname "$0")/../lib/output.sh"
# shellcheck disable=SC1091
# shellcheck source=SCRIPTDIR/../lib/network.sh
. "$(dirname "$0")/../lib/network.sh"

domain="${1:-example.com}"
local_domain="${LOCAL_DOMAIN:-$DEFAULT_LOCAL_DOMAIN}"

printf 'Public DNS comparison for %s\n\n' "$domain"

if public_addresses="$(timeout 10 dig @1.1.1.1 "$domain" A +time=2 +tries=1 +short)" &&
  [ -n "$public_addresses" ]; then
  ok "Cloudflare DNS at 1.1.1.1 resolves ${domain}"
else
  fail "Cloudflare DNS at 1.1.1.1 cannot resolve ${domain}"
  hint "The network, route, VPN, or firewall may be the problem."
  exit 1
fi

if system_addresses="$(timeout 10 getent ahosts "$domain")" && [ -n "$system_addresses" ]; then
  ok "The system resolver resolves ${domain}"
else
  fail "The system resolver cannot resolve ${domain}"
  hint "Public DNS works, so the local DNS configuration is the likely problem."
  exit 2
fi

# Split-horizon check: the local domain must resolve to a LAN address through
# dnsmasq, regardless of which upstream the system resolver currently uses.
if local_addresses="$(timeout 10 dig @127.0.0.1 "$local_domain" A +time=2 +tries=1 +short)" &&
  [ -n "$local_addresses" ]; then
  first_local="$(printf '%s\n' "$local_addresses" | head -n 1)"
  if is_private_ipv4 "$first_local"; then
    ok "dnsmasq resolves ${local_domain} to LAN address ${first_local}"
  else
    fail "dnsmasq resolves ${local_domain} to public address ${first_local}"
    hint "dnsmasq must forward the local zone to the LAN upstreams, not NextDNS."
    exit 3
  fi
else
  fail "dnsmasq cannot resolve ${local_domain}"
  hint "The LAN DNS upstreams or dnsmasq domain rules may be the problem."
  exit 3
fi
