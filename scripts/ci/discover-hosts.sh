#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"

if [ -z "${GITHUB_OUTPUT:-}" ]; then
	echo "GITHUB_OUTPUT is not set"
	exit 1
fi

nixos_hosts="$(nix eval --json --apply 'x: builtins.attrNames x' .#nixosConfigurations)"
darwin_hosts="$(nix eval --json --apply 'x: builtins.attrNames x' .#darwinConfigurations 2>/dev/null || echo '[]')"

case "$mode" in
validate)
	echo "nixos-hosts=$nixos_hosts" >>"$GITHUB_OUTPUT"
	echo "darwin-hosts=$darwin_hosts" >>"$GITHUB_OUTPUT"

	if [ "$nixos_hosts" != "[]" ]; then
		echo "has-nixos=true" >>"$GITHUB_OUTPUT"
	else
		echo "has-nixos=false" >>"$GITHUB_OUTPUT"
	fi

	if [ "$darwin_hosts" != "[]" ]; then
		echo "has-darwin=true" >>"$GITHUB_OUTPUT"
	else
		echo "has-darwin=false" >>"$GITHUB_OUTPUT"
	fi
	;;

security)
	targets="$(jq -cn \
		--argjson nixos "$nixos_hosts" \
		--argjson darwin "$darwin_hosts" \
		'($nixos | map({ host: ., flake: ("nixosConfigurations." + . + ".config.system.build.toplevel") }))
       + ($darwin | map({ host: ., flake: ("darwinConfigurations." + . + ".config.system.build.toplevel") }))')"

	echo "targets=$targets" >>"$GITHUB_OUTPUT"
	if [ "$targets" != "[]" ]; then
		echo "has-targets=true" >>"$GITHUB_OUTPUT"
	else
		echo "has-targets=false" >>"$GITHUB_OUTPUT"
	fi
	;;

*)
	echo "Usage: $0 {validate|security}"
	exit 2
	;;
esac
