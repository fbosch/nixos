#!/usr/bin/env bash

set -euo pipefail

archive_dir="@archiveDir@"
destination_dir="/mnt/nas/backup/forgejo"
archive="${archive_dir}/forgejo-dump.tar.zst"
destination="${destination_dir}/forgejo-dump.tar.zst"

mkdir -p "$destination_dir"

test -s "$archive"

partial_destination="$(mktemp "${destination_dir}/.forgejo-dump.XXXXXX.partial")"
cp -- "$archive" "$partial_destination"
test -s "$partial_destination"
mv -f "$partial_destination" "$destination"
