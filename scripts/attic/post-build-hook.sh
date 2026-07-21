#!/usr/bin/env bash
set -eu

queue_dir="@queueDir@"

if [ -z "${OUT_PATHS:-}" ]; then
  exit 0
fi

mkdir -p "$queue_dir"
queue_file="$(mktemp "$queue_dir/.pending.XXXXXX")"
printf '%s\n' "${OUT_PATHS}" >"$queue_file"
mv "$queue_file" "${queue_file}.paths"

exit 0
