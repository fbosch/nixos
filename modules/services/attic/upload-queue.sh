#!/usr/bin/env bash
set -eu
shopt -s nullglob

attic_cli="@atticClient@/bin/attic"
token_file="@tokenFile@"
cache_name="@cacheName@"
endpoint="@endpoint@"
queue_directory="@queueDirectory@"

if [ ! -r "$token_file" ]; then
  echo "attic upload queue: token file missing or unreadable" >&2
  exit 1
fi

"$attic_cli" login --set-default rvn "$endpoint" "$(cat "$token_file")" >/dev/null

for uploading_file in "$queue_directory"/*.uploading; do
  mv "$uploading_file" "${uploading_file%.uploading}.paths"
done

for queue_file in "$queue_directory"/*.paths; do
  uploading_file="${queue_file%.paths}.uploading"
  mv "$queue_file" "$uploading_file"

  if "$attic_cli" push "$cache_name" --stdin <"$uploading_file"; then
    rm "$uploading_file"
  else
    mv "$uploading_file" "$queue_file"
    exit 1
  fi
done
