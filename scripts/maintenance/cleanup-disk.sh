#!/usr/bin/env bash

set -euo pipefail

if ! command -v gum >/dev/null; then
  printf 'gum is required for this recipe. Run it through just.\n' >&2
  exit 1
fi

section() {
  gum style \
    --border rounded \
    --border-foreground 212 \
    --foreground 212 \
    --bold \
    --margin "1 0" \
    --padding "0 1" \
    "$1"
}

show_disk_usage() {
  section "Root filesystem"
  gum style --border rounded --padding "0 1" "$(df -h /)"
}

inspect_home() {
  section "Home directory usage"

  if command -v dust >/dev/null; then
    dust \
      --reverse \
      --depth 2 \
      --number-of-lines 40 \
      --min-size 100M \
      --only-dir \
      --no-percent-bars \
      --no-colors \
      --no-progress \
      "$HOME" | gum pager --show-line-numbers=false --no-soft-wrap
    return
  fi

  gum style --foreground 214 "dust is unavailable in this environment."
}

inspect_system_data() {
  local report

  section "System data usage"

  if ! report="$(sudo du -x -B1 --max-depth=2 /var/lib 2>/dev/null)"; then
    gum style --foreground 1 "Could not inspect /var/lib."
    return
  fi

  {
    printf '%s\n' "Root filesystem"
    df -h /
    printf '\n%s\n' "Top-level /var/lib paths"
    printf '%s\n' "$report" |
      awk -F '\t' '$2 == "/var/lib" || $2 ~ "^/var/lib/[^/]+$"' |
      sort -n |
      numfmt --field=1 --to=iec-i --suffix=B
    printf '\n%s\n' "Largest /var/lib paths"
    printf '%s\n' "$report" |
      sort -n |
      tail -80 |
      numfmt --field=1 --to=iec-i --suffix=B
  } | gum pager --show-line-numbers=false --no-soft-wrap
}

inspect_user_podman_storage() {
  local report

  section "User Podman storage"

  if ! command -v podman >/dev/null; then
    gum style --foreground 214 "podman is unavailable in this environment."
    return
  fi

  if ! report="$(podman system df -v 2>&1)"; then
    printf '%s\n' "$report"
    return
  fi

  printf '%s\n' "$report" | gum pager --show-line-numbers=false --no-soft-wrap
}

inspect_system_podman_storage() {
  local report

  section "System Podman storage"

  if ! command -v podman >/dev/null; then
    gum style --foreground 214 "podman is unavailable in this environment."
    return
  fi

  if ! report="$(sudo podman system df -v 2>&1)"; then
    printf '%s\n' "$report"
    return
  fi

  printf '%s\n' "$report" | gum pager --show-line-numbers=false --no-soft-wrap
}

