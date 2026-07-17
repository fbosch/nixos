#!/usr/bin/env bash

set -uo pipefail

domain="${1:-example.com}"

if [ -t 1 ]; then
  green=$'\033[32m'
  red=$'\033[31m'
  reset=$'\033[0m'
else
  green=""
  red=""
  reset=""
fi

ok() {
  printf '%s[ OK ]%s %s\n' "$green" "$reset" "$1"
}

fail() {
  printf '%s[FAIL]%s %s\n' "$red" "$reset" "$1"
}

printf 'Public DNS comparison for %s\n\n' "$domain"

if public_addresses="$(timeout 10 dig @1.1.1.1 "$domain" A +time=2 +tries=1 +short)" &&
  [ -n "$public_addresses" ]; then
  ok "Cloudflare DNS at 1.1.1.1 resolves ${domain}"
else
  fail "Cloudflare DNS at 1.1.1.1 cannot resolve ${domain}"
  printf 'The network, route, VPN, or firewall may be the problem.\n'
  exit 1
fi

if system_addresses="$(timeout 10 getent ahosts "$domain")" && [ -n "$system_addresses" ]; then
  ok "The system resolver resolves ${domain}"
  exit 0
fi

fail "The system resolver cannot resolve ${domain}"
printf 'Public DNS works, so the local DNS configuration is the likely problem.\n'
exit 2
