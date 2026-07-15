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
		printf '%s %s\n' "$(CLICOLOR_FORCE=1 gum style --foreground "$color" "[$label]")" "$message"
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

render_version_update() {
	local old_version="${1%%$'\t'*}"
	local new_version="${1#*$'\t'}"

	if "$has_gum"; then
		printf '%s %s %s' \
			"$(CLICOLOR_FORCE=1 gum style --foreground 1 --bold "$old_version")" \
			"$(CLICOLOR_FORCE=1 gum style --foreground 7 --bold "→")" \
			"$(CLICOLOR_FORCE=1 gum style --foreground 2 --bold "$new_version")"
	else
		printf '%s → %s' "$old_version" "$new_version"
	fi
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

		printf '%s\n' "$(CLICOLOR_FORCE=1 gum style --foreground 6 --bold "$label")"
		printf '  %s\n' "$(CLICOLOR_FORCE=1 gum style --foreground 244 "$line")"
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

declare -A package_update_prs=()

package_is_at_version() {
	local package_name="$1"
	local version="$2"
	local package_file="$packages_dir/$package_name/package.nix"
	local package_contents

	[ -f "$package_file" ] || return 1
	package_contents="$(<"$package_file")"
	[[ $package_contents == *"version = \"$version\";"* ]]
}

load_pending_update_prs() {
	local path
	local pr_number
	local package_name
	local old_version
	local new_version

	if ! command -v gh >/dev/null 2>&1; then
		return
	fi

	while IFS= read -r pr_number; do
		while IFS=$'\t' read -r path old_version new_version; do
			package_name="${path#pkgs/by-name/}"
			package_name="${package_name%/package.nix}"
			if package_is_at_version "$package_name" "$new_version"; then
				continue
			fi
			package_update_prs["$package_name"]="$old_version"$'\t'"$new_version"
		done < <(
			cd "$repo_root"
			gh api "repos/{owner}/{repo}/pulls/$pr_number/files?per_page=100" --paginate \
				--jq '.[] | select(.filename | test("^pkgs/by-name/[^/]+/package\\.nix$")) | .filename as $file | ([.patch | split("\n")[] | select(test("^-\\s*version\\s*=")) | capture("^-\\s*version\\s*=\\s*\\\"(?<version>[^\\\"]+)\\\";").version][0]) as $old | ([.patch | split("\n")[] | select(test("^\\+\\s*version\\s*=")) | capture("^\\+\\s*version\\s*=\\s*\\\"(?<version>[^\\\"]+)\\\";").version][0]) as $new | "\($file)\t\($old)\t\($new)"' 2>/dev/null
		)
	done < <(
		cd "$repo_root"
		gh pr list --state open --label custom-packages --json number --jq '.[].number' 2>/dev/null
	)
}

select_package_with_gum() {
	local selection
	local package_name

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

	if ! selection="$(
		for package_name in "${package_names[@]}"; do
			if [ -n "${package_update_prs[$package_name]:-}" ]; then
				printf '%s  %s\n' "$package_name" "$(render_version_update "${package_update_prs[$package_name]}")"
			else
				printf '%s\n' "$package_name"
			fi
		done | gum filter --no-strip-ansi --placeholder "Select package to update"
	)"; then
		status 3 SKIP "cancelled" >&2
		return 2
	fi

	if [ -z "$selection" ]; then
		status 3 SKIP "cancelled" >&2
		return 2
	fi

	printf '%s\n' "${selection%%  *}"
}

load_pending_update_prs

if [ "$#" -eq 1 ]; then
	package_name="$1"
elif package_name="$(select_package_with_gum)"; then
	:
else
	selection_exit_code=$?
	if [ "$selection_exit_code" -eq 2 ]; then
		exit 0
	fi
	exit "$selection_exit_code"
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

if [ -n "${package_update_prs[$package_name]:-}" ]; then
	status 2 UPDATE ".#$package_name $(render_version_update "${package_update_prs[$package_name]}")"
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
	printf '%s\n' "$(CLICOLOR_FORCE=1 gum style --foreground 212 --bold "Update .#$package_name")"
	printf '%s\n' "$(CLICOLOR_FORCE=1 gum style --foreground 244 "$package_file")"
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
