#!/usr/bin/env bash

set -euo pipefail

archive_dir="@archiveDir@"
destination_dir="/mnt/nas/backup/forgejo"
archive="${archive_dir}/forgejo-dump.tar.zst"
destination="${destination_dir}/forgejo-dump.tar.zst"
partial_dir="${destination_dir}/.forgejo-rsync-partial"

mkdir -p "$destination_dir"

test -s "$archive"

rsync --partial-dir="$partial_dir" -- "$archive" "$destination"
test -s "$destination"

if ! cmp --silent -- "$archive" "$destination"; then
  printf 'Forgejo backup verification failed; preserving local archive: %s\n' "$archive" >&2
  exit 1
fi

rm -- "$archive"
printf 'Forgejo backup exported and local archive removed: %s\n' "$destination"
