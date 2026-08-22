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
  local revision="${2:-}"

  if "$has_gum"; then
    printf '%s %s' \
      "$(CLICOLOR_FORCE=1 gum style --foreground 1 --bold "$old_version")" \
      "$(CLICOLOR_FORCE=1 gum style --foreground 7 --bold "→")"
    if [ -n "$revision" ]; then
      printf ' %s %s' \
        "$(CLICOLOR_FORCE=1 gum style --foreground 244 "$revision")" \
        "$(CLICOLOR_FORCE=1 gum style --foreground 7 --bold "→")"
    fi
    printf ' %s' "$(CLICOLOR_FORCE=1 gum style --foreground 2 --bold "$new_version")"
  else
    printf '%s → ' "$old_version"
    if [ -n "$revision" ]; then
      printf '%s → ' "$revision"
    fi
    printf '%s' "$new_version"
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
  echo "Usage: $0 [--all | package-name]" >&2
  echo "Example: $0 lightpanda" >&2
  echo "       $0 --all" >&2
  echo "       $0" >&2
}

is_update_candidate() {
  local package_file="$1"
  local package_contents

  package_contents="$(<"$package_file")"

  [[ $package_contents == *"version ="* ]] &&
    [[ $package_contents == *"fetchFromGitHub"* || $package_contents == *"fetchurl"* || $package_contents == *"fetchgit"* ]]
}

