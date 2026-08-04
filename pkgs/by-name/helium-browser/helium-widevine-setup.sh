#!/usr/bin/env bash
set -euo pipefail

command_name=helium-widevine-setup
default_source=/opt/google/chrome/WidevineCdm
default_user_data_dir="${XDG_CONFIG_HOME:-$HOME/.config}/net.imput.helium"

usage() {
  cat <<EOF
Usage: $command_name [OPTIONS]

Install Widevine from an existing local Google Chrome installation into one
Helium user-data directory. The CDM is never downloaded or distributed.

Options:
  --source DIR           Existing Chrome WidevineCdm directory.
                         Default: Nix-installed Google Chrome, otherwise
                         $default_source
  --user-data-dir DIR    Helium user-data directory.
                         Default: $default_user_data_dir
  -h, --help             Show this help text.

Examples:
  $command_name
  $command_name --source /path/to/WidevineCdm --user-data-dir ~/.config/helium-browser/youtube

Run the command once for every Helium webapp profile that needs DRM.
Restart Helium after installation.
EOF
}

die() {
  printf '%s: %s\n' "$command_name" "$1" >&2
  exit "${2:-1}"
}

source_dir=
user_data_dir=$default_user_data_dir

while [ "$#" -gt 0 ]; do
  case "$1" in
  --source)
    [ "$#" -ge 2 ] || die "--source requires a directory" 2
    source_dir=$2
    shift 2
    ;;
  --user-data-dir)
    [ "$#" -ge 2 ] || die "--user-data-dir requires a directory" 2
    user_data_dir=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown option: $1" 2
    ;;
  esac
done

if [ -z "$source_dir" ]; then
  if [ -d "$default_source" ]; then
    source_dir=$default_source
  elif chrome_bin="$(command -v google-chrome-stable)"; then
    chrome_bin="$(realpath -e "$chrome_bin")" || die "could not resolve Google Chrome: $chrome_bin"
    source_dir="$(dirname "$(dirname "$chrome_bin")")/share/google/chrome/WidevineCdm"
  else
    source_dir=$default_source
  fi
fi

source_dir=$(realpath -e "$source_dir") || die "source directory does not exist: $source_dir"
user_data_dir=$(realpath -m "$user_data_dir")

[ -d "$source_dir" ] || die "source is not a directory: $source_dir"
[ -f "$source_dir/manifest.json" ] || die "manifest.json is missing from: $source_dir"
[ -f "$source_dir/_platform_specific/linux_x64/libwidevinecdm.so" ] || die "Linux x86_64 CDM is missing from: $source_dir"

version=$(jq -er '.version | select(type == "string" and test("^[0-9]+(\\.[0-9]+)+$"))' "$source_dir/manifest.json") ||
  die "source manifest has no valid Widevine version: $source_dir/manifest.json"

component_dir="$user_data_dir/WidevineCdm"
destination="$component_dir/$version"
hint_file="$component_dir/latest-component-updated-widevine-cdm"

printf 'Working  Checking local Widevine CDM...\n' >&2

if [ -e "$destination" ]; then
  [ -d "$destination" ] || die "target component is not a directory: $destination"
  [ -f "$destination/manifest.json" ] || die "target component is incomplete: $destination"
  [ -f "$destination/_platform_specific/linux_x64/libwidevinecdm.so" ] || die "target component is incomplete: $destination"
  printf 'Info     Reusing Widevine %s already installed.\n' "$version" >&2
else
  mkdir -p "$component_dir"
  temporary_component=$(mktemp -d "$component_dir/.${version}.XXXXXX")
  temporary_hint=

  cleanup() {
    rm -rf "$temporary_component" "$temporary_hint"
  }
  trap cleanup EXIT HUP INT TERM

  printf 'Working  Installing Widevine %s...\n' "$version" >&2
  cp -a "$source_dir/." "$temporary_component"
  mv "$temporary_component" "$destination"
fi

temporary_hint=$(mktemp "$component_dir/.latest-component-updated-widevine-cdm.XXXXXX")
jq -n --arg path "$destination" '{ Path: $path }' >"$temporary_hint"
mv -f "$temporary_hint" "$hint_file"

printf 'Success  Installed Widevine %s.\n' "$version"
printf '  User data dir  %s\n' "$user_data_dir"
printf '  Source         %s\n' "$source_dir"
printf 'Restart Helium to load the CDM.\n'
