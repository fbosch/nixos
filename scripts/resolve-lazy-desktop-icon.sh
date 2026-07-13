#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf 'Usage: %s <pkgs attribute> [desktop file] [asset path]\n' "$0" >&2
	printf 'Example: %s protonup-qt protonup-qt.desktop assets/icons/protonup-qt.png\n' "$0" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
	usage
	exit 1
fi

package_attr="$1"
desktop_file_name="${2:-}"
asset_path="${3:-}"

if [[ ! $package_attr =~ ^[[:alpha:]_][[:alnum:]_-]*(\.[[:alpha:]_][[:alnum:]_-]*)*$ ]]; then
	printf 'Invalid pkgs attribute: %s\n' "$package_attr" >&2
	exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
host="$(hostname)"

cd "$repo_root"
package_path="$(nix eval --raw ".#nixosConfigurations.\"$host\".pkgs.$package_attr.outPath")"
nix build --no-link "$package_path"

desktop_dir="$package_path/share/applications"
if [ ! -d "$desktop_dir" ]; then
	printf 'Package has no desktop entries: %s\n' "$package_path" >&2
	exit 1
fi

if [ -n "$desktop_file_name" ]; then
	desktop_file="$desktop_dir/$desktop_file_name"
	if [ ! -f "$desktop_file" ]; then
		printf 'Desktop entry not found: %s\n' "$desktop_file" >&2
		exit 1
	fi
else
	shopt -s nullglob
	desktop_files=("$desktop_dir"/*.desktop)
	if [ "${#desktop_files[@]}" -ne 1 ]; then
		printf 'Specify a desktop file; found %s entries in %s\n' "${#desktop_files[@]}" "$desktop_dir" >&2
		printf '%s\n' "${desktop_files[@]}" >&2
		exit 1
	fi
	desktop_file="${desktop_files[0]}"
fi

icon_name=""
while IFS= read -r line; do
	case "$line" in
		Icon=*)
			icon_name="${line#Icon=}"
			break
			;;
	esac
done < "$desktop_file"

if [ -z "$icon_name" ]; then
	printf 'Desktop entry has no Icon field: %s\n' "$desktop_file" >&2
	exit 1
fi

if [[ $icon_name = /* ]]; then
	icon_path="$icon_name"
else
	icon_paths=()
	for icon_dir in "$package_path/share/pixmaps" "$package_path/share/icons"; do
		if [ ! -d "$icon_dir" ]; then
			continue
		fi

		while IFS= read -r -d '' candidate; do
			candidate_name="${candidate##*/}"
			case "$candidate_name" in
				"$icon_name" | "$icon_name".png | "$icon_name".svg | "$icon_name".xpm)
					icon_paths+=("$candidate")
					;;
			esac
		done < <(find "$icon_dir" -type f -print0)

		if [ "${#icon_paths[@]}" -gt 0 ]; then
			break
		fi
	done

	if [ "${#icon_paths[@]}" -eq 0 ]; then
		printf 'Could not locate icon %q in %s\n' "$icon_name" "$package_path" >&2
		exit 1
	fi

	if [ "${#icon_paths[@]}" -gt 1 ]; then
		scalable_icons=()
		for candidate in "${icon_paths[@]}"; do
			case "$candidate" in
				*/scalable/*) scalable_icons+=("$candidate") ;;
			esac
		done

		if [ "${#scalable_icons[@]}" -eq 1 ]; then
			icon_path="${scalable_icons[0]}"
		else
			large_icons=()
			for candidate in "${icon_paths[@]}"; do
				case "$candidate" in
					*/256x256/*) large_icons+=("$candidate") ;;
				esac
			done

			if [ "${#large_icons[@]}" -eq 1 ]; then
				icon_path="${large_icons[0]}"
			else
				printf 'Icon %q has multiple candidates; choose one explicitly:\n' "$icon_name" >&2
				printf '%s\n' "${icon_paths[@]}" >&2
				exit 1
			fi
		fi
	else
		icon_path="${icon_paths[0]}"
	fi
fi

if [[ $icon_path != "$package_path"/* ]]; then
	printf 'Icon is outside the package output: %s\n' "$icon_path" >&2
	exit 1
fi

if [ -n "$asset_path" ]; then
	case "$asset_path" in
		/* | ../* | */../* | ..)
			printf 'Asset path must be relative to the repository: %s\n' "$asset_path" >&2
			exit 1
			;;
	esac

	asset_path="$repo_root/$asset_path"
	install -Dm644 "$icon_path" "$asset_path"
	icon_path="$asset_path"
fi

printf '%s\n' "$icon_path"
