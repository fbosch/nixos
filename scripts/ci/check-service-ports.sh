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

backtick=$'\x60'
mapfile -t documented_ports < <(
  grep -oE "${backtick}[0-9]+/(tcp|udp)${backtick}" "$doc_path" |
    tr -d '`' |
    sort -u
)

mapfile -t missing_ports < <(comm -23 \
  <(printf '%s\n' "${declared_ports[@]}" | sort -u) \
  <(printf '%s\n' "${documented_ports[@]}" | sort -u))

mapfile -t stale_ports < <(comm -13 \
  <(printf '%s\n' "${declared_ports[@]}" | sort -u) \
  <(printf '%s\n' "${documented_ports[@]}" | sort -u))

if [ "${#missing_ports[@]}" -gt 0 ] || [ "${#stale_ports[@]}" -gt 0 ]; then
  echo "${doc_path} does not match declared exposed ports for ${host}:"

  if [ "${#missing_ports[@]}" -gt 0 ]; then
    echo "Missing from documentation:"
    printf '  - %s\n' "${missing_ports[@]}"
  fi

  if [ "${#stale_ports[@]}" -gt 0 ]; then
    echo "Missing from services.exposedPorts:"
    printf '  - %s\n' "${stale_ports[@]}"
  fi

  exit 1
fi

echo "${doc_path} exactly matches declared exposed ports for ${host}"