inspect_deleted_open_files() {
  local raw_report report

  section "Deleted files still held open"

  if ! raw_report="$(
    sudo bash <<'ROOT'
declare -A seen=()

for fd in /proc/[0-9]*/fd/*; do
  target="$(readlink "$fd" 2>/dev/null)" || continue
  case "$target" in
  *" (deleted)")
    metadata="$(stat -Lc '%d:%i %b' "$fd" 2>/dev/null)" || continue
    inode="${metadata% *}"
    blocks="${metadata##* }"
    if [[ -v seen[$inode] ]]; then
      continue
    fi
    seen[$inode]=1

    allocated_size="$((blocks * 512))"
    pid="${fd#/proc/}"
    pid="${pid%%/*}"
    process="$(cat "/proc/$pid/comm" 2>/dev/null || printf 'unknown')"
    printf -v process_display '%q' "$process"
    printf -v target_display '%q' "$target"
    printf '%s\t%s\t%s\t%s\n' "$allocated_size" "$pid" "$process_display" "$target_display"
    ;;
  esac
done
ROOT
  )"; then
    gum style --foreground 1 "Could not inspect open files."
    return
  fi

  if [[ -z $raw_report ]]; then
    gum style --foreground 10 "No deleted files are still held open."
    return
  fi

  report="$(
    printf '%s\n' "$raw_report" |
      sort -n |
      tail -30 |
      numfmt --field=1 --to=iec-i --suffix=B
  )"

  {
    printf 'ALLOCATED\tPID\tPROCESS\tDELETED FILE\n'
    printf '%s\n' "$report"
  } | gum pager --show-line-numbers=false --no-soft-wrap
}

prune_user_podman_images() {
  if ! command -v podman >/dev/null; then
    gum style --foreground 214 "podman is unavailable in this environment."
    return
  fi

  if ! gum confirm "Delete every user Podman image not used by a container?"; then
    return
  fi

  if podman image prune --all --force; then
    gum style --foreground 10 "Unused user Podman images removed."
  else
    gum style --foreground 1 "Could not prune user Podman images."
  fi
}

prune_system_podman_images() {
  if ! command -v podman >/dev/null; then
    gum style --foreground 214 "podman is unavailable in this environment."
    return
  fi

  if ! gum confirm "Delete every system Podman image not used by a container?"; then
    return
  fi

  if sudo podman image prune --all --force; then
    gum style --foreground 10 "Unused system Podman images removed."
  else
    gum style --foreground 1 "Could not prune system Podman images."
  fi
}

clean_pnpm_stores() {
  local active_store pnpm_version store_root store store_name
  local -a other_stores=()

  if ! command -v pnpm >/dev/null; then
    gum style --foreground 214 "pnpm is unavailable in this environment."
    return
  fi

  if ! active_store="$(pnpm store path)"; then
    gum style --foreground 1 "Could not locate the active pnpm store."
    return
  fi

  pnpm_version="$(pnpm --version)"
  store_root="$(dirname "$active_store")"

  section "pnpm storage"
  gum style --foreground 244 "Active store for pnpm ${pnpm_version}:"

  if [[ -d $active_store ]]; then
    du -sh "$active_store"

    if gum confirm "Remove unreferenced packages from the active pnpm store?"; then
      if pnpm store prune; then
        gum style --foreground 10 "Unreferenced pnpm packages removed."
      else
        gum style --foreground 1 "Could not prune the active pnpm store."
      fi
    fi
  else
    gum style --foreground 214 "The active pnpm store does not exist yet: ${active_store}"
  fi

  if [[ ! -d $store_root ]]; then
    return
  fi

  while IFS= read -r -d '' store; do
    store_name="${store##*/}"
    if [[ $store != "$active_store" && $store_name =~ ^v[0-9]+$ ]]; then
      other_stores+=("$store")
    fi
  done < <(find "$store_root" -mindepth 1 -maxdepth 1 -type d -print0)

  if ((${#other_stores[@]} == 0)); then
    return
  fi

  gum style --foreground 244 "Other pnpm store versions:"
  du -sh -- "${other_stores[@]}"
  gum style --foreground 214 "Pinned older pnpm versions may need to download these packages again."

  if ! gum confirm "Permanently delete the other pnpm store versions listed above?"; then
    return
  fi

  if rm -rf --one-file-system -- "${other_stores[@]}"; then
    gum style --foreground 10 "Other pnpm store versions removed."
  else
    gum style --foreground 1 "Could not remove other pnpm store versions."
  fi
}

collect_nix_garbage() {
  if ! gum confirm "Delete all unreachable Nix store paths?"; then
    return
  fi

  gum spin --spinner dot --title "Collecting unreachable Nix store paths" -- nix store gc
  gum style --foreground 10 "Nix garbage collection completed."
}

empty_trash() {
  local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
  local -a entries=()

  if [[ ! -d $trash_dir ]]; then
    gum style --foreground 214 "No XDG Trash directory exists."
    return
  fi

  if ! gum confirm "Permanently empty the XDG Trash?"; then
    return
  fi

  shopt -s dotglob nullglob
  entries=("$trash_dir"/files/* "$trash_dir"/info/*)
  shopt -u dotglob nullglob

  if ((${#entries[@]} > 0)); then
    rm -rf -- "${entries[@]}"
  fi

  gum style --foreground 10 "XDG Trash emptied."
}

while true; do
  show_disk_usage

  action="$(gum choose \
    --header "Choose an action" \
    "Inspect home directory usage" \
    "Inspect system data usage" \
    "Inspect user Podman storage" \
    "Inspect system Podman storage" \
    "Inspect deleted files still held open" \
    "Collect unreachable Nix store paths" \
    "Prune unused user Podman images" \
    "Prune unused system Podman images" \
    "Clean pnpm stores" \
    "Empty XDG Trash" \
    "Exit")"

  case "$action" in
  "Inspect home directory usage")
    inspect_home
    ;;
  "Inspect system data usage")
    inspect_system_data
    ;;
  "Inspect user Podman storage")
    inspect_user_podman_storage
    ;;
  "Inspect system Podman storage")
    inspect_system_podman_storage
    ;;
  "Inspect deleted files still held open")
    inspect_deleted_open_files
    ;;
  "Collect unreachable Nix store paths")
    collect_nix_garbage
    ;;
  "Prune unused user Podman images")
    prune_user_podman_images
    ;;
  "Prune unused system Podman images")
    prune_system_podman_images
    ;;
  "Clean pnpm stores")
    clean_pnpm_stores
    ;;
  "Empty XDG Trash")
    empty_trash
    ;;
  "Exit")
    exit 0
    ;;
  esac
done
