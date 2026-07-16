#!/usr/bin/env bash

set -uo pipefail

domain="${1:-example.com}"
failures=0

if [ -t 1 ]; then
	bold=$'\033[1m'
	cyan=$'\033[36m'
	green=$'\033[32m'
	yellow=$'\033[33m'
	red=$'\033[31m'
	reset=$'\033[0m'
else
	bold=""
	cyan=""
	green=""
	yellow=""
	red=""
	reset=""
fi

ok() {
	printf '%s[ OK ]%s %s\n' "$green" "$reset" "$1"
}

fail() {
	printf '%s[FAIL]%s %s\n' "$red" "$reset" "$1"
	failures=$((failures + 1))
}

info() {
	printf '%s[INFO]%s %s\n' "$yellow" "$reset" "$1"
}

section() {
	printf '\n%s%s%s\n' "$bold$cyan" "$1" "$reset"
}

section "Link and addressing"
ip -brief link
ip -brief address

section "Default route"
if default_route="$(ip route show default)" && [ -n "$default_route" ]; then
	ok "$default_route"
else
	fail "No IPv4 default route"
fi

section "Internet transport"
if curl --connect-timeout 5 --max-time 10 --fail --silent --show-error \
	--resolve one.one.one.one:443:1.1.1.1 \
	--output /dev/null https://one.one.one.one/cdn-cgi/trace; then
	ok "HTTPS reachable without DNS"
else
	fail "HTTPS unreachable without DNS"
fi

section "DNS"
if addresses="$(timeout 10 getent ahosts "$domain")" && [ -n "$addresses" ]; then
	ok "${domain} resolves"
	printf '%s\n' "$addresses"
else
	fail "${domain} does not resolve through the system resolver"
fi

section "DNS services"
for service in dnsmasq.service nextdns.service; do
	if systemctl is-active --quiet "$service"; then
		ok "$service is active"
	else
		fail "$service is inactive"
	fi
done

section "VPN"
for service in mullvad-daemon.service tailscaled.service; do
	if systemctl is-active --quiet "$service"; then
		ok "$service is active"
	else
		info "$service is inactive"
	fi
done
ip -brief link show type wireguard 2>/dev/null || true

section "Summary"
if [ "$failures" -eq 0 ]; then
	ok "Network checks passed"
else
	fail "${failures} issue(s) detected"
fi
