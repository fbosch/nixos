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
    '$ nix build '*)
      label="Resolve update script"
      ;;
    '$ nix develop '*)
      label="Run update script"
      ;;
    '$ git -C '*)
      label="Review package changes"
      ;;
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
  echo "         $0 hyprland-plugins/cursor-outline" >&2
  echo "       $0 --all" >&2
  echo "       $0" >&2
}

is_update_candidate() {
  local package_file="$1"
  local package_contents

  package_contents="$(<"$package_file")"

  [[ $package_contents == *"version ="* ]] &&
    [[ $package_contents == *"src ="* ]] &&
    [[ $package_contents =~ fetch[A-Za-z]+ ]]
}

uses_explicit_update_script() {
  local package_file="$1"
  local package_contents

  package_contents="$(<"$package_file")"
  [[ $package_contents == *"updateScript"* ]]
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

shopt -s globstar nullglob

if [ ! -d "$packages_dir" ]; then
  error "expected directory not found at $packages_dir" >&2
  exit 1
fi

declare -A package_updates=()
update_check_dir=""
update_check_failed=false
nix_update_command=()

ensure_nix_update_command() {
  if [ "${#nix_update_command[@]}" -gt 0 ]; then
    return 0
  fi

  local store_path
  if ! store_path="$(nix build nixpkgs#nix-update --no-link --print-out-paths)"; then
    error "failed to resolve nix-update from nixpkgs" >&2
    return 1
  fi

  nix_update_command=("$store_path/bin/nix-update")
  if [ ! -x "${nix_update_command[0]}" ]; then
    error "resolved nix-update executable not found at ${nix_update_command[0]}" >&2
    nix_update_command=()
    return 1
  fi
}

cleanup_update_check() {
  local exit_code=$?

  if [ -n "$update_check_dir" ]; then
    rm -rf -- "$update_check_dir" || true
  fi
  return "$exit_code"
}
trap cleanup_update_check EXIT

create_update_check_copy() {
  update_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/update-local-package.XXXXXX")"
  if ! (
    cd "$repo_root" || exit 1
    git ls-files -co --exclude-standard -z |
      while IFS= read -r -d '' path; do
        if [ -e "$path" ] || [ -L "$path" ]; then
          printf '%s\0' "$path"
        fi
      done |
      tar --null --verbatim-files-from --create --file=- --files-from=-
  ) | tar --extract --file=- --directory="$update_check_dir"; then
    error "failed to create a temporary repository for update checks" >&2
    exit 1
  fi

  # nix-update uses Git to inspect changes; stage the copied worktree without committing it.
  if ! (
    cd "$update_check_dir" || exit 1
    git init -q || exit 1
    git add --all
  ); then
    error "failed to initialize the temporary repository for update checks" >&2
    exit 1
  fi
}

restore_update_check_copy() {
  if ! (
    cd "$update_check_dir" || exit 1
    git restore --worktree -- .
  ); then
    status 1 CHECK "failed to restore the temporary repository after an update check" >&2
    update_check_failed=true
    return 1
  fi
}

check_package_update() {
  local package_name="$1"
  local package_file="$packages_dir/$package_name/package.nix"
  local check_package_file="$update_check_dir/pkgs/by-name/$package_name/package.nix"
  local before_hash
  local after_hash
  local output_file
  local old_version
  local new_version
  local -a nix_update_args

  if ! old_version="$(package_version "$package_file")"; then
    status 1 CHECK "unable to read the current version of .#$package_name" >&2
    update_check_failed=true
    return 1
  fi
  if ! before_hash="$(sha256sum "$check_package_file")"; then
    status 1 CHECK "unable to snapshot .#$package_name before checking" >&2
    update_check_failed=true
    return 1
  fi
  if ! output_file="$(mktemp)"; then
    status 1 CHECK "unable to create output capture for .#$package_name" >&2
    update_check_failed=true
    return 1
  fi
  nix_update_args=(-q -F)
  if uses_explicit_update_script "$package_file"; then
    nix_update_args+=(-u)
  fi
  if [[ "$old_version" == unstable-* || "$old_version" == *-unstable ]]; then
    nix_update_args+=(--version unstable)
  fi
  nix_update_args+=(--override-filename "$check_package_file" "$package_name")

  if "$has_gum"; then
    gum style --foreground 244 "Checking .#$package_name for updates..."
  else
    printf 'Checking .#%s for updates...\n' "$package_name"
  fi

  if ! (
    cd "$update_check_dir" || exit 1
    "${nix_update_command[@]}" "${nix_update_args[@]}"
  ) >"$output_file" 2>&1; then
    if grep -Fq 'VersionError: Please specify the version. We can only get the latest version from' "$output_file"; then
      status 3 SKIP "nix-update could not discover an upstream version for .#$package_name; skipping automatic check" >&2
      rm -f -- "$output_file"
      restore_update_check_copy || true
      return 0
    fi

    status 1 CHECK "unable to check .#$package_name for updates" >&2
    cat "$output_file" >&2
    rm -f -- "$output_file"
    restore_update_check_copy || true
    update_check_failed=true
    return 1
  fi

  if ! after_hash="$(sha256sum "$check_package_file")"; then
    rm -f -- "$output_file"
    status 1 CHECK "unable to snapshot .#$package_name after checking" >&2
    restore_update_check_copy || true
    update_check_failed=true
    return 1
  fi
  rm -f -- "$output_file"

  if [ "$before_hash" = "$after_hash" ]; then
    restore_update_check_copy || true
    return 0
  fi

  if ! new_version="$(package_version "$check_package_file")"; then
    status 1 CHECK "nix-update changed .#$package_name to an unreadable package" >&2
    restore_update_check_copy || true
    update_check_failed=true
    return 1
  fi
  package_updates["$package_name"]="$old_version"$'\t'"$new_version"
  restore_update_check_copy || true
}

check_upstream_updates() {
  local package_file
  if ! ensure_nix_update_command; then
    update_check_failed=true
    return 0
  fi

  local package_name

  create_update_check_copy
  for package_file in "$packages_dir"/**/package.nix; do
    package_name="${package_file#"$packages_dir"/}"
    package_name="${package_name%/package.nix}"
    if is_update_candidate "$package_file"; then
      check_package_update "$package_name" || true
    fi
  done
}

select_package_with_gum() {
  local line
  local selection
  local package_name
  local revision
  local version
  local -a package_names

  mapfile -t package_names < <(
    for package_file in "$packages_dir"/**/package.nix; do
      package_name="${package_file#"$packages_dir"/}"
      package_name="${package_name%/package.nix}"
      if is_update_candidate "$package_file" &&
        { "$show_all" || [ -n "${package_updates[$package_name]:-}" ]; }; then
        printf '%s\n' "$package_name"
      fi
    done | sort
  )

  if [ "${#package_names[@]}" -eq 0 ]; then
    if "$update_check_failed"; then
      status 1 ERROR "one or more package update checks failed; no complete update list is available" >&2
      return 1
    fi
    status 3 SKIP "no package updates found" >&2
    return 2
  fi

  if ! selection="$(
    for package_name in "${package_names[@]}"; do
      revision="$(package_revision "$packages_dir/$package_name/package.nix")"
      if [ -n "${package_updates[$package_name]:-}" ]; then
        printf '%s  %s\n' "$package_name" "$(render_version_update "${package_updates[$package_name]}" "$revision")"
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
else
  if ! "$has_gum"; then
    error "no package argument provided and 'gum' is not installed" >&2
    echo "Pass a package name explicitly, for example: $0 lightpanda" >&2
    exit 1
  fi

  check_upstream_updates
  if selection="$(select_package_with_gum)"; then
    mapfile -t selected_packages <<<"$selection"
  else
    selection_exit_code=$?
    if [ "$selection_exit_code" -eq 2 ]; then
      exit 0
    fi
    exit "$selection_exit_code"
  fi
fi

for package_name in "${selected_packages[@]}"; do
  package_file="$packages_dir/$package_name/package.nix"
  current_version=""

  if [ ! -f "$package_file" ]; then
    error "package file not found at $package_file" >&2
    exit 1
  fi

  if ! is_update_candidate "$package_file"; then
    status 3 SKIP ".#$package_name has no versioned upstream source for nix-update"
    continue
  fi

  if [ -n "${package_updates[$package_name]:-}" ]; then
    status 2 UPDATE ".#$package_name $(render_version_update "${package_updates[$package_name]}" "$(package_revision "$package_file")")"
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
  nix_update_args=(-F)
  if uses_explicit_update_script "$package_file"; then
    nix_update_args+=(-u)
  fi
  if ! current_version="$(package_version "$package_file")"; then
    error "unable to read the current version of .#$package_name" >&2
    exit 1
  fi
  if [[ "$current_version" == unstable-* || "$current_version" == *-unstable ]]; then
    nix_update_args+=(--version unstable)
  fi
  nix_update_args+=("$package_name")
  if ! ensure_nix_update_command; then
    exit 1
  fi

  run_update "Updating .#$package_name" "${nix_update_command[@]}" "${nix_update_args[@]}"
  after_hash="$(sha256sum "$package_file")"

  if [ "$before_hash" = "$after_hash" ]; then
    status 3 SKIP ".#$package_name already matches upstream; no changes to build"
    continue
  fi

  run_step "Building .#$package_name" nix build ".#$package_name"

  status 2 DONE ".#$package_name is updated and builds successfully"
done
