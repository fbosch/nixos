#!/usr/bin/env bash
set -u

queue_directory="@queueDirectory@"

if [ -z "${OUT_PATHS:-}" ]; then
  exit 0
fi

mkdir -p -m 0700 "$queue_directory"
queue_file="$(mktemp "$queue_directory/.pending.XXXXXX")"
IFS=' ' read -r -a out_paths <<<"${OUT_PATHS}"
printf '%s\n' "${out_paths[@]}" >"$queue_file"
mv "$queue_file" "$queue_directory/${queue_file##*.pending.}.paths"

exit 0
