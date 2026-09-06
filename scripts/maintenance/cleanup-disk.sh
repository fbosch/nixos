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

copy_report() {
  local report="$1" encoded

  if [[ -n ${SSH_CONNECTION:-} ]]; then
    if ! encoded="$(printf '%s\n' "$report" | base64 --wrap=0)"; then
      gum style --foreground 1 "Could not encode the report for the terminal clipboard."
      return
    fi

    if printf '\033]52;c;%s\a' "$encoded" >/dev/tty; then
      gum style --foreground 10 "Report sent to the terminal clipboard."
    else
      gum style --foreground 1 "The terminal clipboard did not accept the report."
    fi
    return
  fi

  if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-copy >/dev/null; then
    if printf '%s\n' "$report" | wl-copy; then
      gum style --foreground 10 "Report copied to the clipboard."
    else
      gum style --foreground 1 "wl-copy could not copy the report."
    fi
    return
  fi

  if [[ -n ${DISPLAY:-} ]] && command -v xclip >/dev/null; then
    if printf '%s\n' "$report" | xclip -selection clipboard; then
      gum style --foreground 10 "Report copied to the clipboard."
    else
      gum style --foreground 1 "xclip could not copy the report."
    fi
    return
  fi

  if [[ -n ${DISPLAY:-} ]] && command -v xsel >/dev/null; then
    if printf '%s\n' "$report" | xsel --clipboard --input; then
      gum style --foreground 10 "Report copied to the clipboard."
    else
      gum style --foreground 1 "xsel could not copy the report."
    fi
    return
  fi

  if command -v pbcopy >/dev/null; then
    if printf '%s\n' "$report" | pbcopy; then
      gum style --foreground 10 "Report copied to the clipboard."
    else
      gum style --foreground 1 "pbcopy could not copy the report."
    fi
    return
  fi

  gum style --foreground 1 "No supported clipboard command is available."
}

show_report() {
  local report="$1" result

  if ! command -v fzf >/dev/null; then
    printf '%s\n' "$report" | gum pager --show-line-numbers=false --no-soft-wrap
    if gum confirm "Copy this report to the clipboard?"; then
      copy_report "$report"
    fi
    return
  fi

  if result="$(
    printf '%s\n' "$report" |
      fzf \
        --ansi \
        --no-sort \
        --wrap \
        --layout=reverse-list \
        --height=100% \
        --border=rounded \
        --header='Type to filter • y copy all • q close' \
        --header-first \
        --prompt='Filter: ' \
        --expect=y \
        --bind='q:abort,enter:ignore'
  )"; then
    if [[ ${result%%$'\n'*} == y ]]; then
      copy_report "$report"
    fi
  fi
}

show_disk_usage() {
  section "Root filesystem"
  gum style --border rounded --padding "0 1" "$(df -h /)"
}

inspect_home() {
  local report

  section "Home directory usage"

  if command -v dust >/dev/null; then
    if report="$(
      dust \
        --reverse \
        --depth 2 \
        --number-of-lines 40 \
        --min-size 100M \
        --only-dir \
        --no-percent-bars \
        --no-colors \
        --no-progress \
        "$HOME"
    )"; then
      show_report "$report"
    else
      gum style --foreground 1 "Could not inspect the home directory."
    fi
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

  report="$({
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
  })"

  show_report "$report"
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

  show_report "$report"
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

  show_report "$report"
}

# containers/image removes these directories when an image destination closes;
# surviving directories belong to interrupted image-copy operations.
manage_system_podman_temp_storage() {
  local mode="$1"
  shift

  sudo bash -s -- "$mode" "$@" <<'ROOT'
set -uo pipefail

mode="$1"
shift
readonly temp_root="/var/tmp"
readonly minimum_age_seconds=900
podman_socket_was_active=false
podman_service_was_active=false

if [[ $mode != report && $mode != clean ]]; then
  printf 'Unsupported Podman temporary-storage operation: %s\n' "$mode" >&2
  exit 2
fi

if [[ $(readlink -f -- "$temp_root") != "$temp_root" ]]; then
  printf '%s must not be a symbolic link.\n' "$temp_root" >&2
  exit 1
fi

has_mount() {
  local directory="$1" mountpoint mountpoints

  if ! mountpoints="$(findmnt -rn -o TARGET)"; then
    printf 'Could not inspect mountpoints before Podman temporary-storage cleanup.\n' >&2
    return 2
  fi

  while IFS= read -r mountpoint; do
    case "$mountpoint" in
    "$directory" | "$directory"/*) return 0 ;;
    esac
  done <<<"$mountpoints"

  return 1
}

is_stale_temp_directory() {
  local directory="$1" name metadata modified now mount_status

  name="${directory##*/}"
  [[ $directory =~ ^/var/tmp/container_images_storage[0-9]+$ ]] || return 1
  [[ $name =~ ^container_images_storage[0-9]+$ ]] || return 1
  [[ -d $directory && ! -L $directory ]] || return 1

  metadata="$(stat -c '%u:%g:%Y' -- "$directory")" || return 1
  [[ ${metadata%%:*} == 0 && ${metadata#*:} == 0:* ]] || return 1
  modified="${metadata##*:}"
  now="$(date +%s)"
  ((now - modified > minimum_age_seconds)) || return 1

  has_mount "$directory"
  mount_status=$?
  case "$mount_status" in
  0)
    printf 'Skipping mounted Podman temporary path: %s\n' "$directory" >&2
    return 1
    ;;
  1) ;;
  *) return 1 ;;
  esac
}

