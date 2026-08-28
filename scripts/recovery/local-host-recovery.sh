#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly manifests_dir="$script_dir/manifests"

declare manifest_destination=""
declare manifest_mount_source=""
declare -a source_types=()
declare -a source_paths=()

staging_dir=""
list_file=""
checksum_value=""

usage() {
  cat <<'EOF'
Usage:
  local-host-recovery.sh check
  local-host-recovery.sh backup
  local-host-recovery.sh verify [--host <host>] <backup-id>

Create or verify a recovery archive using a checked-in host manifest.
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

main() {
  local operation="${1:-}"
  local running_host selected_host backup_id manifest

  case "$operation" in
  -h | --help | help)
    (($# == 1)) || usage_error "help does not accept additional arguments"
    usage
    return
    ;;
  check | backup)
    (($# == 1)) || usage_error "$operation does not accept additional arguments"
    ;;
  verify)
    case "$#:${2:-}" in
    2:*)
      selected_host=""
      backup_id="$2"
      ;;
    4:--host)
      selected_host="$3"
      backup_id="$4"
      ;;
    *) usage_error "verify requires [--host <host>] and one backup ID" ;;
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
  parse_manifest "$manifest"
  validate_destination

  case "$operation" in
  check)
    validate_sources
    printf 'Recovery check passed: host=%s sources=%s destination=%s\n' "$selected_host" "${#source_paths[@]}" "$manifest_destination"
    ;;
  backup)
    [[ $selected_host == "$running_host" ]] || die "backup host must match the running host"
    create_backup "$selected_host" "$manifest"
    ;;
  verify) verify_backup "$selected_host" "$manifest" "$backup_id" ;;
  esac
}

main "$@"
