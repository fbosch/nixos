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
    "Collect unreachable Nix store paths" \
    "Empty XDG Trash" \
    "Exit")"

  case "$action" in
  "Inspect home directory usage")
    inspect_home
    ;;
  "Collect unreachable Nix store paths")
    collect_nix_garbage
    ;;
  "Empty XDG Trash")
    empty_trash
    ;;
  "Exit")
    exit 0
    ;;
  esac
done
