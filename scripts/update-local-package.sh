#!/usr/bin/env bash

set -euo pipefail

has_gum=false
if command -v gum >/dev/null 2>&1; then
	has_gum=true
fi

status() {
	local color="$1"
	local label="$2"
	local message="$3"

	if "$has_gum"; then
		printf '%s %s\n' "$(gum style --foreground "$color" "[$label]")" "$message"
	else
		printf '[%s] %s\n' "$label" "$message"
	fi
}

error() {
	status 1 ERROR "$*"
}

run_step() {
	local title="$1"
	shift

	if "$has_gum"; then
		gum style --foreground 244 "$title..."
	else
		printf '%s...\n' "$title"
	fi

	"$@"
}

render_update_output() {
	local output="$1"
	local line
	local instantiated=false
	local label

	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		'$ nix-instantiate '*)
			if "$instantiated"; then
				label="Re-evaluate package"
			else
				label="Instantiate package"
				instantiated=true
			fi
			;;
		'$ nix build '*) label="Resolve update script" ;;
		'$ nix develop '*) label="Run update script" ;;
		'$ git -C '*) label="Review package changes" ;;
		*)
			printf '%s\n' "$line"
			continue
			;;
		esac

		printf '%s\n' "$(gum style --foreground 6 --bold "$label")"
		printf '  %s\n' "$(gum style --foreground 244 "$line")"
	done <"$output"
}

run_update() {
	local title="$1"
	local output
	local exit_code
	shift

	if ! "$has_gum"; then
		run_step "$title" "$@"
		return
	fi

	output="$(mktemp)"
	gum style --foreground 244 "$title..."
	if "$@" >"$output" 2>&1; then
		render_update_output "$output"
	else
		exit_code=$?
		cat "$output" >&2
		rm -f "$output"
		return "$exit_code"
	fi

	rm -f "$output"
}

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
	error "expected directory not found at $packages_dir" >&2
	exit 1
fi

select_package_with_gum() {
	local selection

	if ! command -v gum >/dev/null 2>&1; then
		error "no package argument provided and 'gum' is not installed" >&2
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
		error "no updatable by-name packages found under $packages_dir" >&2
		exit 1
	fi

	if ! selection="$(printf '%s\n' "${package_names[@]}" | gum filter --placeholder "Select package to update")"; then
		status 3 SKIP "cancelled"
		exit 0
	fi

	if [ -z "$selection" ]; then
		status 3 SKIP "cancelled"
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
	error "package name must be a by-name key (for example: surge), not a path" >&2
	exit 1
fi

package_file="$packages_dir/$package_name/package.nix"

if [ ! -f "$package_file" ]; then
	error "package file not found at $package_file" >&2
	exit 1
fi

if ! is_update_candidate "$package_file"; then
	status 3 SKIP ".#$package_name has no versioned upstream source for nix-update"
	exit 0
fi

cd "$repo_root"

if nix eval --raw ".#$package_name.name" >/dev/null 2>&1; then
	:
else
	error "flake package '.#$package_name' does not exist on this system" >&2
	exit 1
fi

if "$has_gum"; then
	printf '\n'
	printf '%s\n' "$(gum style --foreground 212 --bold "Update .#$package_name")"
	printf '%s\n' "$(gum style --foreground 244 "$package_file")"
fi

before_hash="$(sha256sum "$package_file")"
nix_update_args=(-F -u "$package_name")

run_update "Updating .#$package_name" nix run nixpkgs#nix-update -- "${nix_update_args[@]}"
after_hash="$(sha256sum "$package_file")"

if [ "$before_hash" = "$after_hash" ]; then
	status 3 SKIP ".#$package_name already matches upstream; no changes to build"
	exit 0
fi

run_step "Building .#$package_name" nix build ".#$package_name"

status 2 DONE ".#$package_name is updated and builds successfully"