report_candidates() {
  local directory identity size
  local -a directories=("$temp_root"/container_images_storage*)

  if ((${#directories[@]} > 1000)); then
    printf 'Refusing to inspect %s Podman temporary directories at once.\n' "${#directories[@]}" >&2
    return 1
  fi

  for directory in "${directories[@]}"; do
    is_stale_temp_directory "$directory" || continue
    identity="$(stat -c '%d:%i' -- "$directory")" || return 1
    size="$(du -sx -B1 -- "$directory" | cut -f1)" || return 1
    printf '%s\t%s\t%s\t%s\n' \
      "$size" \
      "$(stat -c '%y' -- "$directory")" \
      "$identity" \
      "$directory"
  done
}

producer_is_running() {
  local process executable name

  for process in /proc/[0-9]*; do
    executable="$(readlink "$process/exe" 2>/dev/null)" || continue
    name="${executable##*/}"
    case "$name" in
    podman | .podman-wrapped)
      if grep -Eq '/podman-pause-[^/]+\.scope$' "$process/cgroup" 2>/dev/null; then
        continue
      fi
      ;;
    buildah | skopeo) ;;
    *) continue ;;
    esac

    printf 'Image-copy process is still running: PID %s (%s)\n' "${process##*/}" "$name" >&2
    return 0
  done

  return 1
}

clean_candidates() {
  local entry expected_identity directory current_identity size
  local status=0

  systemctl --quiet is-active podman.socket && podman_socket_was_active=true
  systemctl --quiet is-active podman.service && podman_service_was_active=true

  restore_podman_api() {
    local restore_status=0

    if [[ $podman_socket_was_active == true ]]; then
      systemctl start podman.socket || restore_status=1
    fi
    if [[ $podman_service_was_active == true ]]; then
      systemctl start podman.service || restore_status=1
    fi

    return "$restore_status"
  }

  trap 'restore_podman_api || true' EXIT

  if ! systemctl stop podman.socket; then
    printf 'Could not stop podman.socket.\n' >&2
    return 1
  fi
  if ! systemctl stop podman.service; then
    printf 'Could not stop podman.service.\n' >&2
    return 1
  fi
  if producer_is_running; then
    printf 'Stop active Podman, Buildah, or Skopeo operations before cleaning temporary storage.\n' >&2
    return 1
  fi

  for entry in "$@"; do
    expected_identity="${entry%%|*}"
    directory="${entry#*|}"

    if ! is_stale_temp_directory "$directory"; then
      printf 'skipped\t0\t%s\tno longer eligible\n' "$directory"
      status=1
      continue
    fi

    current_identity="$(stat -c '%d:%i' -- "$directory")" || {
      printf 'skipped\t0\t%s\tcould not verify identity\n' "$directory"
      status=1
      continue
    }
    if [[ $current_identity != "$expected_identity" ]]; then
      printf 'skipped\t0\t%s\tidentity changed after approval\n' "$directory"
      status=1
      continue
    fi

    size="$(du -sx -B1 -- "$directory" | cut -f1)" || {
      printf 'skipped\t0\t%s\tcould not measure allocation\n' "$directory"
      status=1
      continue
    }
    if rm -rf --one-file-system -- "$directory" && [[ ! -e $directory ]]; then
      printf 'removed\t%s\t%s\n' "$size" "$directory"
    else
      printf 'failed\t%s\t%s\tremoval incomplete\n' "$size" "$directory"
      status=1
    fi
  done

  if ! restore_podman_api; then
    printf 'Could not restore the Podman API service state.\n' >&2
    status=1
  fi
  trap - EXIT

  return "$status"
}

case "$mode" in
report)
  report_candidates
  ;;
clean)
  clean_candidates "$@"
  ;;
esac
ROOT
}

