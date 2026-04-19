#!/usr/bin/env bash

set -euo pipefail

doc_path="docs/agents/service-ports.md"
host="rvn-srv"

if ! command -v jq >/dev/null 2>&1; then
	echo "jq is required to validate documented service ports"
	exit 1
fi

mapfile -t declared_ports < <(
	nix eval --json ".#nixosConfigurations.${host}.config.services.exposedPorts" |
		jq -r '[.[] | (.tcpPorts[]? | "\(.)/tcp"), (.udpPorts[]? | "\(.)/udp")] | unique | .[]'
)

missing_ports=()

for port in "${declared_ports[@]}"; do
	if ! grep -Fq -- "$port" "$doc_path"; then
		missing_ports+=("$port")
	fi
done

if [ "${#missing_ports[@]}" -gt 0 ]; then
	echo "${doc_path} is missing documented ports for ${host}:"
	printf '  - %s\n' "${missing_ports[@]}"
	exit 1
fi

echo "${doc_path} covers all declared exposed ports for ${host}"
