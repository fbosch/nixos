#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"

if [ -z "${GITHUB_OUTPUT:-}" ]; then
	echo "GITHUB_OUTPUT is not set"
	exit 1
fi

nixos_hosts="$(nix eval --json --apply 'x: builtins.attrNames x' .#nixosConfigurations)"
darwin_hosts="$(nix eval --json --apply 'x: builtins.attrNames x' .#darwinConfigurations 2>/dev/null || echo '[]')"

json_array() {
	jq -cn '$ARGS.positional' --args "$@"
}

base_flake_ref() {
	local base_rev

	if [ -z "${GITHUB_BASE_REF:-}" ]; then
		return 1
	fi

	base_rev="$(git rev-parse --verify "origin/${GITHUB_BASE_REF}^{commit}" 2>/dev/null || true)"
	if [ -z "$base_rev" ]; then
		base_rev="$(git rev-parse --verify "${GITHUB_BASE_REF}^{commit}" 2>/dev/null || true)"
	fi

	if [ -z "$base_rev" ]; then
		return 1
	fi

	printf 'git+file://%s?rev=%s\n' "$PWD" "$base_rev"
}

toplevel_drv_path() {
	local flake_ref="$1"
	local attr="$2"
	local host="$3"

	nix eval --raw "${flake_ref}#${attr}.${host}.config.system.build.toplevel.drvPath" 2>/dev/null
}

changed_hosts() {
	local hosts_json="$1"
	local attr="$2"
	local base_ref="$3"
	local changed=()
	local hosts=()
	local host
	local current_drv
	local base_drv

	mapfile -t hosts < <(jq -r '.[]' <<<"$hosts_json")
	for host in "${hosts[@]}"; do
		if ! current_drv="$(toplevel_drv_path . "$attr" "$host")"; then
			changed+=("$host")
			continue
		fi

		if ! base_drv="$(toplevel_drv_path "$base_ref" "$attr" "$host")"; then
			changed+=("$host")
			continue
		fi

		if [ "$current_drv" != "$base_drv" ]; then
			changed+=("$host")
		fi
	done

	json_array "${changed[@]}"
}

validate_hosts() {
	local hosts_json="$1"
	local attr="$2"
	local base_ref

	if base_ref="$(base_flake_ref)"; then
		changed_hosts "$hosts_json" "$attr" "$base_ref"
		return
	fi

	printf '%s\n' "$hosts_json"
}

case "$mode" in
validate)
	nixos_hosts="$(validate_hosts "$nixos_hosts" nixosConfigurations)"
	darwin_hosts="$(validate_hosts "$darwin_hosts" darwinConfigurations)"

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
