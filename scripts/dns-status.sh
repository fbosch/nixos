#!/usr/bin/env bash

set -uo pipefail

domain="${1:-example.com}"

section() {
	printf '\n== %s ==\n' "$1"
}

section "Resolver configuration"
readlink -f /etc/resolv.conf 2>&1 || true
cat /etc/resolv.conf 2>&1 || true

section "DNS services"
systemctl --no-pager --plain status dnsmasq.service nextdns.service 2>&1 || true

section "Local DNS listeners"
ss -lntup '( sport = :53 or sport = :5553 )' 2>&1 || true

section "System resolver lookup: ${domain}"
timeout 10 getent ahosts "$domain" 2>&1 || true

section "NextDNS lookup: ${domain}"
timeout 10 dig @127.0.0.1 -p 5553 "$domain" A +time=2 +tries=1 2>&1 || true

section "Recent DNS service logs"
journalctl -u dnsmasq.service -u nextdns.service -n 30 --no-pager 2>&1 || true
