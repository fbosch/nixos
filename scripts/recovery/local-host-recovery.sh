#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly manifests_dir="$script_dir/manifests"
readonly persist_root="${LOCAL_HOST_RECOVERY_PERSIST_ROOT:-/persist}"
readonly target_only="${LOCAL_HOST_RECOVERY_TARGET_ONLY:-false}"

declare manifest_destination=""
declare manifest_mount_source=""
declare -a source_types=()
declare -a source_paths=()
declare -a backup_ids=()
declare resolved_backup_id=""

staging_dir=""
list_file=""
checksum_value=""

usage() {
  cat <<'EOF'
Usage:
  local-host-recovery.sh check
  local-host-recovery.sh backup
  local-host-recovery.sh list [--host <host>]
  local-host-recovery.sh verify [--host <host>] <backup-id|--latest>
  local-host-recovery.sh compare [--host <host>] <backup-id|--latest>
  local-host-recovery.sh restore [--host <host>] <backup-id|--latest> [--yes]

Create, verify, compare, or restore a recovery archive using a checked-in host manifest.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

usage_error() {
  printf 'Error: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

cleanup() {
  if [[ -n $list_file ]]; then
    rm -f -- "$list_file"
  fi

  if [[ -n $staging_dir ]]; then
    rm -rf -- "$staging_dir"
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

validate_absolute_path() {
  local label="$1"
  local path="$2"
  local normalized

  [[ $path == /* ]] || die "$label must be an absolute path: $path"
  [[ $path != *$'\t'* && $path != *$'\n'* ]] || die "$label contains an unsupported control character"

  normalized="$(realpath -m -- "$path")"
  [[ $normalized == "$path" ]] || die "$label must be normalized: $path"
}

paths_overlap() {
  local first="$1"
  local second="$2"

  [[ $first == "$second" || $first == "$second/"* || $second == "$first/"* ]]
}

parse_manifest() {
  local manifest="$1"
  local state="version"
  local line directive first second extra
  local existing_path

  [[ -r $manifest ]] || die "host recovery manifest is missing or unreadable: $manifest"

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue

    IFS=$'\t' read -r directive first second extra <<<"$line"
    [[ -z ${extra:-} ]] || die "manifest record has too many fields: $directive"

    case "$state:$directive" in
    version:version)
      [[ $first == "1" && -z ${second:-} ]] || die "unsupported recovery manifest version"
      state="destination"
      ;;
    destination:destination)
      [[ -n $first && -z ${second:-} ]] || die "invalid destination record"
      validate_absolute_path "manifest destination" "$first"
      manifest_destination="$first"
      state="mount-source"
      ;;
    mount-source:mount-source)
      [[ -n $first && -z ${second:-} ]] || die "invalid mount-source record"
      manifest_mount_source="$first"
      state="source"
      ;;
    source:source)
      [[ $first == "file" ]] || die "unsupported source type: $first"
      [[ -n ${second:-} ]] || die "source path is missing"
      validate_absolute_path "source path" "$second"

      if paths_overlap "$manifest_destination" "$second"; then
        die "source path overlaps the backup destination: $second"
      fi

      for existing_path in "${source_paths[@]}"; do
        if paths_overlap "$existing_path" "$second"; then
          die "source paths overlap: $existing_path and $second"
        fi
      done

      source_types+=("$first")
      source_paths+=("$second")
      ;;
    *) die "unexpected manifest record '$directive' while expecting '$state'" ;;
    esac
  done <"$manifest"

  [[ $state == "source" ]] || die "recovery manifest is incomplete"
  ((${#source_paths[@]} > 0)) || die "recovery manifest has no source records"
}

validate_destination() {
  local canonical_destination
  local -a mount_sources mount_targets

  [[ -d $manifest_destination && ! -L $manifest_destination ]] ||
    die "backup destination must be an existing directory: $manifest_destination"

  canonical_destination="$(realpath -e -- "$manifest_destination")"
  [[ $canonical_destination == "$manifest_destination" ]] ||
    die "backup destination must not contain symlinks: $manifest_destination"

  stat --file-system --format='%T' "$manifest_destination" >/dev/null
  mapfile -t mount_sources < <(findmnt -n -T "$manifest_destination" -t cifs -o SOURCE)
  mapfile -t mount_targets < <(findmnt -n -T "$manifest_destination" -t cifs -o TARGET)

  ((${#mount_sources[@]} == 1 && ${#mount_targets[@]} == 1)) ||
    die "backup destination does not resolve to exactly one CIFS mount: $manifest_destination"
  [[ ${mount_sources[0]} == "$manifest_mount_source" ]] ||
    die "backup destination resolved to unexpected mount source: ${mount_sources[0]}"
  [[ ${mount_targets[0]} == "$manifest_destination" ]] ||
    die "CIFS mount target differs from the backup destination: ${mount_targets[0]}"
}

validate_sources() {
  local index source_type source_path

  for index in "${!source_paths[@]}"; do
    source_type="${source_types[$index]}"
    source_path="${source_paths[$index]}"

    case "$source_type" in
    file)
      [[ -f $source_path && ! -L $source_path ]] ||
        die "required recovery file is missing or has the wrong type: $source_path"
      ;;
    esac
  done
}

ensure_host_destination() {
  local host="$1"
  local host_destination="$manifest_destination/$host"

  if [[ -e $host_destination ]]; then
    [[ -d $host_destination && ! -L $host_destination ]] ||
      die "host backup destination is not a directory: $host_destination"
  else
    mkdir --mode=0700 -- "$host_destination"
  fi

  printf '%s\n' "$host_destination"
}

write_source_list() {
  local source_path

  list_file="$1"
  : >"$list_file"
  for source_path in "${source_paths[@]}"; do
    printf '%s\0' "${source_path#/}" >>"$list_file"
  done
}

calculate_digest() {
  local path="$1"
  local output

  if ! output="$(sha256sum -- "$path")"; then
    die "could not read file while calculating archive digest: $path"
  fi
  [[ $output =~ ^([0-9a-f]{64})[[:space:]] ]] || die "could not calculate archive digest"
  checksum_value="${BASH_REMATCH[1]}"
}

calculate_checksums() {
  local backup_dir="$1"
  local payload_digest manifest_digest

  calculate_digest "$backup_dir/payload.tar"
  payload_digest="$checksum_value"
  calculate_digest "$backup_dir/manifest.tsv"
  manifest_digest="$checksum_value"
  printf -v checksum_value '%s  payload.tar\n%s  manifest.tsv' "$payload_digest" "$manifest_digest"
}

verify_checksums() {
  local backup_dir="$1"
  local expected actual

  calculate_checksums "$backup_dir"
  expected="$checksum_value"
  actual="$(<"$backup_dir/SHA256SUMS")"
  [[ $actual == "$expected" ]] || die "backup checksum verification failed"
}

verify_archive_members() {
  local backup_dir="$1"
  local expected=""
  local actual verbose_members source_path member

  for source_path in "${source_paths[@]}"; do
    expected+="${source_path#/}"$'\n'
  done
  expected="${expected%$'\n'}"
  actual="$(tar --list --file="$backup_dir/payload.tar")" || die "backup archive is unreadable"
  [[ $actual == "$expected" ]] || die "backup archive members differ from the host manifest"

  verbose_members="$(tar --list --verbose --file="$backup_dir/payload.tar")" || die "backup archive metadata is unreadable"
  while IFS= read -r member; do
    [[ ${member:0:1} == "-" ]] || die "backup archive contains a non-regular member"
  done <<<"$verbose_members"
}

create_backup() {
  local host="$1"
  local manifest="$2"
  local host_destination backup_id final_dir archive source_list

  validate_sources
  host_destination="$(ensure_host_destination "$host")"
  backup_id="$(date -u +%Y%m%dT%H%M%SZ)-p$$"
  final_dir="$host_destination/$backup_id"
  [[ ! -e $final_dir ]] || die "backup ID already exists: $backup_id"

  staging_dir="$(mktemp -d "$host_destination/.partial-$backup_id.XXXXXX")"
  chmod 0700 "$staging_dir"
  archive="$staging_dir/payload.tar"
  source_list="$staging_dir/source-list"
  write_source_list "$source_list"

  tar \
    --create \
    --file="$archive" \
    --format=pax \
    --numeric-owner \
    --acls \
    --xattrs \
    --sparse \
    --directory=/ \
    --null \
    --files-from="$source_list"
  tar --list --file="$archive" >/dev/null

  install --mode=0600 -- "$manifest" "$staging_dir/manifest.tsv"
  rm -f -- "$source_list"
  list_file=""

  calculate_checksums "$staging_dir"
  printf '%s\n' "$checksum_value" >"$staging_dir/SHA256SUMS"
  verify_checksums "$staging_dir"
  chmod 0600 "$archive" "$staging_dir/SHA256SUMS"

  mv --no-target-directory -- "$staging_dir" "$final_dir"
  staging_dir=""
  validate_backup_set "$final_dir" "$manifest"
  printf 'Backup complete: host=%s id=%s\n' "$host" "$backup_id"
}

validate_backup_set() {
  local backup_dir="$1"
  local manifest="$2"
  local -a entries

  [[ -d $backup_dir && ! -L $backup_dir ]] || die "backup set does not exist: $backup_dir"
  for entry in payload.tar manifest.tsv SHA256SUMS; do
    [[ -f "$backup_dir/$entry" && ! -L "$backup_dir/$entry" ]] ||
      die "backup set is missing required file: $entry"
  done

  shopt -s nullglob dotglob
  entries=("$backup_dir"/*)
  shopt -u nullglob dotglob
  ((${#entries[@]} == 3)) || die "backup set contains unexpected files"

  cmp --silent -- "$manifest" "$backup_dir/manifest.tsv" ||
    die "backup manifest differs from the current host manifest"
  verify_checksums "$backup_dir"
  verify_archive_members "$backup_dir"
}

verify_backup() {
  local host="$1"
  local manifest="$2"
  local backup_id="$3"
  local host_destination backup_dir

  [[ $backup_id =~ ^[0-9]{8}T[0-9]{6}Z-p[0-9]+$ ]] || usage_error "invalid backup ID: $backup_id"
  host_destination="$manifest_destination/$host"
  [[ -d $host_destination && ! -L $host_destination ]] ||
    die "host backup destination does not exist: $host_destination"
  backup_dir="$host_destination/$backup_id"

  validate_backup_set "$backup_dir" "$manifest"
  printf 'Backup verified: host=%s id=%s\n' "$host" "$backup_id"
}

resolve_current_source() {
  local source_path="$1"
  local persistent_path="$persist_root$source_path"

  current_source_path=""
  if [[ -f $persistent_path && ! -L $persistent_path ]]; then
    current_source_path="$persistent_path"
  elif [[ $target_only != true && -f $source_path && ! -L $source_path ]]; then
    current_source_path="$source_path"
  fi
}

validate_persistence_root() {
  local canonical_root

  [[ -d $persist_root && ! -L $persist_root ]] || die "persistence root must be a real directory: $persist_root"
  canonical_root="$(realpath -e -- "$persist_root")"
  [[ $canonical_root == "$persist_root" && $canonical_root != / ]] ||
    die "persistence root must be a canonical non-root directory: $persist_root"
}

validate_restore_parents() {
  local source_path relative parent component current
  local -a components

  for source_path in "${source_paths[@]}"; do
    relative="${source_path#/}"
    parent="${relative%/*}"
    current="$persist_root"
    IFS=/ read -r -a components <<<"$parent"
    for component in "${components[@]}"; do
      current="$current/$component"
      [[ ! -L $current ]] || die "persistent restore parent must not be a symlink: $current"
      [[ ! -e $current || -d $current ]] || die "persistent restore parent is not a directory: $current"
    done
  done
}

prepare_fresh_restore_parents() {
  local source_path relative parent

  for source_path in "${source_paths[@]}"; do
    relative="${source_path#/}"
    parent="${relative%/*}"
    install --directory --mode=0700 -- "$persist_root/$parent"
  done
}

compare_backup() {
  local host="$1"
  local manifest="$2"
  local backup_id="$3"
  local host_destination backup_dir source_path member
  local current_source_path=""
  local mismatches=0

  [[ $backup_id =~ ^[0-9]{8}T[0-9]{6}Z-p[0-9]+$ ]] || usage_error "invalid backup ID: $backup_id"
  host_destination="$manifest_destination/$host"
  [[ -d $host_destination && ! -L $host_destination ]] ||
    die "host backup destination does not exist: $host_destination"
  backup_dir="$host_destination/$backup_id"

  validate_backup_set "$backup_dir" "$manifest"
  if [[ $target_only == true ]]; then
    validate_persistence_root
    validate_restore_parents
  fi
  for source_path in "${source_paths[@]}"; do
    member="${source_path#/}"
    resolve_current_source "$source_path"
    if [[ -z $current_source_path ]]; then
      printf 'MISSING   %s\n' "$source_path"
      ((mismatches += 1))
    elif cmp --silent -- "$current_source_path" <(tar --extract --to-stdout --file="$backup_dir/payload.tar" "$member"); then
      printf 'MATCH     %s\n' "$source_path"
    else
      printf 'MISMATCH  %s\n' "$source_path"
      ((mismatches += 1))
    fi
  done

  ((mismatches == 0)) ||
    die "recovery comparison failed: host=$host id=$backup_id mismatches=$mismatches"
  printf 'Recovery comparison passed: host=%s id=%s sources=%s\n' "$host" "$backup_id" "${#source_paths[@]}"
}

ensure_directory() {
  local path="$1"

  if [[ -e $path ]]; then
    [[ -d $path && ! -L $path ]] || die "recovery path is not a directory: $path"
  else
    mkdir --mode=0700 -- "$path"
  fi
}

create_restore_rollback() {
  local host="$1"
  local manifest="$2"
  local backup_id="$3"
  local rollback_root rollback_id final_dir archive source_list source_path

  for source_path in "${source_paths[@]}"; do
    [[ -f "$persist_root$source_path" && ! -L "$persist_root$source_path" ]] ||
      die "persistent restore target is missing or has the wrong type: $persist_root$source_path"
  done

  ensure_directory "$manifest_destination/.rollbacks"
  rollback_root="$manifest_destination/.rollbacks/$host"
  ensure_directory "$rollback_root"
  rollback_id="$(date -u +%Y%m%dT%H%M%SZ)-before-$backup_id-p$$"
  final_dir="$rollback_root/$rollback_id"
  [[ ! -e $final_dir ]] || die "rollback ID already exists: $rollback_id"

  staging_dir="$(mktemp -d "$rollback_root/.partial-$rollback_id.XXXXXX")"
  chmod 0700 "$staging_dir"
  archive="$staging_dir/payload.tar"
  source_list="$staging_dir/source-list"
  write_source_list "$source_list"

  tar \
    --create \
    --file="$archive" \
    --format=pax \
    --numeric-owner \
    --acls \
    --xattrs \
    --sparse \
    --directory="$persist_root" \
    --null \
    --files-from="$source_list"
  install --mode=0600 -- "$manifest" "$staging_dir/manifest.tsv"
  rm -f -- "$source_list"
  list_file=""

  calculate_checksums "$staging_dir"
  printf '%s\n' "$checksum_value" >"$staging_dir/SHA256SUMS"
  verify_checksums "$staging_dir"
  chmod 0600 "$archive" "$staging_dir/SHA256SUMS"

  mv --no-target-directory -- "$staging_dir" "$final_dir"
  staging_dir=""
  validate_backup_set "$final_dir" "$manifest"
  printf '%s\n' "$final_dir"
}

restore_backup() {
  local host="$1"
  local manifest="$2"
  local backup_id="$3"
  local assume_yes="$4"
  local host_destination backup_dir rollback_dir reply source_path
  local present_targets=0

  [[ $backup_id =~ ^[0-9]{8}T[0-9]{6}Z-p[0-9]+$ ]] || usage_error "invalid backup ID: $backup_id"
  host_destination="$manifest_destination/$host"
  [[ -d $host_destination && ! -L $host_destination ]] ||
    die "host backup destination does not exist: $host_destination"
  backup_dir="$host_destination/$backup_id"
  validate_backup_set "$backup_dir" "$manifest"
  validate_persistence_root
  validate_restore_parents
  for source_path in "${source_paths[@]}"; do
    if [[ -e $persist_root$source_path ]]; then
      [[ -f $persist_root$source_path && ! -L $persist_root$source_path ]] ||
        die "persistent restore target has the wrong type: $persist_root$source_path"
      ((present_targets += 1))
    fi
  done
  if ((present_targets != 0 && present_targets != ${#source_paths[@]})); then
    die "persistent restore target contains a partial identity set"
  fi
  if [[ $assume_yes != true ]]; then
    [[ -t 0 ]] || usage_error "restore requires --yes when no interactive terminal is available"
    printf 'Restore recovery archive %s on %s? [y/N] ' "$backup_id" "$host" >&2
    IFS= read -r reply
    case "$reply" in
    y | Y | yes | YES) ;;
    *)
      printf 'Restore cancelled.\n'
      return
      ;;
    esac
  fi

  if ((present_targets == 0)); then
    prepare_fresh_restore_parents
    printf 'Fresh persistence target verified; no rollback was required.\n'
  else
    rollback_dir="$(create_restore_rollback "$host" "$manifest" "$backup_id")"
    printf 'Rollback created: %s\n' "$rollback_dir"
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl --quiet is-active mullvad-daemon.service; then
    systemctl stop mullvad-daemon.service
    printf 'Service stopped: mullvad-daemon.service\n'
  fi

  tar \
    --extract \
    --file="$backup_dir/payload.tar" \
    --directory="$persist_root" \
    --same-owner \
    --numeric-owner \
    --acls \
    --xattrs \
    --overwrite

  compare_backup "$host" "$manifest" "$backup_id"
  printf 'Recovery restored: host=%s id=%s sources=%s\n' "$host" "$backup_id" "${#source_paths[@]}"
  printf 'Rebuild and reboot this host before remote use.\n'
}

collect_backup_ids() {
  local host="$1"
  local host_destination="$manifest_destination/$host"
  local candidate backup_id

  backup_ids=()
  [[ -e $host_destination ]] || return 0
  [[ -d $host_destination && ! -L $host_destination ]] ||
    die "host backup destination is not a directory: $host_destination"

  shopt -s nullglob
  for candidate in "$host_destination"/*; do
    backup_id="${candidate##*/}"
    [[ -d $candidate && ! -L $candidate ]] || die "unexpected entry in host backup destination: $backup_id"
    [[ $backup_id =~ ^[0-9]{8}T[0-9]{6}Z-p[0-9]+$ ]] || die "invalid backup directory name: $backup_id"
    backup_ids+=("$backup_id")
  done
  shopt -u nullglob
}

format_backup_age() {
  local backup_id="$1"
  local timestamp created_epoch current_epoch delta value unit suffix

  timestamp="${backup_id%%-p*}"
  if ! created_epoch="$(date -u --date="${timestamp:0:4}-${timestamp:4:2}-${timestamp:6:2} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2} UTC" +%s)"; then
    die "backup ID contains an invalid timestamp: $backup_id"
  fi
  current_epoch="$(date -u +%s)"
  delta=$((current_epoch - created_epoch))
  suffix="ago"
  if ((delta < 0)); then
    delta=$((-delta))
    suffix="from now"
  fi

  if ((delta < 60)); then
    value="$delta"
    unit="second"
  elif ((delta < 3600)); then
    value=$((delta / 60))
    unit="minute"
  elif ((delta < 86400)); then
    value=$((delta / 3600))
    unit="hour"
  else
    value=$((delta / 86400))
    unit="day"
  fi
  [[ $value == "1" ]] || unit+="s"
  printf '%s %s %s\n' "$value" "$unit" "$suffix"
}

list_backups() {
  local host="$1"
  local index backup_id age

  collect_backup_ids "$host"
  if ((${#backup_ids[@]} == 0)); then
    printf 'No recovery backups found: host=%s\n' "$host"
    return
  fi

  printf 'Recovery backups: host=%s\n' "$host"
  for ((index = ${#backup_ids[@]} - 1; index >= 0; index--)); do
    backup_id="${backup_ids[$index]}"
    age="$(format_backup_age "$backup_id")"
    printf '  %s  %s\n' "$backup_id" "$age"
  done
}

resolve_backup_id() {
  local host="$1"
  local selector="$2"

  if [[ $selector == --latest ]]; then
    collect_backup_ids "$host"
    ((${#backup_ids[@]} > 0)) || die "no recovery backups found for host: $host"
    resolved_backup_id="${backup_ids[${#backup_ids[@]} - 1]}"
  else
    [[ $selector =~ ^[0-9]{8}T[0-9]{6}Z-p[0-9]+$ ]] || usage_error "invalid backup ID: $selector"
    resolved_backup_id="$selector"
  fi
}

main() {
  local operation="${1:-}"
  local running_host selected_host backup_id assume_yes="false" manifest

  case "$operation" in
  -h | --help | help)
    (($# == 1)) || usage_error "help does not accept additional arguments"
    usage
    return
    ;;
  check | backup)
    (($# == 1)) || usage_error "$operation does not accept additional arguments"
    ;;
  list)
    case "$#:${2:-}" in
    1:*) selected_host="" ;;
    3:--host) selected_host="$3" ;;
    *) usage_error "$operation accepts only [--host <host>]" ;;
    esac
    ;;
  verify | compare)
    case "$#:${2:-}" in
    2:*)
      selected_host=""
      backup_id="$2"
      ;;
    4:--host)
      selected_host="$3"
      backup_id="$4"
      ;;
    *) usage_error "$operation requires [--host <host>] and one backup ID" ;;
    esac
    ;;
  restore)
    case "$#:${2:-}:${5:-}" in
    2:*:*)
      selected_host=""
      backup_id="$2"
      ;;
    3:*:*)
      [[ $3 == --yes ]] || usage_error "restore accepts only --yes after the backup ID"
      selected_host=""
      backup_id="$2"
      assume_yes="true"
      ;;
    4:--host:*)
      [[ -n $3 && $3 != -* ]] || usage_error "restore --host requires a host name"
      selected_host="$3"
      backup_id="$4"
      ;;
    5:--host:--yes)
      [[ -n $3 && $3 != -* ]] || usage_error "restore --host requires a host name"
      selected_host="$3"
      backup_id="$4"
      assume_yes="true"
      ;;
    *) usage_error "restore requires [--host <host>] <backup-id|--latest> [--yes]" ;;
    esac
    ;;
  "") usage_error "an operation is required" ;;
  *) usage_error "unknown operation: $operation" ;;
  esac

  [[ "$(id -u)" == "0" ]] || die "run this command as root"
  for command in cmp date findmnt hostname install mktemp mv realpath sha256sum stat tar; do
    require_command "$command"
  done

  running_host="$(hostname -s)"
  selected_host="${selected_host:-$running_host}"
  [[ $running_host =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || die "unsupported hostname: $running_host"
  [[ $selected_host =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || die "unsupported recovery host: $selected_host"
  manifest="$manifests_dir/$selected_host.tsv"
  validate_absolute_path "persistence root" "$persist_root"
  parse_manifest "$manifest"
  validate_destination

  if [[ $operation == restore && $persist_root == /persist && $selected_host != "$running_host" ]]; then
    die "foreign-host restore requires an explicit non-default persistence root"
  fi

  if [[ $operation == verify || $operation == compare || $operation == restore ]]; then
    resolve_backup_id "$selected_host" "$backup_id"
    backup_id="$resolved_backup_id"
  fi

  case "$operation" in
  check)
    validate_sources
    printf 'Recovery check passed: host=%s sources=%s destination=%s\n' "$selected_host" "${#source_paths[@]}" "$manifest_destination"
    ;;
  backup)
    [[ $selected_host == "$running_host" ]] || die "backup host must match the running host"
    create_backup "$selected_host" "$manifest"
    ;;
  list) list_backups "$selected_host" ;;
  verify) verify_backup "$selected_host" "$manifest" "$backup_id" ;;
  compare) compare_backup "$selected_host" "$manifest" "$backup_id" ;;
  restore) restore_backup "$selected_host" "$manifest" "$backup_id" "$assume_yes" ;;
  esac
}

main "$@"
