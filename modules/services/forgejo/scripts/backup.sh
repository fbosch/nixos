#!/usr/bin/env bash

set -euo pipefail

archive_dir="@archiveDir@"
work_dir="$(runuser -u forgejo -- mktemp -d)"
archive="${archive_dir}/forgejo-dump.tar.zst"
partial_archive="${archive}.partial"
forgejo_stopped=false

restore_forgejo() {
  rm -rf "$work_dir"

  if [ "$forgejo_stopped" = true ]; then
    systemctl start forgejo.service
  fi
}
trap restore_forgejo EXIT

systemctl stop forgejo.service
forgejo_stopped=true

runuser -u forgejo -- @forgejo@ dump \
  --work-path /var/lib/forgejo \
  --custom-path /var/lib/forgejo/custom \
  --type tar.zst \
  --file "$partial_archive" \
  --quiet \
  --tempdir "$work_dir"

test -s "$partial_archive"
mv "$partial_archive" "$archive"

printf 'Forgejo backup complete: %s\n' "$archive"
