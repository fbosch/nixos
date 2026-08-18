#!/usr/bin/env bash

set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/output.sh
. "$(dirname "$0")/lib/output.sh"

domain="${1:-example.com}"

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
  exit 0
fi

fail "The system resolver cannot resolve ${domain}"
hint "Public DNS works, so the local DNS configuration is the likely problem."
exit 2