clean_system_podman_temp_storage() {
  local raw_report report cleanup_report removed_report
  local candidate_count candidate_size removed_count removed_size
  local before_available after_available available_gain cleanup_status
  local _size _modified identity path
  local -a approved_candidates=()

  section "Stale system Podman temporary storage"

  if ! raw_report="$(manage_system_podman_temp_storage report)"; then
    gum style --foreground 1 "Could not inspect system Podman temporary storage."
    return
  fi

  if [[ -z $raw_report ]]; then
    gum style --foreground 10 "No stale system Podman temporary directories were found."
    return
  fi

  while IFS=$'\t' read -r _size _modified identity path; do
    approved_candidates+=("${identity}|${path}")
  done <<<"$raw_report"

  candidate_count="${#approved_candidates[@]}"
  candidate_size="$(printf '%s\n' "$raw_report" | awk -F '\t' '{ total += $1 } END { printf "%.0f", total }')"

  report="$({
    printf 'Stale root-owned Podman image-copy directories\n'
    printf 'Candidates: %s\n' "$candidate_count"
    printf 'Estimated allocated size: %s\n' "$(numfmt --to=iec-i --suffix=B "$candidate_size")"
    printf 'Selection: older than 15 minutes, with no nested mounts\n'
    printf '\nALLOCATED\tMODIFIED\tPATH\n'
    printf '%s\n' "$raw_report" |
      sort -n |
      awk -F '\t' 'BEGIN { OFS = "\t" } { print $1, $2, $4 }' |
      numfmt --field=1 --to=iec-i --suffix=B
  })"

  show_report "$report"

  gum style --foreground 214 \
    "Cleanup briefly stops the rootful Podman API; running containers remain running."
  if ! gum confirm "Permanently delete these ${candidate_count} stale Podman temporary directories?"; then
    return
  fi

  before_available="$(df --output=avail -B1 / | tail -1 | tr -d ' ')"
  if cleanup_report="$(manage_system_podman_temp_storage clean "${approved_candidates[@]}")"; then
    cleanup_status=0
  else
    cleanup_status=$?
  fi
  after_available="$(df --output=avail -B1 / | tail -1 | tr -d ' ')"
  available_gain="$((after_available - before_available))"
  ((available_gain >= 0)) || available_gain=0

  removed_report="$(printf '%s\n' "$cleanup_report" | awk -F '\t' '$1 == "removed"')"
  if [[ -n $removed_report ]]; then
    removed_count="$(printf '%s\n' "$removed_report" | wc -l)"
    removed_size="$(printf '%s\n' "$removed_report" | awk -F '\t' '{ total += $2 } END { printf "%.0f", total }')"
    gum style --foreground 10 \
      "Removed ${removed_count} directories (estimated $(numfmt --to=iec-i --suffix=B "$removed_size"); available space increased by $(numfmt --to=iec-i --suffix=B "$available_gain"))."
  else
    gum style --foreground 214 "No approved directories were removed."
  fi

  if ((cleanup_status != 0)); then
    printf '%s\n' "$cleanup_report" | awk -F '\t' '$1 != "removed"'
    gum style --foreground 1 "Some directories were skipped or could not be removed."
  fi
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

  report="$(
    printf 'ALLOCATED\tPID\tPROCESS\tDELETED FILE\n'
    printf '%s\n' "$report"
  )"

  show_report "$report"
}

prune_user_podman_images() {
  if ! command -v podman >/dev/null; then
    gum style --foreground 214 "podman is unavailable in this environment."
    return
  fi

  if ! gum confirm "Delete dangling user Podman images?"; then
    return
  fi

  if podman image prune --force; then
    gum style --foreground 10 "Dangling user Podman images removed."
  else
    gum style --foreground 1 "Could not prune user Podman images."
  fi
}

prune_system_podman_images() {
  if ! command -v podman >/dev/null; then
    gum style --foreground 214 "podman is unavailable in this environment."
    return
  fi

  if ! gum confirm "Delete dangling system Podman images?"; then
    return
  fi

  if sudo podman image prune --force; then
    gum style --foreground 10 "Dangling system Podman images removed."
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
    "Clean stale system Podman temporary storage" \
    "Inspect deleted files still held open" \
    "Collect unreachable Nix store paths" \
    "Prune dangling user Podman images" \
    "Prune dangling system Podman images" \
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
  "Clean stale system Podman temporary storage")
    clean_system_podman_temp_storage
    ;;
  "Inspect deleted files still held open")
    inspect_deleted_open_files
    ;;
  "Collect unreachable Nix store paths")
    collect_nix_garbage
    ;;
  "Prune dangling user Podman images")
    prune_user_podman_images
    ;;
  "Prune dangling system Podman images")
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
