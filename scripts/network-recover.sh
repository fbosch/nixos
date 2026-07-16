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

case "$mode" in
	dns)
		printf 'Restarting local DNS services...\n'
		systemctl restart nextdns.service dnsmasq.service
		;;
	full)
		printf 'Restarting NetworkManager...\n'
		systemctl restart NetworkManager.service
		if wait_for_default_route; then
			printf 'Default route restored.\n'
		else
			printf 'No default route after 20 seconds.\n' >&2
		fi
		printf 'Restarting local DNS services...\n'
		systemctl restart nextdns.service dnsmasq.service
		;;
	*)
		printf 'Usage: %s <dns|full> [domain]\n' "$0" >&2
		exit 64
		;;
esac

bash "$(dirname "$0")/network-recovery-check.sh" "$domain"