package_revision() {
  local package_file="$1"
  local package_contents

  package_contents="$(<"$package_file")"
  if [[ $package_contents =~ rev[[:space:]]*=[[:space:]]*\"([[:xdigit:]]{7,64})\" ]]; then
    printf '%.8s' "${BASH_REMATCH[1]}"
    return
  fi

  printf '-'
}

package_version() {
  local package_file="$1"
  local package_contents

  package_contents="$(<"$package_file")"
  if [[ $package_contents =~ version[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi

  return 1
}

if [ "$#" -gt 1 ]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
packages_dir="$repo_root/pkgs/by-name"

if [ ! -d "$packages_dir" ]; then
  error "expected directory not found at $packages_dir" >&2
  exit 1
fi

declare -A package_update_prs=()
update_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nixos/update-local-package"
update_cache_ttl=3600
update_cache_available=false

package_is_at_version() {
  local package_name="$1"
  local version="$2"
  local package_file="$packages_dir/$package_name/package.nix"
  local package_contents

  [ -f "$package_file" ] || return 1
  package_contents="$(<"$package_file")"
  [[ $package_contents == *"version = \"$version\";"* ]]
}

record_pending_update() {
  local path="$1"
  local old_version="$2"
  local new_version="$3"
  local package_name

  [ -n "$old_version" ] && [ -n "$new_version" ] || return
  package_name="${path#pkgs/by-name/}"
  package_name="${package_name%/package.nix}"
  if ! package_is_at_version "$package_name" "$old_version"; then
    return
  fi
  if package_is_at_version "$package_name" "$new_version"; then
    return
  fi
  package_update_prs["$package_name"]="$old_version"$'\t'"$new_version"
}

read_pending_updates() {
  local path
  local old_version
  local new_version

  while IFS=$'\t' read -r path old_version new_version; do
    record_pending_update "$path" "$old_version" "$new_version"
  done <"$1"
}

fetch_pr_updates() {
  local pr_number="$1"

  cd "$repo_root"
  # The jq expression deliberately contains jq interpolation syntax.
  # shellcheck disable=SC2016
  gh api "repos/{owner}/{repo}/pulls/$pr_number/files?per_page=100" --paginate \
    --jq '.[] | select(.filename | test("^pkgs/by-name/[^/]+/package\\.nix$")) | .filename as $file | ([.patch | split("\n")[] | select(test("^-\\s*version\\s*=")) | capture("^-\\s*version\\s*=\\s*\\\"(?<version>[^\\\"]+)\\\";").version][0]) as $old | ([.patch | split("\n")[] | select(test("^\\+\\s*version\\s*=")) | capture("^\\+\\s*version\\s*=\\s*\\\"(?<version>[^\\\"]+)\\\";").version][0]) as $new | "\($file)\t\($old)\t\($new)"' 2>/dev/null
}

fetch_pending_update_pr_numbers() {
  cd "$repo_root"
  gh pr list --state open --label custom-packages --json number --jq '.[].number' 2>/dev/null
}

load_pr_updates() {
  local pr_number="$1"
  local cache_file="$update_cache_dir/renovate-pr-$pr_number.tsv"
  local cache_modified
  local cache_tmp
  local path
  local old_version
  local new_version
  local updates

  if "$update_cache_available"; then
    cache_modified="$(stat -c %Y "$cache_file" 2>/dev/null || true)"
    if [ -n "$cache_modified" ] && [ "$(($(date +%s) - cache_modified))" -lt "$update_cache_ttl" ]; then
      read_pending_updates "$cache_file"
      return
    fi

    if cache_tmp="$(mktemp "$update_cache_dir/.renovate-pr-$pr_number.XXXXXX")"; then
      if fetch_pr_updates "$pr_number" >"$cache_tmp"; then
        mv "$cache_tmp" "$cache_file"
        read_pending_updates "$cache_file"
      else
        rm -f "$cache_tmp"
      fi
      return
    fi
  fi

  updates="$(fetch_pr_updates "$pr_number")" || return
  while IFS=$'\t' read -r path old_version new_version; do
    record_pending_update "$path" "$old_version" "$new_version"
  done <<<"$updates"
}

load_pending_update_prs() {
  local cache_file="$update_cache_dir/renovate-prs.txt"
  local cache_modified
  local cache_tmp
  local pr_number

  if ! command -v gh >/dev/null 2>&1; then
    return
  fi
  if mkdir -p "$update_cache_dir" 2>/dev/null; then
    update_cache_available=true
  fi

  if "$update_cache_available"; then
    cache_modified="$(stat -c %Y "$cache_file" 2>/dev/null || true)"
    if [ -z "$cache_modified" ] || [ "$(($(date +%s) - cache_modified))" -ge "$update_cache_ttl" ]; then
      if cache_tmp="$(mktemp "$update_cache_dir/.renovate-prs.XXXXXX")"; then
        if fetch_pending_update_pr_numbers >"$cache_tmp"; then
          mv "$cache_tmp" "$cache_file"
        else
          rm -f "$cache_tmp"
        fi
      fi
    fi

    if [ -f "$cache_file" ]; then
      while IFS= read -r pr_number; do
        [ -n "$pr_number" ] && load_pr_updates "$pr_number"
      done <"$cache_file"
      return
    fi
  fi

  while IFS= read -r pr_number; do
    [ -n "$pr_number" ] && load_pr_updates "$pr_number"
  done < <(fetch_pending_update_pr_numbers)
}

clear_update_cache() {
  rm -f \
    "$update_cache_dir/renovate-prs.txt" \
    "$update_cache_dir"/renovate-pr-*.tsv
}

select_package_with_gum() {
  local line
  local selection
  local package_name
  local revision
  local version
  local -a package_names

  if ! command -v gum >/dev/null 2>&1; then
    error "no package argument provided and 'gum' is not installed" >&2
    echo "Pass a package name explicitly, for example: $0 lightpanda" >&2
    exit 1
  fi

  mapfile -t package_names < <(
    for dir in "$packages_dir"/*; do
      package_name="$(basename "$dir")"
      if [ -f "$dir/package.nix" ] &&
        is_update_candidate "$dir/package.nix" &&
        { "$show_all" || [ -n "${package_update_prs[$package_name]:-}" ]; }; then
        basename "$dir"
      fi
    done | sort
  )

  if [ "${#package_names[@]}" -eq 0 ]; then
    status 3 SKIP "no package updates found" >&2
    return 2
  fi

  if ! selection="$(
    for package_name in "${package_names[@]}"; do
      revision="$(package_revision "$packages_dir/$package_name/package.nix")"
      if [ -n "${package_update_prs[$package_name]:-}" ]; then
        printf '%s  %s\n' "$package_name" "$(render_version_update "${package_update_prs[$package_name]}" "$revision")"
      else
        version="$(package_version "$packages_dir/$package_name/package.nix")"
        printf '%s  %s\n' "$package_name" "$(render_version_update "$version"$'\t'"$version" "$revision")"
      fi
    done | gum choose --no-limit --ordered --no-strip-ansi --header "Select packages to update"
  )"; then
    status 3 SKIP "cancelled" >&2
    return 2
  fi

  if [ -z "$selection" ]; then
    status 3 SKIP "cancelled" >&2
    return 2
  fi

  while IFS= read -r line; do
    printf '%s\n' "${line%%  *}"
  done <<<"$selection"
}

load_pending_update_prs

show_all=false
if [ "$#" -eq 1 ] && [ "$1" = "--all" ]; then
  show_all=true
elif [ "$#" -eq 1 ] && [[ $1 == --* ]]; then
  error "unknown option: $1" >&2
  usage
  exit 1
fi

declare -a selected_packages
if [ "$#" -eq 1 ] && ! "$show_all"; then
  selected_packages=("$1")
elif selection="$(select_package_with_gum)"; then
  mapfile -t selected_packages <<<"$selection"
else
  selection_exit_code=$?
  if [ "$selection_exit_code" -eq 2 ]; then
    exit 0
  fi
  exit "$selection_exit_code"
fi

for package_name in "${selected_packages[@]}"; do
  if [[ $package_name == *"/"* ]]; then
    error "package name must be a by-name key (for example: lightpanda), not a path" >&2
    exit 1
  fi

  package_file="$packages_dir/$package_name/package.nix"

  if [ ! -f "$package_file" ]; then
    error "package file not found at $package_file" >&2
    exit 1
  fi

  if ! is_update_candidate "$package_file"; then
    status 3 SKIP ".#$package_name has no versioned upstream source for nix-update"
    continue
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
    clear_update_cache
    status 3 SKIP ".#$package_name already matches upstream; no changes to build"
    continue
  fi

  run_step "Building .#$package_name" nix build ".#$package_name"

  clear_update_cache
  status 2 DONE ".#$package_name is updated and builds successfully"
done
