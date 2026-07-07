#!/usr/bin/env bash

set -euo pipefail

usage() {
	echo "Usage: $0 [package-name]" >&2
	echo "Example: $0 surge" >&2
	echo "       $0" >&2
}

is_update_candidate() {
	local package_file="$1"
	local package_contents

	package_contents="$(<"$package_file")"

	[[ $package_contents == *"version ="* ]] &&
		[[ $package_contents == *"fetchFromGitHub"* || $package_contents == *"fetchurl"* || $package_contents == *"fetchgit"* ]]
}

if [ "$#" -gt 1 ]; then
	usage
	exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
packages_dir="$repo_root/pkgs/by-name"

if [ ! -d "$packages_dir" ]; then
	echo "Error: expected directory not found at $packages_dir" >&2
	exit 1
fi

select_package_with_gum() {
	local selection

	if ! command -v gum >/dev/null 2>&1; then
		echo "Error: no package argument provided and 'gum' is not installed." >&2
		echo "Pass a package name explicitly, for example: $0 surge" >&2
		exit 1
	fi

	mapfile -t package_names < <(
		for dir in "$packages_dir"/*; do
			if [ -f "$dir/package.nix" ] && is_update_candidate "$dir/package.nix"; then
				basename "$dir"
			fi
		done | sort
	)

	if [ "${#package_names[@]}" -eq 0 ]; then
		echo "Error: no updatable by-name packages found under $packages_dir" >&2
		exit 1
	fi

	if ! selection="$(printf '%s\n' "${package_names[@]}" | gum filter --placeholder "Select package to update")"; then
		echo "Cancelled."
		exit 0
	fi

	if [ -z "$selection" ]; then
		echo "Cancelled."
		exit 0
	fi

	printf '%s\n' "$selection"
}

if [ "$#" -eq 1 ]; then
	package_name="$1"
else
	package_name="$(select_package_with_gum)"
fi

if [[ $package_name == *"/"* ]]; then
	echo "Error: package name must be a by-name key (for example: surge), not a path." >&2
	exit 1
fi

package_file="$packages_dir/$package_name/package.nix"

if [ ! -f "$package_file" ]; then
	echo "Error: package file not found at $package_file" >&2
	exit 1
fi

if ! is_update_candidate "$package_file"; then
	echo "Done: .#$package_name has no versioned upstream source for nix-update."
	exit 0
fi

cd "$repo_root"

if nix eval --raw ".#$package_name.name" >/dev/null 2>&1; then
	:
else
	echo "Error: flake package '.#$package_name' does not exist on this system." >&2
	exit 1
fi

echo "Updating .#$package_name via nix-update..."
before_hash="$(sha256sum "$package_file")"
nix_update_args=(-F "$package_name")

case "$package_name" in
	rtk | fff-mcp)
		nix_update_args+=(--use-github-releases --version-regex '^v([0-9]+\.[0-9]+\.[0-9]+)$')
		;;
esac

nix run nixpkgs#nix-update -- "${nix_update_args[@]}"
after_hash="$(sha256sum "$package_file")"

if [ "$before_hash" = "$after_hash" ]; then
	echo "Done: .#$package_name already matches upstream; no changes to build."
	exit 0
fi

echo "Building .#$package_name to verify update..."
nix build ".#$package_name"

echo "Done: .#$package_name is updated and builds successfully."
