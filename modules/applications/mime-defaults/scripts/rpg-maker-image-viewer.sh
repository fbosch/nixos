#!/usr/bin/env bash
set -euo pipefail

cache_root="${RPG_MAKER_CACHE_ROOT:-/tmp/rpg-maker-loupe-$UID}"
RPG_MAKER_DECODER_IDENTITY="${RPG_MAKER_DECODER_IDENTITY:-rpgmasd-unknown}"
lock_timeout=30
active_stage_dir=""

die() {
  local message="$1"
  message="${message//\\n/$'\n'}"
  if ((${#message} > 2000)); then
    message="${message:0:2000}"
    message+=$'\n[details truncated]'
  fi

  printf 'rpg-maker-image-viewer: %s\n' "$message" >&2
  zenity --error \
    --title="Unable to Open RPG Maker Image" \
    --text="$message" \
    2>/dev/null || true
  exit 1
}

cleanup() {
  if [[ -n $active_stage_dir ]]; then
    rm -rf -- "$active_stage_dir"
  fi
}
trap cleanup EXIT

ensure_private_directory() {
  local directory="$1"
  local description="$2"
  local owner

  if [[ -L $directory ]]; then
    die "The $description is a symbolic link and cannot be used: $directory"
  fi

  if [[ ! -e $directory ]]; then
    if ! mkdir --mode=700 -- "$directory" 2>/dev/null && [[ ! -d $directory ]]; then
      die "Unable to create the $description: $directory"
    fi
  fi

  if [[ ! -d $directory ]]; then
    die "The $description is not a directory: $directory"
  fi

  if ! owner="$(stat -c '%u' -- "$directory" 2>/dev/null)"; then
    die "Unable to inspect the $description: $directory"
  fi
  if [[ $owner != "$UID" ]]; then
    die "The $description is not owned by this user: $directory"
  fi

  if ! chmod 700 -- "$directory"; then
    die "Unable to restrict permissions on the $description: $directory"
  fi
}

private_file() {
  local file="$1"
  local owner

  [[ -f $file && ! -L $file ]] || return 1
  owner="$(stat -c '%u' -- "$file" 2>/dev/null)" || return 1
  [[ $owner == "$UID" ]] || return 1
  chmod 600 -- "$file" || return 1
}

remove_cache_path() {
  local path="$1"
  local owner

  [[ -e $path || -L $path ]] || return 0
  owner="$(stat -c '%u' -- "$path" 2>/dev/null)" || die "Unable to inspect a cache entry: $path"
  if [[ $owner != "$UID" ]]; then
    die "A cache entry is not owned by this user: $path"
  fi
  rm -f -- "$path" || die "Unable to remove a cache entry: $path"
}

log_excerpt() {
  local log_file="$1"
  [[ -s $log_file ]] || return 0
  tail -c 2000 -- "$log_file" | tr '\0' ' '
}

fail_with_log() {
  local message="$1"
  local log_file="$2"
  local details

  details="$(log_excerpt "$log_file")"
  if [[ -n $details ]]; then
    die "$message\n\nrpgmasd output:\n$details"
  fi
  die "$message"
}

if [[ $# -eq 0 ]]; then
  die "No encrypted RPG Maker image was selected."
fi

case "$cache_root" in
/tmp/*) ;;
*) die "The cache must remain under /tmp: $cache_root" ;;
esac
ensure_private_directory "$cache_root" "cache root"

declare -a selected_files=()
declare -a source_dirs=()
declare -A seen_selected_files=()
declare -A seen_source_dirs=()

for input in "$@"; do
  if [[ ! -f $input ]]; then
    die "Selected image is unavailable: $input"
  fi

  case "${input,,}" in
  *.rpgmvp | *.png_) ;;
  *) die "The selected file is not an encrypted RPG Maker image: $input" ;;
  esac

  canonical_input="$(realpath -e -- "$input")" || die "Unable to resolve selected image: $input"
  source_dir="$(dirname -- "$canonical_input")"

  if [[ ! ${seen_selected_files["$canonical_input"]+yes} ]]; then
    selected_files+=("$canonical_input")
    seen_selected_files["$canonical_input"]=1
  fi
  if [[ ! ${seen_source_dirs["$source_dir"]+yes} ]]; then
    source_dirs+=("$source_dir")
    seen_source_dirs["$source_dir"]=1
  fi
done

declare -A selected_output_by_file=()

process_source_dir() {
  local source_dir="$1"
  local source_hash
  local cache_dir
  local lock_path
  local lock_fd
  local owner
  local candidate
  local candidate_base
  local output_base
  local metadata_base
  local source_signature
  local cached_decoder_identity
  local cached_signature
  local cached_hash
  local -a metadata_lines
  local cache_path
  local metadata_path
  local stage_base
  local stage_output_base
  local staged_hash
  local staged_signature
  local details
  local index=0
  local path_base
  local lock_acquired=false

  source_hash="$(printf '%s' "$source_dir" | sha256sum - | cut -d ' ' -f1)"
  cache_dir="$cache_root/$source_hash"
  ensure_private_directory "$cache_dir" "cache directory"

  lock_path="$cache_root/$source_hash.lock"
  if [[ -L $lock_path ]]; then
    die "The cache lock is a symbolic link and cannot be used: $lock_path"
  fi
  if ! exec {lock_fd}>>"$lock_path"; then
    die "Unable to open the cache lock: $lock_path"
  fi
  if [[ -L $lock_path ]]; then
    die "The cache lock changed into a symbolic link: $lock_path"
  fi
  owner="$(stat -c '%u' -- "$lock_path" 2>/dev/null)" || die "Unable to inspect the cache lock: $lock_path"
  if [[ $owner != "$UID" ]]; then
    die "The cache lock is not owned by this user: $lock_path"
  fi
  chmod 600 -- "$lock_path" || die "Unable to restrict permissions on the cache lock: $lock_path"
  if ! flock -w "$lock_timeout" "$lock_fd"; then
    die "Timed out waiting for another RPG Maker image conversion to finish for:\n$source_dir"
  fi
  lock_acquired=true

  declare -a candidates=()
  while IFS= read -r -d '' candidate; do
    candidates+=("$candidate")
  done < <(
    find -P "$source_dir" -maxdepth 1 -type f \
      \( -iname '*.rpgmvp' -o -iname '*.png_' \) -print0 | sort -z
  )
  if ((${#candidates[@]} == 0)); then
    die "No encrypted RPG Maker images remain in:\n$source_dir"
  fi

  declare -A expected_outputs=()
  declare -A expected_metadata=()
  declare -a missing_sources=()
  declare -a missing_hashes=()
  declare -a missing_signatures=()
  declare -a missing_stage_bases=()
  declare -a missing_stage_output_bases=()
  declare -a missing_output_bases=()

  for candidate in "${candidates[@]}"; do
    candidate_base="$(basename -- "$candidate")"
    output_base="$candidate_base.png"
    metadata_base="$output_base.source-hash"
    expected_outputs["$output_base"]=1
    expected_metadata["$metadata_base"]=1

    source_signature="$(stat -c '%s|%y|%z|%d|%i' -- "$candidate" 2>/dev/null)" || die "Unable to inspect encrypted image: $candidate"
    cache_path="$cache_dir/$output_base"
    metadata_path="$cache_dir/$metadata_base"

    if [[ -f $cache_path && ! -L $cache_path && -f $metadata_path && ! -L $metadata_path ]]; then
      mapfile -t metadata_lines <"$metadata_path"
      cached_decoder_identity="${metadata_lines[0]-}"
      cached_signature="${metadata_lines[1]-}"
      cached_hash="${metadata_lines[2]-}"
      if [[ $cached_decoder_identity == "$RPG_MAKER_DECODER_IDENTITY" && $cached_signature == "$source_signature" && -n $cached_hash ]]; then
        continue
      fi
    fi

    missing_sources+=("$candidate")
    missing_hashes+=("")
    missing_signatures+=("$source_signature")
    missing_output_bases+=("$output_base")
    index=$((index + 1))
    case "${candidate_base,,}" in
    *.rpgmvp) stage_base="image-$index.rpgmvp" ;;
    *.png_) stage_base="image-$index.png_" ;;
    *) die "Unsupported encrypted image in source directory: $candidate" ;;
    esac
    missing_stage_bases+=("$stage_base")
    missing_stage_output_bases+=("${stage_base%.*}.png")
  done

  while IFS= read -r -d '' cache_path; do
    path_base="$(basename -- "$cache_path")"
    if [[ ! ${expected_outputs["$path_base"]+yes} ]]; then
      remove_cache_path "$cache_path"
      remove_cache_path "$cache_path.source-hash"
    fi
  done < <(
    find -P "$cache_dir" -maxdepth 1 \( -type f -o -type l \) -name '*.png' -print0
  )
  while IFS= read -r -d '' cache_path; do
    path_base="$(basename -- "$cache_path")"
    if [[ ! ${expected_metadata["$path_base"]+yes} ]]; then
      remove_cache_path "$cache_path"
    fi
  done < <(
    find -P "$cache_dir" -maxdepth 1 \( -type f -o -type l \) -name '*.source-hash' -print0
  )

  for output_base in "${missing_output_bases[@]}"; do
    remove_cache_path "$cache_dir/$output_base"
    remove_cache_path "$cache_dir/$output_base.source-hash"
  done

  if ((${#missing_sources[@]} > 0)); then
    active_stage_dir="$(mktemp -d --tmpdir="$cache_root" .staging.XXXXXX)" || die "Unable to create private conversion staging"
    chmod 700 -- "$active_stage_dir" || die "Unable to restrict conversion staging permissions"
    mkdir --mode=700 -- "$active_stage_dir/input" "$active_stage_dir/output" "$active_stage_dir/publish" || die "Unable to create conversion staging directories"

    for index in "${!missing_sources[@]}"; do
      stage_base="${missing_stage_bases[$index]}"
      if ! cp -- "${missing_sources[$index]}" "$active_stage_dir/input/$stage_base"; then
        die "Unable to stage encrypted image:\n${missing_sources[$index]}"
      fi
      chmod 600 -- "$active_stage_dir/input/$stage_base" || die "Unable to restrict staged image permissions"
      staged_hash="$(sha256sum -- "$active_stage_dir/input/$stage_base")"
      staged_hash="${staged_hash%% *}"
      missing_hashes[index]="$staged_hash"
      staged_signature="$(stat -c '%s|%y|%z|%d|%i' -- "${missing_sources[$index]}" 2>/dev/null)" || die "Unable to inspect encrypted image: ${missing_sources[$index]}"
      if [[ $staged_signature != "${missing_signatures[$index]}" ]]; then
        die "An encrypted image changed while it was being staged:\n${missing_sources[$index]}"
      fi
    done

    if ! rpgmasd decrypt \
      --input-dir "$active_stage_dir/input" \
      --output-dir "$active_stage_dir/output" \
      >"$active_stage_dir/rpgmasd.log" 2>&1; then
      fail_with_log "Unable to decrypt images from:\n$source_dir" "$active_stage_dir/rpgmasd.log"
    fi

    for index in "${!missing_sources[@]}"; do
      stage_output_base="${missing_stage_output_bases[$index]}"
      cache_path="$active_stage_dir/output/$stage_output_base"
      if [[ ! -f $cache_path || -L $cache_path || ! -s $cache_path ]]; then
        details="$(log_excerpt "$active_stage_dir/rpgmasd.log")"
        if [[ -n $details ]]; then
          die "rpgmasd did not produce an image for:\n${missing_sources[$index]}\n\nrpgmasd output:\n$details"
        fi
        die "rpgmasd did not produce an image for:\n${missing_sources[$index]}"
      fi
      if [[ "$(od -An -tx1 -N8 -- "$cache_path" | tr -d '[:space:]')" != 89504e470d0a1a0a ]]; then
        details="$(log_excerpt "$active_stage_dir/rpgmasd.log")"
        if [[ -n $details ]]; then
          die "rpgmasd produced an invalid PNG for:\n${missing_sources[$index]}\n\nrpgmasd output:\n$details"
        fi
        die "rpgmasd produced an invalid PNG for:\n${missing_sources[$index]}"
      fi

      output_base="${missing_output_bases[$index]}"
      if ! cp -- "$cache_path" "$active_stage_dir/publish/$output_base"; then
        die "Unable to prepare decrypted image publication:\n$source_dir/$output_base"
      fi
      chmod 600 -- "$active_stage_dir/publish/$output_base" || die "Unable to restrict decrypted image permissions"
      metadata_base="$output_base.source-hash"
      if ! printf '%s\n%s\n%s\n' "$RPG_MAKER_DECODER_IDENTITY" "${missing_signatures[$index]}" "${missing_hashes[$index]}" >"$active_stage_dir/publish/$metadata_base"; then
        die "Unable to prepare cache metadata:\n$source_dir/$metadata_base"
      fi
      chmod 600 -- "$active_stage_dir/publish/$metadata_base" || die "Unable to restrict cache metadata permissions"
    done

    declare -a published_paths=()
    for output_base in "${missing_output_bases[@]}"; do
      metadata_base="$output_base.source-hash"
      if ! mv -- "$active_stage_dir/publish/$metadata_base" "$cache_dir/$metadata_base"; then
        for cache_path in "${published_paths[@]}"; do
          rm -f -- "$cache_path"
        done
        die "Unable to publish decrypted image metadata:\n$cache_dir/$metadata_base"
      fi
      published_paths+=("$cache_dir/$metadata_base")
      if ! mv -- "$active_stage_dir/publish/$output_base" "$cache_dir/$output_base"; then
        for cache_path in "${published_paths[@]}"; do
          rm -f -- "$cache_path"
        done
        die "Unable to publish decrypted image:\n$cache_dir/$output_base"
      fi
      published_paths+=("$cache_dir/$output_base")
    done
  fi

  for candidate in "${candidates[@]}"; do
    candidate_base="$(basename -- "$candidate")"
    output_base="$candidate_base.png"
    selected_output_by_file["$candidate"]="$cache_dir/$output_base"
  done

  if [[ -n $active_stage_dir ]]; then
    rm -rf -- "$active_stage_dir"
    active_stage_dir=""
  fi

  if [[ $lock_acquired == true ]]; then
    flock -u "$lock_fd"
    exec {lock_fd}>&-
  fi
}

for source_dir in "${source_dirs[@]}"; do
  process_source_dir "$source_dir"
done

declare -a selected_outputs=()
for selected_file in "${selected_files[@]}"; do
  if [[ -z ${selected_output_by_file["$selected_file"]+yes} ]]; then
    die "Unable to find a decrypted image for:\n$selected_file"
  fi
  selected_outputs+=("${selected_output_by_file["$selected_file"]}")
done

if ((${#selected_outputs[@]} == 0)); then
  die "No encrypted RPG Maker images were selected."
fi

if ! loupe "${selected_outputs[@]}"; then
  die "Loupe could not open the decrypted RPG Maker image."
fi
